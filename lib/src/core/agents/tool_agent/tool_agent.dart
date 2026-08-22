import 'dart:async';
import 'dart:convert';
import 'package:opentool_dart/opentool_client.dart';
import '../../llm/model.dart';
import '../../agents/text_agent/text_agent.dart';
import '../../driver/opentool/opentool_callback_driver.dart';
import '../../driver/opentool/opentool_driver.dart';
import '../../driver/tool_driver.dart';
import '../llm/exception.dart';
import '../llm/context_normalizer.dart';
import '../llm/openai_executor.dart';
import '../model.dart';
import '../pipeline/model.dart';
import '../pipeline/pipeline.dart';
import '../session_agent/dispatcher.dart';
import '../session_agent/model.dart';
import '../session_agent/task_execution_state.dart';
import '../simple_agent.dart';
import '../text_agent/model.dart';
import '../text_agent/text_agent_message_handler.dart';
import '../tool_agent/model.dart';
import 'tool_agent_message_handler.dart';

const String _streamEventsKey = "__streamEvents__";

class ToolAgent extends TextAgent {
  static const int _contextKeepMessageCount = 8;
  static const double _contextUsageThreshold = 0.7;
  static const String _summarySystemPrompt = '''
You are a conversation context compressor. Summarize the given history for future turns.
Rules:
- Keep only facts, constraints, confirmed decisions, user preferences, and open questions.
- Do not invent information.
- Be concise and structured.
- Max length: 200 words.

Output format (Markdown):
- summary: ...
- facts:
  - ...
- open_questions:
  - ...
- artifacts:
  - ...
''';

  List<ToolDriver> toolDriverList;
  late Pipeline<FunctionCallParam> toolPipeLine;
  CallbackOpenTool? callbackOpenTool;
  final int streamCallTimeoutSeconds;
  final int? toolReturnPackMinLength;
  final ToolExecutionLimits executionLimits;
  final Map<String, OpenToolCallbackDriver> _callbackToolDriverMap = {};
  final Map<String, List<ToolDriver>> _toolDriversByOriginalTaskId = {};
  final Map<String, _StreamCallTaskState> _streamTaskStateMap = {};
  final Map<String, Map<String, dynamic>> _streamExceptionTaskInfo = {};
  final Map<String, _ToolTaskExecutionState> _toolTaskStateMap = {};
  final Map<String, Set<OpenAIExecutor>> _activeLLMExecutors = {};
  final Map<String, Map<String, ToolDriver>> _activeToolCalls = {};

  ToolAgent({
    required super.sessionId,
    this.toolDriverList = const <ToolDriver>[],
    this.callbackOpenTool,
    required super.llmConfig,
    required super.agentSession,
    String? super.systemPrompt,
    super.timeoutSeconds = 3600,
    super.taskPipelineStrategy,
    String toolPipelineStrategy = PipelineStrategyType.PARALLEL,
    this.streamCallTimeoutSeconds = 60,
    this.toolReturnPackMinLength,
    this.executionLimits = const ToolExecutionLimits(),
    super.enableThinking,
  }) {
    manager.registerHandler(
        role: TextRoleType.USER,
        handler: UserMessageHandler(toLLM));
    manager.registerHandler(
        role: ToolRoleType.ASSISTANT,
        handler: LLMFunctionCallingMessageHandler(toUser, toTool));
    manager.registerHandler(
        role: ToolRoleType.TOOL, handler: ToolMessageHandler(toLLM, onToolReturn: onToolReturn));

    toolPipeLine = Pipeline(toolPipelineStrategy);
  }

  @override
  int get taskExecutionTimeoutSeconds => executionLimits.maxTaskDurationSeconds;

  bool hasPendingTaskWork(String taskId) {
    return _toolTaskStateMap.containsKey(taskId) ||
        _activeLLMExecutors.containsKey(taskId) ||
        _activeToolCalls.containsKey(taskId) ||
        _streamTaskStateMap.containsKey(taskId) ||
        _streamExceptionTaskInfo.containsKey(taskId);
  }

  _ToolTaskExecutionState _toolTaskState(String taskId) {
    return _toolTaskStateMap.putIfAbsent(
      taskId,
      _ToolTaskExecutionState.new,
    );
  }

