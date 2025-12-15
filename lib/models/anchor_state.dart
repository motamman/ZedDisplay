/// Data models for the Anchor Alarm Tool
/// Integrates with SignalK anchor alarm plugin

/// Alarm states matching SignalK notification states
enum AnchorAlarmState {
  normal,
  warn,
  alarm,
  emergency;

  /// Parse from SignalK notification state string
  static AnchorAlarmState fromString(String? state) {
    switch (state?.toLowerCase()) {
      case 'warn':
        return AnchorAlarmState.warn;
      case 'alarm':
        return AnchorAlarmState.alarm;
      case 'emergency':
        return AnchorAlarmState.emergency;
      default:
        return AnchorAlarmState.normal;
    }
  }

  /// Whether this state should trigger an alarm sound
  bool get isAlarming => this == alarm || this == emergency;

  /// Whether this state should show a warning indicator
  bool get isWarning => this == warn || isAlarming;
}

/// Anchor position with optional depth
class AnchorPosition {
  final double latitude;
  final double longitude;
  final double? altitude; // Depth as negative value (meters below surface)

  const AnchorPosition({
    required this.latitude,
    required this.longitude,
    this.altitude,
  });

  /// Create from SignalK position value object
  factory AnchorPosition.fromSignalK(Map<String, dynamic> json) {
    return AnchorPosition(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      altitude: json['altitude'] != null ? (json['altitude'] as num).toDouble() : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    if (altitude != null) 'altitude': altitude,
  };

  @override
  String toString() => 'AnchorPosition($latitude, $longitude, depth: $altitude)';
}

/// Track point for vessel history
class TrackPoint {
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  const TrackPoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  factory TrackPoint.fromJson(Map<String, dynamic> json) {
    return TrackPoint(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      timestamp: json['timestamp'] is String
          ? DateTime.parse(json['timestamp'] as String)
          : json['timestamp'] as DateTime,
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// Check-in configuration for vigilance monitoring
class CheckInConfig {
  final bool enabled;
  final Duration interval;
  final Duration gracePeriod;
  final String? customMessage;

  const CheckInConfig({
    this.enabled = false,
    this.interval = const Duration(minutes: 30),
    this.gracePeriod = const Duration(seconds: 60),
    this.customMessage,
  });

  factory CheckInConfig.fromJson(Map<String, dynamic> json) {
    return CheckInConfig(
      enabled: json['enabled'] as bool? ?? false,
      interval: Duration(minutes: json['intervalMinutes'] as int? ?? 30),
      gracePeriod: Duration(seconds: json['gracePeriodSeconds'] as int? ?? 60),
      customMessage: json['customMessage'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'intervalMinutes': interval.inMinutes,
    'gracePeriodSeconds': gracePeriod.inSeconds,
    if (customMessage != null) 'customMessage': customMessage,
  };

  CheckInConfig copyWith({
    bool? enabled,
    Duration? interval,
    Duration? gracePeriod,
    String? customMessage,
  }) {
    return CheckInConfig(
      enabled: enabled ?? this.enabled,
      interval: interval ?? this.interval,
      gracePeriod: gracePeriod ?? this.gracePeriod,
      customMessage: customMessage ?? this.customMessage,
    );
  }
}

/// Complete anchor alarm state
class AnchorState {
  /// Whether anchor alarm is active/deployed
  final bool isActive;

  /// Anchor GPS position
  final AnchorPosition? anchorPosition;

  /// Maximum alarm radius in meters
  final double? maxRadius;

  /// Current distance from vessel to anchor in meters
  final double? currentRadius;

  /// Length of anchor rode deployed in meters
  final double? rodeLength;

  /// Distance from bow to anchor in meters
  final double? distanceFromBow;

  /// True bearing from vessel to anchor in radians
  final double? bearingTrue;

  /// Apparent bearing relative to vessel heading in radians
  final double? apparentBearing;

  /// Current alarm state
  final AnchorAlarmState alarmState;

  /// Alarm notification message
  final String? alarmMessage;

  /// Vessel position
  final AnchorPosition? vesselPosition;

  /// Vessel heading in degrees
  final double? vesselHeading;

  const AnchorState({
    this.isActive = false,
    this.anchorPosition,
    this.maxRadius,
    this.currentRadius,
    this.rodeLength,
    this.distanceFromBow,
    this.bearingTrue,
    this.apparentBearing,
    this.alarmState = AnchorAlarmState.normal,
    this.alarmMessage,
    this.vesselPosition,
    this.vesselHeading,
  });

  /// Create initial empty state
  factory AnchorState.initial() => const AnchorState();

  /// Calculate bearing in degrees (0-360) from radians
  double? get bearingDegrees {
    if (bearingTrue == null) return null;
    final degrees = bearingTrue! * 180 / 3.14159265359;
    return (degrees + 360) % 360;
  }

  /// Get percentage of radius used (0-100+)
  double? get radiusPercentage {
    if (currentRadius == null || maxRadius == null || maxRadius == 0) return null;
    return (currentRadius! / maxRadius!) * 100;
  }

  /// Whether vessel is within safe zone
  bool get isWithinRadius {
    if (currentRadius == null || maxRadius == null) return true;
    return currentRadius! <= maxRadius!;
  }

  /// Copy with new values
  AnchorState copyWith({
    bool? isActive,
    AnchorPosition? anchorPosition,
    double? maxRadius,
    double? currentRadius,
    double? rodeLength,
    double? distanceFromBow,
    double? bearingTrue,
    double? apparentBearing,
    AnchorAlarmState? alarmState,
    String? alarmMessage,
    AnchorPosition? vesselPosition,
    double? vesselHeading,
  }) {
    return AnchorState(
      isActive: isActive ?? this.isActive,
      anchorPosition: anchorPosition ?? this.anchorPosition,
      maxRadius: maxRadius ?? this.maxRadius,
      currentRadius: currentRadius ?? this.currentRadius,
      rodeLength: rodeLength ?? this.rodeLength,
      distanceFromBow: distanceFromBow ?? this.distanceFromBow,
      bearingTrue: bearingTrue ?? this.bearingTrue,
      apparentBearing: apparentBearing ?? this.apparentBearing,
      alarmState: alarmState ?? this.alarmState,
      alarmMessage: alarmMessage ?? this.alarmMessage,
      vesselPosition: vesselPosition ?? this.vesselPosition,
      vesselHeading: vesselHeading ?? this.vesselHeading,
    );
  }

  @override
  String toString() => 'AnchorState(active: $isActive, distance: $currentRadius/$maxRadius, state: $alarmState)';
}
