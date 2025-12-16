// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_token.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AuthToken _$AuthTokenFromJson(Map<String, dynamic> json) => AuthToken(
  token: json['token'] as String,
  clientId: json['clientId'] as String?,
  expiresAt: json['expiresAt'] == null
      ? null
      : DateTime.parse(json['expiresAt'] as String),
  issuedAt: json['issuedAt'] == null
      ? null
      : DateTime.parse(json['issuedAt'] as String),
  serverUrl: json['serverUrl'] as String,
  connectionId: json['connectionId'] as String?,
);

Map<String, dynamic> _$AuthTokenToJson(AuthToken instance) => <String, dynamic>{
  'token': instance.token,
  'clientId': instance.clientId,
  'expiresAt': instance.expiresAt?.toIso8601String(),
  'issuedAt': instance.issuedAt.toIso8601String(),
  'serverUrl': instance.serverUrl,
  'connectionId': instance.connectionId,
};
