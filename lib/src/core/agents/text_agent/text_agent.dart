import 'dart:convert';

import '../../llm/model.dart';
import '../llm/exception.dart';
import '../llm/openai_executor.dart';
import '../model.dart';
import '../reflection/model.dart';
import '../reflection/reflector.dart';
import '../reflection/reflector_agent.dart';
import '../reflection/reflector_manager.dart';
import '../session_agent/agent_message_handler.dart';
import '../session_agent/dispatcher.dart';
import '../session_agent/model.dart';
import '../session_agent/session_agent.dart';
import '../simple_agent.dart';
import 'text_agent_message_handler.dart';
import 'model.dart';

class TextAgent extends SessionAgent {
  static const int _contextKeepMessageCount = 8;
  static const double _contextUsageThreshold = 0.7;
  static const String _summarySystemPrompt = '''
You are a conversation context compressor. Summarize the given history for future turns.
Rules:
- Keep only facts, constraints, confirmed decisions, user preferences, and open questions.
- Do not invent information.
- Be concise and structured.
- Max length: 200 words.

Output format (Markdown):
- summary: ...
- facts:
  - ...
- open_questions:
  - ...
- artifacts:
  - ...
''';

  LLMConfig? llmConfig;
  bool? enableThinking;
  ReflectorManager reflectionManager = ReflectorManager();
  Completions? currAgentReflectorCompletions;
  AgentMessageHandlerManager manager = AgentMessageHandlerManager();

  TextAgent(
      {required super.sessionId,
      required this.llmConfig,
      required super.agentSession,
      String? super.systemPrompt,
      super.timeoutSeconds = 600,
      List<ReflectPrompt> textReflectPromptList = const [],
      super.taskPipelineStrategy,
      this.enableThinking}) {
    textReflectPromptList.forEach((reflectPrompt) {
      ReflectorAgent reflectorAgent = ReflectorAgent(
          llmExecutor: OpenAIExecutor(reflectPrompt.llmConfig),
          systemPrompt: reflectPrompt.prompt,
          sessionId: this.sessionId,
          parentTaskId: this.parentTaskId);
      AgentReflector agentReflector = AgentReflector(
          agent: reflectorAgent, subscribeCompletions: subscribeCompletions);
      reflectionManager.addReflector(agentReflector);
    });

    manager.registerHandler(
        role: TextRoleType.USER,
        handler: UserMessageHandler(reflectionManager, toLLM));
    manager.registerHandler(
        role: TextRoleType.ASSISTANT,
        handler: LLMMessageHandler(reflectionManager, toReflection, toUser));
    manager.registerHandler(
        role: TextRoleType.REFLECTION,
        handler: TextReflectionMessageHandler(reflectionManager, toLLM, toUser,
            onTextRetry: onReflectionRetry));
  }

  void subscribeCompletions(Completions? completions) {
    currAgentReflectorCompletions = completions;
  }

  @override
  Future<void> toAgent(AgentMessage agentMessage) async {
    agentSession.addListenAgentMessage(agentMessage);
    Command? nextCommand = manager.handleMessage(agentMessage);
    if (nextCommand != null) dispatcherMap.dispatch(nextCommand);
  }

  Future<void> toReflection(AgentMessage agentMessage) async {
    Reflection reflection = await reflectionManager.reflect(agentMessage.type,
        agentMessage.content as String, agentMessage.originalTaskId);
    AgentMessage reflectionMessage = AgentMessage(
        sessionId: agentMessage.sessionId,
        originalTaskId: agentMessage.originalTaskId,
        parentTaskId: this.parentTaskId,
        taskId: agentMessage.taskId,
        role: TextRoleType.REFLECTION,
        to: TextRoleType.AGENT,
        type: TextMessageType.REFLECTION,
        content: reflection,
        completions: currAgentReflectorCompletions);
    Command reflectionCommand = Command(toAgent, reflectionMessage);
    dispatcherMap.dispatch(reflectionCommand);
  }

  void onReflectionRetry(AgentMessage agentMessage) {
    dispatcherMap.clearTaskMessageList(agentMessage.taskId);
  }

