import '../models/node.dart';

/// context builder
/// responsible for building the context of the node and passing the dependency results
class ContextBuilder {

  String buildExecutionContext(String nodeId, Map<String, String> dependencyResults,
      AutoTaskNode node) {
    final contextParts = <String>[];

    final sortedDependencies = _sortByCompletionOrder(dependencyResults);

    for (final entry in sortedDependencies.entries) {
      String depId = entry.key;
      String result = entry.value;
      contextParts.add('【task ${depId} execution result】:\n$result\n');
    }

    final taskContext = buildTaskSpecificPrompt(node);

    String fullContext = '';
    if (contextParts.isNotEmpty) {
      fullContext = '${contextParts.join('\n')}\n【current task requirements】:\n$taskContext';
    } else {
      fullContext = '【current task requirements】:\n$taskContext';
    }

    return fullContext;
  }

  String formatDependencyResults(Map<String, String> results) {
    if (results.isEmpty) {
      return 'no dependency results';
    }

    final formatted = <String>[];
    for (var entry in results.entries) {
      formatted.add('${entry.key}: ${entry.value}');
    }

    return formatted.join('\n');
  }

  String buildTaskSpecificPrompt(AutoTaskNode node) {
    return '''
任务名称: ${node.name}
任务职责: ${node.description.duty}
执行约束: ${node.description.constraint}
可用工具: ${node.tools.isEmpty ? '无' : node.tools.join(', ')}
''';
  }

  Map<String, String> _sortByCompletionOrder(Map<String, String> results) {
    return results;
  }
}