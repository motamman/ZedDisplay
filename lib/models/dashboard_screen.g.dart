// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dashboard_screen.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DashboardScreen _$DashboardScreenFromJson(Map<String, dynamic> json) =>
    DashboardScreen(
      id: json['id'] as String,
      name: json['name'] as String,
      placements: (json['placements'] as List<dynamic>)
          .map((e) => ToolPlacement.fromJson(e as Map<String, dynamic>))
          .toList(),
      order: (json['order'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$DashboardScreenToJson(DashboardScreen instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'placements': instance.placements,
      'order': instance.order,
    };
