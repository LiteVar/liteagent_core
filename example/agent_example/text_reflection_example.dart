import 'dart:async';
import 'package:dotenv/dotenv.dart';
import 'package:liteagent_core_dart/liteagent_core.dart';
import 'package:liteagent_core_dart/liteagent_service.dart';

import '../listener.dart';

/// [IMPORTANT] Prepare:
/// 1. Add LLM baseUrl and apiKey to `.env` file
String prompt = "你好！";

Future<void> main() async {
  String sessionId = uniqueId();
  TextAgent textAgent = TextAgent(
    sessionId: sessionId,
    llmConfig: _buildLLMConfig(),
    agentSession: _buildSession(sessionId),
    systemPrompt: _buildSystemPrompt(),
    textReflectPromptList: _buildTextReflectPromptList(),
  );

  void Function(String taskId) fetchTaskId = (String taskId) {
    _updateSession(textAgent.agentSession, taskId);
  };

  await textAgent.userToAgent( contentList: [Content(type: ContentType.TEXT, message: prompt)], fetchTaskId: fetchTaskId);
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
  return 'You are a translate robot. Translate any user content language to English. Reply sentence after translating, not chatting.';
}

List<ReflectPrompt> _buildTextReflectPromptList() {
  LLMConfig llmConfig = _buildLLMConfig();
  return [
    ReflectPrompt(llmConfig: llmConfig, prompt: "You are a language reflector, you can reflect `LLM Response` language is English or not. If English, score is 10, else score is 0."),
  ];
}
