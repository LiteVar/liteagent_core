import 'package:dotenv/dotenv.dart';
import 'package:liteagent_core_dart/liteagent_core.dart';

import '_text_agent_provider_shared.dart';

/// [IMPORTANT] Prepare:
/// 1. Add `llamadartModelId` and `llamadartModelPath` to `example/.env`
/// 2. Optional: add `llamadartMultimodalProjectorPath`
Future<void> main() async {
  await runTextAgentExample(
    llmConfig: _buildLLMConfig(),
    prompt: 'Who are you?',
    systemPrompt: 'You are a Q&A robot.',
    stream: true,
  );
}

LLMConfig _buildLLMConfig() {
  final env = DotEnv()..load(['example/.env']);
  final modelId = env['llamadartModelId']!;
  final modelPath = env['llamadartModelPath']!;

  return LLMConfig(
    provider: LLMProviderType.llamadart,
    model: modelId,
    providerOptions: {
      'modelPath': modelPath,
      if (env['llamadartMultimodalProjectorPath'] != null)
        'multimodalProjectorPath': env['llamadartMultimodalProjectorPath'],
    },
  );
}
