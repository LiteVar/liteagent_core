import 'package:opentool_dart/opentool_client.dart';

abstract class ToolDriver {
  Future<void> init() async {}
  List<FunctionModel> parse();
  bool hasFunction(String functionName);
  Future<ToolReturn> call(FunctionCall functionCall);
  Future<void> streamCall(
    FunctionCall functionCall,
    void Function(String event, ToolReturn toolReturn) onStream,
  ) async {}
  Future<void> cancel(String functionCallId) async {}
  Future<void> dispose() async {}
}
