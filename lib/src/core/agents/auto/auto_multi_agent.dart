import 'dart:async';
import 'dart:convert';
import '../../driver/tool_driver.dart';
import '../model.dart';
import '../session_agent/model.dart';
import '../session_agent/session.dart';
import '../tool_agent/tool_agent.dart';
import '../reflection/model.dart';
import '../pipeline/model.dart';
import 'planner/planner.dart';
import 'executor/executor.dart';
import 'summarizer/summarizer.dart';
import 'package:opentool_dart/opentool_client.dart' as ot;
import '../../llm/model.dart';
import '../../driver/opentool/opentool_callback_driver.dart';
import 'wrappers/function.dart';
import 'models/node.dart';
import 'wrappers/llm.dart';
import '../multi_agent/model.dart';
import '../tool_agent/model.dart';
import 'package:unique_id_dart/unique_id_dart.dart';

abstract class AutoMessageSender {
  Future<void> sendAgentMessage(AgentMessage message);

  Future<void> sendFunctionCallStart(String taskId, ot.FunctionCall call);

  Future<void> sendFunctionCallDone(
      String taskId, ot.FunctionCall call, String result);
}

class AutoMultiAgent extends ToolAgent implements AutoMessageSender {
  late final AutoTaskPlanner taskPlanner;

  late final AutoNodeExecutor nodeExecutor;

  late final AutoSummarizer summarizer;

  final List<IndexedLLMConfig> indexedLLMConfigs = [];

  final List<IndexedFunction> indexedFunctions = [];

  String originalTaskId = "";

  AutoMultiAgent._internal({
    required super.sessionId,
    required super.toolDriverList,
    super.callbackOpenTool,
    required super.llmConfig,
    required super.agentSession,
    super.systemPrompt,
    super.timeoutSeconds = 3600,
    super.streamCallTimeoutSeconds,
    super.toolReturnPackMinLength,
    List<ReflectPrompt> toolReflectPromptList = const [],
    String taskPipelineStrategy = PipelineStrategyType.PARALLEL,
    String toolPipelineStrategy = PipelineStrategyType.PARALLEL,
    super.enableThinking,
    List<LLMConfig>? llmConfigList,
  }) : super(
            toolReflectPromptList: toolReflectPromptList,
            taskPipelineStrategy: taskPipelineStrategy,
            toolPipelineStrategy: toolPipelineStrategy) {}

  static Future<AutoMultiAgent> create({
    required String sessionId,
    required List<ToolDriver> toolDriverList,
    CallbackOpenTool? clientOpenTool,
    required LLMConfig? llmConfig,
    required AgentSession agentSession,
    String? systemPrompt,
    int timeoutSeconds = 3600,
    int streamCallTimeoutSeconds = 60,
    List<ReflectPrompt> toolReflectPromptList = const [],
    String taskPipelineStrategy = PipelineStrategyType.PARALLEL,
    String toolPipelineStrategy = PipelineStrategyType.PARALLEL,
    bool? enableThinking,
    List<LLMConfig>? llmConfigList,
    int? toolReturnPackMinLength,
  }) async {
    try {
      AutoMultiAgent instance = AutoMultiAgent._internal(
        sessionId: sessionId,
        toolDriverList: toolDriverList,
        callbackOpenTool: clientOpenTool,
        llmConfig: llmConfig,
        agentSession: agentSession,
        systemPrompt: systemPrompt,
        timeoutSeconds: timeoutSeconds,
        streamCallTimeoutSeconds: streamCallTimeoutSeconds,
        toolReflectPromptList: toolReflectPromptList,
        taskPipelineStrategy: taskPipelineStrategy,
        toolPipelineStrategy: toolPipelineStrategy,
        enableThinking: enableThinking,
        llmConfigList: llmConfigList,
        toolReturnPackMinLength: toolReturnPackMinLength,
      );

      instance._initializeIndexedLLMConfigs(llmConfigList);

      await instance._initializeIndexedFunctions();

      instance._initializeComponents();

      instance._printInitializationInfo();

      return instance;
    } catch (e) {
      throw Exception('AutoMultiAgent init error: $e');
    }
  }

