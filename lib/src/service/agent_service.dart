import 'dart:async';
import 'package:liteagent_core_dart/liteagent_core.dart';
import 'package:opentool_dart/opentool_client.dart' as ot;
import 'package:openapi_dart/openapi_dart.dart';
import 'package:openrpc_dart/openrpc_dart.dart';
import 'package:unique_id_dart/unique_id_dart.dart';
import 'dart:collection';
import 'session_message_manage_service.dart';
import 'dto.dart';
import 'exception.dart';

class AgentService {
  static const int _SENT_MESSAGES_CAPACITY = 500;
  final SkillParser _skillParser = MarkdownSkillParser();
  final SkillValidator _skillValidator = const SkillValidator();

  Map<String, SessionAgent> sessionAgents = {};

  /// Map<sessionId, SessionAgent>
  Map<String, SimpleAgent> simpleAgents = {};

  /// Map<sessionId, SimpleAgent>
  List<ToolDriver> globalDriverList = [];
  Map<String, OpenToolCallbackDriver> callbackOpenToolMap = {};
  final Map<String, Set<OpenToolCallbackDriver>> _callbackDriversBySessionId =
      {};
  final Map<OpenToolCallbackDriver, Set<String>> _callbackDriverSessionIds = {};
  final Map<String, OpenToolCallbackDriver> _callbackDriversByFunctionCallId =
      {};

  /// Map<sessionId, ClientDriver>
  List<PresetOpenSpecDto> _presetOpenSpecList = [];
  List<SessionMessageManageService> agentMessageManageServiceList = [];
  LinkedHashMap<Message, Map<String, bool>> sentMessages =
      LinkedHashMap<Message, Map<String, bool>>();

  /// Map<Message, Map<sessionId, bool>>
  Map<String, String> _sessionBaseSystemPromptMap = {};

  /// Map<sessionId, baseSystemPrompt>
  Map<String, String?> _sessionExtraSystemPromptMap = {};

  /// Map<sessionId, extraSystemPrompt>
  Map<String, LLMConfig?> _sessionLlmConfigMap = {};

  /// Map<sessionId, default llmConfig from init>
  Map<String, LLMConfig?> _simpleSessionLlmConfigMap = {};

  /// Map<sessionId, default llmConfig from initSimple>

  /// agentId -> sessionId
  Map<String, Set<String>> agentSessionsMap = {};

  /// sessionId -> agentId
  Map<String, String> sessionAgentMap = {};

  /// sessionId -> createTime
  Map<String, DateTime> sessionCreateTimeMap = {};

  AgentService(
      {List<ToolDriver> globalToolDriverList = const [],
      List<SessionMessageManageService> messageManageServiceList = const []}) {
    globalDriverList.addAll(globalToolDriverList);
    agentMessageManageServiceList.addAll(messageManageServiceList);
  }

  Future<bool> testLLMConfig(
    String baseUrl,
    String? apiKey, {
    String provider = "openai",
    String? model,
    String? adapter,
    Map<String, String>? headers,
    Map<String, dynamic>? providerOptions,
  }) async {
    return OpenAIUtil.checkLLMConfig(
      baseUrl,
      apiKey,
      provider: provider,
      model: model,
      adapter: adapter,
      headers: headers,
      providerOptions: providerOptions,
    );
  }

  void setPresetOpenSpecList(List<PresetOpenSpecDto> presetOpenSpecList) {
    _presetOpenSpecList = presetOpenSpecList;
  }

  Future<SessionDto> initSimple(SimpleCapabilityDto simpleCapabilityDto) async {
    String sessionId = uniqueId();
    String systemPrompt = simpleCapabilityDto.systemPrompt;
    LLMConfig? llmConfig = simpleCapabilityDto.llmConfig?.toModel();

    String fullSystemPrompt = _mergeFullSystemPrompt(
      systemPrompt,
      skills: simpleCapabilityDto.skills,
    );

    SimpleAgent simpleAgent = SimpleAgent(
        llmConfig: llmConfig,
        systemPrompt: fullSystemPrompt,
        responseFormat: ResponseFormat(type: ResponseFormatType.TEXT));

    simpleAgents[sessionId] = simpleAgent;
    _simpleSessionLlmConfigMap[sessionId] = llmConfig;

    SessionDto sessionDto = SessionDto(sessionId: sessionId);
    return sessionDto;
  }

  Future<AgentMessageDto> startSimple(
      String sessionId, UserTaskDto userTaskDto) async {
    SimpleAgent? simpleAgent = simpleAgents[sessionId];
    if (simpleAgent == null)
      throw SessionAgentNotFoundException(sessionId: sessionId);
    LLMConfig? llmConfig = userTaskDto.llmConfig?.toModel() ??
        _simpleSessionLlmConfigMap[sessionId] ??
        simpleAgent.llmConfig;
    if (llmConfig == null) {
      throw LLMConfigRequiredException(
          scene: "chat/simple", sessionId: sessionId);
    }
    if (userTaskDto.extraSystemPrompt != null) {
      String? extraSystemPrompt = userTaskDto.extraSystemPrompt;
      if (extraSystemPrompt != null && extraSystemPrompt.isEmpty) {
        extraSystemPrompt = null;
      }
      String baseSystemPrompt = simpleAgent.systemPrompt ?? "";
      simpleAgent.systemPrompt = _buildEffectiveSystemPrompt(
        baseSystemPrompt,
        extraSystemPrompt,
      );
    }
    List<Content> userMessageList = userTaskDto.content
        .map((userMessageDto) => _convertToContent(userMessageDto))
        .toList();
    try {
      AgentMessage agentMessage = await simpleAgent.userToAgent(
          contentList: userMessageList, requestLLMConfig: llmConfig);
      return AgentMessageDto.fromModel(agentMessage);
    } finally {
      simpleAgents.remove(sessionId);
      _simpleSessionLlmConfigMap.remove(sessionId);
    }
  }

