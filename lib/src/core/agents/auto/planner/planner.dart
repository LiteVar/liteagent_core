import 'dart:async';
import 'dart:convert';
import 'package:opentool_dart/opentool_dart.dart';
import '../../../llm/model.dart';
import 'template.dart';
import '../../tool_agent/tool_agent.dart';
import '../../session_agent/model.dart';
import '../../session_agent/session.dart';
import '../../../util/unique_id_generator.dart';
import '../models/function.dart';
import '../models/node.dart';
import '../models/llm.dart';
import '../../session_agent/session_agent.dart';
import '../../multi_agent/model.dart';
import '../../tool_agent/model.dart';
import '../../model.dart';

class AutoTaskPlanner {

  final LLMConfig plannerLLMConfig;

  final SessionAgent mainAgent;

  AutoTaskPlanner({
    required this.plannerLLMConfig,
    required this.mainAgent,
  });

  Future<String> planTasks({
    required String userCommand,
    required List<IndexedLLMConfig> indexedLLMConfigs,
    required List<IndexedFunction> indexedFunctions,
    required String taskId,
  }) async {

    final planningPrompt = AutoPlanningTemplate.getTaskPlanningTemplate(
      availableModels: indexedLLMConfigs,
      indexedFunctions: indexedFunctions,
    );

    String tempSessionId = uniqueId();
    final tempSession = AgentSession(sessionId: tempSessionId);

    String planningResult = '';
    final completer = Completer<String>();

    tempSession.addAgentMessageListener((message) {

      mainAgent.agentSession.addListenAgentMessage(message);

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

    final plannerAgent = ToolAgent(
      sessionId: tempSessionId,
      toolDriverList: const <ToolDriver>[],
      llmConfig: plannerLLMConfig,
      agentSession: tempSession,
      systemPrompt: planningPrompt,
    );

    final plannerFunctionCall = FunctionCall(id: uniqueId(), name: 'planner', arguments: {});

    try {
      sendStartMessage(taskId, plannerFunctionCall);

      await plannerAgent.userToAgent(
        contentList: [Content(type: ContentType.TEXT, message: userCommand)],
        parentTaskId: taskId,
      );

      final resultContent = await completer.future;

      sendDoneMessage(taskId, plannerFunctionCall, resultContent);

      return resultContent;

    } catch (e) {
      sendDoneMessage(taskId, plannerFunctionCall, "task planning failed: $e");
      throw AutoPlanningException('task planning failed: $e');
    } finally {
      // clean up temporary session resources
      tempSession.resetListener();
      tempSession.clearMessage();
    }
  }

  Future<void> sendStartMessage(String taskId, FunctionCall functionCall) async {
      AgentMessage subAgentMessage = AgentMessage(
        sessionId: mainAgent.sessionId,
        parentTaskId: mainAgent.parentTaskId,
        taskId: taskId,
        role: MultiAgentRoleType.AGENT,
        to: MultiAgentRoleType.SUBAGENT,
        type: MultiAgentMessageType.TOOL_CALLS,
        content: [functionCall]
      );
      mainAgent.agentSession.addListenAgentMessage(subAgentMessage);

      AgentMessage clientMessage = AgentMessage(
        sessionId: mainAgent.sessionId,
        parentTaskId: mainAgent.parentTaskId,
        taskId: taskId,
        role: MultiAgentRoleType.AGENT,
        to: MultiAgentRoleType.CLIENT,
        type: MultiAgentMessageType.TASK_STATUS,
        content: TaskStatus(status:MultiAgentStatusType.START, taskId: taskId, description: ToolStatusDescription(functionCallIdList: [functionCall.id]).toJson())
      );
      mainAgent.agentSession.addListenAgentMessage(clientMessage);
  }

  Future<void> sendDoneMessage(String taskId, FunctionCall functionCall, String finalResult) async {
      AgentMessage subAgentReturnMessage = AgentMessage(
        sessionId: mainAgent.sessionId,
        parentTaskId: mainAgent.parentTaskId,
        taskId: taskId,
        role: MultiAgentRoleType.SUBAGENT,
        to: MultiAgentRoleType.AGENT,
        type: MultiAgentMessageType.TOOL_RETURN,
        content: ToolReturn(id: functionCall.id, result: {"result": finalResult})
      );
      mainAgent.agentSession.addListenAgentMessage(subAgentReturnMessage);

      AgentMessage subAgentStatusMessage = AgentMessage(
        sessionId: mainAgent.sessionId,
        parentTaskId: mainAgent.parentTaskId,
        taskId: taskId,
        role: MultiAgentRoleType.SUBAGENT,
        to: MultiAgentRoleType.AGENT,
        type: MultiAgentMessageType.TASK_STATUS,
        content: TaskStatus(status:MultiAgentStatusType.DONE, taskId: taskId, description: ToolStatusDescription(functionCallIdList: [functionCall.id]).toJson())
      );
      mainAgent.agentSession.addListenAgentMessage(subAgentStatusMessage);
  }
}

class AutoPlanningException implements Exception {
  final String message;
  
  AutoPlanningException(this.message);
  
  @override
  String toString() => 'AutoPlanningException: $message';
} 