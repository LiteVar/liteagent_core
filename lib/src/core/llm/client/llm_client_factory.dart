import '../model.dart';
import 'adapters/cactus_openai_chat_client_adapter.dart';
import 'adapters/dart_openai_chat_client_adapter.dart';
import 'adapters/lite_oneapi_chat_client_adapter.dart';
import 'chat_completions_client.dart';
import 'llm_provider_type.dart';

class LLMClientFactory {
  static ChatCompletionsClient create(
    LLMConfig llmConfig, {
    Duration? requestsTimeout,
  }) {
    switch (LLMProviderType.normalize(llmConfig.provider)) {
      case LLMProviderType.openai:
        return DartOpenAIChatClientAdapter(
          llmConfig,
          requestsTimeout: requestsTimeout,
        );
      case LLMProviderType.cactus:
        return CactusOpenAIChatClientAdapter(llmConfig);
      case LLMProviderType.liteOneApi:
        return LiteOneApiChatClientAdapter(llmConfig);
      default:
        throw UnsupportedError(
          'Unsupported llm provider: ${llmConfig.provider}',
        );
    }
  }
}