  void _initializeComponents() {
    taskPlanner = AutoTaskPlanner(
      plannerLLMConfig: llmConfig,
      messageSender: this,
    );

    nodeExecutor = AutoNodeExecutor(
      indexedFunctions: indexedFunctions,
      messageSender: this,
      callbackOpenTool: callbackOpenTool,
    );

    summarizer = AutoSummarizer(
      summarizerLLMConfig: llmConfig,
      messageSender: this,
    );
  }

  void _printInitializationInfo() {
    print('=== AutoMultiAgent available LLM models ===');
    for (IndexedLLMConfig indexedLLMConfig in indexedLLMConfigs) {
      print(
          '${indexedLLMConfig.index}: ${indexedLLMConfig.llmConfig.model} - ${indexedLLMConfig.description ?? "general model"}');
    }

    print('=== AutoMultiAgent available functions ===');
    for (IndexedFunction indexedFunction in indexedFunctions) {
      print(
          '${indexedFunction.index}: ${indexedFunction.functionModel.name} - ${indexedFunction.functionModel.description}');
    }
  }

  @override
  Future<void> userToAgent(
      {required List<Content> contentList,
      bool? stream,
      String? originalTaskId,
      String? parentTaskId,
      LLMConfig? requestLLMConfig,
      void Function(String taskId)? fetchTaskId}) async {
    timeout.clear();
    this.parentTaskId = parentTaskId;
    String taskId = uniqueId();
    if (fetchTaskId != null) fetchTaskId(taskId);
    dispatcherMap.create(taskId);
    originalTaskId = originalTaskId ?? taskId;
    this.originalTaskId = originalTaskId;
    if (requestLLMConfig != null) {
      setTaskLLMConfig(originalTaskId, requestLLMConfig);
    }

    try {
      _executeAutoMode(taskId, originalTaskId, contentList);
    } catch (e, s) {
      _sendDoneMessage(
        taskId,
        originalTaskId,
        'error occurred during execution: $e\n$s',
      );
    }
  }

  @override
  void stop({String? originalTaskId, String? taskId}) {
    try {
      taskPlanner.stop();
      nodeExecutor.stop();
      summarizer.stop();
    } catch (e) {
      print('stop error');
    }

    super.stop(originalTaskId: originalTaskId, taskId: taskId);
  }

  @override
  void clear() {
    try {
      taskPlanner.clear();
      nodeExecutor.clear();
      summarizer.clear();
    } catch (e) {
      print('clear error');
    }

    super.clear();
  }

  void _initializeIndexedLLMConfigs(List<LLMConfig>? llmConfigList) {
    indexedLLMConfigs.clear();

    if (llmConfigList != null && llmConfigList.isNotEmpty) {
      for (int i = 0; i < llmConfigList.length; i++) {
        indexedLLMConfigs.add(IndexedLLMConfig(
          index: i,
          llmConfig: llmConfigList[i],
          description: "",
        ));
      }
    } else {
      // if no LLM config list is provided, use the main llmConfig when available.
      if (llmConfig != null) {
        indexedLLMConfigs.add(IndexedLLMConfig(
          index: 0,
          llmConfig: llmConfig!,
          description: 'main model',
        ));
      }
    }
  }