  /// Initializes a new session, or reconstructs an evicted session when
  /// [restoreState] is supplied.
  ///
  /// [restoreState] is only for restoring persisted completed context. Normal
  /// session creation must leave it unset.
  Future<SessionDto> initSession(
    CapabilityDto capabilityDto, {
    String? agentId,
    SessionRestoreState? restoreState,
    List<ToolDriver>? customToolDriverList,
  }) async {
    final String sessionId = restoreState?.sessionId ?? uniqueId();
    if (sessionAgents.containsKey(sessionId)) {
      throw SessionAlreadyExistsException(sessionId: sessionId);
    }
    DateTime createTime = DateTime.now();

    if (agentId != null) {
      sessionAgentMap[sessionId] = agentId;
      agentSessionsMap.putIfAbsent(agentId, () => <String>{});
      agentSessionsMap[agentId]!.add(sessionId);
    }
    sessionCreateTimeMap[sessionId] = createTime;
    String systemPrompt = capabilityDto.systemPrompt;
    String fullSystemPrompt = _mergeFullSystemPrompt(
      systemPrompt,
      skills: capabilityDto.skills,
    );
    _sessionBaseSystemPromptMap[sessionId] = fullSystemPrompt;
    _sessionExtraSystemPromptMap[sessionId] = null;
    LLMConfig? llmConfig = capabilityDto.llmConfig?.toModel();
    final int? resolvedToolReturnPackMinLength =
        capabilityDto.toolReturnPackMinLength == null
            ? 800
            : (capabilityDto.toolReturnPackMinLength! <= 0
                ? null
                : capabilityDto.toolReturnPackMinLength);
    final toolExecutionLimits = ToolExecutionLimits(
      maxLlmRequests: capabilityDto.maxLlmRequests ?? 64,
      maxToolRounds: capabilityDto.maxToolRounds ?? 16,
      maxToolCalls: capabilityDto.maxToolCalls ?? 64,
      maxConsecutiveIdenticalToolRounds:
          capabilityDto.maxConsecutiveIdenticalToolRounds ?? 3,
      maxTaskDurationSeconds: capabilityDto.maxTaskDurationSeconds ?? 300,
    );
    _sessionLlmConfigMap[sessionId] = llmConfig;
    List<ReflectPrompt>? reflectPromptList = capabilityDto.reflectPromptList
        ?.map((reflectPromptDto) => ReflectPrompt(
            llmConfig: reflectPromptDto.llmConfig.toModel(),
            prompt: reflectPromptDto.prompt))
        .toList();
    List<ToolDriver> toolDriverList = [];
    toolDriverList.addAll(globalDriverList);
    List<OpenSpecDto> presetOpenSpecList = _presetOpenSpecList
        .where((presetOpenSpec) => presetOpenSpec.openSpec != null)
        .map((presetOpenSpec) => presetOpenSpec.openSpec!)
        .toList();
    toolDriverList.addAll(await _buildToolDriverList(presetOpenSpecList));
    toolDriverList
        .addAll(await _buildToolDriverList(capabilityDto.openSpecList));
    if (customToolDriverList != null)
      toolDriverList.addAll(customToolDriverList);

    List<AgentDriver>? subAgentDriverList =
        await _buildAgentDriverList(capabilityDto.sessionList, sessionId);
    final AgentSession agentSession = _buildSession(
      sessionId,
      restoreState: restoreState,
    );

    if (capabilityDto.auto == true) {
      // AutoAgent
      List<LLMConfig>? llmConfigList = capabilityDto.llmConfigList
          ?.map((llmConfigDto) => llmConfigDto.toModel())
          .toList();

      CallbackOpenTool? clientOpenTool;
      if (capabilityDto.callbackOpenTool != null)
        clientOpenTool = CallbackOpenTool(
            opentool: capabilityDto.callbackOpenTool!.opentool,
            timeout: capabilityDto.callbackOpenTool!.timeout,
            fetchClientDriver: this.fetchClientDriver,
            releaseClientDriver: this.releaseClientDriver);

      AutoMultiAgent autoMultiAgent = await AutoMultiAgent.create(
        sessionId: sessionId,
        llmConfig: llmConfig,
        agentSession: agentSession,
        toolDriverList: toolDriverList,
        clientOpenTool: clientOpenTool,
        systemPrompt: fullSystemPrompt,
        toolReflectPromptList: reflectPromptList ?? const [],
        timeoutSeconds: capabilityDto.timeoutSeconds,
        taskPipelineStrategy: capabilityDto.taskPipelineStrategy,
        toolPipelineStrategy:
            capabilityDto.toolPipelineStrategy ?? PipelineStrategyType.PARALLEL,
        enableThinking: capabilityDto.enableThinking,
        llmConfigList: llmConfigList,
        toolReturnPackMinLength: resolvedToolReturnPackMinLength,
        executionLimits: toolExecutionLimits,
      );
      _attachIdleTimeoutHandler(autoMultiAgent);
      sessionAgents[sessionId] = autoMultiAgent;
    } else if (toolDriverList.isEmpty &&
        subAgentDriverList == null &&
        capabilityDto.callbackOpenTool == null) {
      // TextAgent
      SessionAgent textAgent = TextAgent(
          sessionId: sessionId,
          llmConfig: llmConfig,
          agentSession: agentSession,
          systemPrompt: fullSystemPrompt,
          textReflectPromptList: reflectPromptList ?? [],
          timeoutSeconds: capabilityDto.timeoutSeconds,
          taskPipelineStrategy: capabilityDto.taskPipelineStrategy,
          enableThinking: capabilityDto.enableThinking);
      _attachIdleTimeoutHandler(textAgent);
      sessionAgents[sessionId] = textAgent;
    } else if (subAgentDriverList == null) {
      // ToolAgent
      CallbackOpenTool? clientOpenTool = null;
      if (capabilityDto.callbackOpenTool != null)
        clientOpenTool = CallbackOpenTool(
            opentool: capabilityDto.callbackOpenTool!.opentool,
            timeout: capabilityDto.callbackOpenTool!.timeout,
            fetchClientDriver: this.fetchClientDriver,
            releaseClientDriver: this.releaseClientDriver);
      SessionAgent toolAgent = ToolAgent(
          sessionId: sessionId,
          llmConfig: llmConfig,
          agentSession: agentSession,
          toolDriverList: toolDriverList,
          callbackOpenTool: clientOpenTool,
          systemPrompt: fullSystemPrompt,
          toolReflectPromptList: reflectPromptList ?? [],
          timeoutSeconds: capabilityDto.timeoutSeconds,
          taskPipelineStrategy: capabilityDto.taskPipelineStrategy,
          toolPipelineStrategy: capabilityDto.toolPipelineStrategy ??
              PipelineStrategyType.PARALLEL,
          enableThinking: capabilityDto.enableThinking,
          toolReturnPackMinLength: resolvedToolReturnPackMinLength,
          executionLimits: toolExecutionLimits);
      _attachIdleTimeoutHandler(toolAgent);
      sessionAgents[sessionId] = toolAgent;
    } else {
      // MultiAgent
      CallbackOpenTool? clientOpenTool = null;
      if (capabilityDto.callbackOpenTool != null)
        clientOpenTool = CallbackOpenTool(
            opentool: capabilityDto.callbackOpenTool!.opentool,
            timeout: capabilityDto.callbackOpenTool!.timeout,
            fetchClientDriver: this.fetchClientDriver,
            releaseClientDriver: this.releaseClientDriver);
      SessionAgent toolAgent = MultiAgent(
          sessionId: sessionId,
          llmConfig: llmConfig,
          agentSession: agentSession,
          toolDriverList: toolDriverList,
          subAgentDriverList: subAgentDriverList,
          clientOpenTool: clientOpenTool,
          systemPrompt: fullSystemPrompt,
          toolReflectPromptList: reflectPromptList ?? [],
          timeoutSeconds: capabilityDto.timeoutSeconds,
          taskPipelineStrategy: capabilityDto.taskPipelineStrategy,
          toolPipelineStrategy: capabilityDto.toolPipelineStrategy ??
              PipelineStrategyType.PARALLEL,
          enableThinking: capabilityDto.enableThinking,
          toolReturnPackMinLength: resolvedToolReturnPackMinLength,
          executionLimits: toolExecutionLimits);
      _attachIdleTimeoutHandler(toolAgent);
      sessionAgents[sessionId] = toolAgent;
    }

    SessionDto sessionDto = SessionDto(sessionId: sessionId);

    return sessionDto;
  }

