import 'package:liteagent_core_dart/liteagent_core.dart';
import 'package:liteagent_core_dart/liteagent_service.dart';
import 'package:unique_id_dart/unique_id_dart.dart';

import '../listener.dart';

Future<void> runTextAgentExample({
  required LLMConfig llmConfig,
  required String prompt,
  required String systemPrompt,
  bool stream = false,
}) async {
  final sessionId = uniqueId();
  final textAgent = TextAgent(
    sessionId: sessionId,
    llmConfig: llmConfig,
    agentSession: AgentSession(sessionId: sessionId),
    systemPrompt: systemPrompt,
  );

  void fetchTaskId(String taskId) {
    _attachListeners(textAgent.agentSession, taskId, stream: stream);
  }

  await textAgent.userToAgent(
    contentList: [Content(type: ContentType.TEXT, message: prompt)],
    stream: stream,
    fetchTaskId: fetchTaskId,
  );
}

void _attachListeners(
  AgentSession agentSession,
  String taskId, {
  required bool stream,
}) {
  agentSession.addAgentMessageListener((AgentMessage agentMessage) {
    listen(
      agentSession.sessionId,
      taskId,
      AgentMessageDto.fromModel(agentMessage),
    );
  });

  if (!stream) return;

  agentSession.addAgentMessageChunkListener((AgentMessageChunk agentMessageChunk) {
    listenChunk(
      agentSession.sessionId,
      taskId,
      AgentMessageChunkDto.fromModel(agentMessageChunk),
    );
  });
}