  Future<void> _initializeIndexedFunctions() async {
    indexedFunctions.clear();
    int currentIndex = 0;

    await Future.wait(toolDriverList.map((driver) => driver.init()));

    for (ToolDriver toolDriver in toolDriverList) {
      List<ot.FunctionModel> functionModels = toolDriver.parse();

      for (ot.FunctionModel functionModel in functionModels) {
        indexedFunctions.add(IndexedFunction(
          index: currentIndex,
          functionModel: functionModel,
          toolDriver: toolDriver,
        ));
        currentIndex++;
      }
    }

    if (callbackOpenTool != null) {
      ot.OpenTool opentool =
          await ot.OpenToolJsonLoader().load(callbackOpenTool!.opentool);
      OpenToolCallbackDriver callbackDriver =
          OpenToolCallbackDriver(opentool, (_) {},
              timeout: callbackOpenTool!.timeout ?? 60);
      List<ot.FunctionModel> callbackFunctions = callbackDriver.parse();

      for (ot.FunctionModel functionModel in callbackFunctions) {
        indexedFunctions.add(IndexedFunction(
          index: currentIndex,
          functionModel: functionModel,
          toolDriver: callbackDriver,
        ));
        currentIndex++;
      }
    }
  }

  Future<void> _executeAutoMode(
      String taskId, String originalTaskId, List<Content> contentList) async {
    await Future.delayed(Duration(seconds: 1));
    final LLMConfig? effectiveLLMConfig =
        resolveTaskLLMConfig(originalTaskId, defaultLLMConfig: llmConfig);
    if (effectiveLLMConfig == null) {
      throw Exception("LLM config is required for auto task");
    }
    final List<IndexedLLMConfig> taskIndexedLLMConfigs = indexedLLMConfigs
        .map((e) => IndexedLLMConfig(
              index: e.index,
              llmConfig: e.llmConfig,
              description: e.description,
            ))
        .toList();
    if (taskIndexedLLMConfigs.isEmpty) {
      taskIndexedLLMConfigs.add(
        IndexedLLMConfig(
          index: 0,
          llmConfig: effectiveLLMConfig,
          description: 'request model',
        ),
      );
    }

    String userCommand = _extractUserCommand(contentList);

    _sendStartMessage(taskId, originalTaskId, contentList);

    String planningResult = await taskPlanner.planTasks(
      userCommand: userCommand,
      indexedLLMConfigs: taskIndexedLLMConfigs,
      indexedFunctions: indexedFunctions,
      taskId: taskId,
      requestLLMConfig: effectiveLLMConfig,
    );

    String cleanedResult = taskPlanner.cleanPlanningResult(planningResult);

    if (!taskPlanner.validatePlanningResult(cleanedResult)) {
      _sendDoneMessage(taskId, originalTaskId, cleanedResult);
      return;
    }

    List<dynamic> planningJson = jsonDecode(cleanedResult);
    List<AutoTaskNode> taskNodes = planningJson
        .map((json) => AutoTaskNode.fromJson(json as Map<String, dynamic>))
        .toList();
    if (taskNodes.isEmpty) {
      _sendDoneMessage(taskId, originalTaskId, cleanedResult);
      return;
    }

    List<AutoTaskNode> completedNodes = await nodeExecutor.executeNodeTree(
      taskNodes,
      taskId,
      indexedLLMConfigs: taskIndexedLLMConfigs,
    );

    String summary = await summarizer.generateSummary(
      userCommand: userCommand,
      completedNodes: completedNodes,
      taskId: taskId,
      requestLLMConfig: effectiveLLMConfig,
    );

    await _sendDoneMessage(taskId, originalTaskId, summary);
  }

  String _extractUserCommand(List<Content> contentList) {
    return contentList
        .where((content) => content.type == ContentType.TEXT)
        .map((content) => content.message)
        .join(' ')
        .trim();
  }

  Future<void> _sendStartMessage(
      String taskId, String originalTaskId, List<Content> contentList) async {

    AgentMessage userMessage = AgentMessage(
        sessionId: sessionId,
        originalTaskId: originalTaskId,
        parentTaskId: parentTaskId,
        taskId: taskId,
        role: SessionRoleType.USER,
        to: SessionRoleType.AGENT,
        type: SessionMessageType.CONTENT_LIST,
        content: contentList);
    await sendAgentMessage(userMessage);

    AgentMessage clientMessage = AgentMessage(
        sessionId: sessionId,
        originalTaskId: originalTaskId,
        parentTaskId: parentTaskId,
        taskId: taskId,
        role: SessionRoleType.AGENT,
        to: SessionRoleType.CLIENT,
        type: SessionMessageType.TASK_STATUS,
        content: TaskStatus(status: TaskStatusType.START, taskId: taskId));
    await sendAgentMessage(clientMessage);
  }

