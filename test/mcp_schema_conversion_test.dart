import 'package:liteagent_core_dart/src/core/driver/mcp/mcp_base_driver.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:opentool_dart/opentool_client.dart' as ot;
import 'package:test/test.dart';

class _TestDriver extends McpBaseDriver {
  @override
  Future<ot.ToolReturn> call(ot.FunctionCall functionCall) async {
    return ot.ToolReturn(
      id: functionCall.id,
      result: const <String, dynamic>{},
    );
  }
}

void main() {
  group('McpBaseDriver schema conversion', () {
    test('converts object input schema properties to parameters', () {
      final driver = _TestDriver();
      final schema = JsonObject(
        properties: <String, JsonSchema>{
          'q': JsonSchema.string(description: 'query'),
          'limit': JsonSchema.integer(description: 'limit'),
          'tags': JsonSchema.array(
            items: JsonSchema.string(),
            description: 'tags',
          ),
        },
        required: const ['q'],
      );

      final params = driver.convertToolInputSchemaToParameters(schema);

      expect(
        params.map((p) => p.name),
        containsAll(<String>['q', 'limit', 'tags']),
      );

      final q = params.firstWhere((p) => p.name == 'q');
      expect(q.required, isTrue);
      expect(q.schema.type, ot.SchemaType.STRING);
      expect(q.description, 'query');

      final tags = params.firstWhere((p) => p.name == 'tags');
      expect(tags.schema.type, ot.SchemaType.ARRAY);
      expect(tags.schema.items, isNotNull);
      expect(tags.schema.items!.type, ot.SchemaType.STRING);
    });

    test('converts string enum to opentool enum', () {
      final driver = _TestDriver();
      final schema = JsonSchema.string(
        description: 'mode',
        enumValues: const ['a', 'b'],
      );

      final otSchema = driver.convertJsonSchemaToOtSchema(schema);
      expect(otSchema.type, ot.SchemaType.STRING);
      expect(otSchema.enum_, const ['a', 'b']);
    });

    test('converts const schema values', () {
      final driver = _TestDriver();
      final schema = JsonConst('fixed', description: 'fixed value');

      final otSchema = driver.convertJsonSchemaToOtSchema(schema);
      expect(otSchema.type, ot.SchemaType.STRING);
      expect((otSchema.toJson() as Map)['const'], 'fixed');
      expect(otSchema.description, 'fixed value');
    });

    test('falls back to single input parameter for non-object tool input', () {
      final driver = _TestDriver();
      final schema = JsonSchema.string(description: 'raw input');

      final params = driver.convertToolInputSchemaToParameters(schema);
      expect(params, hasLength(1));
      expect(params.single.name, 'input');
      expect(params.single.required, isTrue);
      expect(params.single.schema.type, ot.SchemaType.STRING);
    });

    test('converts single-property output schema to named return', () {
      final driver = _TestDriver();
      final outputSchema = JsonObject(
        properties: <String, JsonSchema>{
          'ok': JsonSchema.boolean(description: 'success'),
        },
      );

      final ret = driver.convertToolOutputSchemaToReturn(outputSchema)!;
      expect(ret.name, 'ok');
      expect(ret.schema.type, ot.SchemaType.BOOLEAN);
      expect(ret.description, 'success');
    });
  });
}
