import 'dart:async';

import 'package:dart_openai_sdk/dart_openai_sdk.dart';
import 'package:liteagent_core/src/core/agents/llm/openai_executor.dart';
import 'package:liteagent_core/src/core/agents/llm/model.dart';
import 'package:liteagent_core/src/core/agents/model.dart';
import 'package:liteagent_core/src/core/agents/session_agent/session.dart';
import 'package:liteagent_core/src/core/agents/session_agent/session_restore_state.dart';
import 'package:liteagent_core/src/core/agents/text_agent/text_agent.dart';
import 'package:liteagent_core/src/core/llm/model.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'package:test/test.dart';

void main() {
  test('reasoning delta to text and stop emits one complete reasoning message',
      () async {
    final completions = _completions();
    final chunks = <AgentMessageChunk>[];
    final executor = _StubOpenAIExecutor([
      _reasoningDelta('plan '),
      _reasoningDelta('the answer'),
      _textDelta('final answer'),
      ChatCompletionDelta(finishReason: FinishReasonType.STOP),
      ChatCompletionDelta(completions: completions),
    ]);

    final messages = await _request(executor, chunks);
    final reasoningMessages = messages
        .where((message) => message.type == AgentMessageType.REASONING)
        .toList();

    expect(reasoningMessages, hasLength(1));
    expect(reasoningMessages.single.content, 'plan the answer');
    expect(reasoningMessages.single.sessionId, 'session-1');
    expect(reasoningMessages.single.originalTaskId, 'original-task-1');
    expect(reasoningMessages.single.parentTaskId, 'parent-task-1');
    expect(reasoningMessages.single.taskId, 'task-1');
    expect(reasoningMessages.single.role, AgentRoleType.LLM);
    expect(reasoningMessages.single.to, AgentRoleType.AGENT);
    expect(reasoningMessages.single.completions, same(completions));

    final textMessages = messages
        .where((message) => message.type == AgentMessageType.TEXT)
        .toList();
    expect(textMessages, hasLength(1));
    expect(textMessages.single.content, 'final answer');
    expect(textMessages.single.completions, same(completions));

    expect(
      chunks
          .where((chunk) =>
              chunk.type == AgentMessageType.REASONING && chunk.part is String)
          .map((chunk) => chunk.part),
      ['plan ', 'the answer'],
    );
  });

  test(
      'reasoning delta to tool calls emits reasoning and preserves tool accumulation',
      () async {
    final completions = _completions();
    final chunks = <AgentMessageChunk>[];
    final executor = _StubOpenAIExecutor([
      _reasoningDelta('choose a tool'),
      _toolCallDelta(
          id: 'call-1', name: 'search', arguments: '{"query":"dart"}'),
      ChatCompletionDelta(finishReason: FinishReasonType.TOOL_CALLS),
      ChatCompletionDelta(completions: completions),
    ]);

    final messages = await _request(executor, chunks);
    final reasoningMessages = messages
        .where((message) => message.type == AgentMessageType.REASONING)
        .toList();
    final toolMessages = messages
        .where((message) => message.type == AgentMessageType.TOOL_CALLS)
        .toList();

    expect(reasoningMessages, hasLength(1));
    expect(reasoningMessages.single.content, 'choose a tool');
    expect(reasoningMessages.single.completions, same(completions));
    expect(toolMessages, hasLength(1));
    expect(toolMessages.single.completions, same(completions));
    expect(toolMessages.single.reasoningContent, 'choose a tool');

    final functionCalls = toolMessages.single.content as List<FunctionCall>;
    expect(functionCalls, hasLength(1));
    expect(functionCalls.single.id, 'call-1');
    expect(functionCalls.single.name, 'search');
    expect(functionCalls.single.arguments, {'query': 'dart'});
  });

  test('ordinary text stream does not emit an empty reasoning message',
      () async {
    final executor = _StubOpenAIExecutor([
      _textDelta('plain answer'),
      ChatCompletionDelta(finishReason: FinishReasonType.STOP),
    ]);

    final messages = await _request(executor, <AgentMessageChunk>[]);

    expect(
        messages.where((message) => message.type == AgentMessageType.REASONING),
        isEmpty);
    expect(messages.where((message) => message.type == AgentMessageType.TEXT),
        hasLength(1));
  });

  test('standalone reasoning is not converted to a user context message',
      () async {
    final executor = _StubOpenAIExecutor([_textDelta('next answer')]);

    await _requestWithContext(executor, [
      _message(role: AgentRoleType.AGENT, content: 'first question'),
      _message(
        role: AgentRoleType.LLM,
        type: AgentMessageType.REASONING,
        content: 'private reasoning',
      ),
      _message(role: AgentRoleType.LLM, content: 'first answer'),
      _inputMessage(),
    ]);

    expect(executor.receivedMessages, hasLength(3));
    expect(
      executor.receivedMessages.map((message) => message.role),
      [
        OpenAIChatMessageRole.user,
        OpenAIChatMessageRole.assistant,
        OpenAIChatMessageRole.user,
      ],
    );
    expect(
      executor.receivedMessages
          .expand((message) => message.content ?? const [])
          .map((item) => item.text),
      isNot(contains('private reasoning')),
    );
  });

  test('restored standalone reasoning is excluded from the next context',
      () async {
    final session = AgentSession(sessionId: 'session-1')
      ..restore(
        SessionRestoreState(
          sessionId: 'session-1',
          contextMessages: [
            _message(role: AgentRoleType.AGENT, content: 'first question'),
            _message(
              role: AgentRoleType.LLM,
              type: AgentMessageType.REASONING,
              content: 'restored reasoning',
            ),
            _message(role: AgentRoleType.LLM, content: 'first answer'),
          ],
        ),
      );
    final agent = TextAgent(
      sessionId: 'session-1',
      llmConfig: null,
      agentSession: session,
    );
    session.hasSystemMessage = true;
    agent.dispatcherMap.create('next-task');

    final context = await agent.prepareAgentLLMMessageList(
      _message(
        role: AgentRoleType.AGENT,
        content: 'next question',
        taskId: 'next-task',
      ),
    );

    expect(
      context.where((message) => message.type == AgentMessageType.REASONING),
      isEmpty,
    );
    expect(context.map((message) => message.content), [
      'first question',
      'first answer',
    ]);
    expect(
      session.taskDoneAgentMessageList
          .where((message) => message.type == AgentMessageType.REASONING)
          .single
          .content,
      'restored reasoning',
    );
  });

  test('restored reasoning is replayed only on its assistant tool calls',
      () async {
    final executor = _StubOpenAIExecutor(
      [_textDelta('next answer')],
      model: 'deepseek-v4',
    );
    final session = AgentSession(sessionId: 'session-1')
      ..restore(
        SessionRestoreState(
          sessionId: 'session-1',
          contextMessages: [
            _message(role: AgentRoleType.AGENT, content: 'find it'),
            _message(
              role: AgentRoleType.LLM,
              type: AgentMessageType.REASONING,
              content: 'use search',
            ),
            _message(
              role: AgentRoleType.LLM,
              type: AgentMessageType.TOOL_CALLS,
              content: [
                FunctionCall(
                  id: 'call-1',
                  name: 'search',
                  arguments: {'query': 'dart'},
                ),
              ],
            ),
            _message(
              role: AgentRoleType.TOOL,
              type: AgentMessageType.TOOL_RETURN,
              content: ToolReturn(
                id: 'call-1',
                result: {'value': 'result'},
              ),
            ),
          ],
        ),
      );

    await _requestWithContext(
      executor,
      [...session.taskDoneAgentMessageList, _inputMessage()],
    );

    final toolCallsMessage = executor.receivedMessages.singleWhere(
      (message) => message.toolCalls?.isNotEmpty == true,
    );
    expect(toolCallsMessage.role, OpenAIChatMessageRole.assistant);
    expect(toolCallsMessage.reasoningContent, 'use search');
    expect(
      executor.receivedMessages
          .where((message) => message.role == OpenAIChatMessageRole.user)
          .expand((message) => message.content ?? const [])
          .map((item) => item.text),
      isNot(contains('use search')),
    );
  });

  test('reasoning message is still delivered to agent listeners', () async {
    final session = AgentSession(sessionId: 'session-1');
    final agent = TextAgent(
      sessionId: 'session-1',
      llmConfig: null,
      agentSession: session,
    );
    final listened = <AgentMessage>[];
    session.addAgentMessageListener(listened.add);

    await agent.toAgent(
      _message(
        role: AgentRoleType.LLM,
        type: AgentMessageType.REASONING,
        content: 'visible reasoning',
      ),
    );

    expect(listened, hasLength(1));
    expect(listened.single.type, AgentMessageType.REASONING);
    expect(listened.single.content, 'visible reasoning');
  });

  test(
      'reasoning closes once when a boundary, finish reason, and stream close all occur',
      () async {
    final executor = _StubOpenAIExecutor([
      _reasoningDelta('only once'),
      _textDelta('answer'),
      ChatCompletionDelta(finishReason: FinishReasonType.STOP),
    ]);

    final messages = await _request(executor, <AgentMessageChunk>[]);

    expect(
      messages
          .where((message) => message.type == AgentMessageType.REASONING)
          .map((m) => m.content),
      ['only once'],
    );
  });

  test(
      'stream close emits accumulated reasoning without a finish or usage delta',
      () async {
    final executor = _StubOpenAIExecutor([_reasoningDelta('closed reasoning')]);

    final messages = await _request(executor, <AgentMessageChunk>[]);

    expect(
      messages
          .where((message) => message.type == AgentMessageType.REASONING)
          .map((m) => m.content),
      ['closed reasoning'],
    );
  });
}

