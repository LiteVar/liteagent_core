import 'dart:async';
import 'package:opentool_dart/opentool_client.dart';
import 'model.dart';
import 'opentool_driver.dart';

class OpenToolCallbackDriver extends OpenToolDriver {
  final void Function(FunctionCall functionCall) listenCallbackFunctionCall;
  final int timeout;
  Completer<ToolReturn>? _callToolReturnCompleter;

  Map<String, StreamController<EventToolReturn>> _streamCallMap = {};

  OpenToolCallbackDriver(
      OpenTool opentool,
      this.listenCallbackFunctionCall, {
        this.timeout = 60,
      }) : super(opentool);

  /// Call mode
  @override
  Future<ToolReturn> call(FunctionCall functionCall) async {
    _callToolReturnCompleter = Completer<ToolReturn>();

    /// invoke remote call
    listenCallbackFunctionCall(functionCall);

    /// Wait for toolReturn or Timeout
    return await _callToolReturnCompleter!.future.timeout(
      Duration(seconds: timeout),
      onTimeout: () {
        if (!_callToolReturnCompleter!.isCompleted) {
          ToolReturn toolReturn = ToolReturn(
            id: functionCall.id,
            result: {
              "error":
              "Function `${functionCall.toJson()}` timeout after ${timeout}s."
            },
          );
          _callToolReturnCompleter!.complete(toolReturn);
        }
        return _callToolReturnCompleter!.future;
      },
    );
  }

  /// Stream Call mode
  @override
  Future<void> streamCall(FunctionCall functionCall, void Function(String event, Map<String, dynamic>) onStream,) async {
    _streamCallMap[functionCall.id] = StreamController<EventToolReturn>();

    /// invoke remote call
    listenCallbackFunctionCall(functionCall);

    _streamCallMap[functionCall.id]!.stream.
    timeout(
      Duration(seconds: timeout),
      onTimeout: (sink) {
        ToolReturn toolReturn = ToolReturn(
          id: functionCall.id,
          result: {
            "error":
            "Function `${functionCall.toJson()}` timeout after ${timeout}s."
          },
        );
        onStream(EventType.ERROR, toolReturn.toJson());
        sink.close();
      },
    )
      .listen(
        (eventToolReturn){
          onStream(eventToolReturn.event, eventToolReturn.toolReturn.toJson());
        },
        onDone: (){
          onStream(EventType.DONE, {});
        },
        onError: (e) {
          onStream(EventType.ERROR, {"error": e.toString()});
        }
    );
  }

  void callback(ToolReturn toolReturn) {
    if (_callToolReturnCompleter != null &&
        !_callToolReturnCompleter!.isCompleted) {
      _callToolReturnCompleter!.complete(toolReturn);
    }
  }

  void streamCallback(String event, ToolReturn toolReturn) {
    StreamController<EventToolReturn>? eventToolReturnStreamController = _streamCallMap[toolReturn.id];
    if(eventToolReturnStreamController != null) {
      EventToolReturn eventToolReturn = EventToolReturn(event: event, toolReturn: toolReturn);
      eventToolReturnStreamController.add(eventToolReturn);
    }
  }
}