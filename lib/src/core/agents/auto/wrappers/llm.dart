import '../../../llm/model.dart';

/// indexed LLM config class
/// used in AutoMultiAgent to manage multiple LLM model configurations
class IndexedLLMConfig {

  final int index;
  
  final LLMConfig llmConfig;
  
  final String? description;

  IndexedLLMConfig({
    required this.index,
    required this.llmConfig,
    this.description,
  });

  @override
  String toString() {
    return 'IndexedLLMConfig(index: $index, model: ${llmConfig.model}, description: $description)';
  }
} 