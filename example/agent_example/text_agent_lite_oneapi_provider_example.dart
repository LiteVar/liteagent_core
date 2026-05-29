import 'package:dotenv/dotenv.dart';
import 'package:liteagent_core_dart/liteagent_core.dart';

import '_text_agent_provider_shared.dart';

/// [IMPORTANT] Prepare:
/// 1. Add `liteOneApiBaseUrl` and `liteOneApiApiKey` to `example/.env`
/// 2. Optional: add `liteOneApiAdapter`, defaults to `openai`
/// 3. Optional: add `liteOneApiModel`, defaults to `deepseek-v4-pro`
Future<void> main() async {
  await runTextAgentExample(
    llmConfig: _buildLLMConfig(),
    prompt: 'Who are you?',
    systemPrompt: 'You are a Q&A robot.',
  );
}

LLMConfig _buildLLMConfig() {
  final env = DotEnv()..load(['example/.env']);

  return LLMConfig(
    provider: LLMProviderType.liteOneApi,
    baseUrl: env['liteOneApiBaseUrl'] ?? env['baseUrl']!,
    apiKey: env['liteOneApiApiKey'] ?? env['apiKey']!,
    adapter: env['liteOneApiAdapter'],
    model: env['liteOneApiModel'] ?? 'deepseek-v4-pro',
  );
}
