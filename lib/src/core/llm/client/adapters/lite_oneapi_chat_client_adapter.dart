import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:lite_oneapi/lite_oneapi.dart';

import '../../model.dart';
import '../chat_completions_client.dart';

class LiteOneApiChatClientAdapter implements ChatCompletionsClient {
  final LLMConfig llmConfig;

  late final LiteOneApiClient _client;
  final Set<http.Client> _activeClients = {};

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
  }) async {
    final requestClient = http.Client();
    _activeClients.add(requestClient);
    try {
      return await _client.chat.create(
        model: model,
        messages: messages,
        tools: tools,
        responseFormat: responseFormat,
        temperature: temperature,
        maxTokens: maxTokens,
        topP: topP,
        enableThinking: enableThinking,
        seed: 6,
        client: requestClient,
      );
    } finally {
      _activeClients.remove(requestClient);
      requestClient.close();
    }
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
    final requestClient = http.Client();
    _activeClients.add(requestClient);
    final source = _client.chat.createStream(
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
      client: requestClient,
    );
    return _trackStream(source, requestClient);
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

  @override
  Future<void> cancelActiveRequests() async {
    final clients = _activeClients.toList();
    _activeClients.clear();
    for (final client in clients) {
      client.close();
    }
  }

  Stream<T> _trackStream<T>(Stream<T> source, http.Client requestClient) {
    late StreamController<T> controller;
    StreamSubscription<T>? subscription;

    void closeClient() {
      _activeClients.remove(requestClient);
      requestClient.close();
    }

    controller = StreamController<T>(
      onListen: () {
        subscription = source.listen(
          controller.add,
          onError: (Object error, StackTrace stackTrace) {
            controller.addError(error, stackTrace);
            closeClient();
            controller.close();
          },
          onDone: () {
            closeClient();
            controller.close();
          },
          cancelOnError: true,
        );
      },
      onCancel: () async {
        await subscription?.cancel();
        closeClient();
      },
    );
    return controller.stream;
  }
}
