import 'dart:async';
import 'dart:convert';
import 'package:opentool_dart/opentool_client.dart';
import '../../driver/agent_driver.dart';
import '../../driver/tool_driver.dart';
import '../llm/exception.dart';
import '../llm/openai_executor.dart';
import '../model.dart';
import '../pipeline/model.dart';
import '../pipeline/pipeline.dart';
import '../reflection/model.dart';
import '../session_agent/dispatcher.dart';
import '../text_agent/text_agent_message_handler.dart';
import '../tool_agent/model.dart';
import '../tool_agent/tool_agent.dart';
import 'model.dart';
import 'multi_agent_message_handler.dart';

class MultiAgent extends ToolAgent {
  static const String _subAgentFunctionName = "callSubAgent";
  static const String _subAgentNameKey = "agentName";
  static const String _subAgentFunctionDescription = "Call a sub-agent by name.";
  List<AgentDriver> subAgentDriverList;
  late Pipeline<FunctionCallParam> subAgentPipeLine;
  final Map<String, SeparatedFunctionCallList> _separatedFunctionCallMap = {};

  MultiAgent({
    required sessionId,
    toolDriverList = const <ToolDriver>[],
    clientOpenTool,
    required llmConfig,
    required agentSession,
    String? systemPrompt,
    int timeoutSeconds = 3600,
    int streamCallTimeoutSeconds = 60,
    List<ReflectPrompt> toolReflectPromptList = const[],
    String taskPipelineStrategy   = PipelineStrategyType.PARALLEL,
    String toolPipelineStrategy = PipelineStrategyType.PARALLEL,
    required this.subAgentDriverList,
    bool? enableThinking,
  }) : super(
    sessionId: sessionId,
    toolDriverList: toolDriverList,
    callbackOpenTool: clientOpenTool,
    llmConfig: llmConfig,
    agentSession: agentSession,
    systemPrompt: systemPrompt,
    timeoutSeconds: timeoutSeconds,
    streamCallTimeoutSeconds: streamCallTimeoutSeconds,
    taskPipelineStrategy: taskPipelineStrategy,
    toolPipelineStrategy: toolPipelineStrategy,
    enableThinking: enableThinking,
  ) {

    manager.registerHandler(role: MultiAgentRoleType.USER, handler: UserMessageHandler(toolReflectionManager, toLLM));  //override TextAgent User handler, for save List<Content>
    manager.registerHandler(role: MultiAgentRoleType.ASSISTANT, handler: MultiAgentFunctionCallingMessageHandler(toolReflectionManager, toReflection, toUser, _partitionFunctionCallMessage)); //override TextAgent LLM handler
    manager.registerHandler(role: MultiAgentRoleType.TOOL, handler: MultiAgentToolMessageHandler(onFunctionCallResult));
    manager.registerHandler(role: MultiAgentRoleType.SUBAGENT, handler: SubAgentMessageHandler(onFunctionCallResult));
    manager.registerHandler(role: MultiAgentRoleType.REFLECTION, handler: MultiAgentReflectionMessageHandler(toolReflectionManager, toLLM, _partitionFunctionCallMessage));//toTool, onToolRetry: super.onReflectionRetry));

    subAgentPipeLine = Pipeline(toolPipelineStrategy);
  }

  @override
  Future<void> toLLM(AgentMessage agentMessage) async {
    agentSession.addListenAgentMessage(agentMessage);

    final toolDrivers = await prepareToolDrivers(agentMessage);
    await Future.wait(toolDrivers.map((driver) => driver.init()));
    List<FunctionModel> functionModelList = await buildFunctionModelList(toolDrivers);

    List<FunctionModel> subAgentFunctionModelList = await _buildFunctionModelList(this.subAgentDriverList);
    functionModelList.addAll(subAgentFunctionModelList);

    try {
      List<AgentMessage> agentLLMMessageList = prepareAgentLLMMessageList(agentMessage);
      if(super.agentSession.isStream) {
        Stream<AgentMessage> agentMessageStream = await OpenAIExecutor(llmConfig).requestByStream(agentMessageList: agentLLMMessageList, functionModelList: functionModelList, enableThinking: enableThinking, listenChunk: listenChunk);
        agentMessageStream.listen((newAgentMessage) {
          Command nextCommand = Command(toAgent, newAgentMessage);
          dispatcherMap.dispatch(nextCommand);
        },
          onDone: () {},
          onError: (e) {
            pushException(agentMessage.sessionId, agentMessage.taskId, agentMessage.originalTaskId, e.toString());
          }
        );
      } else {
        AgentMessage llmMessage = await OpenAIExecutor(llmConfig).request(agentMessageList: agentLLMMessageList, functionModelList: functionModelList, enableThinking: enableThinking);
        Command nextCommand = Command(toAgent, llmMessage);
        dispatcherMap.dispatch(nextCommand);
      }
    } on LLMException catch(e) {
      pushException(agentMessage.sessionId, agentMessage.taskId, agentMessage.originalTaskId, jsonEncode(e.toJson()));
    }
  }

