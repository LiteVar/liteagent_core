import 'dart:async';
import '../../../llm/model.dart';
import 'prompt.dart';
import '../models/node.dart';
import '../wrappers/tool_agent.dart';
import '../auto_multi_agent.dart';
import '../../../util/unique_id_generator.dart';
import '../../session_agent/session.dart';

class AutoSummarizer {

  final LLMConfig summarizerLLMConfig;

  final AutoMessageSender messageSender;

  AutoToolAgent? summarizerAgent;

  AutoSummarizer({
    required this.summarizerLLMConfig,
    required this.messageSender,
  });

  Future<String> generateSummary({
    required String userCommand,
    required List<AutoTaskNode> completedNodes,
    required String taskId,
  }) async {

    final sessionId = uniqueId();
    final agentSession = AgentSession(sessionId: sessionId);
    final systemPrompt = SummaryPrompt.getSystemPrompt(
      userCommand: userCommand,
      completedNodes: completedNodes,
    );

    summarizerAgent = AutoToolAgent(
      sessionId: sessionId,
      agentSession: agentSession,
      llmConfig: summarizerLLMConfig,
      systemPrompt: systemPrompt,
    );

    try {
      final resultContent = await summarizerAgent!.execute(
        userInput: "generate summary",
        originalTaskId: taskId,
        parentTaskId: taskId,
        functionName: 'summarizer',
        messageSender: messageSender,
      );

      return _cleanSummaryResult(resultContent);
    } catch (e) {
      throw AutoSummaryException('summary generation failed: $e');
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

  void stop() {
    summarizerAgent?.stop();
  }

  void clear() {
    summarizerAgent?.clear();
  }
}

class AutoSummaryException implements Exception {
  final String message;
  
  AutoSummaryException(this.message);
  
  @override
  String toString() => 'AutoSummaryException: $message';
} 