import 'package:json_annotation/json_annotation.dart';
part 'mcp_stdio.g.dart';

@JsonSerializable()
class McpStdio {
  String command;
  List<String> args;
  @JsonKey(name: 'env')
  Map<String, String>? environment;


  McpStdio({required this.command, required this.args, this.environment});

  factory McpStdio.fromJson(Map<String, dynamic> json) => _$McpStdioFromJson(json);
  Map<String, dynamic> toJson() => _$McpStdioToJson(this);
}

