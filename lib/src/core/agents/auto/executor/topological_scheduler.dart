import 'dart:collection';
import '../models/node.dart';

/// topological scheduler
/// responsible for Kahn algorithm topological sort and node ready state management
class TopologicalScheduler {

  Queue<String> generateExecutionOrder(List<AutoTaskNode> nodes) {
    final graph = <String, Set<String>>{};
    final inDegree = <String, int>{};

    for (var node in nodes) {
      graph[node.id] = Set<String>.from(node.dependencies);
      inDegree[node.id] = node.dependencies.length;
    }

    final queue = Queue<String>();
    final result = Queue<String>();

    // add all nodes with in-degree 0
    for (var entry in inDegree.entries) {
      if (entry.value == 0) {
        queue.add(entry.key);
      }
    }

    // Kahn algorithm
    while (queue.isNotEmpty) {
      String current = queue.removeFirst();
      result.add(current);

      // update the in-degree of all nodes that depend on the current node
      for (var entry in graph.entries) {
        if (entry.value.contains(current)) {
          String dependent = entry.key;
          inDegree[dependent] = inDegree[dependent]! - 1;
          if (inDegree[dependent] == 0) {
            queue.add(dependent);
          }
        }
      }
    }

    return result;
  }

  List<String> getReadyNodes(Map<String, int> inDegree) {
    return inDegree.entries
        .where((entry) => entry.value == 0)
        .map((entry) => entry.key)
        .toList();
  }

  /// update in-degree table
  void updateInDegree(String completedNode, Map<String, int> inDegree,
      Map<String, Set<String>> reverseDependencyGraph) {
    final dependents = reverseDependencyGraph[completedNode] ?? <String>{};
    for (String dependent in dependents) {
      if (inDegree.containsKey(dependent)) {
        inDegree[dependent] = inDegree[dependent]! - 1;
      }
    }
  }
}