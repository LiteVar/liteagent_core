import 'package:opentool_dart/opentool_dart.dart';

import '../agents/model.dart';

abstract class AgentDriver extends ToolDriver {
  String? parentTaskId;
  List<void Function(AgentMessage)> agentMessageListeners = [];
  final String promptKey = "prompt";
  final String promptDescription = "A sentence described in natural language like a human. e.g. `Help me to do something.`";
  final String resultKey = "result";
  final int llmFunctionDescriptionMaxLength = 1024;

  void setParentTaskId(String parentTaskId) {
    this.parentTaskId = parentTaskId;
  }

  void addAgentMessageListener(void Function(AgentMessage) agentMessageListener) {
    agentMessageListeners.add(agentMessageListener);
  }

  String truncateWithEllipsis(String text, int maxLength) {
    if (text.length <= maxLength) return text;

    String ellipsis = "...";

    String truncated = text.substring(0, maxLength-ellipsis.length);
    int lastSpace = truncated.lastIndexOf(' ');

    if (lastSpace != -1) {
      truncated = truncated.substring(0, lastSpace);
    }

    return '$truncated$ellipsis';
  }

  void broadcastAgentMessages(AgentMessage agentMessage) {
    for (var listener in agentMessageListeners) {
      listener(agentMessage);
    }
  }
  
  Future<ToolReturn> callAgent(FunctionCall functionCall, String originalTaskId);
}