import 'dart:async';
import 'package:opentool_dart/opentool_dart.dart';
import '../../../llm/model.dart';
import 'prompt.dart';
import '../../session_agent/model.dart';
import '../../session_agent/session.dart';
import '../../../util/unique_id_generator.dart';
import '../wrappers/function.dart';
import '../wrappers/llm.dart';
import '../../model.dart';
import '../wrappers/tool_agent.dart';
import '../auto_multi_agent.dart';

class AutoTaskPlanner {

  final LLMConfig plannerLLMConfig;

  final AutoMessageSender messageSender;

  AutoTaskPlanner({
    required this.plannerLLMConfig,
    required this.messageSender,
  });

  Future<String> planTasks({
    required String userCommand,
    required List<IndexedLLMConfig> indexedLLMConfigs,
    required List<IndexedFunction> indexedFunctions,
    required String taskId,
  }) async {

    final planningPrompt = PlanningPrompt.getSystemPrompt(
      availableModels: indexedLLMConfigs,
      indexedFunctions: indexedFunctions,
    );

    String tempSessionId = uniqueId();
    final tempSession = AgentSession(sessionId: tempSessionId);

    String planningResult = '';
    final completer = Completer<String>();

    tempSession.addAgentMessageListener((message) {

      messageSender.sendAgentMessage(message);

      if (message.type == SessionMessageType.TEXT &&
          message.role == SessionRoleType.AGENT &&
          message.to == SessionRoleType.USER &&
          message.content is String) {
        planningResult += message.content as String;
      }

      if (message.type == SessionMessageType.TASK_STATUS) {
        final taskStatus = message.content as TaskStatus;
        if (taskStatus.status == TaskStatusType.DONE || 
            taskStatus.status == TaskStatusType.STOP || 
            taskStatus.status == TaskStatusType.EXCEPTION) {
          if (!completer.isCompleted) {
            completer.complete(planningResult);
          }
        }
      }
    });

    final plannerAgent = AutoToolAgent(
      sessionId: tempSessionId, 
      llmConfig: plannerLLMConfig,
      agentSession: tempSession,
      systemPrompt: planningPrompt,
    );

    final plannerFunctionCall = FunctionCall(id: uniqueId(), name: 'planner', arguments: {});

    try {
      await messageSender.sendFunctionCallStart(taskId, plannerFunctionCall);

      await plannerAgent.userToAgent(
        contentList: [Content(type: ContentType.TEXT, message: userCommand)],
        parentTaskId: taskId,
      );

      final resultContent = await completer.future;

      await messageSender.sendFunctionCallDone(taskId, plannerFunctionCall, resultContent);

      return resultContent;

    } catch (e) {
      await messageSender.sendFunctionCallDone(taskId, plannerFunctionCall, "task planning failed: $e");
      throw AutoPlanningException('task planning failed: $e');
    } finally {
      // clean up temporary session resources
      tempSession.resetListener();
      tempSession.clearMessage();
    }
  }

  bool validatePlanningResult(String result) {
    try {
      final decoded = result.trim();
      if (!decoded.startsWith('[') || !decoded.endsWith(']')) {
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// clean up the extra content in the planning result
  String cleanPlanningResult(String result) {
    String cleaned = result.trim();
    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7);
    }
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    
    int startIndex = cleaned.indexOf('[');
    int endIndex = cleaned.lastIndexOf(']');
    
    if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
      cleaned = cleaned.substring(startIndex, endIndex + 1);
    }
    
    return cleaned.trim();
  }
}

class AutoPlanningException implements Exception {
  final String message;
  
  AutoPlanningException(this.message);
  
  @override
  String toString() => 'AutoPlanningException: $message';
} 