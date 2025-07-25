import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import '../model.dart';
import '../session_agent/model.dart';
import '../session_agent/dispatcher.dart';
import '../tool_agent/tool_agent.dart';
import 'planner/planner.dart';
import 'executor/executor.dart';
import 'summarizer/summarizer.dart';
import 'package:opentool_dart/opentool_dart.dart';
import '../../util/unique_id_generator.dart';
import '../../llm/model.dart';
import 'models/function.dart';
import 'models/node.dart';
import 'models/llm.dart';
import 'planner/template.dart';

class AutoMultiAgent extends ToolAgent {

  late final AutoTaskPlanner taskPlanner;

  late final AutoNodeExecutor nodeExecutor;
  
  late final AutoSummarizer autoSummarizer;
  
  final List<IndexedFunction> indexedFunctions = [];
  
  final List<IndexedLLMConfig> indexedLLMConfigs = [];
  
  AutoMultiAgent({
    required super.sessionId,
    required super.toolDriverList,
    super.clientOpenTool,
    required super.llmConfig,
    required super.agentSession,
    super.systemPrompt,
    super.timeoutSeconds = 3600,
    super.toolReflectPromptList,
    super.taskPipelineStrategy,
    super.toolPipelineStrategy,
    List<LLMConfig>? llmConfigList,
  }) {
    _initializeIndexedFunctions();
    _initializeIndexedLLMConfigs(llmConfigList);

    print('=== AutoMultiAgent available functions ===');
    for (IndexedFunction indexedFunction in indexedFunctions) {
      print('${indexedFunction.index}: ${indexedFunction.functionModel.name} - ${indexedFunction.functionModel.description}');
    }

    print('=== AutoMultiAgent available LLM models ===');
    for (IndexedLLMConfig indexedLLMConfig in indexedLLMConfigs) {
      print('${indexedLLMConfig.index}: ${indexedLLMConfig.llmConfig.model} - ${indexedLLMConfig.description ?? "general model"}');
    }

    taskPlanner = AutoTaskPlanner(
      plannerLLMConfig: llmConfig,
      mainAgent: this,
    );

    nodeExecutor = AutoNodeExecutor(
      modelConfigMap: _buildModelConfigMap(),
      indexedFunctions: indexedFunctions,
      mainAgent: this,
    );

    autoSummarizer = AutoSummarizer(
      summarizerLLMConfig: llmConfig,
      mainAgent: this,
    );
  }

  @override
  Future<void> userToAgent({required List<Content> contentList, bool? stream, String? parentTaskId, void Function(String taskId)? fetchTaskId}) async {
    this.parentTaskId = parentTaskId;
    String taskId = uniqueId();
    if(fetchTaskId != null) fetchTaskId(taskId);
    dispatcherMap.create(taskId);
   
    try {
      _executeAutoMode(taskId, contentList);
    } catch (e, s) {
      _sendDoneMessage(taskId, 'error occurred during execution: $e\n$s');
    }
  }

  @override
  void stop({String? taskId}) {
    nodeExecutor.stop();
    super.stop(taskId: taskId);
  }

  @override
  void clear() {
    nodeExecutor.clear();
    super.clear();
  }

  void _initializeIndexedFunctions() {
    indexedFunctions.clear();
    int currentIndex = 0;
    
    for (ToolDriver toolDriver in toolDriverList) {
      List<FunctionModel> functionModels = toolDriver.parse();
      
      for (FunctionModel functionModel in functionModels) {
        indexedFunctions.add(IndexedFunction(
          index: currentIndex,
          functionModel: functionModel,
          toolDriver: toolDriver,
        ));
        currentIndex++;
      }
    }
  }

  void _initializeIndexedLLMConfigs(List<LLMConfig>? llmConfigList) {
    indexedLLMConfigs.clear();
    
    if (llmConfigList != null && llmConfigList.isNotEmpty) {
      for (int i = 0; i < llmConfigList.length; i++) {
        indexedLLMConfigs.add(IndexedLLMConfig(
          index: i,
          llmConfig: llmConfigList[i],
          description: 'model ${i + 1}',
        ));
      }
    } else {
      // if no LLM config list is provided, use the main llmConfig to create a single config
      indexedLLMConfigs.add(IndexedLLMConfig(
        index: 0,
        llmConfig: llmConfig,
        description: 'main model',
      ));
    }
  }

