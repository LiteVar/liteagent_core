import 'dart:async';
import 'package:lite_agent_core_dart/src/core/agents/tool_agent/tool_agent.dart';
import 'package:opentool_dart/opentool_dart.dart';
import 'function.dart';
import '../../session_agent/session.dart';
import '../../session_agent/model.dart';
import '../../../util/unique_id_generator.dart';
import '../../model.dart';
import '../../../llm/model.dart';
import '../auto_multi_agent.dart';

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

  static Future<String> executeWithTracking({
    required String functionName,
    required String userInput,
    required String taskId,
    required AutoMessageSender messageSender,
    required LLMConfig llmConfig,
    String? systemPrompt,
    List<IndexedFunction>? indexedFunctions,
    String? parentTaskId,
  }) async {
    final tempSession = _createTempSession();
    final completer = Completer<String>();
    String result = '';

    _setupMessageListener(tempSession, completer, result, messageSender);

    final agent = AutoToolAgent(
      sessionId: tempSession.sessionId,
      llmConfig: llmConfig,
      agentSession: tempSession,
      systemPrompt: systemPrompt,
      indexedFunctions: indexedFunctions ?? [],
    );

    final functionCall = FunctionCall(id: uniqueId(), name: functionName, arguments: {});

    try {
      await messageSender.sendFunctionCallStart(taskId, functionCall);

      await agent.userToAgent(
        contentList: [Content(type: ContentType.TEXT, message: userInput)],
        parentTaskId: parentTaskId ?? taskId,
      );

      final resultContent = await completer.future;
      
      await messageSender.sendFunctionCallDone(taskId, functionCall, resultContent);
      
      return resultContent;

    } catch (e) {
      final errorMessage = "$functionName failed: $e";
      await messageSender.sendFunctionCallDone(taskId, functionCall, errorMessage);
      return errorMessage;
    }
  }

  static AgentSession _createTempSession() {
    String tempSessionId = uniqueId();
    return AgentSession(sessionId: tempSessionId);
  }

  static void _setupMessageListener(
    AgentSession tempSession,
    Completer<String> completer,
    String result,
    AutoMessageSender messageSender,
  ) {
    String accumResult = result;
    
    tempSession.addAgentMessageListener((message) {

      messageSender.sendAgentMessage(message);

      if (message.type == SessionMessageType.TEXT &&
          message.role == SessionRoleType.AGENT &&
          message.to == SessionRoleType.USER &&
          message.content is String) {
        accumResult += message.content as String;
      }

      if (message.type == SessionMessageType.TASK_STATUS) {
        final taskStatus = message.content as TaskStatus;
        if (taskStatus.status == TaskStatusType.DONE || 
            taskStatus.status == TaskStatusType.STOP || 
            taskStatus.status == TaskStatusType.EXCEPTION) {
          if (!completer.isCompleted) {
            completer.complete(accumResult);
          }
        }
      }
    });
  }
}