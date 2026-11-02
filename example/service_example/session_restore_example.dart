import 'dart:convert';

import 'package:liteagent_core/liteagent_core.dart';
import 'package:liteagent_core/liteagent_service.dart';

/// Demonstrates restoring completed session context without a database, LLM,
/// tool server, API key, listener replay, or stream events.
Future<void> main() async {
  final agentService = AgentService();
  final capability = CapabilityDto(
    systemPrompt: 'You are a concise assistant.',
  );

  // Normal initialization remains unchanged and starts with empty context.
  final newSession = await agentService.initSession(capability);
  final newAgent = agentService.getSessionAgent(newSession.sessionId)!;
  _check(newSession.sessionId.isNotEmpty, 'new session id was not generated');
  _check(
    newAgent.agentSession.taskDoneAgentMessageList.isEmpty,
    'new session context should be empty',
  );
  await agentService.clearSession(newSession.sessionId);

  const restoredSessionId = 'persisted-session-id';
  final completedMessages = <AgentMessage>[
    _message(
      sessionId: restoredSessionId,
      taskId: 'task-1',
      originalTaskId: 'original-task-1',
      role: SessionRoleType.SYSTEM,
      to: SessionRoleType.AGENT,
      type: AgentMessageType.TEXT,
      content: 'You are a concise assistant.',
    ),
    _message(
      sessionId: restoredSessionId,
      taskId: 'task-1',
      originalTaskId: 'original-task-1',
      role: SessionRoleType.AGENT,
      to: AgentRoleType.LLM,
      type: AgentMessageType.CONTENT_LIST,
      content: <Content>[
        Content(type: ContentType.TEXT, message: 'Remember project Alpha.'),
      ],
    ),
    _message(
      sessionId: restoredSessionId,
      taskId: 'task-1',
      originalTaskId: 'original-task-1',
      role: AgentRoleType.LLM,
      to: SessionRoleType.AGENT,
      type: AgentMessageType.TEXT,
      content: 'I will remember project Alpha.',
    ),
  ];

  // Simulate the server storing DTO JSON and reconstructing AgentMessage.
  final persistedJson = completedMessages
      .map((message) => jsonEncode(AgentMessageDto.fromModel(message).toJson()))
      .toList();
  final restoredMessages = persistedJson
      .map(
        (json) => AgentMessageDto.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        ).toModel(),
      )
      .toList();

  final restoredSession = await agentService.initSession(
    capability,
    restoreState: SessionRestoreState(
      sessionId: restoredSessionId,
      contextMessages: restoredMessages,
    ),
  );
  final restoredAgent =
      agentService.getSessionAgent(restoredSession.sessionId)!;
  final restoredContext = restoredAgent.agentSession.taskDoneAgentMessageList;

  _check(
    restoredSession.sessionId == restoredSessionId,
    'restored session id changed',
  );
  _check(restoredContext.length == 3, 'restored context is incomplete');
  _check(
    restoredContext.map((message) => message.role).join(',') ==
        '${SessionRoleType.SYSTEM},${SessionRoleType.AGENT},${AgentRoleType.LLM}',
    'restored context order changed',
  );
  _check(
    restoredContext.every(
      (message) => message.originalTaskId == 'original-task-1',
    ),
    'originalTaskId was not preserved',
  );
  _check(
    restoredAgent.agentSession.hasSystemMessage,
    'system message state was not derived',
  );
  _check(
    restoredAgent.agentSession.listenAgentMessageList.isEmpty,
    'restore should not replay listener history',
  );

  // AgentSession owns its copied list after restoration.
  restoredMessages.clear();
  _check(
    restoredContext.length == 3,
    'external list mutation changed restored context',
  );

  var duplicateRejected = false;
  try {
    await agentService.initSession(
      capability,
      restoreState: const SessionRestoreState(
        sessionId: restoredSessionId,
        contextMessages: <AgentMessage>[],
      ),
    );
  } on SessionAlreadyExistsException {
    duplicateRejected = true;
  }
  _check(duplicateRejected, 'duplicate running session was overwritten');

  print('Session restore example passed:');
  print('- normal session id generation');
  print('- DTO JSON round trip with originalTaskId');
  print('- restored id, context order, and system state');
  print('- silent restore and defensive list copy');
  print('- duplicate running session rejection');
}

AgentMessage _message({
  required String sessionId,
  required String taskId,
  required String originalTaskId,
  required String role,
  required String to,
  required String type,
  required dynamic content,
}) {
  return AgentMessage(
    sessionId: sessionId,
    originalTaskId: originalTaskId,
    parentTaskId: null,
    taskId: taskId,
    role: role,
    to: to,
    type: type,
    content: content,
  );
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}
