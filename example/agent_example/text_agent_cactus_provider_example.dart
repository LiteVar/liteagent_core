import 'package:dotenv/dotenv.dart';
import 'package:liteagent_core_dart/liteagent_core.dart';

import '_text_agent_provider_shared.dart';

/// [IMPORTANT] Prepare:
/// 1. Add `cactusModelId` and `cactusModelPath` to `example/.env`
/// 2. Optional: add `cactusAppId`, `cactusShowLogs`, `cactusCorpusDir`
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
  final modelId = env['cactusModelId']!;
  final modelPath = env['cactusModelPath']!;

  return LLMConfig(
    provider: LLMProviderType.cactus,
    model: modelId,
    providerOptions: {
      'appId': env['cactusAppId'],
      'showLogs': env['cactusShowLogs']?.toLowerCase() == 'true',
      'defaultCorpusDir': env['cactusCorpusDir'],
      'models': {
        modelId: {
          'purpose': 'chat',
          'modelPath': modelPath,
          if (env['cactusCorpusDir'] != null)
            'corpusDir': env['cactusCorpusDir'],
          'cacheIndex': false,
        },
      },
    },
  );
}
