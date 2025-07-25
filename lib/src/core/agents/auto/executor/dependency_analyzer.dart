import 'dart:collection';
import '../models/node.dart';

/// dependency analyzer
/// responsible for circular dependency detection, critical path analysis, etc.
class DependencyAnalyzer {

  bool hasCircularDependency(List<AutoTaskNode> nodes) {
    final graph = _buildGraph(nodes);
    final visiting = <String>{};
    final visited = <String>{};

    for (String nodeId in graph.keys) {
      if (!visited.contains(nodeId)) {
        if (_dfsHasCycle(nodeId, graph, visiting, visited)) {
          return true;
        }
      }
    }
    return false;
  }

  Map<String, Set<String>> buildDependencyGraph(List<AutoTaskNode> nodes) {
    final graph = <String, Set<String>>{};
    for (var node in nodes) {
      graph[node.id] = Set<String>.from(node.dependencies.map((e) => e.id));
    }
    return graph;
  }

  /// build reverse dependency graph
  Map<String, Set<String>> buildReverseDependencyGraph(Map<String, Set<String>> graph) {
    final reverseGraph = <String, Set<String>>{};

    for (String nodeId in graph.keys) {
      reverseGraph[nodeId] = <String>{};
    }

    for (var entry in graph.entries) {
      String nodeId = entry.key;
      Set<String> dependencies = entry.value;

      for (String depId in dependencies) {
        reverseGraph.putIfAbsent(depId, () => <String>{});
        reverseGraph[depId]!.add(nodeId);
      }
    }

    return reverseGraph;
  }

  /// identify critical path
  List<String> identifyCriticalPath(Map<String, Set<String>> graph) {
    // use topological sort and longest path algorithm to identify critical path
    final inDegree = <String, int>{};
    final maxDepth = <String, int>{};
    final predecessor = <String, String?>{};

    // initialize in-degree
    for (String nodeId in graph.keys) {
      inDegree[nodeId] = graph[nodeId]!.length;
      maxDepth[nodeId] = 0;
      predecessor[nodeId] = null;
    }

    final queue = Queue<String>();

    // find all nodes with in-degree 0
    for (var entry in inDegree.entries) {
      if (entry.value == 0) {
        queue.add(entry.key);
      }
    }

    // topological sort and calculate the longest path
    while (queue.isNotEmpty) {
      String current = queue.removeFirst();

      // update all nodes that depend on the current node
      for (var entry in graph.entries) {
        if (entry.value.contains(current)) {
          String dependent = entry.key;
          inDegree[dependent] = inDegree[dependent]! - 1;

          // update the maximum depth
          if (maxDepth[current]! + 1 > maxDepth[dependent]!) {
            maxDepth[dependent] = maxDepth[current]! + 1;
            predecessor[dependent] = current;
          }

          if (inDegree[dependent] == 0) {
            queue.add(dependent);
          }
        }
      }
    }

    // find the deepest node
    String? deepestNode;
    int maxDepthValue = -1;
    for (var entry in maxDepth.entries) {
      if (entry.value > maxDepthValue) {
        maxDepthValue = entry.value;
        deepestNode = entry.key;
      }
    }

    // backtrack to build the critical path
    final criticalPath = <String>[];
    String? current = deepestNode;
    while (current != null) {
      criticalPath.insert(0, current);
      current = predecessor[current];
    }

    return criticalPath;
  }

  /// DFS detect circular dependency
  bool _dfsHasCycle(String nodeId, Map<String, Set<String>> graph,
      Set<String> visiting, Set<String> visited) {
    if (visiting.contains(nodeId)) {
      return true; // found cycle
    }

    if (visited.contains(nodeId)) {
      return false;
    }

    visiting.add(nodeId);

    final dependencies = graph[nodeId] ?? <String>{};
    for (String dep in dependencies) {
      if (_dfsHasCycle(dep, graph, visiting, visited)) {
        return true;
      }
    }

    visiting.remove(nodeId);
    visited.add(nodeId);
    return false;
  }

  /// build a simple graph structure
  Map<String, Set<String>> _buildGraph(List<AutoTaskNode> nodes) {
    final graph = <String, Set<String>>{};
    for (var node in nodes) {
      graph[node.id] = Set<String>.from(node.dependencies.map((e) => e.id));
    }
    return graph;
  }
}