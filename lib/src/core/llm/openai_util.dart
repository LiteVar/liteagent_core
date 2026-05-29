import 'dart:async';
import 'package:dart_openai_sdk/dart_openai_sdk.dart';
import 'client/chat_completions_client.dart';
import 'client/llm_client_factory.dart';
import 'model.dart';

class OpenAIUtil {
  late LLMConfig llmConfig;
  late ChatCompletionsClient _client;

  OpenAIUtil(this.llmConfig, {Duration? requestsTimeout}) {
    _client = LLMClientFactory.create(
      llmConfig,
      requestsTimeout: requestsTimeout,
    );
  }

  static Future<bool> checkLLMConfig(
    String baseUrl,
    String? apiKey, {
    String provider = "openai",
    String? model,
    String? adapter,
    Map<String, String>? headers,
    Map<String, dynamic>? providerOptions,
  }) async {
    try {
      final client = LLMClientFactory.create(
        LLMConfig(
          provider: provider,
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model ?? "ping",
          adapter: adapter,
          headers: headers,
          providerOptions: providerOptions,
        ),
      );
      return await client.testConnection();
    } catch (e) {
      print(e);
      return false;
    }
  }

  static Future<bool> checkLLMConfigByConfig(LLMConfig llmConfig) async {
    try {
      final client = LLMClientFactory.create(llmConfig);
      return await client.testConnection();
    } catch (e) {
      print(e);
      return false;
    }
  }

  Future<ChatCompletion> chat(
      {required List<OpenAIChatCompletionChoiceMessageModel> messageList,
      List<OpenAIToolModel>? toolList,
      ResponseFormat? responseFormat,
      bool? enableThinking}) async {
    Map<String, dynamic>? responseFormatJson = null;
    if (responseFormat != null) responseFormatJson = responseFormat.toJson();
    OpenAIChatCompletionModel chatCompletion = await _client.create(
      model: llmConfig.model,
      responseFormat: responseFormatJson,
      messages: messageList,
      tools: toolList,
      temperature: llmConfig.temperature,
      maxTokens: llmConfig.maxTokens,
      topP: llmConfig.topP,
      enableThinking: enableThinking,
    );

    double? contextUsageRatio;
    if (llmConfig.contextWindowSize != null &&
        llmConfig.contextWindowSize! > 0) {
      contextUsageRatio =
          chatCompletion.usage.promptTokens / llmConfig.contextWindowSize!;
    }
    TokenUsage tokenUsage = TokenUsage(
      promptTokens: chatCompletion.usage.promptTokens,
      completionTokens: chatCompletion.usage.completionTokens,
      totalTokens: chatCompletion.usage.totalTokens,
      contextUsageRatio: contextUsageRatio,
    );

    Completions completions = Completions(
      tokenUsage: tokenUsage,
      id: chatCompletion.id,
      model: llmConfig.model,
      limits: _resolveCompletionsLimits(),
    );

    return ChatCompletion(
        message: chatCompletion.choices.first.message,
        completions: completions);
  }

  Future<Stream<ChatCompletionDelta>> chatByStream(
      {required List<OpenAIChatCompletionChoiceMessageModel> messageList,
      List<OpenAIToolModel>? toolList,
      ResponseFormat? responseFormat,
      bool? enableThinking}) async {
    Map<String, dynamic>? responseFormatJson = null;
    if (responseFormat != null) responseFormatJson = responseFormat.toJson();
    Stream<OpenAIStreamChatCompletionModel> chatCompletionStream =
        _client.createStream(
            model: llmConfig.model,
            responseFormat: responseFormatJson,
            messages: messageList,
            tools: toolList,
            temperature: llmConfig.temperature,
            maxTokens: llmConfig.maxTokens,
            topP: llmConfig.topP,
            enableThinking: enableThinking,
            streamOptions: {"include_usage": true});

    return chatCompletionStream
        .map((OpenAIStreamChatCompletionModel streamCompletion) {
      Completions? completions = null;
      if (streamCompletion.usage != null) {
        double? contextUsageRatio;
        if (llmConfig.contextWindowSize != null &&
            llmConfig.contextWindowSize! > 0) {
          contextUsageRatio = streamCompletion.usage!.promptTokens /
              llmConfig.contextWindowSize!;
        }
        TokenUsage tokenUsage = TokenUsage(
          promptTokens: streamCompletion.usage!.promptTokens,
          completionTokens: streamCompletion.usage!.completionTokens,
          totalTokens: streamCompletion.usage!.totalTokens,
          contextUsageRatio: contextUsageRatio,
        );
        completions = Completions(
          tokenUsage: tokenUsage,
          id: streamCompletion.id,
          model: llmConfig.model,
          limits: _resolveCompletionsLimits(),
        );
      }
      OpenAIStreamChatCompletionChoiceDeltaModel? delta = null;
      String? finishReason = null;
      if (streamCompletion.choices.length > 0) {
        delta = streamCompletion.choices.first.delta;
        finishReason = streamCompletion.choices.first.finishReason;
      }

      return ChatCompletionDelta(
          delta: delta, finishReason: finishReason, completions: completions);
    });
  }

  CompletionsLimits? _resolveCompletionsLimits() {
    try {
      final int maxTokens = llmConfig.maxTokens;
      final int? contextWindowSize = (llmConfig.contextWindowSize != null &&
              llmConfig.contextWindowSize! > 0)
          ? llmConfig.contextWindowSize
          : null;

      return CompletionsLimits(
        maxTokens: maxTokens,
        contextWindowSize: contextWindowSize,
      );
    } catch (_) {
      return null;
    }
  }
}
