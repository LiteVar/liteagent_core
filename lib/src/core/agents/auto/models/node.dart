
import 'package:json_annotation/json_annotation.dart';

part 'node.g.dart';

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
@JsonSerializable(includeIfNull: false, explicitToJson: true)
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
  @JsonKey(fromJson: AutoNodeStatus.fromString, toJson: _statusToString)
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

  static String _statusToString(AutoNodeStatus status) => status.toStringValue();

  int? get executionTimeMs {
    if (startTime != null && endTime != null) {
      return endTime!.difference(startTime!).inMilliseconds;
    }
    return null;
  }
  factory AutoTaskNode.fromJson(Map<String, dynamic> json) => _$AutoTaskNodeFromJson(json);

  Map<String, dynamic> toJson() => _$AutoTaskNodeToJson(this);

  @override
  String toString() {
    String basicInfo = 'AutoTaskNode{id: $id, name: $name, dependencies: $dependencies}';
    if (status != AutoNodeStatus.PENDING) {
      return '$basicInfo, status: ${status.toStringValue()}, result: ${result?.length ?? 0} chars';
    }
    return basicInfo;
  }
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class AutoTaskDescription {

  final String duty;
  
  final String constraint;

  AutoTaskDescription({
    required this.duty,
    required this.constraint,
  });

  factory AutoTaskDescription.fromJson(Map<String, dynamic> json) => _$AutoTaskDescriptionFromJson(json);

  Map<String, dynamic> toJson() => _$AutoTaskDescriptionToJson(this);

  @override
  String toString() => 'AutoTaskDescription{duty: $duty, constraint: $constraint}';
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class NodeLLMModel {

  final String id;
  final String name;

  NodeLLMModel({
    required this.id,
    required this.name,
  });

  factory NodeLLMModel.fromJson(Map<String, dynamic> json) => _$NodeLLMModelFromJson(json);

  Map<String, dynamic> toJson() => _$NodeLLMModelToJson(this);

  @override
  String toString() => 'NodeLLMModel{id: $id, name: $name}';
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class NodeTool {

  final String id;
  final String name;

  NodeTool({
    required this.id,
    required this.name,
  });

  factory NodeTool.fromJson(Map<String, dynamic> json) => _$NodeToolFromJson(json);

  Map<String, dynamic> toJson() => _$NodeToolToJson(this);

  @override
  String toString() => 'NodeTool{id: $id, name: $name}';  
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class NodeDependency {

  final String id;
  final String name;

  NodeDependency({
    required this.id,
    required this.name,
  });

  factory NodeDependency.fromJson(Map<String, dynamic> json) => _$NodeDependencyFromJson(json);

  Map<String, dynamic> toJson() => _$NodeDependencyToJson(this);

  @override
  String toString() => 'NodeDependency{id: $id, name: $name}';
}