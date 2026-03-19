import '../models/node.dart';

/// Auto task summary prompt - generates user-facing answers from multi-task results
class SummaryPrompt {

  static String getSystemPrompt({
    required String userCommand,
    required List<AutoTaskNode> completedNodes,
  }) {
    return '''
你是一个智能助手，你的职责是根据多个子任务的执行结果，直接回答用户的原始问题。

核心要求：
- 直接回答用户的问题，像对话一样自然地给出答案
- 从各子任务结果中提取与用户问题相关的关键信息，整合为一个完整连贯的回答
- 不要提及"任务"、"子任务"、"执行"等内部概念，用户不需要知道背后的执行过程
- 如果某些部分未能获取到结果，简要说明该部分暂时无法提供即可，不要解释原因

回答原则：
- 聚焦问题本身，给出用户真正想要的答案
- 信息完整，将分散在不同结果中的内容有机整合
- 语言自然流畅，避免生硬的罗列
- 仅基于已有结果作答，不编造信息

## 输出格式
- 使用Markdown格式
- 适当使用emoji增强可读性
- 控制总长度在500字以内
- 根据内容自然组织结构，无需固定模板

用户问题：$userCommand
以下是各部分的结果信息：
${SummaryPrompt._formatNodeResults(completedNodes)}
''';
  }

  /// Format node results focusing on content rather than execution details
  static String _formatNodeResults(List<AutoTaskNode> completedNodes) {
    StringBuffer buffer = StringBuffer();

    for (AutoTaskNode node in completedNodes) {
      buffer.writeln('【${node.name}】');

      if (node.status == AutoNodeStatus.SUCCEEDED && node.result?.isNotEmpty == true) {
        String truncatedResult = _intelligentTruncate(node.result!, maxLength: 500);
        buffer.writeln(truncatedResult);
      } else if (node.status == AutoNodeStatus.FAILED) {
        buffer.writeln('[该部分未能获取到结果]');
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