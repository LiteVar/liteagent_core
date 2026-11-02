# LiteAgent core for dart

[English](README.md) · 中文

大模型`AI Agent`的多会话服务

## 功能

- 支持纯文本的agent，无需JSON Spec
- 支持 OpenAPI、OpenRPC、OpenTool 和 MCP 工具
- 支持通过 HTTP、JSON-RPC、MCP 及自定义驱动执行大模型工具调用
- 支持 OpenAI 兼容接口和 Lite OneAPI 大模型服务

## 使用

包名为 `liteagent_core_dart`。使用 OpenAI 兼容接口时，在 `example/.env` 中配置 `baseUrl` 和 `apiKey`，然后运行 `dart run example/agent_example/text_agent_openai_provider_example.dart`。Lite OneAPI 的配置可参考 `text_agent_lite_oneapi_provider_example.dart`。

### AgentService

`initSession` 创建会话，`startSession` 提交任务并通过监听器返回消息。需要工具时，可通过 `CapabilityDto.openSpecList` 或 `initSession(customToolDriverList: ...)` 提供工具描述与驱动。

```dart
import 'package:liteagent_core_dart/liteagent_core.dart';
import 'package:liteagent_core_dart/liteagent_service.dart';

Future<void> main() async {
  final service = AgentService();
  final capability = CapabilityDto(
    llmConfig: LLMConfigDto(
      baseUrl: 'https://your-endpoint.example/v1',
      apiKey: 'your-api-key',
      model: 'your-model',
    ),
    systemPrompt: '你是一名助手。',
  );
  final session = await service.initSession(capability);
  await service.startSession(
    session.sessionId,
    UserTaskDto(content: [ContentDto(type: ContentType.TEXT, message: '你好')]),
    (sessionId, taskId, message) => print(message.toJson()),
  );
}
```

### 恢复持久化会话运行态

`AgentService.initSession` 新增可选参数 `SessionRestoreState`，用于恢复因空闲超时、服务重启等原因从内存中消失的 Session。普通创建会话时不要传该参数，core 会继续自动生成新的 Session ID，原有行为不变。

数据库持久化、Session 删除状态和业务过期判断由上层服务负责。本包不依赖 SQLite、Drift 或其他数据库实现。

```dart
// 从上层持久化实现读取已完成任务的上下文 DTO。
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

恢复行为与数据约束：

- `contextMessages` 必须按原始消息顺序传入，并且只包含已完成任务的上下文。
- 未完成的工具调用、流式 chunk、等待 callback 的任务不能用于恢复。
- Assistant 的 `tool_calls` 与工具返回消息必须完整配对。
- 上下文会通过 defensive copy 写入 `AgentSession.taskDoneAgentMessageList`，不会重新执行历史任务、触发消息监听器、产生流事件或重新广播历史消息。
- `hasSystemMessage` 会根据恢复的 developer/system 消息自动推导，下一轮不会重复添加 system prompt。
- `sessionSummary` 和 `summaryMessageCount` 会被重置；后续需要时可由 core 重新生成摘要。
- 如果相同 ID 的运行态 Session 已存在，会抛出 `SessionAlreadyExistsException`，不会覆盖原 Session。
- MultiAgent 的根 Session 上下文独立恢复；需要恢复的子 Session 应由上层分别恢复。
- AutoMultiAgent 只把每轮已完成的用户指令和最终回答作为跨轮上下文。无论上下文来自内存还是外部恢复，下一轮 Planner 都会使用同一份上下文；内部规划、节点、工具及流事件不会进入跨轮上下文。

`AgentMessageDto` 会序列化 `originalTaskId`，并提供 `toModel()` 用于重建 `AgentMessage`。读取缺少 `originalTaskId` 的旧 JSON 时，会自动回退到 `taskId`。

以下离线示例不需要数据库、LLM API Key 或工具服务：

```bash
dart run example/service_example/session_restore_example.dart
```

完整的持久化往返与恢复检查请参考 [`example/service_example/session_restore_example.dart`](example/service_example/session_restore_example.dart)。

### Tool返回压缩

`CapabilityDto` 支持 `toolReturnPackMinLength`，用于控制发送给大模型前的 tool 返回压缩：

- `null`：使用默认阈值 `800`
- `> 0`：当 `jsonEncode(toolReturn).length >= toolReturnPackMinLength` 时启用压缩
- `<= 0`：关闭压缩

示例：

```dart
CapabilityDto capabilityDto = CapabilityDto(
  llmConfig: _buildLLMConfig(),
  systemPrompt: _buildSystemPrompt(),
  openSpecList: await _buildOpenSpecList(),
  toolReturnPackMinLength: 1200, // null=>800, <=0=>关闭
);
```

### Function calling 安全限制

`ToolAgent`、`MultiAgent` 和 `AutoMultiAgent` 会执行 task 级别的安全限制，避免模型无限调用工具。直接使用 Agent API 时可传入 `ToolExecutionLimits`；通过 `AgentService` 使用时，可在 `CapabilityDto` 中设置对应的可选字段。

默认限制：

- `maxLlmRequests: 64`
- `maxToolRounds: 16`
- `maxToolCalls: 64`
- `maxConsecutiveIdenticalToolRounds: 3`
- `maxTaskDurationSeconds: 300`

当工具名称及规范化后的 JSON 参数相同时，两次调用会被视为相同调用；模型服务生成的 function-call ID 不参与比较。超过任意限制后，当前 task 会终止，并且只产生一个 `TaskStatusType.EXCEPTION` 状态，其 description 中包含 `code: tool_loop_limit_exceeded`。

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

`CapabilityDto` 和 `SimpleCapabilityDto` 支持可选的 `skills` 字段。每个元素都应该是一份完整的 `SKILL.md` 文本，并遵循 [Agent Skills specification](https://agentskills.io/specification)。

示例：

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

启用后，skills 会按下面的格式追加到 `systemPrompt` 下方：

```text
<原有 systemPrompt>

[Skill: <skill.name>]
<skill.description>
<skill 的 markdown 正文>
```

### MultiAgent

在根 `CapabilityDto` 中设置 `subAgentList` 来创建内联子 Agent。通过 `initSession` 创建根会话，再按上面的方式调用 `startSession`。

```dart
final capability = CapabilityDto(
  llmConfig: llmConfigDto,
  systemPrompt: '协调子 Agent。',
  subAgentList: [
    AgentDto(
      name: 'translator',
      capability: CapabilityDto(
        llmConfig: llmConfigDto,
        systemPrompt: '你是一名翻译助手。',
      ),
    ),
  ],
);
final session = await service.initSession(capability);
```

### 直接使用 ToolAgent

直接使用 Agent API 时，传入 `LLMConfig`、`AgentSession` 和可选的工具驱动。`userToAgent` 会生成任务 ID，并接收 `contentList`。

```dart
final agent = ToolAgent(
  sessionId: sessionId,
  llmConfig: llmConfig,
  agentSession: AgentSession(sessionId: sessionId),
  toolDriverList: drivers,
  systemPrompt: '你是一名工具助手。',
);
await agent.userToAgent(
  contentList: [Content(type: ContentType.TEXT, message: '你好')],
);
```

完整的工具驱动设置见 [`example/agent_example/tool_agent_example.dart`](example/agent_example/tool_agent_example.dart)。
