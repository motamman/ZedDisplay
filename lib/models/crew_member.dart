import 'package:json_annotation/json_annotation.dart';

part 'crew_member.g.dart';

/// Status options for crew members
enum CrewStatus {
  @JsonValue('on_watch')
  onWatch,
  @JsonValue('off_watch')
  offWatch,
  @JsonValue('standby')
  standby,
  @JsonValue('resting')
  resting,
  @JsonValue('away')
  away,
}

/// Role options for crew members
enum CrewRole {
  @JsonValue('captain')
  captain,
  @JsonValue('first_mate')
  firstMate,
  @JsonValue('crew')
  crew,
  @JsonValue('guest')
  guest,
}

/// Represents a crew member on the vessel
@JsonSerializable()
class CrewMember {
  /// Unique identifier for the crew member (UUID)
  final String id;

  /// Display name
  final String name;

  /// Role on the vessel
  final CrewRole role;

  /// Current status
  final CrewStatus status;

  /// Device ID for this crew member's device
  final String deviceId;

  /// Optional avatar (base64 encoded or URL)
  final String? avatar;

  /// When this profile was created
  final DateTime createdAt;

  /// When this profile was last updated
  final DateTime updatedAt;

  CrewMember({
    required this.id,
    required this.name,
    this.role = CrewRole.crew,
    this.status = CrewStatus.offWatch,
    required this.deviceId,
    this.avatar,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Create a copy with updated fields
  CrewMember copyWith({
    String? id,
    String? name,
    CrewRole? role,
    CrewStatus? status,
    String? deviceId,
    String? avatar,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CrewMember(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      status: status ?? this.status,
      deviceId: deviceId ?? this.deviceId,
      avatar: avatar ?? this.avatar,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  /// Get display string for role
  String get roleDisplay {
    switch (role) {
      case CrewRole.captain:
        return 'Captain';
      case CrewRole.firstMate:
        return 'First Mate';
      case CrewRole.crew:
        return 'Crew';
      case CrewRole.guest:
        return 'Guest';
    }
  }

  /// Get display string for status
  String get statusDisplay {
    switch (status) {
      case CrewStatus.onWatch:
        return 'On Watch';
      case CrewStatus.offWatch:
        return 'Off Watch';
      case CrewStatus.standby:
        return 'Standby';
      case CrewStatus.resting:
        return 'Resting';
      case CrewStatus.away:
        return 'Away';
    }
  }

  factory CrewMember.fromJson(Map<String, dynamic> json) =>
      _$CrewMemberFromJson(json);
  Map<String, dynamic> toJson() => _$CrewMemberToJson(this);
}

/// Presence information for a crew member
@JsonSerializable()
class CrewPresence {
  /// Crew member ID this presence belongs to
  final String crewId;

  /// Whether the crew member is currently online
  final bool online;

  /// Last time we received a heartbeat
  final DateTime lastSeen;

  /// IP address on the local network (for direct connections)
  final String? localIp;

  CrewPresence({
    required this.crewId,
    this.online = false,
    DateTime? lastSeen,
    this.localIp,
  }) : lastSeen = lastSeen ?? DateTime.now();

  /// Check if presence is stale (no heartbeat in 60 seconds)
  bool get isStale {
    return DateTime.now().difference(lastSeen).inSeconds > 60;
  }

  /// Create a copy with updated fields
  CrewPresence copyWith({
    String? crewId,
    bool? online,
    DateTime? lastSeen,
    String? localIp,
  }) {
    return CrewPresence(
      crewId: crewId ?? this.crewId,
      online: online ?? this.online,
      lastSeen: lastSeen ?? this.lastSeen,
      localIp: localIp ?? this.localIp,
    );
  }

  factory CrewPresence.fromJson(Map<String, dynamic> json) =>
      _$CrewPresenceFromJson(json);
  Map<String, dynamic> toJson() => _$CrewPresenceToJson(this);
}