  SeparatedFunctionCallList _separateFunctionCallList(String originalTaskId, List<FunctionCall> functionCallList) {
    List<FunctionCall> toolFunctionCalls = [];
    List<FunctionCall> subAgentFunctionCalls = [];
    List<ToolDriver> drivers = getToolDriversForOriginalTask(originalTaskId);

    for (FunctionCall functionCall in functionCallList) {
      int toolIndex = drivers.indexWhere((toolDriver) => toolDriver.hasFunction(functionCall.name));
      if(toolIndex >= 0) {
        toolFunctionCalls.add(functionCall);
      } else {
        if(functionCall.name == _subAgentFunctionName) {
          subAgentFunctionCalls.add(functionCall);
        }
      }
    }

    return SeparatedFunctionCallList(toolFunctionCalls: toolFunctionCalls, subAgentFunctionCalls: subAgentFunctionCalls, hasToolFunctionCallsDone: toolFunctionCalls.isEmpty, hasSubAgentFunctionCallsDone: subAgentFunctionCalls.isEmpty);
  }

  Future<List<FunctionModel>> _buildFunctionModelList(List<AgentDriver> subAgentDriverList) async{
    if (subAgentDriverList.isEmpty) {
      return [];
    }
    List<FunctionModel> agentFunctionModelList = [];
    for (AgentDriver agentDriver in subAgentDriverList) {
      await agentDriver.init();
      List<FunctionModel> functionModelList = await agentDriver.parse();
      agentFunctionModelList.addAll(functionModelList);
    }
    if (agentFunctionModelList.isEmpty) {
      return [];
    }

    final AgentDriver baseDriver = subAgentDriverList.first;
    final List<String> agentNameList = [];
    final List<String> agentNameDescriptions = [];
    for (final functionModel in agentFunctionModelList) {
      agentNameList.add(functionModel.name);
      final String rawDescription = functionModel.description.trim();
      final String description = rawDescription.isNotEmpty ? rawDescription : functionModel.name;
      final String shortDescription =
          baseDriver.truncateWithEllipsis(description, baseDriver.llmFunctionDescriptionMaxLength);
      agentNameDescriptions.add("${functionModel.name} - $shortDescription");
    }
    final String agentNameDescription =
        "Choose an agent. Available agents: ${agentNameDescriptions.join("; ")}";

    final Parameter agentNameParameter = Parameter(
      name: _subAgentNameKey,
      description: agentNameDescription,
      schema: Schema(type: DataType.STRING, enum_: agentNameList),
      required: true,
    );
    final Parameter promptParameter = Parameter(
      name: baseDriver.promptKey,
      description: baseDriver.truncateWithEllipsis(
        baseDriver.promptDescription,
        baseDriver.llmFunctionDescriptionMaxLength,
      ),
      schema: Schema(type: DataType.STRING),
      required: true,
    );
    final FunctionModel functionModel = FunctionModel(
      name: _subAgentFunctionName,
      description: _subAgentFunctionDescription,
      parameters: [agentNameParameter, promptParameter],
    );
    return [functionModel];
  }

  void _partitionFunctionCallMessage(AgentMessage agentMessage) {
    if(agentMessage.type == MultiAgentMessageType.TOOL_CALLS) {
      List<FunctionCall> functionCallList = agentMessage.content as List<FunctionCall>;
      final SeparatedFunctionCallList separatedFunctionCallList =
          _separateFunctionCallList(agentMessage.originalTaskId, functionCallList);
      _separatedFunctionCallMap[agentMessage.taskId] = separatedFunctionCallList;
      if(separatedFunctionCallList.toolFunctionCalls.isNotEmpty) {
        AgentMessage toolMessage = AgentMessage(
            sessionId: agentMessage.sessionId,
            originalTaskId: agentMessage.originalTaskId,
            parentTaskId: agentMessage.parentTaskId,
            taskId: agentMessage.taskId,
            role: MultiAgentRoleType.AGENT,
            to: MultiAgentRoleType.TOOL,
            type: MultiAgentMessageType.TOOL_CALLS,
            content: separatedFunctionCallList.toolFunctionCalls
        );
        Command command = Command(toTool, toolMessage);
        dispatcherMap.dispatch(command);
      }

      if(separatedFunctionCallList.subAgentFunctionCalls.isNotEmpty) {
        AgentMessage subAgentMessage = AgentMessage(
            sessionId: agentMessage.sessionId,
            originalTaskId: agentMessage.originalTaskId,
            parentTaskId: agentMessage.parentTaskId,
            taskId: agentMessage.taskId,
            role: MultiAgentRoleType.AGENT,
            to: MultiAgentRoleType.SUBAGENT,
            type: MultiAgentMessageType.TOOL_CALLS,
            content: separatedFunctionCallList.subAgentFunctionCalls
        );
        Command command = Command(toSubAgent, subAgentMessage);
        dispatcherMap.dispatch(command);
      }
    }
  }

