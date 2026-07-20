import 'dart:async';
import 'dart:convert';
import 'package:dart_openai_sdk/dart_openai_sdk.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'package:token_pack/token_pack.dart';
import '../text_agent/model.dart';
import 'context_normalizer.dart';
import 'exception.dart';
import '../../llm/openai_util.dart';
import '../../llm/model.dart';
import '../model.dart';
import 'llm_executor.dart';
import 'model.dart';

const String _streamEventsKey = "__streamEvents__";

class OpenAIExecutor extends OpenAIUtil implements LLMExecutor {
  late String _sessionId;
  String? _parentTaskId;
  late String _taskId;
  final int? toolReturnPackMinLength;

  OpenAIExecutor(
    super.llmConfig, {
    Duration? requestsTimeout,
    this.toolReturnPackMinLength,
  }) : super(requestsTimeout: requestsTimeout);

  Future<AgentMessage> request(
      {required List<AgentMessage> agentMessageList,
      List<FunctionModel>? functionModelList,
      ResponseFormat? responseFormat,
      bool? enableThinking}) async {
    AgentMessage agentMessage = agentMessageList
        .lastWhere((agentMessage) => agentMessage.role == AgentRoleType.AGENT);
    _sessionId = agentMessage.sessionId;
    _parentTaskId = agentMessage.parentTaskId;
    _taskId = agentMessage.taskId;
    List<OpenAIChatCompletionChoiceMessageModel> requestMessageList = [];

    for (AgentMessage agentMessage
        in normalizeReasoningContext(agentMessageList)) {
      if ((agentMessage.role == AgentRoleType.TOOL ||
              agentMessage.role == AgentRoleType.SUBAGENT) &&
          agentMessage.type == AgentMessageType.TASK_STATUS) {
        // If tool return status, skip
        continue;
      } else {
        requestMessageList.add(_buildOpenAIMessage(agentMessage));
      }
    }

    List<OpenAIToolModel>? tools = functionModelList
        ?.map((FunctionModel functionModel) =>
            _buildOpenAIToolModel(functionModel))
        .toList();

    try {
      ChatCompletion chatCompletion = await super.chat(
          messageList: requestMessageList,
          toolList: tools,
          responseFormat: responseFormat,
          enableThinking: enableThinking);

      return _toAgentMessage(
          chatCompletion.message, agentMessage.originalTaskId,
          completions: chatCompletion.completions);
    } catch (e) {
      throw LLMException(message: e.toString());
    }
  }

