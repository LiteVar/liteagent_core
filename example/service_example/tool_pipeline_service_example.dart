import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:liteagent_core/liteagent_core.dart';
import 'package:liteagent_core/liteagent_service.dart';
import '../listener.dart';

/// [IMPORTANT] Prepare:
/// 1. Some OpenSpec json file, according to `/example/json/open*/*.json`, which is callable.
/// 2. Run your tool server, which is described in json file.
/// 3. Add LLM baseUrl and apiKey to `.env` file


AgentService agentService = AgentService();

Future<void> main() async {
  CapabilityDto capabilityDto = CapabilityDto(
    llmConfig: _buildLLMConfig(),
    systemPrompt: _buildSystemPrompt(),
    openSpecList: await _buildOpenSpecList(),
    /// Add tool pipeline strategy here
    toolPipelineStrategy: PipelineStrategyType.REJECT
  );

  print("[CapabilityDto] " + capabilityDto.toJson().toString());

  SessionDto sessionDto = await agentService.initSession(capabilityDto);

  print("[SessionDto] " + sessionDto.toJson().toString());

  try {
    String prompt1 = "Help me set store a text 'hello1'.";
    UserTaskDto userTaskDto = UserTaskDto(content: [ContentDto(type: ContentType.TEXT, message: prompt1)]);
    await agentService.startSession(sessionDto.sessionId, userTaskDto, listen);
  } on TaskRejectException catch (e) {
    print(e);
  }
  try {
    String prompt2 = "Help me set store a text 'hello22'.";
    UserTaskDto userTaskDto = UserTaskDto(content: [ContentDto(type: ContentType.TEXT, message: prompt2)]);
    await agentService.startSession(sessionDto.sessionId, userTaskDto, listen);
  } on TaskRejectException catch (e) {
    print(e);
  }
  try {
    String prompt3 = "Help me set store a text 'hello333'.";
    UserTaskDto userTaskDto = UserTaskDto(content: [ContentDto(type: ContentType.TEXT, message: prompt3)]);
    await agentService.startSession(
      sessionDto.sessionId,
      userTaskDto,
      listen
    );
  } on TaskRejectException catch (e) {
    print(e);
  }

  await sleep(15);

  SessionTaskDto sessionTaskDto = SessionTaskDto(sessionId: sessionDto.sessionId);
  await agentService.stopSession(sessionTaskDto);
  print("[stopSession] ");

  await sleep(5);

  await agentService.clearSession(sessionDto.sessionId);
  print("[clearSession] ");
}

Future<void> sleep(int seconds) async {
  for (int i = seconds; i > 0; i--) {
    print(i);
    await Future.delayed(Duration(seconds: 1));
  }
}

LLMConfigDto _buildLLMConfig() {
  DotEnv env = DotEnv();
  env.load(['example/.env']);

  return LLMConfigDto(
    baseUrl: env["baseUrl"]!,
    apiKey: env["apiKey"]!,
    model: "gpt-4o-mini",
  );
}

Future<List<OpenSpecDto>> _buildOpenSpecList() async {
  String folder = "${Directory.current.path}${Platform.pathSeparator}example${Platform.pathSeparator}custom_driver";
  List<String> fileNameList = [
    "mock-tool.json"
  ];

  List<OpenSpecDto> openSpecList = [];
  for (String fileName in fileNameList) {
    File file = File("$folder${Platform.pathSeparator}$fileName");
    String jsonString = await file.readAsString();
    OpenSpecDto openSpecDto = OpenSpecDto(openSpec: jsonString, protocol: Protocol.OPENTOOL);
    openSpecList.add(openSpecDto);
  }

  return openSpecList;
}

/// Use Prompt engineering to design SystemPrompt
/// https://platform.openai.com/docs/guides/prompt-engineering
String _buildSystemPrompt() {
  return 'You are a tools caller, who can call tools to help me manage my storage.';
}
