import 'dart:async';

import 'package:liteagent_core/liteagent_core.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'package:test/test.dart';

void main() {
  group('ToolAgent execution limits', () {
    test('invalid non-positive configuration falls back to safe defaults', () {
      const limits = ToolExecutionLimits(
        maxLlmRequests: 0,
        maxToolRounds: -1,
        maxToolCalls: 0,
        maxConsecutiveIdenticalToolRounds: -1,
        maxTaskDurationSeconds: 0,
      );

      expect(limits.maxLlmRequests, 64);
      expect(limits.maxToolRounds, 16);
      expect(limits.maxToolCalls, 64);
      expect(limits.maxConsecutiveIdenticalToolRounds, 3);
      expect(limits.maxTaskDurationSeconds, 300);
    });

    test('terminates consecutive calls with the same tool and arguments', () async {
      final driver = _RecordingToolDriver();
      final harness = _buildHarness(
        driver: driver,
        limits: const ToolExecutionLimits(
          maxLlmRequests: 20,
          maxToolRounds: 20,
          maxToolCalls: 20,
          maxConsecutiveIdenticalToolRounds: 2,
          maxTaskDurationSeconds: 30,
        ),
        callsForRound: (_) => [
          _call('write_memory_summary', {'text': 'same'})
        ],
      );

      final terminal = await harness.run();

      expect(terminal.status, TaskStatusType.EXCEPTION);
      expect(terminal.description!['code'], 'tool_loop_limit_exceeded');
      expect(terminal.description!['limit'], 'maxConsecutiveIdenticalToolRounds');
      expect(driver.callCount, 2);
      expect(_terminalStatuses(harness.session), hasLength(1));
      expect(harness.agent.hasPendingTaskWork(harness.taskId), isFalse);
    });

    test('same tool with different arguments is limited by rounds, not duplicate detection',
        () async {
      final driver = _RecordingToolDriver();
      final harness = _buildHarness(
        driver: driver,
        limits: const ToolExecutionLimits(
          maxLlmRequests: 20,
          maxToolRounds: 3,
          maxToolCalls: 20,
          maxConsecutiveIdenticalToolRounds: 1,
          maxTaskDurationSeconds: 30,
        ),
        callsForRound: (round) => [
          _call('write_memory_summary', {'text': 'value-$round'}),
        ],
      );

      final terminal = await harness.run();

      expect(terminal.description!['limit'], 'maxToolRounds');
      expect(driver.callCount, 3);
    });

    test('alternating tools does not trigger identical-call detection', () async {
      final driver = _RecordingToolDriver(
        functionNames: const {'first_tool', 'second_tool'},
      );
      final harness = _buildHarness(
        driver: driver,
        limits: const ToolExecutionLimits(
          maxLlmRequests: 20,
          maxToolRounds: 4,
          maxToolCalls: 20,
          maxConsecutiveIdenticalToolRounds: 1,
          maxTaskDurationSeconds: 30,
        ),
        callsForRound: (round) => [
          _call(round.isOdd ? 'first_tool' : 'second_tool', const {'value': 1}),
        ],
      );

      final terminal = await harness.run();

      expect(terminal.description!['limit'], 'maxToolRounds');
      expect(driver.callCount, 4);
    });

    test('rejects an entire tool batch when the total call limit would be exceeded', () async {
      final driver = _RecordingToolDriver(
        functionNames: const {'first_tool', 'second_tool'},
      );
      final harness = _buildHarness(
        driver: driver,
        limits: const ToolExecutionLimits(
          maxLlmRequests: 20,
          maxToolRounds: 20,
          maxToolCalls: 3,
          maxConsecutiveIdenticalToolRounds: 20,
          maxTaskDurationSeconds: 30,
        ),
        callsForRound: (round) => [
          _call('first_tool', {'round': round}),
          _call('second_tool', {'round': round}),
        ],
      );

      final terminal = await harness.run();

      expect(terminal.description!['limit'], 'maxToolCalls');
      expect(driver.callCount, 2);
    });

    test('terminates when the maximum LLM request count is reached', () async {
      final driver = _RecordingToolDriver();
      final harness = _buildHarness(
        driver: driver,
        limits: const ToolExecutionLimits(
          maxLlmRequests: 3,
          maxToolRounds: 20,
          maxToolCalls: 20,
          maxConsecutiveIdenticalToolRounds: 20,
          maxTaskDurationSeconds: 30,
        ),
        callsForRound: (round) => [
          _call('write_memory_summary', {'text': 'value-$round'}),
        ],
      );

      final terminal = await harness.run();

      expect(terminal.description!['limit'], 'maxLlmRequests');
      expect(driver.callCount, 3);
      expect(harness.agent.llmCallCount, 3);
    });
  });

  group('ToolAgent task termination', () {
    test('external stop cancels a pending tool and emits one terminal status', () async {
      final driver = _BlockingToolDriver();
      final harness = _buildHarness(
        driver: driver,
        callsForRound: (_) => [
          _call('write_memory_summary', const {'text': 'same'})
        ],
      );

      final terminalFuture = harness.start();
      await driver.started.future;
      harness.agent.stop(taskId: harness.taskId);
      final terminal = await terminalFuture;

      expect(terminal.status, TaskStatusType.STOP);
      expect(driver.cancelCount, 1);
      expect(_terminalStatuses(harness.session), hasLength(1));
      expect(harness.agent.hasPendingTaskWork(harness.taskId), isFalse);
    });

    test('a late tool return after stop cannot restart LLM inference', () async {
      final driver = _BlockingToolDriver(completeWhenCancelled: false);
      final harness = _buildHarness(
        driver: driver,
        callsForRound: (_) => [
          _call('write_memory_summary', const {'text': 'same'})
        ],
      );

      final terminalFuture = harness.start();
      await driver.started.future;
      harness.agent.stop(taskId: harness.taskId);
      final terminal = await terminalFuture;
      driver.complete({'status': 'late'});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(terminal.status, TaskStatusType.STOP);
      expect(harness.agent.llmCallCount, 1);
      expect(_terminalStatuses(harness.session), hasLength(1));
      expect(harness.agent.hasPendingTaskWork(harness.taskId), isFalse);
    });

    test('stop racing with a tool callback still produces one terminal state', () async {
      final driver = _BlockingToolDriver(completeWhenCancelled: false);
      final harness = _buildHarness(
        driver: driver,
        callsForRound: (_) => [
          _call('write_memory_summary', const {'text': 'same'})
        ],
      );

      final terminalFuture = harness.start();
      await driver.started.future;
      scheduleMicrotask(() => harness.agent.stop(taskId: harness.taskId));
      scheduleMicrotask(() => driver.complete({'status': 'accepted'}));
      await terminalFuture;
      await Future<void>.delayed(Duration.zero);

      expect(_terminalStatuses(harness.session), hasLength(1));
      expect(harness.agent.isTaskTerminal(harness.taskId), isTrue);
    });

    test('task execution deadline cancels pending work', () async {
      final driver = _BlockingToolDriver();
      final harness = _buildHarness(
        driver: driver,
        limits: const ToolExecutionLimits(
          maxLlmRequests: 20,
          maxToolRounds: 20,
          maxToolCalls: 20,
          maxConsecutiveIdenticalToolRounds: 20,
          maxTaskDurationSeconds: 1,
        ),
        callsForRound: (_) => [
          _call('write_memory_summary', const {'text': 'same'})
        ],
      );

      final terminal = await harness.run();

      expect(terminal.status, TaskStatusType.EXCEPTION);
      expect(terminal.description!['code'], 'task_execution_timeout');
      expect(driver.cancelCount, 1);
      expect(harness.agent.hasPendingTaskWork(harness.taskId), isFalse);
    });
  });
}

