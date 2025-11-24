import 'dart:async';
import 'package:opentool_daemon/opentool_daemon_client.dart';
import 'package:opentool_dart/opentool_client.dart';

class DaemonService {
  final DaemonClient _client;

  DaemonService(
      {String host = HostType.LOCALHOST, int port = DAEMON_DEFAULT_PORT})
      : _client = DaemonClient(host: host, port: port);

  Future<List<OpenToolServerDto>> getServers() {
    return _client.listServer();
  }

  Future<CommandResultDto> runServer(
    String serverId, {
    String? hostType,
    int timeoutSeconds = -1,
  }) {
    return _client.runServer(
      serverId,
      hostType,
      timeoutSeconds: timeoutSeconds,
    );
  }

  Future<List<ToolWithApiKeyDto>> getToolsWithApiKeys({
    required String daemonApiKey,
    bool includeAllHosts = false,
  }) {
    final String? allParam = includeAllHosts ? '1' : null;
    return _client.listToolWithApiKeys(allParam, daemonApiKey: daemonApiKey);
  }

  Future<List<ToolDto>> getTools({bool includeAllHosts = false}) {
    final String? allParam = includeAllHosts ? '1' : null;
    return _client.listTool(allParam);
  }

  Future<CommandResultDto> startTool(
    String toolId, {
    int timeoutSeconds = -1,
    void Function(CommandResultDto log)? onLog,
  }) async {
    final completer = Completer<CommandResultDto>();
    _client.startTool(
      toolId,
      timeoutSeconds: timeoutSeconds,
      onData: (CommandResultDto chunk) {
        onLog?.call(chunk);
      },
      onError: (CommandResultDto result) {
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      },
      onStreamError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    return completer.future;
  }

  Future<ToolIdDto> stopTool(String toolId) {
    return _client.stopTool(toolId);
  }
}
