import 'package:liteagent_core_dart/src/core/llm/client/adapters/dart_openai_chat_client_adapter.dart';
import 'package:liteagent_core_dart/src/core/llm/client/adapters/lite_oneapi_chat_client_adapter.dart';
import 'package:liteagent_core_dart/src/core/llm/client/adapters/llamadart_openai_chat_client_adapter.dart';
import 'package:liteagent_core_dart/src/core/llm/client/llm_client_factory.dart';
import 'package:liteagent_core_dart/src/core/llm/client/llm_provider_type.dart';
import 'package:liteagent_core_dart/src/core/llm/model.dart';
import 'package:test/test.dart';

void main() {
  group('LLMClientFactory', () {
    test('defaults to openai when provider is omitted', () {
      final client = LLMClientFactory.create(
        LLMConfig(
          model: 'gpt-4o-mini',
          baseUrl: 'https://api.openai.com/v1',
          apiKey: 'sk-test',
        ),
      );

      expect(client, isA<DartOpenAIChatClientAdapter>());
    });

    test('routes to lite_oneapi and defaults adapter to openai', () {
      final config = LLMConfig(
        provider: LLMProviderType.liteOneApi,
        model: 'qwen-plus',
        baseUrl: 'https://gateway.example.com/v1',
        apiKey: 'sk-test',
      );

      final client = LLMClientFactory.create(config);

      expect(client, isA<LiteOneApiChatClientAdapter>());
      expect(config.adapter, isNull);
    });

    test('routes to llamadart provider', () {
      final client = LLMClientFactory.create(
        LLMConfig(
          provider: LLMProviderType.llamadart,
          model: 'google/gemma-3-270m-it',
          providerOptions: {
            'models': {
              'google/gemma-3-270m-it': {
                'purpose': 'chat',
                'modelPath': '/tmp/gemma',
              },
            },
          },
        ),
      );

      expect(client, isA<LlamadartOpenAIChatClientAdapter>());
    });

    test('routes cactus provider aliases to llamadart', () {
      final client = LLMClientFactory.create(
        LLMConfig(
          provider: 'cactus_openai',
          model: 'google/gemma-3-270m-it',
          providerOptions: {
            'modelPath': '/tmp/gemma',
          },
        ),
      );

      expect(client, isA<LlamadartOpenAIChatClientAdapter>());
    });
  });
}
