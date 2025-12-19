import 'dart:convert';
import 'dart:io';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:opentool_dart/opentool_client.dart' as ot;
import '../mcp_base_driver.dart';
import 'mcp_stdio.dart';

class McpStdioDriver extends McpBaseDriver {
  late Client client;
  late StdioClientTransport transport;

  McpStdioDriver(McpStdio mcpStdio, {void Function()? onTransportClose}) {
    StdioServerParameters serverParams = StdioServerParameters(
      command: mcpStdio.command,
      args: mcpStdio.args,
      environment: mcpStdio.environment,
      stderrMode: ProcessStartMode.normal,
    );
    transport = StdioClientTransport(serverParams);

    Implementation clientInfo = Implementation(name: 'McpStdioDriver', version: '1.0.0');

    client = Client(clientInfo);

    transport.onerror = (error) {
      throw error;
    };

    transport.onclose = () {
      if (onTransportClose != null) onTransportClose();
    };
  }

  factory McpStdioDriver.fromMcpStdioString(String mcpStdioString) {
    McpStdio openMcp =
        McpStdio.fromJson((jsonDecode(mcpStdioString).values.first as Map<String, dynamic>));
    return McpStdioDriver(openMcp);
  }

  @override
  Future<void> init() async {
    if (isConnected) {
      return;
    }

    try {
      await client.connect(transport);
      ListToolsResult listToolsResult = await client.listTools();
      functionModelList = convertToFunctionModelList(listToolsResult);
      isConnected = true;
    } catch (error) {
      rethrow;
    }
  }

  @override
  Future<ot.ToolReturn> call(ot.FunctionCall functionCall) async {
    CallToolResult callToolResult = await client.callTool(
      CallToolRequest(
        name: functionCall.name,
        arguments: functionCall.arguments,
      ),
    );
    return ot.ToolReturn(id: functionCall.id, result: callToolResult.toJson());
  }
}
