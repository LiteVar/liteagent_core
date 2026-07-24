import 'dart:async';
import '../model.dart';
import '../../llm/model.dart';
import '../pipeline/model.dart';
import '../pipeline/pipeline.dart';
import 'dispatcher.dart';
import 'exception.dart';
import 'model.dart';
import 'session.dart';
import 'task_execution_state.dart';
import 'timeout.dart';
import 'package:unique_id_dart/unique_id_dart.dart';

abstract class SessionAgent {
  String sessionId;
  String? parentTaskId;
  String? systemPrompt;
  AgentSession agentSession;
  DispatcherMap dispatcherMap = DispatcherMap();
  late Timeout timeout;
  void Function(String sessionId)? onIdleTimeout;
  PipelineAsync<ContentsTask> pipeline;
  final Map<String, LLMConfig> _requestLLMConfigMap = {};
  final Map<String, TaskExecutionState> _taskExecutionStateMap = {};
  final Set<String> _terminalTaskIds = {};
  bool _isClearing = false;

  SessionAgent({
    required this.sessionId,
    required this.agentSession,
    this.systemPrompt,
    String taskPipelineStrategy = PipelineStrategyType.PARALLEL,
    timeoutSeconds = 600,
    this.onIdleTimeout,
  })  : pipeline = PipelineAsync(taskPipelineStrategy),
        timeout = Timeout(timeoutSeconds);

  int? get taskExecutionTimeoutSeconds => null;

  bool isTaskActive(String taskId) {
    if (_terminalTaskIds.contains(taskId)) return false;
    final state = _taskExecutionStateMap[taskId];
    if (state == null) return true;
    return !state.isTerminal && dispatcherMap.isActive(taskId);
  }

  bool isTaskTerminal(String taskId) {
    if (_terminalTaskIds.contains(taskId)) return true;
    final state = _taskExecutionStateMap[taskId];
    return state?.isTerminal ?? false;
  }

  TaskExecutionState? getTaskExecutionState(String taskId) {
    return _taskExecutionStateMap[taskId];
  }

  Future<void> onTaskTerminating(TaskExecutionState state) async {}

  void registerTaskExecution(String taskId, String originalTaskId) {
    _terminalTaskIds.remove(taskId);
    final taskState = TaskExecutionState(
      taskId: taskId,
      originalTaskId: originalTaskId,
    );
    _taskExecutionStateMap[taskId] = taskState;
    final executionTimeoutSeconds = taskExecutionTimeoutSeconds;
    if (executionTimeoutSeconds != null && executionTimeoutSeconds > 0) {
      taskState.deadlineTimer = Timer(
        Duration(seconds: executionTimeoutSeconds),
        () {
          finishTask(
            taskId: taskId,
            status: TaskStatusType.EXCEPTION,
            description: {
              "code": "task_execution_timeout",
              "limit": "maxTaskDurationSeconds",
              "configured": executionTimeoutSeconds,
            },
          );
        },
      );
    }
  }

  Future<void> userToAgent(
      {required List<Content> contentList,
      bool? stream,
      String? originalTaskId,
      String? parentTaskId,
      LLMConfig? requestLLMConfig,
      void Function(String taskId)? fetchTaskId}) async {
    _isClearing = false;
    timeout.clear();
    this.agentSession.isStream = stream ?? false;
    this.parentTaskId = parentTaskId;
    String taskId = uniqueId();
    if (fetchTaskId != null) fetchTaskId(taskId);
    dispatcherMap.create(taskId);
    originalTaskId = originalTaskId ?? taskId;
    registerTaskExecution(taskId, originalTaskId);
    if (requestLLMConfig != null) {
      _requestLLMConfigMap[originalTaskId] = requestLLMConfig;
    }

    pipeline.addJob(ContentsTask(taskId: taskId, contentList: contentList));
    AddStatusAsync statusAsync =
        await pipeline.runAsync(_userToAgent, asyncId: taskId, originalTaskId: originalTaskId);

    switch (statusAsync.addStatus) {
      case AddStatus.REJECT:
        {
          await finishTask(
            taskId: taskId,
            status: TaskStatusType.EXCEPTION,
            description: TaskRejectException(
              taskId: taskId,
              strategy: pipeline.pipelineStrategyType,
            ).toJson(),
          );
        }
        ;
      case AddStatus.ERROR_STRATEGY:
        throw StrategyNotExistException(
            source: "task: $taskId", strategy: pipeline.pipelineStrategyType);
      case AddStatus.SUCCESS:
        break;
    }
  }

