// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tool_definition.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ConfigSchema _$ConfigSchemaFromJson(Map<String, dynamic> json) => ConfigSchema(
      allowsMinMax: json['allowsMinMax'] as bool? ?? true,
      allowsColorCustomization:
          json['allowsColorCustomization'] as bool? ?? true,
      allowsMultiplePaths: json['allowsMultiplePaths'] as bool? ?? false,
      minPaths: (json['minPaths'] as num?)?.toInt() ?? 1,
      maxPaths: (json['maxPaths'] as num?)?.toInt() ?? 1,
      styleOptions: (json['styleOptions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );

Map<String, dynamic> _$ConfigSchemaToJson(ConfigSchema instance) =>
    <String, dynamic>{
      'allowsMinMax': instance.allowsMinMax,
      'allowsColorCustomization': instance.allowsColorCustomization,
      'allowsMultiplePaths': instance.allowsMultiplePaths,
      'minPaths': instance.minPaths,
      'maxPaths': instance.maxPaths,
      'styleOptions': instance.styleOptions,
    };

ToolDefinition _$ToolDefinitionFromJson(Map<String, dynamic> json) =>
    ToolDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      category: $enumDecode(_$ToolCategoryEnumMap, json['category']),
      configSchema:
          ConfigSchema.fromJson(json['configSchema'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$ToolDefinitionToJson(ToolDefinition instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'category': _$ToolCategoryEnumMap[instance.category]!,
      'configSchema': instance.configSchema,
    };

const _$ToolCategoryEnumMap = {
  ToolCategory.gauge: 'gauge',
  ToolCategory.chart: 'chart',
  ToolCategory.display: 'display',
  ToolCategory.compass: 'compass',
  ToolCategory.other: 'other',
};