  _ToolLimitViolation? _reserveLLMRequest(String taskId) {
    final state = _toolTaskState(taskId);
    final observed = state.llmRequests + 1;
    if (observed > executionLimits.maxLlmRequests) {
      return _ToolLimitViolation(
        limit: "maxLlmRequests",
        configured: executionLimits.maxLlmRequests,
        observed: observed,
      );
    }
    state.llmRequests = observed;
    return null;
  }

  Future<bool> reserveLLMRequest(AgentMessage agentMessage) async {
    if (!isTaskActive(agentMessage.taskId)) return false;
    final violation = _reserveLLMRequest(agentMessage.taskId);
    if (violation == null) return true;
    await _terminateForLimit(agentMessage, violation);
    return false;
  }

  _ToolLimitViolation? _reserveToolRound(
    String taskId,
    List<FunctionCall> functionCalls,
  ) {
    final state = _toolTaskState(taskId);
    final nextRoundCount = state.toolRounds + 1;
    if (nextRoundCount > executionLimits.maxToolRounds) {
      return _ToolLimitViolation(
        limit: "maxToolRounds",
        configured: executionLimits.maxToolRounds,
        observed: nextRoundCount,
      );
    }

    final nextToolCallCount = state.toolCalls + functionCalls.length;
    if (nextToolCallCount > executionLimits.maxToolCalls) {
      return _ToolLimitViolation(
        limit: "maxToolCalls",
        configured: executionLimits.maxToolCalls,
        observed: nextToolCallCount,
      );
    }

    final signature = _toolRoundSignature(functionCalls);
    final nextIdenticalRoundCount = signature == state.previousToolRoundSignature
        ? state.consecutiveIdenticalToolRounds + 1
        : 1;
    if (nextIdenticalRoundCount > executionLimits.maxConsecutiveIdenticalToolRounds) {
      return _ToolLimitViolation(
        limit: "maxConsecutiveIdenticalToolRounds",
        configured: executionLimits.maxConsecutiveIdenticalToolRounds,
        observed: nextIdenticalRoundCount,
        signature: signature,
      );
    }

    state
      ..toolRounds = nextRoundCount
      ..toolCalls = nextToolCallCount
      ..previousToolRoundSignature = signature
      ..consecutiveIdenticalToolRounds = nextIdenticalRoundCount;
    return null;
  }

  String _toolRoundSignature(List<FunctionCall> functionCalls) {
    final signatures = functionCalls.map((functionCall) {
      return jsonEncode({
        "name": functionCall.name,
        "arguments": _canonicalizeJson(functionCall.arguments),
      });
    }).toList()
      ..sort();
    return signatures.join("|");
  }

