import 'dart:async';
import 'package:lite_agent_core_dart/lite_agent_core.dart';

import '../model.dart';

class AgentSession {
  String sessionId;
  bool hasSystemMessage = false;
  List<AgentMessage> listenAgentMessageList = [];
  List<void Function(AgentMessage)> _agentMessageListenerList = [];
  List<void Function(AgentMessageChunk)> _agentMessageChunkListenerList = [];
  List<AgentMessage> taskDoneAgentMessageList = [];
  bool isStream = false;

  AgentSession({required this.sessionId});

  void clearMessage() {
    hasSystemMessage = false;
    listenAgentMessageList = [];
    taskDoneAgentMessageList = [];
  }

  void resetListener() { _agentMessageListenerList = []; }

  void addAgentMessageListener(void Function(AgentMessage) agentMessageListener) {
    _agentMessageListenerList.add(agentMessageListener);
  }

  void addAgentMessageChunkListener(void Function(AgentMessageChunk) agentMessageChunkListener) {
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

  Future<void> addListenAgentMessageChunk(AgentMessageChunk agentMessageChunk) async {
    _agentMessageChunkListenerList.forEach((agentLLMMessageChunkListener) async {
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