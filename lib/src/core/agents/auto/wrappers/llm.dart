import '../../../llm/model.dart';

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