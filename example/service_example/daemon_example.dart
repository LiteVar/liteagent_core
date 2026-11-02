import 'package:liteagent_core/liteagent_service.dart';
import 'package:opentool_daemon/opentool_daemon_client.dart';
import 'package:opentool_dart/opentool_client.dart';

/// Demonstrates how to inspect and control OpenTool Daemon resources.
///
/// Preparation:
/// 1. Start the OpenTool Daemon locally (`opentool-daemon serve`).
/// 2. Set [daemonApiKey] when the example should list tool API keys.

String daemonApiKey = '';
Future<void> main() async {
  final String daemonHost = HostType.LOCALHOST;
  final int daemonPort = DAEMON_DEFAULT_PORT;

  final daemonService = DaemonService(host: daemonHost, port: daemonPort);
  print('[daemon] Connecting to $daemonHost:$daemonPort');

  final servers = await _listServers(daemonService);
  if (servers.isNotEmpty) {
    final server = servers.first;
    final result = await daemonService.runServer(
      server.id,
      hostType: HostType.LOCALHOST,
      timeoutSeconds: 30,
    );
    _logCommandResult('[runServer]', result);
  }

  final tools = await _listTools(daemonService);
  if (tools.isNotEmpty) {
    await _startToolOnce(daemonService, tools.first.id);
  }

  if (daemonApiKey.isNotEmpty) {
    await _listToolsWithApiKeys(daemonService, daemonApiKey);
  } else {
    print('[apiKey] Skipped.');
  }
}

Future<List<OpenToolServerDto>> _listServers(
  DaemonService daemonService,
) async {
  final servers = await daemonService.getServers();
  if (servers.isEmpty) {
    print(
      '[servers] No server artifacts found. Use opentool-daemon CLI to pull.',
    );
  } else {
    print('[servers] ${servers.length} available:');
    for (final server in servers) {
      print(
        '  - ${server.alias} (${server.id}) '
        '${server.registry}/${server.namespace}/${server.name}:'
        '${server.version}',
      );
    }
  }
  return servers;
}

Future<List<ToolDto>> _listTools(DaemonService daemonService) async {
  final tools = await daemonService.getTools(includeAllHosts: true);
  if (tools.isEmpty) {
    print('[tools] No tools are registered yet.');
  } else {
    print('[tools] ${tools.length} known tool(s):');
    for (final tool in tools) {
      print(
        '  - ${tool.alias} (${tool.id}) ${tool.host}:${tool.port} '
        '[${tool.status}]',
      );
    }
  }
  return tools;
}

Future<void> _startToolOnce(DaemonService daemonService, String toolId) async {
  print('[startTool] Booting $toolId');
  await daemonService.startTool(
    toolId,
    timeoutSeconds: 60,
    onLog: (CommandResultDto chunk) {
      final output = chunk.output ?? chunk.error;
      if (output != null && output.isNotEmpty) {
        print('  ${chunk.command}: $output');
      }
    },
    onError: (CommandResultDto error) {
      print('  ${error.command}: ${error.error ?? 'Tool startup failed'}');
    },
  );
  print('[startTool] $toolId is ready');

  final stopResult = await daemonService.stopTool(toolId);
  print('[stopTool] Stopped ${stopResult.id}');
}

Future<void> _listToolsWithApiKeys(
  DaemonService daemonService,
  String daemonApiKey,
) async {
  final tools = await daemonService.getToolsWithApiKeys(
    daemonApiKey: daemonApiKey,
    includeAllHosts: true,
  );
  if (tools.isEmpty) {
    print('[apiKey] No tool API keys returned.');
    return;
  }
  print('[apiKey] ${tools.length} tool(s) expose keys:');
  for (final tool in tools) {
    print(
      '  - ${tool.alias} (${tool.id}) key=${tool.apiKey} '
      '@ ${tool.host}:${tool.port}',
    );
  }
}

void _logCommandResult(String label, CommandResultDto result) {
  final buffer = StringBuffer()
    ..writeln('$label ${result.command}')
    ..writeln('  output: ${result.output ?? '-'}');
  if (result.error != null && result.error!.isNotEmpty) {
    buffer.writeln('  error: ${result.error}');
  }
  print(buffer.toString());
}
