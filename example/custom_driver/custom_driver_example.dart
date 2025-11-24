import 'dart:io';
import 'package:liteagent_core_dart/liteagent_core.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'mock_driver.dart';

Future<void> main() async {
  Map<String, dynamic> args = {};
  FunctionCall functionCall = FunctionCall(id: "callId-0", name: "count", arguments: args);

  String jsonFileName = "mock-tool.json";
  String jsonPath = "${Directory.current.path}${Platform.pathSeparator}example${Platform.pathSeparator}custom_driver${Platform.pathSeparator}$jsonFileName";
  OpenTool openTool = await OpenToolJsonLoader().loadFromFile(jsonPath);
  OpenToolDriver mockDriver = MockDriver(openTool);

  ToolReturn toolReturn = await mockDriver.call(functionCall);
  print(toolReturn.toJson());
}