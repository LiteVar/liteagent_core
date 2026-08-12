import 'package:opentool_daemon/opentool_daemon_client.dart';
import 'package:opentool_dart/opentool_client.dart';

class DaemonService {
  final DaemonClient _client;

  DaemonService({
    String host = HostType.LOCALHOST,
    int port = DAEMON_DEFAULT_PORT,
  }) : _client = DaemonClient(host: host, port: port);

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

  /// Starts a tool and completes only after the daemon reports that it is ready.
  ///
  /// Startup failures are reported through [onError] and are also propagated by
  /// the returned future as a [DaemonApiException].
  Future<void> startTool(
    String toolId, {
    int timeoutSeconds = -1,
    void Function(CommandResultDto log)? onLog,
    void Function(CommandResultDto error)? onError,
  }) {
    return _client.startTool(
      toolId,
      timeoutSeconds: timeoutSeconds,
      onData: (CommandResultDto chunk) => onLog?.call(chunk),
      onError: (CommandResultDto error) => onError?.call(error),
    );
  }

  Future<ToolIdDto> stopTool(String toolId) {
    return _client.stopTool(toolId);
  }
}
