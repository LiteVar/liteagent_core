import 'dart:convert';
import 'package:opentool_dart/opentool_client.dart' as ot;
import '../../llm/model.dart';
import '../llm/llm_executor.dart';
import '../llm/model.dart';
import '../model.dart';
import '../session_agent/model.dart';
import '../text_agent/model.dart';
import 'model.dart';
import 'reflector_driver.dart';
import '../../utils/unique_id_generator.dart';

class ReflectorAgent {
  LLMExecutor llmExecutor;
  String systemPrompt;
  late String sessionId;
  String? parentTaskId;

  ReflectorAgent({required this.llmExecutor, required this.systemPrompt, required this.sessionId, this.parentTaskId});

  Future<ReflectScore> evaluate(List<Content> contentList, String message, String originalTaskId, void Function(Completions? completions) subscribeCompletions) async {

    String userMessage = jsonEncode(contentList.map((content)=>content.toJson()).toList());

    String messageToReflect = message;

    try {
      // if FunctionCallList, remove "id" field from each FunctionCall for reflection
      List<dynamic> jsonList = jsonDecode(message);
      List<Map<String, dynamic>> jsonWithoutIdList = jsonList.map((dyn){
        Map<String, dynamic> json = dyn as Map<String, dynamic>;
        if(json["id"] != null) json.remove("id");
        return json;
      }).toList();
      messageToReflect = jsonEncode(jsonWithoutIdList);
    } catch(e) {
      //Do nothing
    }

    String text = "# User Request:\n\n```json\n$userMessage\n```\n\n# LLM Response:\n\n```text\n$messageToReflect\n```";

    Content content = Content(type: ContentType.TEXT, message: text);

    List<Content> reflectContentList = [content];

    List<AgentMessage> agentLLMMessageList = [];

    String taskId = uniqueId();

    if(systemPrompt.isNotEmpty) {
      AgentMessage systemMessage = AgentMessage(
        sessionId: sessionId,
        originalTaskId: originalTaskId,
        parentTaskId: parentTaskId,
        taskId: taskId,
        role: TextRoleType.DEVELOPER,
        to: TextRoleType.AGENT,
        type: TextMessageType.TEXT,
        content: systemPrompt
      );
      agentLLMMessageList.add(systemMessage);
    }

    AgentMessage reflectMessage = AgentMessage(
      sessionId: sessionId,
      originalTaskId: originalTaskId,
      parentTaskId: parentTaskId,
      taskId: taskId,
      role: TextRoleType.AGENT,
      to: TextRoleType.ASSISTANT,
      type: TextMessageType.CONTENT_LIST,
      content: reflectContentList
    );

    agentLLMMessageList.add(reflectMessage);

    ReflectorDriver reflectionDriver = ReflectorDriver();

    AgentMessage llmMessage = await llmExecutor.request(agentMessageList: agentLLMMessageList, functionModelList: reflectionDriver.parse());
    subscribeCompletions(llmMessage.completions);
    if (llmMessage.type == AgentMessageType.TOOL_CALLS) {
      List<ot.FunctionCall> functionCallList = llmMessage.content as List<ot.FunctionCall>;
      ot.FunctionCall functionCall = functionCallList.first;
      try {
        ReflectScore reflectScore = ReflectScore.fromJson(functionCall.arguments);
        return reflectScore;
      } catch(e) {
        return ReflectScore(score: 0, description: e.toString());
      }
    } else {
      return ReflectScore(score: 0, description: "ReflectorAgent reply message type is NOT functionCallList");
    }
  }
}

