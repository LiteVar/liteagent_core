import '../model.dart';

/// The completed context required to restore an evicted [AgentSession].
///
/// [contextMessages] must be supplied in their original order and contain only
/// context from completed tasks. Incomplete tool calls, streaming chunks, and
/// tasks waiting for callbacks must not be restored. For tool-agent context,
/// assistant tool calls and tool returns must be complete and correctly paired.
///
/// The persistence layer is responsible for deciding whether a stored session
/// has been deleted or has expired. Core only restores the supplied context.
class SessionRestoreState {
  final String sessionId;

  /// Completed context messages used to assemble the next LLM request.
  final List<AgentMessage> contextMessages;

  const SessionRestoreState({
    required this.sessionId,
    required this.contextMessages,
  });
}
