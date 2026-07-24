import 'dart:async';
import '../model.dart';
import 'model.dart';

class Command {
  final Future<void> Function(AgentMessage) func;
  final AgentMessage agentMessage;

  Command(this.func, this.agentMessage);

  Future<void> execute() => func(agentMessage);
}

class DispatcherMap {
  final Map<String, Dispatcher> _dispatcherMap = {};

  void create(String taskId) {
    remove(taskId);
    _dispatcherMap[taskId] = Dispatcher();
  }

  bool dispatch(Command command) {
    final dispatcher = _dispatcherMap[command.agentMessage.taskId];
    if (dispatcher == null || !dispatcher.isListening()) return false;
    return dispatcher.dispatch(command);
  }

  List<AgentMessage> getTaskMessageList(String taskId) {
    return _dispatcherMap[taskId]?.getTaskMessageList() ?? const [];
  }

  bool isActive(String taskId) {
    return _dispatcherMap[taskId]?.isListening() ?? false;
  }

  List<String> activeTaskIds() {
    return _dispatcherMap.entries
        .where((entry) => entry.value.isListening())
        .map((entry) => entry.key)
        .toList();
  }

  void breakTask(String taskId) {
    remove(taskId);
  }

  void clearTaskMessageList(String taskId) {
    _dispatcherMap[taskId]?.clearTaskMessageList();
  }

  void stopAll(Future<void> Function(AgentMessage) stopFunc, AgentMessageBase message) {
    for (final entry in _dispatcherMap.entries.toList()) {
      final taskId = entry.key;
      final dispatcher = entry.value;
      if (dispatcher.isListening()) {
        AgentMessage currAgentMessage = AgentMessage(
            sessionId: message.sessionId,
            originalTaskId: message.originalTaskId,
            parentTaskId: message.parentTaskId,
            taskId: taskId,
            role: message.role,
            to: message.to,
            type: message.type,
            content: message.content);
        Command currStopCommand = Command(stopFunc, currAgentMessage);
        stop(taskId, currStopCommand);
      }
    }
  }

  void stop(String taskId, Command stopCommand) {
    final dispatcher = _dispatcherMap[taskId];
    if (dispatcher == null || !dispatcher.isListening()) return;
    stopCommand.execute();
    remove(taskId);
  }

  void remove(String taskId) {
    final dispatcher = _dispatcherMap.remove(taskId);
    dispatcher?.stop();
  }

  void clear(Future<void> Function(AgentMessage) stopFunc, AgentMessageBase message) {
    stopAll(stopFunc, message);
    _dispatcherMap.clear();
  }
}

class Dispatcher {
  final StreamController<Command> _streamController = StreamController<Command>();
  late StreamSubscription<Command> _subscription;
  bool _isListening = false;
  late List<AgentMessage> _taskMessageList = [];
  bool _isTaskDone = false;

  Dispatcher() {
    if (!_streamController.hasListener) {
      _isListening = true;
      _subscription = _streamController.stream.listen((command) async => await command.execute());
    }
  }

  bool dispatch(Command command) {
    if (!_isListening || _streamController.isClosed) return false;
    _addTaskMessage(command.agentMessage);
    _streamController.add(command);
    return true;
  }

  void _addTaskMessage(AgentMessage sessionMessage) {
    if (sessionMessage.to == SessionRoleType.AGENT &&
        sessionMessage.type == SessionMessageType.TEXT &&
        sessionMessage.content is String &&
        (sessionMessage.content as String).trim() == TaskStatusType.DONE) {
      _isTaskDone = true;
    }
    _taskMessageList.add(sessionMessage);
  }

  bool isTaskDone() => _isTaskDone;

  List<AgentMessage> getTaskMessageList() {
    return _taskMessageList;
  }

  void clearTaskMessageList() {
    _taskMessageList = [];
  }

  void stop() {
    if (!_isListening) return;
    _isListening = false;
    _subscription.cancel();
    _streamController.close();
    _taskMessageList = [];
  }

  bool isListening() => _isListening;
}