_Harness _buildHarness({
  required ToolDriver driver,
  required List<FunctionCall> Function(int round) callsForRound,
  ToolExecutionLimits limits = const ToolExecutionLimits(
    maxLlmRequests: 20,
    maxToolRounds: 20,
    maxToolCalls: 20,
    maxConsecutiveIdenticalToolRounds: 3,
    maxTaskDurationSeconds: 30,
  ),
}) {
  final session = AgentSession(sessionId: 'test-session');
  final agent = _ScriptedToolAgent(
    session: session,
    driver: driver,
    limits: limits,
    callsForRound: callsForRound,
  );
  return _Harness(agent, session);
}

FunctionCall _call(String name, Map<String, dynamic> arguments) {
  return FunctionCall(id: '', name: name, arguments: arguments);
}

List<TaskStatus> _terminalStatuses(AgentSession session) {
  return session.listenAgentMessageList
      .where((message) => message.type == SessionMessageType.TASK_STATUS)
      .map((message) => message.content)
      .whereType<TaskStatus>()
      .where(
        (status) =>
            status.status == TaskStatusType.DONE ||
            status.status == TaskStatusType.STOP ||
            status.status == TaskStatusType.EXCEPTION,
      )
      .toList();
}

class _Harness {
  final _ScriptedToolAgent agent;
  final AgentSession session;
  String taskId = '';