  Future<void> startSession(
      String sessionId,
      UserTaskDto userTaskDto,
      void Function(
              String sessionId, String taskId, AgentMessageDto agentMessageDto)
          listen,
      {void Function(String sessionId, String taskId,
              AgentMessageChunkDto agentMessageChunkDto)?
          listenChunk,
      void Function(String taskId)? getTaskId}) async {
    SessionAgent? sessionAgent = sessionAgents[sessionId];
    if (sessionAgent == null)
      throw SessionAgentNotFoundException(sessionId: sessionId);
    LLMConfig? llmConfig =
        userTaskDto.llmConfig?.toModel() ?? _sessionLlmConfigMap[sessionId];
    if (llmConfig == null) {
      throw LLMConfigRequiredException(scene: "chat", sessionId: sessionId);
    }
    _updateSessionSystemPrompt(
        sessionId, sessionAgent, userTaskDto.extraSystemPrompt);
    List<Content> userMessageList = userTaskDto.content
        .map((contentDto) => _convertToContent(contentDto))
        .toList();

    void Function(String taskId) fetchTaskId = (String taskId) {
      if (getTaskId != null) getTaskId(taskId);
      if (sessionAgent is MultiAgent) {
        List<String> subSessionIds = getSubSessionIds(sessionId);
        if (subSessionIds.isNotEmpty) {
          _updateSession(sessionAgent.agentSession, taskId, listen,
              listenChunk: listenChunk, subAgentSessionList: subSessionIds);
        } else {
          _updateSession(sessionAgent.agentSession, taskId, listen,
              listenChunk: listenChunk);
        }
      } else {
        _updateSession(sessionAgent.agentSession, taskId, listen,
            listenChunk: listenChunk);
      }
    };

    await sessionAgent.userToAgent(
        contentList: userMessageList,
        stream: userTaskDto.isChunk,
        requestLLMConfig: llmConfig,
        fetchTaskId: fetchTaskId);
  }

