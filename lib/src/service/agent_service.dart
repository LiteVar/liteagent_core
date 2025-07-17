import 'dart:async';
import 'dart:convert';
import 'package:opentool_dart/opentool_dart.dart';
import 'package:openapi_dart/openapi_dart.dart';
import 'package:openmodbus_dart/openmodbus_dart.dart';
import 'package:openrpc_dart/openrpc_dart.dart';
import '../../lite_agent_core.dart';
import 'session_message_manage_service.dart';
import 'dto.dart';
import 'exception.dart';

class AgentService {
  Map<String, SessionAgent> sessionAgents = {}; /// Map<sessionId, SessionAgent>
  Map<String, SimpleAgent> simpleAgents = {}; /// Map<sessionId, SimpleAgent>
  List<ToolDriver> globalDriverList = [];
  Map<String, OpenToolDriver> opentoolDriverMap = {}; /// Map<sessionId, OpenToolDriver>
  Map<String, ClientDriver> clientDriverMap= {}; /// Map<sessionId, ClientDriver>
  List<SessionMessageManageService> agentMessageManageServiceList = [];

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

  Future<SessionDto> initSession(
      CapabilityDto capabilityDto,
      void Function(String sessionId, AgentMessageDto agentMessageDto) listen, {
        Map<String, OpenToolDriver>? opentoolDriverMap,
        List<ToolDriver>? customToolDriverList,
        void Function(String sessionId, AgentMessageChunkDto agentMessageChunkDto)? listenChunk
      }) async {
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

    List<AgentDriver>? agentDriverList = await _buildAgentDriverList(capabilityDto.sessionList, sessionId, listen);

    if(toolDriverList.isEmpty && agentDriverList == null && capabilityDto.clientOpenTool == null) { // TextAgent
      SessionAgent textAgent = TextAgent(
          sessionId: sessionId,
          llmConfig: llmConfig,
          agentSession: _buildSession(sessionId, listen, listenChunk: listenChunk),
          systemPrompt: systemPrompt,
          textReflectPromptList: reflectPromptList??[],
          timeoutSeconds: capabilityDto.timeoutSeconds,
          taskPipelineStrategy: capabilityDto.taskPipelineStrategy
      );
      sessionAgents[sessionId] = textAgent;
    } else if(agentDriverList == null) {  // ToolAgent
      ClientOpenTool? clientOpenTool = null;
      if(capabilityDto.clientOpenTool != null) clientOpenTool = ClientOpenTool(opentool: capabilityDto.clientOpenTool!.opentool, timeout: capabilityDto.clientOpenTool!.timeout, fetchClientDriver: this.fetchClientDriver);
      SessionAgent toolAgent = ToolAgent(
          sessionId: sessionId,
          llmConfig: llmConfig,
          agentSession: _buildSession(sessionId, listen, listenChunk: listenChunk),
          toolDriverList: toolDriverList,
          clientOpenTool: clientOpenTool,
          systemPrompt: systemPrompt,
          toolReflectPromptList: reflectPromptList??[],
          timeoutSeconds: capabilityDto.timeoutSeconds,
          taskPipelineStrategy: capabilityDto.taskPipelineStrategy,
          toolPipelineStrategy: capabilityDto.toolPipelineStrategy??PipelineStrategyType.PARALLEL
      );
      sessionAgents[sessionId] = toolAgent;
    } else {  // MultiAgent
      ClientOpenTool? clientOpenTool = null;
      if(capabilityDto.clientOpenTool != null) clientOpenTool = ClientOpenTool(opentool: capabilityDto.clientOpenTool!.opentool, timeout: capabilityDto.clientOpenTool!.timeout, fetchClientDriver: this.fetchClientDriver);
      SessionAgent toolAgent = MultiAgent(
          sessionId: sessionId,
          llmConfig: llmConfig,
          agentSession: _buildSession(sessionId, listen, listenChunk: listenChunk),
          toolDriverList: toolDriverList,
          subAgentDriverList: agentDriverList,
          clientOpenTool: clientOpenTool,
          systemPrompt: systemPrompt,
          toolReflectPromptList: reflectPromptList??[],
          timeoutSeconds: capabilityDto.timeoutSeconds,
          taskPipelineStrategy: capabilityDto.taskPipelineStrategy,
          toolPipelineStrategy: capabilityDto.toolPipelineStrategy??PipelineStrategyType.PARALLEL
      );
      sessionAgents[sessionId] = toolAgent;
    }

    SessionDto sessionDto = SessionDto(sessionId: sessionId);

    return sessionDto;
  }

  Future<void> startSession(String sessionId, UserTaskDto userTaskDto, {String? taskId}) async {
    SessionAgent? sessionAgent = sessionAgents[sessionId];
    if(sessionAgent == null) throw SessionAgentNotFoundException(sessionId: sessionId);
    List<Content> userMessageList = userTaskDto.content
        .map((contentDto) => _convertToContent(contentDto))
        .toList();
    await sessionAgent.userToAgent(contentList: userMessageList, taskId: taskId, stream: userTaskDto.stream);
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
  }

  Content _convertToContent(ContentDto contentDto) {
    return Content(type: contentDto.type, message: contentDto.message);
  }

