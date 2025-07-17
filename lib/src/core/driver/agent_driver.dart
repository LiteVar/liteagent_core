import 'package:opentool_dart/opentool_dart.dart';

abstract class AgentDriver extends ToolDriver {
  String? parentTaskId;
  final String promptKey = "prompt";
  final String promptDescription = "A sentence described in natural language like a human. e.g. `Help me to do something.`";
  final String resultKey = "result";
  final int llmFunctionDescriptionMaxLength = 1024;

  void setParentTaskId(String parentTaskId) {
    this.parentTaskId = parentTaskId;
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

}