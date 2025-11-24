import 'package:opentool_dart/opentool_client.dart' as ot;
import 'jsonrpc_http_util.dart';
import 'package:openrpc_dart/openrpc_dart.dart';
import 'openrpc_driver.dart';

class JsonRPCDriver extends OpenRPCDriver {
  JsonRPCDriver(super.openRPC);

  @override
  Future<ot.ToolReturn> call(ot.FunctionCall functionCall) async {
    JsonRPCHttpRequestBody jsonRPCHttpRequestBody = JsonRPCHttpRequestBody(
      method: functionCall.name,
      params: functionCall.arguments,
      id: functionCall.id
    );
    JsonRPCHttpRequest jsonRPCHttpRequest = JsonRPCHttpRequest(url: openRPC.servers!.first.url, body: jsonRPCHttpRequestBody);
    JsonRPCHttpResponse jsonRPCHttpResponse = await requestJsonRPCHttpAPI(jsonRPCHttpRequest);
    return ot.ToolReturn(id: functionCall.id, result: jsonRPCHttpResponse.toJson());
  }

  @override
  bool hasFunction(String functionName) {
    return openRPC.methods.any((Method method) => method.name == functionName);
  }
}
