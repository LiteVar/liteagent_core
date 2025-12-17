// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'node.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AutoTaskNode _$AutoTaskNodeFromJson(Map<String, dynamic> json) => AutoTaskNode(
      id: json['id'] as String,
      name: json['name'] as String,
      description: AutoTaskDescription.fromJson(
          json['description'] as Map<String, dynamic>),
      tools: (json['tools'] as List<dynamic>)
          .map((e) => NodeTool.fromJson(e as Map<String, dynamic>))
          .toList(),
      model: NodeLLMModel.fromJson(json['model'] as Map<String, dynamic>),
      dependencies: (json['dependencies'] as List<dynamic>?)
              ?.map((e) => NodeDependency.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      result: json['result'] as String?,
      startTime: json['startTime'] == null
          ? null
          : DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] == null
          ? null
          : DateTime.parse(json['endTime'] as String),
      status: json['status'] == null
          ? AutoNodeStatus.PENDING
          : AutoNodeStatus.fromString(json['status'] as String),
    );

Map<String, dynamic> _$AutoTaskNodeToJson(AutoTaskNode instance) {
  final val = <String, dynamic>{
    'id': instance.id,
    'name': instance.name,
    'description': instance.description.toJson(),
    'tools': instance.tools.map((e) => e.toJson()).toList(),
    'model': instance.model.toJson(),
    'dependencies': instance.dependencies.map((e) => e.toJson()).toList(),
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('result', instance.result);
  writeNotNull('startTime', instance.startTime?.toIso8601String());
  writeNotNull('endTime', instance.endTime?.toIso8601String());
  val['status'] = AutoTaskNode._statusToString(instance.status);
  return val;
}

AutoTaskDescription _$AutoTaskDescriptionFromJson(Map<String, dynamic> json) =>
    AutoTaskDescription(
      duty: json['duty'] as String,
      constraint: json['constraint'] as String,
    );

Map<String, dynamic> _$AutoTaskDescriptionToJson(
        AutoTaskDescription instance) =>
    <String, dynamic>{
      'duty': instance.duty,
      'constraint': instance.constraint,
    };

NodeLLMModel _$NodeLLMModelFromJson(Map<String, dynamic> json) => NodeLLMModel(
      id: json['id'] as String,
      name: json['name'] as String,
    );

Map<String, dynamic> _$NodeLLMModelToJson(NodeLLMModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
    };

NodeTool _$NodeToolFromJson(Map<String, dynamic> json) => NodeTool(
      id: json['id'] as String,
      name: json['name'] as String,
    );

Map<String, dynamic> _$NodeToolToJson(NodeTool instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
    };

NodeDependency _$NodeDependencyFromJson(Map<String, dynamic> json) =>
    NodeDependency(
      id: json['id'] as String,
      name: json['name'] as String,
    );

Map<String, dynamic> _$NodeDependencyToJson(NodeDependency instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
    };
