import 'package:opentool_dart/opentool_client.dart';

import 'opentool_driver.dart';

class OpenToolClientDriver extends OpenToolDriver {
  late Client client;
  String? apiKey;

  OpenToolClientDriver(OpenTool opentool, {this.apiKey}): super(opentool) {
    if( opentool.server == null) {
      throw Exception("OpenToolServer is null");
    }
    String url = opentool.server!.url;
    Uri uri = Uri.parse(url);
    bool ssl = uri.scheme == "https";
    String host = uri.host;
    int port = uri.port;
    client = OpenToolClient(isSSL: ssl, toolHost: host, toolPort: port, toolApiKey: apiKey);
  }

  @override
  Future<ToolReturn> call(FunctionCall functionCall) async {
    return await client.call(functionCall);
  }

  @override
  Future<void> streamCall(
    FunctionCall functionCall,
    void Function(String event, ToolReturn toolReturn) onStream,
  ) async {
    return await client.streamCall(functionCall, onStream);
  }
}
