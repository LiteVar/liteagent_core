import 'dart:async';
import 'package:dart_openai_sdk/dart_openai_sdk.dart';
import 'model.dart';

class OpenAIUtil {
  late LLMConfig llmConfig;
  late OpenAIClient _client;

  OpenAIUtil(this.llmConfig, {Duration? requestsTimeout}) {
    _client = OpenAIClient(
      apiKey: llmConfig.apiKey,
      baseUrl: llmConfig.baseUrl,
      requestsTimeOut: requestsTimeout ?? const Duration(seconds: 300),
      showLogs: false,
    );
  }

  static Future<bool> checkLLMConfig(String baseUrl, String apiKey) async {
    try {
      OpenAIClient tempClient = OpenAIClient(
        apiKey: apiKey,
        baseUrl: baseUrl,
        showLogs: false,
      );
      bool isConnected = await tempClient.testConnection();
      return isConnected;
    } catch(e) {
      print(e);
      return false;
    }
  }

  Future<ChatCompletion> chat({required List<OpenAIChatCompletionChoiceMessageModel> messageList, List<OpenAIToolModel>? toolList, ResponseFormat? responseFormat, bool? enableThinking}) async {
    Map<String, dynamic>? responseFormatJson = null;
    if(responseFormat != null) responseFormatJson = responseFormat.toJson();
    OpenAIChatCompletionModel chatCompletion = await _client.chat.create(
      model: llmConfig.model,
      responseFormat: responseFormatJson,
      seed: 6,
      messages: messageList,
      tools: toolList,
      temperature: llmConfig.temperature,
      maxTokens: llmConfig.maxTokens,
      topP: llmConfig.topP,
      enableThinking: enableThinking,
    );

    TokenUsage tokenUsage = TokenUsage(
      promptTokens: chatCompletion.usage.promptTokens,
      completionTokens: chatCompletion.usage.completionTokens,
      totalTokens: chatCompletion.usage.totalTokens
    );

    Completions completions = Completions(tokenUsage: tokenUsage, id: chatCompletion.id, model: llmConfig.model);

    return ChatCompletion(message: chatCompletion.choices.first.message, completions: completions);
  }

  Future<Stream<ChatCompletionDelta>> chatByStream({required List<OpenAIChatCompletionChoiceMessageModel> messageList, List<OpenAIToolModel>? toolList, ResponseFormat? responseFormat, bool? enableThinking}) async {
    Map<String, dynamic>? responseFormatJson = null;
    if(responseFormat != null) responseFormatJson = responseFormat.toJson();
    Stream<OpenAIStreamChatCompletionModel> chatCompletionStream = await _client.chat.createStream(
      model: llmConfig.model,
      responseFormat: responseFormatJson,
      seed: 6,
      messages: messageList,
      tools: toolList,
      temperature: llmConfig.temperature,
      maxTokens: llmConfig.maxTokens,
      topP: llmConfig.topP,
      enableThinking: enableThinking,
      streamOptions: {"include_usage": true}
    );

    return chatCompletionStream.map((OpenAIStreamChatCompletionModel streamCompletion) {
      Completions? completions = null;
      if(streamCompletion.usage != null) {
        TokenUsage tokenUsage = TokenUsage(
          promptTokens: streamCompletion.usage!.promptTokens,
          completionTokens: streamCompletion.usage!.completionTokens,
          totalTokens: streamCompletion.usage!.totalTokens
        );
        completions = Completions(tokenUsage: tokenUsage, id: streamCompletion.id, model: llmConfig.model);
      }
      OpenAIStreamChatCompletionChoiceDeltaModel? delta = null;
      String? finishReason = null;
      if(streamCompletion.choices.length > 0) {
        delta = streamCompletion.choices.first.delta;
        finishReason = streamCompletion.choices.first.finishReason;
      }

      return ChatCompletionDelta(delta: delta, finishReason: finishReason, completions: completions);
    });
  }
}