import 'dart:async';
import 'package:opentool_dart/opentool_dart.dart';
import '../agents/llm/model.dart';
import '../agents/model.dart';
import '../agents/session_agent/model.dart';
import 'model.dart';
import 'agent_driver.dart';

class SessionAgentDriver extends AgentDriver {

  List<NamedSessionAgent> namedSessionAgents;

  SessionAgentDriver({required this.namedSessionAgents});

  @override
  List<FunctionModel> parse() {
    List<FunctionModel> functionModelList = [];
    namedSessionAgents.forEach((namedSessionAgent) {
      Parameter parameter = Parameter(name: promptKey, description: truncateWithEllipsis(promptDescription, llmFunctionDescriptionMaxLength), schema: Schema(type: DataType.STRING), required: true);
      FunctionModel functionModel = FunctionModel(
          name: namedSessionAgent.name,
          description: namedSessionAgent.description??(namedSessionAgent.agent.systemPrompt??truncateWithEllipsis(namedSessionAgent.agent.systemPrompt!, llmFunctionDescriptionMaxLength)),
          parameters: [parameter]
      );
      functionModelList.add(functionModel);
    });
    return functionModelList;
  }

  @override
  bool hasFunction(String functionName) {
    try {
      return namedSessionAgents.where((agentModel)=>agentModel.name == functionName).isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<ToolReturn> call(FunctionCall functionCall) async {
      return ToolReturn(id: functionCall.id, result: { "error": "Not Support call, use callAgent instead" });
  }

  @override
  Future<ToolReturn> callAgent(FunctionCall functionCall, String originalTaskId) async {
    try {
      String prompt = functionCall.arguments[promptKey];
      NamedSessionAgent namedSessionAgent = namedSessionAgents.where((agentModel) => agentModel.name == functionCall.name).first;
      Content content = Content(type: ContentType.TEXT, message: prompt);

      Completer<AgentMessage> completer = Completer();
      void Function(AgentMessage) listen = (agentMessage) {
        if(agentMessage.role == AgentRoleType.AGENT && agentMessage.to == AgentRoleType.USER) {
          completer.complete(agentMessage);
        }
      };
      namedSessionAgent.agent.agentSession.addAgentMessageListener(listen);

      agentMessageListeners.forEach((void Function(AgentMessage) agentMessageListener) => namedSessionAgent.agent.agentSession.addAgentMessageListener(agentMessageListener));

      await namedSessionAgent.agent.userToAgent(contentList: [content], originalTaskId: originalTaskId, parentTaskId: this.parentTaskId);

      AgentMessage agentMessage = await completer.future;
      String result = agentMessage.content as String;

      return ToolReturn(id: functionCall.id, result: { resultKey: result });
    } catch(e) {
      return ToolReturn(id: functionCall.id, result: { "error": "Not Support agent `${functionCall.name}`" });
    }
  }

}