import 'package:llamadart_openai/llamadart_openai.dart';

import '../../model.dart';
import '../chat_completions_client.dart';

class LlamadartOpenAIChatClientAdapter implements ChatCompletionsClient {
  LlamadartOpenAIChatClientAdapter(this.llmConfig) {
    final providerOptions = llmConfig.providerOptions ?? const {};
    final injected = providerOptions['llamadartClient'];
    if (injected is LlamadartOpenAI) {
      _client = injected;
      return;
    }
    _client = LlamadartOpenAI.llamadart(
      model: _buildModelOptions(providerOptions),
    );
  }

  final LLMConfig llmConfig;

  late final LlamadartOpenAI _client;

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
      _buildModelOptions(llmConfig.providerOptions ?? const {});
      return true;
    } catch (_) {
      return false;
    }
  }

  LocalModelOptions _buildModelOptions(Map<String, dynamic> providerOptions) {
    final configuredOptions = providerOptions['modelOptions'];
    if (configuredOptions is LocalModelOptions) {
      return configuredOptions;
    }

    final rawModel = providerOptions['models'] is Map
        ? (providerOptions['models'] as Map)[llmConfig.model]
        : null;
    final modelOptions = rawModel is Map ? rawModel : providerOptions;
    final modelPath = modelOptions['modelPath']?.toString();
    if (modelPath == null || modelPath.isEmpty) {
      throw ArgumentError(
        'Llamadart provider requires providerOptions.modelPath or '
        'providerOptions.models["${llmConfig.model}"].modelPath.',
      );
    }

    return LocalModelOptions(
      modelPath: modelPath,
      multimodalProjectorPath: modelOptions['multimodalProjectorPath']?.toString(),
      metadata: _metadataFrom(modelOptions['metadata']),
    );
  }

  Map<String, Object?> _metadataFrom(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }
}
