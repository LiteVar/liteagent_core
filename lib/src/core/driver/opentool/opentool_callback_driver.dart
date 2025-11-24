import 'dart:async';
import 'package:opentool_dart/opentool_client.dart';
import 'opentool_driver.dart';

class OpenToolCallbackDriver extends OpenToolDriver {
  void Function(FunctionCall functionCall) listenCallbackFunctionCall;
  int timeout;
  Completer<ToolReturn>? _toolReturnCompleter;

  OpenToolCallbackDriver(OpenTool opentool, this.listenCallbackFunctionCall, {this.timeout = 60}) : super(opentool);

  @override
  Future<ToolReturn> call(FunctionCall functionCall) async {
    _toolReturnCompleter = Completer<ToolReturn>();
    listenCallbackFunctionCall(functionCall);

    return await _toolReturnCompleter!.future.timeout(
      Duration(seconds: timeout),
      onTimeout: () {
        if (!_toolReturnCompleter!.isCompleted) {
          ToolReturn toolReturn = ToolReturn(id: functionCall.id, result: {"error": "Function `${functionCall.toJson()}` timeout after ${timeout}s."},);
          _toolReturnCompleter!.complete(toolReturn);
        }
        return _toolReturnCompleter!.future;
      },
    );
  }

  void callback(ToolReturn toolReturn) {
    if (_toolReturnCompleter != null && !_toolReturnCompleter!.isCompleted) {
      _toolReturnCompleter!.complete(toolReturn);
    }
  }
}