  Future<Stream<AgentMessage>> requestByStream(
      {required List<AgentMessage> agentMessageList,
      List<FunctionModel>? functionModelList,
      ResponseFormat? responseFormat,
      bool? enableThinking,
      void Function(AgentMessageChunk)? listenChunk}) async {
    AgentMessage agentMessage = agentMessageList
        .lastWhere((agentMessage) => agentMessage.role == AgentRoleType.AGENT);
    _sessionId = agentMessage.sessionId;
    _parentTaskId = agentMessage.parentTaskId;
    _taskId = agentMessage.taskId;
    List<OpenAIChatCompletionChoiceMessageModel> requestMessageList = [];

    for (AgentMessage agentMessage
        in normalizeReasoningContext(agentMessageList)) {
      if ((agentMessage.role == AgentRoleType.TOOL ||
              agentMessage.role == AgentRoleType.SUBAGENT) &&
          agentMessage.type == AgentMessageType.TASK_STATUS) {
        // If tool return status, skip
        continue;
      } else {
        requestMessageList.add(_buildOpenAIMessage(agentMessage));
      }
    }

    List<OpenAIToolModel>? tools = functionModelList
        ?.map((FunctionModel functionModel) =>
            _buildOpenAIToolModel(functionModel))
        .toList();

    try {
      Stream<ChatCompletionDelta> chatCompletionDeltaStream =
          await chatByStream(
              messageList: requestMessageList,
              toolList: tools,
              responseFormat: responseFormat,
              enableThinking: enableThinking);

      StreamController<AgentMessage> agentMessageStreamController =
          StreamController<AgentMessage>();

      DeltaAccumulation textAccumulation = _buildTextAccumulation(listenChunk,
          agentMessageStreamController, agentMessage.originalTaskId);
      final reasoningBuffer = StringBuffer();
      DeltaAccumulation functionCallAccumulation =
          _buildFunctionCallAccumulation(
        agentMessageStreamController,
        agentMessage.originalTaskId,
        reasoningContent: () => reasoningBuffer.toString(),
      );
      DeltaAccumulation reasoningAccumulation = _buildReasoningAccumulation(
          listenChunk,
          agentMessageStreamController,
          agentMessage.originalTaskId);
      String finishReasonCache = "";

      chatCompletionDeltaStream.listen((chatCompletionDelta) {
        if (chatCompletionDelta.finishReason == FinishReasonType.LENGTH)
          throw LLMException(
              message:
                  "The generation exceeded max_tokens or the conversation exceeded the max context length.");
        if (chatCompletionDelta.finishReason == FinishReasonType.CONTENT_FILTER)
          throw LLMException(
              message: "the content filtering system detects harmful content");
        finishReasonCache =
            chatCompletionDelta.finishReason ?? finishReasonCache;

        if (chatCompletionDelta.delta?.reasoningContent != null) {
          reasoningBuffer.write(chatCompletionDelta.delta!.reasoningContent!);
          AgentMessageChunk? reasoningChunk =
              _reasoningDeltaToAgentMessageChunk(
                  chatCompletionDelta, agentMessage.originalTaskId);
          if (reasoningChunk != null && listenChunk != null)
            listenChunk(reasoningChunk);
        }
        // Feed every delta to the reasoning accumulator. The first content or
        // tool-call delta is also the boundary that closes accumulated
        // reasoning and emits its durable AgentMessage counterpart.
        reasoningAccumulation.appendDelta(chatCompletionDelta);

        if (chatCompletionDelta.delta?.toolCalls != null ||
            chatCompletionDelta.finishReason == FinishReasonType.TOOL_CALLS ||
            (finishReasonCache == FinishReasonType.TOOL_CALLS &&
                chatCompletionDelta.completions != null)) {
          functionCallAccumulation.appendDelta(chatCompletionDelta);
        } else if (chatCompletionDelta.delta?.content != null ||
            chatCompletionDelta.finishReason == FinishReasonType.STOP ||
            (finishReasonCache == FinishReasonType.STOP &&
                chatCompletionDelta.completions != null)) {
          AgentMessageChunk? agentMessageChunk = _chunkDeltaToAgentMessageChunk(
              chatCompletionDelta, agentMessage.originalTaskId);
          if (agentMessageChunk != null && listenChunk != null)
            listenChunk(agentMessageChunk);
          textAccumulation.appendDelta(chatCompletionDelta);
        }
      }, onDone: () {
        textAccumulation.close();
        reasoningAccumulation.close();
        functionCallAccumulation.close();
        agentMessageStreamController.close();
      }, onError: (e) {
        agentMessageStreamController.addError(e);
      });

      return agentMessageStreamController.stream;
    } catch (e) {
      throw LLMException(message: e.toString());
    }
  }

  TextAccumulation _buildTextAccumulation(
      void Function(AgentMessageChunk)? listenChunk,
      StreamController<AgentMessage> agentMessageStreamController,
      String originalTaskId) {
    return TextAccumulation((text, Completions? completions) {
      if (listenChunk != null) {
        AgentMessageChunk chunkDoneMessageChunk = AgentMessageChunk(
            sessionId: _sessionId,
            originalTaskId: originalTaskId,
            parentTaskId: _parentTaskId,
            taskId: _taskId,
            role: AgentRoleType.LLM,
            to: AgentRoleType.AGENT,
            type: AgentMessageType.TASK_STATUS,
            part:
                TaskStatus(status: TextStatusType.CHUNK_DONE, taskId: _taskId));
        listenChunk(chunkDoneMessageChunk);
      }

      AgentMessage agentMessage = AgentMessage(
          sessionId: _sessionId,
          originalTaskId: originalTaskId,
          parentTaskId: _parentTaskId,
          taskId: _taskId,
          role: AgentRoleType.LLM,
          to: AgentRoleType.AGENT,
          type: AgentMessageType.TEXT,
          content: text,
          completions: completions);
      agentMessageStreamController.add(agentMessage);
    });
  }

