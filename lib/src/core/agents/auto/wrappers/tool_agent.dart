import 'dart:async';
import 'package:opentool_dart/opentool_client.dart' as ot;
import '../../../driver/tool_driver.dart';
import '../../../driver/opentool/opentool_callback_driver.dart';
import '../../tool_agent/tool_agent.dart';
import '../../tool_agent/model.dart';
import 'function.dart';
import '../../session_agent/session.dart';
import '../../session_agent/model.dart';
import '../../model.dart';
import '../auto_multi_agent.dart';
import 'package:unique_id_dart/unique_id_dart.dart';

class AutoToolAgent extends ToolAgent {

  final List<IndexedFunction> indexedFunctions;

  AutoToolAgent({
    required super.sessionId,
    required super.llmConfig,
    required super.agentSession,
    super.systemPrompt,
    super.streamCallTimeoutSeconds,
    CallbackOpenTool? callbackOpenTool,
    this.indexedFunctions = const [],
  }) : super(callbackOpenTool: callbackOpenTool) {
    if (indexedFunctions.isNotEmpty) {
      toolDriverList = _buildToolDriverList();
    }
  }

  List<ToolDriver> _buildToolDriverList() {
    final toolDriverSet = <ToolDriver>{};
    for (var indexedFunction in indexedFunctions) {
      if (indexedFunction.toolDriver is OpenToolCallbackDriver) continue;
      toolDriverSet.add(indexedFunction.toolDriver);
    }
    return toolDriverSet.toList();
  }

  @override
  Future<List<ot.FunctionModel>> buildFunctionModelList([List<ToolDriver>? drivers]) async {
    if (indexedFunctions.isNotEmpty) {
      List<ot.FunctionModel> functionModelList = [];
      indexedFunctions.forEach((IndexedFunction indexedFunction) {
        functionModelList.add(indexedFunction.functionModel);
      });
      return functionModelList;
    }

    final driverList = drivers ?? toolDriverList;
    List<ot.FunctionModel> functionModelList = [];
    driverList.forEach((ToolDriver toolDriver) {
      functionModelList.addAll(toolDriver.parse());
    });
    return functionModelList;
  }

  Future<String> execute({
    required String userInput,
    required String originalTaskId,
    String? parentTaskId,
    required String functionName,
    required AutoMessageSender messageSender,
  }) async {

    final completer = Completer<String>();
    String result = '';

    _setupMessageListener(agentSession, completer, result, messageSender);

    final functionCall = ot.FunctionCall(id: uniqueId(), name: functionName, arguments: {});

    String taskId = uniqueId();
    void Function(String result) fetchTaskId = (String result) {
      taskId = result;
    };

    try {
      await messageSender.sendFunctionCallStart(taskId, functionCall);
      await super.userToAgent(
        contentList: [Content(type: ContentType.TEXT, message: userInput)],
        originalTaskId: originalTaskId,
        parentTaskId: parentTaskId,
        fetchTaskId: fetchTaskId,
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

  void _setupMessageListener(
    AgentSession agentSession,
    Completer<String> completer,
    String result,
    AutoMessageSender messageSender,
  ) {
    String accumResult = result;
    
    agentSession.addAgentMessageListener((message) {

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
