import 'package:lite_oneapi/lite_oneapi.dart';

import '../../model.dart';
import '../chat_completions_client.dart';

class LiteOneApiChatClientAdapter implements ChatCompletionsClient {
  final LLMConfig llmConfig;

  late final LiteOneApiClient _client;

  LiteOneApiChatClientAdapter(this.llmConfig) {
    _client = LiteOneApiClient(
      config: LiteOneApiClientConfig(
        apiKey: llmConfig.apiKey,
        baseUrl: llmConfig.baseUrl,
        adapter: llmConfig.adapter ?? 'openai',
        headers: llmConfig.headers ?? const {},
      ),
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
      messages: messages,
      tools: tools,
      responseFormat: responseFormat,
      temperature: temperature,
      maxTokens: maxTokens,
      topP: topP,
      enableThinking: enableThinking,
      seed: 6,
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
      messages: messages,
      tools: tools,
      responseFormat: responseFormat,
      temperature: temperature,
      maxTokens: maxTokens,
      topP: topP,
      enableThinking: enableThinking,
      streamOptions: streamOptions,
      seed: 6,
    );
  }

  @override
  Future<bool> testConnection() async {
    try {
      await _client.chat.create(
        model: llmConfig.model,
        messages: [
          OpenAIChatCompletionChoiceMessageModel(
            role: OpenAIChatMessageRole.user,
            content: [
              OpenAIChatCompletionChoiceMessageContentItemModel.text('ping'),
            ],
          ),
        ],
        maxTokens: 1,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