  ReasoningAccumulation _buildReasoningAccumulation(
      void Function(AgentMessageChunk)? listenChunk,
      StreamController<AgentMessage> agentMessageStreamController,
      String originalTaskId) {
    return ReasoningAccumulation((reasoning, Completions? completions) {
      if (reasoning.isEmpty) return;
      if (listenChunk != null) {
        AgentMessageChunk chunkDoneMessageChunk = AgentMessageChunk(
            sessionId: _sessionId,
            originalTaskId: originalTaskId,
            parentTaskId: _parentTaskId,
            taskId: _taskId,
            role: AgentRoleType.LLM,
            to: AgentRoleType.AGENT,
            type: ReasoningMessageType.TASK_STATUS,
            part: TaskStatus(
                status: ReasoningStatusType.CHUNK_DONE, taskId: _taskId));
        listenChunk(chunkDoneMessageChunk);
      }

      AgentMessage agentMessage = AgentMessage(
          sessionId: _sessionId,
          originalTaskId: originalTaskId,
          parentTaskId: _parentTaskId,
          taskId: _taskId,
          role: AgentRoleType.LLM,
          to: AgentRoleType.AGENT,
          type: AgentMessageType.REASONING,
          content: reasoning,
          completions: completions);
      agentMessageStreamController.add(agentMessage);
    });
  }

  FunctionCallAccumulation _buildFunctionCallAccumulation(
    StreamController<AgentMessage> agentMessageStreamController,
    String originalTaskId, {
    String Function()? reasoningContent,
  }) {
    return FunctionCallAccumulation(
        (functionCallList, Completions? completions) {
      final reasoning = reasoningContent?.call();
      AgentMessage agentMessage = AgentMessage(
          sessionId: _sessionId,
          originalTaskId: originalTaskId,
          parentTaskId: _parentTaskId,
          taskId: _taskId,
          role: AgentRoleType.LLM,
          to: AgentRoleType.AGENT,
          type: AgentMessageType.TOOL_CALLS,
          reasoningContent:
              reasoning == null || reasoning.isEmpty ? null : reasoning,
          content: functionCallList,
          completions: completions);
      agentMessageStreamController.add(agentMessage);
    });
  }

  OpenAIToolModel _buildOpenAIToolModel(FunctionModel functionModel) {
    List<OpenAIFunctionProperty> openAIFunctionPropertyList = [];
    functionModel.parameters.forEach((Parameter parameter) {
      openAIFunctionPropertyList
          .add(_convertToOpenAIFunctionProperty(parameter));
    });
    OpenAIFunctionModel openAIFunctionModel =
        OpenAIFunctionModel.withParameters(
            name: functionModel.name,
            description: functionModel.description,
            parameters: openAIFunctionPropertyList);
    OpenAIToolModel openAIToolModel =
        OpenAIToolModel(type: "function", function: openAIFunctionModel);
    return openAIToolModel;
  }

  OpenAIFunctionProperty _convertToOpenAIFunctionProperty(Parameter parameter) {
    return _toOpenAIFunctionProperty(
        parameter.name,
        parameter.description ?? (parameter.schema.description ?? ""),
        parameter.schema,
        parameter.required);
  }

  OpenAIFunctionProperty _toOpenAIFunctionProperty(
      String name, String? description, Schema schema, bool required) {
    switch (schema.type.toLowerCase()) {
      case DataType.BOOLEAN:
        return OpenAIFunctionProperty.boolean(
          name: name,
          description: description ?? (schema.description),
          isRequired: required,
          enumValues: schema.enum_?.whereType<bool>().toList(),
        );
      case DataType.INTEGER:
        return OpenAIFunctionProperty.integer(
          name: name,
          description: description ?? (schema.description),
          isRequired: required,
          enumValues: schema.enum_?.whereType<int>().toList(),
        );
      case DataType.NUMBER:
        return OpenAIFunctionProperty.number(
          name: name,
          description: description ?? (schema.description),
          isRequired: required,
          enumValues: schema.enum_?.whereType<double>().toList(),
        );
      case DataType.STRING:
        return OpenAIFunctionProperty.string(
          name: name,
          description: description ?? (schema.description),
          isRequired: required,
          enumValues: schema.enum_?.whereType<String>().toList(),
        );
      case DataType.ARRAY:
        {
          final Schema itemsSchema =
              schema.items ?? Schema(type: DataType.STRING);
          OpenAIFunctionProperty openAIFunctionProperty =
              _toOpenAIFunctionProperty(name,
                  description ?? (schema.description), itemsSchema, required);
          return OpenAIFunctionProperty.array(
              name: name,
              description: schema.description,
              isRequired: required,
              items: openAIFunctionProperty);
        }
      case DataType.OBJECT:
        {
          Map<String, Schema> properties = schema.properties ?? {};
          List<String>? requiredList = schema.required;
          Map<String, OpenAIFunctionProperty> openAIFunctionProperties = {};
          properties.forEach((String name, Schema schema0) {
            bool required = false;
            if (requiredList != null && requiredList.contains(name)) {
              required = true;
            }
            OpenAIFunctionProperty openAIFunctionProperty =
                _toOpenAIFunctionProperty(
                    name, schema0.description ?? "", schema0, required);
            openAIFunctionProperties[name] = openAIFunctionProperty;
          });

          return OpenAIFunctionProperty.object(
              name: name,
              description: schema.description,
              isRequired: required,
              properties: openAIFunctionProperties.values);
        }
      default:
        {
          return OpenAIFunctionProperty(name: "", typeMap: {});
        }
    }
  }

