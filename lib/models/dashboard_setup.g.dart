// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dashboard_setup.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DashboardSetup _$DashboardSetupFromJson(Map<String, dynamic> json) =>
    DashboardSetup(
      version: json['version'] as String? ?? '1.0.0',
      metadata:
          SetupMetadata.fromJson(json['metadata'] as Map<String, dynamic>),
      layout: DashboardLayout.fromJson(json['layout'] as Map<String, dynamic>),
      tools: (json['tools'] as List<dynamic>)
          .map((e) => Tool.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$DashboardSetupToJson(DashboardSetup instance) =>
    <String, dynamic>{
      'version': instance.version,
      'metadata': instance.metadata,
      'layout': instance.layout,
      'tools': instance.tools,
    };

SetupMetadata _$SetupMetadataFromJson(Map<String, dynamic> json) =>
    SetupMetadata(
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      author: json['author'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
      thumbnailUrl: json['thumbnailUrl'] as String?,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              const [],
    );

Map<String, dynamic> _$SetupMetadataToJson(SetupMetadata instance) =>
    <String, dynamic>{
      'name': instance.name,
      'description': instance.description,
      'author': instance.author,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
      'thumbnailUrl': instance.thumbnailUrl,
      'tags': instance.tags,
    };

SavedSetup _$SavedSetupFromJson(Map<String, dynamic> json) => SavedSetup(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsedAt: json['lastUsedAt'] == null
          ? null
          : DateTime.parse(json['lastUsedAt'] as String),
      isActive: json['isActive'] as bool? ?? false,
      screenCount: (json['screenCount'] as num?)?.toInt() ?? 0,
      toolCount: (json['toolCount'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$SavedSetupToJson(SavedSetup instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'createdAt': instance.createdAt.toIso8601String(),
      'lastUsedAt': instance.lastUsedAt?.toIso8601String(),
      'isActive': instance.isActive,
      'screenCount': instance.screenCount,
      'toolCount': instance.toolCount,
    };
