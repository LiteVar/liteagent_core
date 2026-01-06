import 'dart:async';
import '../models/node.dart';
import '../wrappers/function.dart';
import 'context_builder.dart';
import '../wrappers/tool_agent.dart';
import '../wrappers/llm.dart';
import '../auto_multi_agent.dart';
import 'prompt.dart';
import '../../session_agent/session.dart';
import 'package:unique_id_dart/unique_id_dart.dart';

/// execution manager
/// responsible for concurrent execution control and status management
class ExecutionManager {
  final List<IndexedLLMConfig> indexedLLMConfigs;
  final List<IndexedFunction> indexedFunctions;
  final AutoMessageSender messageSender;
  final int maxConcurrency;

  final Map<String, AutoToolAgent> _executorPool = {};
  final Map<String, AutoToolAgent> _activeExecutors = {};

  ExecutionManager({
    required this.indexedLLMConfigs,
    required this.indexedFunctions,
    required this.messageSender,
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
    if (_activeExecutors.containsKey(node.id)) {
      throw Exception('node ${node.id} is already executing');
    }


    final sessionId = uniqueId();
    final agentSession = AgentSession(sessionId: sessionId);
    final llmConfig = indexedLLMConfigs[int.parse(node.model.id)].llmConfig;
    final systemPrompt = ExecutionPrompt.getSystemPrompt(node, context);
    final indexedFunctionsForNode = indexedFunctions.where((indexedFunction) => node.tools.any((tool) => tool.id == indexedFunction.index.toString())).toList();

    final agent = AutoToolAgent(
      sessionId: sessionId,
      agentSession: agentSession,
      llmConfig: llmConfig,
      systemPrompt: systemPrompt,
      indexedFunctions: indexedFunctionsForNode,
    );

    _executorPool[node.id] = agent;
    _activeExecutors[node.id] = agent;

    try {

      final resultContent = await agent.execute(
        userInput: "execute task",
        originalTaskId: taskId,
        parentTaskId: taskId,
        functionName: node.name,
        messageSender: messageSender,
      );

      String finalResult = resultContent.isNotEmpty ? resultContent : 'Task done';
      return finalResult;

    } catch (error) {
      rethrow;
    } finally {
      _activeExecutors.remove(node.id);
    }
  }

  /// check if the node can be executed concurrently
  bool canExecuteConcurrently(String nodeId) {
    return !_activeExecutors.containsKey(nodeId) && _activeExecutors.length < maxConcurrency;
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
    for (var agent in _executorPool.values) {
      agent.clear();
    }
    _executorPool.clear();
  }

  void stop() {
    for (var agent in _activeExecutors.values) {
      agent.stop();
    }
    _activeExecutors.clear();
  }
}