  Future<void> _sendDoneMessage(
      String taskId, String originalTaskId, String finalResult) async {
    clearTaskLLMConfig(originalTaskId);
    AgentMessage userMessage = AgentMessage(
        sessionId: sessionId,
        originalTaskId: originalTaskId,
        parentTaskId: parentTaskId,
        taskId: taskId,
        role: SessionRoleType.AGENT,
        to: SessionRoleType.USER,
        type: SessionMessageType.TEXT,
        content: finalResult);
    await sendAgentMessage(userMessage);

    AgentMessage clientMessage = AgentMessage(
        sessionId: sessionId,
        originalTaskId: originalTaskId,
        parentTaskId: parentTaskId,
        taskId: taskId,
        role: SessionRoleType.AGENT,
        to: SessionRoleType.CLIENT,
        type: SessionMessageType.TASK_STATUS,
        content: TaskStatus(status: TaskStatusType.DONE, taskId: taskId));
    await sendAgentMessage(clientMessage);
    timeout.start(handleIdleTimeout);
  }

  @override
  Future<void> sendAgentMessage(AgentMessage message) async {
    await agentSession.addListenAgentMessage(message);
  }

  @override
  Future<void> sendFunctionCallStart(
      String taskId, ot.FunctionCall call) async {
    AgentMessage subAgentMessage = AgentMessage(
        sessionId: sessionId,
        originalTaskId: originalTaskId,
        parentTaskId: parentTaskId,
        taskId: taskId,
        role: MultiAgentRoleType.AGENT,
        to: MultiAgentRoleType.SUBAGENT,
        type: MultiAgentMessageType.TOOL_CALLS,
        content: [call]);
    sendAgentMessage(subAgentMessage);

    AgentMessage clientMessage = AgentMessage(
        sessionId: sessionId,
        originalTaskId: originalTaskId,
        parentTaskId: parentTaskId,
        taskId: taskId,
        role: MultiAgentRoleType.AGENT,
        to: MultiAgentRoleType.CLIENT,
        type: MultiAgentMessageType.TASK_STATUS,
        content: TaskStatus(
            status: MultiAgentStatusType.START,
            taskId: taskId,
            description:
                ToolStatusDescription(functionCallIdList: [call.id]).toJson()));
    sendAgentMessage(clientMessage);
  }

  @override
  Future<void> sendFunctionCallDone(
      String taskId, ot.FunctionCall call, String result) async {
    AgentMessage subAgentReturnMessage = AgentMessage(
        sessionId: sessionId,
        originalTaskId: originalTaskId,
        parentTaskId: parentTaskId,
        taskId: taskId,
        role: MultiAgentRoleType.SUBAGENT,
        to: MultiAgentRoleType.AGENT,
        type: MultiAgentMessageType.TOOL_RETURN,
        content: ot.ToolReturn(id: call.id, result: {"result": result}));
    sendAgentMessage(subAgentReturnMessage);

    AgentMessage subAgentStatusMessage = AgentMessage(
        sessionId: sessionId,
        originalTaskId: originalTaskId,
        parentTaskId: parentTaskId,
        taskId: taskId,
        role: MultiAgentRoleType.SUBAGENT,
        to: MultiAgentRoleType.AGENT,
        type: MultiAgentMessageType.TASK_STATUS,
        content: TaskStatus(
            status: MultiAgentStatusType.DONE,
            taskId: taskId,
            description:
                ToolStatusDescription(functionCallIdList: [call.id]).toJson()));
    sendAgentMessage(subAgentStatusMessage);
  }
}

class AutoExecutionException implements Exception {
  final String message;

  AutoExecutionException(this.message);

  @override
  String toString() => 'AutoExecutionException: $message';
}
