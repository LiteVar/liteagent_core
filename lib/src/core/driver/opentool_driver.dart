import 'package:opentool_dart/opentool_dart.dart';

import 'tool_driver.dart';

abstract class OpenToolDriver extends ToolDriver {
  OpenTool opentool;

  OpenToolDriver(this.opentool);

  @override
  List<FunctionModel> parse() {
    return opentool.functions;
  }

  @override
  bool hasFunction(String functionName) => opentool.functions
    .where((FunctionModel functionModel) => functionModel.name == functionName)
    .isNotEmpty;
}