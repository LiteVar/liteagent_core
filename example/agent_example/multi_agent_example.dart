import 'dart:async';
import 'dart:io';
import 'package:lite_agent_core_dart/lite_agent_core.dart';
import 'package:lite_agent_core_dart/lite_agent_service.dart';
import 'package:dotenv/dotenv.dart';
import 'package:openrpc_dart/openrpc_dart.dart';
import 'package:opentool_dart/opentool_dart.dart';
import '../custom_driver/mock_driver.dart';
import '../listener.dart';

/// [IMPORTANT] Prepare:
/// 1. Add LLM baseUrl and apiKey to `.env` file
String prompt = "Find the text with ID 0 and translate it into Chinese.";

Future<void> main() async {
  String sessionId = uniqueId();
  LLMConfig llmConfig = _buildLLMConfig();
  MultiAgent multiAgent = MultiAgent(
    sessionId: sessionId,
    llmConfig: llmConfig,
    agentSession: _buildSession(sessionId),
    subAgentDriverList: await _buildSubAgentDriverList(llmConfig, sessionId),
    systemPrompt: "You play the role of a tool caller. You can help me decide which tool to call to complete the task according to my requirements. You can only call one tool at a time. \n\nYou support the following tools:\n\n 1. Translation\n 2. Add, delete, modify and query tools"
  );
  await multiAgent.userToAgent(contentList: [Content(type: ContentType.TEXT, message: prompt)]);
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

Future<List<AgentDriver>> _buildSubAgentDriverList(LLMConfig llmConfig, String originalSessionId) async {

  SimpleAgent simpleAgent = SimpleAgent(llmConfig: llmConfig, systemPrompt: "You are a translator, who can translate text to Chinese.",);
  NamedSimpleAgent namedSimpleAgent = NamedSimpleAgent(name: "translator", description: "Translate text to Chinese", agent: simpleAgent);
  SimpleAgentDriver simpleAgentDriver = SimpleAgentDriver(namedSimpleAgents: [namedSimpleAgent]);

  String sessionId = uniqueId();
  ToolAgent toolAgent = ToolAgent(
      sessionId: sessionId,
      llmConfig: llmConfig,
      agentSession: _buildSession(originalSessionId),
      toolDriverList: await _buildToolDriverList(),
      systemPrompt: _buildSystemPrompt()
  );
  NamedSessionAgent namedSessionAgent = NamedSessionAgent(name: "CRUDTools", description: "Add, delete, modify and query tools", agent: toolAgent);
  SessionAgentDriver sessionAgentDriver = SessionAgentDriver(namedSessionAgents: [namedSessionAgent]);

  List<AgentDriver> subAgentDriverList = [simpleAgentDriver, sessionAgentDriver];

  return subAgentDriverList;
}

Future<List<ToolDriver>> _buildToolDriverList() async {
  String folder = "${Directory.current.path}${Platform.pathSeparator}example${Platform.pathSeparator}custom_driver";
  List<String> fileNameList = [
    "mock-tool.json"
  ];

  List<ToolDriver> toolDriverList = [];
  for (String fileName in fileNameList) {
    OpenTool openTool = await OpenToolLoader().loadFromFile("$folder${Platform.pathSeparator}$fileName");
    ToolDriver toolDriver = MockDriver().bind(openTool);
    toolDriverList.add(toolDriver);
  }
  return toolDriverList;
}

AgentSession _buildSession(String originalSessionId) {
  AgentSession session = AgentSession();
  session.addAgentMessageListener((AgentMessage agentMessage) {
    listen(originalSessionId, AgentMessageDto.fromModel(agentMessage));
  });
  return session;
}

/// Use Prompt engineering to design SystemPrompt
/// https://platform.openai.com/docs/guides/prompt-engineering
String _buildSystemPrompt() {
  return 'You are a tools caller, who can call tools to help me manage my storage.';
}
