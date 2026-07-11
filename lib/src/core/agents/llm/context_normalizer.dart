import '../model.dart';
import 'model.dart';

/// Normalizes completed agent history before it is sent to an LLM.
///
/// Standalone reasoning messages are observable history, not chat messages.
/// They are therefore omitted from the returned list. When reasoning belongs
/// to an assistant tool-call response, it is copied onto that tool-call
/// message so providers that require `reasoning_content` replay can receive it
/// without injecting reasoning as a separate conversation turn.
List<AgentMessage> normalizeReasoningContext(List<AgentMessage> messages) {
  final normalized = <AgentMessage>[];
  final pendingReasoning = <_GenerationKey, StringBuffer>{};

  for (final message in messages) {
    final key = _GenerationKey.fromMessage(message);

    if (message.role == AgentRoleType.LLM &&
        message.type == AgentMessageType.REASONING) {
      final reasoning = message.content;
      if (reasoning is String && reasoning.isNotEmpty) {
        pendingReasoning.putIfAbsent(key, StringBuffer.new).write(reasoning);
      }
      continue;
    }

    if (message.role == AgentRoleType.LLM &&
        message.type == AgentMessageType.TOOL_CALLS) {
      final reasoning = pendingReasoning.remove(key)?.toString();
      if ((message.reasoningContent == null ||
              message.reasoningContent!.isEmpty) &&
          reasoning != null &&
          reasoning.isNotEmpty) {
        normalized.add(_copyWithReasoningContent(message, reasoning));
      } else {
        normalized.add(message);
      }
      continue;
    }

    // A final assistant response closes the generation. Its reasoning is not
    // carried into a later tool call that happens to reuse the same task id.
    if (message.role == AgentRoleType.LLM &&
        message.type == AgentMessageType.TEXT) {
      pendingReasoning.remove(key);
    }

    normalized.add(message);
  }

  return normalized;
}

AgentMessage _copyWithReasoningContent(
  AgentMessage message,
  String reasoningContent,
) {
  return AgentMessage(
    sessionId: message.sessionId,
    agentId: message.agentId,
    originalTaskId: message.originalTaskId,
    parentTaskId: message.parentTaskId,
    taskId: message.taskId,
    role: message.role,
    to: message.to,
    type: message.type,
    content: message.content,
    reasoningContent: reasoningContent,
    completions: message.completions,
  );
}

class _GenerationKey {
  const _GenerationKey({
    required this.sessionId,
    required this.originalTaskId,
    required this.parentTaskId,
    required this.taskId,
  });

  factory _GenerationKey.fromMessage(AgentMessage message) => _GenerationKey(
        sessionId: message.sessionId,
        originalTaskId: message.originalTaskId,
        parentTaskId: message.parentTaskId,
        taskId: message.taskId,
      );

  final String sessionId;
  final String originalTaskId;
  final String? parentTaskId;
  final String taskId;

  @override
  bool operator ==(Object other) {
    return other is _GenerationKey &&
        sessionId == other.sessionId &&
        originalTaskId == other.originalTaskId &&
        parentTaskId == other.parentTaskId &&
        taskId == other.taskId;
  }

  @override
  int get hashCode => Object.hash(
        sessionId,
        originalTaskId,
        parentTaskId,
        taskId,
      );
}
