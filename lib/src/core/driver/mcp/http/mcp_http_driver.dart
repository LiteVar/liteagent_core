import 'dart:convert';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:opentool_dart/opentool_dart.dart' as ot;
import '../mcp_base_driver.dart';
import 'mcp_http.dart';

class McpHttpDriver extends McpBaseDriver {
  late Client client;
  late StreamableHttpClientTransport transport;
  String? sessionId;

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
    if (isConnected) {
      return;
    }

    try {
      await client.connect(transport);
      this.sessionId = transport.sessionId;
      ListToolsResult listToolsResult = await client.listTools();
      functionModelList = convertToFunctionModelList(listToolsResult);
      isConnected = true;
    } catch (error) {
      rethrow;
    }
  }

  @override
  Future<ot.ToolReturn> call(ot.FunctionCall functionCall) async {
    CallToolResult callToolResult = await client.callTool(CallToolRequestParams(name: functionCall.name, arguments: functionCall.arguments));
    return ot.ToolReturn(id: functionCall.id, result: callToolResult.toJson());
  }
}