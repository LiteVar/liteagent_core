import 'dart:async';
import 'package:liteagent_core_dart/liteagent_core.dart';
import 'package:opentool_daemon/opentool_daemon_utils.dart';
import 'package:opentool_dart/opentool_client.dart' as ot;
import 'package:openapi_dart/openapi_dart.dart';
import 'package:openrpc_dart/openrpc_dart.dart';
import 'dart:collection';
import 'session_message_manage_service.dart';
import 'dto.dart';
import 'exception.dart';

class AgentService {
  static const int _SENT_MESSAGES_CAPACITY = 500;

  Map<String, SessionAgent> sessionAgents = {}; /// Map<sessionId, SessionAgent>
  Map<String, SimpleAgent> simpleAgents = {}; /// Map<sessionId, SimpleAgent>
  List<ToolDriver> globalDriverList = [];
  Map<String, OpenToolDriver> opentoolDriverMap = {}; /// Map<sessionId, OpenToolDriver>
  Map<String, OpenToolCallbackDriver> clientDriverMap= {}; /// Map<sessionId, ClientDriver>
  List<SessionMessageManageService> agentMessageManageServiceList = [];
  LinkedHashMap<Message, Map<String, bool>> sentMessages = LinkedHashMap<Message, Map<String, bool>>(); /// Map<Message, Map<sessionId, bool>>

  AgentService({List<ToolDriver> globalToolDriverList = const [], List<SessionMessageManageService> messageManageServiceList = const []}) {
    globalDriverList.addAll(globalToolDriverList);
    agentMessageManageServiceList.addAll(messageManageServiceList);
  }

  Future<bool> testLLMConfig(String baseUrl, String apiKey) async {
    return OpenAIUtil.checkLLMConfig(baseUrl, apiKey);
  }

  Future<SessionDto> initSimple(SimpleCapabilityDto simpleCapabilityDto) async {
    String sessionId = uniqueId();
    String systemPrompt = simpleCapabilityDto.systemPrompt;
    LLMConfig llmConfig = simpleCapabilityDto.llmConfig.toModel();

    SimpleAgent simpleAgent = SimpleAgent(
        llmConfig: llmConfig,
        systemPrompt: systemPrompt,
        responseFormat: ResponseFormat(type: ResponseFormatType.TEXT)
    );

    simpleAgents[sessionId] = simpleAgent;

    SessionDto sessionDto = SessionDto(sessionId: sessionId);
    return sessionDto;
  }

  Future<AgentMessageDto> startSimple(String sessionId, UserTaskDto userTaskDto) async {
    SimpleAgent? simpleAgent = simpleAgents[sessionId];
    if(simpleAgent == null) throw SessionAgentNotFoundException(sessionId: sessionId);
    List<Content> userMessageList = userTaskDto.content
        .map((userMessageDto) => _convertToContent(userMessageDto))
        .toList();
    AgentMessage agentMessage = await simpleAgent.userToAgent(contentList: userMessageList);
    return AgentMessageDto.fromModel(agentMessage);
  }

