import 'dart:async';

import 'package:liteagent_core_dart/liteagent_core.dart';
import 'package:liteagent_core_dart/liteagent_service.dart';
import 'package:opentool_dart/opentool_client.dart' as ot;
import 'package:opentool_dart/opentool_schema.dart' as schema;
import 'package:test/test.dart';

void main() {
  group('OpenToolCallbackDriver', () {
    test('returns a single callback response', () async {
      late OpenToolCallbackDriver driver;
      driver = OpenToolCallbackDriver(
        _buildOpenTool(stream: false),
        (functionCall) {
          Future.microtask(() {
            driver.callback(
              ot.ToolReturn(
                id: functionCall.id,
                result: {'value': functionCall.name},
              ),
            );
          });
        },
        timeout: 1,
      );

      final result = await driver.call(_functionCall('call-1'));

      expect(result.id, 'call-1');
      expect(result.result['value'], 'test_tool');
    });

    test('keeps concurrent callback calls isolated', () async {
      late OpenToolCallbackDriver driver;
      final pendingCalls = <String>[];
      driver = OpenToolCallbackDriver(
        _buildOpenTool(stream: false),
        (functionCall) => pendingCalls.add(functionCall.id),
        timeout: 1,
      );

      final firstFuture = driver.call(_functionCall('call-1'));
      final secondFuture = driver.call(_functionCall('call-2'));

      expect(pendingCalls, ['call-1', 'call-2']);

      driver.callback(
        ot.ToolReturn(id: 'call-2', result: {'value': 'second'}),
      );
      driver.callback(
        ot.ToolReturn(id: 'call-1', result: {'value': 'first'}),
      );

      final firstResult = await firstFuture;
      final secondResult = await secondFuture;

      expect(firstResult.result['value'], 'first');
      expect(secondResult.result['value'], 'second');
    });

    test('keeps concurrent stream callbacks isolated', () async {
      final driver = OpenToolCallbackDriver(
        _buildOpenTool(stream: true),
        (_) {},
        timeout: 1,
      );
      final firstEvents = <String>[];
      final secondEvents = <String>[];

      await driver.streamCall(_functionCall('call-1'), (event, toolReturn) {
        firstEvents.add('$event:${toolReturn.result['value'] ?? toolReturn.result['done']}');
      });
      await driver.streamCall(_functionCall('call-2'), (event, toolReturn) {
        secondEvents.add('$event:${toolReturn.result['value'] ?? toolReturn.result['done']}');
      });

      driver.streamCallback(
        ot.EventType.DATA,
        ot.ToolReturn(id: 'call-2', result: {'value': 'b1'}),
      );
      driver.streamCallback(
        ot.EventType.DATA,
        ot.ToolReturn(id: 'call-1', result: {'value': 'a1'}),
      );
      driver.streamCallback(
        ot.EventType.DONE,
        ot.ToolReturn(id: 'call-2', result: {'done': 'b-done'}),
      );
      driver.streamCallback(
        ot.EventType.DONE,
        ot.ToolReturn(id: 'call-1', result: {'done': 'a-done'}),
      );

      await Future<void>.delayed(Duration.zero);

      expect(firstEvents, ['data:a1', 'done:a-done']);
      expect(secondEvents, ['data:b1', 'done:b-done']);
    });

    test('returns timeout result and clears stale callback state', () async {
      final driver = OpenToolCallbackDriver(
        _buildOpenTool(stream: false),
        (_) {},
        timeout: 1,
      );

      final result = await driver.call(_functionCall('call-timeout'));

      expect(result.id, 'call-timeout');
      expect(
        result.result['error'],
        contains('timeout after 1s'),
      );
      expect(
        driver.callback(
          ot.ToolReturn(id: 'call-timeout', result: {'value': 'late'}),
        ),
        isFalse,
      );
    });

    test('cancel clears pending state and rejects a late callback', () async {
      final driver = OpenToolCallbackDriver(
        _buildOpenTool(stream: false),
        (_) {},
        timeout: 30,
      );

      final resultFuture = driver.call(_functionCall('call-cancelled'));
      await driver.cancel('call-cancelled');
      final result = await resultFuture;

      expect(result.result['error'], contains('cancelled'));
      expect(
        driver.callback(
          ot.ToolReturn(id: 'call-cancelled', result: {'value': 'late'}),
        ),
        isFalse,
      );
    });
  });

  group('AgentService callback routing', () {
    test('routes child callback return by functionCall id even via root session', () async {
      final service = AgentService();
      final rootDriver = OpenToolCallbackDriver(
        _buildOpenTool(stream: false),
        (_) {},
        timeout: 1,
      );
      final childDriver = OpenToolCallbackDriver(
        _buildOpenTool(stream: false),
        (_) {},
        timeout: 1,
      );

      service.fetchClientDriver('root-session', rootDriver);
      service.fetchClientDriver('child-session', childDriver);

      final rootFuture = rootDriver.call(_functionCall('root-call'));
      final childFuture = childDriver.call(_functionCall('child-call'));

      service.clientDriverCallback(
        'root-session',
        ot.ToolReturn(id: 'child-call', result: {'value': 'child'}),
      );
      service.clientDriverCallback(
        'root-session',
        ot.ToolReturn(id: 'root-call', result: {'value': 'root'}),
      );

      final rootResult = await rootFuture;
      final childResult = await childFuture;

      expect(rootResult.result['value'], 'root');
      expect(childResult.result['value'], 'child');
    });

    test('released callback driver is removed from session routing', () async {
      final service = AgentService();
      final driver = OpenToolCallbackDriver(
        _buildOpenTool(stream: false),
        (_) {},
        timeout: 30,
      );
      service.fetchClientDriver('session', driver);
      final resultFuture = driver.call(_functionCall('released-call'));

      await driver.cancel('released-call');
      service.releaseClientDriver('session', driver);

      expect(
        () => service.clientDriverCallback(
          'session',
          ot.ToolReturn(id: 'released-call', result: {'value': 'late'}),
        ),
        throwsA(isA<SessionAgentNotFoundException>()),
      );
      await resultFuture;
    });
  });
}

ot.FunctionCall _functionCall(String id) {
  return ot.FunctionCall(
    id: id,
    name: 'test_tool',
    arguments: const {},
  );
}

ot.OpenTool _buildOpenTool({required bool stream}) {
  return ot.OpenTool(
    opentool: '1.0.0',
    info: schema.Info(title: 'test', version: '1.0.0'),
    functions: [
      schema.FunctionModel(
        name: 'test_tool',
        description: 'test',
        parameters: const [],
        return_: schema.Return(
          name: 'result',
          schema: schema.Schema(type: schema.SchemaType.STRING),
        ),
        stream: stream
            ? {
                ot.EventType.DATA: schema.Return(
                  name: 'data',
                  schema: schema.Schema(type: schema.SchemaType.STRING),
                ),
                ot.EventType.DONE: schema.Return(
                  name: 'done',
                  schema: schema.Schema(type: schema.SchemaType.STRING),
                ),
              }
            : null,
      ),
    ],
  );
}
