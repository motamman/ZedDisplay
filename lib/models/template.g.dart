// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'template.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Template _$TemplateFromJson(Map<String, dynamic> json) => Template(
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
      category:
          $enumDecodeNullable(_$TemplateCategoryEnumMap, json['category']) ??
              TemplateCategory.other,
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
      downloadCount: (json['downloadCount'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
      sourceUrl: json['sourceUrl'] as String?,
      isLocal: json['isLocal'] as bool? ?? true,
    );

Map<String, dynamic> _$TemplateToJson(Template instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'author': instance.author,
      'version': instance.version,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
      'toolTypeId': instance.toolTypeId,
      'config': instance.config,
      'category': _$TemplateCategoryEnumMap[instance.category]!,
      'tags': instance.tags,
      'thumbnailUrl': instance.thumbnailUrl,
      'iconUrl': instance.iconUrl,
      'requiredPaths': instance.requiredPaths,
      'minAppVersion': instance.minAppVersion,
      'downloadCount': instance.downloadCount,
      'rating': instance.rating,
      'ratingCount': instance.ratingCount,
      'sourceUrl': instance.sourceUrl,
      'isLocal': instance.isLocal,
    };

const _$TemplateCategoryEnumMap = {
  TemplateCategory.navigation: 'navigation',
  TemplateCategory.environment: 'environment',
  TemplateCategory.electrical: 'electrical',
  TemplateCategory.engine: 'engine',
  TemplateCategory.sailing: 'sailing',
  TemplateCategory.safety: 'safety',
  TemplateCategory.complete: 'complete',
  TemplateCategory.other: 'other',
};

TemplateCollection _$TemplateCollectionFromJson(Map<String, dynamic> json) =>
    TemplateCollection(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      author: json['author'] as String,
      version: json['version'] as String? ?? '1.0.0',
      createdAt: DateTime.parse(json['createdAt'] as String),
      category:
          $enumDecodeNullable(_$TemplateCategoryEnumMap, json['category']) ??
              TemplateCategory.complete,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              const [],
      templates: (json['templates'] as List<dynamic>)
          .map((e) => Template.fromJson(e as Map<String, dynamic>))
          .toList(),
      thumbnailUrl: json['thumbnailUrl'] as String?,
      isLocal: json['isLocal'] as bool? ?? true,
    );

Map<String, dynamic> _$TemplateCollectionToJson(TemplateCollection instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'author': instance.author,
      'version': instance.version,
      'createdAt': instance.createdAt.toIso8601String(),
      'category': _$TemplateCategoryEnumMap[instance.category]!,
      'tags': instance.tags,
      'templates': instance.templates,
      'thumbnailUrl': instance.thumbnailUrl,
      'isLocal': instance.isLocal,
    };