  Future<void> _userToAgent(ContentsTask contentsTask, String originalTaskId) async {
    Command clientCommand = Command(
        toClient,
        AgentMessage(
            sessionId: sessionId,
            originalTaskId: originalTaskId,
            parentTaskId: this.parentTaskId,
            taskId: contentsTask.taskId,
            role: SessionRoleType.AGENT,
            to: SessionRoleType.CLIENT,
            type: SessionMessageType.TASK_STATUS,
            content: TaskStatus(status: TaskStatusType.START, taskId: contentsTask.taskId)));
    dispatcherMap.dispatch(clientCommand);

    AgentMessage contentMessage = AgentMessage(
        sessionId: sessionId,
        originalTaskId: originalTaskId,
        parentTaskId: parentTaskId,
        taskId: contentsTask.taskId,
        role: SessionRoleType.USER,
        to: SessionRoleType.AGENT,
        type: SessionMessageType.CONTENT_LIST,
        content: contentsTask.contentList);

    if (systemPrompt == null || agentSession.hasSystemMessage) {
      dispatcherMap.dispatch(Command(toAgent, contentMessage));
    } else {
      dispatcherMap.dispatch(Command(_initSystemMessage, contentMessage));
    }
  }

  Future<void> toAgent(AgentMessage agentMessage);

  Future<void> _initSystemMessage(AgentMessage sessionMessage) async {
    if (systemPrompt != null && systemPrompt!.isNotEmpty) {
      AgentMessage systemMessage = AgentMessage(
          sessionId: sessionMessage.sessionId,
          originalTaskId: sessionMessage.originalTaskId,
          parentTaskId: this.parentTaskId,
          taskId: sessionMessage.taskId,
          role: SessionRoleType.SYSTEM,
          to: SessionRoleType.AGENT,
          type: SessionMessageType.TEXT,
          content: systemPrompt);
      agentSession.addTaskDoneAgentMessageList([systemMessage]);
      agentSession.hasSystemMessage = true;
      await toAgent(systemMessage);
    }
    Command command = Command(toAgent, sessionMessage);
    dispatcherMap.dispatch(command);
  }

  Future<void> toClient(AgentMessage sessionMessage) async {
    agentSession.addListenAgentMessage(sessionMessage);
  }

  Future<bool> finishTask({
    required String taskId,
    required String status,
    dynamic description,
    bool saveTaskHistory = false,
  }) async {
    final state = _taskExecutionStateMap[taskId];
    if (state == null || !state.tryTerminate(status, description)) return false;

    final taskMessages = saveTaskHistory
        ? List<AgentMessage>.from(dispatcherMap.getTaskMessageList(taskId))
        : const <AgentMessage>[];

    pipeline.completeAsync(taskId);
    clearTaskLLMConfig(state.originalTaskId);

    try {
      await onTaskTerminating(state);
    } finally {
      dispatcherMap.remove(taskId);
      _terminalTaskIds.add(taskId);
      _taskExecutionStateMap.remove(taskId);
      if (!_isClearing) {
        final terminalMessage = AgentMessage(
          sessionId: sessionId,
          originalTaskId: state.originalTaskId,
          parentTaskId: parentTaskId,
          taskId: taskId,
          role: SessionRoleType.AGENT,
          to: SessionRoleType.CLIENT,
          type: SessionMessageType.TASK_STATUS,
          content: TaskStatus(
            status: status,
            taskId: taskId,
            description: description,
          ),
        );
        await toClient(terminalMessage);
      }
      if (saveTaskHistory) {
        agentSession.addTaskDoneAgentMessageList(taskMessages);
      }
      if (!_isClearing && _taskExecutionStateMap.values.every((state) => state.isTerminal)) {
        timeout.start(handleIdleTimeout);
      }
    }
    return true;
  }

  void stop({String? taskId, String? originalTaskId}) {
    if (taskId == null) {
      for (final activeTaskId in dispatcherMap.activeTaskIds()) {
        finishTask(taskId: activeTaskId, status: TaskStatusType.STOP);
      }
    } else {
      finishTask(taskId: taskId, status: TaskStatusType.STOP);
    }
  }

  void clear() {
    _isClearing = true;
    stop();
    agentSession.clearMessage();
    timeout.clear();
    _requestLLMConfigMap.clear();
    for (final state in _taskExecutionStateMap.values) {
      state.deadlineTimer?.cancel();
    }
  }

  void handleIdleTimeout() {
    if (onIdleTimeout != null) {
      onIdleTimeout!(sessionId);
      return;
    }
    clear();
  }

  LLMConfig? resolveTaskLLMConfig(String originalTaskId, {LLMConfig? defaultLLMConfig}) {
    return _requestLLMConfigMap[originalTaskId] ?? defaultLLMConfig;
  }

  void setTaskLLMConfig(String originalTaskId, LLMConfig requestLLMConfig) {
    _requestLLMConfigMap[originalTaskId] = requestLLMConfig;
  }

  void clearTaskLLMConfig(String originalTaskId) {
    _requestLLMConfigMap.remove(originalTaskId);
  }
}
