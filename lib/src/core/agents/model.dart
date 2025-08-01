import '../llm/model.dart';

class Message {
  String sessionId;
  String? agentId;
  String? parentTaskId;
  String role;
  String to;
  String type;
  DateTime createTime = DateTime.now();
  Message({
    required this.sessionId,
    this.agentId,
     this.parentTaskId,
    required this.role,
    required this.to,
    required this.type
  });
}

class AgentMessageBase extends Message {
  dynamic content;
  String? reasoningContent;
  AgentMessageBase({
    required super.sessionId,
    super.agentId,
    super.parentTaskId,
    required super.role,
    required super.to,
    required super.type,
    required this.content,
    this.reasoningContent
  });
}

class AgentMessage extends AgentMessageBase {
  String taskId;
  Completions? completions;
  AgentMessage({
    required super.sessionId,
    super.agentId,
    required super.parentTaskId,
    required this.taskId,
    required super.role,
    required super.to,
    required super.type,
    required super.content,
    super.reasoningContent,
    this.completions
  });
}

class TaskStatus {
  String status;  // Follow TaskStatusType
  String taskId;
  Map<String, dynamic>? description;

  TaskStatus({required this.status, required this.taskId, this.description});

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      if(description != null)'description': description
    };
  }
}

class AgentMessageChunk extends Message {
  String taskId;
  dynamic part;

  AgentMessageChunk({
    required super.sessionId,
    super.agentId,
    required super.parentTaskId,
    required this.taskId,
    required super.role,
    required super.to,
    required super.type,
    required this.part
  });
}

