import 'package:lite_agent_core_dart/lite_agent_core.dart';
import 'package:opentool_dart/opentool_dart.dart';

import 'mock_util.dart';

class MockDriver extends OpenToolDriver {
  MockUtil mockUtil = MockUtil();

  MockDriver(OpenTool opentool): super(opentool);

  @override
  Future<ToolReturn> call(FunctionCall functionCall) async{
    String functionName = functionCall.name;
    if(functionName == "count") {
      int count = mockUtil.count();
      return ToolReturn(id: functionCall.id, result: {"count": count});
    } else if(functionName == "create") {
      String text = functionCall.arguments["text"] as String;
      int id = mockUtil.create(text);
      return ToolReturn(id: functionCall.id, result: {"id": id});
    } else if(functionName == "read") {
      int id = functionCall.arguments["id"] as int;
      String text = mockUtil.read(id);
      return ToolReturn(id: functionCall.id, result: {"text": text});
    } else if(functionName == "update") {
      int id = functionCall.arguments["id"] as int;
      String text = functionCall.arguments["text"] as String;
      mockUtil.update(id, text);
      return ToolReturn(id: functionCall.id, result: {"result": "Update successfully."});
    } else if(functionName == "delete") {
      int id = functionCall.arguments["id"] as int;
      mockUtil.delete(id);
      return ToolReturn(id: functionCall.id, result: {"result": "Delete successfully."});
    } else {
      return ToolReturn(id: functionCall.id, result: FunctionNotSupportedException(functionName: functionName).toJson());
    }
  }
}