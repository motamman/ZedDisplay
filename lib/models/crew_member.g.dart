// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'crew_member.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CrewMember _$CrewMemberFromJson(Map<String, dynamic> json) => CrewMember(
  id: json['id'] as String,
  name: json['name'] as String,
  role: $enumDecodeNullable(_$CrewRoleEnumMap, json['role']) ?? CrewRole.crew,
  status:
      $enumDecodeNullable(_$CrewStatusEnumMap, json['status']) ??
      CrewStatus.offWatch,
  deviceId: json['deviceId'] as String,
  deviceName: json['deviceName'] as String?,
  avatar: json['avatar'] as String?,
  createdAt: json['createdAt'] == null
      ? null
      : DateTime.parse(json['createdAt'] as String),
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$CrewMemberToJson(CrewMember instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'role': _$CrewRoleEnumMap[instance.role]!,
      'status': _$CrewStatusEnumMap[instance.status]!,
      'deviceId': instance.deviceId,
      'deviceName': instance.deviceName,
      'avatar': instance.avatar,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
    };

const _$CrewRoleEnumMap = {
  CrewRole.captain: 'captain',
  CrewRole.firstMate: 'first_mate',
  CrewRole.crew: 'crew',
  CrewRole.guest: 'guest',
};

const _$CrewStatusEnumMap = {
  CrewStatus.onWatch: 'on_watch',
  CrewStatus.offWatch: 'off_watch',
  CrewStatus.standby: 'standby',
  CrewStatus.resting: 'resting',
  CrewStatus.away: 'away',
};

CrewPresence _$CrewPresenceFromJson(Map<String, dynamic> json) => CrewPresence(
  crewId: json['crewId'] as String,
  online: json['online'] as bool? ?? false,
  lastSeen: json['lastSeen'] == null
      ? null
      : DateTime.parse(json['lastSeen'] as String),
  localIp: json['localIp'] as String?,
);

Map<String, dynamic> _$CrewPresenceToJson(CrewPresence instance) =>
    <String, dynamic>{
      'crewId': instance.crewId,
      'online': instance.online,
      'lastSeen': instance.lastSeen.toIso8601String(),
      'localIp': instance.localIp,
    };