  Future<void> _executeAutoMode(String taskId, List<Content> contentList) async {
    await Future.delayed(Duration(seconds: 1));

    String userCommand = _extractUserCommand(contentList);

    _sendStartMessage(taskId, contentList);

    String planningResult = await taskPlanner.planTasks(
      userCommand: userCommand,
      indexedLLMConfigs: indexedLLMConfigs,
      indexedFunctions: indexedFunctions,
      taskId: taskId,
    );

    String cleanedResult = AutoPlanningTemplate.cleanPlanningResult(planningResult);
    
    if (!AutoPlanningTemplate.validatePlanningResult(cleanedResult)) {
      _sendDoneMessage(taskId, cleanedResult);
      return;
    }

    List<dynamic> planningJson = jsonDecode(cleanedResult);
    List<AutoTaskNode> taskNodes = planningJson
        .map((json) => AutoTaskNode.fromJson(json as Map<String, dynamic>))
        .toList();
    if (taskNodes.isEmpty) {
      _sendDoneMessage(taskId, cleanedResult);
      return;
    }
    
    List<AutoTaskNode> completedNodes = await nodeExecutor.executeNodeTree(taskNodes, taskId);
                
    String summary = await autoSummarizer.generateSummary(
      userCommand: userCommand,
      completedNodes: completedNodes,
      taskId: taskId,
    );

    await _sendDoneMessage(taskId, summary);
  }
  
  String _extractUserCommand(List<Content> contentList) {
    return contentList
        .where((content) => content.type == ContentType.TEXT)
        .map((content) => content.message)
        .join(' ')
        .trim();
  }

  Map<String, LLMConfig> _buildModelConfigMap() {
    final Map<String, LLMConfig> configMap = {};
    for (IndexedLLMConfig indexedConfig in indexedLLMConfigs) {
      configMap[indexedConfig.index.toString()] = indexedConfig.llmConfig;
    }
    return configMap;
  }
  
  Future<void> _sendStartMessage(String taskId, List<Content> contentList) async {

    AgentMessage clientMessage = AgentMessage(
      sessionId: sessionId,
      parentTaskId: parentTaskId,
      taskId: taskId,
      role: SessionRoleType.AGENT,
      to: SessionRoleType.CLIENT,
      type: SessionMessageType.TASK_STATUS,
      content: TaskStatus(status: TaskStatusType.START, taskId: taskId)
    );
    await agentSession.addListenAgentMessage(clientMessage);

    AgentMessage userMessage = AgentMessage(
      sessionId: sessionId,
      parentTaskId: parentTaskId,
      taskId: taskId,
      role: SessionRoleType.USER,
      to: SessionRoleType.AGENT,
      type: SessionMessageType.CONTENT_LIST,
      content: contentList
    );
    await agentSession.addListenAgentMessage(userMessage);
  }

  Future<void> _sendDoneMessage(String taskId, String finalResult) async {
    AgentMessage userMessage = AgentMessage(
      sessionId: sessionId,
      parentTaskId: parentTaskId,
      taskId: taskId,
      role: SessionRoleType.AGENT,
      to: SessionRoleType.USER,
      type: SessionMessageType.TEXT,
      content: finalResult
    );
    await agentSession.addListenAgentMessage(userMessage);

    AgentMessage clientMessage = AgentMessage(
      sessionId: sessionId,
      parentTaskId: parentTaskId,
      taskId: taskId,
      role: SessionRoleType.AGENT,
      to: SessionRoleType.CLIENT,
      type: SessionMessageType.TASK_STATUS,
      content: TaskStatus(status: TaskStatusType.DONE, taskId: taskId)
    );
    await agentSession.addListenAgentMessage(clientMessage);
  }
}

class AutoExecutionException implements Exception {
  final String message;
  
  AutoExecutionException(this.message);
  
  @override
  String toString() => 'AutoExecutionException: $message';
} 