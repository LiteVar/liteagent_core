// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SessionDto _$SessionDtoFromJson(Map<String, dynamic> json) => SessionDto(
      sessionId: json['sessionId'] as String,
    );

Map<String, dynamic> _$SessionDtoToJson(SessionDto instance) =>
    <String, dynamic>{
      'sessionId': instance.sessionId,
    };

SessionNameDto _$SessionNameDtoFromJson(Map<String, dynamic> json) =>
    SessionNameDto(
      sessionId: json['sessionId'] as String,
      name: json['name'] as String?,
      description: json['description'] as String?,
    );

Map<String, dynamic> _$SessionNameDtoToJson(SessionNameDto instance) {
  final val = <String, dynamic>{
    'sessionId': instance.sessionId,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('name', instance.name);
  writeNotNull('description', instance.description);
  return val;
}

SimpleCapabilityDto _$SimpleCapabilityDtoFromJson(Map<String, dynamic> json) =>
    SimpleCapabilityDto(
      llmConfig:
          LLMConfigDto.fromJson(json['llmConfig'] as Map<String, dynamic>),
      systemPrompt: json['systemPrompt'] as String,
    );

Map<String, dynamic> _$SimpleCapabilityDtoToJson(
        SimpleCapabilityDto instance) =>
    <String, dynamic>{
      'llmConfig': instance.llmConfig.toJson(),
      'systemPrompt': instance.systemPrompt,
    };

CapabilityDto _$CapabilityDtoFromJson(Map<String, dynamic> json) =>
    CapabilityDto(
      llmConfig:
          LLMConfigDto.fromJson(json['llmConfig'] as Map<String, dynamic>),
      systemPrompt: json['systemPrompt'] as String,
      openSpecList: (json['openSpecList'] as List<dynamic>?)
          ?.map((e) => OpenSpecDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      callbackOpenTool: json['callbackOpenTool'] == null
          ? null
          : CallbackOpenToolDto.fromJson(
              json['callbackOpenTool'] as Map<String, dynamic>),
      sessionList: (json['sessionList'] as List<dynamic>?)
          ?.map((e) => SessionNameDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      reflectPromptList: (json['reflectPromptList'] as List<dynamic>?)
          ?.map((e) => ReflectPromptDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      timeoutSeconds: (json['timeoutSeconds'] as num?)?.toInt() ?? 3600,
      taskPipelineStrategy: json['taskPipelineStrategy'] as String? ??
          PipelineStrategyType.PARALLEL,
      toolPipelineStrategy: json['toolPipelineStrategy'] as String?,
      auto: json['auto'] as bool?,
      llmConfigList: (json['llmConfigList'] as List<dynamic>?)
          ?.map((e) => LLMConfigDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      enableThinking: json['enableThinking'] as bool?,
    );

Map<String, dynamic> _$CapabilityDtoToJson(CapabilityDto instance) {
  final val = <String, dynamic>{
    'llmConfig': instance.llmConfig.toJson(),
    'systemPrompt': instance.systemPrompt,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull(
      'openSpecList', instance.openSpecList?.map((e) => e.toJson()).toList());
  writeNotNull('callbackOpenTool', instance.callbackOpenTool?.toJson());
  writeNotNull(
      'sessionList', instance.sessionList?.map((e) => e.toJson()).toList());
  writeNotNull('reflectPromptList',
      instance.reflectPromptList?.map((e) => e.toJson()).toList());
  val['timeoutSeconds'] = instance.timeoutSeconds;
  val['taskPipelineStrategy'] = instance.taskPipelineStrategy;
  writeNotNull('toolPipelineStrategy', instance.toolPipelineStrategy);
  writeNotNull('auto', instance.auto);
  writeNotNull(
      'llmConfigList', instance.llmConfigList?.map((e) => e.toJson()).toList());
  writeNotNull('enableThinking', instance.enableThinking);
  return val;
}

OpenSpecDto _$OpenSpecDtoFromJson(Map<String, dynamic> json) => OpenSpecDto(
      openSpec: json['openSpec'] as String,
      protocol: json['protocol'] as String,
      apiKey: json['apiKey'] == null
          ? null
          : ApiKeyDto.fromJson(json['apiKey'] as Map<String, dynamic>),
      serverUrl: json['serverUrl'] as String?,
    );

Map<String, dynamic> _$OpenSpecDtoToJson(OpenSpecDto instance) {
  final val = <String, dynamic>{
    'openSpec': instance.openSpec,
    'protocol': instance.protocol,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('serverUrl', instance.serverUrl);
  writeNotNull('apiKey', instance.apiKey?.toJson());
  return val;
}

LLMConfigDto _$LLMConfigDtoFromJson(Map<String, dynamic> json) => LLMConfigDto(
      baseUrl: json['baseUrl'] as String,
      apiKey: json['apiKey'] as String,
      model: json['model'] as String,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.0,
      maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 4096,
      topP: (json['topP'] as num?)?.toDouble() ?? 1.0,
      supportsToolCalling: json['supportsToolCalling'] as bool? ?? true,
      supportsDeepThinking: json['supportsDeepThinking'] as bool? ?? false,
    );

Map<String, dynamic> _$LLMConfigDtoToJson(LLMConfigDto instance) =>
    <String, dynamic>{
      'baseUrl': instance.baseUrl,
      'apiKey': instance.apiKey,
      'model': instance.model,
      'temperature': instance.temperature,
      'maxTokens': instance.maxTokens,
      'topP': instance.topP,
      'supportsToolCalling': instance.supportsToolCalling,
      'supportsDeepThinking': instance.supportsDeepThinking,
    };

AgentMessageDto _$AgentMessageDtoFromJson(Map<String, dynamic> json) =>
    AgentMessageDto(
      sessionId: json['sessionId'] as String,
      agentId: json['agentId'] as String?,
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
              json['completions'] as Map<String, dynamic>),
      createTime: DateTime.parse(json['createTime'] as String),
    );

Map<String, dynamic> _$AgentMessageDtoToJson(AgentMessageDto instance) {
  final val = <String, dynamic>{
    'sessionId': instance.sessionId,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('agentId', instance.agentId);
  writeNotNull('parentTaskId', instance.parentTaskId);
  val['taskId'] = instance.taskId;
  val['role'] = instance.role;
  val['to'] = instance.to;
  val['type'] = instance.type;
  writeNotNull('content', instance.content);
  writeNotNull('reasoningContent', instance.reasoningContent);
  writeNotNull('completions', instance.completions?.toJson());
  val['createTime'] = instance.createTime.toIso8601String();
  return val;
}

CompletionsDto _$CompletionsDtoFromJson(Map<String, dynamic> json) =>
    CompletionsDto(
      usage: TokenUsageDto.fromJson(json['usage'] as Map<String, dynamic>),
      id: json['id'] as String,
      model: json['model'] as String,
    );

Map<String, dynamic> _$CompletionsDtoToJson(CompletionsDto instance) =>
    <String, dynamic>{
      'usage': instance.usage.toJson(),
      'id': instance.id,
      'model': instance.model,
    };

TokenUsageDto _$TokenUsageDtoFromJson(Map<String, dynamic> json) =>
    TokenUsageDto(
      promptTokens: (json['promptTokens'] as num).toInt(),
      completionTokens: (json['completionTokens'] as num).toInt(),
      totalTokens: (json['totalTokens'] as num).toInt(),
    );

Map<String, dynamic> _$TokenUsageDtoToJson(TokenUsageDto instance) =>
    <String, dynamic>{
      'promptTokens': instance.promptTokens,
      'completionTokens': instance.completionTokens,
      'totalTokens': instance.totalTokens,
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
    );

Map<String, dynamic> _$UserTaskDtoToJson(UserTaskDto instance) {
  final val = <String, dynamic>{
    'content': instance.content.map((e) => e.toJson()).toList(),
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('isChunk', instance.isChunk);
  return val;
}

SessionTaskDto _$SessionTaskDtoFromJson(Map<String, dynamic> json) =>
    SessionTaskDto(
      sessionId: json['sessionId'] as String,
      taskId: json['taskId'] as String?,
    );

Map<String, dynamic> _$SessionTaskDtoToJson(SessionTaskDto instance) {
  final val = <String, dynamic>{
    'sessionId': instance.sessionId,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('taskId', instance.taskId);
  return val;
}

ReflectScoreDto _$ReflectScoreDtoFromJson(Map<String, dynamic> json) =>
    ReflectScoreDto(
      score: (json['score'] as num).toInt(),
      description: json['description'] as String?,
    );

Map<String, dynamic> _$ReflectScoreDtoToJson(ReflectScoreDto instance) {
  final val = <String, dynamic>{
    'score': instance.score,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('description', instance.description);
  return val;
}

MessageScoreDto _$MessageScoreDtoFromJson(Map<String, dynamic> json) =>
    MessageScoreDto(
      contentList: (json['contentList'] as List<dynamic>)
          .map((e) => ContentDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      messageType: json['messageType'] as String,
      message: json['message'] as String,
      reflectScoreList: (json['reflectScoreList'] as List<dynamic>)
          .map((e) => ReflectScoreDto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$MessageScoreDtoToJson(MessageScoreDto instance) =>
    <String, dynamic>{
      'contentList': instance.contentList.map((e) => e.toJson()).toList(),
      'messageType': instance.messageType,
      'message': instance.message,
      'reflectScoreList':
          instance.reflectScoreList.map((e) => e.toJson()).toList(),
    };

ReflectionDto _$ReflectionDtoFromJson(Map<String, dynamic> json) =>
    ReflectionDto(
      isPass: json['isPass'] as bool,
      messageScore: MessageScoreDto.fromJson(
          json['messageScore'] as Map<String, dynamic>),
      passScore: (json['passScore'] as num).toInt(),
      count: (json['count'] as num).toInt(),
      maxCount: (json['maxCount'] as num).toInt(),
    );

Map<String, dynamic> _$ReflectionDtoToJson(ReflectionDto instance) =>
    <String, dynamic>{
      'isPass': instance.isPass,
      'messageScore': instance.messageScore.toJson(),
      'passScore': instance.passScore,
      'count': instance.count,
      'maxCount': instance.maxCount,
    };

TaskStatusDto _$TaskStatusDtoFromJson(Map<String, dynamic> json) =>
    TaskStatusDto(
      status: json['status'] as String,
      taskId: json['taskId'] as String,
      description: json['description'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$TaskStatusDtoToJson(TaskStatusDto instance) {
  final val = <String, dynamic>{
    'status': instance.status,
    'taskId': instance.taskId,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('description', instance.description);
  return val;
}

ContentDto _$ContentDtoFromJson(Map<String, dynamic> json) => ContentDto(
      type: json['type'] as String,
      message: json['message'] as String,
    );

Map<String, dynamic> _$ContentDtoToJson(ContentDto instance) =>
    <String, dynamic>{
      'type': instance.type,
      'message': instance.message,
    };

ReflectPromptDto _$ReflectPromptDtoFromJson(Map<String, dynamic> json) =>
    ReflectPromptDto(
      llmConfig:
          LLMConfigDto.fromJson(json['llmConfig'] as Map<String, dynamic>),
      prompt: json['prompt'] as String,
    );

Map<String, dynamic> _$ReflectPromptDtoToJson(ReflectPromptDto instance) =>
    <String, dynamic>{
      'llmConfig': instance.llmConfig.toJson(),
      'prompt': instance.prompt,
    };

AgentMessageChunkDto _$AgentMessageChunkDtoFromJson(
        Map<String, dynamic> json) =>
    AgentMessageChunkDto(
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
    AgentMessageChunkDto instance) {
  final val = <String, dynamic>{
    'sessionId': instance.sessionId,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('agentId', instance.agentId);
  writeNotNull('parentTaskId', instance.parentTaskId);
  val['taskId'] = instance.taskId;
  val['role'] = instance.role;
  val['to'] = instance.to;
  val['type'] = instance.type;
  writeNotNull('part', instance.part);
  val['createTime'] = instance.createTime.toIso8601String();
  return val;
}

AgentIdDto _$AgentIdDtoFromJson(Map<String, dynamic> json) => AgentIdDto(
      agentId: json['agentId'] as String,
    );

Map<String, dynamic> _$AgentIdDtoToJson(AgentIdDto instance) =>
    <String, dynamic>{
      'agentId': instance.agentId,
    };

AgentDto _$AgentDtoFromJson(Map<String, dynamic> json) => AgentDto(
      name: json['name'] as String,
      capability:
          CapabilityDto.fromJson(json['capability'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$AgentDtoToJson(AgentDto instance) => <String, dynamic>{
      'name': instance.name,
      'capability': instance.capability.toJson(),
    };

AgentInfoDto _$AgentInfoDtoFromJson(Map<String, dynamic> json) => AgentInfoDto(
      agentId: json['agentId'] as String,
      name: json['name'] as String,
      capability:
          CapabilityDto.fromJson(json['capability'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$AgentInfoDtoToJson(AgentInfoDto instance) =>
    <String, dynamic>{
      'agentId': instance.agentId,
      'name': instance.name,
      'capability': instance.capability.toJson(),
    };

SessionAgentMessageDto _$SessionAgentMessageDtoFromJson(
        Map<String, dynamic> json) =>
    SessionAgentMessageDto(
      sessionId: json['sessionId'] as String,
      agentMessageDto: AgentMessageDto.fromJson(
          json['agentMessageDto'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$SessionAgentMessageDtoToJson(
        SessionAgentMessageDto instance) =>
    <String, dynamic>{
      'sessionId': instance.sessionId,
      'agentMessageDto': instance.agentMessageDto.toJson(),
    };

CallbackOpenToolDto _$CallbackOpenToolDtoFromJson(Map<String, dynamic> json) =>
    CallbackOpenToolDto(
      opentool: json['opentool'] as String,
      timeout: (json['timeout'] as num?)?.toInt(),
    );

Map<String, dynamic> _$CallbackOpenToolDtoToJson(CallbackOpenToolDto instance) {
  final val = <String, dynamic>{
    'opentool': instance.opentool,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('timeout', instance.timeout);
  return val;
}
