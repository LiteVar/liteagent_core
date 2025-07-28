import 'dart:async';

import '../../../llm/model.dart';
import '../models/node.dart';
import '../wrappers/function.dart';
import 'dependency_analyzer.dart';
import 'execution_manager.dart';
import 'topological_scheduler.dart';
import '../wrappers/llm.dart';
import '../auto_multi_agent.dart';

class AutoNodeExecutor {
  final List<IndexedLLMConfig> indexedLLMConfigs;
  final List<IndexedFunction> indexedFunctions;
  final AutoMessageSender messageSender;
  
  late final DependencyAnalyzer _dependencyAnalyzer;
  late final TopologicalScheduler _topologicalScheduler;
  late final ExecutionManager _executionManager;
  
  bool _isRunning = false;
  
  AutoNodeExecutor({
    required this.indexedLLMConfigs,
    required this.indexedFunctions,
    required this.messageSender,
  }) {
    _dependencyAnalyzer = DependencyAnalyzer();
    _topologicalScheduler = TopologicalScheduler();
    _executionManager = ExecutionManager(
      indexedLLMConfigs: indexedLLMConfigs,
      indexedFunctions: indexedFunctions,
      messageSender: messageSender,
    );
  }
  
  Future<List<AutoTaskNode>> executeNodeTree(List<AutoTaskNode> nodes, String taskId) async {
    if (_isRunning) {
      throw Exception('executor is running');
    }
    
    _isRunning = true;
    
    try {
      // 1. dependency analysis
      if (_dependencyAnalyzer.hasCircularDependency(nodes)) {
        throw Exception('circular dependency detected, cannot execute');
      }
      
      final dependencyGraph = _dependencyAnalyzer.buildDependencyGraph(nodes);
      final reverseDependencyGraph = _dependencyAnalyzer.buildReverseDependencyGraph(dependencyGraph);
      
      // 2. build node map
      final nodeMap = <String, AutoTaskNode>{};
      final inDegree = <String, int>{};
      for (var node in nodes) {
        nodeMap[node.id] = node;
        inDegree[node.id] = node.dependencies.length;
        node.status = AutoNodeStatus.PENDING;
      }
      
      // 3. execute scheduling
      final results = <String, String>{};
      final blockedNodes = <String>{};
      final completedNodes = <AutoTaskNode>[];
      
      while (results.length + blockedNodes.length < nodes.length) {
        // get ready nodes
        final readyNodes = _topologicalScheduler.getReadyNodes(inDegree)
            .where((nodeId) => !results.containsKey(nodeId) && !blockedNodes.contains(nodeId))
            .toList();
        
        if (readyNodes.isEmpty) {
          // check if there is a deadlock
          final remainingNodes = nodes.where((node) => 
              !results.containsKey(node.id) && !blockedNodes.contains(node.id)).toList();
          if (remainingNodes.isNotEmpty) {
            print('deadlock or dependency problem detected, remaining nodes: ${remainingNodes.map((n) => n.id).join(', ')}');
            break;
          }
        }
        
        print('readyNodes: ${readyNodes.join(', ')}');
        
        // mark nodes as executing
        for (String nodeId in readyNodes) {
          final node = nodeMap[nodeId]!;
          node.status = AutoNodeStatus.EXECUTING;
        }
        
        // parallel execution of ready nodes
        final batchResults = await _executionManager.parallelExecution(
          readyNodes, nodeMap, results, taskId);
        
        // process execution results
        for (var entry in batchResults.entries) {
          String nodeId = entry.key;
          String result = entry.value;
          final node = nodeMap[nodeId]!;
          
          if (result.startsWith('ERROR:')) {
            node.status = AutoNodeStatus.FAILED;
            node.result = result;            
            print('node $nodeId execution failed: $result');
          } else {
            results[nodeId] = result;
            node.status = AutoNodeStatus.SUCCEEDED;
            node.result = result;
            
            // update in-degree
            _topologicalScheduler.updateInDegree(nodeId, inDegree, reverseDependencyGraph);
            
            completedNodes.add(node);
            
            print('node $nodeId execution completed');
          }
        }
      }
      
      return completedNodes;
      
    } finally {
      _isRunning = false;
    }
  }
  
  void stop() {
    _executionManager.stop();
    _isRunning = false;
  }
  
  void clear() {
    _executionManager.clear();
    _isRunning = false;
  }
    
  bool get isRunning => _isRunning;
} 