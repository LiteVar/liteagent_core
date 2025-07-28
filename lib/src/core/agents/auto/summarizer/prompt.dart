import '../models/node.dart';

/// Auto task summary template
class SummaryPrompt {

  static String getSystemPrompt({
    required String userCommand,
    required List<AutoTaskNode> completedNodes,
  }) {
    return '''
你是专业的任务执行总结分析师，擅长分析多任务结果，理解用户需求，并高效提取关键信息，生成结构清晰、简洁实用的总结报告。

能力包括：
- 回溯用户需求，判断结果是否达标
- 提炼执行过程中的核心信息
- 结构化输出总结内容

总结原则：
- 用户导向：围绕用户需求，聚焦是否解决核心问题
- 结果导向：突出成果与影响，失败简述即可
- 简洁清晰：信息优先级明确，避免冗余
- 真实准确：仅基于实际结果，客观反映任务完成情况

## 输出格式要求
- 使用Markdown格式
- 适当使用emoji增强可读性
- 控制总长度在500字以内，不要超过500字
- 结构清晰，层次分明

以下是需要总结的内容：
用户需求：$userCommand
任务执行结果：${SummaryPrompt._formatExecutionDetails(completedNodes)}
''';
  }

  /// format node execution details to structured data for summary analysis
  static String _formatExecutionDetails(List<AutoTaskNode> completedNodes) {
    StringBuffer buffer = StringBuffer();
    
    int totalNodes = completedNodes.length;
    int successNodes = completedNodes.where((node) => node.status == AutoNodeStatus.SUCCEEDED).length;
    int failedNodes = completedNodes.where((node) => node.status == AutoNodeStatus.FAILED).length;
    
    buffer.writeln('- 总任务数：$totalNodes');
    buffer.writeln('- 成功完成：$successNodes');
    buffer.writeln('- 执行失败：$failedNodes');
    buffer.writeln();
    
    buffer.writeln('【详细执行结果】');
    for (AutoTaskNode node in completedNodes) {
      
      buffer.writeln("任务${node.id}: ${node.name}");

      if (node.dependencies.isNotEmpty) {
        buffer.writeln(" 依赖: ${node.dependencies.map((dep) => dep.id).join(', ')}");
      }
      
      if (node.result?.isNotEmpty == true) {
        String truncatedResult = _intelligentTruncate(node.result!, maxLength: 200);
        buffer.writeln(" 结果: $truncatedResult");
      }
      
      if (node.status == AutoNodeStatus.FAILED) {
        buffer.writeln(" 失败原因: ${node.result ?? '未知错误'}");
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