// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tool_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DataSource _$DataSourceFromJson(Map<String, dynamic> json) => DataSource(
  path: json['path'] as String,
  source: json['source'] as String?,
  label: json['label'] as String?,
  color: json['color'] as String?,
);

Map<String, dynamic> _$DataSourceToJson(DataSource instance) =>
    <String, dynamic>{
      'path': instance.path,
      'source': instance.source,
      'label': instance.label,
      'color': instance.color,
    };

StyleConfig _$StyleConfigFromJson(Map<String, dynamic> json) => StyleConfig(
  minValue: (json['minValue'] as num?)?.toDouble(),
  maxValue: (json['maxValue'] as num?)?.toDouble(),
  unit: json['unit'] as String?,
  primaryColor: json['primaryColor'] as String?,
  secondaryColor: json['secondaryColor'] as String?,
  showLabel: json['showLabel'] as bool? ?? true,
  showValue: json['showValue'] as bool? ?? true,
  showUnit: json['showUnit'] as bool? ?? true,
  ttlSeconds: (json['ttlSeconds'] as num?)?.toInt(),
  laylineAngle: (json['laylineAngle'] as num?)?.toDouble(),
  targetTolerance: (json['targetTolerance'] as num?)?.toDouble(),
  showLaylines: json['showLaylines'] as bool?,
  showTrueWind: json['showTrueWind'] as bool?,
  showCOG: json['showCOG'] as bool?,
  showAWS: json['showAWS'] as bool?,
  showTWS: json['showTWS'] as bool?,
  customProperties: json['customProperties'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$StyleConfigToJson(StyleConfig instance) =>
    <String, dynamic>{
      'minValue': instance.minValue,
      'maxValue': instance.maxValue,
      'unit': instance.unit,
      'primaryColor': instance.primaryColor,
      'secondaryColor': instance.secondaryColor,
      'showLabel': instance.showLabel,
      'showValue': instance.showValue,
      'showUnit': instance.showUnit,
      'ttlSeconds': instance.ttlSeconds,
      'laylineAngle': instance.laylineAngle,
      'targetTolerance': instance.targetTolerance,
      'showLaylines': instance.showLaylines,
      'showTrueWind': instance.showTrueWind,
      'showCOG': instance.showCOG,
      'showAWS': instance.showAWS,
      'showTWS': instance.showTWS,
      'customProperties': instance.customProperties,
    };

GridPosition _$GridPositionFromJson(Map<String, dynamic> json) => GridPosition(
  row: (json['row'] as num).toInt(),
  col: (json['col'] as num).toInt(),
  width: (json['width'] as num?)?.toInt() ?? 1,
  height: (json['height'] as num?)?.toInt() ?? 1,
);

Map<String, dynamic> _$GridPositionToJson(GridPosition instance) =>
    <String, dynamic>{
      'row': instance.row,
      'col': instance.col,
      'width': instance.width,
      'height': instance.height,
    };

PixelPosition _$PixelPositionFromJson(Map<String, dynamic> json) =>
    PixelPosition(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
    );

Map<String, dynamic> _$PixelPositionToJson(PixelPosition instance) =>
    <String, dynamic>{
      'x': instance.x,
      'y': instance.y,
      'width': instance.width,
      'height': instance.height,
    };

ToolConfig _$ToolConfigFromJson(Map<String, dynamic> json) => ToolConfig(
  vesselId: json['vesselId'] as String?,
  dataSources: (json['dataSources'] as List<dynamic>)
      .map((e) => DataSource.fromJson(e as Map<String, dynamic>))
      .toList(),
  style: StyleConfig.fromJson(json['style'] as Map<String, dynamic>),
);

Map<String, dynamic> _$ToolConfigToJson(ToolConfig instance) =>
    <String, dynamic>{
      'vesselId': instance.vesselId,
      'dataSources': instance.dataSources,
      'style': instance.style,
    };
