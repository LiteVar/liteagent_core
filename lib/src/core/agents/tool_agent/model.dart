import 'package:opentool_dart/opentool_client.dart';
import '../../driver/opentool/opentool_callback_driver.dart';
import '../llm/model.dart';
import '../text_agent/model.dart';

class ToolRoleType {
  static const String DEVELOPER = TextRoleType.DEVELOPER; // system prompt
  static const String USER = TextRoleType.USER; // user
  static const String AGENT = TextRoleType.AGENT; // agent
  static const String ASSISTANT = TextRoleType.ASSISTANT; // llm
  static const String TOOL = AgentRoleType.TOOL; // external tools
  static const String CLIENT = TextRoleType.CLIENT; // external caller
  static const String REFLECTION = TextRoleType.REFLECTION; // reflection
}

class ToolMessageType {
  static String TEXT = TextMessageType.TEXT; //String
  static String IMAGE_URL = TextMessageType.IMAGE_URL; //String
  static String CONTENT_LIST = TextMessageType.CONTENT_LIST; //List<Content>
  static String TOOL_CALLS = AgentMessageType.TOOL_CALLS; //List<FunctionCall>
  static String TOOL_RETURN = AgentMessageType.TOOL_RETURN; //ToolReturn
  static String TASK_STATUS = TextMessageType.TASK_STATUS; //TaskStatus
  static String FUNCTION_CALL = AgentMessageType.FUNCTION_CALL; //FunctionCall
}

class ToolStatusType {
  static const String START = "toolsStart";
  // static const String STOP = "toolStop";
  static const String DONE = "toolsDone";
  // static const String EXCEPTION = "toolException";
}

class ToolStatusDescription {
  List<String> functionCallIdList;

  ToolStatusDescription({this.functionCallIdList = const []});

  Map<String, dynamic> toJson() => {
        'functionCallIdList': functionCallIdList,
      };
}

class FunctionCallType {
  static const String TOOL = "tool";
  static const String SUBAGENT = "subAgent";
}

class FunctionCallParam {
  String sessionId;
  String taskId;
  String originalTaskId;
  String? type;
  int index;
  FunctionCall functionCall;
  FunctionCallParam(
      {required this.sessionId,
      required this.taskId,
      required this.originalTaskId,
      this.type,
      required this.index,
      required this.functionCall});
}

class CallbackOpenTool {
  String opentool;
  int? timeout;
  void Function(String sessionId, OpenToolCallbackDriver clientDriver)? fetchClientDriver;
  void Function(String sessionId, OpenToolCallbackDriver clientDriver)? releaseClientDriver;

  CallbackOpenTool({
    required this.opentool,
    this.timeout,
    this.fetchClientDriver,
    this.releaseClientDriver,
  });
}

class ToolExecutionLimits {
  final int _maxLlmRequests;
  final int _maxToolRounds;
  final int _maxToolCalls;
  final int _maxConsecutiveIdenticalToolRounds;
  final int _maxTaskDurationSeconds;

  const ToolExecutionLimits({
    int maxLlmRequests = 64,
    int maxToolRounds = 16,
    int maxToolCalls = 64,
    int maxConsecutiveIdenticalToolRounds = 3,
    int maxTaskDurationSeconds = 300,
  })  : _maxLlmRequests = maxLlmRequests,
        _maxToolRounds = maxToolRounds,
        _maxToolCalls = maxToolCalls,
        _maxConsecutiveIdenticalToolRounds = maxConsecutiveIdenticalToolRounds,
        _maxTaskDurationSeconds = maxTaskDurationSeconds;

  int get maxLlmRequests => _positiveOrDefault(_maxLlmRequests, 64);
  int get maxToolRounds => _positiveOrDefault(_maxToolRounds, 16);
  int get maxToolCalls => _positiveOrDefault(_maxToolCalls, 64);
  int get maxConsecutiveIdenticalToolRounds =>
      _positiveOrDefault(_maxConsecutiveIdenticalToolRounds, 3);
  int get maxTaskDurationSeconds => _positiveOrDefault(_maxTaskDurationSeconds, 300);

  static int _positiveOrDefault(int value, int fallback) {
    return value > 0 ? value : fallback;
  }
}
