import '../llm/model.dart';
import '../session_agent/model.dart';

class TextRoleType {
  static const String DEVELOPER = SessionRoleType.SYSTEM; // system prompt
  static const String USER = SessionRoleType.USER; // user
  static const String AGENT = SessionRoleType.AGENT; // agent
  static const String ASSISTANT = AgentRoleType.LLM; // llm
  static const String CLIENT = SessionRoleType.CLIENT; // external caller
}

class TextMessageType {
  static String TEXT = SessionMessageType.TEXT; //String
  static String IMAGE_URL = SessionMessageType.IMAGE_URL; //String
  static String CONTENT_LIST = SessionMessageType.CONTENT_LIST; //List<Content>
  static String TASK_STATUS = SessionMessageType.TASK_STATUS; //TaskStatus
  static String EXCEPTION = "exception"; //Exception
}

class TextStatusType {
  static const String CHUNK_DONE = "chunkDone";
}

class ReasoningMessageType {
  static const String REASONING = AgentMessageType.REASONING; //String
  static const String TASK_STATUS = AgentMessageType.TASK_STATUS; //TaskStatus
}

class ReasoningStatusType {
  static const String CHUNK_DONE = "reasoningChunkDone";
}
