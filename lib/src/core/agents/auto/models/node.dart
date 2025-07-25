
enum AutoNodeStatus {
  PENDING,     // waiting to be executed
  EXECUTING,   // executing
  SUCCEEDED,   // successfully completed
  FAILED,      // execution failed
  CANCELLED,   // cancelled
  ;

  String toStringValue() {
    switch (this) {
      case AutoNodeStatus.PENDING:
        return 'pending';
      case AutoNodeStatus.EXECUTING:
        return 'executing';
      case AutoNodeStatus.SUCCEEDED:
        return 'completed';
      case AutoNodeStatus.FAILED:
        return 'failed';
      case AutoNodeStatus.CANCELLED:
        return 'cancelled';
    }
  }

  static AutoNodeStatus fromString(String statusStr) {
    switch (statusStr.toLowerCase()) {
      case 'pending':
        return AutoNodeStatus.PENDING;
      case 'executing':
        return AutoNodeStatus.EXECUTING;
      case 'completed':
      case 'succeeded':
        return AutoNodeStatus.SUCCEEDED;
      case 'failed':
        return AutoNodeStatus.FAILED;
      case 'cancelled':
        return AutoNodeStatus.CANCELLED;
      default:
        return AutoNodeStatus.PENDING;
    }
  }
}

/// DAG task node model
class AutoTaskNode {

  final String id;
  final String name;
  final AutoTaskDescription description;
  final List<NodeTool> tools;
  final NodeLLMModel model;
  final List<NodeDependency> dependencies;
  String? result;
  DateTime? startTime;
  DateTime? endTime;
  AutoNodeStatus status;

  AutoTaskNode({
    required this.id,
    required this.name,
    required this.description,
    required this.tools,
    required this.model,
    this.dependencies = const [],
    this.result,
    this.startTime,
    this.endTime,
    this.status = AutoNodeStatus.PENDING,
  });

  int? get executionTimeMs {
    if (startTime != null && endTime != null) {
      return endTime!.difference(startTime!).inMilliseconds;
    }
    return null;
  }
  factory AutoTaskNode.fromJson(Map<String, dynamic> json) {

    return AutoTaskNode(
      id: json['id'] as String,
      name: json['name'] as String,
      description: AutoTaskDescription.fromJson(json['description'] as Map<String, dynamic>),
      tools: (json['tools'] as List<dynamic>?)?.map((tool) => NodeTool.fromJson(tool as Map<String, dynamic>)).toList() ?? [],
      model: NodeLLMModel.fromJson(json['model'] as Map<String, dynamic>),
      dependencies: (json['dependencies'] as List<dynamic>?)?.map((dep) => NodeDependency.fromJson(dep as Map<String, dynamic>)).toList() ?? [],
      result: json['result'] as String?,
      startTime: json['startTime'] != null ? DateTime.parse(json['startTime']) : null,
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
      status: AutoNodeStatus.fromString(json['status'] as String? ?? 'pending'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description.toJson(),
      'tools': tools.map((tool) => tool.toJson()).toList(),
      'model': model.toJson(),
      'dependencies': dependencies.map((dep) => dep.toJson()).toList(),
      'result': result,
      'startTime': startTime?.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'status': status.toStringValue(),
    };
  }

  @override
  String toString() {
    String basicInfo = 'AutoTaskNode{id: $id, name: $name, dependencies: $dependencies}';
    if (status != AutoNodeStatus.PENDING) {
      return '$basicInfo, status: ${status.toStringValue()}, result: ${result?.length ?? 0} chars';
    }
    return basicInfo;
  }
}

class AutoTaskDescription {

  final String duty;
  
  final String constraint;

  AutoTaskDescription({
    required this.duty,
    required this.constraint,
  });

  factory AutoTaskDescription.fromJson(Map<String, dynamic> json) {
    return AutoTaskDescription(
      duty: json['duty'] as String,
      constraint: json['constraint'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'duty': duty,
      'constraint': constraint,
    };
  }

  @override
  String toString() => 'AutoTaskDescription{duty: $duty, constraint: $constraint}';
}

class NodeLLMModel {

  final String id;
  final String name;

  NodeLLMModel({
    required this.id,
    required this.name,
  });

  factory NodeLLMModel.fromJson(Map<String, dynamic> json) {
    return NodeLLMModel(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
  }

  @override
  String toString() => 'NodeLLMModel{id: $id, name: $name}';
}

class NodeTool {

  final String id;
  final String name;

  NodeTool({
    required this.id,
    required this.name,
  });

  factory NodeTool.fromJson(Map<String, dynamic> json) {
    return NodeTool(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
  }

  @override
  String toString() => 'NodeTool{id: $id, name: $name}';  
}

class NodeDependency {

  final String id;
  final String name;

  NodeDependency({
    required this.id,
    required this.name,
  });

  factory NodeDependency.fromJson(Map<String, dynamic> json) {
    return NodeDependency(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
  }

  @override
  String toString() => 'NodeDependency{id: $id, name: $name}';
}