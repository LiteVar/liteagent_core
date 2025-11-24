import 'dart:convert';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:opentool_dart/opentool_dart.dart' as ot;
import '../../tool_driver.dart';
import 'mcp_http.dart';

class McpHttpDriver extends ToolDriver {
  late Client client;
  late StreamableHttpClientTransport transport;
  String? sessionId;
  late List<ot.FunctionModel> functionModelList;

  McpHttpDriver(McpHttp mcpHttp, {OAuthClientProvider? authProvider, void Function()? onTransportClose}) {
    Uri url = Uri.parse(mcpHttp.url);
    StreamableHttpClientTransportOptions httpOptions = StreamableHttpClientTransportOptions(
        authProvider: authProvider,
        sessionId: sessionId
    );

    transport = StreamableHttpClientTransport(url, opts: httpOptions);

    Implementation clientInfo = Implementation(name: 'McpHttpTool', version: '1.0.0');

    client = Client(clientInfo);

    transport.onerror = (error) {
      throw error;
    };

    transport.onclose = () {
      if(onTransportClose != null) onTransportClose();
    };
  }

  factory McpHttpDriver.fromMcpHttpString(String mcpHttpString) {
    McpHttp mcpHttp = McpHttp.fromJson((jsonDecode(mcpHttpString).values.first as Map<String, dynamic>));
    return McpHttpDriver(mcpHttp);
  }

  @override
  Future<void> init() async {
    await client.connect(transport);
    this.sessionId = transport.sessionId;
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