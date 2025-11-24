// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mcp_stdio.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

McpStdio _$McpStdioFromJson(Map<String, dynamic> json) => McpStdio(
      command: json['command'] as String,
      args: (json['args'] as List<dynamic>).map((e) => e as String).toList(),
      environment: (json['env'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ),
    );

Map<String, dynamic> _$McpStdioToJson(McpStdio instance) => <String, dynamic>{
      'command': instance.command,
      'args': instance.args,
      'env': instance.environment,
    };