  _Harness(this.agent, this.session);

  Future<TaskStatus> start() {
    final terminal = Completer<TaskStatus>();
    session.addAgentMessageListener((message) {
      if (message.taskId != taskId || message.type != SessionMessageType.TASK_STATUS) {
        return;
      }
      final status = message.content as TaskStatus;
      if ((status.status == TaskStatusType.DONE ||
              status.status == TaskStatusType.STOP ||
              status.status == TaskStatusType.EXCEPTION) &&
          !terminal.isCompleted) {
        terminal.complete(status);
      }
    });
    agent.userToAgent(
      contentList: [Content(type: ContentType.TEXT, message: 'run')],
      fetchTaskId: (id) => taskId = id,
    );
    return terminal.future.timeout(const Duration(seconds: 3));
  }

  Future<TaskStatus> run() => start();
}

class _ScriptedToolAgent extends ToolAgent {
  final List<FunctionCall> Function(int round) callsForRound;
  int llmCallCount = 0;

  _ScriptedToolAgent({
    required AgentSession session,
    required ToolDriver driver,
    required ToolExecutionLimits limits,
    required this.callsForRound,
  }) : super(
          sessionId: session.sessionId,
          llmConfig: LLMConfig(model: 'unused'),
          agentSession: session,
          toolDriverList: [driver],
          executionLimits: limits,
        );

  @override
  Future<void> toLLM(AgentMessage agentMessage) async {
    if (!await reserveLLMRequest(agentMessage)) return;
    llmCallCount++;
    final calls = callsForRound(llmCallCount)
        .map(
          (call) => FunctionCall(
            id: 'call-$llmCallCount-${call.name}',
            name: call.name,
            arguments: Map<String, dynamic>.from(call.arguments),
          ),
        )
        .toList();
    await toAgent(
      AgentMessage(
        sessionId: agentMessage.sessionId,
        originalTaskId: agentMessage.originalTaskId,
        parentTaskId: agentMessage.parentTaskId,
        taskId: agentMessage.taskId,
        role: AgentRoleType.LLM,
        to: AgentRoleType.AGENT,
        type: AgentMessageType.TOOL_CALLS,
        content: calls,
      ),
    );
  }
}

class _RecordingToolDriver extends ToolDriver {
  final Set<String> functionNames;
  int callCount = 0;

  _RecordingToolDriver({
    this.functionNames = const {'write_memory_summary'},
  });

  @override
  Future<ToolReturn> call(FunctionCall functionCall) async {
    callCount++;
    return ToolReturn(id: functionCall.id, result: const {'status': 'accepted'});
  }

  @override
  bool hasFunction(String functionName) => functionNames.contains(functionName);

  @override
  List<FunctionModel> parse() => const [];
}

class _BlockingToolDriver extends _RecordingToolDriver {
  final bool completeWhenCancelled;
  final Completer<void> started = Completer<void>();
  final Completer<ToolReturn> _result = Completer<ToolReturn>();
  int cancelCount = 0;

  _BlockingToolDriver({this.completeWhenCancelled = true});

  @override
  Future<ToolReturn> call(FunctionCall functionCall) {
    callCount++;
    if (!started.isCompleted) started.complete();
    return _result.future;
  }

  @override
  Future<void> cancel(String functionCallId) async {
    cancelCount++;
    if (completeWhenCancelled && !_result.isCompleted) {
      _result.complete(
        ToolReturn(id: functionCallId, result: const {'error': 'cancelled'}),
      );
    }
  }

  void complete(Map<String, dynamic> result) {
    if (!_result.isCompleted) {
      _result.complete(ToolReturn(id: 'late-call', result: result));
    }
  }
}
