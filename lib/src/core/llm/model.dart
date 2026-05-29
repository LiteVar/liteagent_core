import 'package:dart_openai_sdk/dart_openai_sdk.dart';
import 'client/llm_provider_type.dart';

class LLMConfig {
  String provider;
  String baseUrl;
  String? apiKey;
  String model;
  String? adapter;
  Map<String, String>? headers;
  Map<String, dynamic>? providerOptions;
  double temperature;
  int maxTokens;
  int? contextWindowSize;
  double topP;
  bool supportsToolCall;
  bool supportsReasoning;
  LLMConfig(
      {this.provider = LLMProviderType.openai,
      this.baseUrl = "",
      this.apiKey,
      required this.model,
      this.adapter,
      this.headers,
      this.providerOptions,
      this.temperature = 0.0,
      this.maxTokens = 4096,
      this.contextWindowSize,
      this.topP = 1.0,
      this.supportsToolCall = true,
      this.supportsReasoning = false}) {
    provider = LLMProviderType.normalize(provider);
    adapter = adapter?.trim().isEmpty == true ? null : adapter?.trim();
  }
}

class Completions {
  TokenUsage tokenUsage;
  String id;
  String model;
  CompletionsLimits? limits;

  Completions({
    required this.tokenUsage,
    required this.id,
    required this.model,
    this.limits,
  });
}

class CompletionsLimits {
  final int maxTokens;
  final int? contextWindowSize;

  CompletionsLimits({required this.maxTokens, this.contextWindowSize});
}

class TokenUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final double? contextUsageRatio;

  TokenUsage(
      {required this.promptTokens,
      required this.completionTokens,
      required this.totalTokens,
      this.contextUsageRatio});
}

class ChatCompletion {
  OpenAIChatCompletionChoiceMessageModel message;
  Completions completions;

  ChatCompletion({required this.message, required this.completions});
}

class FinishReasonType {
  static String STOP = "stop";
  static String TOOL_CALLS = "tool_calls";
  static String LENGTH = "length";
  static String CONTENT_FILTER = "content_filter";
}

class ChatCompletionDelta {
  OpenAIStreamChatCompletionChoiceDeltaModel? delta;
  String? finishReason;
  Completions? completions;

  ChatCompletionDelta({this.delta, this.finishReason, this.completions});
}

class ResponseFormatType {
  static String TEXT = "text";
  static String JSON_OBJECT = "json_object";
  static String JSON_SCHEMA = "json_schema";
}

class ResponseFormat {
  String type;

  ResponseFormat({required this.type});

  Map<String, String> toJson() {
    return {"type": type};
  }
}
