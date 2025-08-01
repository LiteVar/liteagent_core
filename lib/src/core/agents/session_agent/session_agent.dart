import 'dart:async';
import '../../util/unique_id_generator.dart';
import '../model.dart';
import '../pipeline/model.dart';
import '../pipeline/pipeline.dart';
import 'dispatcher.dart';
import 'exception.dart';
import 'model.dart';
import 'session.dart';
import 'timeout.dart';

abstract class SessionAgent {
  String sessionId;
  String? parentTaskId;
  String? systemPrompt;
  AgentSession agentSession;
  DispatcherMap dispatcherMap = DispatcherMap();
  late Timeout timeout;
  PipelineAsync<ContentsTask> pipeline;

  SessionAgent({
    required this.sessionId,
    required this.agentSession,
    this.systemPrompt,
    String taskPipelineStrategy = PipelineStrategyType.PARALLEL,
    timeoutSeconds = 600
  }) :  pipeline = PipelineAsync(taskPipelineStrategy),
        timeout = Timeout(timeoutSeconds);

  Future<void> userToAgent({required List<Content> contentList, bool? stream, String? originalTaskId, String? parentTaskId, void Function(String taskId)? fetchTaskId}) async {
    this.agentSession.isStream = stream??false;
    this.parentTaskId = parentTaskId;
    String taskId = uniqueId();
    if(fetchTaskId != null) fetchTaskId(taskId);
    dispatcherMap.create(taskId);
    originalTaskId = originalTaskId??taskId;

    pipeline.addJob(ContentsTask(taskId: taskId, contentList: contentList));
    AddStatusAsync statusAsync = await pipeline.runAsync(_userToAgent, asyncId: taskId, originalTaskId: originalTaskId);

    switch(statusAsync.addStatus) {
      case AddStatus.REJECT: {
        pipeline.completeAsync(taskId);
        Command clientCommand = Command(
          toClient,
          AgentMessage(
            sessionId: sessionId,
            originalTaskId: originalTaskId,
            parentTaskId: this.parentTaskId,
            taskId: taskId,
            role: SessionRoleType.AGENT,
            to: SessionRoleType.CLIENT,
            type: SessionMessageType.TASK_STATUS,
            content: TaskStatus(status: TaskStatusType.START, taskId: taskId, description: TaskRejectException(taskId: taskId, strategy: pipeline.pipelineStrategyType).toJson())
          ));
        dispatcherMap.dispatch(clientCommand);
      };
      case AddStatus.ERROR_STRATEGY: throw StrategyNotExistException(source: "task: $taskId", strategy: pipeline.pipelineStrategyType);
      case AddStatus.SUCCESS: break;
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
        content: TaskStatus(status: TaskStatusType.START, taskId: contentsTask.taskId)
      ));
    dispatcherMap.dispatch(clientCommand);

    AgentMessage contentMessage = AgentMessage(
      sessionId: sessionId,
      originalTaskId: originalTaskId,
      parentTaskId: parentTaskId,
      taskId: contentsTask.taskId,
      role: SessionRoleType.USER,
      to: SessionRoleType.AGENT,
      type: SessionMessageType.CONTENT_LIST,
      content: contentsTask.contentList
    );

    if ( systemPrompt == null || agentSession.hasSystemMessage ) {
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
        content: systemPrompt
      );
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

  void stop({String? taskId = null, String? originalTaskId}) {
    if(taskId == null) {
      AgentMessageBase stopMessage = AgentMessageBase(
        sessionId: sessionId,
        originalTaskId: originalTaskId??"",
        role: SessionRoleType.AGENT,
        to: SessionRoleType.CLIENT,
        type: SessionMessageType.TASK_STATUS,
        content: TaskStatus(status: TaskStatusType.STOP, taskId: taskId??"")
      );
      dispatcherMap.stopAll(toClient, stopMessage);
    } else {
      _stop(taskId, originalTaskId??"");
    }
  }

  void _stop(String taskId, String originalTaskId) {
    pipeline.completeAsync(taskId);
    Command clientCommand = Command(
      toClient,
      AgentMessage(
        sessionId: sessionId,
        originalTaskId: originalTaskId,
        parentTaskId: parentTaskId,
        taskId: taskId,
        role: SessionRoleType.AGENT,
        to: SessionRoleType.CLIENT,
        type: SessionMessageType.TASK_STATUS,
        content: TaskStatus(status: TaskStatusType.STOP, taskId: taskId)
      ));
    dispatcherMap.stop(taskId, clientCommand);
    timeout.start(clear);
  }

  void clear() {
    stop();
    agentSession.clearMessage();
    timeout.clear();
  }

}