  void onFunctionCallResult(String from, AgentMessage agentMessage) {
    // agentSession.addListenAgentMessage(agentMessage);
    final SeparatedFunctionCallList? separatedFunctionCallList =
        _separatedFunctionCallMap[agentMessage.taskId];
    if (separatedFunctionCallList == null) {
      return;
    }
    if(separatedFunctionCallList.toolFunctionCalls.isNotEmpty &&
        from == MultiAgentRoleType.TOOL &&
        agentMessage.type == MultiAgentMessageType.TASK_STATUS &&
        (agentMessage.content as TaskStatus).status == ToolStatusType.DONE
    ) {
      separatedFunctionCallList.hasToolFunctionCallsDone = true;
    } else if (separatedFunctionCallList.subAgentFunctionCalls.isNotEmpty &&
        from == MultiAgentRoleType.SUBAGENT &&
        agentMessage.type == MultiAgentMessageType.TASK_STATUS &&
        (agentMessage.content as TaskStatus).status == MultiAgentStatusType.DONE
    ) {
      separatedFunctionCallList.hasSubAgentFunctionCallsDone = true;
    }
    if(separatedFunctionCallList.hasToolFunctionCallsDone &&
        separatedFunctionCallList.hasSubAgentFunctionCallsDone) {
      _separatedFunctionCallMap.remove(agentMessage.taskId);
      Command command = Command(toLLM, agentMessage);
      dispatcherMap.dispatch(command);
    }
  }

  @override
  List<AgentMessage> prepareAgentLLMMessageList(AgentMessage agentMessage) {
    List<AgentMessage> agentLLMMessageList = [];
    List<AgentMessage> sessionMessageList = List<AgentMessage>.from(agentSession.taskDoneAgentMessageList);
    List<AgentMessage> taskMessageList = dispatcherMap.getTaskMessageList(agentMessage.taskId);
    sessionMessageList.addAll(taskMessageList);
    sessionMessageList.forEach((sessionMessage){
      if( sessionMessage.role == MultiAgentRoleType.DEVELOPER ||
          sessionMessage.role == MultiAgentRoleType.ASSISTANT ||
          sessionMessage.to == MultiAgentRoleType.ASSISTANT   ||
          sessionMessage.role == MultiAgentRoleType.TOOL      ||
          sessionMessage.role == MultiAgentRoleType.SUBAGENT ) {
        agentLLMMessageList.add(sessionMessage);
      }
    });
    return agentLLMMessageList;
  }

  Future<void> requestSubAgents(AgentMessage agentMessage) async {
    List<FunctionCall> functionCallList = agentMessage.content as List<FunctionCall>;
    final String promptKey =
        subAgentDriverList.isNotEmpty ? subAgentDriverList.first.promptKey : "prompt";

    for (FunctionCall functionCall in functionCallList) {
      final dynamic agentNameValue = functionCall.arguments[_subAgentNameKey];
      if (agentNameValue is! String || agentNameValue.trim().isEmpty) {
        _dispatchSubAgentError(agentMessage, functionCall, "Missing or invalid agentName.");
        continue;
      }
      int subAgentIndex = subAgentDriverList
          .indexWhere((agentDriver) => agentDriver.hasFunction(agentNameValue));
      if(subAgentIndex < 0) {
        _dispatchSubAgentError(agentMessage, functionCall, "Unknown agent `$agentNameValue`.");
        continue;
      }
      final Map<String, dynamic> subAgentArguments =
          Map<String, dynamic>.from(functionCall.arguments);
      subAgentArguments.remove(_subAgentNameKey);
      final dynamic promptValue = subAgentArguments[promptKey];
      if (promptValue is! String || promptValue.isEmpty) {
        _dispatchSubAgentError(agentMessage, functionCall, "Missing or invalid prompt.");
        continue;
      }
      final FunctionCall subAgentFunctionCall = FunctionCall(
        id: functionCall.id,
        name: agentNameValue,
        arguments: subAgentArguments,
      );
      FunctionCallParam functionCallParam = FunctionCallParam(
        sessionId: agentMessage.sessionId,
        taskId: agentMessage.taskId,
        originalTaskId: agentMessage.originalTaskId,
        type: FunctionCallType.SUBAGENT,
        index: subAgentIndex,
        functionCall: subAgentFunctionCall,
      );
      subAgentPipeLine.addJob(functionCallParam);
    }
    List<String> functionCallIdList = functionCallList.map((functionCall) => functionCall.id).toList();

    subAgentPipeLine.run(_requestSubAgent, onComplete: () async {
      AgentMessage subAgentDoneMessage = AgentMessage(
        sessionId: agentMessage.sessionId,
        originalTaskId: agentMessage.originalTaskId,
        parentTaskId: agentMessage.parentTaskId,
        taskId: agentMessage.taskId,
        role: MultiAgentRoleType.SUBAGENT,
        to: MultiAgentRoleType.AGENT,
        type: MultiAgentMessageType.TASK_STATUS,
        content: TaskStatus(status: MultiAgentStatusType.DONE, taskId: agentMessage.taskId, description: ToolStatusDescription(functionCallIdList: functionCallIdList).toJson())
      );
      Command command = Command(toAgent, subAgentDoneMessage);
      dispatcherMap.dispatch(command);
    });
  }

