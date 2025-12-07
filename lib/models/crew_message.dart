import 'package:json_annotation/json_annotation.dart';

part 'crew_message.g.dart';

/// Type of crew message
enum MessageType {
  @JsonValue('text')
  text,
  @JsonValue('status')
  status,
  @JsonValue('alert')
  alert,
  @JsonValue('file')
  file,
}

/// Represents a message between crew members
@JsonSerializable()
class CrewMessage {
  /// Unique message ID
  final String id;

  /// Sender's crew ID
  final String fromId;

  /// Sender's display name (cached for offline display)
  final String fromName;

  /// Recipient: "all" for broadcast, or specific crew ID for direct message
  final String toId;

  /// Message type
  final MessageType type;

  /// Message content (text, status message, or file reference)
  final String content;

  /// When the message was sent
  final DateTime timestamp;

  /// Whether message has been read (for direct messages)
  final bool read;

  CrewMessage({
    required this.id,
    required this.fromId,
    required this.fromName,
    this.toId = 'all',
    this.type = MessageType.text,
    required this.content,
    DateTime? timestamp,
    this.read = false,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Check if this is a broadcast message
  bool get isBroadcast => toId == 'all';

  /// Check if this is a direct message
  bool get isDirectMessage => toId != 'all';

  /// Create a copy with updated fields
  CrewMessage copyWith({
    String? id,
    String? fromId,
    String? fromName,
    String? toId,
    MessageType? type,
    String? content,
    DateTime? timestamp,
    bool? read,
  }) {
    return CrewMessage(
      id: id ?? this.id,
      fromId: fromId ?? this.fromId,
      fromName: fromName ?? this.fromName,
      toId: toId ?? this.toId,
      type: type ?? this.type,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      read: read ?? this.read,
    );
  }

  factory CrewMessage.fromJson(Map<String, dynamic> json) =>
      _$CrewMessageFromJson(json);
  Map<String, dynamic> toJson() => _$CrewMessageToJson(this);
}

/// Predefined status messages for quick broadcast
class StatusMessages {
  static const List<String> watchStatus = [
    'Starting watch',
    'Ending watch',
    'Watch handover complete',
  ];

  static const List<String> vesselStatus = [
    'Underway',
    'Anchored',
    'Moored',
    'Adrift',
  ];

  static const List<String> alerts = [
    'Man overboard!',
    'All hands on deck',
    'Prepare for weather',
    'Engine issue',
  ];

  static const List<String> general = [
    'Lunch ready',
    'Coffee break',
    'Need assistance',
    'All clear',
  ];
}