  OpenAIChatCompletionChoiceMessageModel _buildOpenAIMessage(
      AgentMessage agentMessage) {
    /// System Prompt
    if (agentMessage.role == AgentRoleType.SYSTEM &&
        agentMessage.type == AgentMessageType.TEXT) {
      return OpenAIChatCompletionChoiceMessageModel(
          role: OpenAIChatMessageRole.system,
          content: [
            OpenAIChatCompletionChoiceMessageContentItemModel.text(
                agentMessage.content as String)
          ]);
    }

    /// LLM return text
    if (agentMessage.role == AgentRoleType.LLM &&
        agentMessage.type == AgentMessageType.TEXT) {
      return OpenAIChatCompletionChoiceMessageModel(
          role: OpenAIChatMessageRole.assistant,
          content: [
            OpenAIChatCompletionChoiceMessageContentItemModel.text(
                agentMessage.content as String)
          ]);
    }

    /// LLM return image
    if (agentMessage.role == AgentRoleType.LLM &&
        agentMessage.type == AgentMessageType.IMAGE_URL) {
      return OpenAIChatCompletionChoiceMessageModel(
          role: OpenAIChatMessageRole.assistant,
          content: [
            OpenAIChatCompletionChoiceMessageContentItemModel.imageUrl(
                agentMessage.content as String)
          ]);
    }

    /// LLM return function calling
    if (agentMessage.role == AgentRoleType.LLM &&
        agentMessage.type == AgentMessageType.TOOL_CALLS) {
      List<FunctionCall> functionCallList =
          agentMessage.content as List<FunctionCall>;
      List<OpenAIResponseToolCall> openAIResponseToolCallList =
          functionCallList.map((FunctionCall functionCall) {
        return _toOpenAIResponseToolCall(functionCall);
      }).toList();

      return OpenAIChatCompletionChoiceMessageModel(
          role: OpenAIChatMessageRole.assistant,
          content: null,
          toolCalls: openAIResponseToolCallList,
          reasoningContent: _resolveToolCallsReasoningContent(agentMessage));
    }

    /// AGENT return TOOL or SUBAGENT result
    if ((agentMessage.role == AgentRoleType.TOOL ||
            agentMessage.role == AgentRoleType.SUBAGENT) &&
        agentMessage.type == AgentMessageType.TOOL_RETURN) {
      ToolReturn toolReturn = agentMessage.content as ToolReturn;
      final streamEvents = toolReturn.result[_streamEventsKey];
      final source = streamEvents is List
          ? jsonEncode(streamEvents)
          : jsonEncode(toolReturn.result);
      final toolContent = _serializeToolReturnContent(source);
      return OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.tool,
        content: [
          OpenAIChatCompletionChoiceMessageContentItemModel.text(toolContent)
        ],
      ).asRequestFunctionMessage(toolCallId: toolReturn.id);
    }