  void _dispatchSubAgentError(AgentMessage agentMessage, FunctionCall functionCall, String errorMessage) {
    AgentMessage subAgentErrorMessage = AgentMessage(
      sessionId: agentMessage.sessionId,
      originalTaskId: agentMessage.originalTaskId,
      parentTaskId: agentMessage.parentTaskId,
      taskId: agentMessage.taskId,
      role: MultiAgentRoleType.SUBAGENT,
      to: MultiAgentRoleType.AGENT,
      type: MultiAgentMessageType.TOOL_RETURN,
      content: ToolReturn(id: functionCall.id, result: {"error": errorMessage}),
    );
    Command command = Command(toAgent, subAgentErrorMessage);
    dispatcherMap.dispatch(command);
  }

  Future<void> _requestSubAgent(FunctionCallParam functionCallParam) async {
    try {
      if(functionCallParam.type == null || functionCallParam.type == FunctionCallType.SUBAGENT) {
        AgentDriver agentDriver = subAgentDriverList[functionCallParam.index];
        agentDriver.setParentTaskId(functionCallParam.taskId);
        agentDriver.addAgentMessageListener((AgentMessage agentMessage){
          agentSession.addListenAgentMessage(agentMessage);
        });
        ToolReturn toolReturn = await agentDriver.callAgent(functionCallParam.functionCall, functionCallParam.originalTaskId);
        AgentMessage toolMessage = AgentMessage(
          sessionId: functionCallParam.sessionId,
          originalTaskId: functionCallParam.originalTaskId,
          parentTaskId: this.parentTaskId,
          taskId: functionCallParam.taskId,
          role: MultiAgentRoleType.SUBAGENT,
          to: MultiAgentRoleType.AGENT,
          type: MultiAgentMessageType.TOOL_RETURN,
          content: toolReturn
        );
        Command command = Command(toAgent, toolMessage);
        dispatcherMap.dispatch(command);
      }
    } on ToolBreakException catch(e) {
      /** When toolDriver.call throw ToolBreakException, it will break task.*/
      this.dispatcherMap.breakTask(functionCallParam.taskId);
      throw e;
    }
  }

  Future<void> toSubAgent(AgentMessage agentMessage) async {
    if(agentMessage.type == MultiAgentMessageType.TOOL_CALLS) {
      List<FunctionCall> functionCallList = agentMessage.content as List<FunctionCall>;
      List<String> functionCallIdList = functionCallList.map((functionCall) => functionCall.id).toList();
      agentSession.addListenAgentMessage(agentMessage);
      Command clientCommand = Command(
        toClient,
        AgentMessage(
          sessionId: agentMessage.sessionId,
          originalTaskId: agentMessage.originalTaskId,
          parentTaskId: agentMessage.parentTaskId,
          taskId: agentMessage.taskId,
          role: MultiAgentRoleType.AGENT,
          to: MultiAgentRoleType.CLIENT,
          type: MultiAgentMessageType.TASK_STATUS,
          content: TaskStatus(status:MultiAgentStatusType.START, taskId: agentMessage.taskId, description: ToolStatusDescription(functionCallIdList: functionCallIdList).toJson())
        ));
      dispatcherMap.dispatch(clientCommand);
      requestSubAgents(agentMessage);
    }
  }
}
