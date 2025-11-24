import 'package:opentool_dart/opentool_schema.dart';
import '../../../driver/tool_driver.dart';

class IndexedFunction {

  final int index;
  
  final FunctionModel functionModel;
  
  final ToolDriver toolDriver;

  IndexedFunction({
    required this.index,
    required this.functionModel,
    required this.toolDriver,
  });

  @override
  String toString() {
    return 'IndexedFunction(index: $index, name: ${functionModel.name}, driver: ${toolDriver.runtimeType})';
  }
} 