// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'crew_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CrewMessage _$CrewMessageFromJson(Map<String, dynamic> json) => CrewMessage(
  id: json['id'] as String,
  fromId: json['fromId'] as String,
  fromName: json['fromName'] as String,
  toId: json['toId'] as String? ?? 'all',
  type:
      $enumDecodeNullable(_$MessageTypeEnumMap, json['type']) ??
      MessageType.text,
  content: json['content'] as String,
  timestamp: json['timestamp'] == null
      ? null
      : DateTime.parse(json['timestamp'] as String),
  read: json['read'] as bool? ?? false,
);

Map<String, dynamic> _$CrewMessageToJson(CrewMessage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'fromId': instance.fromId,
      'fromName': instance.fromName,
      'toId': instance.toId,
      'type': _$MessageTypeEnumMap[instance.type]!,
      'content': instance.content,
      'timestamp': instance.timestamp.toIso8601String(),
      'read': instance.read,
    };

const _$MessageTypeEnumMap = {
  MessageType.text: 'text',
  MessageType.status: 'status',
  MessageType.alert: 'alert',
  MessageType.file: 'file',
};
