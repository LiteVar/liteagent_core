import 'package:dart_openai_sdk/dart_openai_sdk.dart';

import '../../model.dart';
import '../chat_completions_client.dart';

class DartOpenAIChatClientAdapter implements ChatCompletionsClient {
  final LLMConfig llmConfig;
  final Duration requestsTimeout;

  late final OpenAIClient _client;

  DartOpenAIChatClientAdapter(
    this.llmConfig, {
    Duration? requestsTimeout,
  }) : requestsTimeout = requestsTimeout ?? const Duration(seconds: 300) {
    _client = OpenAIClient(
      apiKey: llmConfig.apiKey,
      baseUrl: llmConfig.baseUrl,
      requestsTimeOut: this.requestsTimeout,
      showLogs: false,
    );
  }

  @override
  Future<OpenAIChatCompletionModel> create({
    required String model,
    required List<OpenAIChatCompletionChoiceMessageModel> messages,
    List<OpenAIToolModel>? tools,
    Object? responseFormat,
    double? temperature,
    int? maxTokens,
    double? topP,
    bool? enableThinking,
  }) {
    return _client.chat.create(
      model: model,
      responseFormat: responseFormat,
      seed: 6,
      messages: messages,
      tools: tools,
      temperature: temperature,
      maxTokens: maxTokens,
      topP: topP,
      enableThinking: enableThinking,
    );
  }

  @override
  Stream<OpenAIStreamChatCompletionModel> createStream({
    required String model,
    required List<OpenAIChatCompletionChoiceMessageModel> messages,
    List<OpenAIToolModel>? tools,
    Object? responseFormat,
    double? temperature,
    int? maxTokens,
    double? topP,
    bool? enableThinking,
    Map<String, dynamic>? streamOptions,
  }) {
    return _client.chat.createStream(
      model: model,
      responseFormat: responseFormat,
      seed: 6,
      messages: messages,
      tools: tools,
      temperature: temperature,
      maxTokens: maxTokens,
      topP: topP,
      enableThinking: enableThinking,
      streamOptions: streamOptions,
    );
  }

  @override
  Future<bool> testConnection() {
    return _client.testConnection();
  }
}
