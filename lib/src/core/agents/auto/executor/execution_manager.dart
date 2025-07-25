import 'dart:async';
import 'package:opentool_dart/opentool_dart.dart';

import '../../tool_agent/tool_agent.dart';
import '../../../llm/model.dart';
import '../../session_agent/session_agent.dart';
import '../../session_agent/session.dart';
import '../models/node.dart';
import '../models/function.dart';
import '../../multi_agent/model.dart';
import '../../session_agent/model.dart';
import '../../tool_agent/model.dart';
import '../../model.dart';
import '../../../util/unique_id_generator.dart';
import 'context_builder.dart';


/// execution manager
/// responsible for concurrent execution control and status management
class ExecutionManager {
  final Map<String, LLMConfig> modelConfigMap;
  final List<IndexedFunction> indexedFunctions;
  final SessionAgent mainAgent;
  final int maxConcurrency;

  final Map<String, ToolAgent> _taskExecutors = {};
  final Set<String> _executing = {};
  final Set<String> _activeSubSessionIds = {};

  ExecutionManager({
    required this.modelConfigMap,
    required this.indexedFunctions,
    required this.mainAgent,
    this.maxConcurrency = 3,
  });

  /// concurrent execution
  Future<Map<String, String>> parallelExecution(
      List<String> readyNodeIds,
      Map<String, AutoTaskNode> nodeMap,
      Map<String, String> dependencyResults,
      String taskId) async {

    final results = <String, String>{};
    final futures = <Future<void>>[];

    // limit concurrency
    final nodesToExecute = readyNodeIds.take(maxConcurrency).toList();

    for (String nodeId in nodesToExecute) {
      final node = nodeMap[nodeId];
      if (node == null) continue;

      // build the context of the node
      final contextBuilder = ContextBuilder();
      final nodeContext = contextBuilder.buildExecutionContext(
          nodeId,
          _getNodeDependencyResults(node, dependencyResults),
          node
      );

      // create asynchronous execution task
      final future = executeNode(node, nodeContext, taskId).then((result) {
        results[nodeId] = result;
        return result;
      }).catchError((error) {
        results[nodeId] = 'ERROR: $error';
        return 'ERROR: $error';
      });

      futures.add(future.then((_) {}));
    }

    // wait for all tasks to complete
    await Future.wait(futures);

    return results;
  }

  Future<String> executeNode(AutoTaskNode node, String context, String taskId) async {
    if (_executing.contains(node.id)) {
      throw Exception('node ${node.id} is already executing');
    }

    _executing.add(node.id);

    String sessionId = uniqueId();
    
    final functionCall = FunctionCall(id: node.id, name: node.name, arguments: {});

    try {

      final tempSession = AgentSession(sessionId: sessionId);

      String executionResult = '';
      final completer = Completer<String>();

      // record sub session ID
      _addSubSessionId(sessionId);

      tempSession.addAgentMessageListener((message) {

        mainAgent.agentSession.addListenAgentMessage(message);

        // collect execution results
        if (message.type == SessionMessageType.TEXT &&
            message.role == SessionRoleType.AGENT &&
            message.to == SessionRoleType.USER &&
            message.content is String) {
          executionResult += message.content as String;
        }


        // check if the task is completed
        if (message.type == SessionMessageType.TASK_STATUS) {
          final taskStatus = message.content as TaskStatus;
          if(taskStatus.status == TaskStatusType.DONE || taskStatus.status == TaskStatusType.STOP || taskStatus.status == TaskStatusType.EXCEPTION ) {
            if (!completer.isCompleted) {
              completer.complete(executionResult);
            }
          }
        }
      });

      final nodeTools = <ToolDriver>[];
      for (NodeTool tool in node.tools) {
        if (int.tryParse(tool.id) != null) {
          nodeTools.add(indexedFunctions[int.parse(tool.id)].toolDriver);
        }
      }

      final tempToolAgent = ToolAgent(
        sessionId: sessionId,
        toolDriverList: nodeTools,
        llmConfig: modelConfigMap[node.model.id] ?? modelConfigMap.values.first,
        agentSession: tempSession,
        systemPrompt: _buildSystemPrompt(node, context),
      );

      await tempToolAgent.userToAgent(
        contentList: [Content(type: ContentType.TEXT, message: "execute task")],
        parentTaskId: taskId,
      );

      sendStartMessage(taskId, functionCall);

      final resultContent = await completer.future;

      String finalResult = resultContent.isNotEmpty ? resultContent : 'Task done';

      sendDoneMessage(taskId, functionCall, finalResult);

      return finalResult;

    } catch (error) {
      rethrow;
    } finally {
      _executing.remove(node.id);
      _removeSubSessionId(sessionId);
    }
  }

