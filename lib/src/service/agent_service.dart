import 'dart:async';
import 'package:liteagent_core/liteagent_core.dart';
import 'package:opentool_dart/opentool_client.dart' as ot;
import 'package:openapi_dart/openapi_dart.dart';
import 'package:openrpc_dart/openrpc_dart.dart';
import 'package:unique_id_dart/unique_id_dart.dart';
import 'dart:collection';
import 'session_message_manage_service.dart';
import 'dto.dart';
import 'exception.dart';

/// Read-only snapshot of one node in an AgentService runtime tree.
///
/// The root node has a null [parentSessionId] and [isInlineChild] is false.
/// The returned capability is a detached copy and can be safely modified by
/// callers without changing the service's runtime configuration.
class SessionAgentRuntimeInfo {
  final String sessionId;
  final String? parentSessionId;
  final String? name;
  final CapabilityDto capability;
  final bool isInlineChild;

  const SessionAgentRuntimeInfo({
    required this.sessionId,
    required this.parentSessionId,
    required this.name,
    required this.capability,
    required this.isInlineChild,
  });
}

class _RuntimeAgentNode {
  final String sessionId;
  final String? parentSessionId;
  final String? name;
  final CapabilityDto capability;
  final bool isInlineChild;
  final DateTime createTime;
  final String fullSystemPrompt;
  final LLMConfig? llmConfig;
  final SessionAgent agent;
  final List<_RuntimeAgentNode> children;

  _RuntimeAgentNode({
    required this.sessionId,
    required this.parentSessionId,
    required this.name,
    required this.capability,
    required this.isInlineChild,
    required this.createTime,
    required this.fullSystemPrompt,
    required this.llmConfig,
    required this.agent,
    required this.children,
  });
}

