// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tool_instance.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ToolInstance _$ToolInstanceFromJson(Map<String, dynamic> json) => ToolInstance(
      id: json['id'] as String,
      toolTypeId: json['toolTypeId'] as String,
      config: ToolConfig.fromJson(json['config'] as Map<String, dynamic>),
      screenId: json['screenId'] as String,
      position: GridPosition.fromJson(json['position'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$ToolInstanceToJson(ToolInstance instance) =>
    <String, dynamic>{
      'id': instance.id,
      'toolTypeId': instance.toolTypeId,
      'config': instance.config,
      'screenId': instance.screenId,
      'position': instance.position,
    };