  dynamic _canonicalizeJson(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {
        for (final key in keys) key: _canonicalizeJson(value[key]),
      };
    }
    if (value is List) {
      return value.map(_canonicalizeJson).toList();
    }
    return value;
  }

  Future<void> _terminateForLimit(
    AgentMessage agentMessage,
    _ToolLimitViolation violation,
  ) async {
    await finishTask(
      taskId: agentMessage.taskId,
      status: TaskStatusType.EXCEPTION,
      description: violation.toJson(),
    );
  }

  void _registerLLMExecutor(String taskId, OpenAIExecutor executor) {
    _activeLLMExecutors.putIfAbsent(taskId, () => {}).add(executor);
  }

  void _unregisterLLMExecutor(String taskId, OpenAIExecutor executor) {
    final executors = _activeLLMExecutors[taskId];
    executors?.remove(executor);
    if (executors?.isEmpty ?? false) {
      _activeLLMExecutors.remove(taskId);
    }
  }

  void registerActiveToolCall(
    String taskId,
    String functionCallId,
    ToolDriver driver,
  ) {
    _activeToolCalls.putIfAbsent(taskId, () => {})[functionCallId] = driver;
  }

  void unregisterActiveToolCall(String taskId, String functionCallId) {
    final calls = _activeToolCalls[taskId];
    calls?.remove(functionCallId);
    if (calls?.isEmpty ?? false) {
      _activeToolCalls.remove(taskId);
    }
  }

  @override
  Future<void> onTaskTerminating(TaskExecutionState state) async {
    toolPipeLine.removeWhere((job) => job.taskId == state.taskId);

    final streamState = _streamTaskStateMap.remove(state.taskId);
    streamState?.timeoutTimer?.cancel();
    if (streamState != null) {
      for (final callState in streamState.calls.values) {
        callState.terminated = true;
        if (!callState.doneCompleter.isCompleted) {
          callState.doneCompleter.complete();
        }
      }
    }
    _streamExceptionTaskInfo.remove(state.taskId);

    final executors = _activeLLMExecutors.remove(state.taskId)?.toList() ?? const [];
    final activeCalls = _activeToolCalls.remove(state.taskId) ?? const <String, ToolDriver>{};

    await Future.wait([
      ...executors.map((executor) => _ignoreCancellationError(executor.cancel())),
      ...activeCalls.entries.map(
        (entry) => _ignoreCancellationError(entry.value.cancel(entry.key)),
      ),
    ]);

    _toolTaskStateMap.remove(state.taskId);
    final callbackDriver = _callbackToolDriverMap.remove(state.originalTaskId);
    if (callbackDriver != null) {
      callbackOpenTool?.releaseClientDriver?.call(sessionId, callbackDriver);
    }
    _toolDriversByOriginalTaskId.remove(state.originalTaskId);
    await super.onTaskTerminating(state);
  }

  Future<void> _ignoreCancellationError(Future<void> cancellation) async {
    try {
      await cancellation;
    } catch (_) {
      // Task termination is best-effort across third-party drivers.
    }
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

  int? get resolvedToolReturnPackMinLength {
    final configured = toolReturnPackMinLength;
    if (configured == null) return 800;
    if (configured <= 0) return null;
    return configured;
  }

  @override
  Future<void> toAgent(AgentMessage agentMessage) async {
    if (!isTaskActive(agentMessage.taskId)) return;
    if (agentMessage.role == ToolRoleType.ASSISTANT &&
        agentMessage.type == ToolMessageType.TOOL_CALLS) {
      final functionCalls = agentMessage.content as List<FunctionCall>;
      final violation = _reserveToolRound(agentMessage.taskId, functionCalls);
      if (violation != null) {
        await _terminateForLimit(agentMessage, violation);
        return;
      }
    }
    agentSession.addListenAgentMessage(agentMessage);
    Command? nextCommand = manager.handleMessage(agentMessage);
    if (nextCommand != null) dispatcherMap.dispatch(nextCommand);
  }

  @override
  Future<List<AgentMessage>> prepareAgentLLMMessageList(AgentMessage agentMessage) async {
    List<AgentMessage> sessionMessageList =
        List<AgentMessage>.from(agentSession.taskDoneAgentMessageList);
    List<AgentMessage> taskMessageList = dispatcherMap.getTaskMessageList(agentMessage.taskId);

    List<AgentMessage> sessionContextMessages = _filterContextMessages(sessionMessageList);
    List<AgentMessage> taskContextMessages = _filterContextMessages(taskMessageList);

    bool shouldSummarize = _shouldSummarize();
    if (shouldSummarize) {
      await _updateSessionSummary(sessionContextMessages);
    }

    List<AgentMessage> agentLLMMessageList = [];
    if (shouldSummarize && agentSession.sessionSummary?.isNotEmpty == true) {
      agentLLMMessageList.add(_buildSummaryMessage(agentMessage, agentSession.sessionSummary!));
      if (sessionContextMessages.length > _contextKeepMessageCount) {
        sessionContextMessages = sessionContextMessages.sublist(
          sessionContextMessages.length - _contextKeepMessageCount,
        );
      }
    }

    agentLLMMessageList.addAll(sessionContextMessages);
    agentLLMMessageList.addAll(taskContextMessages);
    return agentLLMMessageList;
  }

  @override
  Future<void> toLLM(AgentMessage agentMessage) async {
    if (!await reserveLLMRequest(agentMessage)) return;
    agentSession.addListenAgentMessage(agentMessage);
    final LLMConfig? effectiveLLMConfig =
        resolveTaskLLMConfig(agentMessage.originalTaskId, defaultLLMConfig: llmConfig);
    if (effectiveLLMConfig == null) {
      pushException(
        agentMessage.sessionId,
        agentMessage.taskId,
        agentMessage.originalTaskId,
        jsonEncode(LLMException(message: "LLM config is required").toJson()),
      );
      return;
    }

    final drivers = await prepareToolDrivers(agentMessage);
    await Future.wait(drivers.map((driver) => driver.init()));
    if (!isTaskActive(agentMessage.taskId)) return;
    List<FunctionModel> functionModelList =
        await buildAvailableFunctionModelList(agentMessage, drivers);

    final executor = OpenAIExecutor(
      effectiveLLMConfig,
      toolReturnPackMinLength: resolvedToolReturnPackMinLength,
    );
    _registerLLMExecutor(agentMessage.taskId, executor);
    bool streamListenerStarted = false;

    try {
      List<AgentMessage> agentLLMMessageList = await prepareAgentLLMMessageList(agentMessage);
      if (!isTaskActive(agentMessage.taskId)) return;
      if (super.agentSession.isStream) {
        Stream<AgentMessage> agentMessageStream = await executor.requestByStream(
            agentMessageList: agentLLMMessageList,
            functionModelList: functionModelList,
            enableThinking: enableThinking,
            listenChunk: listenChunk);
        if (!isTaskActive(agentMessage.taskId)) return;
        agentMessageStream.listen((newAgentMessage) {
          if (!isTaskActive(agentMessage.taskId)) return;
          Command nextCommand = Command(toAgent, newAgentMessage);
          dispatcherMap.dispatch(nextCommand);
        }, onDone: () {
          _unregisterLLMExecutor(agentMessage.taskId, executor);
        }, onError: (e) {
          _unregisterLLMExecutor(agentMessage.taskId, executor);
          if (!isTaskActive(agentMessage.taskId)) return;
          pushException(agentMessage.sessionId, agentMessage.taskId, agentMessage.originalTaskId,
              e.toString());
        });
        streamListenerStarted = true;
      } else {
        AgentMessage llmMessage = await executor.request(
            agentMessageList: agentLLMMessageList,
            functionModelList: functionModelList,
            enableThinking: enableThinking);
        if (!isTaskActive(agentMessage.taskId)) return;
        Command nextCommand = Command(toAgent, llmMessage);
        dispatcherMap.dispatch(nextCommand);
      }
    } on LLMException catch (e) {
      if (!isTaskActive(agentMessage.taskId)) return;
      pushException(agentMessage.sessionId, agentMessage.taskId, agentMessage.originalTaskId,
          jsonEncode(e.toJson()));
    } finally {
      if (!streamListenerStarted) {
        _unregisterLLMExecutor(agentMessage.taskId, executor);
      }
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

  Future<List<FunctionModel>> buildAvailableFunctionModelList(
    AgentMessage agentMessage,
    List<ToolDriver> drivers,
  ) {
    return buildFunctionModelList(drivers);
  }

  Future<OpenToolCallbackDriver> buildClientDriver(AgentMessage agentMessage) async {
    OpenTool opentool = await OpenToolJsonLoader().load(this.callbackOpenTool!.opentool);
    void Function(FunctionCall functionCall) listenClientFunctionCall =
        (FunctionCall functionCall) {
      if (!isTaskActive(agentMessage.taskId)) return;
      AgentMessage clientMessage = AgentMessage(
          sessionId: agentMessage.sessionId,
          originalTaskId: agentMessage.originalTaskId,
          parentTaskId: agentMessage.parentTaskId,
          taskId: agentMessage.taskId,
          role: ToolRoleType.AGENT,
          to: ToolRoleType.CLIENT,
          type: ToolMessageType.FUNCTION_CALL,
          content: functionCall);
      Command functionCallCommand = Command(toAgent, clientMessage);
      dispatcherMap.dispatch(functionCallCommand);
    };
    return OpenToolCallbackDriver(opentool, listenClientFunctionCall,
        timeout: callbackOpenTool!.timeout ?? 60);
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

  Future<void> _handleStreamToolCall(
      FunctionCallParam functionCallParam, ToolDriver toolDriver) async {
    if (!isTaskActive(functionCallParam.taskId)) return;
    final taskState = _getOrCreateStreamTaskState(functionCallParam);
    final callState = taskState.getOrCreateCall(
      functionCallParam.functionCall.id,
      functionCallParam.functionCall.name,
    );
    _resetStreamTimeout(taskState);

    void onStream(String event, ToolReturn toolReturn) {
      if (!isTaskActive(functionCallParam.taskId)) return;
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
    if (!isTaskActive(taskState.taskId)) return;
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
    if (!isTaskActive(taskState.taskId)) return;
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
    if (!isTaskActive(taskState.taskId)) return;
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
    if (!isTaskActive(taskState.taskId)) return;
    taskState.timeoutTimer?.cancel();
    taskState.timeoutTimer = Timer(
      Duration(seconds: taskState.timeoutSeconds),
      () => _handleStreamTimeout(taskState),
    );
  }

  void _handleStreamTimeout(_StreamCallTaskState taskState) {
    if (!isTaskActive(taskState.taskId)) return;
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
    if (!isTaskActive(taskState.taskId)) return;
    if (taskState.llmBusy) return;
    taskState.llmBusy = true;
    Future(() async {
      try {
        while (true) {
          if (!isTaskActive(taskState.taskId)) break;
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

  Future<List<AgentMessage>> _buildStreamMessageList(_StreamCallTaskState taskState) async {
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

    final messageList = await prepareAgentLLMMessageList(anchorMessage);
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
    if (!isTaskActive(taskState.taskId)) return;
    final drivers = getToolDriversForOriginalTask(taskState.originalTaskId);
    final functionModelList = await buildFunctionModelList(drivers);
    final messageList = await _buildStreamMessageList(taskState);
    final LLMConfig? effectiveLLMConfig =
        resolveTaskLLMConfig(taskState.originalTaskId, defaultLLMConfig: llmConfig);
    if (effectiveLLMConfig == null) {
      pushException(
        taskState.sessionId,
        taskState.taskId,
        taskState.originalTaskId,
        jsonEncode(LLMException(message: "LLM config is required").toJson()),
      );
      return;
    }

    final limit = _reserveLLMRequest(taskState.taskId);
    if (limit != null) {
      await finishTask(
        taskId: taskState.taskId,
        status: TaskStatusType.EXCEPTION,
        description: limit.toJson(),
      );
      return;
    }

    final executor = OpenAIExecutor(
      effectiveLLMConfig,
      toolReturnPackMinLength: resolvedToolReturnPackMinLength,
    );
    _registerLLMExecutor(taskState.taskId, executor);
    try {
      final stream = await executor.requestByStream(
        agentMessageList: messageList,
        functionModelList: functionModelList,
        enableThinking: enableThinking,
        listenChunk: listenChunk,
      );

      final completer = Completer<void>();
      stream.listen(
        (message) async {
          if (!isTaskActive(taskState.taskId)) return;
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
        onDone: () {
          _unregisterLLMExecutor(taskState.taskId, executor);
          if (!completer.isCompleted) completer.complete();
        },
        onError: (e) {
          _unregisterLLMExecutor(taskState.taskId, executor);
          if (!isTaskActive(taskState.taskId)) {
            if (!completer.isCompleted) completer.complete();
            return;
          }
          pushException(
              taskState.sessionId, taskState.taskId, taskState.originalTaskId, e.toString());
          if (!completer.isCompleted) completer.complete();
        },
      );
      await completer.future;
    } on LLMException catch (e) {
      _unregisterLLMExecutor(taskState.taskId, executor);
      if (!isTaskActive(taskState.taskId)) return;
      pushException(
          taskState.sessionId, taskState.taskId, taskState.originalTaskId, jsonEncode(e.toJson()));
    }
  }

  Future<void> _runFinalStreamInference(_StreamCallTaskState taskState) async {
    if (!isTaskActive(taskState.taskId)) return;
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
    if (!isTaskActive(agentMessage.taskId)) return;
    List<FunctionCall> functionCallList = agentMessage.content as List<FunctionCall>;
    List<ToolDriver> drivers = getToolDriversForOriginalTask(agentMessage.originalTaskId);
    bool hasStreamCall = false;

    for (FunctionCall functionCall in functionCallList) {
      int toolIndex = drivers.indexWhere((toolDriver) => toolDriver.hasFunction(functionCall.name));
      if (toolIndex >= 0) {
        FunctionCallParam functionCallParam = FunctionCallParam(
            sessionId: agentMessage.sessionId,
            taskId: agentMessage.taskId,
            originalTaskId: agentMessage.originalTaskId,
            type: FunctionCallType.TOOL,
            index: toolIndex,
            functionCall: functionCall);
        toolPipeLine.addJob(functionCallParam);
        if (_supportsStreamCall(drivers[toolIndex], functionCall)) {
          hasStreamCall = true;
        }
      }
    }
    List<String> functionCallIdList =
        functionCallList.map((functionCall) => functionCall.id).toList();

    toolPipeLine.run(_requestTool,
        onComplete: hasStreamCall
            ? null
            : () async {
                if (!isTaskActive(agentMessage.taskId)) return;
                AgentMessage toolDoneMessage = AgentMessage(
                    sessionId: agentMessage.sessionId,
                    originalTaskId: agentMessage.originalTaskId,
                    parentTaskId: agentMessage.parentTaskId,
                    taskId: agentMessage.taskId,
                    role: ToolRoleType.TOOL,
                    to: ToolRoleType.AGENT,
                    type: ToolMessageType.TASK_STATUS,
                    content: TaskStatus(
                        status: ToolStatusType.DONE,
                        taskId: agentMessage.taskId,
                        description: ToolStatusDescription(functionCallIdList: functionCallIdList)
                            .toJson()));
                Command command = Command(toAgent, toolDoneMessage);
                dispatcherMap.dispatch(command);
              });
  }

  Future<void> _requestTool(FunctionCallParam functionCallParam) async {
    if (!isTaskActive(functionCallParam.taskId)) return;
    try {
      if (functionCallParam.type == null || functionCallParam.type == FunctionCallType.TOOL) {
        List<ToolDriver> drivers = getToolDriversForOriginalTask(functionCallParam.originalTaskId);
        ToolDriver toolDriver = drivers[functionCallParam.index];
        ToolReturn toolReturn;
        registerActiveToolCall(
          functionCallParam.taskId,
          functionCallParam.functionCall.id,
          toolDriver,
        );

        try {
          if (_supportsStreamCall(toolDriver, functionCallParam.functionCall)) {
            await _handleStreamToolCall(functionCallParam, toolDriver);
            return;
          } else {
            toolReturn = await toolDriver.call(functionCallParam.functionCall);
          }
        } finally {
          unregisterActiveToolCall(
            functionCallParam.taskId,
            functionCallParam.functionCall.id,
          );
        }

        if (!isTaskActive(functionCallParam.taskId)) return;
        AgentMessage toolMessage = AgentMessage(
            sessionId: functionCallParam.sessionId,
            originalTaskId: functionCallParam.originalTaskId,
            parentTaskId: super.parentTaskId,
            taskId: functionCallParam.taskId,
            role: ToolRoleType.TOOL,
            to: ToolRoleType.AGENT,
            type: ToolMessageType.TOOL_RETURN,
            content: toolReturn);
        Command command = Command(toAgent, toolMessage);
        dispatcherMap.dispatch(command);
      }
    } on ToolBreakException catch (e) {
      /** When toolDriver.call throw ToolBreakException, it will break task.*/
      await finishTask(
        taskId: functionCallParam.taskId,
        status: TaskStatusType.EXCEPTION,
        description: {"error": e.toString()},
      );
      throw e;
    }
  }

  Future<void> toTool(AgentMessage agentMessage) async {
    if (!isTaskActive(agentMessage.taskId)) return;
    if (agentMessage.type == ToolMessageType.TOOL_CALLS) {
      List<FunctionCall> functionCallList = agentMessage.content as List<FunctionCall>;
      List<String> functionCallIdList =
          functionCallList.map((functionCall) => functionCall.id).toList();
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
              content: TaskStatus(
                  status: ToolStatusType.START,
                  taskId: agentMessage.taskId,
                  description:
                      ToolStatusDescription(functionCallIdList: functionCallIdList).toJson())));
      dispatcherMap.dispatch(clientCommand);
      requestTools(agentMessage);
    }
  }

  @override
  Future<void> toUser(AgentMessage sessionMessage) async {
    if (!isTaskActive(sessionMessage.taskId)) return;
    final exceptionInfo = _streamExceptionTaskInfo.remove(sessionMessage.taskId);
    if (exceptionInfo == null) {
      return super.toUser(sessionMessage);
    }

    agentSession.addListenAgentMessage(sessionMessage);

    await finishTask(
      taskId: sessionMessage.taskId,
      status: TaskStatusType.EXCEPTION,
      description: exceptionInfo,
      saveTaskHistory: true,
    );
  }

  bool _shouldSummarize() {
    int? contextWindowSize = llmConfig?.contextWindowSize;
    if (contextWindowSize == null || contextWindowSize <= 0) return false;
    int? promptTokens = _lastPromptTokens();
    if (promptTokens == null) return false;
    double ratio = promptTokens / contextWindowSize;
    return ratio >= _contextUsageThreshold;
  }

  int? _lastPromptTokens() {
    for (final message in agentSession.taskDoneAgentMessageList.reversed) {
      final usage = message.completions?.tokenUsage;
      if (usage != null) return usage.promptTokens;
    }
    return null;
  }

  Future<void> _updateSessionSummary(List<AgentMessage> sessionContextMessages) async {
    if (sessionContextMessages.length <= _contextKeepMessageCount) return;

    int cutoff = sessionContextMessages.length - _contextKeepMessageCount;
    if (cutoff == agentSession.summaryMessageCount &&
        agentSession.sessionSummary?.isNotEmpty == true) {
      return;
    }

    String summaryInput = _formatMessagesForSummary(
      sessionContextMessages.sublist(0, cutoff),
    );
    if (summaryInput.isEmpty) return;

    try {
      if (llmConfig == null) return;
      SimpleAgent summarizer =
          SimpleAgent(llmConfig: llmConfig, systemPrompt: _summarySystemPrompt);
      AgentMessage result = await summarizer.userToAgent(
        contentList: [Content(type: ContentType.TEXT, message: summaryInput)],
      );
      String summary = (result.content as String).trim();
      if (summary.isNotEmpty) {
        agentSession.sessionSummary = summary;
        agentSession.summaryMessageCount = cutoff;
      }
    } catch (_) {
      // If summary fails, keep existing context to avoid breaking requests.
    }
  }

  List<AgentMessage> _filterContextMessages(List<AgentMessage> messages) {
    List<AgentMessage> filtered = [];
    for (final sessionMessage in messages) {
      if (sessionMessage.role == TextRoleType.DEVELOPER ||
          sessionMessage.role == TextRoleType.ASSISTANT ||
          sessionMessage.to == TextRoleType.ASSISTANT ||
          sessionMessage.role == ToolRoleType.TOOL) {
        filtered.add(sessionMessage);
      }
    }
    return normalizeReasoningContext(filtered);
  }

  AgentMessage _buildSummaryMessage(AgentMessage anchor, String summary) {
    return AgentMessage(
      sessionId: anchor.sessionId,
      originalTaskId: anchor.originalTaskId,
      parentTaskId: anchor.parentTaskId,
      taskId: anchor.taskId,
      role: TextRoleType.DEVELOPER,
      to: TextRoleType.ASSISTANT,
      type: TextMessageType.TEXT,
      content: 'Session summary:\\n$summary',
    );
  }

  String _formatMessagesForSummary(List<AgentMessage> messages) {
    final buffer = StringBuffer();
    for (final message in messages) {
      final text = _contentToText(message);
      if (text.isEmpty) continue;
      buffer.writeln('${_roleLabel(message)}: $text');
    }
    return buffer.toString().trim();
  }

  String _roleLabel(AgentMessage message) {
    if (message.role == TextRoleType.USER) return 'User';
    if (message.role == TextRoleType.ASSISTANT) return 'Assistant';
    if (message.role == ToolRoleType.TOOL) return 'Tool';
    if (message.role == TextRoleType.DEVELOPER) return 'System';
    return 'Other';
  }

  String _contentToText(AgentMessage message) {
    final content = message.content;
    if (content is String) return content.trim();
    if (content is List<Content>) {
      return content
          .map((item) {
            if (item.type == ContentType.TEXT) return item.message;
            if (item.type == ContentType.IMAGE_URL) return '[image] ${item.message}';
            return item.message;
          })
          .join('\\n')
          .trim();
    }
    try {
      return jsonEncode(content);
    } catch (_) {
      return '';
    }
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

class _ToolTaskExecutionState {
  int llmRequests = 0;
  int toolRounds = 0;
  int toolCalls = 0;
  int consecutiveIdenticalToolRounds = 0;
  String? previousToolRoundSignature;
}

class _ToolLimitViolation {
  final String limit;
  final int configured;
  final int observed;
  final String? signature;

  const _ToolLimitViolation({
    required this.limit,
    required this.configured,
    required this.observed,
    this.signature,
  });

  Map<String, dynamic> toJson() => {
        "code": "tool_loop_limit_exceeded",
        "limit": limit,
        "configured": configured,
        "observed": observed,
        if (signature != null) "signature": signature,
      };
}
