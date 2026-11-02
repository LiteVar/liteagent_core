// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SessionDto _$SessionDtoFromJson(Map<String, dynamic> json) =>
    SessionDto(sessionId: json['sessionId'] as String);

Map<String, dynamic> _$SessionDtoToJson(SessionDto instance) =>
    <String, dynamic>{'sessionId': instance.sessionId};

SimpleCapabilityDto _$SimpleCapabilityDtoFromJson(Map<String, dynamic> json) =>
    SimpleCapabilityDto(
      llmConfig: json['llmConfig'] == null
          ? null
          : LLMConfigDto.fromJson(json['llmConfig'] as Map<String, dynamic>),
      systemPrompt: json['systemPrompt'] as String,
      skills: (json['skills'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$SimpleCapabilityDtoToJson(
  SimpleCapabilityDto instance,
) => <String, dynamic>{
  'llmConfig': ?instance.llmConfig?.toJson(),
  'systemPrompt': instance.systemPrompt,
  'skills': ?instance.skills,
};

CapabilityDto _$CapabilityDtoFromJson(
  Map<String, dynamic> json,
) => CapabilityDto(
  llmConfig: json['llmConfig'] == null
      ? null
      : LLMConfigDto.fromJson(json['llmConfig'] as Map<String, dynamic>),
  systemPrompt: json['systemPrompt'] as String,
  skills: (json['skills'] as List<dynamic>?)?.map((e) => e as String).toList(),
  openSpecList: (json['openSpecList'] as List<dynamic>?)
      ?.map((e) => OpenSpecDto.fromJson(e as Map<String, dynamic>))
      .toList(),
  callbackOpenTool: json['callbackOpenTool'] == null
      ? null
      : CallbackOpenToolDto.fromJson(
          json['callbackOpenTool'] as Map<String, dynamic>,
        ),
  subAgentList: (json['subAgentList'] as List<dynamic>?)
      ?.map((e) => AgentDto.fromJson(e as Map<String, dynamic>))
      .toList(),
  timeoutSeconds: (json['timeoutSeconds'] as num?)?.toInt() ?? 3600,
  taskPipelineStrategy:
      json['taskPipelineStrategy'] as String? ?? PipelineStrategyType.PARALLEL,
  toolPipelineStrategy: json['toolPipelineStrategy'] as String?,
  auto: json['auto'] as bool?,
  llmConfigList: (json['llmConfigList'] as List<dynamic>?)
      ?.map((e) => LLMConfigDto.fromJson(e as Map<String, dynamic>))
      .toList(),
  enableThinking: json['enableThinking'] as bool?,
  toolReturnPackMinLength: (json['toolReturnPackMinLength'] as num?)?.toInt(),
  maxLlmRequests: (json['maxLlmRequests'] as num?)?.toInt(),
  maxToolRounds: (json['maxToolRounds'] as num?)?.toInt(),
  maxToolCalls: (json['maxToolCalls'] as num?)?.toInt(),
  maxConsecutiveIdenticalToolRounds:
      (json['maxConsecutiveIdenticalToolRounds'] as num?)?.toInt(),
  maxTaskDurationSeconds: (json['maxTaskDurationSeconds'] as num?)?.toInt(),
);

Map<String, dynamic> _$CapabilityDtoToJson(CapabilityDto instance) =>
    <String, dynamic>{
      'llmConfig': ?instance.llmConfig?.toJson(),
      'systemPrompt': instance.systemPrompt,
      'skills': ?instance.skills,
      'openSpecList': ?instance.openSpecList?.map((e) => e.toJson()).toList(),
      'callbackOpenTool': ?instance.callbackOpenTool?.toJson(),
      'subAgentList': ?instance.subAgentList?.map((e) => e.toJson()).toList(),
      'timeoutSeconds': instance.timeoutSeconds,
      'taskPipelineStrategy': instance.taskPipelineStrategy,
      'toolPipelineStrategy': ?instance.toolPipelineStrategy,
      'auto': ?instance.auto,
      'llmConfigList': ?instance.llmConfigList?.map((e) => e.toJson()).toList(),
      'enableThinking': ?instance.enableThinking,
      'toolReturnPackMinLength': ?instance.toolReturnPackMinLength,
      'maxLlmRequests': ?instance.maxLlmRequests,
      'maxToolRounds': ?instance.maxToolRounds,
      'maxToolCalls': ?instance.maxToolCalls,
      'maxConsecutiveIdenticalToolRounds':
          ?instance.maxConsecutiveIdenticalToolRounds,
      'maxTaskDurationSeconds': ?instance.maxTaskDurationSeconds,
    };

OpenSpecDto _$OpenSpecDtoFromJson(Map<String, dynamic> json) => OpenSpecDto(
  openSpec: json['openSpec'] as String,
  protocol: json['protocol'] as String,
  apiKey: json['apiKey'] == null
      ? null
      : ApiKeyDto.fromJson(json['apiKey'] as Map<String, dynamic>),
  serverUrl: json['serverUrl'] as String?,
);

Map<String, dynamic> _$OpenSpecDtoToJson(OpenSpecDto instance) =>
    <String, dynamic>{
      'openSpec': instance.openSpec,
      'protocol': instance.protocol,
      'serverUrl': ?instance.serverUrl,
      'apiKey': ?instance.apiKey?.toJson(),
    };

LLMConfigDto _$LLMConfigDtoFromJson(Map<String, dynamic> json) => LLMConfigDto(
  provider: json['provider'] as String?,
  baseUrl: json['baseUrl'] as String? ?? "",
  apiKey: json['apiKey'] as String?,
  model: json['model'] as String,
  adapter: json['adapter'] as String?,
  headers: (json['headers'] as Map<String, dynamic>?)?.map(
    (k, e) => MapEntry(k, e as String),
  ),
  providerOptions: json['providerOptions'] as Map<String, dynamic>?,
  temperature: (json['temperature'] as num?)?.toDouble() ?? 0.0,
  maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 4096,
  contextWindowSize: (json['contextWindowSize'] as num?)?.toInt(),
  topP: (json['topP'] as num?)?.toDouble() ?? 1.0,
  supportsToolCall: json['supportsToolCall'] as bool? ?? true,
  supportsReasoning: json['supportsReasoning'] as bool? ?? false,
);

Map<String, dynamic> _$LLMConfigDtoToJson(LLMConfigDto instance) =>
    <String, dynamic>{
      'provider': ?instance.provider,
      'baseUrl': instance.baseUrl,
      'apiKey': ?instance.apiKey,
      'model': instance.model,
      'adapter': ?instance.adapter,
      'headers': ?instance.headers,
      'providerOptions': ?instance.providerOptions,
      'temperature': instance.temperature,
      'maxTokens': instance.maxTokens,
      'contextWindowSize': ?instance.contextWindowSize,
      'topP': instance.topP,
      'supportsToolCall': instance.supportsToolCall,
      'supportsReasoning': instance.supportsReasoning,
    };

AgentMessageDto _$AgentMessageDtoFromJson(Map<String, dynamic> json) =>
    AgentMessageDto(
      sessionId: json['sessionId'] as String,
      agentId: json['agentId'] as String?,
      originalTaskId: _readOriginalTaskId(json, 'originalTaskId') as String?,
      parentTaskId: json['parentTaskId'] as String?,
      taskId: json['taskId'] as String,
      role: json['role'] as String,
      to: json['to'] as String,
      type: json['type'] as String,
      content: json['content'],
      reasoningContent: json['reasoningContent'] as String?,
      completions: json['completions'] == null
          ? null
          : CompletionsDto.fromJson(
              json['completions'] as Map<String, dynamic>,
            ),
      createTime: DateTime.parse(json['createTime'] as String),
    );

Map<String, dynamic> _$AgentMessageDtoToJson(AgentMessageDto instance) =>
    <String, dynamic>{
      'sessionId': instance.sessionId,
      'agentId': ?instance.agentId,
      'originalTaskId': instance.originalTaskId,
      'parentTaskId': ?instance.parentTaskId,
      'taskId': instance.taskId,
      'role': instance.role,
      'to': instance.to,
      'type': instance.type,
      'content': ?instance.content,
      'reasoningContent': ?instance.reasoningContent,
      'completions': ?instance.completions?.toJson(),
      'createTime': instance.createTime.toIso8601String(),
    };

CompletionsDto _$CompletionsDtoFromJson(Map<String, dynamic> json) =>
    CompletionsDto(
      usage: TokenUsageDto.fromJson(json['usage'] as Map<String, dynamic>),
      id: json['id'] as String,
      model: json['model'] as String,
      limits: json['limits'] == null
          ? null
          : CompletionsLimitsDto.fromJson(
              json['limits'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$CompletionsDtoToJson(CompletionsDto instance) =>
    <String, dynamic>{
      'usage': instance.usage.toJson(),
      'id': instance.id,
      'model': instance.model,
      'limits': ?instance.limits?.toJson(),
    };

CompletionsLimitsDto _$CompletionsLimitsDtoFromJson(
  Map<String, dynamic> json,
) => CompletionsLimitsDto(
  maxTokens: (json['maxTokens'] as num).toInt(),
  contextWindowSize: (json['contextWindowSize'] as num?)?.toInt(),
);

Map<String, dynamic> _$CompletionsLimitsDtoToJson(
  CompletionsLimitsDto instance,
) => <String, dynamic>{
  'maxTokens': instance.maxTokens,
  'contextWindowSize': ?instance.contextWindowSize,
};

TokenUsageDto _$TokenUsageDtoFromJson(Map<String, dynamic> json) =>
    TokenUsageDto(
      promptTokens: (json['promptTokens'] as num).toInt(),
      completionTokens: (json['completionTokens'] as num).toInt(),
      totalTokens: (json['totalTokens'] as num).toInt(),
      contextUsageRatio: (json['contextUsageRatio'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$TokenUsageDtoToJson(TokenUsageDto instance) =>
    <String, dynamic>{
      'promptTokens': instance.promptTokens,
      'completionTokens': instance.completionTokens,
      'totalTokens': instance.totalTokens,
      'contextUsageRatio': ?instance.contextUsageRatio,
    };

ApiKeyDto _$ApiKeyDtoFromJson(Map<String, dynamic> json) => ApiKeyDto(
  type: $enumDecode(_$ApiKeyTypeEnumMap, json['type']),
  apiKey: json['apiKey'] as String,
);

Map<String, dynamic> _$ApiKeyDtoToJson(ApiKeyDto instance) => <String, dynamic>{
  'type': _$ApiKeyTypeEnumMap[instance.type]!,
  'apiKey': instance.apiKey,
};

const _$ApiKeyTypeEnumMap = {
  ApiKeyType.basic: 'basic',
  ApiKeyType.bearer: 'bearer',
  ApiKeyType.original: 'original',
};

UserTaskDto _$UserTaskDtoFromJson(Map<String, dynamic> json) => UserTaskDto(
  content: (json['content'] as List<dynamic>)
      .map((e) => ContentDto.fromJson(e as Map<String, dynamic>))
      .toList(),
  isChunk: json['isChunk'] as bool?,
  extraSystemPrompt: json['extraSystemPrompt'] as String?,
  llmConfig: json['llmConfig'] == null
      ? null
      : LLMConfigDto.fromJson(json['llmConfig'] as Map<String, dynamic>),
);

Map<String, dynamic> _$UserTaskDtoToJson(UserTaskDto instance) =>
    <String, dynamic>{
      'content': instance.content.map((e) => e.toJson()).toList(),
      'isChunk': ?instance.isChunk,
      'extraSystemPrompt': ?instance.extraSystemPrompt,
      'llmConfig': ?instance.llmConfig?.toJson(),
    };

SessionTaskDto _$SessionTaskDtoFromJson(Map<String, dynamic> json) =>
    SessionTaskDto(
      sessionId: json['sessionId'] as String,
      taskId: json['taskId'] as String?,
    );

Map<String, dynamic> _$SessionTaskDtoToJson(SessionTaskDto instance) =>
    <String, dynamic>{
      'sessionId': instance.sessionId,
      'taskId': ?instance.taskId,
    };

TaskStatusDto _$TaskStatusDtoFromJson(Map<String, dynamic> json) =>
    TaskStatusDto(
      status: json['status'] as String,
      taskId: json['taskId'] as String,
      description: json['description'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$TaskStatusDtoToJson(TaskStatusDto instance) =>
    <String, dynamic>{
      'status': instance.status,
      'taskId': instance.taskId,
      'description': ?instance.description,
    };

ContentDto _$ContentDtoFromJson(Map<String, dynamic> json) => ContentDto(
  type: json['type'] as String,
  message: json['message'] as String,
);

Map<String, dynamic> _$ContentDtoToJson(ContentDto instance) =>
    <String, dynamic>{'type': instance.type, 'message': instance.message};

AgentMessageChunkDto _$AgentMessageChunkDtoFromJson(
  Map<String, dynamic> json,
) => AgentMessageChunkDto(
  sessionId: json['sessionId'] as String,
  agentId: json['agentId'] as String?,
  parentTaskId: json['parentTaskId'] as String?,
  taskId: json['taskId'] as String,
  role: json['role'] as String,
  to: json['to'] as String,
  type: json['type'] as String,
  part: json['part'],
  createTime: DateTime.parse(json['createTime'] as String),
);

Map<String, dynamic> _$AgentMessageChunkDtoToJson(
  AgentMessageChunkDto instance,
) => <String, dynamic>{
  'sessionId': instance.sessionId,
  'agentId': ?instance.agentId,
  'parentTaskId': ?instance.parentTaskId,
  'taskId': instance.taskId,
  'role': instance.role,
  'to': instance.to,
  'type': instance.type,
  'part': ?instance.part,
  'createTime': instance.createTime.toIso8601String(),
};

AgentDto _$AgentDtoFromJson(Map<String, dynamic> json) => AgentDto(
  name: json['name'] as String,
  capability: CapabilityDto.fromJson(
    json['capability'] as Map<String, dynamic>,
  ),
);

Map<String, dynamic> _$AgentDtoToJson(AgentDto instance) => <String, dynamic>{
  'name': instance.name,
  'capability': instance.capability.toJson(),
};

SessionAgentMessageDto _$SessionAgentMessageDtoFromJson(
  Map<String, dynamic> json,
) => SessionAgentMessageDto(
  sessionId: json['sessionId'] as String,
  agentMessageDto: AgentMessageDto.fromJson(
    json['agentMessageDto'] as Map<String, dynamic>,
  ),
);

Map<String, dynamic> _$SessionAgentMessageDtoToJson(
  SessionAgentMessageDto instance,
) => <String, dynamic>{
  'sessionId': instance.sessionId,
  'agentMessageDto': instance.agentMessageDto.toJson(),
};

CallbackOpenToolDto _$CallbackOpenToolDtoFromJson(Map<String, dynamic> json) =>
    CallbackOpenToolDto(
      opentool: json['opentool'] as String,
      timeout: (json['timeout'] as num?)?.toInt(),
    );

Map<String, dynamic> _$CallbackOpenToolDtoToJson(
  CallbackOpenToolDto instance,
) => <String, dynamic>{
  'opentool': instance.opentool,
  'timeout': ?instance.timeout,
};

PresetOpenSpecDto _$PresetOpenSpecDtoFromJson(Map<String, dynamic> json) =>
    PresetOpenSpecDto(
      systemPrompt: json['systemPrompt'] as String,
      openSpec: json['openSpec'] == null
          ? null
          : OpenSpecDto.fromJson(json['openSpec'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$PresetOpenSpecDtoToJson(PresetOpenSpecDto instance) =>
    <String, dynamic>{
      'systemPrompt': instance.systemPrompt,
      'openSpec': ?instance.openSpec?.toJson(),
    };

SessionInfoDto _$SessionInfoDtoFromJson(Map<String, dynamic> json) =>
    SessionInfoDto(
      sessionId: json['sessionId'] as String,
      agentId: json['agentId'] as String?,
      createTime: DateTime.parse(json['createTime'] as String),
      topic: json['topic'] as String?,
    );

Map<String, dynamic> _$SessionInfoDtoToJson(SessionInfoDto instance) =>
    <String, dynamic>{
      'sessionId': instance.sessionId,
      'agentId': ?instance.agentId,
      'createTime': instance.createTime.toIso8601String(),
      'topic': ?instance.topic,
    };
