import 'package:opentool_dart/opentool_client.dart';

import '../tool_agent/model.dart';

class MultiAgentRoleType {
  static const String DEVELOPER = ToolRoleType.DEVELOPER; // system prompt
  static const String USER = ToolRoleType.USER; // user
  static const String AGENT = ToolRoleType.AGENT; // agent
  static const String SUBAGENT = "subAgent"; // subagent
  static const String ASSISTANT = ToolRoleType.ASSISTANT; // llm
  static const String TOOL = ToolRoleType.TOOL; // external tools
  static const String CLIENT = ToolRoleType.CLIENT; // external caller
  static const String REFLECTION = ToolRoleType.REFLECTION; // reflection
}

class MultiAgentMessageType {
  static String TEXT = ToolMessageType.TEXT; //String
  static String IMAGE_URL = ToolMessageType.IMAGE_URL; //String
  static String CONTENT_LIST = ToolMessageType.CONTENT_LIST; //List<Content>
  static String TOOL_CALLS = ToolMessageType.TOOL_CALLS; //List<FunctionCall>
  static String TOOL_RETURN = ToolMessageType.TOOL_RETURN; //ToolReturn
  static String TASK_STATUS = ToolMessageType.TASK_STATUS; //TaskStatus
  static String FUNCTION_CALL = ToolMessageType.FUNCTION_CALL; //FunctionCall
}

class MultiAgentStatusType {
  static const String START = "subAgentsStart";
  static const String DONE = "subAgentsDone";
}

class SeparatedFunctionCallList {
  List<FunctionCall> toolFunctionCalls;
  List<FunctionCall> subAgentFunctionCalls;
  bool hasToolFunctionCallsDone;
  bool hasSubAgentFunctionCallsDone;
  SeparatedFunctionCallList({this.toolFunctionCalls = const [], this.subAgentFunctionCalls = const [], this.hasToolFunctionCallsDone = false, this.hasSubAgentFunctionCallsDone = false});
}