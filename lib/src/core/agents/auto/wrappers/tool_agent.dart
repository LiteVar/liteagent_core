import 'package:lite_agent_core_dart/src/core/agents/tool_agent/tool_agent.dart';
import 'package:opentool_dart/opentool_dart.dart';
import 'function.dart';

class AutoToolAgent extends ToolAgent {

  final List<IndexedFunction> indexedFunctions;

  AutoToolAgent({
    required super.sessionId,
    required super.llmConfig,
    required super.agentSession,
    super.systemPrompt,
    this.indexedFunctions = const [],
  }) {
    if (indexedFunctions.isNotEmpty) {
      toolDriverList = _buildToolDriverList();
    }
  }

  List<ToolDriver> _buildToolDriverList() {
    final toolDriverSet = <ToolDriver>{};
    for (var indexedFunction in indexedFunctions) {
      toolDriverSet.add(indexedFunction.toolDriver);
    }
    return toolDriverSet.toList();
  }

  @override
  Future<List<FunctionModel>> buildFunctionModelList() async {
    List<FunctionModel> functionModelList = [];
    indexedFunctions.forEach((IndexedFunction indexedFunction) {
      functionModelList.add(indexedFunction.functionModel);
    });
    return functionModelList;
  }
}