class _RuntimeAgentBuildContext {
  final List<_RuntimeAgentNode> nodes = [];
  final Set<String> reservedSessionIds = {};
}

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
  final Map<String, Set<OpenToolCallbackDriver>> _callbackDriversBySessionId = {};
  final Map<OpenToolCallbackDriver, Set<String>> _callbackDriverSessionIds = {};
  final Map<String, OpenToolCallbackDriver> _callbackDriversByFunctionCallId = {};

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

  /// Runtime ownership tree for root sessions and their inline children.
  final Map<String, String?> _parentSessionIdMap = {};
  final Map<String, Set<String>> _childrenSessionIdsMap = {};
  final Map<String, SessionAgentRuntimeInfo> _sessionRuntimeInfoMap = {};

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

  Future<AgentMessageDto> startSimple(String sessionId, UserTaskDto userTaskDto) async {
    SimpleAgent? simpleAgent = simpleAgents[sessionId];
    if (simpleAgent == null) throw SessionAgentNotFoundException(sessionId: sessionId);
    LLMConfig? llmConfig = userTaskDto.llmConfig?.toModel() ??
        _simpleSessionLlmConfigMap[sessionId] ??
        simpleAgent.llmConfig;
    if (llmConfig == null) {
      throw LLMConfigRequiredException(scene: "chat/simple", sessionId: sessionId);
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
    List<Content> userMessageList =
        userTaskDto.content.map((userMessageDto) => _convertToContent(userMessageDto)).toList();
    try {
      AgentMessage agentMessage =
          await simpleAgent.userToAgent(contentList: userMessageList, requestLLMConfig: llmConfig);
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
    if (_hasSession(sessionId)) {
      throw SessionAlreadyExistsException(sessionId: sessionId);
    }
    _validateCapabilityTree(capabilityDto);

    final buildContext = _RuntimeAgentBuildContext();
    buildContext.reservedSessionIds.add(sessionId);
    try {
      final rootNode = await _buildRuntimeAgent(
        capabilityDto,
        sessionId: sessionId,
        parentSessionId: null,
        name: null,
        isInlineChild: false,
        restoreState: restoreState,
        customToolDriverList: customToolDriverList,
        buildContext: buildContext,
      );
      _commitRuntimeTree(rootNode, agentId: agentId);
      return SessionDto(sessionId: sessionId);
    } catch (_) {
      _disposeBuiltAgents(buildContext.nodes);
      rethrow;
    }
  }

  Future<void> startSession(String sessionId, UserTaskDto userTaskDto,
      void Function(String sessionId, String taskId, AgentMessageDto agentMessageDto) listen,
      {void Function(String sessionId, String taskId, AgentMessageChunkDto agentMessageChunkDto)?
          listenChunk,
      void Function(String taskId)? getTaskId}) async {
    SessionAgent? sessionAgent = sessionAgents[sessionId];
    if (sessionAgent == null) throw SessionAgentNotFoundException(sessionId: sessionId);
    LLMConfig? llmConfig = userTaskDto.llmConfig?.toModel() ?? _sessionLlmConfigMap[sessionId];
    if (llmConfig == null) {
      throw LLMConfigRequiredException(scene: "chat", sessionId: sessionId);
    }
    _updateSessionSystemPrompt(sessionId, sessionAgent, userTaskDto.extraSystemPrompt);
    List<Content> userMessageList =
        userTaskDto.content.map((contentDto) => _convertToContent(contentDto)).toList();

    void Function(String taskId) fetchTaskId = (String taskId) {
      if (getTaskId != null) getTaskId(taskId);
      if (sessionAgent is MultiAgent) {
        List<String> subSessionIds = getSubSessionIds(sessionId);
        if (subSessionIds.isNotEmpty) {
          _updateSession(sessionAgent.agentSession, taskId, listen,
              listenChunk: listenChunk, subAgentSessionList: subSessionIds);
        } else {
          _updateSession(sessionAgent.agentSession, taskId, listen, listenChunk: listenChunk);
        }
      } else {
        _updateSession(sessionAgent.agentSession, taskId, listen, listenChunk: listenChunk);
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
    return sessionAgent.agentSession.listenAgentMessageList.map((AgentMessage agentMessage) {
      AgentMessageDto agentMessageDto = AgentMessageDto.fromModel(agentMessage);
      return agentMessageDto;
    }).toList();
  }

  Future<void> stopSession(SessionTaskDto sessionTaskDto) async {
    SessionAgent? sessionAgent = sessionAgents[sessionTaskDto.sessionId];
    if (sessionAgent == null)
      throw SessionAgentNotFoundException(sessionId: sessionTaskDto.sessionId);
    sessionAgent.stop(taskId: sessionTaskDto.taskId);
    _stopOwnedInlineTasks(
      sessionTaskDto.sessionId,
      sessionTaskDto.taskId,
    );
  }

  void _stopOwnedInlineTasks(String sessionId, String? taskId) {
    for (final childSessionId in getSubSessionIds(sessionId)) {
      final SessionAgent? childAgent = sessionAgents[childSessionId];
      if (childAgent == null) continue;
      for (final childTaskId in childAgent.dispatcherMap.activeTaskIds()) {
        final TaskExecutionState? taskState = childAgent.getTaskExecutionState(childTaskId);
        if (taskId == null || taskState == null || taskState.originalTaskId == taskId) {
          childAgent.stop(taskId: childTaskId);
        }
      }
    }
  }

  Future<void> clearSession(String sessionId) async {
    final List<String> sessionIdsToClear = _collectSessionIdsForClear(sessionId);
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

    List<AgentMessage> messageList = sessionAgent.agentSession.listenAgentMessageList;
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
          return textContent.length > 50 ? textContent.substring(0, 50) : textContent;
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

  /// Returns the requested session and every inline descendant in depth-first
  /// order. An unknown or already-cleared session returns an empty list.
  List<SessionAgentRuntimeInfo> getSessionTree(String rootSessionId) {
    if (!_sessionRuntimeInfoMap.containsKey(rootSessionId)) {
      return [];
    }

    final List<SessionAgentRuntimeInfo> result = <SessionAgentRuntimeInfo>[];
    final Set<String> visitedSessionIds = <String>{};

    void visit(String sessionId) {
      if (!visitedSessionIds.add(sessionId)) return;
      final SessionAgentRuntimeInfo? info = _sessionRuntimeInfoMap[sessionId];
      if (info == null) return;
      result.add(_copyRuntimeInfo(info));
      for (final childSessionId in _childrenSessionIdsMap[sessionId] ?? const <String>{}) {
        visit(childSessionId);
      }
    }

    visit(rootSessionId);
    return result;
  }

  SessionAgentRuntimeInfo _copyRuntimeInfo(SessionAgentRuntimeInfo info) {
    return SessionAgentRuntimeInfo(
      sessionId: info.sessionId,
      parentSessionId: info.parentSessionId,
      name: info.name,
      capability: _cloneCapability(info.capability),
      isInlineChild: info.isInlineChild,
    );
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

  bool _hasSession(String sessionId) {
    return sessionAgents.containsKey(sessionId) ||
        simpleAgents.containsKey(sessionId) ||
        _sessionRuntimeInfoMap.containsKey(sessionId);
  }

  void _validateCapabilityTree(CapabilityDto rootCapability) {
    final RegExp namePattern = RegExp(r'^[a-zA-Z0-9_-]{1,64}$');
    final Set<CapabilityDto> visiting = <CapabilityDto>{};

    void visit(CapabilityDto capability, String path) {
      if (!visiting.add(capability)) {
        throw FormatException('Cyclic inline subAgentList at `$path`.');
      }

      final subAgentList = capability.subAgentList ?? const <AgentDto>[];
      if (capability.auto == true && subAgentList.isNotEmpty) {
        throw FormatException(
          'AutoMultiAgent does not support inline subAgentList at `$path`.',
        );
      }

      final Set<String> names = <String>{};
      for (int index = 0; index < subAgentList.length; index++) {
        final AgentDto subAgent = subAgentList[index];
        final String childPath = '$path.subAgentList[$index]';
        if (!namePattern.hasMatch(subAgent.name)) {
          throw FormatException(
            'Invalid inline sub-agent name `${subAgent.name}` at `$childPath`. '
            'Names must match ^[a-zA-Z0-9_-]{1,64}\$.',
          );
        }
        if (!names.add(subAgent.name)) {
          throw FormatException(
            'Duplicate inline sub-agent name `${subAgent.name}` at `$path`.',
          );
        }
        visit(subAgent.capability, childPath);
      }

      visiting.remove(capability);
    }

    visit(rootCapability, 'root');
  }

  String _allocateRuntimeSessionId(_RuntimeAgentBuildContext buildContext) {
    String sessionId;
    do {
      sessionId = uniqueId();
    } while (_hasSession(sessionId) || buildContext.reservedSessionIds.contains(sessionId));
    buildContext.reservedSessionIds.add(sessionId);
    return sessionId;
  }

  Future<_RuntimeAgentNode> _buildRuntimeAgent(
    CapabilityDto capability, {
    required String sessionId,
    required String? parentSessionId,
    required String? name,
    required bool isInlineChild,
    required SessionRestoreState? restoreState,
    required List<ToolDriver>? customToolDriverList,
    required _RuntimeAgentBuildContext buildContext,
  }) async {
    final DateTime createTime = DateTime.now();
    final String fullSystemPrompt = _mergeFullSystemPrompt(
      capability.systemPrompt,
      skills: capability.skills,
    );
    final LLMConfig? llmConfig = capability.llmConfig?.toModel();
    final int? resolvedToolReturnPackMinLength = capability.toolReturnPackMinLength == null
        ? 800
        : (capability.toolReturnPackMinLength! <= 0 ? null : capability.toolReturnPackMinLength);
    final ToolExecutionLimits toolExecutionLimits = ToolExecutionLimits(
      maxLlmRequests: capability.maxLlmRequests ?? 64,
      maxToolRounds: capability.maxToolRounds ?? 16,
      maxToolCalls: capability.maxToolCalls ?? 64,
      maxConsecutiveIdenticalToolRounds: capability.maxConsecutiveIdenticalToolRounds ?? 3,
      maxTaskDurationSeconds: capability.maxTaskDurationSeconds ?? 300,
    );
    final List<ToolDriver> toolDriverList = <ToolDriver>[];
    toolDriverList.addAll(globalDriverList);
    final List<OpenSpecDto> presetOpenSpecList = _presetOpenSpecList
        .where((presetOpenSpec) => presetOpenSpec.openSpec != null)
        .map((presetOpenSpec) => presetOpenSpec.openSpec!)
        .toList();
    toolDriverList.addAll(await _buildToolDriverList(presetOpenSpecList));
    toolDriverList.addAll(await _buildToolDriverList(capability.openSpecList));
    if (customToolDriverList != null) {
      toolDriverList.addAll(customToolDriverList);
    }

    final List<_RuntimeAgentNode> children = <_RuntimeAgentNode>[];
    final List<AgentDto> subAgentList = capability.subAgentList ?? const <AgentDto>[];
    for (final AgentDto subAgent in subAgentList) {
      final String childSessionId = _allocateRuntimeSessionId(buildContext);
      final _RuntimeAgentNode child = await _buildRuntimeAgent(
        subAgent.capability,
        sessionId: childSessionId,
        parentSessionId: sessionId,
        name: subAgent.name,
        isInlineChild: true,
        restoreState: null,
        customToolDriverList: null,
        buildContext: buildContext,
      );
      children.add(child);
    }

    List<AgentDriver>? subAgentDriverList;
    if (children.isNotEmpty) {
      final List<NamedSessionAgent> namedSessionAgents = children
          .map(
            (child) => NamedSessionAgent(
              name: child.name!,
              description: _buildInlineAgentDescription(
                child.capability.systemPrompt,
              ),
              agent: child.agent,
            ),
          )
          .toList();
      subAgentDriverList = <AgentDriver>[
        SessionAgentDriver(namedSessionAgents: namedSessionAgents),
      ];
    }

    final AgentSession agentSession = _buildSession(
      sessionId,
      restoreState: restoreState,
    );
    final SessionAgent agent = await _createRuntimeAgent(
      capability: capability,
      sessionId: sessionId,
      llmConfig: llmConfig,
      agentSession: agentSession,
      fullSystemPrompt: fullSystemPrompt,
      toolDriverList: toolDriverList,
      subAgentDriverList: subAgentDriverList,
      resolvedToolReturnPackMinLength: resolvedToolReturnPackMinLength,
      toolExecutionLimits: toolExecutionLimits,
    );

    final _RuntimeAgentNode node = _RuntimeAgentNode(
      sessionId: sessionId,
      parentSessionId: parentSessionId,
      name: name,
      capability: capability,
      isInlineChild: isInlineChild,
      createTime: createTime,
      fullSystemPrompt: fullSystemPrompt,
      llmConfig: llmConfig,
      agent: agent,
      children: children,
    );
    buildContext.nodes.add(node);
    return node;
  }

  Future<SessionAgent> _createRuntimeAgent({
    required CapabilityDto capability,
    required String sessionId,
    required LLMConfig? llmConfig,
    required AgentSession agentSession,
    required String fullSystemPrompt,
    required List<ToolDriver> toolDriverList,
    required List<AgentDriver>? subAgentDriverList,
    required int? resolvedToolReturnPackMinLength,
    required ToolExecutionLimits toolExecutionLimits,
  }) async {
    final CallbackOpenTool? clientOpenTool = _buildCallbackOpenTool(
      capability.callbackOpenTool,
    );

    if (capability.auto == true) {
      final List<LLMConfig>? llmConfigList =
          capability.llmConfigList?.map((llmConfigDto) => llmConfigDto.toModel()).toList();
      return AutoMultiAgent.create(
        sessionId: sessionId,
        llmConfig: llmConfig,
        agentSession: agentSession,
        toolDriverList: toolDriverList,
        clientOpenTool: clientOpenTool,
        systemPrompt: fullSystemPrompt,
        timeoutSeconds: capability.timeoutSeconds,
        taskPipelineStrategy: capability.taskPipelineStrategy,
        toolPipelineStrategy: capability.toolPipelineStrategy ?? PipelineStrategyType.PARALLEL,
        enableThinking: capability.enableThinking,
        llmConfigList: llmConfigList,
        toolReturnPackMinLength: resolvedToolReturnPackMinLength,
        executionLimits: toolExecutionLimits,
      );
    }

    if (subAgentDriverList != null) {
      return MultiAgent(
        sessionId: sessionId,
        llmConfig: llmConfig,
        agentSession: agentSession,
        toolDriverList: toolDriverList,
        subAgentDriverList: subAgentDriverList,
        clientOpenTool: clientOpenTool,
        systemPrompt: fullSystemPrompt,
        timeoutSeconds: capability.timeoutSeconds,
        taskPipelineStrategy: capability.taskPipelineStrategy,
        toolPipelineStrategy: capability.toolPipelineStrategy ?? PipelineStrategyType.PARALLEL,
        enableThinking: capability.enableThinking,
        toolReturnPackMinLength: resolvedToolReturnPackMinLength,
        executionLimits: toolExecutionLimits,
      );
    }

    if (toolDriverList.isEmpty && capability.callbackOpenTool == null) {
      return TextAgent(
        sessionId: sessionId,
        llmConfig: llmConfig,
        agentSession: agentSession,
        systemPrompt: fullSystemPrompt,
        timeoutSeconds: capability.timeoutSeconds,
        taskPipelineStrategy: capability.taskPipelineStrategy,
        enableThinking: capability.enableThinking,
      );
    }

    return ToolAgent(
      sessionId: sessionId,
      llmConfig: llmConfig,
      agentSession: agentSession,
      toolDriverList: toolDriverList,
      callbackOpenTool: clientOpenTool,
      systemPrompt: fullSystemPrompt,
      timeoutSeconds: capability.timeoutSeconds,
      taskPipelineStrategy: capability.taskPipelineStrategy,
      toolPipelineStrategy: capability.toolPipelineStrategy ?? PipelineStrategyType.PARALLEL,
      enableThinking: capability.enableThinking,
      toolReturnPackMinLength: resolvedToolReturnPackMinLength,
      executionLimits: toolExecutionLimits,
    );
  }

  CallbackOpenTool? _buildCallbackOpenTool(CallbackOpenToolDto? dto) {
    if (dto == null) return null;
    return CallbackOpenTool(
      opentool: dto.opentool,
      timeout: dto.timeout,
      fetchClientDriver: fetchClientDriver,
      releaseClientDriver: releaseClientDriver,
    );
  }

  String _buildInlineAgentDescription(String systemPrompt) {
    return systemPrompt.length <= 1024 ? systemPrompt : systemPrompt.substring(0, 1024);
  }

  List<_RuntimeAgentNode> _flattenRuntimeTree(_RuntimeAgentNode root) {
    final List<_RuntimeAgentNode> nodes = <_RuntimeAgentNode>[];
    final Set<String> visited = <String>{};

    void visit(_RuntimeAgentNode node) {
      if (!visited.add(node.sessionId)) return;
      nodes.add(node);
      for (final child in node.children) {
        visit(child);
      }
    }

    visit(root);
    return nodes;
  }

  void _commitRuntimeTree(_RuntimeAgentNode root, {String? agentId}) {
    final List<_RuntimeAgentNode> nodes = _flattenRuntimeTree(root);
    final Set<String> seenSessionIds = <String>{};
    for (final node in nodes) {
      if (!seenSessionIds.add(node.sessionId) || _hasSession(node.sessionId)) {
        throw SessionAlreadyExistsException(sessionId: node.sessionId);
      }
    }

    final List<String> committedSessionIds = <String>[];
    try {
      for (final node in nodes) {
        sessionAgents[node.sessionId] = node.agent;
        sessionCreateTimeMap[node.sessionId] = node.createTime;
        _sessionBaseSystemPromptMap[node.sessionId] = node.fullSystemPrompt;
        _sessionExtraSystemPromptMap[node.sessionId] = null;
        _sessionLlmConfigMap[node.sessionId] = node.llmConfig;
        _parentSessionIdMap[node.sessionId] = node.parentSessionId;
        _childrenSessionIdsMap.putIfAbsent(
          node.sessionId,
          () => <String>{},
        );
        if (node.parentSessionId != null) {
          _childrenSessionIdsMap
              .putIfAbsent(node.parentSessionId!, () => <String>{})
              .add(node.sessionId);
        }
        _sessionRuntimeInfoMap[node.sessionId] = SessionAgentRuntimeInfo(
          sessionId: node.sessionId,
          parentSessionId: node.parentSessionId,
          name: node.name,
          capability: _cloneCapability(node.capability),
          isInlineChild: node.isInlineChild,
        );
        committedSessionIds.add(node.sessionId);
      }

      if (agentId != null) {
        sessionAgentMap[root.sessionId] = agentId;
        agentSessionsMap.putIfAbsent(agentId, () => <String>{}).add(root.sessionId);
      }

      for (final node in nodes) {
        _attachIdleTimeoutHandler(node.agent);
      }
    } catch (_) {
      _rollbackCommittedRuntimeEntries(committedSessionIds, agentId);
      rethrow;
    }
  }

  void _rollbackCommittedRuntimeEntries(
    List<String> sessionIds,
    String? agentId,
  ) {
    if (agentId != null) {
      agentSessionsMap[agentId]?.removeWhere(sessionIds.contains);
      if (agentSessionsMap[agentId]?.isEmpty ?? false) {
        agentSessionsMap.remove(agentId);
      }
      sessionAgentMap.removeWhere(
        (sessionId, mappedAgentId) => mappedAgentId == agentId && sessionIds.contains(sessionId),
      );
    }
    for (final sessionId in sessionIds.reversed) {
      _removeRuntimeMapsOnly(sessionId);
    }
  }

  CapabilityDto _cloneCapability(CapabilityDto capability) {
    return CapabilityDto.fromJson(
      Map<String, dynamic>.from(capability.toJson()),
    );
  }

  void _disposeBuiltAgents(List<_RuntimeAgentNode> nodes) {
    final Set<SessionAgent> disposedAgents = <SessionAgent>{};
    for (final node in nodes) {
      if (disposedAgents.add(node.agent)) {
        node.agent.clear();
      }
    }
  }

  void _attachIdleTimeoutHandler(SessionAgent sessionAgent) {
    sessionAgent.onIdleTimeout = (String id) {
      final String? rootSessionId = _findRuntimeRootSessionId(id);
      if (rootSessionId == null) return;
      unawaited(clearSession(rootSessionId));
    };
  }

  String? _findRuntimeRootSessionId(String sessionId) {
    if (!_sessionRuntimeInfoMap.containsKey(sessionId)) return null;

    String currentSessionId = sessionId;
    final Set<String> visitedSessionIds = <String>{};
    while (visitedSessionIds.add(currentSessionId)) {
      final String? parentSessionId = _parentSessionIdMap[currentSessionId];
      if (parentSessionId == null) return currentSessionId;
      if (!_sessionRuntimeInfoMap.containsKey(parentSessionId)) return null;
      currentSessionId = parentSessionId;
    }
    return null;
  }

  List<String> _collectSessionIdsForClear(String sessionId) {
    final String? runtimeRootSessionId = _findRuntimeRootSessionId(sessionId);
    final String rootSessionId = runtimeRootSessionId ?? sessionId;
    final List<String> sessionIds = <String>[];
    final Set<String> visitedSessionIds = <String>{};

    void visit(String currentSessionId) {
      if (!visitedSessionIds.add(currentSessionId)) return;
      for (final childSessionId in _childrenSessionIdsMap[currentSessionId] ?? const <String>{}) {
        visit(childSessionId);
      }
      if (_hasSession(currentSessionId)) {
        sessionIds.add(currentSessionId);
      }
    }

    if (_sessionRuntimeInfoMap.containsKey(rootSessionId)) {
      visit(rootSessionId);
    } else if (simpleAgents.containsKey(rootSessionId) ||
        sessionAgents.containsKey(rootSessionId)) {
      sessionIds.add(rootSessionId);
    }
    return sessionIds;
  }

  void _clearSessionEntry(String sessionId) {
    SessionAgent? sessionAgent = sessionAgents.remove(sessionId);
    sessionAgent?.clear();
    simpleAgents.remove(sessionId);
    _removeRuntimeMapsOnly(sessionId);
  }

  void _removeRuntimeMapsOnly(String sessionId) {
    sessionAgents.remove(sessionId);
    simpleAgents.remove(sessionId);
    _detachCallbackDriversForSession(sessionId);
    _sessionBaseSystemPromptMap.remove(sessionId);
    _sessionExtraSystemPromptMap.remove(sessionId);
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
    _sessionRuntimeInfoMap.remove(sessionId);

    final String? parentSessionId = _parentSessionIdMap.remove(sessionId);
    if (parentSessionId != null) {
      final Set<String>? siblingSessionIds = _childrenSessionIdsMap[parentSessionId];
      siblingSessionIds?.remove(sessionId);
      if (siblingSessionIds?.isEmpty ?? false) {
        _childrenSessionIdsMap.remove(parentSessionId);
      }
    }
    _childrenSessionIdsMap.remove(sessionId);
  }

  void _updateSession(AgentSession agentSession, String taskId,
      void Function(String sessionId, String taskId, AgentMessageDto agentMessageDto) listen,
      {void Function(String sessionId, String taskId, AgentMessageChunkDto agentMessageChunkDto)?
          listenChunk,
      List<String>? subAgentSessionList}) {
    agentSession.addAgentMessageListener((AgentMessage agentMessage) {
      AgentMessageDto agentMessageDto = AgentMessageDto.fromModel(agentMessage);
      if ((agentMessage.originalTaskId == taskId || agentMessage.originalTaskId.isEmpty) &&
          !_isSentMessage(agentMessage, agentSession.sessionId)) {
        _recordAgentMessage(agentSession.sessionId, taskId, agentMessageDto);
        listen(agentSession.sessionId, taskId, agentMessageDto);
        _addToSentMessages(agentMessage, agentSession.sessionId);
      }
    });
    if (listenChunk != null) {
      agentSession.addAgentMessageChunkListener((AgentMessageChunk agentMessageChunk) {
        if ((agentMessageChunk.originalTaskId == taskId ||
                agentMessageChunk.originalTaskId.isEmpty) &&
            !_isSentMessage(agentMessageChunk, agentSession.sessionId)) {
          listenChunk(
              agentSession.sessionId, taskId, AgentMessageChunkDto.fromModel(agentMessageChunk));
          _addToSentMessages(agentMessageChunk, agentSession.sessionId);
        }
      });
    }

    if (subAgentSessionList != null && subAgentSessionList.isNotEmpty) {
      subAgentSessionList.forEach((subSessionId) {
        SessionAgent? subSessionAgent = sessionAgents[subSessionId];
        if (subSessionAgent != null) {
          subSessionAgent.agentSession.addAgentMessageListener((AgentMessage agentMessage) {
            if ((agentMessage.originalTaskId == taskId || agentMessage.originalTaskId.isEmpty) &&
                !_isSentMessage(agentMessage, subSessionId)) {
              AgentMessageDto agentMessageDto = AgentMessageDto.fromModel(agentMessage);
              _recordAgentMessage(subSessionId, taskId, agentMessageDto);
              listen(subSessionId, taskId, agentMessageDto);
              _addToSentMessages(agentMessage, subSessionId);
            }
          });
          if (listenChunk != null) {
            subSessionAgent.agentSession
                .addAgentMessageChunkListener((AgentMessageChunk agentMessageChunk) {
              if ((agentMessageChunk.originalTaskId == taskId ||
                      agentMessageChunk.originalTaskId.isEmpty) &&
                  !_isSentMessage(agentMessageChunk, subSessionId)) {
                listenChunk(
                    subSessionId, taskId, AgentMessageChunkDto.fromModel(agentMessageChunk));
                _addToSentMessages(agentMessageChunk, subSessionId);
              }
            });
          }
        }
      });
    }
  }

  Future<List<ToolDriver>> _buildToolDriverList(List<OpenSpecDto>? openSpecDtoList) async {
    if (openSpecDtoList == null) return [];
    List<ToolDriver> toolDriverList = [];
    for (OpenSpecDto openSpecDto in openSpecDtoList) {
      if (openSpecDto.protocol == Protocol.OPENAPI) {
        OpenAPI openAPI = await OpenAPILoader().load(openSpecDto.openSpec);
        String? authorization;
        if (openSpecDto.apiKey != null) {
          authorization =
              convertToAuthorization(openSpecDto.apiKey!.type, openSpecDto.apiKey!.apiKey);
        }
        ToolDriver openAPIDriver = OpenAPIDriver(openAPI, authorization: authorization);
        toolDriverList.add(openAPIDriver);
      } else if (openSpecDto.protocol == Protocol.JSONRPCHTTP) {
        OpenRPC openRPC = await OpenRPCLoader().load(openSpecDto.openSpec);
        ToolDriver jsonrpcHttpDriver = JsonRPCDriver(openRPC);
        toolDriverList.add(jsonrpcHttpDriver);
      } else if (openSpecDto.protocol == Protocol.MCP_STDIO) {
        McpStdioDriver mcpStdioDriver = McpStdioDriver.fromMcpStdioString(openSpecDto.openSpec);
        toolDriverList.add(mcpStdioDriver);
      } else if (openSpecDto.protocol == Protocol.MCP_HTTP) {
        McpHttpDriver mcpHttpDriver = McpHttpDriver.fromMcpHttpString(openSpecDto.openSpec);
        toolDriverList.add(mcpHttpDriver);
      } else if (openSpecDto.protocol == Protocol.OPENTOOL) {
        ot.OpenTool opentool = await ot.OpenToolJsonLoader().load(openSpecDto.openSpec);
        if (opentool.server == null && openSpecDto.serverUrl != null) {
          opentool.server = ot.ServerConfig(url: openSpecDto.serverUrl!, description: "");
        }
        String? apiKey;
        if (openSpecDto.apiKey != null) {
          apiKey = convertToAuthorization(openSpecDto.apiKey!.type, openSpecDto.apiKey!.apiKey);
        }
        OpenToolDriver? opentoolDriver = OpenToolClientDriver(opentool, apiKey: apiKey);
        toolDriverList.add(opentoolDriver);
      }
    }

    return toolDriverList;
  }

  void _recordAgentMessage(String sessionId, String taskId, AgentMessageDto agentMessageDto) {
    SessionAgentMessageDto sessionAgentMessageDto =
        SessionAgentMessageDto(sessionId: sessionId, agentMessageDto: agentMessageDto);
    agentMessageManageServiceList.forEach((service) {
      service.addMessage(sessionAgentMessageDto);
    });
  }

  bool _isSentMessage(Message message, String toSessionId) {
    return sentMessages.containsKey(message) && sentMessages[message]![toSessionId] == true;
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

  void fetchClientDriver(String sessionId, OpenToolCallbackDriver clientDriver) {
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

  void releaseClientDriver(String sessionId, OpenToolCallbackDriver clientDriver) {
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

  void clientDriverStreamCallback(String sessionId, String event, ot.ToolReturn toolReturn) {
    if (!_dispatchClientDriverStreamCallback(sessionId, event, toolReturn)) {
      throw SessionAgentNotFoundException(sessionId: sessionId);
    }
  }

  void _registerPendingCallbackDriver(String functionCallId, OpenToolCallbackDriver clientDriver) {
    _callbackDriversByFunctionCallId[functionCallId] = clientDriver;
  }

  void _unregisterPendingCallbackDriver(
      String functionCallId, OpenToolCallbackDriver clientDriver) {
    final registeredDriver = _callbackDriversByFunctionCallId[functionCallId];
    if (registeredDriver == clientDriver) {
      _callbackDriversByFunctionCallId.remove(functionCallId);
    }
  }

  bool _dispatchClientDriverCallback(String sessionId, ot.ToolReturn toolReturn) {
    final OpenToolCallbackDriver? exactDriver = _callbackDriversByFunctionCallId[toolReturn.id];
    if (exactDriver != null && exactDriver.callback(toolReturn)) {
      return true;
    }

    final Set<OpenToolCallbackDriver>? sessionDrivers = _callbackDriversBySessionId[sessionId];
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
    final OpenToolCallbackDriver? exactDriver = _callbackDriversByFunctionCallId[toolReturn.id];
    if (exactDriver != null && exactDriver.streamCallback(event, toolReturn)) {
      return true;
    }

    final Set<OpenToolCallbackDriver>? sessionDrivers = _callbackDriversBySessionId[sessionId];
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
    if (!_sessionRuntimeInfoMap.containsKey(rootSessionId)) return [];

    final List<String> result = <String>[];
    final Set<String> visitedSessionIds = <String>{rootSessionId};

    void visit(String sessionId) {
      for (final childSessionId in _childrenSessionIdsMap[sessionId] ?? const <String>{}) {
        if (!visitedSessionIds.add(childSessionId)) continue;
        result.add(childSessionId);
        visit(childSessionId);
      }
    }

    visit(rootSessionId);
    return result;
  }

  String _mergeFullSystemPrompt(String systemPrompt, {List<String>? skills}) {
    String fullSystemPrompt = systemPrompt;
    final skillSystemPrompt = _buildSkillSystemPrompt(skills);
    if (skillSystemPrompt.isNotEmpty) {
      fullSystemPrompt = _buildEffectiveSystemPrompt(fullSystemPrompt, skillSystemPrompt);
    }

    for (PresetOpenSpecDto presetOpenSpec in _presetOpenSpecList) {
      fullSystemPrompt = fullSystemPrompt + "\n---" + presetOpenSpec.systemPrompt;
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

  void _updateSessionSystemPrompt(
      String sessionId, SessionAgent sessionAgent, String? newExtraSystemPrompt) {
    String baseSystemPrompt =
        _sessionBaseSystemPromptMap[sessionId] ?? sessionAgent.systemPrompt ?? "";
    String? extraSystemPrompt = _sessionExtraSystemPromptMap[sessionId];
    if (newExtraSystemPrompt != null) {
      String? normalizedExtra = newExtraSystemPrompt.isEmpty ? null : newExtraSystemPrompt;
      extraSystemPrompt = normalizedExtra;
      _sessionExtraSystemPromptMap[sessionId] = normalizedExtra;
    }
    String effectiveSystemPrompt = _buildEffectiveSystemPrompt(baseSystemPrompt, extraSystemPrompt);
    sessionAgent.systemPrompt = effectiveSystemPrompt;
    if (sessionAgent.agentSession.hasSystemMessage) {
      _replaceSystemMessageContent(sessionAgent.agentSession, effectiveSystemPrompt);
    }
  }

  String _buildEffectiveSystemPrompt(String baseSystemPrompt, String? extraSystemPrompt) {
    if (extraSystemPrompt == null || extraSystemPrompt.isEmpty) return baseSystemPrompt;
    if (baseSystemPrompt.isEmpty) return extraSystemPrompt;
    return baseSystemPrompt + "\n---\n" + extraSystemPrompt;
  }

  void _replaceSystemMessageContent(AgentSession agentSession, String effectiveSystemPrompt) {
    for (int i = 0; i < agentSession.taskDoneAgentMessageList.length; i++) {
      AgentMessage message = agentSession.taskDoneAgentMessageList[i];
      if (message.role == SessionRoleType.SYSTEM && message.type == SessionMessageType.TEXT) {
        message.content = effectiveSystemPrompt;
        break;
      }
    }

    for (int i = 0; i < agentSession.listenAgentMessageList.length; i++) {
      AgentMessage message = agentSession.listenAgentMessageList[i];
      if (message.role == SessionRoleType.SYSTEM && message.type == SessionMessageType.TEXT) {
        message.content = effectiveSystemPrompt;
        break;
      }
    }
  }
}
