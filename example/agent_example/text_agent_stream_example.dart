import 'dart:async';
import 'package:dotenv/dotenv.dart';
import 'package:liteagent_core_dart/liteagent_core.dart';
import 'package:liteagent_core_dart/liteagent_service.dart';
import 'package:opentool_daemon/opentool_daemon_utils.dart';

import '../listener.dart';

/// [IMPORTANT] Prepare:
/// 1. Add LLM baseUrl and apiKey to `.env` file
String prompt = "Who are you?";

Future<void> main() async {
  String sessionId = uniqueId();
  TextAgent textAgent = TextAgent(
    sessionId: sessionId,
    llmConfig: _buildLLMConfig(),
    agentSession: _buildSession(sessionId),
    systemPrompt: _buildSystemPrompt()
  );

  void Function(String taskId) fetchTaskId = (String taskId) {
    _updateSession(textAgent.agentSession, taskId);
  };

  await textAgent.userToAgent(contentList: [Content(type: ContentType.TEXT, message: prompt)], stream: true, fetchTaskId: fetchTaskId);
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
  agentSession.addAgentMessageChunkListener((AgentMessageChunk agentMessageChunk) {
    listenChunk(agentSession.sessionId, taskId,  AgentMessageChunkDto.fromModel(agentMessageChunk));
  });
}

/// Use Prompt engineering to design SystemPrompt
/// https://platform.openai.com/docs/guides/prompt-engineering
String _buildSystemPrompt() {
  return 'You are a Q&A robot.';
}