  AgentSession _buildSession(String sessionId, void Function(String sessionId, AgentMessageDto agentMessageDto) listen, {void Function(String sessionId, AgentMessageChunkDto agentMessageChunkDto)? listenChunk}) {
    AgentSession agentSession = AgentSession();
    agentSession.addAgentMessageListener((AgentMessage agentMessage) {
      AgentMessageDto agentMessageDto = AgentMessageDto.fromModel(agentMessage);
      _recordAgentMessage(sessionId, agentMessageDto);
      listen(sessionId, agentMessageDto);
    });
    if(listenChunk != null) {
      agentSession.addAgentMessageChunkListener((AgentMessageChunk agentMessageChunk) {
        listenChunk(sessionId, AgentMessageChunkDto.fromModel(agentMessageChunk));
      });
    }
    return agentSession;
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
      } else if (openSpecDto.protocol == Protocol.OPENMODBUS) {
        OpenModbus openModbus = await OpenModbusLoader().load(openSpecDto.openSpec);
        ToolDriver openModbusDriver = OpenModbusDriver(openModbus);
        toolDriverList.add(openModbusDriver);
      } else if (openSpecDto.protocol == Protocol.JSONRPCHTTP) {
        OpenRPC openRPC = await OpenRPCLoader().load(openSpecDto.openSpec);
        ToolDriver jsonrpcHttpDriver = JsonRPCDriver(openRPC);
        toolDriverList.add(jsonrpcHttpDriver);
      } else if (openSpecDto.protocol == Protocol.OPENTOOL) {
        if(openSpecDto.openToolId == null) throw OpenToolIdNotFoundException(openToolId: "NULL");
        OpenToolDriver? opentoolDriver = await opentoolDriverMap[openSpecDto.openToolId!];
        if(opentoolDriver != null) {
          OpenTool openTool = await OpenToolLoader().load(openSpecDto.openSpec);
          toolDriverList.add(opentoolDriver.bind(openTool));
        } else {
          throw OpenToolIdNotFoundException(openToolId: openSpecDto.openToolId!);
        }
      } else if (openSpecDto.protocol == Protocol.SERIALPORT) {
        SerialPortDriver serialPortDriver = SerialPortDriver();
        toolDriverList.add(serialPortDriver);
      } else if (openSpecDto.protocol == Protocol.MCP_STDIO_TOOLS) {
        OpenMCP openMCP = OpenMCP.fromJson(jsonDecode(openSpecDto.openSpec));
        McpStdioDriver mcpStdioDriver = McpStdioDriver(openMCP);
        toolDriverList.add(mcpStdioDriver);
      }
    }
    return toolDriverList;
  }

  Future<List<AgentDriver>?> _buildAgentDriverList(List<SessionNameDto>? sessionList, String sessionId, void Function(String sessionId, AgentMessageDto agentMessageDto) listen) async {
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
        void Function(AgentMessage agentMessage) AgentListen = (AgentMessage agentMessage){
            String role = agentMessage.role;
            if(agentMessage.role == AgentRoleType.AGENT) role = AgentRoleType.SUBAGENT;
            if(agentMessage.role == AgentRoleType.USER) role = AgentRoleType.AGENT;
            String to = agentMessage.to;
            if(agentMessage.to == AgentRoleType.AGENT) to = AgentRoleType.SUBAGENT;
            if(agentMessage.to == AgentRoleType.USER) to = AgentRoleType.AGENT;

            AgentMessage subAgentMessage = AgentMessage(
              sessionId: agentMessage.sessionId,
              parentTaskId: agentMessage.parentTaskId,
              taskId: agentMessage.taskId,
              role: role,
              to: to,
              type: agentMessage.type,
              content: agentMessage.content
            );
            if(role == AgentRoleType.SUBAGENT && agentMessage.type == AgentMessageType.TASK_STATUS) {
              if(agentMessage.content is TaskStatus) {
                TaskStatus taskStatus = agentMessage.content as TaskStatus;
                if(taskStatus.status == TaskStatusType.START) {
                  taskStatus.description = {"subAgent": agentName};
                  subAgentMessage = AgentMessage(
                    sessionId: agentMessage.sessionId,
                    parentTaskId: agentMessage.parentTaskId,
                    taskId: agentMessage.taskId,
                    role: role,
                    to: to,
                    type: agentMessage.type,
                    content: taskStatus
                  );
                }
              }
            }

          AgentMessageDto agentMessageDto = AgentMessageDto.fromModel(subAgentMessage);
          _recordAgentMessage(session.sessionId, agentMessageDto);
          listen(sessionId, agentMessageDto);
        };
        sessionAgent.agentSession.addAgentMessageListener(AgentListen);
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

  void _recordAgentMessage(String sessionId, AgentMessageDto agentMessageDto) {
    SessionAgentMessageDto sessionAgentMessageDto = SessionAgentMessageDto(sessionId: sessionId, agentMessageDto: agentMessageDto);
    agentMessageManageServiceList.forEach((service) {
      service.addMessage(sessionAgentMessageDto);
    });
  }

  void fetchClientDriver(String sessionId, ClientDriver clientDriver) {
    clientDriverMap[sessionId] = clientDriver;
  }

  void clientDriverCallback(String sessionId, ToolReturn toolReturn) {
    ClientDriver? clientDriver = clientDriverMap[sessionId];
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