  Future<List<AgentMessageDto>?> getCacheHistory(String sessionId) async {
    SessionAgent? sessionAgent = sessionAgents[sessionId];
    if (sessionAgent == null) return null;
    return sessionAgent.agentSession.listenAgentMessageList
        .map((AgentMessage agentMessage) {
      AgentMessageDto agentMessageDto = AgentMessageDto.fromModel(agentMessage);
      return agentMessageDto;
    }).toList();
  }

  Future<void> stopSession(SessionTaskDto sessionTaskDto) async {
    SessionAgent? sessionAgent = sessionAgents[sessionTaskDto.sessionId];
    if (sessionAgent == null)
      throw SessionAgentNotFoundException(sessionId: sessionTaskDto.sessionId);
    sessionAgent.stop(taskId: sessionTaskDto.taskId);
  }

  Future<void> clearSession(String sessionId) async {
    final Set<String> sessionIdsToClear = _collectSessionIdsForClear(sessionId);
    if (sessionIdsToClear.isEmpty) {
      throw SessionAgentNotFoundException(sessionId: sessionId);
    }
    for (final id in sessionIdsToClear) {
      _clearSessionEntry(id);
    }
    sentMessages.clear();
  }

  List<SessionInfoDto> getSessionsByAgentId(String agentId) {
    Set<String>? sessionIds = agentSessionsMap[agentId];
    if (sessionIds == null || sessionIds.isEmpty) {
      return [];
    }

    return sessionIds.map((sessionId) {
      return SessionInfoDto(
        sessionId: sessionId,
        agentId: agentId,
        createTime: sessionCreateTimeMap[sessionId] ?? DateTime.now(),
        topic: _getSessionTopic(sessionId),
      );
    }).toList();
  }

  String? _getSessionTopic(String sessionId) {
    SessionAgent? sessionAgent = sessionAgents[sessionId];
    if (sessionAgent == null) return null;

    List<AgentMessage> messageList =
        sessionAgent.agentSession.listenAgentMessageList;
    for (AgentMessage message in messageList) {
      if (message.role == AgentRoleType.USER) {
        dynamic content = message.content;
        String? textContent;

        if (content is String) {
          textContent = content;
        } else if (content is List<Content>) {
          for (Content c in content) {
            if (c.type == ContentType.TEXT) {
              textContent = c.message;
              break;
            }
          }
        }

        if (textContent != null && textContent.isNotEmpty) {
          return textContent.length > 50
              ? textContent.substring(0, 50)
              : textContent;
        }
      }
    }
    return null;
  }

  SessionAgent? getSessionAgent(String sessionId) {
    return sessionAgents[sessionId];
  }

  String? getAgentIdBySessionId(String sessionId) {
    return sessionAgentMap[sessionId];
  }

  Content _convertToContent(ContentDto contentDto) {
    return Content(type: contentDto.type, message: contentDto.message);
  }

  AgentSession _buildSession(
    String sessionId, {
    SessionRestoreState? restoreState,
  }) {
    AgentSession agentSession = AgentSession(sessionId: sessionId);
    if (restoreState != null) {
      agentSession.restore(restoreState);
    }
    // agentSession.addAgentMessageListener((AgentMessage agentMessage) {
    //   AgentMessageDto agentMessageDto = AgentMessageDto.fromModel(agentMessage);
    //   _recordAgentMessage(sessionId, agentMessageDto);
    //   listen(sessionId, agentMessageDto);
    // });
    // if(listenChunk != null) {
    //   agentSession.addAgentMessageChunkListener((AgentMessageChunk agentMessageChunk) {
    //     listenChunk(sessionId, AgentMessageChunkDto.fromModel(agentMessageChunk));
    //   });
    // }
    return agentSession;
  }

  void _attachIdleTimeoutHandler(SessionAgent sessionAgent) {
    sessionAgent.onIdleTimeout = (String id) {
      unawaited(clearSession(id));
    };
  }

  Set<String> _collectSessionIdsForClear(String rootSessionId) {
    final Set<String> sessionIds = <String>{};
    if (sessionAgents.containsKey(rootSessionId)) {
      sessionIds.add(rootSessionId);
      sessionIds.addAll(getSubSessionIds(rootSessionId));
      return sessionIds;
    }
    if (simpleAgents.containsKey(rootSessionId)) {
      sessionIds.add(rootSessionId);
    }
    return sessionIds;
  }

