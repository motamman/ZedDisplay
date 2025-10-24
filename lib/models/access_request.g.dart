// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'access_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AccessRequest _$AccessRequestFromJson(Map<String, dynamic> json) =>
    AccessRequest(
      requestId: json['requestId'] as String,
      clientId: json['clientId'] as String,
      description: json['description'] as String,
      state: const AccessRequestStateConverter().fromJson(
        json['state'] as String,
      ),
      token: json['token'] as String?,
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.parse(json['expiresAt'] as String),
      statusHref: json['statusHref'] as String?,
      message: json['message'] as String?,
    );

Map<String, dynamic> _$AccessRequestToJson(AccessRequest instance) =>
    <String, dynamic>{
      'requestId': instance.requestId,
      'clientId': instance.clientId,
      'description': instance.description,
      'state': const AccessRequestStateConverter().toJson(instance.state),
      'token': instance.token,
      'expiresAt': instance.expiresAt?.toIso8601String(),
      'statusHref': instance.statusHref,
      'message': instance.message,
    };
