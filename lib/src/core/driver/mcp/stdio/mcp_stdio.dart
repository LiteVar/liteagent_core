import 'package:json_annotation/json_annotation.dart';
part 'mcp_stdio.g.dart';

@JsonSerializable()
class McpStdio {
  String command;
  List<String> args;

  McpStdio({required this.command, required this.args});

  factory McpStdio.fromJson(Map<String, dynamic> json) => _$McpStdioFromJson(json);
  Map<String, dynamic> toJson() => _$McpStdioToJson(this);
}