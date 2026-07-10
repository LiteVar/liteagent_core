import 'dart:async';
import '../model.dart';
import 'model.dart';
import 'session_restore_state.dart';

class AgentSession {
  String sessionId;
  bool hasSystemMessage = false;
  List<AgentMessage> listenAgentMessageList = [];
  List<void Function(AgentMessage)> _agentMessageListenerList = [];
  List<void Function(AgentMessageChunk)> _agentMessageChunkListenerList = [];
  List<AgentMessage> taskDoneAgentMessageList = [];
  String? sessionSummary;
  int summaryMessageCount = 0;
  bool isStream = false;

  AgentSession({required this.sessionId});

  /// Silently restores completed context for the next LLM request.
  ///
  /// This intentionally does not populate [listenAgentMessageList] or notify
  /// listeners. Historical tasks are not replayed or executed.
  void restore(SessionRestoreState state) {
    taskDoneAgentMessageList = List<AgentMessage>.from(state.contextMessages);
    hasSystemMessage = state.contextMessages.any(
      (message) => message.role == SessionRoleType.SYSTEM,
    );
    sessionSummary = null;
    summaryMessageCount = 0;
  }

  void clearMessage() {
    hasSystemMessage = false;
    listenAgentMessageList = [];
    taskDoneAgentMessageList = [];
    sessionSummary = null;
    summaryMessageCount = 0;
  }

  void resetListener() {
    _agentMessageListenerList = [];
  }

  void addAgentMessageListener(
      void Function(AgentMessage) agentMessageListener) {
    _agentMessageListenerList.add(agentMessageListener);
  }

  void addAgentMessageChunkListener(
      void Function(AgentMessageChunk) agentMessageChunkListener) {
    _agentMessageChunkListenerList.add(agentMessageChunkListener);
  }

  List<void Function(AgentMessage)> getAgentMessageListenerList() {
    return _agentMessageListenerList;
  }

  List<void Function(AgentMessageChunk)> getAgentMessageChunkListenerList() {
    return _agentMessageChunkListenerList;
  }

  Future<void> addListenAgentMessage(AgentMessage agentMessage) async {
    _record(agentMessage);
    _broadcast(agentMessage);
  }

  Future<void> addListenAgentMessageChunk(
      AgentMessageChunk agentMessageChunk) async {
    _agentMessageChunkListenerList
        .forEach((agentLLMMessageChunkListener) async {
      agentLLMMessageChunkListener(agentMessageChunk);
    });
  }

  void addTaskDoneAgentMessageList(List<AgentMessage> agentMessageList) {
    this.taskDoneAgentMessageList.addAll(agentMessageList);
  }

  void _record(AgentMessage agentMessage) {
    listenAgentMessageList.add(agentMessage);
  }

  void _broadcast(AgentMessage agentMessage) {
    _agentMessageListenerList.forEach((agentLLMMessageListener) async {
      agentLLMMessageListener(agentMessage);
    });
  }
}
