import 'dart:async';
import '../../../llm/model.dart';
import 'prompt.dart';
import '../wrappers/function.dart';
import '../wrappers/llm.dart';
import '../wrappers/tool_agent.dart';
import '../auto_multi_agent.dart';
import '../../session_agent/session.dart';
import '../../../utils/unique_id_generator.dart';

class AutoTaskPlanner {

  final LLMConfig plannerLLMConfig;

  final AutoMessageSender messageSender;

  AutoToolAgent? plannerAgent;

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

    final sessionId = uniqueId();
    final agentSession = AgentSession(sessionId: sessionId);
    final planningPrompt = PlanningPrompt.getSystemPrompt(
      availableModels: indexedLLMConfigs,
      indexedFunctions: indexedFunctions,
    );

    plannerAgent = AutoToolAgent(
      sessionId: sessionId,
      agentSession: agentSession,
      llmConfig: plannerLLMConfig,
      systemPrompt: planningPrompt,
    );

    try {
      return await plannerAgent!.execute(
        userInput: userCommand,
        originalTaskId: taskId,
        parentTaskId: taskId,
        functionName: 'planner',
        messageSender: messageSender,
      );
    } catch (e) {
      throw AutoPlanningException('task planning failed: $e');
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

  void stop() {
    plannerAgent?.stop();
  }

  void clear() {
    plannerAgent?.clear();
  }
}

class AutoPlanningException implements Exception {
  final String message;
  
  AutoPlanningException(this.message);
  
  @override
  String toString() => 'AutoPlanningException: $message';
} 