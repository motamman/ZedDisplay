// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_connection.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ServerConnection _$ServerConnectionFromJson(Map<String, dynamic> json) =>
    ServerConnection(
      id: json['id'] as String,
      name: json['name'] as String,
      serverUrl: json['serverUrl'] as String,
      useSecure: json['useSecure'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastConnectedAt: json['lastConnectedAt'] == null
          ? null
          : DateTime.parse(json['lastConnectedAt'] as String),
    );

Map<String, dynamic> _$ServerConnectionToJson(ServerConnection instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'serverUrl': instance.serverUrl,
      'useSecure': instance.useSecure,
      'createdAt': instance.createdAt.toIso8601String(),
      'lastConnectedAt': instance.lastConnectedAt?.toIso8601String(),
    };
