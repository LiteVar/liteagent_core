import 'dart:async';

import 'package:liteagent_core_dart/liteagent_core.dart';
import 'package:liteagent_core_dart/src/core/agents/auto/wrappers/function.dart';
import 'package:liteagent_core_dart/src/core/agents/auto/wrappers/llm.dart';
import 'package:test/test.dart';

void main() {
  group('AutoMultiAgent completed conversation context', () {
    test('planner input separates history from the current instruction', () {
      final input = PlanningPrompt.buildUserInput(
        userCommand: 'Continue it.',
        conversationContext: 'User: Remember Alpha.\nAssistant: Done.',
      );

      expect(input, contains('# Previous completed conversation'));
      expect(input, contains('User: Remember Alpha.'));
      expect(input, contains('# Current user instruction\nContinue it.'));
    });

    test('records an in-memory turn and supplies it to the next planner call',
        () async {
      final session = AgentSession(sessionId: 'auto-session');
      final agent = await _buildAgent(session);
      final planner = _RecordingPlanner(messageSender: agent);
      agent.taskPlanner = planner;

      await _runInstruction(agent, 'Remember project Alpha.');

      expect(planner.conversationContexts.single, isEmpty);
      expect(session.taskDoneAgentMessageList, hasLength(2));
      expect(
        session.taskDoneAgentMessageList.map((message) => message.role),
        <String>[SessionRoleType.USER, SessionRoleType.AGENT],
      );

      await _runInstruction(agent, 'Continue that project.');

      expect(planner.userCommands, <String>[
        'Remember project Alpha.',
        'Continue that project.',
      ]);
      expect(
        planner.conversationContexts[1],
        'User: Remember project Alpha.\n'
        'Assistant: planner-result-1',
      );
      expect(session.taskDoneAgentMessageList, hasLength(4));
    });

    test('supplies restored completed context to the planner', () async {
      final restoredMessages = <AgentMessage>[
        _contextMessage(
          role: SessionRoleType.USER,
          to: SessionRoleType.AGENT,
          type: SessionMessageType.CONTENT_LIST,
          content: <Content>[
            Content(type: ContentType.TEXT, message: 'Remember project Beta.'),
          ],
        ),
        _contextMessage(
          role: SessionRoleType.AGENT,
          to: SessionRoleType.USER,
          type: SessionMessageType.TEXT,
          content: 'Project Beta remembered.',
        ),
      ];
      final session = AgentSession(sessionId: 'auto-session')
        ..restore(
          SessionRestoreState(
            sessionId: 'auto-session',
            contextMessages: restoredMessages,
          ),
        );
      final agent = await _buildAgent(session);
      final planner = _RecordingPlanner(messageSender: agent);
      agent.taskPlanner = planner;

      await _runInstruction(agent, 'Continue that project.');

      expect(planner.userCommands.single, 'Continue that project.');
      expect(
        planner.conversationContexts.single,
        'User: Remember project Beta.\n'
        'Assistant: Project Beta remembered.',
      );
      expect(session.taskDoneAgentMessageList, hasLength(4));
      expect(
        session.taskDoneAgentMessageList.take(2),
        orderedEquals(restoredMessages),
      );
    });
  });
}

Future<AutoMultiAgent> _buildAgent(AgentSession session) {
  return AutoMultiAgent.create(
    sessionId: session.sessionId,
    toolDriverList: const <ToolDriver>[],
    llmConfig: LLMConfig(model: 'test-model'),
    agentSession: session,
  );
}

Future<void> _runInstruction(AutoMultiAgent agent, String instruction) async {
  final done = Completer<void>();
  agent.agentSession.addAgentMessageListener((message) {
    if (message.sessionId != agent.sessionId ||
        message.type != SessionMessageType.TASK_STATUS ||
        message.content is! TaskStatus) {
      return;
    }
    final status = message.content as TaskStatus;
    if (status.status == TaskStatusType.DONE && !done.isCompleted) {
      done.complete();
    }
  });

  await agent.userToAgent(
    contentList: <Content>[
      Content(type: ContentType.TEXT, message: instruction),
    ],
  );
  await done.future.timeout(const Duration(seconds: 5));
}

AgentMessage _contextMessage({
  required String role,
  required String to,
  required String type,
  required dynamic content,
}) {
  return AgentMessage(
    sessionId: 'auto-session',
    originalTaskId: 'restored-task',
    parentTaskId: null,
    taskId: 'restored-task',
    role: role,
    to: to,
    type: type,
    content: content,
  );
}

class _RecordingPlanner extends AutoTaskPlanner {
  final List<String> userCommands = <String>[];
  final List<String> conversationContexts = <String>[];

  _RecordingPlanner({required AutoMessageSender messageSender})
      : super(plannerLLMConfig: null, messageSender: messageSender);

  @override
  Future<String> planTasks({
    required String userCommand,
    String conversationContext = '',
    required List<IndexedLLMConfig> indexedLLMConfigs,
    required List<IndexedFunction> indexedFunctions,
    required String taskId,
    LLMConfig? requestLLMConfig,
  }) async {
    userCommands.add(userCommand);
    conversationContexts.add(conversationContext);
    return 'planner-result-${userCommands.length}';
  }
}
