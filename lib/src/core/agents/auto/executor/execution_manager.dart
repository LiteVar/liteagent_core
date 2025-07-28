import 'dart:async';
import 'package:opentool_dart/opentool_dart.dart';

import '../../tool_agent/tool_agent.dart';
import '../../session_agent/session_agent.dart';
import '../../session_agent/session.dart';
import '../models/node.dart';
import '../wrappers/function.dart';
import '../../session_agent/model.dart';
import '../../model.dart';
import '../../../util/unique_id_generator.dart';
import 'context_builder.dart';
import '../wrappers/tool_agent.dart';
import '../wrappers/llm.dart';
import '../auto_multi_agent.dart';
import 'prompt.dart';

/// execution manager
/// responsible for concurrent execution control and status management
class ExecutionManager {
  final List<IndexedLLMConfig> indexedLLMConfigs;
  final List<IndexedFunction> indexedFunctions;
  final AutoMessageSender messageSender;
  final int maxConcurrency;

  final Map<String, ToolAgent> _taskExecutors = {};
  final Set<String> _executing = {};
  final Set<String> _activeSubSessionIds = {};

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

        messageSender.sendAgentMessage(message);

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

      final indexedFunctionsForNode = indexedFunctions.where((indexedFunction) => node.tools.any((tool) => tool.id == indexedFunction.index.toString())).toList();
      final llmConfig = indexedLLMConfigs[int.parse(node.model.id)].llmConfig;
      final systemPrompt = ExecutionPrompt.getSystemPrompt(node, context);

      final tempToolAgent = AutoToolAgent(
        sessionId: sessionId,
        indexedFunctions: indexedFunctionsForNode,
        llmConfig: llmConfig,
        agentSession: tempSession,
        systemPrompt: systemPrompt,
      );

      await messageSender.sendFunctionCallStart(taskId, functionCall);

      await tempToolAgent.userToAgent(
        contentList: [Content(type: ContentType.TEXT, message: "execute task")],
        parentTaskId: taskId,
      );

      final resultContent = await completer.future;

      String finalResult = resultContent.isNotEmpty ? resultContent : 'Task done';

      await messageSender.sendFunctionCallDone(taskId, functionCall, finalResult);

      return finalResult;

    } catch (error) {
      rethrow;
    } finally {
      _executing.remove(node.id);
      _removeSubSessionId(sessionId);
    }
  }



  /// check if the node can be executed concurrently
  bool canExecuteConcurrently(String nodeId) {
    return !_executing.contains(nodeId) && _executing.length < maxConcurrency;
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