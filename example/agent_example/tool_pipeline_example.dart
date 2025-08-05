import 'dart:async';
import 'dart:io';
import 'package:lite_agent_core_dart/lite_agent_core.dart';
import 'package:lite_agent_core_dart/lite_agent_service.dart';
import 'package:dotenv/dotenv.dart';
import 'package:opentool_dart/opentool_dart.dart' as ot;
import '../custom_driver/mock_driver.dart';
import '../listener.dart';

/// [IMPORTANT] Prepare:
/// 1. Some OpenSpec json file, according to `/example/json/*.json`, which is callable.
/// 2. Run your tool server, which is described in json file.
/// 3. Add LLM baseUrl and apiKey to `.env` file

Future<void> main() async {
  String sessionId = uniqueId();
  ToolAgent toolAgent = ToolAgent(
    sessionId: sessionId,
    llmConfig: _buildLLMConfig(),
    agentSession: _buildSession(sessionId),
    toolDriverList: await _buildToolDriverList(),
    systemPrompt: _buildSystemPrompt(),
    toolPipelineStrategy: PipelineStrategyType.SERIAL /// Can change to PARALLEL or REJECT to test
  );

  void Function(String taskId) fetchTaskId = (String taskId) {
    _updateSession(toolAgent.agentSession, taskId);
  };

  try {
    String prompt1 = "Help me set store a text 'hello1'.";
    await toolAgent.userToAgent(contentList: [Content(type: ContentType.TEXT, message: prompt1)], fetchTaskId: fetchTaskId);
  } on TaskRejectException catch (e) {
    print(e);
  }
  try {
    String prompt2 = "Help me set store a text 'hello22'.";
    await toolAgent.userToAgent(contentList: [Content(type: ContentType.TEXT, message: prompt2)], fetchTaskId: fetchTaskId);
  } on TaskRejectException catch (e) {
    print(e);
  }
  try {
    String prompt3 = "Help me set store a text 'hello333'.";
    await toolAgent.userToAgent(contentList: [Content(type: ContentType.TEXT, message: prompt3)], fetchTaskId: fetchTaskId);
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

Future<List<ToolDriver>> _buildToolDriverList() async {
  String folder = "${Directory.current.path}${Platform.pathSeparator}example${Platform.pathSeparator}custom_driver";
  List<String> fileNameList = [
    "mock-tool.json"
  ];

  List<ToolDriver> toolDriverList = [];
  for (String fileName in fileNameList) {
    ot.OpenTool openTool = await ot.OpenToolJsonLoader().loadFromFile("$folder${Platform.pathSeparator}$fileName");
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
}

/// Use Prompt engineering to design SystemPrompt
/// https://platform.openai.com/docs/guides/prompt-engineering
String _buildSystemPrompt() {
  return 'You are a tools caller, who can call tools to help me manage my storage.';
}
