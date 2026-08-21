# LiteAgent core for dart

[English](README.md) · 中文

大模型`AI Agent`的多会话服务

## 功能

- 支持纯文本的agent，无需JSON Spec
- 支持 [OpenAPI](https://github.com/djbird2046/openapi_dart)/[OpenRPC](https://github.com/djbird2046/openrpc_dart)/[OpenModbus](https://github.com/LiteVar/openmodbus_dart)/[OpenTool](https://github.com/LiteVar/opentool_dart) 的JSON文本描述
- 支持 大模型的Function calling 到`HTTP API`/`json-rpc 2.0 over HTTP`/`Modbus`以及自定义工具的执行

## 使用

### 准备

1. 准备OpenSpec的JSON文件，可参照 `/example/json/open*/*.json` 作为样例，并且文件描述的接口真实可调用
2. 启动你的工具服务，对应的服务描述即为步骤1的JSON文件描述
3. 如果需要运行example，在 `example` 文件夹增加 `.env` 文件，并且`.env`文件需要增加如下内容：
     ```properties
     baseUrl = https://xxx.xxx.com         # 大模型接口的BaseURL
     apiKey = sk-xxxxxxxxxxxxxxxxxxxx      # 大模型接口的ApiKey
     ```
4. 使用下方的方法运行Agent服务

### 方法1（推荐）: 使用AgentService
- 例子：`/example/service_example`
- 支持多Agent会话，通过`session id`区分不同会话
- 支持同一Agent多任务，通过`taskId`区分不同任务，任务完成后才放到会话上下文供后续任务作为上下文使用

```dart
Future<void> main() async {
  CapabilityDto capabilityDto = CapabilityDto(
      llmConfig: _buildLLMConfig(),       // 大模型相关配置
      systemPrompt: _buildSystemPrompt(), // 系统提示词
      openSpecList: await _buildOpenSpecList()  // OpenSpec的接口描述
  );
  SessionDto sessionDto = await agentService.initChat(
      capabilityDto, 
      listen        // 订阅Agent与用户、客户端、大模型、工具等角色的交互消息 AgentMessage
  ); // 获得Session Id
  String prompt = "<用户消息，例如：调用某个工具>";
  UserTaskDto userTaskDto = UserTaskDto(taskId: "<用于区分不同任务，不超过36个字符>", contentList: [UserMessageDto(type: UserMessageDtoType.text, message: prompt)]);  // 用户指令支持text/imageUrl
  await agentService.startChat(sessionDto.id, userTaskDto);
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

- MultiAgent支持

```dart
Future<void> main() async {
  CapabilityDto capabilityDto = CapabilityDto(
    llmConfig: llmConfig,
    systemPrompt: systemPrompt,
    subAgentList: [
      AgentDto(
        name: 'translator',
        capability: CapabilityDto(
          llmConfig: llmConfig,
          systemPrompt: '你是翻译 Agent。',
        ),
      ),
      AgentDto(
        name: 'CRUDTools',
        capability: CapabilityDto(
          llmConfig: llmConfig,
          systemPrompt: '你是数据库工具 Agent。',
        ),
      ),
    ],
  );

  SessionDto sessionDto = await agentService.initChat(capabilityDto, listen);

  UserTaskDto userTaskDto = UserTaskDto(contentList: [UserMessageDto(type: UserMessageDtoType.text, message: prompt)]);
  await agentService.startChat(sessionDto.id, userTaskDto);
}
```

- Reflection支持

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
  String prompt = "<用户消息，例如：调用某个工具>";
  UserTaskDto userTaskDto = UserTaskDto(taskId: "<用于区分不同任务，不超过36个字符>", contentList: [UserMessageDto(type: UserMessageDtoType.text, message: prompt)]);
  await agentService.startChat(sessionDto.id, userTaskDto);
}
```

### 方法2: 使用ToolAgent

- 例子：`/example/agent_example`
- 更底层的调用，自由度更大，仅单一会话
- [方法1的AgentService](#方法1推荐-使用agentservice)是对ToolAgent的较为友好的封装

```dart
Future<void> main() async {
  ToolAgent toolAgent = ToolAgent(
      llmRunner: _buildLLMRunner(),
      session: _buildSession(),
      toolRunnerList: await _buildToolRunnerList(),
      systemPrompt: _buildSystemPrompt()
  );
  String prompt = "<用户消息，例如：调用某个工具>";
  toolAgent.userToAgent(taskId: "<用于区分不同任务，不超过36个字符>", contentList: [Content(type: ContentType.text, message: prompt)]);
}
```
