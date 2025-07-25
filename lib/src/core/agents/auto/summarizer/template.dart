import '../models/node.dart';

/// Auto task summary template
class AutoSummaryTemplate {

  static String getSummaryTemplate() {
    return '''
# 角色：你是一个专业的任务执行总结分析师
你具备深度的数据分析能力、总结归纳能力和用户需求理解能力，能够对复杂的多任务执行结果进行智能分析和总结。

# 核心能力
- **执行结果分析**：深度分析每个任务节点的执行状况、时长和结果质量
- **用户需求回溯**：准确理解用户原始需求，判断执行结果是否满足预期
- **关键信息提取**：从大量执行细节中提取最有价值的核心信息
- **结构化总结**：将复杂的执行过程组织成清晰易懂的总结报告

# 总结原则
## 1. 用户导向原则
- 始终以用户的原始需求为中心进行总结
- 重点关注用户最关心的核心问题是否得到解决
- 避免过度技术细节，注重实际价值和影响

## 2. 结果导向原则  
- 优先总结各任务的最终成果和实际效果
- 突出关键成就和重要发现
- 对失败任务进行简要说明，但不过分渲染

## 3. 简洁性原则
- 控制总结长度，避免冗长的描述
- 使用清晰的结构和层次
- 重要信息优先，次要细节可省略

## 4. 准确性原则
- 基于实际执行结果进行总结，不添加推测
- 准确反映任务完成状态和质量
- 如有错误或失败，客观描述原因

# 总结任务
请基于用户的原始需求和所有任务节点的执行结果，生成一份简洁而全面的执行总结。

## 总结要求
1. **需求回顾**：简要回顾用户的原始需求
2. **核心成果**：总结最重要的执行成果和发现  
4. **关键亮点**：突出显示最有价值的结果
5. **结论**：给出明确的完成状态和建议

## 输出格式要求
- 使用Markdown格式
- 适当使用emoji增强可读性
- 控制总长度在500字以内
- 结构清晰，层次分明

## 注意事项
- 避免简单罗列任务，要进行有机整合
- 重点关注对用户有实际价值的内容
- 保持客观中性的语调，既不过分乐观也不过分悲观
''';
  }

  /// format node execution details to structured data for summary analysis
  static String formatExecutionDetails(List<AutoTaskNode> completedNodes) {
    StringBuffer buffer = StringBuffer();
    
    int totalNodes = completedNodes.length;
    int successNodes = completedNodes.where((node) => node.status == AutoNodeStatus.SUCCEEDED).length;
    int failedNodes = completedNodes.where((node) => node.status == AutoNodeStatus.FAILED).length;
    
    buffer.writeln('【执行统计】');
    buffer.writeln('- 总任务数：$totalNodes');
    buffer.writeln('- 成功完成：$successNodes');
    buffer.writeln('- 执行失败：$failedNodes');
    buffer.writeln();
    
    buffer.writeln('【详细执行结果】');
    for (AutoTaskNode node in completedNodes) {
      String executionTime = node.executionTimeMs != null ? 
          " (耗时: ${node.executionTimeMs}ms)" : "";
      
      buffer.writeln("任务${node.id}: ${node.name}$executionTime");
      buffer.writeln("   职责: ${node.description.duty}");
      
      if (node.dependencies.isNotEmpty) {
        buffer.writeln("   依赖: ${node.dependencies.join(', ')}");
      }
      
      if (node.result?.isNotEmpty == true) {
        String truncatedResult = _intelligentTruncate(node.result!, maxLength: 200);
        buffer.writeln("   结果: $truncatedResult");
      }
      
      if (node.status == AutoNodeStatus.FAILED) {
        buffer.writeln("   失败原因: ${node.result ?? '未知错误'}");
      }
      
      buffer.writeln();
    }
    
    return buffer.toString();
  }

  /// intelligent truncate long text, keep important information
  static String _intelligentTruncate(String content, {int maxLength = 200}) {
    if (content.length <= maxLength) return content;
    
    // intelligent truncate logic
    String truncated = content.substring(0, maxLength - 3);
    
    // try to truncate at the period or newline, keep the integrity
    int lastPeriod = truncated.lastIndexOf('。');
    int lastNewline = truncated.lastIndexOf('\n');
    int lastSpace = truncated.lastIndexOf(' ');
    
    // select the best truncation point (priority period, then newline, then space)
    List<int> cutPoints = [lastPeriod, lastNewline, lastSpace]
        .where((i) => i > maxLength * 0.7) // ensure not to truncate too much
        .toList();
    
    if (cutPoints.isNotEmpty) {
      int bestCutPoint = cutPoints.reduce((a, b) => a > b ? a : b);
      truncated = truncated.substring(0, bestCutPoint);
    }
    
    return truncated + '...';
  }
} 