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
  Future<void> streamCall(
    FunctionCall functionCall,
    void Function(String event, ToolReturn toolReturn) onStream,
  ) async {
    final streamController = StreamController<EventToolReturn>();
    _streamCallMap[functionCall.id] = streamController;

    /// invoke remote call
    listenCallbackFunctionCall(functionCall);

    streamController.stream.timeout(
      Duration(seconds: timeout),
      onTimeout: (sink) {
        ToolReturn toolReturn = ToolReturn(
          id: functionCall.id,
          result: {
            "error":
            "Function `${functionCall.toJson()}` timeout after ${timeout}s."
          },
        );
        onStream(EventType.ERROR, toolReturn);
        _streamCallMap.remove(functionCall.id);
        streamController.close();
        sink.close();
      },
    )
        .listen(
      (eventToolReturn) {
        onStream(eventToolReturn.event, eventToolReturn.toolReturn);
      },
      onDone: () {
        _streamCallMap.remove(functionCall.id);
      },
      onError: (e) {
        onStream(EventType.ERROR, ToolReturn(id: functionCall.id, result: {"error": e.toString()}));
        _streamCallMap.remove(functionCall.id);
        streamController.close();
      },
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
      if (event == EventType.DONE || event == EventType.ERROR) {
        _streamCallMap.remove(toolReturn.id);
        eventToolReturnStreamController.close();
      }
    }
  }
}
