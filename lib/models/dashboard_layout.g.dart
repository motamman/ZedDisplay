// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dashboard_layout.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DashboardLayout _$DashboardLayoutFromJson(Map<String, dynamic> json) =>
    DashboardLayout(
      id: json['id'] as String,
      name: json['name'] as String,
      screens: (json['screens'] as List<dynamic>)
          .map((e) => DashboardScreen.fromJson(e as Map<String, dynamic>))
          .toList(),
      activeScreenIndex: (json['activeScreenIndex'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$DashboardLayoutToJson(DashboardLayout instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'screens': instance.screens,
      'activeScreenIndex': instance.activeScreenIndex,
    };
