import 'package:json_annotation/json_annotation.dart';
import 'package:liteagent_core_dart/liteagent_core.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'exception.dart';

part 'dto.g.dart';

Object? _readOriginalTaskId(Map<dynamic, dynamic> json, String key) =>
    json[key] ?? json['taskId'];

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class SessionDto {
  String sessionId;

  SessionDto({required this.sessionId});

  factory SessionDto.fromJson(Map<String, dynamic> json) =>
      _$SessionDtoFromJson(json);

  Map<String, dynamic> toJson() => _$SessionDtoToJson(this);
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class SessionNameDto extends SessionDto {
  String?
      name; // OpenAI: The name of the function to be called. Must be a-z, A-Z, 0-9, or contain underscores and dashes, with a maximum length of 64.
  String? description;

  SessionNameDto({required super.sessionId, String? name, this.description}) {
    final regex = RegExp(r'^[a-zA-Z0-9_-]{1,64}$');
    if (name != null && !regex.hasMatch(name)) {
      throw AgentNameException(agentName: name);
    }
    this.name = name;
  }

  factory SessionNameDto.fromJson(Map<String, dynamic> json) =>
      _$SessionNameDtoFromJson(json);

  Map<String, dynamic> toJson() => _$SessionNameDtoToJson(this);
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class SimpleCapabilityDto {
  LLMConfigDto? llmConfig;
  String systemPrompt;

  /// Complete SKILL.md documents following Agent Skills specification:
  /// https://agentskills.io/specification
  List<String>? skills;

  SimpleCapabilityDto({
    this.llmConfig,
    required this.systemPrompt,
    this.skills,
  });

  factory SimpleCapabilityDto.fromJson(Map<String, dynamic> json) =>
      _$SimpleCapabilityDtoFromJson(json);

  Map<String, dynamic> toJson() => _$SimpleCapabilityDtoToJson(this);
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class CapabilityDto extends SimpleCapabilityDto {
  List<OpenSpecDto>? openSpecList;
  CallbackOpenToolDto? callbackOpenTool;
  List<SessionNameDto>? sessionList;
  List<ReflectPromptDto>? reflectPromptList;
  int timeoutSeconds;
  String taskPipelineStrategy;
  String? toolPipelineStrategy;
  bool? auto;
  List<LLMConfigDto>? llmConfigList;
  bool? enableThinking;
  int? toolReturnPackMinLength;

  CapabilityDto({
    super.llmConfig,
    required super.systemPrompt,
    super.skills,
    this.openSpecList,
    this.callbackOpenTool,
    this.sessionList,
    this.reflectPromptList,
    this.timeoutSeconds = 3600,
    this.taskPipelineStrategy = PipelineStrategyType.PARALLEL,
    this.toolPipelineStrategy,
    this.auto,
    this.llmConfigList,
    this.enableThinking,
    this.toolReturnPackMinLength,
  });

  factory CapabilityDto.fromJson(Map<String, dynamic> json) =>
      _$CapabilityDtoFromJson(json);

  Map<String, dynamic> toJson() => _$CapabilityDtoToJson(this);
}

class Protocol {
  static const String OPENAPI = "openapi";
  static const String JSONRPCHTTP = "jsonrpcHttp";
  static const String OPENTOOL = "opentool";
  static const String MCP_STDIO = "mcpStdio";
  static const String MCP_HTTP = "mcpHttp";
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class OpenSpecDto {
  String openSpec;
  String protocol;
  String? serverUrl;
  ApiKeyDto? apiKey;
  // String? openToolId; //When protocol is open tool, this is the tool id

  OpenSpecDto(
      {required this.openSpec,
      required this.protocol,
      this.apiKey,
      this.serverUrl});

  factory OpenSpecDto.fromJson(Map<String, dynamic> json) =>
      _$OpenSpecDtoFromJson(json);

  Map<String, dynamic> toJson() => _$OpenSpecDtoToJson(this);
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class LLMConfigDto {
  String? provider;
  String baseUrl;
  String? apiKey;
  String model;
  String? adapter;
  Map<String, String>? headers;
  Map<String, dynamic>? providerOptions;
  double temperature;
  int maxTokens;
  int? contextWindowSize;
  double topP;
  bool supportsToolCall;
  bool supportsReasoning;

  LLMConfigDto(
      {this.provider,
      this.baseUrl = "",
      this.apiKey,
      required this.model,
      this.adapter,
      this.headers,
      this.providerOptions,
      this.temperature = 0.0,
      this.maxTokens = 4096,
      this.contextWindowSize,
      this.topP = 1.0,
      this.supportsToolCall = true,
      this.supportsReasoning = false});

  factory LLMConfigDto.fromJson(Map<String, dynamic> json) =>
      _$LLMConfigDtoFromJson(json);

  Map<String, dynamic> toJson() => _$LLMConfigDtoToJson(this);

  factory LLMConfigDto.fromModel(LLMConfig llmConfig) => LLMConfigDto(
      provider: llmConfig.provider,
      baseUrl: llmConfig.baseUrl,
      apiKey: llmConfig.apiKey,
      model: llmConfig.model,
      adapter: llmConfig.adapter,
      headers: llmConfig.headers,
      providerOptions: llmConfig.providerOptions,
      temperature: llmConfig.temperature,
      maxTokens: llmConfig.maxTokens,
      contextWindowSize: llmConfig.contextWindowSize,
      topP: llmConfig.topP,
      supportsToolCall: llmConfig.supportsToolCall,
      supportsReasoning: llmConfig.supportsReasoning);

  LLMConfig toModel() => LLMConfig(
      provider: provider ?? "openai",
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      adapter: adapter,
      headers: headers,
      providerOptions: providerOptions,
      temperature: temperature,
      maxTokens: maxTokens,
      contextWindowSize: contextWindowSize,
      topP: topP,
      supportsToolCall: supportsToolCall,
      supportsReasoning: supportsReasoning);
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class AgentMessageDto {
  String sessionId;
  String? agentId;
  @JsonKey(readValue: _readOriginalTaskId)
  String originalTaskId;
  String? parentTaskId;
  String taskId;
  String role;
  String to;
  String type;
  dynamic content;
  String? reasoningContent;

  @JsonKey(includeIfNull: false)
  CompletionsDto?
      completions; //When role is llm, this is current llm calling token usage

  DateTime createTime;

  AgentMessageDto({
    required this.sessionId,
    this.agentId,
    String? originalTaskId,
    this.parentTaskId,
    required this.taskId,
    required this.role,
    required this.to,
    required this.type,
    required this.content,
    this.reasoningContent,
    this.completions,
    required this.createTime,
  }) : originalTaskId = originalTaskId ?? taskId;

  factory AgentMessageDto.fromJson(Map<String, dynamic> json) =>
      _$AgentMessageDtoFromJson(json);

  Map<String, dynamic> toJson() => _$AgentMessageDtoToJson(this);

  factory AgentMessageDto.fromModel(AgentMessage agentMessage) {
    dynamic message;

    switch (agentMessage.type) {
      case AgentMessageType.CONTENT_LIST:
        message = (agentMessage.content as List<Content>)
            .map((content) => ContentDto.fromModel(content))
            .toList();
        break;
      case AgentMessageType.FUNCTION_CALL:
        message = agentMessage.content as FunctionCall;
        break;
      case AgentMessageType.TOOL_CALLS:
        message = (agentMessage.content as List<FunctionCall>);
        break;
      case AgentMessageType.TOOL_RETURN:
        message = agentMessage.content as ToolReturn;
        break;
      case AgentMessageType.REFLECTION:
        message = ReflectionDto.fromModel(agentMessage.content as Reflection);
        break;
      case AgentMessageType.TASK_STATUS:
        message = TaskStatusDto.fromModel(agentMessage.content as TaskStatus);
        break;
      default:
        message = agentMessage.content;
    }

    return AgentMessageDto(
      sessionId: agentMessage.sessionId,
      agentId: agentMessage.agentId,
      originalTaskId: agentMessage.originalTaskId,
      parentTaskId: agentMessage.parentTaskId,
      taskId: agentMessage.taskId,
      role: agentMessage.role,
      to: agentMessage.to,
      type: agentMessage.type,
      content: message,
      reasoningContent: agentMessage.reasoningContent,
      completions: agentMessage.completions == null
          ? null
          : CompletionsDto.fromModel(agentMessage.completions!),
      createTime: agentMessage.createTime,
    );
  }

  AgentMessage toModel() {
    final AgentMessage message = AgentMessage(
      sessionId: sessionId,
      agentId: agentId,
      originalTaskId: originalTaskId,
      parentTaskId: parentTaskId,
      taskId: taskId,
      role: role,
      to: to,
      type: type,
      content: _contentToModel(),
      reasoningContent: reasoningContent,
      completions: completions?.toModel(),
    );
    message.createTime = createTime;
    return message;
  }

  dynamic _contentToModel() {
    switch (type) {
      case AgentMessageType.CONTENT_LIST:
        return (content as List<dynamic>)
            .map((item) => item is ContentDto
                ? item.toModel()
                : ContentDto.fromJson(
                    Map<String, dynamic>.from(item as Map),
                  ).toModel())
            .toList();
      case AgentMessageType.FUNCTION_CALL:
        if (content is FunctionCall) return content;
        return FunctionCall.fromJson(
          Map<String, dynamic>.from(content as Map),
        );
      case AgentMessageType.TOOL_CALLS:
        return (content as List<dynamic>)
            .map((item) => item is FunctionCall
                ? item
                : FunctionCall.fromJson(
                    Map<String, dynamic>.from(item as Map),
                  ))
            .toList();
      case AgentMessageType.TOOL_RETURN:
        if (content is ToolReturn) return content;
        return ToolReturn.fromJson(
          Map<String, dynamic>.from(content as Map),
        );
      case AgentMessageType.REFLECTION:
        if (content is Reflection) return content;
        return (content is ReflectionDto
                ? content as ReflectionDto
                : ReflectionDto.fromJson(
                    Map<String, dynamic>.from(content as Map),
                  ))
            .toModel();
      case AgentMessageType.TASK_STATUS:
        if (content is TaskStatus) return content;
        return (content is TaskStatusDto
                ? content as TaskStatusDto
                : TaskStatusDto.fromJson(
                    Map<String, dynamic>.from(content as Map),
                  ))
            .toModel();
      default:
        return content;
    }
  }
}

// @JsonSerializable(includeIfNull: false, explicitToJson: true)
// class FunctionCallDto {
//   late String id;
//   late String name;
//   late Map<String, dynamic> parameters;
//
//   FunctionCallDto({required this.id, required this.name, required this.parameters});
//
//   // factory FunctionCallDto.fromModel(FunctionCall functionCall) => FunctionCallDto(
//   //   id: functionCall.id,
//   //   name: functionCall.name,
//   //   parameters: functionCall.parameters
//   // );
//
//   factory FunctionCallDto.fromJson(Map<String, dynamic> json) => _$FunctionCallDtoFromJson(json);
//
//   Map<String, dynamic> toJson() => _$FunctionCallDtoToJson(this);
// }

// @JsonSerializable(includeIfNull: false, explicitToJson: true)
// class ToolReturnDto {
//   late String id;
//   late Map<String, dynamic> result;
//
//   ToolReturnDto({required this.id, required this.result});
//
//   factory ToolReturnDto.fromModel(ToolReturn toolReturn) => ToolReturnDto(
//       id: toolReturn.id,
//       result: toolReturn.result
//   );
//
//   ToolReturn toModel() => ToolReturn(id: id, result: result);
//
//   factory ToolReturnDto.fromJson(Map<String, dynamic> json) => _$ToolReturnDtoFromJson(json);
//
//   Map<String, dynamic> toJson() => _$ToolReturnDtoToJson(this);
// }

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class CompletionsDto {
  TokenUsageDto usage;

  /// When role is llm, this is current llm calling token usage
  String id;

  /// When role is llm, this is current /chat/completions return message id
  String model;

  @JsonKey(includeIfNull: false)
  CompletionsLimitsDto? limits;

  CompletionsDto({
    required this.usage,
    required this.id,
    required this.model,
    this.limits,
  });

  factory CompletionsDto.fromJson(Map<String, dynamic> json) =>
      _$CompletionsDtoFromJson(json);

  Map<String, dynamic> toJson() => _$CompletionsDtoToJson(this);

  factory CompletionsDto.fromModel(Completions completions) => CompletionsDto(
      usage: TokenUsageDto.fromModel(completions.tokenUsage),
      id: completions.id,
      model: completions.model,
      limits: completions.limits == null
          ? null
          : CompletionsLimitsDto.fromModel(completions.limits!));

  Completions toModel() => Completions(
        tokenUsage: usage.toModel(),
        id: id,
        model: model,
        limits: limits?.toModel(),
      );
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class CompletionsLimitsDto {
  final int maxTokens;
  final int? contextWindowSize;

  CompletionsLimitsDto({required this.maxTokens, this.contextWindowSize});

  factory CompletionsLimitsDto.fromJson(Map<String, dynamic> json) =>
      _$CompletionsLimitsDtoFromJson(json);

  Map<String, dynamic> toJson() => _$CompletionsLimitsDtoToJson(this);

  factory CompletionsLimitsDto.fromModel(CompletionsLimits limits) =>
      CompletionsLimitsDto(
        maxTokens: limits.maxTokens,
        contextWindowSize: limits.contextWindowSize,
      );

  CompletionsLimits toModel() => CompletionsLimits(
        maxTokens: maxTokens,
        contextWindowSize: contextWindowSize,
      );
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class TokenUsageDto {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final double? contextUsageRatio;

  TokenUsageDto(
      {required this.promptTokens,
      required this.completionTokens,
      required this.totalTokens,
      this.contextUsageRatio});

  factory TokenUsageDto.fromJson(Map<String, dynamic> json) =>
      _$TokenUsageDtoFromJson(json);

  Map<String, dynamic> toJson() => _$TokenUsageDtoToJson(this);

  factory TokenUsageDto.fromModel(TokenUsage tokenUsage) => TokenUsageDto(
      promptTokens: tokenUsage.promptTokens,
      completionTokens: tokenUsage.completionTokens,
      totalTokens: tokenUsage.totalTokens,
      contextUsageRatio: tokenUsage.contextUsageRatio);

  TokenUsage toModel() => TokenUsage(
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        totalTokens: totalTokens,
        contextUsageRatio: contextUsageRatio,
      );
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class ApiKeyDto {
  ApiKeyType type;
  String apiKey;

  ApiKeyDto({required this.type, required this.apiKey});

  factory ApiKeyDto.fromJson(Map<String, dynamic> json) =>
      _$ApiKeyDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ApiKeyDtoToJson(this);
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class UserTaskDto {
  @JsonKey(includeIfNull: false)
  List<ContentDto> content;
  bool? isChunk;
  String? extraSystemPrompt;
  LLMConfigDto? llmConfig;

  UserTaskDto(
      {required this.content,
      this.isChunk,
      this.extraSystemPrompt,
      this.llmConfig});

  factory UserTaskDto.fromJson(Map<String, dynamic> json) =>
      _$UserTaskDtoFromJson(json);

  Map<String, dynamic> toJson() => _$UserTaskDtoToJson(this);
}

// enum UserMessageDtoType { text, imageUrl }

// @JsonSerializable(includeIfNull: false, explicitToJson: true)
// class UserMessageDto {
//   UserMessageDtoType type;
//   String message;
//
//   UserMessageDto({required this.type, required this.message});
//
//   factory UserMessageDto.fromJson(Map<String, dynamic> json) => _$UserMessageDtoFromJson(json);
//
//   Map<String, dynamic> toJson() => _$UserMessageDtoToJson(this);
// }

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class SessionTaskDto {
  String sessionId;

  @JsonKey(includeIfNull: false)
  String? taskId;

  SessionTaskDto({required this.sessionId, this.taskId});

  factory SessionTaskDto.fromJson(Map<String, dynamic> json) =>
      _$SessionTaskDtoFromJson(json);

  Map<String, dynamic> toJson() => _$SessionTaskDtoToJson(this);
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class ReflectScoreDto {
  int score;

  @JsonKey(includeIfNull: false)
  String? description;
  ReflectScoreDto({required this.score, this.description});

  factory ReflectScoreDto.fromModel(ReflectScore reflectScore) =>
      ReflectScoreDto(
          score: reflectScore.score, description: reflectScore.description);

  factory ReflectScoreDto.fromJson(Map<String, dynamic> json) =>
      _$ReflectScoreDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ReflectScoreDtoToJson(this);

  ReflectScore toModel() => ReflectScore(
        score: score,
        description: description,
      );
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class MessageScoreDto {
  List<ContentDto> contentList;
  String messageType; //Follow AgentMessage.type
  String message;
  List<ReflectScoreDto> reflectScoreList;
  MessageScoreDto(
      {required this.contentList,
      required this.messageType,
      required this.message,
      required this.reflectScoreList});

  factory MessageScoreDto.fromModel(MessageScore messageScore) =>
      MessageScoreDto(
          contentList: messageScore.contentList
              .map((content) =>
                  ContentDto(type: content.type, message: content.message))
              .toList(),
          messageType: messageScore.messageType,
          message: messageScore.message,
          reflectScoreList: messageScore.reflectScoreList
              .map((reflectScore) => ReflectScoreDto(
                  score: reflectScore.score,
                  description: reflectScore.description))
              .toList());

  factory MessageScoreDto.fromJson(Map<String, dynamic> json) =>
      _$MessageScoreDtoFromJson(json);

  Map<String, dynamic> toJson() => _$MessageScoreDtoToJson(this);

  MessageScore toModel() => MessageScore(
        contentList: contentList.map((content) => content.toModel()).toList(),
        messageType: messageType,
        message: message,
        reflectScoreList:
            reflectScoreList.map((score) => score.toModel()).toList(),
      );
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class ReflectionDto {
  final bool isPass;
  final MessageScoreDto messageScore;
  final int passScore;
  final int count;
  final int maxCount;

  ReflectionDto({
    required this.isPass,
    required this.messageScore,
    required this.passScore,
    required this.count,
    required this.maxCount,
  });

  factory ReflectionDto.fromModel(Reflection result) => ReflectionDto(
      isPass: result.isPass,
      messageScore: MessageScoreDto.fromModel(result.messageScore),
      passScore: result.passScore,
      count: result.count,
      maxCount: result.maxCount);

  factory ReflectionDto.fromJson(Map<String, dynamic> json) =>
      _$ReflectionDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ReflectionDtoToJson(this);

  Reflection toModel() => Reflection(
        isPass: isPass,
        messageScore: messageScore.toModel(),
        passScore: passScore,
        count: count,
        maxCount: maxCount,
      );
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class TaskStatusDto {
  String status;
  String taskId;

  @JsonKey(includeIfNull: false)
  Map<String, dynamic>? description;

  TaskStatusDto({required this.status, required this.taskId, this.description});

  factory TaskStatusDto.fromModel(TaskStatus taskStatus) => TaskStatusDto(
      status: taskStatus.status,
      taskId: taskStatus.taskId,
      description: taskStatus.description);

  factory TaskStatusDto.fromJson(Map<String, dynamic> json) =>
      _$TaskStatusDtoFromJson(json);

  Map<String, dynamic> toJson() => _$TaskStatusDtoToJson(this);

  TaskStatus toModel() => TaskStatus(
        status: status,
        taskId: taskId,
        description: description,
      );
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class ContentDto {
  String type;

  /// ContentType.TEXT ContentType.IMAGE_URL
  String message;

  ContentDto({required this.type, required this.message});

  factory ContentDto.fromModel(Content content) =>
      ContentDto(type: content.type, message: content.message);

  factory ContentDto.fromJson(Map<String, dynamic> json) =>
      _$ContentDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ContentDtoToJson(this);

  Content toModel() => Content(type: type, message: message);
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class ReflectPromptDto {
  LLMConfigDto llmConfig;
  String prompt;

  ReflectPromptDto({required this.llmConfig, required this.prompt});

  factory ReflectPromptDto.fromJson(Map<String, dynamic> json) =>
      _$ReflectPromptDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ReflectPromptDtoToJson(this);
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class AgentMessageChunkDto {
  String sessionId;
  String? agentId;
  String? parentTaskId;
  String taskId;
  String role;
  String to;
  String type;
  dynamic part;
  DateTime createTime;

  AgentMessageChunkDto(
      {required this.sessionId,
      this.agentId,
      this.parentTaskId,
      required this.taskId,
      required this.role,
      required this.to,
      required this.type,
      required this.part,
      required this.createTime});

  factory AgentMessageChunkDto.fromJson(Map<String, dynamic> json) =>
      _$AgentMessageChunkDtoFromJson(json);

  Map<String, dynamic> toJson() => _$AgentMessageChunkDtoToJson(this);

  factory AgentMessageChunkDto.fromModel(AgentMessageChunk agentMessageChunk) {
    dynamic part;

    switch (agentMessageChunk.type) {
      case AgentMessageType.TASK_STATUS:
        part = TaskStatusDto.fromModel(agentMessageChunk.part as TaskStatus);
        break;
      default:
        part = agentMessageChunk.part;
    }

    return AgentMessageChunkDto(
        sessionId: agentMessageChunk.sessionId,
        agentId: agentMessageChunk.agentId,
        parentTaskId: agentMessageChunk.parentTaskId,
        taskId: agentMessageChunk.taskId,
        role: agentMessageChunk.role,
        to: agentMessageChunk.to,
        type: agentMessageChunk.type,
        part: part,
        createTime: agentMessageChunk.createTime);
  }
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class AgentIdDto {
  String agentId;
  AgentIdDto({required this.agentId});

  factory AgentIdDto.fromJson(Map<String, dynamic> json) =>
      _$AgentIdDtoFromJson(json);

  Map<String, dynamic> toJson() => _$AgentIdDtoToJson(this);
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class AgentDto {
  String name;
  CapabilityDto capability;
  AgentDto({required this.name, required this.capability});

  factory AgentDto.fromJson(Map<String, dynamic> json) =>
      _$AgentDtoFromJson(json);

  Map<String, dynamic> toJson() => _$AgentDtoToJson(this);
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class AgentInfoDto extends AgentIdDto {
  String name;
  CapabilityDto capability;
  DateTime? createTime;
  DateTime? updateTime;
  AgentInfoDto({
    required super.agentId,
    required this.name,
    required this.capability,
    this.createTime,
    this.updateTime,
  });

  factory AgentInfoDto.fromJson(Map<String, dynamic> json) =>
      _$AgentInfoDtoFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$AgentInfoDtoToJson(this);
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class SessionAgentMessageDto {
  String sessionId;
  // String taskId;
  AgentMessageDto agentMessageDto;
  SessionAgentMessageDto(
      {required this.sessionId, required this.agentMessageDto});

  factory SessionAgentMessageDto.fromJson(Map<String, dynamic> json) =>
      _$SessionAgentMessageDtoFromJson(json);

  Map<String, dynamic> toJson() => _$SessionAgentMessageDtoToJson(this);
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class CallbackOpenToolDto {
  String opentool;
  int? timeout;

  CallbackOpenToolDto({required this.opentool, this.timeout});

  factory CallbackOpenToolDto.fromJson(Map<String, dynamic> json) =>
      _$CallbackOpenToolDtoFromJson(json);

  Map<String, dynamic> toJson() => _$CallbackOpenToolDtoToJson(this);
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class PresetOpenSpecDto {
  String systemPrompt;
  OpenSpecDto? openSpec;

  PresetOpenSpecDto({required this.systemPrompt, this.openSpec});

  factory PresetOpenSpecDto.fromJson(Map<String, dynamic> json) =>
      _$PresetOpenSpecDtoFromJson(json);

  Map<String, dynamic> toJson() => _$PresetOpenSpecDtoToJson(this);
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class SessionInfoDto {
  String sessionId;
  String? agentId;
  DateTime createTime;
  String? topic;

  SessionInfoDto({
    required this.sessionId,
    this.agentId,
    required this.createTime,
    this.topic,
  });

  factory SessionInfoDto.fromJson(Map<String, dynamic> json) =>
      _$SessionInfoDtoFromJson(json);

  Map<String, dynamic> toJson() => _$SessionInfoDtoToJson(this);
}
