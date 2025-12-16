import 'dart:convert';

/// Represents an intercom channel (like VHF channels)
class IntercomChannel {
  final String id;
  final String name;
  final String? description;
  final int priority;  // Lower = higher priority (CH16 Emergency = 0)
  final bool isEmergency;
  final List<String> activeMembers;  // Crew IDs currently in channel
  final DateTime createdAt;

  IntercomChannel({
    required this.id,
    required this.name,
    this.description,
    this.priority = 10,
    this.isEmergency = false,
    List<String>? activeMembers,
    DateTime? createdAt,
  })  : activeMembers = activeMembers ?? [],
        createdAt = createdAt ?? DateTime.now().toUtc();

  /// Default channels (like marine VHF)
  static List<IntercomChannel> get defaultChannels => [
    IntercomChannel(
      id: 'ch16',
      name: 'Emergency',
      description: 'Distress and safety',
      priority: 0,
      isEmergency: true,
    ),
    IntercomChannel(
      id: 'ch01',
      name: 'Helm',
      description: 'Command and navigation',
      priority: 1,
    ),
    IntercomChannel(
      id: 'ch02',
      name: 'Salon',
      description: 'Main living area',
      priority: 2,
    ),
    IntercomChannel(
      id: 'ch03',
      name: 'Forward Cabin',
      description: 'Forward guest cabin',
      priority: 3,
    ),
    IntercomChannel(
      id: 'ch04',
      name: 'Aft Cabin',
      description: 'Aft cabin',
      priority: 4,
    ),
  ];

  IntercomChannel copyWith({
    String? id,
    String? name,
    String? description,
    int? priority,
    bool? isEmergency,
    List<String>? activeMembers,
    DateTime? createdAt,
  }) {
    return IntercomChannel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      isEmergency: isEmergency ?? this.isEmergency,
      activeMembers: activeMembers ?? this.activeMembers,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'priority': priority,
      'isEmergency': isEmergency,
      'activeMembers': activeMembers,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory IntercomChannel.fromJson(Map<String, dynamic> json) {
    return IntercomChannel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      priority: json['priority'] as int? ?? 10,
      isEmergency: json['isEmergency'] as bool? ?? false,
      activeMembers: (json['activeMembers'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }

  /// Create SignalK resource format
  Map<String, dynamic> toNoteResource({double lat = 0.0, double lng = 0.0}) {
    return {
      'name': 'Channel: $name',
      'description': jsonEncode(toJson()),
      'position': {'latitude': lat, 'longitude': lng},
    };
  }

  factory IntercomChannel.fromNoteResource(String id, Map<String, dynamic> resource) {
    final description = resource['description'] as String;
    final data = jsonDecode(description) as Map<String, dynamic>;
    return IntercomChannel.fromJson({...data, 'id': id});
  }
}

/// Represents an RTC session for voice communication
class RTCSession {
  final String id;
  final String channelId;
  final String initiatorId;  // Crew member who started transmitting
  final String initiatorName;
  final RTCSessionState state;
  final DateTime startedAt;
  final DateTime? endedAt;

  RTCSession({
    required this.id,
    required this.channelId,
    required this.initiatorId,
    required this.initiatorName,
    this.state = RTCSessionState.initializing,
    DateTime? startedAt,
    this.endedAt,
  }) : startedAt = startedAt ?? DateTime.now().toUtc();

  RTCSession copyWith({
    String? id,
    String? channelId,
    String? initiatorId,
    String? initiatorName,
    RTCSessionState? state,
    DateTime? startedAt,
    DateTime? endedAt,
  }) {
    return RTCSession(
      id: id ?? this.id,
      channelId: channelId ?? this.channelId,
      initiatorId: initiatorId ?? this.initiatorId,
      initiatorName: initiatorName ?? this.initiatorName,
      state: state ?? this.state,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'channelId': channelId,
      'initiatorId': initiatorId,
      'initiatorName': initiatorName,
      'state': state.name,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': endedAt?.toIso8601String(),
    };
  }

  factory RTCSession.fromJson(Map<String, dynamic> json) {
    return RTCSession(
      id: json['id'] as String,
      channelId: json['channelId'] as String,
      initiatorId: json['initiatorId'] as String,
      initiatorName: json['initiatorName'] as String,
      state: RTCSessionState.values.firstWhere(
        (s) => s.name == json['state'],
        orElse: () => RTCSessionState.initializing,
      ),
      startedAt: json['startedAt'] != null
          ? DateTime.parse(json['startedAt'] as String)
          : null,
      endedAt: json['endedAt'] != null
          ? DateTime.parse(json['endedAt'] as String)
          : null,
    );
  }
}

/// State of an RTC session
enum RTCSessionState {
  initializing,  // Setting up connection
  connecting,    // Exchanging ICE candidates
  active,        // Voice transmission active
  ended,         // Session ended
  failed,        // Connection failed
}

/// Intercom mode
enum IntercomMode {
  ptt,    // Push-to-talk: hold button to transmit
  duplex, // Open/duplex: always transmitting when in channel
}

/// WebRTC signaling message types
enum SignalingType {
  offer,
  answer,
  iceCandidate,
  hangup,
  channelJoin,
  channelLeave,
  pttStart,  // Push-to-talk started
  pttEnd,    // Push-to-talk ended
}

/// A signaling message for WebRTC
class SignalingMessage {
  final String id;
  final String sessionId;
  final String channelId;
  final String fromId;
  final String fromName;
  final SignalingType type;
  final Map<String, dynamic>? data;  // SDP or ICE candidate data
  final DateTime timestamp;

  SignalingMessage({
    required this.id,
    required this.sessionId,
    required this.channelId,
    required this.fromId,
    required this.fromName,
    required this.type,
    this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().toUtc();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionId': sessionId,
      'channelId': channelId,
      'fromId': fromId,
      'fromName': fromName,
      'type': type.name,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory SignalingMessage.fromJson(Map<String, dynamic> json) {
    return SignalingMessage(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      channelId: json['channelId'] as String,
      fromId: json['fromId'] as String,
      fromName: json['fromName'] as String,
      type: SignalingType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => SignalingType.hangup,
      ),
      data: json['data'] as Map<String, dynamic>?,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
    );
  }

  /// Create SignalK notes resource format
  Map<String, dynamic> toNoteResource({double lat = 0.0, double lng = 0.0}) {
    return {
      'name': 'RTC: ${type.name} from $fromName',
      'description': jsonEncode(toJson()),
      'group': 'zeddisplay-rtc',
      'position': {'latitude': lat, 'longitude': lng},
    };
  }

  factory SignalingMessage.fromNoteResource(String id, Map<String, dynamic> resource) {
    final description = resource['description'] as String;
    final data = jsonDecode(description) as Map<String, dynamic>;
    return SignalingMessage.fromJson({...data, 'id': id});
  }
}
