import 'dart:async';

import 'package:dart_openai_sdk/dart_openai_sdk.dart';
import 'package:http/http.dart' as http;

import '../../model.dart';
import '../chat_completions_client.dart';

class DartOpenAIChatClientAdapter implements ChatCompletionsClient {
  final LLMConfig llmConfig;
  final Duration requestsTimeout;

  late final OpenAIClient _client;
  final Set<http.Client> _activeClients = {};

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
  }) async {
    final requestClient = http.Client();
    _activeClients.add(requestClient);
    try {
      return await _client.chat.create(
        model: model,
        responseFormat: responseFormat,
        seed: 6,
        messages: messages,
        tools: tools,
        temperature: temperature,
        maxTokens: maxTokens,
        topP: topP,
        enableThinking: enableThinking,
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
      responseFormat: responseFormat,
      seed: 6,
      messages: messages,
      tools: tools,
      temperature: temperature,
      maxTokens: maxTokens,
      topP: topP,
      enableThinking: enableThinking,
      streamOptions: streamOptions,
      client: requestClient,
    );
    return _trackStream(source, requestClient);
  }

  @override
  Future<bool> testConnection() {
    return _client.testConnection();
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
