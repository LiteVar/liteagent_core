import 'dart:async';
import 'package:dotenv/dotenv.dart';
import 'package:liteagent_core_dart/liteagent_core.dart';
import 'package:liteagent_core_dart/liteagent_service.dart';
import '../listener.dart';

/// [IMPORTANT] Prepare:
/// 1. Add LLM baseUrl and apiKey to `.env` file

Future<void> main() async {
  String sessionId = uniqueId();
  TextAgent textAgent = TextAgent(
    sessionId: sessionId,
    llmConfig: _buildLLMConfig(),
    agentSession: _buildSession(sessionId),
    systemPrompt: _buildSystemPrompt(),
    taskPipelineStrategy: PipelineStrategyType.REJECT /// Can change to PARALLEL or SERIAL to test
  );

  void Function(String taskId) fetchTaskId = (String taskId) {
    _updateSession(textAgent.agentSession, taskId);
  };

  try {
    String prompt1 = "Who are you?";
    await textAgent.userToAgent(contentList: [Content(type: ContentType.TEXT, message: prompt1)], fetchTaskId: fetchTaskId);
  } on TaskRejectException catch (e) {
    print(e);
  }
  try {
    String prompt2 = "Where are you from?";
    await textAgent.userToAgent(contentList: [Content(type: ContentType.TEXT, message: prompt2)], fetchTaskId: fetchTaskId);
  } on TaskRejectException catch (e) {
    print(e);
  }
  try {
    String prompt3 = "What do you want to do?";
    await textAgent.userToAgent(contentList: [Content(type: ContentType.TEXT, message: prompt3)], fetchTaskId: fetchTaskId);
  } on TaskRejectException catch (e) {
    print(e);
  }

}

LLMConfig _buildLLMConfig() {
  DotEnv env = DotEnv();
  env.load(['example/.env']);

  return LLMConfig(
    baseUrl: env["baseUrl"]!,
    apiKey: env["apiKey"]!,
    model: "gpt-4o-mini",
  );
}

AgentSession _buildSession(String sessionId) {
  AgentSession session = AgentSession(sessionId: sessionId);
  return session;
}

void _updateSession(AgentSession agentSession, String taskId) {
  agentSession.addAgentMessageListener((AgentMessage agentMessage) {
    listen(agentSession.sessionId, taskId, AgentMessageDto.fromModel(agentMessage));
  });
}

/// Use Prompt engineering to design SystemPrompt
/// https://platform.openai.com/docs/guides/prompt-engineering
String _buildSystemPrompt() {
  return 'You are a Q&A robot.';
}