  Future<void> toUser(AgentMessage sessionMessage) async {
    agentSession.addListenAgentMessage(sessionMessage);

    pipeline.completeAsync(sessionMessage.taskId);
    clearTaskLLMConfig(sessionMessage.originalTaskId);
    AgentMessage clientMessage = AgentMessage(
        sessionId: sessionMessage.sessionId,
        originalTaskId: sessionMessage.originalTaskId,
        parentTaskId: this.parentTaskId,
        taskId: sessionMessage.taskId,
        role: TextRoleType.AGENT,
        to: TextRoleType.CLIENT,
        type: TextMessageType.TASK_STATUS,
        content: TaskStatus(
            status: TaskStatusType.DONE, taskId: sessionMessage.taskId));
    Command clientCommand = Command(toClient, clientMessage);
    dispatcherMap.dispatch(clientCommand);
    List<AgentMessage> taskDoneMessageList =
        dispatcherMap.getTaskMessageList(sessionMessage.taskId);
    agentSession.addTaskDoneAgentMessageList(taskDoneMessageList);
    timeout.start(handleIdleTimeout);
  }

  Future<List<AgentMessage>> prepareAgentLLMMessageList(
      AgentMessage agentMessage) async {
    List<AgentMessage> sessionMessageList =
        List<AgentMessage>.from(agentSession.taskDoneAgentMessageList);
    List<AgentMessage> taskMessageList =
        dispatcherMap.getTaskMessageList(agentMessage.taskId);

    List<AgentMessage> sessionContextMessages =
        _filterContextMessages(sessionMessageList);
    List<AgentMessage> taskContextMessages =
        _filterContextMessages(taskMessageList);

    bool shouldSummarize = _shouldSummarize();
    if (shouldSummarize) {
      await _updateSessionSummary(sessionContextMessages);
    }

    List<AgentMessage> agentLLMMessageList = [];
    if (shouldSummarize && agentSession.sessionSummary?.isNotEmpty == true) {
      agentLLMMessageList.add(
          _buildSummaryMessage(agentMessage, agentSession.sessionSummary!));
      if (sessionContextMessages.length > _contextKeepMessageCount) {
        sessionContextMessages = sessionContextMessages.sublist(
          sessionContextMessages.length - _contextKeepMessageCount,
        );
      }
    }

    agentLLMMessageList.addAll(sessionContextMessages);
    agentLLMMessageList.addAll(taskContextMessages);
    return agentLLMMessageList;
  }

  Future<void> toLLM(AgentMessage agentMessage) async {
    agentSession.addListenAgentMessage(agentMessage);
    final LLMConfig? effectiveLLMConfig = resolveTaskLLMConfig(
        agentMessage.originalTaskId,
        defaultLLMConfig: llmConfig);
    if (effectiveLLMConfig == null) {
      pushException(
        agentMessage.sessionId,
        agentMessage.taskId,
        agentMessage.originalTaskId,
        jsonEncode(LLMException(message: "LLM config is required").toJson()),
      );
      return;
    }

    List<AgentMessage> agentLLMMessageList =
        await prepareAgentLLMMessageList(agentMessage);
    try {
      if (super.agentSession.isStream) {
        Stream<AgentMessage> agentMessageStream =
            await OpenAIExecutor(effectiveLLMConfig).requestByStream(
                agentMessageList: agentLLMMessageList,
                enableThinking: enableThinking,
                listenChunk: listenChunk);

        agentMessageStream.listen(
            (newAgentMessage) {
              Command nextCommand = Command(toAgent, newAgentMessage);
              dispatcherMap.dispatch(nextCommand);
            },
            onDone: () {},
            onError: (e) {
              pushException(agentMessage.sessionId, agentMessage.taskId,
                  agentMessage.originalTaskId, e.toString());
            });
      } else {
        AgentMessage newAgentMessage = await OpenAIExecutor(effectiveLLMConfig)
            .request(
                agentMessageList: agentLLMMessageList,
                enableThinking: enableThinking);
        Command nextCommand = Command(toAgent, newAgentMessage);
        dispatcherMap.dispatch(nextCommand);
      }
    } on LLMException catch (e) {
      pushException(agentMessage.sessionId, agentMessage.taskId,
          agentMessage.originalTaskId, jsonEncode(e.toJson()));
    }
  }

  void pushException(String sessionId, String taskId, String originalTaskId,
      String exceptionMessage) {
    pipeline.completeAsync(taskId);
    clearTaskLLMConfig(originalTaskId);
    AgentMessage agentMessage = AgentMessage(
        sessionId: sessionId,
        originalTaskId: originalTaskId,
        parentTaskId: this.parentTaskId,
        taskId: taskId,
        role: TextRoleType.AGENT,
        to: TextRoleType.CLIENT,
        type: TextMessageType.TASK_STATUS,
        content: TaskStatus(
            status: TaskStatusType.EXCEPTION,
            taskId: taskId,
            description: {"error": exceptionMessage}));
    Command exceptionCommand = Command(toClient, agentMessage);
    dispatcherMap.stop(agentMessage.taskId, exceptionCommand);
    timeout.start(handleIdleTimeout);
  }