Future<List<AgentMessage>> _request(
  _StubOpenAIExecutor executor,
  List<AgentMessageChunk> chunks,
) async {
  final stream = await executor.requestByStream(
    agentMessageList: [_inputMessage()],
    listenChunk: chunks.add,
  );
  return stream.toList();
}

Future<List<AgentMessage>> _requestWithContext(
  _StubOpenAIExecutor executor,
  List<AgentMessage> context,
) async {
  final stream = await executor.requestByStream(agentMessageList: context);
  return stream.toList();
}

AgentMessage _inputMessage() {
  return AgentMessage(
    sessionId: 'session-1',
    originalTaskId: 'original-task-1',
    parentTaskId: 'parent-task-1',
    taskId: 'task-1',
    role: AgentRoleType.AGENT,
    to: AgentRoleType.LLM,
    type: AgentMessageType.TEXT,
    content: 'question',
  );
}

AgentMessage _message({
  required String role,
  required dynamic content,
  String type = AgentMessageType.TEXT,
  String taskId = 'task-1',
}) {
  return AgentMessage(
    sessionId: 'session-1',
    originalTaskId: 'original-task-1',
    parentTaskId: 'parent-task-1',
    taskId: taskId,
    role: role,
    to: role == AgentRoleType.AGENT ? AgentRoleType.LLM : AgentRoleType.AGENT,
    type: type,
    content: content,
  );
}

