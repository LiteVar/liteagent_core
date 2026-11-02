import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:liteagent_core/liteagent_core.dart';
import 'package:liteagent_core/liteagent_service.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'package:unique_id_dart/unique_id_dart.dart';
import '../custom_driver/mock_driver.dart';
import '../listener.dart';

/// Auto Multi-Agent with Callback OpenTool Example
///
/// This example demonstrates the Auto Multi-Agent mode with callbackOpenTool:
/// - Preset tools (mock-tool): server-side tools that execute directly
/// - Callback tools (callback-tool): client-side tools that require callback
/// - Planner sees both tool types and assigns them to different task nodes
/// - When a node needs a callback tool, the client receives a FUNCTION_CALL message,
///   executes locally, and returns the result via OpenToolCallbackDriver.callback()

String prompt =
    "First, get the current time from the client. "
    "Then query the text storage count. "
    "Finally, calculate the expression '100 + 200 * 3' on the client side.";

Future<void> main() async {
  String sessionId = uniqueId();
  AgentSession agentSession = AgentSession(sessionId: sessionId);

  String callbackToolJson = await _loadCallbackToolJson();

  OpenToolCallbackDriver? callbackDriver;

  AutoMultiAgent autoMultiAgent = await AutoMultiAgent.create(
    sessionId: sessionId,
    llmConfig: _buildLLMConfig(),
    agentSession: agentSession,
    toolDriverList: await _buildToolDriverList(),
    clientOpenTool: CallbackOpenTool(
      opentool: callbackToolJson,
      timeout: 30,
      fetchClientDriver: (String sid, OpenToolCallbackDriver driver) {
        callbackDriver = driver;
        print('[CallbackOpenTool] fetchClientDriver received for session: $sid');
      },
    ),
    systemPrompt: "You are a smart Auto Multi-Agent system that can use both server-side and client-side tools.",
    llmConfigList: _buildLLMConfigList(),
  );

  _setupMessageListener(agentSession, () => callbackDriver);

  String taskId = '';
  await autoMultiAgent.userToAgent(
    contentList: [Content(type: ContentType.TEXT, message: prompt)],
    fetchTaskId: (String id) {
      taskId = id;
      print('[TaskId] $taskId');
    },
  );

  print('[Prompt] $prompt');

  await _waitForCompletion(300);

  autoMultiAgent.stop();
  print('[Stop]');

  await Future.delayed(Duration(seconds: 2));

  autoMultiAgent.clear();
  print('[Clear]');
}

void _setupMessageListener(
  AgentSession agentSession,
  OpenToolCallbackDriver? Function() getDriver,
) {
  agentSession.addAgentMessageListener((AgentMessage message) {
    AgentMessageDto dto = AgentMessageDto.fromModel(message);
    listen(agentSession.sessionId, message.taskId, dto);

    if (message.type == ToolMessageType.FUNCTION_CALL) {
      FunctionCall functionCall = message.content as FunctionCall;
      print('[Callback] Client received function call: ${functionCall.name}');

      ToolReturn toolReturn = _executeCallbackFunction(functionCall);

      OpenToolCallbackDriver? driver = getDriver();
      if (driver != null) {
        driver.callback(toolReturn);
        print('[Callback] Client returned result for: ${functionCall.name}');
      } else {
        print('[Callback] ERROR: callbackDriver not ready');
      }
    }
  });
}

ToolReturn _executeCallbackFunction(FunctionCall functionCall) {
  switch (functionCall.name) {
    case 'get_current_time':
      return ToolReturn(
        id: functionCall.id,
        result: {"result": DateTime.now().toIso8601String()},
      );
    case 'calculate':
      String expression = functionCall.arguments['expression'] as String? ?? '';
      String result = _simpleCalculate(expression);
      return ToolReturn(
        id: functionCall.id,
        result: {"result": result},
      );
    default:
      return ToolReturn(
        id: functionCall.id,
        result: {"error": "Unknown callback function: ${functionCall.name}"},
      );
  }
}

String _simpleCalculate(String expression) {
  try {
    expression = expression.replaceAll(' ', '');
    List<double> numbers = [];
    List<String> operators = [];
    String currentNumber = '';

    for (int i = 0; i < expression.length; i++) {
      String char = expression[i];
      if (char == '+' || char == '-' || char == '*' || char == '/') {
        if (currentNumber.isNotEmpty) {
          numbers.add(double.parse(currentNumber));
          currentNumber = '';
        }
        operators.add(char);
      } else {
        currentNumber += char;
      }
    }
    if (currentNumber.isNotEmpty) {
      numbers.add(double.parse(currentNumber));
    }

    // * / first
    for (int i = 0; i < operators.length;) {
      if (operators[i] == '*' || operators[i] == '/') {
        double result = operators[i] == '*'
            ? numbers[i] * numbers[i + 1]
            : numbers[i] / numbers[i + 1];
        numbers[i] = result;
        numbers.removeAt(i + 1);
        operators.removeAt(i);
      } else {
        i++;
      }
    }

    // + -
    double result = numbers[0];
    for (int i = 0; i < operators.length; i++) {
      if (operators[i] == '+') {
        result += numbers[i + 1];
      } else if (operators[i] == '-') {
        result -= numbers[i + 1];
      }
    }

    return result == result.toInt().toDouble()
        ? result.toInt().toString()
        : result.toString();
  } catch (e) {
    return 'Error: $e';
  }
}

LLMConfig _buildLLMConfig() {
  DotEnv env = DotEnv();
  env.load(['example/.env']);

  return LLMConfig(
    baseUrl: env["baseUrl"]!,
    apiKey: env["apiKey"]!,
    model: "qwen3.5-122b-a10b",
  );
}

List<LLMConfig> _buildLLMConfigList() {
  DotEnv env = DotEnv();
  env.load(['example/.env']);

  return [
    LLMConfig(
      baseUrl: env["baseUrl"]!,
      apiKey: env["apiKey"]!,
      model: "qwen3.5-122b-a10b",
    ),
  ];
}

Future<List<ToolDriver>> _buildToolDriverList() async {
  String folder =
      "${Directory.current.path}${Platform.pathSeparator}example${Platform.pathSeparator}custom_driver";
  OpenTool openTool = await OpenToolJsonLoader()
      .loadFromFile("$folder${Platform.pathSeparator}mock-tool.json");
  return [MockDriver(openTool)];
}

Future<String> _loadCallbackToolJson() async {
  String folder =
      "${Directory.current.path}${Platform.pathSeparator}example${Platform.pathSeparator}callback_example";
  File file = File("$folder${Platform.pathSeparator}callback-tool.json");
  return await file.readAsString();
}

Future<void> _waitForCompletion(int seconds) async {
  for (int i = seconds; i > 0; i--) {
    if (i % 10 == 0) print('Waiting... ${i}s remaining');
    await Future.delayed(Duration(seconds: 1));
  }
}
