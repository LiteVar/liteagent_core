import 'dart:async';
import 'dart:convert';
import 'package:opentool_dart/opentool_client.dart';
import '../../agents/text_agent/text_agent.dart';
import '../../driver/opentool/opentool_callback_driver.dart';
import '../../driver/opentool/opentool_driver.dart';
import '../../driver/tool_driver.dart';
import '../llm/exception.dart';
import '../llm/openai_executor.dart';
import '../model.dart';
import '../pipeline/model.dart';
import '../pipeline/pipeline.dart';
import '../reflection/model.dart';
import '../reflection/reflector.dart';
import '../reflection/reflector_agent.dart';
import '../reflection/reflector_manager.dart';
import '../session_agent/dispatcher.dart';
import '../session_agent/model.dart';
import '../text_agent/model.dart';
import '../text_agent/text_agent_message_handler.dart';
import '../tool_agent/model.dart';
import 'tool_agent_message_handler.dart';

const String _streamEventsKey = "__streamEvents__";

class ToolAgent extends TextAgent {
  List<ToolDriver> toolDriverList;
  ReflectorManager toolReflectionManager = ReflectorManager();
  late Pipeline<FunctionCallParam> toolPipeLine;
  CallbackOpenTool? callbackOpenTool;
  final int streamCallTimeoutSeconds;
  final Map<String, OpenToolCallbackDriver> _callbackToolDriverMap = {};
  final Map<String, List<ToolDriver>> _toolDriversByOriginalTaskId = {};
  final Map<String, _StreamCallTaskState> _streamTaskStateMap = {};
  final Map<String, Map<String, dynamic>> _streamExceptionTaskInfo = {};

  ToolAgent({
    required super.sessionId,
    this.toolDriverList = const <ToolDriver>[],
    this.callbackOpenTool,
    required super.llmConfig,
    required super.agentSession,
    String? super.systemPrompt,
    super.timeoutSeconds = 3600,
    List<ReflectPrompt> toolReflectPromptList = const[],
    super.taskPipelineStrategy,
    String toolPipelineStrategy = PipelineStrategyType.PARALLEL,
    this.streamCallTimeoutSeconds = 60,
    super.enableThinking,
  }) {
    toolReflectPromptList.forEach((reflectPrompt){
      ReflectorAgent reflectorAgent = ReflectorAgent(llmExecutor: OpenAIExecutor(reflectPrompt.llmConfig), systemPrompt: reflectPrompt.prompt, sessionId: this.sessionId, parentTaskId: this.parentTaskId);
      AgentReflector agentReflector = AgentReflector(agent: reflectorAgent, subscribeCompletions: subscribeCompletions);
      toolReflectionManager.addReflector(agentReflector);
    });

    manager.registerHandler(role: TextRoleType.USER, handler: UserMessageHandler(toolReflectionManager, toLLM));//override TextAgent User handler, for save List<Content>
    manager.registerHandler(role: ToolRoleType.ASSISTANT, handler: LLMFunctionCallingMessageHandler(toolReflectionManager, toReflection, toUser, toTool)); //override TextAgent LLM handler
    manager.registerHandler(role: ToolRoleType.TOOL, handler: ToolMessageHandler(toLLM, onToolReturn: onToolReturn));
    manager.registerHandler(role: ToolRoleType.REFLECTION, handler: ToolReflectionMessageHandler(toolReflectionManager, toLLM, toTool, onToolRetry: super.onReflectionRetry));

    toolPipeLine = Pipeline(toolPipelineStrategy);
  }

  Future<List<ToolDriver>> prepareToolDrivers(AgentMessage agentMessage) async {
    final drivers = List<ToolDriver>.from(toolDriverList);
    if (callbackOpenTool != null && callbackOpenTool!.fetchClientDriver != null) {
      OpenToolCallbackDriver? clientDriver = _callbackToolDriverMap[agentMessage.originalTaskId];
      if (clientDriver == null) {
        clientDriver = await buildClientDriver(agentMessage);
        _callbackToolDriverMap[agentMessage.originalTaskId] = clientDriver;
        callbackOpenTool!.fetchClientDriver!(agentMessage.sessionId, clientDriver);
      }
      drivers.add(clientDriver);
    }
    _toolDriversByOriginalTaskId[agentMessage.originalTaskId] = drivers;
    return drivers;
  }

  List<ToolDriver> getToolDriversForOriginalTask(String originalTaskId) {
    return _toolDriversByOriginalTaskId[originalTaskId] ?? List<ToolDriver>.from(toolDriverList);
  }

