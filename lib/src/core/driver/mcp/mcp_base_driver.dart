import 'package:mcp_dart/mcp_dart.dart';
import 'package:opentool_dart/opentool_dart.dart' as ot;
import '../tool_driver.dart';

/// MCP驱动器的基类，提供公共的Schema解析逻辑
abstract class McpBaseDriver extends ToolDriver {
  late List<ot.FunctionModel> functionModelList;
  bool _isConnected = false;

  /// 检查是否已连接
  bool get isConnected => _isConnected;

  /// 设置连接状态
  set isConnected(bool value) => _isConnected = value;

  @override
  bool hasFunction(String functionName) {
    return functionModelList.any((functionModel) => functionModel.name == functionName);
  }

  @override
  List<ot.FunctionModel> parse() {
    return functionModelList;
  }

  /// 将MCP工具列表转换为FunctionModel列表
  List<ot.FunctionModel> convertToFunctionModelList(ListToolsResult listToolsResult) {
    try {
      if (listToolsResult.tools.isEmpty) {
        return [];
      }

      final functionModels = <ot.FunctionModel>[];
      
      for (final tool in listToolsResult.tools) {
        try {
          final toolName = tool.name.isNotEmpty ? tool.name : 'unnamed_tool_${functionModels.length}';
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

  /// 将工具输入Schema转换为参数列表
  List<ot.Parameter> convertToolInputSchemaToParameters(ToolInputSchema schema) {
    try {
      if (schema.properties == null || schema.properties!.isEmpty) {
        return [];
      }

      final parameters = <ot.Parameter>[];
      for (final entry in schema.properties!.entries) {
        try {
          final name = entry.key;
          final value = entry.value;
          
          Map<String, dynamic> valueMap;
          if (value is Map<String, dynamic>) {
            valueMap = value;
          } else {
            parameters.add(createFallbackParameter(name));
            continue;
          }

          final isRequired = schema.required?.contains(name) ?? false;
          final description = safeGetString(valueMap, 'description') ?? 'Parameter $name';

          final parameter = ot.Parameter(
            name: name,
            description: description,
            required: isRequired,
            schema: parseSchemaWithFallback(valueMap),
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

  /// 将工具输出Schema转换为返回值
  ot.Return? convertToolOutputSchemaToReturn(ToolOutputSchema? outputSchema) {
    try {
      if (outputSchema == null) {
        return createFallbackReturn();
      }

      if (outputSchema.properties == null || outputSchema.properties!.isEmpty) {
        return createFallbackReturn();
      }

      final properties = outputSchema.properties!;
      final required = outputSchema.required;

      if (properties.length == 1) {
        try {
          final entry = properties.entries.first;
          final name = entry.key;
          final value = entry.value;
          
          Map<String, dynamic> valueMap;
          if (value is Map<String, dynamic>) {
            valueMap = value;
          } else {
            return createFallbackReturn();
          }
          
          final description = safeGetString(valueMap, 'description') ?? 'Output field $name';
          
          return ot.Return(
            name: name,
            description: description,
            schema: parseSchemaWithFallback(valueMap),
          );
        } catch (e) {
          return createFallbackReturn();
        }
      }

      try {
        return ot.Return(
          name: 'result',
          description: 'Tool execution result',
          schema: determineReturnSchema(properties, required),
        );
      } catch (e) {
        return createFallbackReturn();
      }
    } catch (e) {
      return createFallbackReturn();
    }
  }

  /// 确定返回值的Schema
  ot.Schema determineReturnSchema(Map<String, dynamic> properties, List<String>? required) {
    final schemaProperties = properties.map((key, value) => 
      MapEntry(key, parseSchemaWithFallback(value as Map<String, dynamic>))
    );

    return ot.Schema(
      type: ot.SchemaType.OBJECT,
      description: 'Tool execution result object',
      properties: schemaProperties,
      required: required,
    );
  }

  /// 解析Schema，带有容错机制
  ot.Schema parseSchemaWithFallback(Map<String, dynamic> schemaMap) {
    try {
      String type = inferSchemaType(schemaMap);
      String? description = safeGetString(schemaMap, 'description') ?? 
                           'Auto-generated description for compatibility';
      List<String>? enumValues;
      
      try {
        enumValues = schemaMap.containsKey('enum') && schemaMap['enum'] != null
            ? List<String>.from(schemaMap['enum'])
            : null;
      } catch (e) {
        enumValues = null;
      }

      ot.Schema? items;
      if (type == 'array' && schemaMap.containsKey('items')) {
        try {
          final itemsData = schemaMap['items'];
          if (itemsData is Map<String, dynamic>) {
            items = parseSchemaWithFallback(itemsData);
          }
        } catch (e) {
          items = createFallbackSchema();
        }
      }

      Map<String, ot.Schema>? properties;
      List<String>? required;
      if (type == 'object') {
        try {
          if (schemaMap.containsKey('properties') && schemaMap['properties'] is Map) {
            properties = <String, ot.Schema>{};
            final propsMap = schemaMap['properties'] as Map<String, dynamic>;
            for (final entry in propsMap.entries) {
              try {
                properties[entry.key] = parseSchemaWithFallback(entry.value as Map<String, dynamic>);
              } catch (e) {
                properties[entry.key] = createFallbackSchema();
              }
            }
          }
        } catch (e) {
          properties = null;
        }

        try {
          required = schemaMap.containsKey('required') && schemaMap['required'] is List
              ? List<String>.from(schemaMap['required'])
              : null;
        } catch (e) {
          required = null;
        }
      }

      return ot.Schema(
        type: type, 
        description: description, 
        properties: properties, 
        items: items, 
        enum_: enumValues, 
        required: required,
      );
    } catch (e) {
      return createFallbackSchema();
    }
  }

  /// 推断Schema类型
  String inferSchemaType(Map<String, dynamic> schemaMap) {
    if (schemaMap.containsKey('type') && schemaMap['type'] is String) {
      return schemaMap['type'] as String;
    }
    
    if (schemaMap.containsKey('properties')) {
      return ot.SchemaType.OBJECT;
    }
    if (schemaMap.containsKey('items')) {
      return ot.SchemaType.ARRAY;
    }
    if (schemaMap.containsKey('enum')) {
      return ot.SchemaType.STRING;
    }
    
    return ot.SchemaType.STRING;
  }

  /// 安全地从Map中获取字符串值
  String? safeGetString(Map<String, dynamic> map, String key) {
    try {
      final value = map[key];
      return value is String ? value : null;
    } catch (e) {
      return null;
    }
  }

  /// 创建默认的Schema
  ot.Schema createFallbackSchema() {
    return ot.Schema(
      type: ot.SchemaType.STRING,
      description: 'Fallback schema for compatibility',
    );
  }

  /// 创建默认的参数
  ot.Parameter createFallbackParameter(String name) {
    return ot.Parameter(
      name: name,
      description: 'Auto-generated parameter for compatibility',
      required: false,
      schema: createFallbackSchema(),
    );
  }

  /// 创建默认的返回值
  ot.Return createFallbackReturn() {
    return ot.Return(
      name: 'result',
      description: 'Generic result for compatibility',
      schema: createFallbackSchema(),
    );
  }
}