ChatCompletionDelta _reasoningDelta(String reasoning) {
  return ChatCompletionDelta(
    delta: OpenAIStreamChatCompletionChoiceDeltaModel(
      role: null,
      content: null,
      reasoningContent: reasoning,
    ),
  );
}

ChatCompletionDelta _textDelta(String text) {
  return ChatCompletionDelta(
    delta: OpenAIStreamChatCompletionChoiceDeltaModel(
      role: null,
      content: [OpenAIChatCompletionChoiceMessageContentItemModel.text(text)],
    ),
  );
}

ChatCompletionDelta _toolCallDelta({
  required String id,
  required String name,
  required String arguments,
}) {
  return ChatCompletionDelta(
    delta: OpenAIStreamChatCompletionChoiceDeltaModel(
      role: null,
      content: null,
      toolCalls: [
        OpenAIStreamResponseToolCall.fromMap({
          'id': id,
          'type': 'function',
          'function': {'name': name, 'arguments': arguments},
          'index': 0,
        }),
      ],
    ),
  );
}

Completions _completions() {
  return Completions(
    tokenUsage:
        TokenUsage(promptTokens: 1, completionTokens: 2, totalTokens: 3),
    id: 'completion-1',
    model: 'test-model',
  );
}

class _StubOpenAIExecutor extends OpenAIExecutor {
  _StubOpenAIExecutor(
    List<ChatCompletionDelta> deltas, {
    String model = 'test-model',
  })  : _deltas = deltas,
        super(LLMConfig(baseUrl: 'http://localhost', model: model));

  final List<ChatCompletionDelta> _deltas;
  List<OpenAIChatCompletionChoiceMessageModel> receivedMessages = [];

  @override
  Future<Stream<ChatCompletionDelta>> chatByStream({
    required List<OpenAIChatCompletionChoiceMessageModel> messageList,
    List<OpenAIToolModel>? toolList,
    ResponseFormat? responseFormat,
    bool? enableThinking,
  }) async {
    receivedMessages = messageList;
    return Stream.fromIterable(_deltas);
  }
}
