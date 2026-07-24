import 'dart:async';
import 'package:opentool_dart/opentool_client.dart';
import '../agents/llm/model.dart';
import '../agents/model.dart';
import '../agents/session_agent/model.dart';
import '../agents/session_agent/session_agent.dart';
import 'model.dart';
import 'agent_driver.dart';

class SessionAgentDriver extends AgentDriver {
  List<NamedSessionAgent> namedSessionAgents;
  final Map<String, _PendingSessionAgentCall> _pendingCalls = {};

  SessionAgentDriver({required this.namedSessionAgents});

  @override
  List<FunctionModel> parse() {
    List<FunctionModel> functionModelList = [];
    namedSessionAgents.forEach((namedSessionAgent) {
      Parameter parameter = Parameter(
          name: promptKey,
          description: truncateWithEllipsis(promptDescription, llmFunctionDescriptionMaxLength),
          schema: Schema(type: DataType.STRING),
          required: true);
      FunctionModel functionModel = FunctionModel(
          name: namedSessionAgent.name,
          description: namedSessionAgent.description ??
              (namedSessionAgent.agent.systemPrompt ??
                  truncateWithEllipsis(
                      namedSessionAgent.agent.systemPrompt!, llmFunctionDescriptionMaxLength)),
          parameters: [parameter]);
      functionModelList.add(functionModel);
    });
    return functionModelList;
  }

  @override
  bool hasFunction(String functionName) {
    try {
      return namedSessionAgents.where((agentModel) => agentModel.name == functionName).isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<ToolReturn> call(FunctionCall functionCall) async {
    return ToolReturn(
        id: functionCall.id, result: {"error": "Not Support call, use callAgent instead"});
  }

  @override
  Future<ToolReturn> callAgent(FunctionCall functionCall, String originalTaskId) async {
    try {
      final String prompt = functionCall.arguments[promptKey];
      final NamedSessionAgent namedSessionAgent =
          namedSessionAgents.where((agentModel) => agentModel.name == functionCall.name).first;
      final Content content = Content(type: ContentType.TEXT, message: prompt);

      String taskId = "";
      final pendingCall = _PendingSessionAgentCall(namedSessionAgent.agent);
      _pendingCalls[functionCall.id] = pendingCall;
      void Function(String taskId) fetchTaskId = (String id) {
        taskId = id;
        pendingCall.taskId = id;
      };

      final Completer<String> completer = Completer();
      bool matches(AgentMessage m) =>
          m.taskId == taskId &&
          m.sessionId == namedSessionAgent.agent.agentSession.sessionId &&
          m.parentTaskId == namedSessionAgent.agent.parentTaskId &&
          m.originalTaskId == originalTaskId;

      void Function(AgentMessage) listen = (AgentMessage agentMessage) {
        if (completer.isCompleted || !matches(agentMessage)) {
          return;
        }
        if (agentMessage.role == AgentRoleType.AGENT && agentMessage.to == AgentRoleType.USER) {
          completer.complete(agentMessage.content as String);
        } else if (agentMessage.role == AgentRoleType.AGENT &&
            agentMessage.to == AgentRoleType.CLIENT &&
            agentMessage.type == AgentMessageType.TASK_STATUS) {
          final TaskStatus taskStatus = agentMessage.content as TaskStatus;
          if (taskStatus.status == TaskStatusType.EXCEPTION ||
              taskStatus.status == TaskStatusType.STOP) {
            completer.complete(taskStatus.toJson().toString());
          }
        }
      };
      namedSessionAgent.agent.agentSession.addAgentMessageListener(listen);

      agentMessageListeners.forEach((void Function(AgentMessage) agentMessageListener) =>
          namedSessionAgent.agent.agentSession.addAgentMessageListener(agentMessageListener));

      await namedSessionAgent.agent.userToAgent(
          contentList: [content],
          originalTaskId: originalTaskId,
          parentTaskId: this.parentTaskId,
          fetchTaskId: fetchTaskId);

      String result;
      try {
        result = await completer.future;
      } finally {
        _pendingCalls.remove(functionCall.id);
      }

      return ToolReturn(id: functionCall.id, result: {resultKey: result});
    } catch (e) {
      _pendingCalls.remove(functionCall.id);
      return ToolReturn(
          id: functionCall.id, result: {"error": "Not Support agent `${functionCall.name}`"});
    }
  }

  @override
  Future<void> cancel(String functionCallId) async {
    final pendingCall = _pendingCalls[functionCallId];
    if (pendingCall == null || pendingCall.taskId.isEmpty) return;
    pendingCall.agent.stop(taskId: pendingCall.taskId);
  }
}

class _PendingSessionAgentCall {
  final SessionAgent agent;
  String taskId = "";

  _PendingSessionAgentCall(this.agent);
}