  Future<SessionDto> initSession(CapabilityDto capabilityDto, {Map<String, OpenToolDriver>? opentoolDriverMap, List<ToolDriver>? customToolDriverList}) async {
    String sessionId = uniqueId();
    String systemPrompt = capabilityDto.systemPrompt;
    LLMConfig llmConfig = capabilityDto.llmConfig.toModel();
    List<ReflectPrompt>? reflectPromptList = capabilityDto.reflectPromptList?.map((reflectPromptDto) => ReflectPrompt(llmConfig: reflectPromptDto.llmConfig.toModel(), prompt: reflectPromptDto.prompt)).toList();

    if(opentoolDriverMap != null) opentoolDriverMap.forEach((key, value) { this.opentoolDriverMap[key] = value;});
    // if(capabilityDto.clientOpenTool != null && listenClientFunctionCall != null) {
    //   OpenTool clientOpenTool = await OpenToolLoader().load(capabilityDto.clientOpenTool!.opentool);
    //
    //   clientDriverMap[sessionId] = ClientDriver(listenFunctionCall, timeout: capabilityDto.clientOpenTool?.timeout??60).bind(clientOpenTool) as ClientDriver;
    // }

    List<ToolDriver> toolDriverList = [];
    toolDriverList.addAll(globalDriverList);
    toolDriverList.addAll(await _buildToolDriverList(capabilityDto.openSpecList));
    if(customToolDriverList != null) toolDriverList.addAll(customToolDriverList);

    List<AgentDriver>? agentDriverList = await _buildAgentDriverList(capabilityDto.sessionList, sessionId);

    if (capabilityDto.auto == true) { // AutoAgent
      List<LLMConfig>? llmConfigList = capabilityDto.llmConfigList?.map((llmConfigDto) => llmConfigDto.toModel()).toList();

      AutoMultiAgent autoMultiAgent = await AutoMultiAgent.create(
        sessionId: sessionId,
        llmConfig: llmConfig,
        agentSession: _buildSession(sessionId),
        toolDriverList: toolDriverList,
        systemPrompt: systemPrompt,
        toolReflectPromptList: reflectPromptList ?? const[],
        timeoutSeconds: capabilityDto.timeoutSeconds,
        taskPipelineStrategy: capabilityDto.taskPipelineStrategy,
        toolPipelineStrategy: capabilityDto.toolPipelineStrategy??PipelineStrategyType.PARALLEL,
        enableThinking: capabilityDto.enableThinking,
        llmConfigList: llmConfigList,
      );
      sessionAgents[sessionId] = autoMultiAgent;
    } else if(toolDriverList.isEmpty && agentDriverList == null && capabilityDto.callbackOpenTool == null) { // TextAgent
      SessionAgent textAgent = TextAgent(
          sessionId: sessionId,
          llmConfig: llmConfig,
          agentSession: _buildSession(sessionId),
          systemPrompt: systemPrompt,
          textReflectPromptList: reflectPromptList??[],
          timeoutSeconds: capabilityDto.timeoutSeconds,
          taskPipelineStrategy: capabilityDto.taskPipelineStrategy,
          enableThinking: capabilityDto.enableThinking
      );
      sessionAgents[sessionId] = textAgent;
    } else if(agentDriverList == null) {  // ToolAgent
      CallbackOpenTool? clientOpenTool = null;
      if(capabilityDto.callbackOpenTool != null) clientOpenTool = CallbackOpenTool(opentool: capabilityDto.callbackOpenTool!.opentool, timeout: capabilityDto.callbackOpenTool!.timeout, fetchClientDriver: this.fetchClientDriver);
      SessionAgent toolAgent = ToolAgent(
          sessionId: sessionId,
          llmConfig: llmConfig,
          agentSession: _buildSession(sessionId),
          toolDriverList: toolDriverList,
          callbackOpenTool: clientOpenTool,
          systemPrompt: systemPrompt,
          toolReflectPromptList: reflectPromptList??[],
          timeoutSeconds: capabilityDto.timeoutSeconds,
          taskPipelineStrategy: capabilityDto.taskPipelineStrategy,
          toolPipelineStrategy: capabilityDto.toolPipelineStrategy??PipelineStrategyType.PARALLEL,
          enableThinking: capabilityDto.enableThinking
      );
      sessionAgents[sessionId] = toolAgent;
    } else {  // MultiAgent
      CallbackOpenTool? clientOpenTool = null;
      if(capabilityDto.callbackOpenTool != null) clientOpenTool = CallbackOpenTool(opentool: capabilityDto.callbackOpenTool!.opentool, timeout: capabilityDto.callbackOpenTool!.timeout, fetchClientDriver: this.fetchClientDriver);
      SessionAgent toolAgent = MultiAgent(
          sessionId: sessionId,
          llmConfig: llmConfig,
          agentSession: _buildSession(sessionId),
          toolDriverList: toolDriverList,
          subAgentDriverList: agentDriverList,
          clientOpenTool: clientOpenTool,
          systemPrompt: systemPrompt,
          toolReflectPromptList: reflectPromptList??[],
          timeoutSeconds: capabilityDto.timeoutSeconds,
          taskPipelineStrategy: capabilityDto.taskPipelineStrategy,
          toolPipelineStrategy: capabilityDto.toolPipelineStrategy??PipelineStrategyType.PARALLEL,
          enableThinking: capabilityDto.enableThinking
      );
      sessionAgents[sessionId] = toolAgent;
    }

    SessionDto sessionDto = SessionDto(sessionId: sessionId);

    return sessionDto;
  }

  Future<void> startSession(String sessionId, UserTaskDto userTaskDto,
      void Function(String sessionId, String taskId, AgentMessageDto agentMessageDto) listen,
      {
        void Function(String sessionId, String taskId,
            AgentMessageChunkDto agentMessageChunkDto)? listenChunk,
        void Function(String taskId)? getTaskId
      }) async {
    SessionAgent? sessionAgent = sessionAgents[sessionId];
    if(sessionAgent == null) throw SessionAgentNotFoundException(sessionId: sessionId);
    List<Content> userMessageList = userTaskDto.content
        .map((contentDto) => _convertToContent(contentDto))
        .toList();

    void Function(String taskId) fetchTaskId = (String taskId) {
      if(getTaskId != null) getTaskId(taskId);
      if(sessionAgent is MultiAgent) {
        List<String> subSessionIds = getSubSessionIds(sessionId);
        if(subSessionIds.isNotEmpty) {
          _updateSession(sessionAgent.agentSession, taskId, listen, listenChunk: listenChunk, subAgentSessionList: subSessionIds);
        } else {
          _updateSession(sessionAgent.agentSession, taskId, listen, listenChunk: listenChunk);
        }
      } else {
        _updateSession(sessionAgent.agentSession, taskId, listen, listenChunk: listenChunk);
      }
    };

    await sessionAgent.userToAgent(contentList: userMessageList, stream: userTaskDto.isChunk, fetchTaskId: fetchTaskId);
  }

