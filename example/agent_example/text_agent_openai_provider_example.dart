import 'package:dotenv/dotenv.dart';
import 'package:liteagent_core/liteagent_core.dart';

import '_text_agent_provider_shared.dart';

/// [IMPORTANT] Prepare:
/// 1. Add `baseUrl` and `apiKey` to `example/.env`
/// 2. Adjust `model` if your OpenAI-compatible endpoint uses another model id
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
    provider: LLMProviderType.openai,
    baseUrl: env['baseUrl']!,
    apiKey: env['apiKey']!,
    model: env['model'] ?? 'gpt-4o-mini',
  );
}