  void onToolReturn(AgentMessage agentLLMMessage) {
    agentSession.addListenAgentMessage(agentLLMMessage);
  }

  @override
  Future<void> toAgent(AgentMessage agentMessage) async {
    agentSession.addListenAgentMessage(agentMessage);
    Command? nextCommand = manager.handleMessage(agentMessage);
    if (nextCommand != null) dispatcherMap.dispatch(nextCommand);
  }

  @override
  List<AgentMessage> prepareAgentLLMMessageList(AgentMessage agentMessage) {
    List<AgentMessage> agentLLMMessageList = [];
    List<AgentMessage> sessionMessageList = List<AgentMessage>.from(agentSession.taskDoneAgentMessageList);
    List<AgentMessage> taskMessageList = dispatcherMap.getTaskMessageList(agentMessage.taskId);
    sessionMessageList.addAll(taskMessageList);
    sessionMessageList.forEach((sessionMessage){
      if( sessionMessage.role == TextRoleType.DEVELOPER ||
          sessionMessage.role == TextRoleType.ASSISTANT ||
          sessionMessage.to == TextRoleType.ASSISTANT ||
          sessionMessage.role == ToolRoleType.TOOL ) {
        agentLLMMessageList.add(sessionMessage);
      }
    });
    return agentLLMMessageList;
  }

