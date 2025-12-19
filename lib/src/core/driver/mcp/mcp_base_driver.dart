import 'package:mcp_dart/mcp_dart.dart';
import 'package:opentool_dart/opentool_client.dart' as ot;
import '../tool_driver.dart';

/// Base class for MCP drivers, providing shared schema parsing logic.
abstract class McpBaseDriver extends ToolDriver {
  late List<ot.FunctionModel> functionModelList;
  bool _isConnected = false;

  /// Whether the driver is connected.
  bool get isConnected => _isConnected;

  /// Updates the connection state.
  set isConnected(bool value) => _isConnected = value;

  @override
  bool hasFunction(String functionName) {
    return functionModelList.any((functionModel) => functionModel.name == functionName);
  }

  @override
  List<ot.FunctionModel> parse() {
    return functionModelList;
  }

  /// Converts MCP tool definitions to a list of `FunctionModel`.
  List<ot.FunctionModel> convertToFunctionModelList(ListToolsResult listToolsResult) {
    try {
      if (listToolsResult.tools.isEmpty) {
        return [];
      }

      final functionModels = <ot.FunctionModel>[];

      for (final tool in listToolsResult.tools) {
        try {
          final toolName =
              tool.name.isNotEmpty ? tool.name : 'unnamed_tool_${functionModels.length}';
          final toolDescription = tool.description ?? 'Auto-generated description for $toolName';

          List<ot.Parameter> parameters;
          try {
            parameters = convertToolInputSchemaToParameters(tool.inputSchema);
          } catch (e) {
            parameters = [];
          }

          ot.Return? returnValue;
          try {
            returnValue = convertToolOutputSchemaToReturn(tool.outputSchema);
          } catch (e) {
            returnValue = null;
          }

          final functionModel = ot.FunctionModel(
            name: toolName,
            description: toolDescription,
            parameters: parameters,
            return_: returnValue,
          );

          functionModels.add(functionModel);
        } catch (e) {
          final toolName = tool.name.isNotEmpty ? tool.name : 'tool_${functionModels.length}';

          final basicFunctionModel = ot.FunctionModel(
            name: toolName,
            description: 'Basic function model for compatibility (conversion failed)',
            parameters: [],
            return_: null,
          );
          functionModels.add(basicFunctionModel);
        }
      }

      return functionModels;
    } catch (e) {
      return [];
    }
  }

  /// Converts a tool input schema to a list of parameters.
  List<ot.Parameter> convertToolInputSchemaToParameters(JsonSchema schema) {
    try {
      if (schema is! JsonObject) {
        // MCP tools usually use an object input schema; provide a compatible fallback.
        return [
          ot.Parameter(
            name: 'input',
            description: schema.description ?? schema.title ?? 'Tool input',
            required: true,
            schema: convertJsonSchemaToOtSchema(schema),
          ),
        ];
      }

      if (schema.properties == null || schema.properties!.isEmpty) {
        return [];
      }

      final required = schema.required ?? const <String>[];

      final parameters = <ot.Parameter>[];
      for (final entry in schema.properties!.entries) {
        try {
          final name = entry.key;
          final value = entry.value;
          final isRequired = required.contains(name);
          final description = value.description ?? value.title ?? 'Parameter $name';

          final parameter = ot.Parameter(
            name: name,
            description: description,
            required: isRequired,
            schema: convertJsonSchemaToOtSchema(value),
          );

          parameters.add(parameter);
        } catch (e) {
          parameters.add(createFallbackParameter(entry.key));
        }
      }

      return parameters;
    } catch (e) {
      return [];
    }
  }

  /// Converts a tool output schema to an `ot.Return`.
  ot.Return? convertToolOutputSchemaToReturn(JsonSchema? outputSchema) {
    try {
      if (outputSchema == null) {
        return createFallbackReturn();
      }

      try {
        if (outputSchema is JsonObject &&
            outputSchema.properties != null &&
            outputSchema.properties!.length == 1) {
          final entry = outputSchema.properties!.entries.first;
          final name = entry.key;
          final schema = entry.value;

          return ot.Return(
            name: name,
            description: schema.description ?? schema.title ?? 'Output field $name',
            schema: convertJsonSchemaToOtSchema(schema),
          );
        }

        return ot.Return(
          name: 'result',
          description: outputSchema.description ?? outputSchema.title ?? 'Tool execution result',
          schema: convertJsonSchemaToOtSchema(outputSchema),
        );
      } catch (e) {
        return createFallbackReturn();
      }
    } catch (e) {
      return createFallbackReturn();
    }
  }

