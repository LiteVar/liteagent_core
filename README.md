# LiteAgent core for dart

English · [中文](README-zh_CN.md)

LLM `AI Agent` multi sessions service.

## Features

- Support pure text agent without JSON Spec.
- Support OpenAPI, OpenRPC, OpenTool, and MCP tools.
- Support LLM function calling to HTTP, JSON-RPC, MCP, and custom tool drivers.
- Support OpenAI-compatible and Lite OneAPI LLM providers.

## Usage

The package name is `liteagent_core`. For an OpenAI-compatible endpoint, put `baseUrl` and `apiKey` in `example/.env`, then run `dart run example/agent_example/text_agent_openai_provider_example.dart`. See `text_agent_lite_oneapi_provider_example.dart` for Lite OneAPI configuration.

### AgentService

`initSession` creates a session. `startSession` submits a task and sends messages to the listener. Tool specifications and drivers are optional; add them through `CapabilityDto.openSpecList` or `initSession(customToolDriverList: ...)` when needed.

```dart
import 'package:liteagent_core/liteagent_core.dart';
import 'package:liteagent_core/liteagent_service.dart';

Future<void> main() async {
  final service = AgentService();
  final capability = CapabilityDto(
    llmConfig: LLMConfigDto(
      baseUrl: 'https://your-endpoint.example/v1',
      apiKey: 'your-api-key',
      model: 'your-model',
    ),
    systemPrompt: 'You are a helpful assistant.',
  );
  final session = await service.initSession(capability);
  await service.startSession(
    session.sessionId,
    UserTaskDto(content: [ContentDto(type: ContentType.TEXT, message: 'Hello')]),
    (sessionId, taskId, message) => print(message.toJson()),
  );
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

### Function-calling safety limits

`ToolAgent`, `MultiAgent`, and `AutoMultiAgent` enforce task-level limits so a model cannot
call tools indefinitely. The direct API accepts `ToolExecutionLimits`; `CapabilityDto`
exposes the same values as optional fields.

Default limits:

- `maxLlmRequests: 64`
- `maxToolRounds: 16`
- `maxToolCalls: 64`
- `maxConsecutiveIdenticalToolRounds: 3`
- `maxTaskDurationSeconds: 300`

Calls are considered identical when the tool name and canonical JSON arguments match;
the provider-generated function-call ID is ignored. A limit violation terminates the
task with one `TaskStatusType.EXCEPTION` status whose description contains
`code: tool_loop_limit_exceeded`.

```dart
final agent = ToolAgent(
  sessionId: sessionId,
  llmConfig: llmConfig,
  agentSession: session,
  toolDriverList: drivers,
  executionLimits: const ToolExecutionLimits(
    maxToolRounds: 8,
    maxToolCalls: 24,
    maxConsecutiveIdenticalToolRounds: 2,
  ),
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

### MultiAgent

Set `subAgentList` on the root capability to build inline child agents. Create the root session with `initSession`, then submit tasks with `startSession` as above.

```dart
final capability = CapabilityDto(
  llmConfig: llmConfigDto,
  systemPrompt: 'Coordinate the child agents.',
  subAgentList: [
    AgentDto(
      name: 'translator',
      capability: CapabilityDto(
        llmConfig: llmConfigDto,
        systemPrompt: 'You are a translator.',
      ),
    ),
  ],
);
final session = await service.initSession(capability);
```

### Direct ToolAgent API

For direct agent control, pass an `LLMConfig`, an `AgentSession`, and optional tool drivers. `userToAgent` creates the task ID and accepts `contentList`.

```dart
final agent = ToolAgent(
  sessionId: sessionId,
  llmConfig: llmConfig,
  agentSession: AgentSession(sessionId: sessionId),
  toolDriverList: drivers,
  systemPrompt: 'You are a tool assistant.',
);
await agent.userToAgent(
  contentList: [Content(type: ContentType.TEXT, message: 'Hello')],
);
```

See [`example/agent_example/tool_agent_example.dart`](example/agent_example/tool_agent_example.dart) for a complete driver setup.