  @override
  Future<void> toLLM(AgentMessage agentMessage) async {
    agentSession.addListenAgentMessage(agentMessage);

    final drivers = await prepareToolDrivers(agentMessage);
    await Future.wait(drivers.map((driver) => driver.init()));
    List<FunctionModel> functionModelList = await buildFunctionModelList(drivers);

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

  @override
  Future<void> toReflection(AgentMessage agentMessage) async {
    if(agentMessage.type == ToolMessageType.TOOL_CALLS) {
      List<FunctionCall> functionCallList = agentMessage.content as List<FunctionCall>;
      List<Map<String, dynamic>> functionCallJsonList = functionCallList.map((functionCall)=>functionCall.toJson()).toList();
      Reflection reflection = await toolReflectionManager.reflect(agentMessage.type, jsonEncode(functionCallJsonList), agentMessage.originalTaskId);
      AgentMessage reflectionMessage = AgentMessage(
          sessionId: agentMessage.sessionId,
          originalTaskId: agentMessage.originalTaskId,
          parentTaskId: agentMessage.parentTaskId,
          taskId: agentMessage.taskId,
          role: TextRoleType.REFLECTION,
          to: TextRoleType.AGENT,
          type: TextMessageType.REFLECTION,
          content: reflection,
          completions: currAgentReflectorCompletions
      );
      Command reflectionCommand = Command(toAgent, reflectionMessage);
      dispatcherMap.dispatch(reflectionCommand);
    } else {
      super.toReflection(agentMessage);
    }
  }

  Future<List<FunctionModel>> buildFunctionModelList([List<ToolDriver>? drivers]) async {
    final driverList = drivers ?? toolDriverList;
    List<FunctionModel> functionModelList = [];
    driverList.forEach((ToolDriver toolDriver) {
      functionModelList.addAll(toolDriver.parse());
    });
    return functionModelList;
  }

  Future<OpenToolCallbackDriver> buildClientDriver(AgentMessage agentMessage) async {
    OpenTool opentool = await OpenToolJsonLoader().load(this.callbackOpenTool!.opentool);
    void Function(FunctionCall functionCall) listenClientFunctionCall = (FunctionCall functionCall) {
      AgentMessage clientMessage = AgentMessage(
          sessionId: agentMessage.sessionId,
          originalTaskId: agentMessage.originalTaskId,
            parentTaskId: agentMessage.parentTaskId,
          taskId: agentMessage.taskId,
          role: ToolRoleType.AGENT,
          to: ToolRoleType.CLIENT,
          type: ToolMessageType.FUNCTION_CALL,
          content: functionCall
      );
      Command functionCallCommand = Command(toAgent, clientMessage);
      dispatcherMap.dispatch(functionCallCommand);
    };
    return OpenToolCallbackDriver(opentool, listenClientFunctionCall, timeout: callbackOpenTool!.timeout??60);
  }

  bool _supportsStreamCall(ToolDriver toolDriver, FunctionCall functionCall) {
    if (toolDriver is OpenToolDriver) {
      FunctionModel? functionModel;
      try {
        functionModel = toolDriver.opentool.functions
            .firstWhere((functionModel) => functionModel.name == functionCall.name);
      } catch (_) {
        functionModel = null;
      }
      return functionModel?.stream != null;
    }
    return false;
  }

  _StreamCallTaskState _getOrCreateStreamTaskState(FunctionCallParam functionCallParam) {
    return _streamTaskStateMap.putIfAbsent(
      functionCallParam.taskId,
      () => _StreamCallTaskState(
        sessionId: functionCallParam.sessionId,
        taskId: functionCallParam.taskId,
        originalTaskId: functionCallParam.originalTaskId,
        parentTaskId: parentTaskId,
        timeoutSeconds: streamCallTimeoutSeconds,
      ),
    );
  }

  Future<void> _handleStreamToolCall(FunctionCallParam functionCallParam, ToolDriver toolDriver) async {
    final taskState = _getOrCreateStreamTaskState(functionCallParam);
    final callState = taskState.getOrCreateCall(
      functionCallParam.functionCall.id,
      functionCallParam.functionCall.name,
    );
    _resetStreamTimeout(taskState);

    void onStream(String event, ToolReturn toolReturn) {
      _handleStreamEvent(taskState, callState, event, toolReturn);
    }

    try {
      await toolDriver.streamCall(functionCallParam.functionCall, onStream);
    } on ToolBreakException {
      rethrow;
    } catch (e) {
      _handleStreamException(taskState, callState, e.toString());
    }

    await callState.doneCompleter.future;
  }

  void _handleStreamEvent(
    _StreamCallTaskState taskState,
    _StreamCallState callState,
    String event,
    ToolReturn toolReturn,
  ) {
    final eventType = event == "exception" ? EventType.ERROR : event;
    final rawPayload = toolReturn.result;
    final dynamic resultPayload =
        rawPayload.containsKey("result") ? rawPayload["result"] : rawPayload;

    if (!callState.hasStart && eventType != EventType.START) {
      _appendStreamEvent(taskState, callState, EventType.START, {});
    }

    _appendStreamEvent(taskState, callState, eventType, resultPayload);
    _resetStreamTimeout(taskState);

    if (eventType == EventType.DONE || eventType == EventType.ERROR) {
      _markStreamCallDone(taskState, callState, eventType == EventType.ERROR, resultPayload);
    }

    _scheduleStreamInference(taskState);
  }

  void _handleStreamException(
    _StreamCallTaskState taskState,
    _StreamCallState callState,
    String errorMessage,
  ) {
    final payload = <String, dynamic>{"error": errorMessage};
    if (!callState.hasStart) {
      _appendStreamEvent(taskState, callState, EventType.START, {});
    }
    _appendStreamEvent(taskState, callState, EventType.ERROR, payload);
    _resetStreamTimeout(taskState);
    _markStreamCallDone(taskState, callState, true, payload);
    _scheduleStreamInference(taskState);
  }

  void _appendStreamEvent(
    _StreamCallTaskState taskState,
    _StreamCallState callState,
    String eventType,
    dynamic payload,
  ) {
    Map<String, dynamic> eventObject;
    if (eventType == EventType.START) {
      callState.hasStart = true;
      eventObject = {
        "start": callState.functionName,
        "data": payload,
      };
    } else if (eventType == EventType.DATA) {
      eventObject = {"data": payload};
    } else if (eventType == EventType.ERROR) {
      eventObject = {"exception": payload};
    } else if (eventType == EventType.DONE) {
      eventObject = {"done": {}};
    } else {
      eventObject = {eventType: payload};
    }

    callState.events.add(eventObject);
    taskState.pending += 1;

    final toolReturn = ToolReturn(id: callState.callId, result: eventObject);
    AgentMessage toolMessage = AgentMessage(
      sessionId: taskState.sessionId,
      originalTaskId: taskState.originalTaskId,
      parentTaskId: taskState.parentTaskId,
      taskId: taskState.taskId,
      role: ToolRoleType.TOOL,
      to: ToolRoleType.AGENT,
      type: ToolMessageType.TOOL_RETURN,
      content: toolReturn,
    );
    agentSession.addListenAgentMessage(toolMessage);
  }

  void _resetStreamTimeout(_StreamCallTaskState taskState) {
    taskState.timeoutTimer?.cancel();
    taskState.timeoutTimer = Timer(
      Duration(seconds: taskState.timeoutSeconds),
      () => _handleStreamTimeout(taskState),
    );
  }

  void _handleStreamTimeout(_StreamCallTaskState taskState) {
    if (taskState.finalInferenceReady) return;
    final payload = <String, dynamic>{
      "error": "streamCall timeout after ${taskState.timeoutSeconds}s."
    };

    for (final callState in taskState.calls.values) {
      if (callState.terminated) continue;
      if (!callState.hasStart) {
        _appendStreamEvent(taskState, callState, EventType.START, {});
      }
      _appendStreamEvent(taskState, callState, EventType.ERROR, payload);
      _markStreamCallDone(taskState, callState, true, payload);
    }

    _scheduleStreamInference(taskState);
  }

  void _markStreamCallDone(
    _StreamCallTaskState taskState,
    _StreamCallState callState,
    bool isException,
    dynamic payload,
  ) {
    if (callState.terminated) return;
    callState.terminated = true;
    if (!callState.doneCompleter.isCompleted) {
      callState.doneCompleter.complete();
    }
    if (isException) {
      taskState.hasException = true;
      if (taskState.exceptionPayload == null && payload is Map<String, dynamic>) {
        taskState.exceptionPayload = payload;
      }
    }
    if (taskState.calls.values.every((state) => state.terminated)) {
      taskState.finalInferenceReady = true;
      taskState.timeoutTimer?.cancel();
    }
  }

  void _scheduleStreamInference(_StreamCallTaskState taskState) {
    if (taskState.llmBusy) return;
    taskState.llmBusy = true;
    Future(() async {
      try {
        while (true) {
          if (taskState.finalInferenceStarted) break;
          if (taskState.finalInferenceReady) {
            taskState.finalInferenceStarted = true;
            await _runFinalStreamInference(taskState);
            taskState.finalInferenceDone = true;
            break;
          }
          if (taskState.pending == 0) break;
          taskState.pending = 0;
          await _runDraftStreamInference(taskState);
        }
      } finally {
        taskState.llmBusy = false;
        if (taskState.finalInferenceDone) {
          _streamTaskStateMap.remove(taskState.taskId);
        } else if (taskState.pending > 0 || taskState.finalInferenceReady) {
          _scheduleStreamInference(taskState);
        }
      }
    });
  }

  Map<String, List<Map<String, dynamic>>> _snapshotStreamEvents(_StreamCallTaskState taskState) {
    final snapshot = <String, List<Map<String, dynamic>>>{};
    taskState.calls.forEach((callId, callState) {
      snapshot[callId] = List<Map<String, dynamic>>.from(callState.events);
    });
    return snapshot;
  }

  List<AgentMessage> _buildStreamMessageList(_StreamCallTaskState taskState) {
    final anchorMessage = AgentMessage(
      sessionId: taskState.sessionId,
      originalTaskId: taskState.originalTaskId,
      parentTaskId: taskState.parentTaskId,
      taskId: taskState.taskId,
      role: ToolRoleType.AGENT,
      to: ToolRoleType.ASSISTANT,
      type: ToolMessageType.TASK_STATUS,
      content: TaskStatus(status: ToolStatusType.DONE, taskId: taskState.taskId),
    );

    final messageList = prepareAgentLLMMessageList(anchorMessage);
    final snapshot = _snapshotStreamEvents(taskState);

    snapshot.forEach((callId, events) {
      final toolReturn = ToolReturn(id: callId, result: {_streamEventsKey: events});
      messageList.add(AgentMessage(
        sessionId: taskState.sessionId,
        originalTaskId: taskState.originalTaskId,
        parentTaskId: taskState.parentTaskId,
        taskId: taskState.taskId,
        role: ToolRoleType.TOOL,
        to: ToolRoleType.AGENT,
        type: ToolMessageType.TOOL_RETURN,
        content: toolReturn,
      ));
    });

    return messageList;
  }

  Future<void> _runDraftStreamInference(_StreamCallTaskState taskState) async {
    final drivers = getToolDriversForOriginalTask(taskState.originalTaskId);
    final functionModelList = await buildFunctionModelList(drivers);
    final messageList = _buildStreamMessageList(taskState);

    try {
      final stream = await OpenAIExecutor(llmConfig).requestByStream(
        agentMessageList: messageList,
        functionModelList: functionModelList,
        enableThinking: enableThinking,
        listenChunk: listenChunk,
      );

      final completer = Completer<void>();
      stream.listen(
        (message) async {
          if (message.type == ToolMessageType.TEXT || message.type == ToolMessageType.IMAGE_URL) {
            AgentMessage userMessage = AgentMessage(
              sessionId: message.sessionId,
              originalTaskId: message.originalTaskId,
              parentTaskId: message.parentTaskId,
              taskId: message.taskId,
              role: ToolRoleType.AGENT,
              to: ToolRoleType.USER,
              type: message.type,
              content: message.content,
              completions: message.completions,
            );
            await agentSession.addListenAgentMessage(userMessage);
          } else {
            await agentSession.addListenAgentMessage(message);
          }
        },
        onDone: () => completer.complete(),
        onError: (e) {
          pushException(taskState.sessionId, taskState.taskId, taskState.originalTaskId, e.toString());
          completer.complete();
        },
      );
      await completer.future;
    } on LLMException catch (e) {
      pushException(taskState.sessionId, taskState.taskId, taskState.originalTaskId, jsonEncode(e.toJson()));
    }
  }

  Future<void> _runFinalStreamInference(_StreamCallTaskState taskState) async {
    final snapshot = _snapshotStreamEvents(taskState);
    snapshot.forEach((callId, events) {
      final toolReturn = ToolReturn(id: callId, result: {_streamEventsKey: events});
      AgentMessage toolMessage = AgentMessage(
        sessionId: taskState.sessionId,
        originalTaskId: taskState.originalTaskId,
        parentTaskId: taskState.parentTaskId,
        taskId: taskState.taskId,
        role: ToolRoleType.TOOL,
        to: ToolRoleType.AGENT,
        type: ToolMessageType.TOOL_RETURN,
        content: toolReturn,
      );
      dispatcherMap.dispatch(Command(toAgent, toolMessage));
    });

    if (taskState.hasException) {
      _streamExceptionTaskInfo[taskState.taskId] =
          taskState.exceptionPayload ?? <String, dynamic>{"error": "streamCall exception"};
    }

    AgentMessage toolDoneMessage = AgentMessage(
      sessionId: taskState.sessionId,
      originalTaskId: taskState.originalTaskId,
      parentTaskId: taskState.parentTaskId,
      taskId: taskState.taskId,
      role: ToolRoleType.TOOL,
      to: ToolRoleType.AGENT,
      type: ToolMessageType.TASK_STATUS,
      content: TaskStatus(
        status: ToolStatusType.DONE,
        taskId: taskState.taskId,
        description: ToolStatusDescription(
          functionCallIdList: taskState.calls.keys.toList(),
        ).toJson(),
      ),
    );
    dispatcherMap.dispatch(Command(toAgent, toolDoneMessage));
  }

  Future<void> requestTools(AgentMessage agentMessage) async {
    List<FunctionCall> functionCallList = agentMessage.content as List<FunctionCall>;
    List<ToolDriver> drivers = getToolDriversForOriginalTask(agentMessage.originalTaskId);
    bool hasStreamCall = false;

    for (FunctionCall functionCall in functionCallList) {
      int toolIndex = drivers.indexWhere((toolDriver) => toolDriver.hasFunction(functionCall.name));
      if(toolIndex >= 0) {
        FunctionCallParam functionCallParam = FunctionCallParam(sessionId: agentMessage.sessionId, taskId: agentMessage.taskId, originalTaskId: agentMessage.originalTaskId, type: FunctionCallType.TOOL, index: toolIndex,functionCall: functionCall);
        toolPipeLine.addJob(functionCallParam);
        if (_supportsStreamCall(drivers[toolIndex], functionCall)) {
          hasStreamCall = true;
        }
      }
    }
    List<String> functionCallIdList = functionCallList.map((functionCall) => functionCall.id).toList();

    toolPipeLine.run(_requestTool, onComplete: hasStreamCall ? null : () async {
      AgentMessage toolDoneMessage = AgentMessage(
        sessionId: agentMessage.sessionId,
        originalTaskId: agentMessage.originalTaskId,
        parentTaskId: agentMessage.parentTaskId,
        taskId: agentMessage.taskId,
        role: ToolRoleType.TOOL,
        to: ToolRoleType.AGENT,
        type: ToolMessageType.TASK_STATUS,
        content: TaskStatus(status: ToolStatusType.DONE, taskId: agentMessage.taskId, description: ToolStatusDescription(functionCallIdList: functionCallIdList).toJson())
      );
      Command command = Command(toAgent, toolDoneMessage);
      dispatcherMap.dispatch(command);
    });
  }

  Future<void> _requestTool(FunctionCallParam functionCallParam) async {
    try {
      if(functionCallParam.type == null || functionCallParam.type == FunctionCallType.TOOL) {
        List<ToolDriver> drivers = getToolDriversForOriginalTask(functionCallParam.originalTaskId);
        ToolDriver toolDriver = drivers[functionCallParam.index];
        ToolReturn toolReturn;

        if (_supportsStreamCall(toolDriver, functionCallParam.functionCall)) {
          await _handleStreamToolCall(functionCallParam, toolDriver);
          return;
        } else {
          toolReturn = await toolDriver.call(functionCallParam.functionCall);
        }

        AgentMessage toolMessage = AgentMessage(
          sessionId: functionCallParam.sessionId,
          originalTaskId: functionCallParam.originalTaskId,
          parentTaskId: super.parentTaskId,
          taskId: functionCallParam.taskId,
          role: ToolRoleType.TOOL,
          to: ToolRoleType.AGENT,
          type: ToolMessageType.TOOL_RETURN,
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

  Future<void> toTool(AgentMessage agentMessage) async {
    if(agentMessage.type == ToolMessageType.TOOL_CALLS) {
      List<FunctionCall> functionCallList = agentMessage.content as List<FunctionCall>;
      List<String> functionCallIdList = functionCallList.map((functionCall) => functionCall.id).toList();
      agentSession.addListenAgentMessage(agentMessage);
      Command clientCommand = Command(
          toClient,
          AgentMessage(
            sessionId: agentMessage.sessionId,
            originalTaskId: agentMessage.originalTaskId,
            taskId: agentMessage.taskId,
            parentTaskId: agentMessage.parentTaskId,
            role: ToolRoleType.AGENT,
            to: ToolRoleType.CLIENT,
            type: ToolMessageType.TASK_STATUS,
            content: TaskStatus(status:ToolStatusType.START, taskId: agentMessage.taskId, description: ToolStatusDescription(functionCallIdList: functionCallIdList).toJson())
          ));
      dispatcherMap.dispatch(clientCommand);
      requestTools(agentMessage);
    }
  }

  @override
  Future<void> toUser(AgentMessage sessionMessage) async {
    final exceptionInfo = _streamExceptionTaskInfo.remove(sessionMessage.taskId);
    if (exceptionInfo == null) {
      return super.toUser(sessionMessage);
    }

    agentSession.addListenAgentMessage(sessionMessage);

    pipeline.completeAsync(sessionMessage.taskId);
    AgentMessage clientMessage = AgentMessage(
      sessionId: sessionMessage.sessionId,
      originalTaskId: sessionMessage.originalTaskId,
      parentTaskId: parentTaskId,
      taskId: sessionMessage.taskId,
      role: TextRoleType.AGENT,
      to: TextRoleType.CLIENT,
      type: TextMessageType.TASK_STATUS,
      content: TaskStatus(
        status: TaskStatusType.EXCEPTION,
        taskId: sessionMessage.taskId,
        description: exceptionInfo,
      ),
    );
    Command clientCommand = Command(toClient, clientMessage);
    dispatcherMap.dispatch(clientCommand);
    List<AgentMessage> taskDoneMessageList = dispatcherMap.getTaskMessageList(sessionMessage.taskId);
    agentSession.addTaskDoneAgentMessageList(taskDoneMessageList);
    timeout.start(handleIdleTimeout);
  }
}

class _StreamCallState {
  final String callId;
  final String functionName;
  final List<Map<String, dynamic>> events = [];
  final Completer<void> doneCompleter = Completer<void>();
  bool hasStart = false;
  bool terminated = false;

  _StreamCallState({required this.callId, required this.functionName});
}

class _StreamCallTaskState {
  final String sessionId;
  final String taskId;
  final String originalTaskId;
  final String? parentTaskId;
  final int timeoutSeconds;
  final Map<String, _StreamCallState> calls = {};

  int pending = 0;
  bool llmBusy = false;
  bool finalInferenceReady = false;
  bool finalInferenceStarted = false;
  bool finalInferenceDone = false;
  bool hasException = false;
  Map<String, dynamic>? exceptionPayload;
  Timer? timeoutTimer;

  _StreamCallTaskState({
    required this.sessionId,
    required this.taskId,
    required this.originalTaskId,
    required this.parentTaskId,
    required this.timeoutSeconds,
  });

  _StreamCallState getOrCreateCall(String callId, String functionName) {
    return calls.putIfAbsent(
      callId,
      () => _StreamCallState(callId: callId, functionName: functionName),
    );
  }
}