    /// AGENT forward USER messages
    if (agentMessage.role == AgentRoleType.AGENT &&
        agentMessage.type == AgentMessageType.CONTENT_LIST) {
      List<LLMContent> contentList = agentMessage.content as List<LLMContent>;

      List<OpenAIChatCompletionChoiceMessageContentItemModel>
          openAIContentList = contentList.map((content) {
        if (content.type == LLMContentType.IMAGE_URL) {
          return OpenAIChatCompletionChoiceMessageContentItemModel.imageUrl(
              content.message);
        } else {
          return OpenAIChatCompletionChoiceMessageContentItemModel.text(
              content.message);
        }
      }).toList();

      return OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.user,
        content: openAIContentList,
      );
    }

    //Default, USER text message
    return OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.user,
        content: [
          OpenAIChatCompletionChoiceMessageContentItemModel.text(
              agentMessage.content as String)
        ]);
  }

  /// Resolve the value to send for `reasoning_content` on an outgoing
  /// assistant message that carries `tool_calls`.
  ///
  /// Compatibility shim for "thinking-mode" models that require
  /// `reasoning_content` to be replayed on assistant messages carrying
  /// `tool_calls`. Some providers (currently DeepSeek V4+, Xiaomi MiMo V2.5+)
  /// reject multi-turn requests with `400 The reasoning_content in the
  /// thinking mode must be passed back to the API.` whenever an assistant
  /// message containing `tool_calls` is missing the `reasoning_content` from
  /// the turn that produced those tool calls. Mirrors `agentos-api`'s
  /// `ModelClient._injectReasoningContentPlaceholder`, but here we have
  /// access to the original [AgentMessage.reasoningContent] (set by
  /// [_toFunctionCallList] on the non-streaming path), so we replay the real
  /// value when available and only fall back to an empty string if it is
  /// missing.
  ///
  /// Priority:
  /// 1. The agent message's own [AgentMessage.reasoningContent] (preserves
  ///    chain-of-thought context across turns).
  /// 2. Empty string `""` — only when the upstream model belongs to a family
  ///    that enforces the replay contract. Enough to pass the validator;
  ///    chain of thought is lost but multi-turn tool calling keeps working.
  /// 3. Otherwise null (the field is omitted from the request body).
  String? _resolveToolCallsReasoningContent(AgentMessage agentMessage) {
    final own = agentMessage.reasoningContent;
    if (own != null && own.isNotEmpty) return own;
    if (_requiresReasoningContentReplay(llmConfig.model)) return '';
    return null;
  }

  /// Model families that enforce the thinking-mode `reasoning_content`
  /// replay contract. Mirrors `agentos-api`'s
  /// `ModelClient._reasoningContentFamilies`. Add another entry here to
  /// extend coverage.
  static final List<_ReasoningContentFamily> _reasoningContentFamilies = [
    // DeepSeek V4 and above: deepseek-v4, deepseek-v4-pro, deepseek-v4-flash,
    // and any future v5 / v6 / v4.x release.
    _ReasoningContentFamily(
      pattern: RegExp(r'deepseek-v(\d+)(?:\.(\d+))?', caseSensitive: false),
      minVersion: const [4],
    ),
    // Xiaomi MiMo V2.5 and above: MiMo-V2.5, MiMo-V2.6, MiMo-V3, MiMo-V4, ...
    _ReasoningContentFamily(
      pattern: RegExp(r'mimo-v(\d+)(?:\.(\d+))?', caseSensitive: false),
      minVersion: const [2, 5],
    ),
  ];

  /// Whether [modelName] belongs to a family that requires
  /// `reasoning_content` to be replayed on assistant tool-call messages.
  static bool _requiresReasoningContentReplay(String modelName) {
    for (final family in _reasoningContentFamilies) {
      final match = family.pattern.firstMatch(modelName);
      if (match == null) continue;
      final major = int.tryParse(match.group(1) ?? '');
      if (major == null) continue;
      final minor = int.tryParse(match.group(2) ?? '0') ?? 0;
      if (_compareVersionParts([major, minor], family.minVersion) >= 0) {
        return true;
      }
    }
    return false;
  }

  /// Element-wise numeric comparison padding the shorter list with zeros
  /// (so `[3]` reads as `[3, 0]` and `[2, 5]` outranks `[2]`).
  static int _compareVersionParts(List<int> a, List<int> b) {
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  String _serializeToolReturnContent(String source) {
    final threshold = toolReturnPackMinLength;
    if (threshold == null || source.length < threshold) return source;
    return autoPack(source).output;
  }

  OpenAIResponseToolCall _toOpenAIResponseToolCall(FunctionCall functionCall) {
    return OpenAIResponseToolCall.fromMap({
      "id": functionCall.id,
      "type": "function",
      "function": {
        "name": functionCall.name,
        "arguments": jsonEncode(functionCall.arguments)
      }
    });
  }

  AgentMessage _toAgentMessage(
      OpenAIChatCompletionChoiceMessageModel
          openAIChatCompletionChoiceMessageModel,
      String originalTaskId,
      {Completions? completions}) {
    dynamic message;
    String? reasoningContent =
        openAIChatCompletionChoiceMessageModel.reasoningContent;

    if (openAIChatCompletionChoiceMessageModel.haveToolCalls &&
        openAIChatCompletionChoiceMessageModel.toolCalls!.isNotEmpty) {
      return _toFunctionCallList(
          openAIChatCompletionChoiceMessageModel.toolCalls!,
          reasoningContent,
          originalTaskId,
          completions);
    }

    message = openAIChatCompletionChoiceMessageModel.content?.first.text;
    return AgentMessage(
        sessionId: _sessionId,
        originalTaskId: originalTaskId,
        parentTaskId: _parentTaskId,
        taskId: _taskId,
        role: AgentRoleType.LLM,
        to: AgentRoleType.AGENT,
        type: AgentMessageType.TEXT,
        reasoningContent: reasoningContent,
        content: message,
        completions: completions);
  }

  AgentMessage _toFunctionCallList(
      List<OpenAIResponseToolCall> toolCalls,
      String? reasoningContent,
      String originalTaskId,
      Completions? completions) {
    List<FunctionCall> functionCallList =
        toolCalls.map((OpenAIResponseToolCall openAIResponseToolCall) {
      String id = openAIResponseToolCall.id!;
      String name = openAIResponseToolCall.function.name!;
      Map<String, dynamic> arguments =
          jsonDecode(openAIResponseToolCall.function.arguments);
      return FunctionCall(id: id, name: name, arguments: arguments);
    }).toList();
    return AgentMessage(
        sessionId: _sessionId,
        originalTaskId: originalTaskId,
        parentTaskId: _parentTaskId,
        taskId: _taskId,
        role: AgentRoleType.LLM,
        to: AgentRoleType.AGENT,
        type: AgentMessageType.TOOL_CALLS,
        reasoningContent: reasoningContent,
        content: functionCallList,
        completions: completions);
  }

  AgentMessageChunk? _chunkDeltaToAgentMessageChunk(
      ChatCompletionDelta chatCompletionDelta, String originalTaskId) {
    String text = chatCompletionDelta.delta?.content?.first?.text ?? "";
    if (text.isNotEmpty) {
      return AgentMessageChunk(
          sessionId: _sessionId,
          originalTaskId: originalTaskId,
          parentTaskId: _parentTaskId,
          taskId: _taskId,
          role: AgentRoleType.LLM,
          to: AgentRoleType.AGENT,
          type: AgentMessageType.TEXT,
          part: text);
    }
    return null;
  }

  AgentMessageChunk? _reasoningDeltaToAgentMessageChunk(
      ChatCompletionDelta chatCompletionDelta, String originalTaskId) {
    String reasoningContent = chatCompletionDelta.delta?.reasoningContent ?? "";
    if (reasoningContent.isNotEmpty) {
      return AgentMessageChunk(
          sessionId: _sessionId,
          originalTaskId: originalTaskId,
          parentTaskId: _parentTaskId,
          taskId: _taskId,
          role: AgentRoleType.LLM,
          to: AgentRoleType.AGENT,
          type: AgentMessageType.REASONING,
          part: reasoningContent);
    }
    return null;
  }
}

