import 'dart:async';

import 'package:liteagent_core_dart/liteagent_core.dart';
import 'package:liteagent_core_dart/liteagent_service.dart' as service;
import 'package:opentool_dart/opentool_client.dart';
import 'package:test/test.dart';

void main() {
  group('AgentService session restore', () {
    test('normal initialization still generates an empty new session',
        () async {
      final agentService = service.AgentService();

      final result = await agentService.initSession(_capability());
      final agent = agentService.getSessionAgent(result.sessionId);

      expect(result.sessionId, isNotEmpty);
      expect(agent, isNotNull);
      expect(agent!.agentSession.taskDoneAgentMessageList, isEmpty);
      expect(agent.agentSession.listenAgentMessageList, isEmpty);
    });

    test('restores the requested id and completed context in order', () async {
      final agentService = service.AgentService();
      final contextMessages = <AgentMessage>[
        _message(taskId: 'task-1', role: SessionRoleType.USER, content: 'one'),
        _message(
          taskId: 'task-1',
          role: AgentRoleType.LLM,
          content: 'two',
        ),
      ];
      final restoreState = service.SessionRestoreState(
        sessionId: 'restored-session',
        contextMessages: contextMessages,
      );

      final result = await agentService.initSession(
        _capability(),
        restoreState: restoreState,
      );
      final agent = agentService.getSessionAgent(result.sessionId);

      expect(result.sessionId, 'restored-session');
      expect(agent, isNotNull);
      expect(
        agent!.agentSession.taskDoneAgentMessageList,
        orderedEquals(contextMessages),
      );

      contextMessages.clear();
      expect(agent.agentSession.taskDoneAgentMessageList, hasLength(2));
    });

    test('duplicate restored session id is rejected without replacement',
        () async {
      final agentService = service.AgentService();
      final restoreState = service.SessionRestoreState(
        sessionId: 'running-session',
        contextMessages: const <AgentMessage>[],
      );
      await agentService.initSession(
        _capability(),
        restoreState: restoreState,
      );
      final original = agentService.getSessionAgent('running-session');

      await expectLater(
        agentService.initSession(
          _capability(),
          restoreState: restoreState,
        ),
        throwsA(isA<service.SessionAlreadyExistsException>()),
      );
      expect(agentService.getSessionAgent('running-session'), same(original));
    });

    test('restores ToolAgent context without invoking a tool', () async {
      final agentService = service.AgentService();
      final toolDriver = _NoopToolDriver();
      final contextMessages = <AgentMessage>[
        _message(taskId: 'tool-task', role: AgentRoleType.LLM),
      ];

      final result = await agentService.initSession(
        _capability(),
        restoreState: service.SessionRestoreState(
          sessionId: 'tool-session',
          contextMessages: contextMessages,
        ),
        customToolDriverList: <ToolDriver>[toolDriver],
      );
      final agent = agentService.getSessionAgent(result.sessionId);

      expect(agent, isA<ToolAgent>());
      expect(
        agent!.agentSession.taskDoneAgentMessageList,
        orderedEquals(contextMessages),
      );
      expect(toolDriver.callCount, 0);
    });

    test('restores only the MultiAgent root session', () async {
      final agentService = service.AgentService();
      final child = await agentService.initSession(_capability());
      final childAgent = agentService.getSessionAgent(child.sessionId)!;
      final contextMessages = <AgentMessage>[
        _message(taskId: 'root-task', role: AgentRoleType.LLM),
      ];
      final rootCapability = service.CapabilityDto(
        systemPrompt: 'root system prompt',
        sessionList: <service.SessionNameDto>[
          service.SessionNameDto(sessionId: child.sessionId, name: 'child'),
        ],
      );

      final result = await agentService.initSession(
        rootCapability,
        restoreState: service.SessionRestoreState(
          sessionId: 'root-session',
          contextMessages: contextMessages,
        ),
      );
      final rootAgent = agentService.getSessionAgent(result.sessionId);

      expect(rootAgent, isA<MultiAgent>());
      expect(
        rootAgent!.agentSession.taskDoneAgentMessageList,
        orderedEquals(contextMessages),
      );
      expect(childAgent.agentSession.taskDoneAgentMessageList, isEmpty);
      expect(agentService.getSessionAgent(child.sessionId), same(childAgent));
    });

    test('restores AutoMultiAgent context without replaying it', () async {
      final agentService = service.AgentService();
      final contextMessages = <AgentMessage>[
        _message(taskId: 'auto-task', role: AgentRoleType.LLM),
      ];

      final result = await agentService.initSession(
        service.CapabilityDto(systemPrompt: 'system prompt', auto: true),
        restoreState: service.SessionRestoreState(
          sessionId: 'auto-session',
          contextMessages: contextMessages,
        ),
      );
      final agent = agentService.getSessionAgent(result.sessionId);

      expect(agent, isA<AutoMultiAgent>());
      expect(
        agent!.agentSession.taskDoneAgentMessageList,
        orderedEquals(contextMessages),
      );
      expect(agent.agentSession.listenAgentMessageList, isEmpty);
    });
  });

  group('AgentSession restore', () {
    test('is silent and restores only completed task context', () {
      final session = AgentSession(sessionId: 'session')
        ..sessionSummary = 'stale summary'
        ..summaryMessageCount = 10;
      final contextMessages = <AgentMessage>[
        _message(taskId: 'task', role: SessionRoleType.USER),
      ];
      var listenerCalls = 0;
      session.addAgentMessageListener((_) => listenerCalls++);

      session.restore(
        SessionRestoreState(
          sessionId: 'session',
          contextMessages: contextMessages,
        ),
      );

      expect(listenerCalls, 0);
      expect(session.listenAgentMessageList, isEmpty);
      expect(session.taskDoneAgentMessageList, orderedEquals(contextMessages));
      expect(session.sessionSummary, isNull);
      expect(session.summaryMessageCount, 0);
    });

    test('derives system state from the developer role', () async {
      final systemMessage = _message(
        taskId: 'old-task',
        role: TextRoleType.DEVELOPER,
        content: 'restored system prompt',
      );
      final session = AgentSession(sessionId: 'session')
        ..restore(
          SessionRestoreState(
            sessionId: 'session',
            contextMessages: <AgentMessage>[systemMessage],
          ),
        );
      final agent = _RecordingSessionAgent(
        sessionId: 'session',
        agentSession: session,
        systemPrompt: 'new system prompt',
      );

      await agent.userToAgent(
        contentList: <Content>[
          Content(type: ContentType.TEXT, message: 'next turn'),
        ],
      );
      final received = await agent.firstAgentMessage;

      expect(SessionRoleType.SYSTEM, TextRoleType.DEVELOPER);
      expect(session.hasSystemMessage, isTrue);
      expect(received.role, SessionRoleType.USER);
      expect(session.taskDoneAgentMessageList, <AgentMessage>[systemMessage]);
    });
  });
}

