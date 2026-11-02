import 'dart:convert';
import 'dart:io';

import 'package:liteagent_core/liteagent_core.dart';
import 'package:liteagent_core/liteagent_service.dart' as service;
import 'package:opentool_dart/opentool_client.dart';
import 'package:test/test.dart';

typedef AgentDto = service.AgentDto;

void main() {
  group('CapabilityDto inline sub-agent JSON', () {
    test('serializes nested subAgentList without sessionList', () {
      final capability = _rootCapability(
        subAgentList: <AgentDto>[
          AgentDto(
            name: 'translator',
            capability: _capability('You are a translator.'),
          ),
          AgentDto(
            name: 'database',
            capability: _capability(
              'You are a database agent.',
              subAgentList: <AgentDto>[
                AgentDto(
                  name: 'query',
                  capability: _capability('You query databases.'),
                ),
              ],
            ),
          ),
        ],
      );

      final json = capability.toJson();

      expect(json['sessionList'], isNull);
      expect(json['subAgentList'], hasLength(2));
      expect(
        (json['subAgentList'] as List<dynamic>)[1]['capability']['subAgentList'],
        hasLength(1),
      );
    });

    test('deserializes nested subAgentList recursively', () {
      final capability = service.CapabilityDto.fromJson(<String, dynamic>{
        'systemPrompt': 'root',
        'subAgentList': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'database',
            'capability': <String, dynamic>{
              'systemPrompt': 'database',
              'subAgentList': <Map<String, dynamic>>[
                <String, dynamic>{
                  'name': 'query',
                  'capability': <String, dynamic>{
                    'systemPrompt': 'query',
                  },
                },
              ],
            },
          },
        ],
      });

      expect(capability.subAgentList, hasLength(1));
      expect(
        capability.subAgentList!.single.capability.subAgentList!.single.name,
        'query',
      );
    });
  });

  group('AgentService inline sub-agent tree', () {
    test('creates child sessionIds internally and builds nested agent types', () async {
      final agentService = service.AgentService();
      final root = await agentService.initSession(
        _rootCapability(
          subAgentList: <AgentDto>[
            AgentDto(
              name: 'text',
              capability: _capability('text child'),
            ),
            AgentDto(
              name: 'tool',
              capability: _capability(
                'tool child',
                openSpecList: <service.OpenSpecDto>[
                  service.OpenSpecDto(
                    openSpec: _minimalOpenTool,
                    protocol: service.Protocol.OPENTOOL,
                    serverUrl: 'http://localhost',
                  ),
                ],
              ),
            ),
            AgentDto(
              name: 'nested',
              capability: _capability(
                'nested child',
                subAgentList: <AgentDto>[
                  AgentDto(
                    name: 'leaf',
                    capability: _capability('leaf child'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

      final tree = agentService.getSessionTree(root.sessionId);
      final childIds = agentService.getSubSessionIds(root.sessionId);

      expect(tree, hasLength(5));
      expect(childIds, hasLength(4));
      expect(tree.first.sessionId, root.sessionId);
      expect(tree.first.parentSessionId, isNull);
      expect(tree.first.isInlineChild, isFalse);
      expect(tree.where((info) => info.name == 'text').single.isInlineChild, isTrue);
      expect(tree.where((info) => info.name == 'tool').single.isInlineChild, isTrue);
      expect(tree.where((info) => info.name == 'leaf').single.parentSessionId, isNotNull);

      expect(agentService.getSessionAgent(root.sessionId), isA<MultiAgent>());
      final textId = tree.where((info) => info.name == 'text').single.sessionId;
      final toolId = tree.where((info) => info.name == 'tool').single.sessionId;
      final nestedId = tree.where((info) => info.name == 'nested').single.sessionId;
      final leafId = tree.where((info) => info.name == 'leaf').single.sessionId;
      expect(agentService.getSessionAgent(textId), isA<TextAgent>());
      expect(agentService.getSessionAgent(toolId), isA<ToolAgent>());
      expect(agentService.getSessionAgent(nestedId), isA<MultiAgent>());
      expect(agentService.getSessionAgent(leafId), isA<TextAgent>());
    });

    test('uses the child systemPrompt as a 1024-character description', () async {
      final longPrompt = 'x' * 1100;
      final agentService = service.AgentService();
      final root = await agentService.initSession(
        _rootCapability(
          subAgentList: <AgentDto>[
            AgentDto(
              name: 'long_prompt',
              capability: _capability(longPrompt),
            ),
          ],
        ),
      );
      final multiAgent = agentService.getSessionAgent(root.sessionId)! as MultiAgent;
      final driver = multiAgent.subAgentDriverList.single as SessionAgentDriver;
      final function = driver.parse().single;

      expect(function.description, longPrompt.substring(0, 1024));
      expect(function.description.length, 1024);
    });

    test('routes function calls to inline TextAgent and ToolAgent', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await request.drain();
        request.response.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.response.write(jsonEncode(<String, dynamic>{
          'id': 'inline-test',
          'created': 0,
          'choices': <Map<String, dynamic>>[
            <String, dynamic>{
              'index': 0,
              'message': <String, dynamic>{
                'role': 'assistant',
                'content': 'inline response',
              },
              'finish_reason': 'stop',
            },
          ],
          'usage': <String, dynamic>{
            'prompt_tokens': 1,
            'completion_tokens': 1,
            'total_tokens': 2,
          },
        }));
        await request.response.close();
      });

      try {
        final llmConfig = service.LLMConfigDto(
          baseUrl: 'http://${server.address.host}:${server.port}/v1',
          model: 'test-model',
        );
        final agentService = service.AgentService();
        final root = await agentService.initSession(
          _rootCapability(
            subAgentList: <AgentDto>[
              AgentDto(
                name: 'text',
                capability: _capability(
                  'text child',
                  llmConfig: llmConfig,
                ),
              ),
              AgentDto(
                name: 'tool',
                capability: _capability(
                  'tool child',
                  llmConfig: llmConfig,
                  openSpecList: <service.OpenSpecDto>[
                    service.OpenSpecDto(
                      openSpec: _minimalOpenTool,
                      protocol: service.Protocol.OPENTOOL,
                      serverUrl: 'http://localhost',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
        final multiAgent = agentService.getSessionAgent(root.sessionId)! as MultiAgent;
        final driver = multiAgent.subAgentDriverList.single as SessionAgentDriver;

        final textReturn = await driver.callAgent(
          FunctionCall(
            id: 'text-call',
            name: 'text',
            arguments: <String, dynamic>{'prompt': 'hello'},
          ),
          'root-task',
        );
        final toolReturn = await driver.callAgent(
          FunctionCall(
            id: 'tool-call',
            name: 'tool',
            arguments: <String, dynamic>{'prompt': 'hello'},
          ),
          'root-task',
        );

        expect(textReturn.result['result'], 'inline response');
        expect(toolReturn.result['result'], 'inline response');
      } finally {
        await server.close(force: true);
      }
    });

    test('rejects invalid inline child names with FormatException', () async {
      final agentService = service.AgentService();

      await expectLater(
        agentService.initSession(
          _rootCapability(
            subAgentList: <AgentDto>[
              AgentDto(
                name: 'not valid',
                capability: _capability('child'),
              ),
            ],
          ),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(agentService.sessionAgents, isEmpty);
      expect(agentService.sessionCreateTimeMap, isEmpty);
    });

    test('rejects duplicate sibling names with FormatException', () async {
      final agentService = service.AgentService();

      await expectLater(
        agentService.initSession(
          _rootCapability(
            subAgentList: <AgentDto>[
              AgentDto(name: 'same', capability: _capability('one')),
              AgentDto(name: 'same', capability: _capability('two')),
            ],
          ),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(agentService.sessionAgents, isEmpty);
    });

    test('rolls back all created agents when a child fails', () async {
      final agentService = service.AgentService();

      await expectLater(
        agentService.initSession(
          _rootCapability(
            subAgentList: <AgentDto>[
              AgentDto(name: 'good', capability: _capability('good')),
              AgentDto(
                name: 'bad',
                capability: _capability(
                  'bad',
                  openSpecList: <service.OpenSpecDto>[
                    service.OpenSpecDto(
                      openSpec: '{not-json',
                      protocol: service.Protocol.OPENTOOL,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        throwsA(anything),
      );

      expect(agentService.sessionAgents, isEmpty);
      expect(agentService.simpleAgents, isEmpty);
      expect(agentService.sessionCreateTimeMap, isEmpty);
      expect(agentService.getSessionTree('missing'), isEmpty);
    });

    test('rejects inline children for AutoMultiAgent explicitly', () async {
      final agentService = service.AgentService();

      await expectLater(
        agentService.initSession(
          service.CapabilityDto(
            systemPrompt: 'auto root',
            auto: true,
            subAgentList: <AgentDto>[
              AgentDto(name: 'child', capability: _capability('child')),
            ],
          ),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(agentService.sessionAgents, isEmpty);
    });

    test('returns isolated runtime info and clears the whole root tree', () async {
      final agentService = service.AgentService();
      final root = await agentService.initSession(
        _rootCapability(
          subAgentList: <AgentDto>[
            AgentDto(
              name: 'child',
              capability: _capability('child'),
            ),
          ],
        ),
      );
      final tree = agentService.getSessionTree(root.sessionId);
      final childId = tree[1].sessionId;

      tree.first.capability.systemPrompt = 'mutated outside service';
      expect(
        agentService.getSessionTree(root.sessionId).first.capability.systemPrompt,
        'root',
      );

      await agentService.clearSession(root.sessionId);

      expect(agentService.sessionAgents, isEmpty);
      expect(agentService.sessionCreateTimeMap, isEmpty);
      expect(agentService.getSubSessionIds(root.sessionId), isEmpty);
      expect(agentService.getSessionTree(root.sessionId), isEmpty);
      expect(agentService.getSessionAgent(childId), isNull);
    });
  });
}

service.CapabilityDto _rootCapability({List<AgentDto>? subAgentList}) {
  return service.CapabilityDto(
    systemPrompt: 'root',
    subAgentList: subAgentList,
  );
}

service.CapabilityDto _capability(
  String systemPrompt, {
  List<AgentDto>? subAgentList,
  List<service.OpenSpecDto>? openSpecList,
  service.LLMConfigDto? llmConfig,
}) {
  return service.CapabilityDto(
    systemPrompt: systemPrompt,
    subAgentList: subAgentList,
    openSpecList: openSpecList,
    llmConfig: llmConfig,
  );
}

const String _minimalOpenTool = '''
{
  "opentool": "1.0.0",
  "info": {"title": "Test tool", "version": "1.0.0"},
  "functions": [
    {"name": "ping", "description": "Ping", "parameters": []}
  ]
}
''';
