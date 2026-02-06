import '../llm/model.dart';
import 'llm/exception.dart';
import 'llm/openai_executor.dart';
import 'session_agent/model.dart';
import 'text_agent/model.dart';
import 'model.dart';
import 'package:unique_id_dart/unique_id_dart.dart';

class SimpleAgent {
  late String sessionId;
  LLMConfig? llmConfig;
  String? systemPrompt;
  ResponseFormat? responseFormat;
  List<void Function(AgentMessage)> agentMessageListeners = [];

  SimpleAgent({this.llmConfig, this.systemPrompt, this.responseFormat}) {
    this.sessionId = uniqueId();
  }

  void addAgentMessageListener(
      void Function(AgentMessage) agentMessageListener) {
    agentMessageListeners.add(agentMessageListener);
  }

  void addAgentMessageListeners(
      List<void Function(AgentMessage)> agentMessageListeners) {
    this.agentMessageListeners.addAll(agentMessageListeners);
  }

  Future<AgentMessage> userToAgent(
      {required List<Content> contentList,
      String? originalTaskId,
      String? parentTaskId,
      LLMConfig? requestLLMConfig}) async {
    String taskId = uniqueId();
    originalTaskId = originalTaskId ?? taskId;

    List<AgentMessage> agentLlmMessageList = [];

    if (systemPrompt != null && systemPrompt!.isNotEmpty) {
      AgentMessage systemMessage = AgentMessage(
          sessionId: sessionId,
          originalTaskId: originalTaskId,
          parentTaskId: parentTaskId,
          taskId: taskId,
          role: TextRoleType.DEVELOPER,
          to: TextRoleType.AGENT,
          type: TextMessageType.TEXT,
          content: systemPrompt);
      agentLlmMessageList.add(systemMessage);
      _broadcastAgentMessages(systemMessage);
    }

    AgentMessage userMessage = AgentMessage(
        sessionId: sessionId,
        originalTaskId: originalTaskId,
        parentTaskId: parentTaskId,
        taskId: taskId,
        role: TextRoleType.AGENT,
        to: TextRoleType.ASSISTANT,
        type: TextMessageType.CONTENT_LIST,
        content: contentList);
    agentLlmMessageList.add(userMessage);
    _broadcastAgentMessages(userMessage);

    LLMConfig? effectiveLLMConfig = requestLLMConfig ?? llmConfig;
    if (effectiveLLMConfig == null) {
      throw LLMException(message: "LLM config is required");
    }
    return await OpenAIExecutor(effectiveLLMConfig).request(
        agentMessageList: agentLlmMessageList, responseFormat: responseFormat);
  }

  void _broadcastAgentMessages(AgentMessage agentMessage) {
    for (var listener in agentMessageListeners) {
      listener(agentMessage);
    }
  }
}