  Future<List<AgentMessageDto>?> getCacheHistory(String sessionId) async {
    SessionAgent? sessionAgent = sessionAgents[sessionId];
    if (sessionAgent == null) return null;
    return sessionAgent
        .agentSession
        .listenAgentMessageList
        .map((AgentMessage agentMessage) {
      AgentMessageDto agentMessageDto = AgentMessageDto.fromModel(agentMessage);
      return agentMessageDto;
    }).toList();
  }

  Future<void> stopSession(SessionTaskDto sessionTaskDto) async {
    SessionAgent? sessionAgent = sessionAgents[sessionTaskDto.sessionId];
    if(sessionAgent == null) throw SessionAgentNotFoundException(sessionId: sessionTaskDto.sessionId);
    sessionAgent.stop(taskId: sessionTaskDto.taskId);
  }

  Future<void> clearSession(String sessionId) async {
    SessionAgent? sessionAgent = sessionAgents[sessionId];
    if(sessionAgent == null) throw SessionAgentNotFoundException(sessionId: sessionId);
    sessionAgent.clear();
    sessionAgents.remove(sessionId);
    sentMessages.clear();
  }

  Content _convertToContent(ContentDto contentDto) {
    return Content(type: contentDto.type, message: contentDto.message);
  }

  AgentSession _buildSession(String sessionId) {
    AgentSession agentSession = AgentSession(sessionId: sessionId);
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

  void _updateSession(AgentSession agentSession, String taskId,
      void Function(String sessionId, String taskId, AgentMessageDto agentMessageDto) listen, {
        void Function(String sessionId, String taskId, AgentMessageChunkDto agentMessageChunkDto)? listenChunk,
        List<String>? subAgentSessionList
      }) {

    agentSession.addAgentMessageListener((AgentMessage agentMessage) {
      AgentMessageDto agentMessageDto = AgentMessageDto.fromModel(agentMessage);
      if ((agentMessage.originalTaskId == taskId || agentMessage.originalTaskId.isEmpty) && !_isSentMessage(agentMessage, agentSession.sessionId)) {
        _recordAgentMessage(agentSession.sessionId, taskId, agentMessageDto);
        listen(agentSession.sessionId, taskId, agentMessageDto);
        _addToSentMessages(agentMessage, agentSession.sessionId);
      }
    });
    if(listenChunk != null) {
      agentSession.addAgentMessageChunkListener((AgentMessageChunk agentMessageChunk) {
        if ((agentMessageChunk.originalTaskId == taskId || agentMessageChunk.originalTaskId.isEmpty) && !_isSentMessage(agentMessageChunk, agentSession.sessionId)) {
          listenChunk(agentSession.sessionId, taskId, AgentMessageChunkDto.fromModel(agentMessageChunk));
          _addToSentMessages(agentMessageChunk, agentSession.sessionId);
        }
      });
    }

    if(subAgentSessionList != null && subAgentSessionList.isNotEmpty) {
      subAgentSessionList.forEach((subSessionId) {
        SessionAgent? subSessionAgent = sessionAgents[subSessionId];
        if(subSessionAgent != null) {
          subSessionAgent.agentSession.addAgentMessageListener((AgentMessage agentMessage) {
            if ((agentMessage.originalTaskId == taskId || agentMessage.originalTaskId.isEmpty) && !_isSentMessage(agentMessage, subSessionId)) {
              AgentMessageDto agentMessageDto = AgentMessageDto.fromModel(agentMessage);
              _recordAgentMessage(subSessionId, taskId, agentMessageDto);
              listen(subSessionId, taskId, agentMessageDto);
              _addToSentMessages(agentMessage, subSessionId);
            }
          });
          if(listenChunk != null) {
            subSessionAgent.agentSession.addAgentMessageChunkListener((AgentMessageChunk agentMessageChunk) {
              if ((agentMessageChunk.originalTaskId == taskId || agentMessageChunk.originalTaskId.isEmpty) && !_isSentMessage(agentMessageChunk, subSessionId)) {
                listenChunk(subSessionId, taskId, AgentMessageChunkDto.fromModel(agentMessageChunk));
                _addToSentMessages(agentMessageChunk, subSessionId);
              }
            });
          }
        }
      });
    }
  }

  Future<List<ToolDriver>> _buildToolDriverList(List<OpenSpecDto>? openSpecDtoList) async {
    if(openSpecDtoList == null) return [];
    List<ToolDriver> toolDriverList = [];
    for (OpenSpecDto openSpecDto in openSpecDtoList) {
      if (openSpecDto.protocol == Protocol.OPENAPI) {
        OpenAPI openAPI = await OpenAPILoader().load(openSpecDto.openSpec);
        String? authorization;
        if (openSpecDto.apiKey != null) {
          authorization = convertToAuthorization(openSpecDto.apiKey!.type, openSpecDto.apiKey!.apiKey);
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
        if( opentool.server == null && openSpecDto.serverUrl != null) {
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

  Future<List<AgentDriver>?> _buildAgentDriverList(List<SessionNameDto>? sessionList, String sessionId) async {
    if( sessionList == null || sessionList.isEmpty ) return null;
    List<NamedSimpleAgent> namedSimpleAgentList = [];
    List<NamedSessionAgent> namedSessionAgentList = [];
    sessionList.forEach((session) {
      SimpleAgent? simpleAgent = simpleAgents[session.sessionId];
      SessionAgent? sessionAgent = sessionAgents[session.sessionId];
      if(simpleAgent == null && sessionAgent == null) throw SessionAgentNotFoundException(sessionId: session.sessionId);

      if(simpleAgent != null) {
        namedSimpleAgentList.add(NamedSimpleAgent(name: session.name??session.sessionId, description: session.description, agent: simpleAgent));
      }
      if(sessionAgent != null) {
        String agentName = session.name??session.sessionId;
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
        namedSessionAgentList.add(NamedSessionAgent(name: agentName, description: session.description, agent: sessionAgent));
      }
    });

    SimpleAgentDriver simpleAgentDriver = SimpleAgentDriver(namedSimpleAgents: namedSimpleAgentList);
    SessionAgentDriver sessionAgentDriver = SessionAgentDriver(namedSessionAgents: namedSessionAgentList);

    List<AgentDriver> agentDriverList = [];
    agentDriverList.add(simpleAgentDriver);
    agentDriverList.add(sessionAgentDriver);
    return agentDriverList;
  }

  void _recordAgentMessage(String sessionId, String taskId, AgentMessageDto agentMessageDto) {
    SessionAgentMessageDto sessionAgentMessageDto = SessionAgentMessageDto(sessionId: sessionId, agentMessageDto: agentMessageDto);
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
    if(!sentMessages.containsKey(message)) {
      sentMessages[message] = {toSessionId: true};
    } else {
      sentMessages[message]![toSessionId] = true;
    }
  }

  void fetchClientDriver(String sessionId, OpenToolCallbackDriver clientDriver) {
    clientDriverMap[sessionId] = clientDriver;
  }

  void clientDriverCallback(String sessionId, ot.ToolReturn toolReturn) {
    OpenToolCallbackDriver? clientDriver = clientDriverMap[sessionId];
    if(clientDriver == null) {
      throw SessionAgentNotFoundException(sessionId: sessionId);
    }
    clientDriver.callback(toolReturn);
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

  List<String> _getSubSessionIdsRecursive(SessionAgent agent, Set<String> visitedSessionIds) {
    List<String> allSubSessionIds = [];

    final (sessionAgentDriver, simpleAgentDriver) = _extractAgentDrivers(agent);

    if (sessionAgentDriver != null) {
      for (var namedSessionAgent in sessionAgentDriver.namedSessionAgents) {
        String subSessionId = namedSessionAgent.agent.sessionId;

        if (!visitedSessionIds.contains(subSessionId)) {
          allSubSessionIds.add(subSessionId);
          visitedSessionIds.add(subSessionId);

          allSubSessionIds.addAll(_getSubSessionIdsRecursive(namedSessionAgent.agent, visitedSessionIds));
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

  (SessionAgentDriver?, SimpleAgentDriver?) _extractAgentDrivers(SessionAgent rootAgent) {
    if (rootAgent is! MultiAgent) {
      return (null, null);
    }

    SessionAgentDriver? sessionAgentDriver;
    SimpleAgentDriver? simpleAgentDriver;

    for (var agentDriver in rootAgent.subAgentDriverList) {
      if (agentDriver is SessionAgentDriver && sessionAgentDriver == null) {
        sessionAgentDriver = agentDriver;
      } else if (agentDriver is SimpleAgentDriver && simpleAgentDriver == null) {
        simpleAgentDriver = agentDriver;
      }
      if (sessionAgentDriver != null && simpleAgentDriver != null) break;
    }

    return (sessionAgentDriver, simpleAgentDriver);
  }
}
