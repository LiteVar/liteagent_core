import 'dart:io';
import 'package:liteagent_core/liteagent_core.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'mock_driver.dart';

Future<void> main() async {
  String jsonFileName = "mock-tool.json";
  String jsonPath = "${Directory.current.path}${Platform.pathSeparator}example${Platform.pathSeparator}custom_driver${Platform.pathSeparator}$jsonFileName";
  OpenTool openTool = await OpenToolJsonLoader().loadFromFile(jsonPath);
  OpenToolDriver mockDriver = MockDriver(openTool);

  // Call Tool
  Map<String, dynamic> arguments0 = {};
  FunctionCall functionCall0 = FunctionCall(id: "callId-0", name: "count", arguments: arguments0);
  ToolReturn toolReturn = await mockDriver.call(functionCall0);
  print(toolReturn.toJson());

  // StreamCall Tool
  Map<String, dynamic> arguments1 = {};
  FunctionCall functionCall1 = FunctionCall(id: "callId-1", name: "sequentiallyRead", arguments: arguments1);
  await mockDriver.streamCall(functionCall1, (event, toolReturn) {
    print( "$event: ${toolReturn.toJson()}");
  });
}