abstract class DeltaAccumulation<T> {
  void Function(T accumulation, Completions? completions) onComplete;
  late T accumulation;
  Completions? _completions;
  bool _finished = false;
  bool _closed = false;
  bool _hasCompleted = false;

  DeltaAccumulation(this.onComplete);

  void appendDelta(ChatCompletionDelta delta) {
    if (_completions == null) _completions = delta.completions;
    _checkComplete();
  }

  void close() {
    _closed = true;
    _checkComplete();
  }

  void _checkComplete() {
    if (_hasCompleted == false &&
        _finished == true &&
        (_completions != null || _closed == true)) {
      _hasCompleted = true;
      onComplete(accumulation, _completions);
    }
  }
}

class TextAccumulation extends DeltaAccumulation<String> {
  TextAccumulation(super.onComplete) {
    accumulation = "";
  }

  @override
  void appendDelta(ChatCompletionDelta delta) {
    if (delta.finishReason == null) {
      accumulation += delta.delta?.content?.first?.text ?? "";
    } else if (delta.finishReason == FinishReasonType.STOP) {
      super._finished = true;
    }
    super.appendDelta(delta);
  }
}

class ReasoningAccumulation extends DeltaAccumulation<String> {
  ReasoningAccumulation(super.onComplete) {
    accumulation = "";
  }

