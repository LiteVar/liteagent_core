import 'dart:async';
import 'dart:convert';
import 'package:opentool_dart/opentool_dart.dart';

import '../../../llm/model.dart';
import 'template.dart';
import '../../tool_agent/tool_agent.dart';
import '../../session_agent/model.dart';
import '../../session_agent/session.dart';
import '../../../util/unique_id_generator.dart';
import '../models/node.dart';
import '../../session_agent/session_agent.dart';
import '../../multi_agent/model.dart';
import '../../tool_agent/model.dart';
import '../../model.dart';

class AutoSummarizer {

  final LLMConfig summarizerLLMConfig;

  final SessionAgent mainAgent;

  AutoSummarizer({
    required this.summarizerLLMConfig,
    required this.mainAgent,
  });

  Future<String> generateSummary({
    required String userCommand,
    required List<AutoTaskNode> completedNodes,
    required String taskId,
  }) async {

    String tempSessionId = uniqueId();
    final tempSession = AgentSession(sessionId: tempSessionId);

    String summaryResult = '';
    final completer = Completer<String>();

    tempSession.addAgentMessageListener((message) {

      mainAgent.agentSession.addListenAgentMessage(message);

      if (message.type == SessionMessageType.TEXT &&
          message.role == SessionRoleType.AGENT &&
          message.to == SessionRoleType.USER &&
          message.content is String) {
        summaryResult += message.content as String;
      }

      if (message.type == SessionMessageType.TASK_STATUS) {
        final taskStatus = message.content as TaskStatus;
        if (taskStatus.status == TaskStatusType.DONE || 
            taskStatus.status == TaskStatusType.STOP || 
            taskStatus.status == TaskStatusType.EXCEPTION) {
          if (!completer.isCompleted) {
            completer.complete(summaryResult);
          }
        }
      }
    });

    String systemPrompt = AutoSummaryTemplate.getSummaryTemplate();
    systemPrompt += _buildSummaryRequest(userCommand, completedNodes);

    final summarizerAgent = ToolAgent(
      sessionId: tempSessionId,
      toolDriverList: const <ToolDriver>[],
      llmConfig: summarizerLLMConfig,
      agentSession: tempSession,
      systemPrompt: systemPrompt,
    );

    final summarizerFunctionCall = FunctionCall(id: uniqueId(), name: 'summarizer', arguments: {});

    try {
      sendStartMessage(taskId, summarizerFunctionCall);

      await summarizerAgent.userToAgent(
        contentList: [Content(type: ContentType.TEXT, message: "generate summary")],
        parentTaskId: taskId,
      );

      final resultContent = await completer.future;

      String cleanedResult = _cleanSummaryResult(resultContent);

      sendDoneMessage(taskId, summarizerFunctionCall, cleanedResult);

      return cleanedResult;

    } catch (e) {
      sendDoneMessage(taskId, summarizerFunctionCall, "summary generation failed: $e");
      rethrow;
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

  /// build summary request content
  String _buildSummaryRequest(String userCommand, List<AutoTaskNode> completedNodes) {
    return """
用户原始需求：
$userCommand

${AutoSummaryTemplate.formatExecutionDetails(completedNodes)}

请基于以上信息生成执行总结。
""";
  }

  /// clean up the extra content in the summary result
  String _cleanSummaryResult(String result) {
    String cleaned = result.trim();
    
    if (cleaned.startsWith('```')) {
      int firstNewline = cleaned.indexOf('\n');
      if (firstNewline != -1) {
        cleaned = cleaned.substring(firstNewline + 1);
      }
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    
    return cleaned.trim();
  }
}

class AutoSummaryException implements Exception {
  final String message;
  
  AutoSummaryException(this.message);
  
  @override
  String toString() => 'AutoSummaryException: $message';
} 