import '../models/node.dart';

/// context builder
/// responsible for building the context of the node and passing the dependency results
class ContextBuilder {

  String buildExecutionContext(String nodeId, Map<String, String> dependencyResults,
      AutoTaskNode node) {
    final contextParts = <String>[];

    for (final dep in node.dependencies) {
      String result = dependencyResults[dep.id] ?? '';
      contextParts.add('【任务[${dep.name}]执行结果】:\n$result\n');
    }

    String fullContext = contextParts.join('\n');

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
}