// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tool_placement.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ToolPlacement _$ToolPlacementFromJson(Map<String, dynamic> json) =>
    ToolPlacement(
      toolId: json['toolId'] as String,
      screenId: json['screenId'] as String,
      position: GridPosition.fromJson(json['position'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$ToolPlacementToJson(ToolPlacement instance) =>
    <String, dynamic>{
      'toolId': instance.toolId,
      'screenId': instance.screenId,
      'position': instance.position,
    };