  void _clearSessionEntry(String sessionId) {
    SessionAgent? sessionAgent = sessionAgents.remove(sessionId);
    sessionAgent?.clear();
    simpleAgents.remove(sessionId);
    _detachCallbackDriversForSession(sessionId);
    _sessionLlmConfigMap.remove(sessionId);
    _simpleSessionLlmConfigMap.remove(sessionId);

    String? agentId = sessionAgentMap.remove(sessionId);
    if (agentId != null) {
      agentSessionsMap[agentId]?.remove(sessionId);
      if (agentSessionsMap[agentId]?.isEmpty ?? false) {
        agentSessionsMap.remove(agentId);
      }
    }
    sessionCreateTimeMap.remove(sessionId);
  }

  void _updateSession(
      AgentSession agentSession,
      String taskId,
      void Function(
              String sessionId, String taskId, AgentMessageDto agentMessageDto)
          listen,
      {void Function(String sessionId, String taskId,
              AgentMessageChunkDto agentMessageChunkDto)?
          listenChunk,
      List<String>? subAgentSessionList}) {
    agentSession.addAgentMessageListener((AgentMessage agentMessage) {
      AgentMessageDto agentMessageDto = AgentMessageDto.fromModel(agentMessage);
      if ((agentMessage.originalTaskId == taskId ||
              agentMessage.originalTaskId.isEmpty) &&
          !_isSentMessage(agentMessage, agentSession.sessionId)) {
        _recordAgentMessage(agentSession.sessionId, taskId, agentMessageDto);
        listen(agentSession.sessionId, taskId, agentMessageDto);
        _addToSentMessages(agentMessage, agentSession.sessionId);
      }
    });
    if (listenChunk != null) {
      agentSession
          .addAgentMessageChunkListener((AgentMessageChunk agentMessageChunk) {
        if ((agentMessageChunk.originalTaskId == taskId ||
                agentMessageChunk.originalTaskId.isEmpty) &&
            !_isSentMessage(agentMessageChunk, agentSession.sessionId)) {
          listenChunk(agentSession.sessionId, taskId,
              AgentMessageChunkDto.fromModel(agentMessageChunk));
          _addToSentMessages(agentMessageChunk, agentSession.sessionId);
        }
      });
    }

    if (subAgentSessionList != null && subAgentSessionList.isNotEmpty) {
      subAgentSessionList.forEach((subSessionId) {
        SessionAgent? subSessionAgent = sessionAgents[subSessionId];
        if (subSessionAgent != null) {
          subSessionAgent.agentSession
              .addAgentMessageListener((AgentMessage agentMessage) {
            if ((agentMessage.originalTaskId == taskId ||
                    agentMessage.originalTaskId.isEmpty) &&
                !_isSentMessage(agentMessage, subSessionId)) {
              AgentMessageDto agentMessageDto =
                  AgentMessageDto.fromModel(agentMessage);
              _recordAgentMessage(subSessionId, taskId, agentMessageDto);
              listen(subSessionId, taskId, agentMessageDto);
              _addToSentMessages(agentMessage, subSessionId);
            }
          });
          if (listenChunk != null) {
            subSessionAgent.agentSession.addAgentMessageChunkListener(
                (AgentMessageChunk agentMessageChunk) {
              if ((agentMessageChunk.originalTaskId == taskId ||
                      agentMessageChunk.originalTaskId.isEmpty) &&
                  !_isSentMessage(agentMessageChunk, subSessionId)) {
                listenChunk(subSessionId, taskId,
                    AgentMessageChunkDto.fromModel(agentMessageChunk));
                _addToSentMessages(agentMessageChunk, subSessionId);
              }
            });
          }
        }
      });
    }
  }

  Future<List<ToolDriver>> _buildToolDriverList(
      List<OpenSpecDto>? openSpecDtoList) async {
    if (openSpecDtoList == null) return [];
    List<ToolDriver> toolDriverList = [];
    for (OpenSpecDto openSpecDto in openSpecDtoList) {
      if (openSpecDto.protocol == Protocol.OPENAPI) {
        OpenAPI openAPI = await OpenAPILoader().load(openSpecDto.openSpec);
        String? authorization;
        if (openSpecDto.apiKey != null) {
          authorization = convertToAuthorization(
              openSpecDto.apiKey!.type, openSpecDto.apiKey!.apiKey);
        }
        ToolDriver openAPIDriver =
            OpenAPIDriver(openAPI, authorization: authorization);
        toolDriverList.add(openAPIDriver);
      } else if (openSpecDto.protocol == Protocol.JSONRPCHTTP) {
        OpenRPC openRPC = await OpenRPCLoader().load(openSpecDto.openSpec);
        ToolDriver jsonrpcHttpDriver = JsonRPCDriver(openRPC);
        toolDriverList.add(jsonrpcHttpDriver);
      } else if (openSpecDto.protocol == Protocol.MCP_STDIO) {
        McpStdioDriver mcpStdioDriver =
            McpStdioDriver.fromMcpStdioString(openSpecDto.openSpec);
        toolDriverList.add(mcpStdioDriver);
      } else if (openSpecDto.protocol == Protocol.MCP_HTTP) {
        McpHttpDriver mcpHttpDriver =
            McpHttpDriver.fromMcpHttpString(openSpecDto.openSpec);
        toolDriverList.add(mcpHttpDriver);
      } else if (openSpecDto.protocol == Protocol.OPENTOOL) {
        ot.OpenTool opentool =
            await ot.OpenToolJsonLoader().load(openSpecDto.openSpec);
        if (opentool.server == null && openSpecDto.serverUrl != null) {
          opentool.server =
              ot.ServerConfig(url: openSpecDto.serverUrl!, description: "");
        }
        String? apiKey;
        if (openSpecDto.apiKey != null) {
          apiKey = convertToAuthorization(
              openSpecDto.apiKey!.type, openSpecDto.apiKey!.apiKey);
        }
        OpenToolDriver? opentoolDriver =
            OpenToolClientDriver(opentool, apiKey: apiKey);
        toolDriverList.add(opentoolDriver);
      }
    }

    return toolDriverList;
  }

