import 'dart:async';
import 'dart:io';
import 'package:liteagent_core/liteagent_core.dart';
import 'package:liteagent_core/liteagent_service.dart';
import 'package:dotenv/dotenv.dart';
import 'package:opentool_dart/opentool_client.dart' as ot;
import 'package:unique_id_dart/unique_id_dart.dart';
import '../custom_driver/mock_driver.dart';
import '../listener.dart';

/// [IMPORTANT] Prepare:
/// 1. Add LLM baseUrl and apiKey to `.env` file
String prompt =
    "Use tool function `sequentiallyRead` to read all items from storage, then summarize.";

Future<void> main() async {
  String sessionId = uniqueId();
  ToolAgent toolAgent = ToolAgent(
    sessionId: sessionId,
    llmConfig: _buildLLMConfig(),
    agentSession: _buildSession(sessionId),
    toolDriverList: await _buildToolDriverList(),
    systemPrompt: _buildSystemPrompt(),
  );

  void Function(String taskId) fetchTaskId = (String taskId) {
    _updateSession(toolAgent.agentSession, taskId);
  };

  await toolAgent.userToAgent(
    contentList: [Content(type: ContentType.TEXT, message: prompt)],
    stream: true,
    fetchTaskId: fetchTaskId,
  );

  toolAgent.agentSession.taskDoneAgentMessageList.forEach((AgentMessage agentMessage) {
    print(AgentMessageDto.fromModel(agentMessage).toJson());
  });
}

LLMConfig _buildLLMConfig() {
  DotEnv env = DotEnv();
  env.load(['example/.env']);

  return LLMConfig(
    baseUrl: env["baseUrl"]!,
    apiKey: env["apiKey"]!,
    model: "qwen3.5-27b",
  );
}

Future<List<ToolDriver>> _buildToolDriverList() async {
  String folder =
      "${Directory.current.path}${Platform.pathSeparator}example${Platform.pathSeparator}custom_driver";
  List<String> fileNameList = [
    "mock-tool.json"
  ];

  List<ToolDriver> toolDriverList = [];
  for (String fileName in fileNameList) {
    ot.OpenTool openTool = await ot.OpenToolJsonLoader()
        .loadFromFile("$folder${Platform.pathSeparator}$fileName");
    ToolDriver toolDriver = MockDriver(openTool);
    toolDriverList.add(toolDriver);
  }
  return toolDriverList;
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
    listenChunk(
      agentSession.sessionId,
      taskId,
      AgentMessageChunkDto.fromModel(agentMessageChunk),
    );
  });
}

/// Use Prompt engineering to design SystemPrompt
/// https://platform.openai.com/docs/guides/prompt-engineering
String _buildSystemPrompt() {
  return 'You are a tools caller, who can call tools to help me manage my storage.';
}