  @override
  void close() {
    if (accumulation.isNotEmpty) super._finished = true;
    super.close();
  }

  @override
  void appendDelta(ChatCompletionDelta delta) {
    if (delta.delta?.reasoningContent != null) {
      accumulation += delta.delta?.reasoningContent ?? "";
    } else if (delta.finishReason == FinishReasonType.STOP ||
        delta.finishReason == FinishReasonType.TOOL_CALLS ||
        delta.delta?.content?.first?.text != null ||
        delta.delta?.toolCalls != null) {
      super._finished = true;
    }
    super.appendDelta(delta);
  }
}

class FunctionCallAccumulation extends DeltaAccumulation<List<FunctionCall>> {
  String currentId = "";
  String currentName = "";
  String currentParameters = "";

  FunctionCallAccumulation(super.onComplete) {
    accumulation = [];
  }

  @override
  void appendDelta(ChatCompletionDelta delta) {
    if (delta.finishReason == null && delta.delta != null) {
      OpenAIResponseToolCall toolCall = delta.delta!.toolCalls!.first;
      // OpenAI-compatible streaming tool_call deltas carry `id` and
      // `function.name` only on the *first* chunk of each tool call.
      // On continuation chunks providers diverge:
      //   - OpenAI / gpt-4o leave these fields as `null`.
      //   - DashScope's deepseek-v4-flash sends empty strings `""`
      //     instead (verified against the upstream SSE stream).
      // Treat `""` as "not provided" (i.e. equivalent to `null`) so that:
      //   * a continuation chunk is never mistaken for the start of a
      //     new tool call — otherwise `"" != currentId` would flush the
      //     in-progress accumulation prematurely and *clobber* both
      //     `currentId` and `currentName` with empty strings, leading to
      //     a silently-dropped tool call at the final `_buildFunctionCall`
      //     (the root cause of the empty `[toolCalls] []` seen with
      //     deepseek-v4-flash);
      //   * for multi-tool responses, arguments for tool N+1 do not get
      //     concatenated onto the arguments buffer of tool N.
      final String? incomingId =
          (toolCall.id != null && toolCall.id!.isNotEmpty) ? toolCall.id : null;
      final String? incomingName =
          (toolCall.function.name != null && toolCall.function.name!.isNotEmpty)
              ? toolCall.function.name
              : null;

      if (incomingId != null && incomingId != currentId) {
        _buildFunctionCall();
        currentId = incomingId;
      }
      if (incomingName != null) currentName = incomingName;
      if (toolCall.function.arguments != null)
        currentParameters += toolCall.function.arguments!;
    } else if (delta.finishReason == FinishReasonType.TOOL_CALLS) {
      _buildFunctionCall();
      super._finished = true;
    }

    super.appendDelta(delta);
  }

  void _buildFunctionCall() {
    if (currentName.isNotEmpty && currentParameters.isNotEmpty) {
      accumulation.add(FunctionCall(
          id: currentId,
          name: currentName,
          arguments: jsonDecode(currentParameters)));
      currentId = "";
      currentName = "";
      currentParameters = "";
    }
  }
}

/// Descriptor for a model family that requires `reasoning_content` to be
/// present on assistant messages with `tool_calls`.
///
/// [pattern] must capture the model's numeric version as groups 1 (major)
/// and optionally 2 (minor). [minVersion] is `[major, minor]` (or `[major]`
/// when only the major matters) and is compared numerically; the shim is
/// applied when the parsed version is `>= minVersion`.
class _ReasoningContentFamily {
  const _ReasoningContentFamily({
    required this.pattern,
    required this.minVersion,
  });

  final RegExp pattern;
  final List<int> minVersion;
}
