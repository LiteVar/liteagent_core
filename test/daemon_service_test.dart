import 'dart:async';
import 'dart:io';

import 'package:liteagent_core/liteagent_service.dart';
import 'package:opentool_daemon/opentool_daemon_client.dart';
import 'package:test/test.dart';

void main() {
  group('DaemonService startTool', () {
    test('waits for the terminal DONE event', () async {
      final releaseDone = Completer<void>();
      final requestReceived = Completer<Uri>();
      final server = await _serve((request) async {
        requestReceived.complete(request.uri);
        _prepareEventStream(request.response);
        request.response.write(
          'event:data\ndata:{"command":"startTool","output":"starting"}\n\n',
        );
        await request.response.flush();
        await releaseDone.future;
        request.response.write(
          'event:done\ndata:{"command":"startTool","output":"ready"}\n\n',
        );
        await request.response.close();
      });

      try {
        final logs = <String?>[];
        var completed = false;
        final start =
            DaemonService(host: server.address.host, port: server.port)
                .startTool(
                  'tool-1',
                  timeoutSeconds: 30,
                  onLog: (result) => logs.add(result.output),
                )
                .then((_) => completed = true);

        final uri = await requestReceived.future;
        expect(uri.path, '/opentool-daemon/tools/tool-1/start');
        expect(uri.queryParameters['timeout'], '30');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(completed, isFalse);

        releaseDone.complete();
        await start;

        expect(completed, isTrue);
        expect(logs, ['starting']);
      } finally {
        if (!releaseDone.isCompleted) releaseDone.complete();
        await server.close(force: true);
      }
    });

    test('propagates a terminal ERROR and reports its payload', () async {
      final server = await _serve((request) async {
        _prepareEventStream(request.response);
        request.response.write(
          'event:error\ndata:{"command":"startTool","error":"boom"}\n\n',
        );
        await request.response.close();
      });

      try {
        CommandResultDto? callbackError;
        final start = DaemonService(
          host: server.address.host,
          port: server.port,
        ).startTool('tool-1', onError: (error) => callbackError = error);

        await expectLater(
          start,
          throwsA(
            isA<DaemonApiException>().having(
              (error) => error.code,
              'code',
              'TOOL_START_FAILED',
            ),
          ),
        );
        expect(callbackError?.error, 'boom');
      } finally {
        await server.close(force: true);
      }
    });

    test('rejects a stream that closes before a terminal event', () async {
      final server = await _serve((request) async {
        _prepareEventStream(request.response);
        request.response.write(
          'event:data\ndata:{"command":"startTool","output":"starting"}\n\n',
        );
        await request.response.close();
      });

      try {
        final start = DaemonService(
          host: server.address.host,
          port: server.port,
        ).startTool('tool-1');

        await expectLater(start, throwsA(isA<SseProtocolException>()));
      } finally {
        await server.close(force: true);
      }
    });
  });
}

Future<HttpServer> _serve(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  return server;
}

void _prepareEventStream(HttpResponse response) {
  response.headers.contentType = ContentType('text', 'event-stream');
  response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
}
