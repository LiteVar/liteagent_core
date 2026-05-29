import 'package:cactus_openai/cactus_openai.dart';

import '../../model.dart';
import '../chat_completions_client.dart';

class CactusOpenAIChatClientAdapter implements ChatCompletionsClient {
  final LLMConfig llmConfig;

  late final CactusOpenAIClient _client;

  CactusOpenAIChatClientAdapter(this.llmConfig) {
    final providerOptions = llmConfig.providerOptions ?? const {};
    _client = CactusOpenAIClient.fromConfig(
      CactusOpenAIClientConfig(
        modelRegistry: _buildModelRegistry(providerOptions),
        showLogs: providerOptions['showLogs'] == true,
        appId: providerOptions['appId'] as String?,
        telemetryCacheLocation:
            providerOptions['telemetryCacheLocation'] as String?,
        defaultCorpusDir: providerOptions['defaultCorpusDir'] as String?,
        defaultCacheIndex: providerOptions['defaultCacheIndex'] == true,
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
      _client.validateConfig();
      _resolveModel(llmConfig.model);
      return true;
    } catch (_) {
      return false;
    }
  }

  CactusModelRegistry _buildModelRegistry(Map<String, dynamic> providerOptions) {
    final rawModels = providerOptions['models'];
    if (rawModels is! Map) {
      throw ArgumentError(
        'Cactus provider requires providerOptions.models to be a map.',
      );
    }

    final Map<String, CactusResolvedModel> models = {};
    rawModels.forEach((key, value) {
      if (value is! Map) {
        throw ArgumentError(
          'Cactus provider model entry for "$key" must be a map.',
        );
      }

      final purposeValue = (value['purpose'] ?? 'chat').toString();
      final purpose = purposeValue == 'audio'
          ? CactusModelPurpose.audio
          : CactusModelPurpose.chat;

      final modelPath = value['modelPath']?.toString();
      if (modelPath == null || modelPath.isEmpty) {
        throw ArgumentError(
          'Cactus provider model entry for "$key" requires modelPath.',
        );
      }

      models[key.toString()] = CactusResolvedModel(
        id: value['id']?.toString() ?? key.toString(),
        purpose: purpose,
        modelPath: modelPath,
        corpusDir: value['corpusDir']?.toString(),
        cacheIndex: value['cacheIndex'] == true,
      );
    });

    return InMemoryCactusModelRegistry(models);
  }

  void _resolveModel(String model) {
    final registry = _client.modelRegistry;
    if (registry == null) {
      throw StateError('No Cactus model registry configured.');
    }
    registry.resolve(model, purpose: CactusModelPurpose.chat);
  }
}
