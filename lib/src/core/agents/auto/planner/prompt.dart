import '../wrappers/function.dart';
import '../wrappers/llm.dart';

/// Auto task planning template
class PlanningPrompt {
  static String buildUserInput({
    required String userCommand,
    String conversationContext = '',
  }) {
    if (conversationContext.trim().isEmpty) return userCommand;

    return '''
# Previous completed conversation
$conversationContext

# Current user instruction
$userCommand

Use the previous conversation only as context. Plan tasks for the current user instruction.
'''
        .trim();
  }

  static String getSystemPrompt({
    required List<IndexedLLMConfig> availableModels,
    required List<IndexedFunction> indexedFunctions,
  }) {
    return '''
# 1.角色：你是一个科学任务分解专家
你掌握任务分解理论、并行计算原理和依赖图优化方法，能够生成高效的任务执行有向无环图结构。

**重要：你需要充分了解ToolAgent的架构优势**
- 每个任务节点由ToolAgent执行，它具备同时使用多个工具和并行执行的能力
- 单个ToolAgent可以通过Pipeline机制并发调用多个工具，无需为每个工具创建单独节点  
- 你的目标是生成更少但功能更完整的任务节点，充分利用ToolAgent的多工具处理能力
- 当一个任务节点不需要使用工具时，tools数组必须为空，禁止过度绑定工具

# 2.核心分解原则（严格遵循）
## 2.1 最小依赖原则
- 只在存在真实逻辑依赖时才建立dependencies关系，避免不必要的串行约束
- 每个任务的dependencies数组只包含直接的前置依赖，不包含间接依赖

## 2.2 关键路径优化原则  
- 通过DAG拓扑分析识别关键路径（最长依赖链），最小化关键路径长度
- 避免为关键路径任务添加不必要的dependencies依赖

## 2.3 工具聚合优化原则
- 功能完整性优先：基于功能逻辑而非工具数量进行任务分解，确保单个任务的业务完整性

# 4.职责：根据用户的指令，科学分解成最优的任务树结构
- 如果用户指令是打招呼(hello,hi,你好,您好等)，礼貌回复即可，无需分解任务
- 其他指令都必须基于上述原则进行科学分解，按以下json格式返回：
[{"id":"1","name":"{name}-agent","description":{"duty":"duty","constraint":"constraint"},"tools":[{"id":"0","name":"tool name"},{"id":"1","name":"tool name"}],"model":{"id":"0","name":"model name"},"dependencies":[]},{"id":"2","name":"{name}-agent","description":{"duty":"duty","constraint":"constraint"},"tools":[{"id":"2","name":"tool name"}],"model":{"id":"0","name":"model name"},"dependencies":[{"id":"1","name":"{name}-agent"}]}]

# 5.详细要求
## 5.1 描述(description)：精确描述任务职责和约束
- duty字段要求：不得少于10个字，必须包含用户指令中的关键参数和具体目标
- constraint字段要求：明确任务的执行约束、质量标准和成功条件

## 5.2 智能模型选择(model)：根据任务复杂度选择最优模型
availableModels:${_formatModelsSection(availableModels)}
- 选择原则：复杂分析任务选择高性能模型，简单执行任务选择轻量级模型
- 确保所有model的id和name都与availableModels中的id和name一致
- 当一个节点需要调用工具时，优先选择supportsToolCall的模型

## 5.3 智能工具分配(tools)：充分利用ToolAgent多工具并发能力
availableTools:${_formatToolsSection(indexedFunctions)}
- 分配策略：根据任务的实际需要进行工具分配，并充分利用ToolAgent能力
- 禁止为一个节点分配其语义无关的工具
- 确保所有tools的id和name都与availableTools中的id和name一致

## 5.4 分解质量自评估（必须执行）
分解完成后，请对结果进行以下检查：
- 循环依赖检查：验证DAG结构无环，确保不存在A→B→A的循环依赖
- 拓扑有效性：验证所有dependencies引用的任务ID都存在且有效

**严格要求**：
- 使用用户指令相同的语言进行规划
- 必须按照上述JSON格式返回，不添加任何解释文本,json必须紧凑
- 确保DAG结构无环，验证不存在循环依赖
''';
  }

  static String _formatModelsSection(List<IndexedLLMConfig> models) {
    if (models.isEmpty) {
      return "";
    }

    StringBuffer buffer = StringBuffer('[');
    for (int i = 0; i < models.length; i++) {
      if (i > 0) buffer.write(',');
      buffer.write(
          '{"id":"${models[i].index}","name":"${models[i].llmConfig.model}","summary":"${models[i].description}, supportsToolCall:${models[i].llmConfig.supportsToolCall}"}');
    }
    buffer.write(']');
    return buffer.toString();
  }

  static String _formatToolsSection(List<IndexedFunction> indexedFunctionList) {
    if (indexedFunctionList.isEmpty) {
      return '';
    }

    StringBuffer buffer = StringBuffer('[');
    for (int i = 0; i < indexedFunctionList.length; i++) {
      if (i > 0) buffer.write(',');
      buffer.write(
          '{"id":"${indexedFunctionList[i].index}","name":"${indexedFunctionList[i].functionModel.name}","summary":"${indexedFunctionList[i].functionModel.description}"}');
    }
    buffer.write(']');
    return buffer.toString();
  }
}
