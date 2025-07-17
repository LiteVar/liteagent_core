import 'dart:convert';
import 'package:opentool_dart/opentool_dart.dart';
import '../model.dart';
import '../reflection/reflector_manager.dart';
import '../session_agent/agent_message_handler.dart';
import '../session_agent/dispatcher.dart';
import '../session_agent/model.dart';
import '../text_agent/model.dart';
import '../tool_agent/model.dart';
import 'model.dart';

class MultiAgentFunctionCallingMessageHandler extends AgentMessageHandler {
  final ReflectorManager reflectionManager;
  final Future<void> Function(AgentMessage) toReflection;
  final Future<void> Function(AgentMessage) toUser;
  final void Function(AgentMessage) partitionFunctionCallMessage;

  MultiAgentFunctionCallingMessageHandler(this.reflectionManager, this.toReflection, this.toUser, this.partitionFunctionCallMessage);

  @override
  Command? handle(AgentMessage agentMessage) {
    if (agentMessage.type == MultiAgentMessageType.TOOL_CALLS) {
      List<FunctionCall> functionCallList = agentMessage.content as List<FunctionCall>;
      if(reflectionManager.shouldReflect) {
        AgentMessage reflectionMessage = AgentMessage(
          sessionId: agentMessage.sessionId,
          parentTaskId: agentMessage.parentTaskId,
          taskId: agentMessage.taskId,
          role: MultiAgentRoleType.AGENT,
          to: MultiAgentRoleType.REFLECTION,
          type: MultiAgentMessageType.TOOL_CALLS,
          content: functionCallList
        );
        return Command(toReflection, reflectionMessage); // If LLM return function call, and should reflect, forward to REFLECTION.
      } else {
        partitionFunctionCallMessage(agentMessage);
      }
    } else if (agentMessage.type == MultiAgentMessageType.TEXT || agentMessage.type == MultiAgentMessageType.IMAGE_URL) {
      AgentMessage agentUserMessage = AgentMessage(
        sessionId: agentMessage.sessionId,
        parentTaskId: agentMessage.parentTaskId,
        taskId: agentMessage.taskId,
        role: MultiAgentRoleType.AGENT,
        to: MultiAgentRoleType.USER,
        type: agentMessage.type,
        content: agentMessage.content);
      return Command(toUser, agentUserMessage); // If LLM return image, forward to USER.
    }
    return null;
  }
}

class SubAgentMessageHandler extends AgentMessageHandler {
  final void Function(String, AgentMessage) onFunctionCallResult;

  SubAgentMessageHandler(this.onFunctionCallResult);

  @override
  Command? handle(AgentMessage agentMessage) {
    if (agentMessage.type == MultiAgentMessageType.TOOL_RETURN) {
      AgentMessage subAgentResultMessage = AgentMessage(
        sessionId: agentMessage.sessionId,
        parentTaskId: agentMessage.parentTaskId,
        taskId: agentMessage.taskId,
        role: MultiAgentRoleType.AGENT,
        to: MultiAgentRoleType.ASSISTANT,
        type: MultiAgentMessageType.TOOL_RETURN,
        content: agentMessage.content
      );
      onFunctionCallResult(MultiAgentRoleType.SUBAGENT, subAgentResultMessage);
    } else if (agentMessage.type == MultiAgentMessageType.TASK_STATUS) {
      TaskStatus taskStatus = agentMessage.content as TaskStatus;
      if (taskStatus.status == MultiAgentStatusType.DONE) {
        AgentMessage subAgentStatusMessage = AgentMessage(
          sessionId: agentMessage.sessionId,
          parentTaskId: agentMessage.parentTaskId,
          taskId: agentMessage.taskId,
          role: MultiAgentRoleType.AGENT,
          to: MultiAgentRoleType.CLIENT,
          type: MultiAgentMessageType.TASK_STATUS,
          content: agentMessage.content
        );
        onFunctionCallResult(MultiAgentRoleType.SUBAGENT, subAgentStatusMessage);
      }
    }
    return null;
  }
}

