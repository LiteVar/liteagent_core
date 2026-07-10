import 'dart:convert';

import 'package:liteagent_core_dart/liteagent_core.dart';
import 'package:liteagent_core_dart/liteagent_service.dart';
import 'package:opentool_dart/opentool_client.dart';
import 'package:test/test.dart';

void main() {
  group('AgentMessageDto', () {
    test('preserves task relationships and tool-call content on round trip',
        () {
      final createTime = DateTime.utc(2026, 7, 10, 1, 2, 3);
      final model = AgentMessage(
        sessionId: 'session',
        agentId: 'agent',
        originalTaskId: 'original-task',
        parentTaskId: 'parent-task',
        taskId: 'task',
        role: AgentRoleType.LLM,
        to: AgentRoleType.AGENT,
        type: AgentMessageType.TOOL_CALLS,
        content: <FunctionCall>[
          FunctionCall(
            id: 'call-1',
            name: 'weather',
            arguments: <String, dynamic>{'city': 'Shanghai'},
          ),
        ],
        reasoningContent: 'reasoning',
        completions: Completions(
          tokenUsage: TokenUsage(
            promptTokens: 10,
            completionTokens: 5,
            totalTokens: 15,
            contextUsageRatio: 0.25,
          ),
          id: 'completion',
          model: 'model',
          limits: CompletionsLimits(
            maxTokens: 100,
            contextWindowSize: 200,
          ),
        ),
      )..createTime = createTime;

      final dto = AgentMessageDto.fromModel(model);
      final json = jsonDecode(jsonEncode(dto.toJson())) as Map<String, dynamic>;
      final restored = AgentMessageDto.fromJson(json).toModel();
      final calls = restored.content as List<FunctionCall>;

      expect(json['originalTaskId'], 'original-task');
      expect(restored.originalTaskId, 'original-task');
      expect(restored.taskId, 'task');
      expect(restored.parentTaskId, 'parent-task');
      expect(restored.type, AgentMessageType.TOOL_CALLS);
      expect(restored.role, AgentRoleType.LLM);
      expect(restored.reasoningContent, 'reasoning');
      expect(restored.createTime, createTime);
      expect(calls, hasLength(1));
      expect(calls.single.id, 'call-1');
      expect(calls.single.name, 'weather');
      expect(calls.single.arguments, <String, dynamic>{'city': 'Shanghai'});
      expect(restored.completions?.id, 'completion');
      expect(restored.completions?.tokenUsage.totalTokens, 15);
      expect(restored.completions?.limits?.contextWindowSize, 200);
    });

    test('falls back to taskId for legacy JSON', () {
      final json = <String, dynamic>{
        'sessionId': 'session',
        'parentTaskId': 'parent',
        'taskId': 'legacy-task',
        'role': AgentRoleType.USER,
        'to': AgentRoleType.AGENT,
        'type': AgentMessageType.CONTENT_LIST,
        'content': <Map<String, dynamic>>[
          <String, dynamic>{'type': ContentType.TEXT, 'message': 'hello'},
        ],
        'createTime': '2026-07-10T01:02:03.000Z',
      };

      final dto = AgentMessageDto.fromJson(json);
      final restored = dto.toModel();
      final content = restored.content as List<Content>;

      expect(dto.originalTaskId, 'legacy-task');
      expect(restored.originalTaskId, 'legacy-task');
      expect(restored.taskId, 'legacy-task');
      expect(restored.parentTaskId, 'parent');
      expect(restored.type, AgentMessageType.CONTENT_LIST);
      expect(content.single.type, ContentType.TEXT);
      expect(content.single.message, 'hello');
    });

    test('converts all remaining structured content types', () {
      final functionCall = _roundTripContent(
        AgentMessageType.FUNCTION_CALL,
        FunctionCall(
          id: 'function-call',
          name: 'lookup',
          arguments: <String, dynamic>{'key': 'value'},
        ),
      ) as FunctionCall;
      expect(functionCall.name, 'lookup');
      expect(functionCall.arguments, <String, dynamic>{'key': 'value'});

      final toolReturn = _roundTripContent(
        AgentMessageType.TOOL_RETURN,
        ToolReturn(
          id: 'function-call',
          result: <String, dynamic>{'answer': 42},
        ),
      ) as ToolReturn;
      expect(toolReturn.id, 'function-call');
      expect(toolReturn.result, <String, dynamic>{'answer': 42});

      final taskStatus = _roundTripContent(
        AgentMessageType.TASK_STATUS,
        TaskStatus(
          status: TaskStatusType.DONE,
          taskId: 'task',
          description: <String, dynamic>{'result': 'done'},
        ),
      ) as TaskStatus;
      expect(taskStatus.status, TaskStatusType.DONE);
      expect(taskStatus.taskId, 'task');
      expect(taskStatus.description, <String, dynamic>{'result': 'done'});

      final reflection = _roundTripContent(
        AgentMessageType.REFLECTION,
        Reflection(
          isPass: true,
          messageScore: MessageScore(
            contentList: <Content>[
              Content(type: ContentType.TEXT, message: 'answer'),
            ],
            messageType: AgentMessageType.TEXT,
            message: 'answer',
            reflectScoreList: <ReflectScore>[
              ReflectScore(score: 9, description: 'good'),
            ],
          ),
          passScore: 8,
          count: 1,
          maxCount: 3,
        ),
      ) as Reflection;
      expect(reflection.isPass, isTrue);
      expect(reflection.messageScore.contentList.single.message, 'answer');
      expect(reflection.messageScore.reflectScoreList.single.score, 9);
    });
  });
}

dynamic _roundTripContent(String type, dynamic content) {
  final model = AgentMessage(
    sessionId: 'session',
    originalTaskId: 'original-task',
    parentTaskId: null,
    taskId: 'task',
    role: AgentRoleType.LLM,
    to: AgentRoleType.AGENT,
    type: type,
    content: content,
  );
  final json = jsonDecode(
    jsonEncode(AgentMessageDto.fromModel(model).toJson()),
  ) as Map<String, dynamic>;
  return AgentMessageDto.fromJson(json).toModel().content;
}