service.CapabilityDto _capability() => service.CapabilityDto(
      systemPrompt: 'system prompt',
    );

AgentMessage _message({
  required String taskId,
  required String role,
  String content = 'content',
}) =>
    AgentMessage(
      sessionId: 'session',
      originalTaskId: taskId,
      parentTaskId: null,
      taskId: taskId,
      role: role,
      to: SessionRoleType.AGENT,
      type: AgentMessageType.TEXT,
      content: content,
    );

class _RecordingSessionAgent extends SessionAgent {
  final Completer<AgentMessage> _firstAgentMessage = Completer<AgentMessage>();

  _RecordingSessionAgent({
    required super.sessionId,
    required super.agentSession,
    super.systemPrompt,
  });

  Future<AgentMessage> get firstAgentMessage =>
      _firstAgentMessage.future.timeout(const Duration(seconds: 1));

  @override
  Future<void> toAgent(AgentMessage agentMessage) async {
    if (!_firstAgentMessage.isCompleted) {
      _firstAgentMessage.complete(agentMessage);
    }
    pipeline.completeAsync(agentMessage.taskId);
  }
}

class _NoopToolDriver extends ToolDriver {
  int callCount = 0;

  @override
  Future<ToolReturn> call(FunctionCall functionCall) async {
    callCount++;
    return ToolReturn(id: functionCall.id, result: <String, dynamic>{});
  }

  @override
  bool hasFunction(String functionName) => false;

  @override
  List<FunctionModel> parse() => const <FunctionModel>[];
}
