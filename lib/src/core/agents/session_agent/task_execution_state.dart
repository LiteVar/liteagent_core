import 'dart:async';

class TaskExecutionState {
  final String taskId;
  final String originalTaskId;
  final DateTime startedAt;

  Timer? deadlineTimer;
  String? terminalStatus;
  dynamic terminalDescription;

  TaskExecutionState({
    required this.taskId,
    required this.originalTaskId,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  bool get isTerminal => terminalStatus != null;

  bool tryTerminate(String status, dynamic description) {
    if (isTerminal) return false;
    terminalStatus = status;
    terminalDescription = description;
    deadlineTimer?.cancel();
    deadlineTimer = null;
    return true;
  }
}
