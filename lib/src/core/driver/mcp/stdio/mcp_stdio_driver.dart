import 'dart:convert';
import 'dart:io';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:opentool_dart/opentool_dart.dart' as ot;
import '../../tool_driver.dart';
import 'mcp_stdio.dart';

class McpStdioDriver extends ToolDriver {
  late Client client;
  late StdioClientTransport transport;
  late List<ot.FunctionModel> functionModelList;

  McpStdioDriver(McpStdio mcpStdio, {void Function()? onTransportClose}) {
    StdioServerParameters serverParams = StdioServerParameters(
      command: mcpStdio.command,
      args: mcpStdio.args,
      stderrMode: ProcessStartMode.normal,
    );
    transport = StdioClientTransport(serverParams);

    Implementation clientInfo = Implementation(name: 'McpStdioDriver', version: '1.0.0');

    client = Client(clientInfo);

    transport.onerror = (error) {
      throw error;
    };

    transport.onclose = () {
      if(onTransportClose != null) onTransportClose();
    };
  }

  factory McpStdioDriver.fromMcpStdioString(String mcpStdioString) {
    McpStdio openMcp = McpStdio.fromJson((jsonDecode(mcpStdioString).values.first as Map<String, dynamic>));
    return McpStdioDriver(openMcp);
  }

  @override
  Future<void> init() async {
    await client.connect(transport);
    ListToolsResult listToolsResult = await client.listTools();
    functionModelList = _convertToFunctionModelList(listToolsResult);
  }

  @override
  Future<ot.ToolReturn> call(ot.FunctionCall functionCall) async {
    CallToolResult callToolResult = await client.callTool(CallToolRequestParams(name: functionCall.name, arguments: functionCall.arguments));
    return ot.ToolReturn(id: functionCall.id, result: callToolResult.toJson());
  }

  @override
  bool hasFunction(String functionName) {
    return functionModelList.any((functionModel) => functionModel.name == functionModel);
  }

  @override
  List<ot.FunctionModel> parse() {
    return functionModelList;
  }

  List<ot.FunctionModel> _convertToFunctionModelList(ListToolsResult listToolsResult) {
    return listToolsResult.tools.map((Tool tool){
      return ot.FunctionModel(
          name: tool.name,
          description: tool.description??"",
          parameters: _convertToolInputSchemaToParameters(tool.inputSchema)
      );
    }).toList();
  }

  List<ot.Parameter> _convertToolInputSchemaToParameters(ToolInputSchema schema, {List<String>? required}) {
    if (schema.properties == null) {
      return [];
    }

    return schema.properties!.entries.map((entry) {
      final name = entry.key;
      final value = entry.value as Map<String, dynamic>;
      final isRequired = required?.contains(name) ?? false;

      return ot.Parameter(
        name: name,
        description: value['description'],
        required: isRequired,
        schema: parseSchema(value),
      );
    }).toList();
  }

  ot.Schema parseSchema(Map<String, dynamic> schemaMap) {
    String type = schemaMap['type'] as String;
    String? description = schemaMap['description'] as String?;
    List<String>? enumValues = schemaMap.containsKey('enum') ? List<String>.from(schemaMap['enum']) : null;

    ot.Schema? items;
    if (type == 'array' && schemaMap.containsKey('items')) {
      items = parseSchema(schemaMap['items'] as Map<String, dynamic>);
    }

    Map<String, ot.Schema>? properties;
    List<String>? required;
    if (type == 'object') {
      properties = schemaMap.containsKey('properties') ? (schemaMap['properties'] as Map<String, dynamic>).map((key, value) => MapEntry(key, parseSchema(value as Map<String, dynamic>))) : null;
      required = schemaMap.containsKey('required') ? List<String>.from(schemaMap['required']) : null;
    }

    return ot.Schema(type: type, description: description, properties: properties, items: items, enum_: enumValues, required: required,);
  }
}