  Future<List<AgentDriver>?> _buildAgentDriverList(
      List<SessionNameDto>? sessionList, String sessionId) async {
    if (sessionList == null || sessionList.isEmpty) return null;
    List<NamedSimpleAgent> namedSimpleAgentList = [];
    List<NamedSessionAgent> namedSessionAgentList = [];
    sessionList.forEach((session) {
      SimpleAgent? simpleAgent = simpleAgents[session.sessionId];
      SessionAgent? sessionAgent = sessionAgents[session.sessionId];
      if (simpleAgent == null && sessionAgent == null)
        throw SessionAgentNotFoundException(sessionId: session.sessionId);

      if (simpleAgent != null) {
        namedSimpleAgentList.add(NamedSimpleAgent(
            name: session.name ?? session.sessionId,
            description: session.description,
            agent: simpleAgent));
      }
      if (sessionAgent != null) {
        String agentName = session.name ?? session.sessionId;
        // void Function(AgentMessage agentMessage) AgentListen = (AgentMessage agentMessage){
        //     String role = agentMessage.role;
        //     if(agentMessage.role == AgentRoleType.AGENT) role = AgentRoleType.SUBAGENT;
        //     if(agentMessage.role == AgentRoleType.USER) role = AgentRoleType.AGENT;
        //     String to = agentMessage.to;
        //     if(agentMessage.to == AgentRoleType.AGENT) to = AgentRoleType.SUBAGENT;
        //     if(agentMessage.to == AgentRoleType.USER) to = AgentRoleType.AGENT;
        //
        //     AgentMessage subAgentMessage = AgentMessage(
        //       sessionId: agentMessage.sessionId,
        //       parentTaskId: agentMessage.parentTaskId,
        //       taskId: agentMessage.taskId,
        //       role: role,
        //       to: to,
        //       type: agentMessage.type,
        //       content: agentMessage.content
        //     );
        //     if(role == AgentRoleType.SUBAGENT && agentMessage.type == AgentMessageType.TASK_STATUS) {
        //       if(agentMessage.content is TaskStatus) {
        //         TaskStatus taskStatus = agentMessage.content as TaskStatus;
        //         if(taskStatus.status == TaskStatusType.START) {
        //           taskStatus.description = {"subAgent": agentName};
        //           subAgentMessage = AgentMessage(
        //             sessionId: agentMessage.sessionId,
        //             parentTaskId: agentMessage.parentTaskId,
        //             taskId: agentMessage.taskId,
        //             role: role,
        //             to: to,
        //             type: agentMessage.type,
        //             content: taskStatus
        //           );
        //         }
        //       }
        //     }
        //
        //   AgentMessageDto agentMessageDto = AgentMessageDto.fromModel(subAgentMessage);
        //   _recordAgentMessage(session.sessionId, agentMessageDto);
        //   listen(sessionId, agentMessageDto);
        // };
        // sessionAgent.agentSession.addAgentMessageListener(AgentListen);
        namedSessionAgentList.add(NamedSessionAgent(
            name: agentName,
            description: session.description,
            agent: sessionAgent));
      }
    });

    SimpleAgentDriver simpleAgentDriver =
        SimpleAgentDriver(namedSimpleAgents: namedSimpleAgentList);
    SessionAgentDriver sessionAgentDriver =
        SessionAgentDriver(namedSessionAgents: namedSessionAgentList);

    List<AgentDriver> agentDriverList = [];
    agentDriverList.add(simpleAgentDriver);
    agentDriverList.add(sessionAgentDriver);
    return agentDriverList;
  }

  void _recordAgentMessage(
      String sessionId, String taskId, AgentMessageDto agentMessageDto) {
    SessionAgentMessageDto sessionAgentMessageDto = SessionAgentMessageDto(
        sessionId: sessionId, agentMessageDto: agentMessageDto);
    agentMessageManageServiceList.forEach((service) {
      service.addMessage(sessionAgentMessageDto);
    });
  }

  bool _isSentMessage(Message message, String toSessionId) {
    return sentMessages.containsKey(message) &&
        sentMessages[message]![toSessionId] == true;
  }

  void _addToSentMessages(Message message, String toSessionId) {
    if (sentMessages.length >= _SENT_MESSAGES_CAPACITY) {
      sentMessages.remove(sentMessages.keys.first);
    }
    if (!sentMessages.containsKey(message)) {
      sentMessages[message] = {toSessionId: true};
    } else {
      sentMessages[message]![toSessionId] = true;
    }
  }

