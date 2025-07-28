import 'dart:async';
import '../../../llm/model.dart';
import 'prompt.dart';
import '../models/node.dart';
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

    String systemPrompt = SummaryPrompt.getSystemPrompt(
      userCommand: userCommand,
      completedNodes: completedNodes,
    );

    try {
      final resultContent = await AutoToolAgent.executeWithTracking(
        functionName: 'summarizer',
        userInput: "generate summary",
        taskId: taskId,
        messageSender: messageSender,
        llmConfig: summarizerLLMConfig,
        systemPrompt: systemPrompt,
        parentTaskId: taskId,
      );

      String cleanedResult = _cleanSummaryResult(resultContent);
      return cleanedResult;

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
}

class AutoSummaryException implements Exception {
  final String message;
  
  AutoSummaryException(this.message);
  
  @override
  String toString() => 'AutoSummaryException: $message';
} 