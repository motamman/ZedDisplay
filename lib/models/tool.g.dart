// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tool.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Tool _$ToolFromJson(Map<String, dynamic> json) => Tool(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      author: json['author'] as String,
      version: json['version'] as String? ?? '1.0.0',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
      toolTypeId: json['toolTypeId'] as String,
      config: ToolConfig.fromJson(json['config'] as Map<String, dynamic>),
      defaultWidth: (json['defaultWidth'] as num?)?.toInt() ?? 2,
      defaultHeight: (json['defaultHeight'] as num?)?.toInt() ?? 2,
      category: $enumDecodeNullable(_$ToolCategoryEnumMap, json['category']) ??
          ToolCategory.other,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              const [],
      thumbnailUrl: json['thumbnailUrl'] as String?,
      iconUrl: json['iconUrl'] as String?,
      requiredPaths: (json['requiredPaths'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      minAppVersion: json['minAppVersion'] as String?,
      usageCount: (json['usageCount'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
      sourceUrl: json['sourceUrl'] as String?,
      isLocal: json['isLocal'] as bool? ?? true,
    );

Map<String, dynamic> _$ToolToJson(Tool instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'author': instance.author,
      'version': instance.version,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
      'toolTypeId': instance.toolTypeId,
      'config': instance.config,
      'defaultWidth': instance.defaultWidth,
      'defaultHeight': instance.defaultHeight,
      'category': _$ToolCategoryEnumMap[instance.category]!,
      'tags': instance.tags,
      'thumbnailUrl': instance.thumbnailUrl,
      'iconUrl': instance.iconUrl,
      'requiredPaths': instance.requiredPaths,
      'minAppVersion': instance.minAppVersion,
      'usageCount': instance.usageCount,
      'rating': instance.rating,
      'ratingCount': instance.ratingCount,
      'sourceUrl': instance.sourceUrl,
      'isLocal': instance.isLocal,
    };

const _$ToolCategoryEnumMap = {
  ToolCategory.navigation: 'navigation',
  ToolCategory.environment: 'environment',
  ToolCategory.electrical: 'electrical',
  ToolCategory.engine: 'engine',
  ToolCategory.sailing: 'sailing',
  ToolCategory.safety: 'safety',
  ToolCategory.complete: 'complete',
  ToolCategory.other: 'other',
};
