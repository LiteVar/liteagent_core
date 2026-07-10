# LiteAgent core for dart

English · [中文](README-zh_CN.md)

LLM `AI Agent` multi sessions service.

## Features

- Support pure text agent without JSON Spec.
- Support  [OpenAPI](https://github.com/djbird2046/openapi_dart)/[OpenRPC](https://github.com/djbird2046/openrpc_dart)/[OpenModbus](https://github.com/LiteVar/openmodbus_dart)/[OpenTool](https://github.com/LiteVar/opentool_dart) JSON Spec.
- Support LLM Function calling to `HTTP API`/`json-rpc 2.0 over HTTP`/`Modbus` and more custom tools.

## Usage

### Prepare

1. Some OpenSpec json file, according to `/example/json/open*/*.json`, which is callable.
2. Run your tool server, which is described in json file.
3. Add `.env` file in the `example` folder, and add below content in the `.env` file：
     ```properties
     baseUrl = https://xxx.xxx.com         # LLM API BaseURL
     apiKey = sk-xxxxxxxxxxxxxxxxxxxx      # LLM API ApiKey
     ```
4. Use below method to run agent service.

### Method 1(Recommend): AgentService
- According to `/example/service_example`
- Support multi agent session via session id.
- Support multi task in the same agent, identify different tasks by `taskId`. After finishing task, task message could be added to session as new task context.

```dart
Future<void> main() async {
  CapabilityDto capabilityDto = CapabilityDto(
      llmConfig: _buildLLMConfig(),       // LLM Config
      systemPrompt: _buildSystemPrompt(), // System Prompt
      openSpecList: await _buildOpenSpecList()  // OpenSpec Description String List
  );
  SessionDto sessionDto = await agentService.initChat(
      capabilityDto,
      listen        // Subscribe AgentMessage, Agent chat with User/Client/LLM/Tools Role
  ); // Get Session Id
  
  String prompt = "<USER PROMPT, e.g. call any one tool>";
  UserTaskDto userTaskDto = UserTaskDto(taskId: "<Identify different tasks, NOT more than 36 chars>", contentList: [UserMessageDto(type: UserMessageDtoType.text, message: prompt)]);  // User Content List, support type text/imageUrl
  await agentService.startChat(sessionDto.id, userTaskDto);
}
```

### Restoring persisted session runtime

`AgentService.initSession` accepts the optional `SessionRestoreState` argument for reconstructing a session that was evicted from memory because of an idle timeout or service restart. Normal session creation should omit this argument and continues to generate a new session ID.

The upper-layer service owns database persistence, deletion, and business-expiration decisions. This package does not depend on SQLite, Drift, or any other database implementation.

```dart
// Load completed context DTOs from your persistence layer.
final List<Map<String, dynamic>> storedMessageJson =
    await persistence.loadCompletedContext(sessionId);

final contextMessages = storedMessageJson
    .map((json) => AgentMessageDto.fromJson(json).toModel())
    .toList();

final restoredSession = await agentService.initSession(
  capabilityDto,
  agentId: agentId,
  restoreState: SessionRestoreState(
    sessionId: sessionId,
    contextMessages: contextMessages,
  ),
);
```

Restoration behavior and constraints:

- `contextMessages` must be in original message order and contain only completed-task context.
- Incomplete tool calls, streaming chunks, and tasks waiting for callbacks must not be restored.
- Assistant `tool_calls` and tool-return messages must be complete and correctly paired.
- Context is copied into `AgentSession.taskDoneAgentMessageList` without replaying tasks, notifying message listeners, emitting stream events, or rebroadcasting historical messages.
- `hasSystemMessage` is inferred from the restored developer/system message, so the next turn does not add the system prompt again.
- `sessionSummary` and `summaryMessageCount` are reset; core can regenerate a summary later when needed.
- Restoring an ID that already belongs to a running session throws `SessionAlreadyExistsException` and does not replace that session.
- MultiAgent root context is restored independently. Referenced child sessions must be restored separately when needed.
- AutoMultiAgent records only each completed user instruction and final answer as cross-turn context. Its Planner consumes the same context for both in-memory and restored sessions; internal planning, node, tool, and stream events are excluded.

`AgentMessageDto` serializes `originalTaskId` and provides `toModel()` for rebuilding `AgentMessage`. When reading legacy JSON without `originalTaskId`, it falls back to `taskId`.

The offline example requires no database, LLM API key, or tool server:

```bash
dart run example/service_example/session_restore_example.dart
```

See [`example/service_example/session_restore_example.dart`](example/service_example/session_restore_example.dart) for a runnable persistence round-trip and restore check.

### Tool return packing

`CapabilityDto` supports `toolReturnPackMinLength` to control tool-return compression before sending content to LLM:

- `null`: use default threshold `800`
- `> 0`: enable compression when `jsonEncode(toolReturn).length >= toolReturnPackMinLength`
- `<= 0`: disable compression

Example:

```dart
CapabilityDto capabilityDto = CapabilityDto(
  llmConfig: _buildLLMConfig(),
  systemPrompt: _buildSystemPrompt(),
  openSpecList: await _buildOpenSpecList(),
  toolReturnPackMinLength: 1200, // null=>800, <=0=>off
);
```

### Skills

`CapabilityDto` and `SimpleCapabilityDto` support an optional `skills` field. Each item should be a complete `SKILL.md` string that follows the [Agent Skills specification](https://agentskills.io/specification).

Example:

```dart
CapabilityDto capabilityDto = CapabilityDto(
  llmConfig: _buildLLMConfig(),
  systemPrompt: _buildSystemPrompt(),
  skills: [
    '''
---
name: summary
description: Summarize long text and extract key decisions.
---
# Summary Skill

Focus on concise synthesis. Preserve facts, constraints, and open questions.
''',
  ],
);
```

When provided, skills are appended below `systemPrompt` in this format:

```text
<original systemPrompt>

[Skill: <skill.name>]
<skill.description>
<skill markdown body>
```

- MultiAgent support

```dart
Future<void> main() async {
  SessionDto sessionDto1 = await _buildTextAgent();
  SessionDto sessionDto2 = await _buildToolAgent();

  CapabilityDto capabilityDto = CapabilityDto(llmConfig: llmConfig, systemPrompt: systemPrompt,
      sessionList: [sessionDto1, sessionDto2]
  );

  SessionDto sessionDto = await agentService.initChat(capabilityDto, listen);

  UserTaskDto userTaskDto = UserTaskDto(contentList: [UserMessageDto(type: UserMessageDtoType.text, message: prompt)]);
  await agentService.startChat(sessionDto.id, userTaskDto);
}
```

- Reflection support

```dart
Future<void> main() async {
  CapabilityDto capabilityDto = CapabilityDto(
      llmConfig: _buildLLMConfig(),
      systemPrompt: _buildSystemPrompt(),
      openSpecList: await _buildOpenSpecList(),
      /// Add reflection prompt list here
      toolReflectionList: await _buildToolReflectionList()
  );
  SessionDto sessionDto = await agentService.initChat(capabilityDto, listen);
  String prompt = "<USER PROMPT, e.g. call any one tool>";
  UserTaskDto userTaskDto = UserTaskDto(taskId: "<Identify different tasks, NOT more than 36 chars>", contentList: [UserMessageDto(type: UserMessageDtoType.text, message: prompt)]);
  await agentService.startChat(sessionDto.id, userTaskDto);
}
```

### Method 2: ToolAgent

- According to `/example/agent_example`
- Pure native calling. Support single session.
- [Method 1 AgentService](#method-1recommend-agentservice) is friendly encapsulation for this.

```dart
Future<void> main() async {
  ToolAgent toolAgent = ToolAgent(
      llmRunner: _buildLLMRunner(),
      session: _buildSession(),
      toolRunnerList: await _buildToolRunnerList(),
      systemPrompt: _buildSystemPrompt()
  );
  String prompt = "<USER PROMPT, e.g. call any one tool>";
  toolAgent.userToAgent(taskId: "<Identify different tasks, NOT more than 36 chars>", [Content(type: ContentType.text, message: prompt)]);
}
```
