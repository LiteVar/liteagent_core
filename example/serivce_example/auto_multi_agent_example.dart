import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:lite_agent_core_dart/lite_agent_core.dart';
import 'package:lite_agent_core_dart/lite_agent_service.dart';
import 'package:opentool_dart/opentool_dart.dart';
import '../custom_driver/mock_driver.dart';
import '../listener.dart';

/// Auto Multi-Agent Service Example with Multi-LLM Configuration
/// 
/// This example demonstrates the Auto Multi-Agent mode capabilities:
/// - Intelligent task decomposition and planning
/// - Multi-agent collaboration and coordination  
/// - Automatic agent selection and delegation
/// - Complex task execution with parallel processing
/// - Multi-LLM configuration for different task nodes
///
String prompt = "query text count, add text:hello, then modify to hi, then query text count again. pay attention to the impact of these operations";

AgentService agentService = AgentService();
Future<void> main() async {
  CapabilityDto capabilityDto = CapabilityDto(
      llmConfig: _buildLLMConfig(),
      systemPrompt: "You are a smart Auto Multi-Agent system",
      openSpecList: await _buildOpenSpecList(),
      auto: true,
      llmConfigList: _buildLLMConfigList(),
  );

  print("[CapabilityDto] " + capabilityDto.toJson().toString());

  List<ToolDriver> customToolDriverList = await _buildCustomToolDriverList();

  SessionDto sessionDto = await agentService.initSession(
    capabilityDto,
    /// If needed, add customToolDriverList here, for preset tools
    customToolDriverList: customToolDriverList
  );

  print("[SessionDto] " + sessionDto.toJson().toString());

  UserTaskDto userTaskDto = UserTaskDto(content: [ContentDto(type: ContentType.TEXT, message: prompt)]);
  await agentService.startSession(sessionDto.sessionId, userTaskDto, listen, listenChunk: listenChunk);

  print("[prompt] " + prompt);

  /// Auto mode requires more time for task planning and execution
  await sleep(200);

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
    model: "gpt-4o",
  );
}

List<LLMConfigDto> _buildLLMConfigList() {
  DotEnv env = DotEnv();
  env.load(['example/.env']);

  return [
    LLMConfigDto(
      baseUrl: env["baseUrl"]!,
      apiKey: env["apiKey"]!,
      model: "gpt-4o"
    ),
    LLMConfigDto(
      baseUrl: env["baseUrl"]!,
      apiKey: env["apiKey"]!,
      model: "gpt-4o-mini"
    ),
  ];
}

Future<List<OpenSpecDto>> _buildOpenSpecList() async {
  String folder = "${Directory.current.path}${Platform.pathSeparator}example${Platform.pathSeparator}json${Platform.pathSeparator}openrpc";
  List<String> fileNameList = [
    "json-rpc-book.json"

    /// you can add more tool spec json file.
    // "json-rpc-food.json"
  ];

  List<OpenSpecDto> openSpecList = [];
  for (String fileName in fileNameList) {
    File file = File("$folder${Platform.pathSeparator}$fileName");
    String jsonString = await file.readAsString();

    OpenSpecDto openSpecDto = OpenSpecDto(openSpec: jsonString, protocol: Protocol.JSONRPCHTTP);

    openSpecList.add(openSpecDto);
  }

  return openSpecList;
}

Future<List<ToolDriver>> _buildCustomToolDriverList() async {
  String folder = "${Directory.current.path}${Platform.pathSeparator}example${Platform.pathSeparator}custom_driver";
  List<String> fileNameList = [
    "mock-tool.json"
  ];

  List<ToolDriver> toolDriverList = [];
  for (String fileName in fileNameList) {
    String jsonPath = "$folder${Platform.pathSeparator}$fileName";

    OpenTool openTool = await OpenToolLoader().loadFromFile(jsonPath);
    ToolDriver toolDriver = MockDriver().bind(openTool);

    toolDriverList.add(toolDriver);
  }
  return toolDriverList;
} 