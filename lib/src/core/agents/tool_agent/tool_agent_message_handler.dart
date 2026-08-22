import '../model.dart';
import '../session_agent/agent_message_handler.dart';
import '../session_agent/dispatcher.dart';
import 'model.dart';

class LLMFunctionCallingMessageHandler extends AgentMessageHandler {
  final Future<void> Function(AgentMessage) toUser;
  final Future<void> Function(AgentMessage) toTool;

  LLMFunctionCallingMessageHandler(this.toUser, this.toTool);

  @override
  Command? handle(AgentMessage agentMessage) {
    if (agentMessage.type == ToolMessageType.TOOL_CALLS) {
      final AgentMessage agentToolMessage = AgentMessage(
        sessionId: agentMessage.sessionId,
        originalTaskId: agentMessage.originalTaskId,
        parentTaskId: agentMessage.parentTaskId,
        taskId: agentMessage.taskId,
        role: ToolRoleType.AGENT,
        to: ToolRoleType.TOOL,
        type: ToolMessageType.TOOL_CALLS,
        content: agentMessage.content,
      );
      return Command(toTool, agentToolMessage);
    }

    if (agentMessage.type == ToolMessageType.TEXT ||
        agentMessage.type == ToolMessageType.IMAGE_URL) {
      final AgentMessage agentUserMessage = AgentMessage(
        sessionId: agentMessage.sessionId,
        originalTaskId: agentMessage.originalTaskId,
        parentTaskId: agentMessage.parentTaskId,
        taskId: agentMessage.taskId,
        role: ToolRoleType.AGENT,
        to: ToolRoleType.USER,
        type: agentMessage.type,
        content: agentMessage.content,
      );
      return Command(toUser, agentUserMessage);
    }

    return null;
  }
}

class ToolMessageHandler extends AgentMessageHandler {
  final Future<void> Function(AgentMessage) toLLM;
  final void Function(AgentMessage)? onToolReturn;

  ToolMessageHandler(this.toLLM, {this.onToolReturn});

  @override
  Command? handle(AgentMessage agentMessage) {
    if (agentMessage.type == ToolMessageType.TOOL_RETURN) {
      final AgentMessage agentLLMMessage = AgentMessage(
        sessionId: agentMessage.sessionId,
        originalTaskId: agentMessage.originalTaskId,
        parentTaskId: agentMessage.parentTaskId,
        taskId: agentMessage.taskId,
        role: ToolRoleType.AGENT,
        to: ToolRoleType.ASSISTANT,
        type: ToolMessageType.TOOL_RETURN,
        content: agentMessage.content,
      );
      if (onToolReturn != null) onToolReturn!(agentLLMMessage);
    } else if (agentMessage.type == ToolMessageType.TASK_STATUS) {
      final TaskStatus taskStatus = agentMessage.content as TaskStatus;
      if (taskStatus.status == ToolStatusType.DONE) {
        final AgentMessage agentToolMessage = AgentMessage(
          sessionId: agentMessage.sessionId,
          originalTaskId: agentMessage.originalTaskId,
          parentTaskId: agentMessage.parentTaskId,
          taskId: agentMessage.taskId,
          role: ToolRoleType.AGENT,
          to: ToolRoleType.CLIENT,
          type: ToolMessageType.TASK_STATUS,
          content: agentMessage.content,
        );
        return Command(toLLM, agentToolMessage);
      }
    }
    return null;
  }
}