  void listenChunk(AgentMessageChunk agentMessageChunk) {
    if (agentMessageChunk.type == TextMessageType.TEXT ||
        agentMessageChunk.type == ReasoningMessageType.REASONING) {
      agentMessageChunk.role = TextRoleType.AGENT;
      agentMessageChunk.to = TextRoleType.USER;
    } else if (agentMessageChunk.type == TextMessageType.TASK_STATUS ||
        agentMessageChunk.type == ReasoningMessageType.TASK_STATUS) {
      agentMessageChunk.role = TextRoleType.AGENT;
      agentMessageChunk.to = TextRoleType.CLIENT;
    }
    agentSession.addListenAgentMessageChunk(agentMessageChunk);
  }

  bool _shouldSummarize() {
    int? contextWindowSize = llmConfig?.contextWindowSize;
    if (contextWindowSize == null || contextWindowSize <= 0) return false;
    int? promptTokens = _lastPromptTokens();
    if (promptTokens == null) return false;
    double ratio = promptTokens / contextWindowSize;
    return ratio >= _contextUsageThreshold;
  }

  int? _lastPromptTokens() {
    for (final message in agentSession.taskDoneAgentMessageList.reversed) {
      final usage = message.completions?.tokenUsage;
      if (usage != null) return usage.promptTokens;
    }
    return null;
  }

  Future<void> _updateSessionSummary(
      List<AgentMessage> sessionContextMessages) async {
    if (sessionContextMessages.length <= _contextKeepMessageCount) return;

    int cutoff = sessionContextMessages.length - _contextKeepMessageCount;
    if (cutoff == agentSession.summaryMessageCount &&
        agentSession.sessionSummary?.isNotEmpty == true) {
      return;
    }

    String summaryInput = _formatMessagesForSummary(
      sessionContextMessages.sublist(0, cutoff),
    );
    if (summaryInput.isEmpty) return;

    try {
      if (llmConfig == null) return;
      SimpleAgent summarizer =
          SimpleAgent(llmConfig: llmConfig, systemPrompt: _summarySystemPrompt);
      AgentMessage result = await summarizer.userToAgent(
        contentList: [Content(type: ContentType.TEXT, message: summaryInput)],
      );
      String summary = (result.content as String).trim();
      if (summary.isNotEmpty) {
        agentSession.sessionSummary = summary;
        agentSession.summaryMessageCount = cutoff;
      }
    } catch (_) {
      // If summary fails, keep existing context to avoid breaking requests.
    }
  }

  List<AgentMessage> _filterContextMessages(List<AgentMessage> messages) {
    List<AgentMessage> filtered = [];
    for (final sessionMessage in messages) {
      if (sessionMessage.role == TextRoleType.DEVELOPER ||
          sessionMessage.role == TextRoleType.ASSISTANT ||
          sessionMessage.to == TextRoleType.ASSISTANT) {
        filtered.add(sessionMessage);
      }
    }
    return filtered;
  }

  AgentMessage _buildSummaryMessage(AgentMessage anchor, String summary) {
    return AgentMessage(
      sessionId: anchor.sessionId,
      originalTaskId: anchor.originalTaskId,
      parentTaskId: anchor.parentTaskId,
      taskId: anchor.taskId,
      role: TextRoleType.DEVELOPER,
      to: TextRoleType.ASSISTANT,
      type: TextMessageType.TEXT,
      content: 'Session summary:\\n$summary',
    );
  }

  String _formatMessagesForSummary(List<AgentMessage> messages) {
    final buffer = StringBuffer();
    for (final message in messages) {
      final text = _contentToText(message);
      if (text.isEmpty) continue;
      buffer.writeln('${_roleLabel(message)}: $text');
    }
    return buffer.toString().trim();
  }

  String _roleLabel(AgentMessage message) {
    if (message.role == TextRoleType.USER) return 'User';
    if (message.role == TextRoleType.ASSISTANT) return 'Assistant';
    if (message.role == TextRoleType.DEVELOPER) return 'System';
    return 'Other';
  }

  String _contentToText(AgentMessage message) {
    final content = message.content;
    if (content is String) return content.trim();
    if (content is List<Content>) {
      return content
          .map((item) {
            if (item.type == ContentType.TEXT) return item.message;
            if (item.type == ContentType.IMAGE_URL)
              return '[image] ${item.message}';
            return item.message;
          })
          .join('\\n')
          .trim();
    }
    try {
      return jsonEncode(content);
    } catch (_) {
      return '';
    }
  }
}
