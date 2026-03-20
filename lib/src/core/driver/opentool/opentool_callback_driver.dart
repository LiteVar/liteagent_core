import 'dart:async';
import 'package:opentool_dart/opentool_client.dart';
import 'model.dart';
import 'opentool_driver.dart';

class OpenToolCallbackDriver extends OpenToolDriver {
  final void Function(FunctionCall functionCall) listenCallbackFunctionCall;
  final int timeout;
  final Map<String, Completer<ToolReturn>> _callToolReturnCompleterMap = {};
  void Function(String functionCallId, OpenToolCallbackDriver driver)?
      _registerPendingCall;
  void Function(String functionCallId, OpenToolCallbackDriver driver)?
      _unregisterPendingCall;

  final Map<String, StreamController<EventToolReturn>> _streamCallMap = {};

  OpenToolCallbackDriver(
    OpenTool opentool,
    this.listenCallbackFunctionCall, {
    this.timeout = 60,
  }) : super(opentool);

  void setPendingCallHooks({
    void Function(String functionCallId, OpenToolCallbackDriver driver)?
        registerPendingCall,
    void Function(String functionCallId, OpenToolCallbackDriver driver)?
        unregisterPendingCall,
  }) {
    _registerPendingCall = registerPendingCall;
    _unregisterPendingCall = unregisterPendingCall;
  }

  void _trackPendingCall(String functionCallId) {
    _registerPendingCall?.call(functionCallId, this);
  }

  void _clearPendingCall(String functionCallId) {
    _unregisterPendingCall?.call(functionCallId, this);
  }

  /// Call mode
  @override
  Future<ToolReturn> call(FunctionCall functionCall) async {
    final completer = Completer<ToolReturn>();
    _callToolReturnCompleterMap[functionCall.id] = completer;
    _trackPendingCall(functionCall.id);

    try {
      /// invoke remote call
      listenCallbackFunctionCall(functionCall);

      /// Wait for toolReturn or Timeout
      return await completer.future.timeout(
        Duration(seconds: timeout),
        onTimeout: () => ToolReturn(
          id: functionCall.id,
          result: {
            "error":
                "Function `${functionCall.toJson()}` timeout after ${timeout}s."
          },
        ),
      );
    } finally {
      _callToolReturnCompleterMap.remove(functionCall.id);
      _clearPendingCall(functionCall.id);
    }
  }

  /// Stream Call mode
  @override
  Future<void> streamCall(
    FunctionCall functionCall,
    void Function(String event, ToolReturn toolReturn) onStream,
  ) async {
    final streamController = StreamController<EventToolReturn>();
    _streamCallMap[functionCall.id] = streamController;
    _trackPendingCall(functionCall.id);

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
        _clearPendingCall(functionCall.id);
        streamController.close();
        sink.close();
      },
    ).listen(
      (eventToolReturn) {
        onStream(eventToolReturn.event, eventToolReturn.toolReturn);
      },
      onDone: () {
        _streamCallMap.remove(functionCall.id);
        _clearPendingCall(functionCall.id);
      },
      onError: (e) {
        onStream(EventType.ERROR,
            ToolReturn(id: functionCall.id, result: {"error": e.toString()}));
        _streamCallMap.remove(functionCall.id);
        _clearPendingCall(functionCall.id);
        streamController.close();
      },
    );
  }

  bool callback(ToolReturn toolReturn) {
    final completer = _callToolReturnCompleterMap[toolReturn.id];
    if (completer != null && !completer.isCompleted) {
      completer.complete(toolReturn);
      return true;
    }
    return false;
  }

  bool streamCallback(String event, ToolReturn toolReturn) {
    StreamController<EventToolReturn>? eventToolReturnStreamController =
        _streamCallMap[toolReturn.id];
    if (eventToolReturnStreamController != null) {
      EventToolReturn eventToolReturn =
          EventToolReturn(event: event, toolReturn: toolReturn);
      eventToolReturnStreamController.add(eventToolReturn);
      if (event == EventType.DONE || event == EventType.ERROR) {
        _streamCallMap.remove(toolReturn.id);
        _clearPendingCall(toolReturn.id);
        eventToolReturnStreamController.close();
      }
      return true;
    }
    return false;
  }
}