  void fetchClientDriver(
      String sessionId, OpenToolCallbackDriver clientDriver) {
    callbackOpenToolMap[sessionId] = clientDriver;
    _callbackDriversBySessionId.putIfAbsent(
      sessionId,
      () => <OpenToolCallbackDriver>{},
    );
    _callbackDriversBySessionId[sessionId]!.add(clientDriver);
    _callbackDriverSessionIds.putIfAbsent(
      clientDriver,
      () => <String>{},
    );
    _callbackDriverSessionIds[clientDriver]!.add(sessionId);
    clientDriver.setPendingCallHooks(
      registerPendingCall: _registerPendingCallbackDriver,
      unregisterPendingCall: _unregisterPendingCallbackDriver,
    );
  }

  void releaseClientDriver(
      String sessionId, OpenToolCallbackDriver clientDriver) {
    if (identical(callbackOpenToolMap[sessionId], clientDriver)) {
      callbackOpenToolMap.remove(sessionId);
    }
    final sessionDrivers = _callbackDriversBySessionId[sessionId];
    sessionDrivers?.remove(clientDriver);
    if (sessionDrivers?.isEmpty ?? false) {
      _callbackDriversBySessionId.remove(sessionId);
    }

    final sessionIds = _callbackDriverSessionIds[clientDriver];
    sessionIds?.remove(sessionId);
    if (sessionIds?.isEmpty ?? false) {
      _callbackDriverSessionIds.remove(clientDriver);
    }
    _callbackDriversByFunctionCallId.removeWhere(
      (_, registeredDriver) => identical(registeredDriver, clientDriver),
    );
    clientDriver.setPendingCallHooks();
  }

  void clientDriverCallback(String sessionId, ot.ToolReturn toolReturn) {
    if (!_dispatchClientDriverCallback(sessionId, toolReturn)) {
      throw SessionAgentNotFoundException(sessionId: sessionId);
    }
  }

  void clientDriverStreamCallback(
      String sessionId, String event, ot.ToolReturn toolReturn) {
    if (!_dispatchClientDriverStreamCallback(sessionId, event, toolReturn)) {
      throw SessionAgentNotFoundException(sessionId: sessionId);
    }
  }

  void _registerPendingCallbackDriver(
      String functionCallId, OpenToolCallbackDriver clientDriver) {
    _callbackDriversByFunctionCallId[functionCallId] = clientDriver;
  }

  void _unregisterPendingCallbackDriver(
      String functionCallId, OpenToolCallbackDriver clientDriver) {
    final registeredDriver = _callbackDriversByFunctionCallId[functionCallId];
    if (registeredDriver == clientDriver) {
      _callbackDriversByFunctionCallId.remove(functionCallId);
    }
  }

  bool _dispatchClientDriverCallback(
      String sessionId, ot.ToolReturn toolReturn) {
    final OpenToolCallbackDriver? exactDriver =
        _callbackDriversByFunctionCallId[toolReturn.id];
    if (exactDriver != null && exactDriver.callback(toolReturn)) {
      return true;
    }

    final Set<OpenToolCallbackDriver>? sessionDrivers =
        _callbackDriversBySessionId[sessionId];
    if (sessionDrivers == null || sessionDrivers.isEmpty) {
      return false;
    }

    for (final driver in sessionDrivers.toList().reversed) {
      if (driver.callback(toolReturn)) {
        return true;
      }
    }
    return false;
  }

  bool _dispatchClientDriverStreamCallback(
      String sessionId, String event, ot.ToolReturn toolReturn) {
    final OpenToolCallbackDriver? exactDriver =
        _callbackDriversByFunctionCallId[toolReturn.id];
    if (exactDriver != null && exactDriver.streamCallback(event, toolReturn)) {
      return true;
    }

    final Set<OpenToolCallbackDriver>? sessionDrivers =
        _callbackDriversBySessionId[sessionId];
    if (sessionDrivers == null || sessionDrivers.isEmpty) {
      return false;
    }

    for (final driver in sessionDrivers.toList().reversed) {
      if (driver.streamCallback(event, toolReturn)) {
        return true;
      }
    }
    return false;
  }

  void _detachCallbackDriversForSession(String sessionId) {
    callbackOpenToolMap.remove(sessionId);
    final Set<OpenToolCallbackDriver>? sessionDrivers =
        _callbackDriversBySessionId.remove(sessionId);
    if (sessionDrivers == null || sessionDrivers.isEmpty) {
      return;
    }

    for (final driver in sessionDrivers) {
      final sessionIds = _callbackDriverSessionIds[driver];
      if (sessionIds == null) {
        continue;
      }
      sessionIds.remove(sessionId);
      if (sessionIds.isEmpty) {
        _callbackDriverSessionIds.remove(driver);
        _callbackDriversByFunctionCallId.removeWhere(
          (_, registeredDriver) => identical(registeredDriver, driver),
        );
      }
    }
  }

  List<String> getSubSessionIds(String rootSessionId) {
    try {
      SessionAgent? rootAgent = sessionAgents[rootSessionId];
      if (rootAgent == null) {
        return [];
      }

      Set<String> visitedSessionIds = {rootSessionId};
      return _getSubSessionIdsRecursive(rootAgent, visitedSessionIds);
    } catch (e) {
      return [];
    }
  }