  void sendStartMessage(String taskId, FunctionCall functionCall) {
    AgentMessage subAgentMessage = AgentMessage(
      sessionId: mainAgent.sessionId,
      parentTaskId: mainAgent.parentTaskId,
      taskId: taskId,
      role: MultiAgentRoleType.AGENT,
      to: MultiAgentRoleType.SUBAGENT,
      type: MultiAgentMessageType.TOOL_CALLS,
      content: [functionCall]
    );
    mainAgent.agentSession.addListenAgentMessage(subAgentMessage);

    AgentMessage clientMessage = AgentMessage(
      sessionId: mainAgent.sessionId,
      parentTaskId: mainAgent.parentTaskId,
      taskId: taskId,
      role: MultiAgentRoleType.AGENT,
      to: MultiAgentRoleType.CLIENT,
      type: MultiAgentMessageType.TASK_STATUS,
      content: TaskStatus(status:MultiAgentStatusType.START, taskId: taskId, description: ToolStatusDescription(functionCallIdList: [functionCall.id]).toJson())
    );
    mainAgent.agentSession.addListenAgentMessage(clientMessage);
  }

  void sendDoneMessage(String taskId, FunctionCall functionCall, String finalResult) {
    AgentMessage subAgentReturnMessage = AgentMessage(
      sessionId: mainAgent.sessionId,
      parentTaskId: mainAgent.parentTaskId,
      taskId: taskId,
      role: MultiAgentRoleType.SUBAGENT,
      to: MultiAgentRoleType.AGENT,
      type: MultiAgentMessageType.TOOL_RETURN,
      content: ToolReturn(id: functionCall.id, result: {"result": finalResult})
    );
    mainAgent.agentSession.addListenAgentMessage(subAgentReturnMessage);

    AgentMessage subAgentStatusMessage = AgentMessage(
      sessionId: mainAgent.sessionId,
      parentTaskId: mainAgent.parentTaskId,
      taskId: taskId,
      role: MultiAgentRoleType.SUBAGENT,
      to: MultiAgentRoleType.AGENT,
      type: MultiAgentMessageType.TASK_STATUS,
      content: TaskStatus(status:MultiAgentStatusType.DONE, taskId: taskId, description: ToolStatusDescription(functionCallIdList: [functionCall.id]).toJson())
    );
    mainAgent.agentSession.addListenAgentMessage(subAgentStatusMessage);
  }

  /// check if the node can be executed concurrently
  bool canExecuteConcurrently(String nodeId) {
    return !_executing.contains(nodeId) && _executing.length < maxConcurrency;
  }

  String _buildSystemPrompt(AutoTaskNode node, String context) {
    return '''
你是一个专门执行"${node.name}"任务的AI助手。

任务职责: ${node.description.duty}
执行约束: ${node.description.constraint}

请根据用户提供的上下文信息和任务要求，使用可用的工具完成任务。

**严格要求**：
- 当需要用户补充信息时，直接从已知信息里决策，禁止向用户提问或互动
- 当同一个工具连续两次调用失败时，请停止继续调用

已知的上下文信息:
$context
''';
  }

  Map<String, String> _getNodeDependencyResults(AutoTaskNode node, Map<String, String> allResults) {
    final nodeResults = <String, String>{};
    for (NodeDependency dep in node.dependencies) {
      if (allResults.containsKey(dep.id)) {
        nodeResults[dep.id] = allResults[dep.id]!;
      }
    }
    return nodeResults;
  }

  void clear() {
    for (var toolAgent in _taskExecutors.values) {
      toolAgent.clear();
    }
    _taskExecutors.clear();
    _executing.clear();
    _activeSubSessionIds.clear();
  }

  void _addSubSessionId(String sessionId) {
    _activeSubSessionIds.add(sessionId);
  }

  void _removeSubSessionId(String sessionId) {
    _activeSubSessionIds.remove(sessionId);
  }

  void stop() {
    for (var toolAgent in _taskExecutors.values) {
      toolAgent.stop();
    }
  }
}