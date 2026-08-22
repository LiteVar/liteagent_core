import '../model.dart';
import '../session_agent/agent_message_handler.dart';
import '../session_agent/dispatcher.dart';
import '../session_agent/model.dart';
import 'model.dart';

class UserMessageHandler extends AgentMessageHandler {
  final Future<void> Function(AgentMessage) toLLM;

  UserMessageHandler(this.toLLM);

  @override
  Command? handle(AgentMessage agentMessage) {
    final List<Content> userContentList = agentMessage.content as List<Content>;
    final AgentMessage newAgentMessage = AgentMessage(
      sessionId: agentMessage.sessionId,
      originalTaskId: agentMessage.originalTaskId,
      parentTaskId: agentMessage.parentTaskId,
      taskId: agentMessage.taskId,
      role: TextRoleType.AGENT,
      to: TextRoleType.ASSISTANT,
      type: TextMessageType.CONTENT_LIST,
      content: userContentList,
    );
    return Command(toLLM, newAgentMessage);
  }
}

class LLMMessageHandler extends AgentMessageHandler {
  final Future<void> Function(AgentMessage) toUser;
  String chunkAccumulation = "";

  LLMMessageHandler(this.toUser);

  @override
  Command? handle(AgentMessage agentMessage) {
    if (agentMessage.type == TextMessageType.TEXT ||
        agentMessage.type == TextMessageType.IMAGE_URL) {
      final AgentMessage agentUserMessage = AgentMessage(
        sessionId: agentMessage.sessionId,
        originalTaskId: agentMessage.originalTaskId,
        parentTaskId: agentMessage.parentTaskId,
        taskId: agentMessage.taskId,
        role: TextRoleType.AGENT,
        to: TextRoleType.USER,
        type: agentMessage.type,
        content: agentMessage.content,
        completions: agentMessage.completions,
      );
      return Command(toUser, agentUserMessage);
    }

    if (agentMessage.type == TextMessageType.TASK_STATUS &&
        agentMessage.content == TextStatusType.CHUNK_DONE) {
      final AgentMessage agentUserMessage = AgentMessage(
        sessionId: agentMessage.sessionId,
        originalTaskId: agentMessage.originalTaskId,
        parentTaskId: agentMessage.parentTaskId,
        taskId: agentMessage.taskId,
        role: TextRoleType.AGENT,
        to: TextRoleType.USER,
        type: TextMessageType.TEXT,
        content: chunkAccumulation,
        completions: agentMessage.completions,
      );
      return Command(toUser, agentUserMessage);
    }

    return null;
  }
}