  List<String> _getSubSessionIdsRecursive(
      SessionAgent agent, Set<String> visitedSessionIds) {
    List<String> allSubSessionIds = [];

    final (sessionAgentDriver, simpleAgentDriver) = _extractAgentDrivers(agent);

    if (sessionAgentDriver != null) {
      for (var namedSessionAgent in sessionAgentDriver.namedSessionAgents) {
        String subSessionId = namedSessionAgent.agent.sessionId;

        if (!visitedSessionIds.contains(subSessionId)) {
          allSubSessionIds.add(subSessionId);
          visitedSessionIds.add(subSessionId);

          allSubSessionIds.addAll(_getSubSessionIdsRecursive(
              namedSessionAgent.agent, visitedSessionIds));
        }
      }
    }

    if (simpleAgentDriver != null) {
      for (var namedSimpleAgent in simpleAgentDriver.namedSimpleAgents) {
        String subSessionId = namedSimpleAgent.agent.sessionId;

        if (!visitedSessionIds.contains(subSessionId)) {
          allSubSessionIds.add(subSessionId);
          visitedSessionIds.add(subSessionId);
        }
      }
    }

    return allSubSessionIds;
  }

  (SessionAgentDriver?, SimpleAgentDriver?) _extractAgentDrivers(
      SessionAgent rootAgent) {
    if (rootAgent is! MultiAgent) {
      return (null, null);
    }

    SessionAgentDriver? sessionAgentDriver;
    SimpleAgentDriver? simpleAgentDriver;

    for (var agentDriver in rootAgent.subAgentDriverList) {
      if (agentDriver is SessionAgentDriver && sessionAgentDriver == null) {
        sessionAgentDriver = agentDriver;
      } else if (agentDriver is SimpleAgentDriver &&
          simpleAgentDriver == null) {
        simpleAgentDriver = agentDriver;
      }
      if (sessionAgentDriver != null && simpleAgentDriver != null) break;
    }

    return (sessionAgentDriver, simpleAgentDriver);
  }

  String _mergeFullSystemPrompt(String systemPrompt, {List<String>? skills}) {
    String fullSystemPrompt = systemPrompt;
    final skillSystemPrompt = _buildSkillSystemPrompt(skills);
    if (skillSystemPrompt.isNotEmpty) {
      fullSystemPrompt =
          _buildEffectiveSystemPrompt(fullSystemPrompt, skillSystemPrompt);
    }

    for (PresetOpenSpecDto presetOpenSpec in _presetOpenSpecList) {
      fullSystemPrompt =
          fullSystemPrompt + "\n---" + presetOpenSpec.systemPrompt;
    }

    return fullSystemPrompt;
  }

  String _buildSkillSystemPrompt(List<String>? rawSkills) {
    if (rawSkills == null || rawSkills.isEmpty) return "";

    final skillBlocks = <String>[];
    for (final rawSkill in rawSkills) {
      final skill = _skillParser.parse(rawSkill);
      _skillValidator.validate(skill);
      final description = skill.manifest.description.trim();
      final instructions = skill.instructions.trim();
      skillBlocks.add(
        '[Skill: ${skill.manifest.name}]\n$description\n$instructions',
      );
    }

    return skillBlocks.join('\n\n');
  }

  void _updateSessionSystemPrompt(String sessionId, SessionAgent sessionAgent,
      String? newExtraSystemPrompt) {
    String baseSystemPrompt = _sessionBaseSystemPromptMap[sessionId] ??
        sessionAgent.systemPrompt ??
        "";
    String? extraSystemPrompt = _sessionExtraSystemPromptMap[sessionId];
    if (newExtraSystemPrompt != null) {
      String? normalizedExtra =
          newExtraSystemPrompt.isEmpty ? null : newExtraSystemPrompt;
      extraSystemPrompt = normalizedExtra;
      _sessionExtraSystemPromptMap[sessionId] = normalizedExtra;
    }
    String effectiveSystemPrompt =
        _buildEffectiveSystemPrompt(baseSystemPrompt, extraSystemPrompt);
    sessionAgent.systemPrompt = effectiveSystemPrompt;
    if (sessionAgent.agentSession.hasSystemMessage) {
      _replaceSystemMessageContent(
          sessionAgent.agentSession, effectiveSystemPrompt);
    }
  }

  String _buildEffectiveSystemPrompt(
      String baseSystemPrompt, String? extraSystemPrompt) {
    if (extraSystemPrompt == null || extraSystemPrompt.isEmpty)
      return baseSystemPrompt;
    if (baseSystemPrompt.isEmpty) return extraSystemPrompt;
    return baseSystemPrompt + "\n---\n" + extraSystemPrompt;
  }

  void _replaceSystemMessageContent(
      AgentSession agentSession, String effectiveSystemPrompt) {
    for (int i = 0; i < agentSession.taskDoneAgentMessageList.length; i++) {
      AgentMessage message = agentSession.taskDoneAgentMessageList[i];
      if (message.role == SessionRoleType.SYSTEM &&
          message.type == SessionMessageType.TEXT) {
        message.content = effectiveSystemPrompt;
        break;
      }
    }

    for (int i = 0; i < agentSession.listenAgentMessageList.length; i++) {
      AgentMessage message = agentSession.listenAgentMessageList[i];
      if (message.role == SessionRoleType.SYSTEM &&
          message.type == SessionMessageType.TEXT) {
        message.content = effectiveSystemPrompt;
        break;
      }
    }
  }
}
