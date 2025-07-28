import 'dart:async';
import 'package:opentool_dart/opentool_dart.dart';

import '../../../llm/model.dart';
import 'prompt.dart';
import '../../session_agent/model.dart';
import '../../session_agent/session.dart';
import '../../../util/unique_id_generator.dart';
import '../models/node.dart';
import '../../model.dart';
import '../wrappers/tool_agent.dart';
import '../auto_multi_agent.dart';

class AutoSummarizer {

  final LLMConfig summarizerLLMConfig;

  final AutoMessageSender messageSender;

  AutoSummarizer({
    required this.summarizerLLMConfig,
    required this.messageSender,
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

      messageSender.sendAgentMessage(message);

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

    String systemPrompt = SummaryPrompt.getSystemPrompt(
      userCommand: userCommand,
      completedNodes: completedNodes,
    );

    final summarizerAgent = AutoToolAgent(
      sessionId: tempSessionId,
      llmConfig: summarizerLLMConfig,
      agentSession: tempSession,
      systemPrompt: systemPrompt
    );

    final summarizerFunctionCall = FunctionCall(id: uniqueId(), name: 'summarizer', arguments: {});

    try {
      await messageSender.sendFunctionCallStart(taskId, summarizerFunctionCall);

      await summarizerAgent.userToAgent(
        contentList: [Content(type: ContentType.TEXT, message: "generate summary")],
        parentTaskId: taskId,
      );

      final resultContent = await completer.future;

      String cleanedResult = _cleanSummaryResult(resultContent);

      await messageSender.sendFunctionCallDone(taskId, summarizerFunctionCall, cleanedResult);

      return cleanedResult;

    } catch (e) {
      await messageSender.sendFunctionCallDone(taskId, summarizerFunctionCall, "summary generation failed: $e");
      rethrow;
    } finally {
      // clean up temporary session resources
      tempSession.resetListener();
      tempSession.clearMessage();
    }
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