class MultiAgentToolMessageHandler extends AgentMessageHandler {
  final void Function(String, AgentMessage) onFunctionCallResult;

  MultiAgentToolMessageHandler(this.onFunctionCallResult);

  @override
  Command? handle(AgentMessage agentMessage) {
    if (agentMessage.type == MultiAgentMessageType.TOOL_RETURN) {
      AgentMessage toolResultMessage = AgentMessage(
        sessionId: agentMessage.sessionId,
        parentTaskId: agentMessage.parentTaskId,
        taskId: agentMessage.taskId,
        role: MultiAgentRoleType.AGENT,
        to: MultiAgentRoleType.ASSISTANT,
        type: MultiAgentMessageType.TOOL_RETURN,
        content: agentMessage.content
      );
      onFunctionCallResult(MultiAgentRoleType.TOOL, toolResultMessage);
    } else if (agentMessage.type == MultiAgentMessageType.TASK_STATUS) {
      TaskStatus taskStatus = agentMessage.content as TaskStatus;
      if (taskStatus.status == ToolStatusType.DONE) {
        AgentMessage toolStatusMessage = AgentMessage(
          sessionId: agentMessage.sessionId,
          parentTaskId: agentMessage.parentTaskId,
          taskId: agentMessage.taskId,
          role: MultiAgentRoleType.AGENT,
          to: MultiAgentRoleType.CLIENT,
          type: MultiAgentMessageType.TASK_STATUS,
          content: agentMessage.content
        );
        onFunctionCallResult(MultiAgentRoleType.TOOL, toolStatusMessage);
      }
    }
    return null;
  }
}

class MultiAgentReflectionMessageHandler extends AgentMessageHandler {

  final ReflectorManager toolReflectionManager;
  final void Function(AgentMessage) partitionFunctionCallMessage;
  final Future<void> Function(AgentMessage) toLLM;
  // final Future<void> Function(AgentMessage) toTool;
  final Function(AgentMessage)? onToolRetry;

  MultiAgentReflectionMessageHandler(this.toolReflectionManager, this.toLLM, this.partitionFunctionCallMessage, {this.onToolRetry});// this.toTool);

  @override
  Command? handle(AgentMessage agentMessage) {
    Reflection reflection = agentMessage.content as Reflection;
    if(reflection.isPass || reflection.count == reflection.maxCount) {
      List<dynamic> jsonList = jsonDecode(reflection.messageScore.message);
      List<FunctionCall> functionCallList = jsonList.map((json)=>FunctionCall.fromJson(json)).toList();
      AgentMessage agentUserMessage = AgentMessage(
        sessionId: agentMessage.sessionId,
        parentTaskId: agentMessage.parentTaskId,
        taskId: agentMessage.taskId,
        role: MultiAgentRoleType.AGENT,
        to: MultiAgentRoleType.TOOL,
        type: MultiAgentMessageType.TOOL_CALLS,
        content: functionCallList
      );
      partitionFunctionCallMessage(agentUserMessage);
    } else {
      List<Content> userContentList = toolReflectionManager.userContentList;
      AgentMessage retryUserContentMessage = AgentMessage(
        sessionId: agentMessage.sessionId,
        parentTaskId: agentMessage.parentTaskId,
        taskId: agentMessage.taskId,
        role: MultiAgentRoleType.AGENT,
        to: MultiAgentRoleType.ASSISTANT,
        type: MultiAgentMessageType.CONTENT_LIST,
        content: userContentList
      );
      if(toolReflectionManager.shouldReflect) {
        if(onToolRetry != null) onToolRetry!(agentMessage);
        toolReflectionManager.retryIncrease();
      }
      return Command(toLLM, retryUserContentMessage); // Reset User messages request to LLM.
    }
    return null;
  }
}