  /// Converts MCP's `JsonSchema` to `opentool`'s `Schema`.
  ot.Schema convertJsonSchemaToOtSchema(JsonSchema schema) {
    final description = schema.description ?? schema.title ?? 'Auto-generated schema';

    switch (schema) {
      case final JsonString s:
        return ot.Schema(
          type: ot.SchemaType.STRING,
          description: description,
          enum_: s.enumValues,
        );
      case JsonNumber():
        return ot.Schema(
          type: 'number',
          description: description,
        );
      case JsonInteger():
        return ot.Schema(
          type: 'integer',
          description: description,
        );
      case JsonBoolean():
        return ot.Schema(
          type: 'boolean',
          description: description,
        );
      case JsonNull():
        return ot.Schema(
          type: 'null',
          description: description,
        );
      case final JsonArray a:
        return ot.Schema(
          type: ot.SchemaType.ARRAY,
          description: description,
          items: a.items != null ? convertJsonSchemaToOtSchema(a.items!) : createFallbackSchema(),
        );
      case final JsonObject o:
        final properties = o.properties?.map(
          (key, value) => MapEntry(key, convertJsonSchemaToOtSchema(value)),
        );

        return ot.Schema(
          type: ot.SchemaType.OBJECT,
          description: description,
          properties: properties,
          required: o.required,
        );
      case final JsonEnum e:
        final values = e.values.map((v) => v.toString()).toList();
        return ot.Schema(
          type: ot.SchemaType.STRING,
          description: description,
          enum_: values,
        );
      case final JsonAllOf allOf:
        return convertAllOfToOtSchema(allOf, description);
      case final JsonAnyOf anyOf:
        return convertAnyOfToOtSchema(anyOf, description);
      case final JsonOneOf oneOf:
        return convertOneOfToOtSchema(oneOf, description);
      case JsonNot():
        // `opentool` schema does not support `not`; use a generic object schema.
        return ot.Schema(
          type: ot.SchemaType.OBJECT,
          description: description,
        );
      case JsonAny():
        // The most permissive schema; prefer `object` to avoid pushing the LLM to generate scalars.
        return ot.Schema(
          type: ot.SchemaType.OBJECT,
          description: description,
        );
    }
  }

  ot.Schema convertAllOfToOtSchema(JsonAllOf allOf, String description) {
    if (allOf.schemas.isEmpty) {
      return ot.Schema(type: ot.SchemaType.OBJECT, description: description);
    }

    final objectSchemas = allOf.schemas.whereType<JsonObject>().toList();
    if (objectSchemas.length == allOf.schemas.length) {
      final mergedProperties = <String, ot.Schema>{};
      final mergedRequired = <String>{};

      for (final schema in objectSchemas) {
        mergedRequired.addAll(schema.required ?? const <String>[]);
        for (final entry in schema.properties?.entries ?? const <MapEntry<String, JsonSchema>>[]) {
          mergedProperties.putIfAbsent(entry.key, () => convertJsonSchemaToOtSchema(entry.value));
        }
      }

      return ot.Schema(
        type: ot.SchemaType.OBJECT,
        description: description,
        properties: mergedProperties.isEmpty ? null : mergedProperties,
        required: mergedRequired.isEmpty ? null : mergedRequired.toList(),
      );
    }

    // If the intersection cannot be represented, fall back to the first schema as best effort.
    return convertJsonSchemaToOtSchema(allOf.schemas.first);
  }

  ot.Schema convertAnyOfToOtSchema(JsonAnyOf anyOf, String description) {
    if (anyOf.schemas.isEmpty) {
      return ot.Schema(type: ot.SchemaType.OBJECT, description: description);
    }

    // `anyOf`/`oneOf` are not directly representable in `opentool` schema; using `object` is safer.
    final objectSchemas = anyOf.schemas.whereType<JsonObject>().toList();
    if (objectSchemas.isNotEmpty && objectSchemas.length == anyOf.schemas.length) {
      final mergedProperties = <String, ot.Schema>{};
      final intersectionRequired = <String>{...?(objectSchemas.first.required)};

      for (final schema in objectSchemas) {
        final required = schema.required ?? const <String>[];
        intersectionRequired.retainAll(required);
        for (final entry in schema.properties?.entries ?? const <MapEntry<String, JsonSchema>>[]) {
          mergedProperties.putIfAbsent(entry.key, () => convertJsonSchemaToOtSchema(entry.value));
        }
      }

      return ot.Schema(
        type: ot.SchemaType.OBJECT,
        description: description,
        properties: mergedProperties.isEmpty ? null : mergedProperties,
        required: intersectionRequired.isEmpty ? null : intersectionRequired.toList(),
      );
    }

    return ot.Schema(type: ot.SchemaType.OBJECT, description: description);
  }

  ot.Schema convertOneOfToOtSchema(JsonOneOf oneOf, String description) {
    if (oneOf.schemas.isEmpty) {
      return ot.Schema(type: ot.SchemaType.OBJECT, description: description);
    }

    // Similar to `anyOf`: without `oneOf` support, fall back to `object`.
    return ot.Schema(type: ot.SchemaType.OBJECT, description: description);
  }

  /// Creates a fallback schema.
  ot.Schema createFallbackSchema() {
    return ot.Schema(
      type: ot.SchemaType.STRING,
      description: 'Fallback schema for compatibility',
    );
  }

  /// Creates a fallback parameter.
  ot.Parameter createFallbackParameter(String name) {
    return ot.Parameter(
      name: name,
      description: 'Auto-generated parameter for compatibility',
      required: false,
      schema: createFallbackSchema(),
    );
  }

  /// Creates a fallback return value.
  ot.Return createFallbackReturn() {
    return ot.Return(
      name: 'result',
      description: 'Generic result for compatibility',
      schema: createFallbackSchema(),
    );
  }
}
