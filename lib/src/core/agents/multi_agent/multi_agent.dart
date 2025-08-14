import 'dart:async';
import 'dart:convert';
import 'package:opentool_dart/opentool_dart.dart';
import '../../driver/agent_driver.dart';
import '../../driver/client_driver.dart';
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
  List<AgentDriver> subAgentDriverList;
  late Pipeline<FunctionCallParam> subAgentPipeLine;
  late SeparatedFunctionCallList _separatedFunctionCallList;

  MultiAgent({
    required sessionId,
    toolDriverList = const <ToolDriver>[],
    clientOpenTool,
    required llmConfig,
    required agentSession,
    String? systemPrompt,
    int timeoutSeconds = 3600,
    List<ReflectPrompt> toolReflectPromptList = const[],
    String taskPipelineStrategy   = PipelineStrategyType.PARALLEL,
    String toolPipelineStrategy = PipelineStrategyType.PARALLEL,
    required this.subAgentDriverList,
    bool? enableThinking,
  }) : super(
    sessionId: sessionId,
    toolDriverList: toolDriverList,
    clientOpenTool: clientOpenTool,
    llmConfig: llmConfig,
    agentSession: agentSession,
    systemPrompt: systemPrompt,
    timeoutSeconds: timeoutSeconds,
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

    await Future.wait(toolDriverList.map((driver) => driver.init()));
    List<FunctionModel> functionModelList = await buildFunctionModelList();
    if(this.clientOpenTool != null && this.clientOpenTool!.fetchClientDriver != null) {
      ClientDriver clientDriver = await buildClientDriver(agentMessage);
      toolDriverList.add(clientDriver);
      this.clientOpenTool!.fetchClientDriver!(agentMessage.sessionId, clientDriver);
      functionModelList.addAll(clientDriver.parse());
    }

    for (AgentDriver agentDriver in subAgentDriverList) {
      await agentDriver.init();
      functionModelList.addAll(agentDriver.parse());
    }

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

  SeparatedFunctionCallList _separateFunctionCallList(List<FunctionCall> functionCallList) {
    List<FunctionCall> toolFunctionCalls = [];
    List<FunctionCall> subAgentFunctionCalls = [];

    for (FunctionCall functionCall in functionCallList) {
      int toolIndex = toolDriverList.indexWhere((toolDriver) => toolDriver.hasFunction(functionCall.name));
      if(toolIndex >= 0) {
        toolFunctionCalls.add(functionCall);
      } else {
        int agentIndex = subAgentDriverList.indexWhere((agentDriver) => agentDriver.hasFunction(functionCall.name));
        if(agentIndex >= 0) {
          subAgentFunctionCalls.add(functionCall);
        }
      }
    }

    return SeparatedFunctionCallList(toolFunctionCalls: toolFunctionCalls, subAgentFunctionCalls: subAgentFunctionCalls, hasToolFunctionCallsDone: toolFunctionCalls.isEmpty, hasSubAgentFunctionCallsDone: subAgentFunctionCalls.isEmpty);
  }

  void _partitionFunctionCallMessage(AgentMessage agentMessage) {
    if(agentMessage.type == MultiAgentMessageType.TOOL_CALLS) {
      List<FunctionCall> functionCallList = agentMessage.content as List<FunctionCall>;
      _separatedFunctionCallList = _separateFunctionCallList(functionCallList);
      if(_separatedFunctionCallList.toolFunctionCalls.isNotEmpty) {
        AgentMessage toolMessage = AgentMessage(
            sessionId: agentMessage.sessionId,
            originalTaskId: agentMessage.originalTaskId,
            parentTaskId: agentMessage.parentTaskId,
            taskId: agentMessage.taskId,
            role: MultiAgentRoleType.AGENT,
            to: MultiAgentRoleType.TOOL,
            type: MultiAgentMessageType.TOOL_CALLS,
            content: _separatedFunctionCallList.toolFunctionCalls
        );
        Command command = Command(toTool, toolMessage);
        dispatcherMap.dispatch(command);
      }

      if(_separatedFunctionCallList.subAgentFunctionCalls.isNotEmpty) {
        AgentMessage subAgentMessage = AgentMessage(
            sessionId: agentMessage.sessionId,
            originalTaskId: agentMessage.originalTaskId,
            parentTaskId: agentMessage.parentTaskId,
            taskId: agentMessage.taskId,
            role: MultiAgentRoleType.AGENT,
            to: MultiAgentRoleType.SUBAGENT,
            type: MultiAgentMessageType.TOOL_CALLS,
            content: _separatedFunctionCallList.subAgentFunctionCalls
        );
        Command command = Command(toSubAgent, subAgentMessage);
        dispatcherMap.dispatch(command);
      }
    }
  }

  void onFunctionCallResult(String from, AgentMessage agentMessage) {
    // agentSession.addListenAgentMessage(agentMessage);
    if(_separatedFunctionCallList.toolFunctionCalls.isNotEmpty &&
        from == MultiAgentRoleType.TOOL &&
        agentMessage.type == MultiAgentMessageType.TASK_STATUS &&
        (agentMessage.content as TaskStatus).status == ToolStatusType.DONE
    ) {
      _separatedFunctionCallList.hasToolFunctionCallsDone = true;
    } else if (_separatedFunctionCallList.subAgentFunctionCalls.isNotEmpty &&
        from == MultiAgentRoleType.SUBAGENT &&
        agentMessage.type == MultiAgentMessageType.TASK_STATUS &&
        (agentMessage.content as TaskStatus).status == MultiAgentStatusType.DONE
    ) {
      _separatedFunctionCallList.hasSubAgentFunctionCallsDone = true;
    }
    if(_separatedFunctionCallList.hasToolFunctionCallsDone && _separatedFunctionCallList.hasSubAgentFunctionCallsDone) {
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

    for (FunctionCall functionCall in functionCallList) {
      int subAgentIndex = subAgentDriverList.indexWhere((toolDriver) => toolDriver.hasFunction(functionCall.name));
      if(subAgentIndex >= 0) {
        FunctionCallParam functionCallParam = FunctionCallParam(sessionId: agentMessage.sessionId, taskId: agentMessage.taskId, originalTaskId: agentMessage.originalTaskId, type: FunctionCallType.SUBAGENT, index: subAgentIndex,functionCall: functionCall);
        toolPipeLine.addJob(functionCallParam);
      }
    }
    List<String> functionCallIdList = functionCallList.map((functionCall) => functionCall.id).toList();

    toolPipeLine.run(_requestSubAgent, onComplete: () async {
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
    if(agentMessage.type == ToolMessageType.TOOL_CALLS) {
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
