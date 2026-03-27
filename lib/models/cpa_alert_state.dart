import 'dart:convert';

enum CpaAlertLevel {
  normal,
  warning,
  alarm;

  bool get isAlarming => this == alarm;
  bool get isWarning => this == warning || isAlarming;
}

class CpaVesselAlert {
  final String vesselId;
  final String? vesselName;
  final CpaAlertLevel level;
  final double cpaMeters;
  final double tcpaSeconds;
  final DateTime firstAlerted;
  final DateTime lastUpdated;
  final DateTime? cooldownUntil;
  final DateTime? divergingSince; // When vessel first showed as diverging

  const CpaVesselAlert({
    required this.vesselId,
    this.vesselName,
    required this.level,
    required this.cpaMeters,
    required this.tcpaSeconds,
    required this.firstAlerted,
    required this.lastUpdated,
    this.cooldownUntil,
    this.divergingSince,
  });

  CpaVesselAlert copyWith({
    CpaAlertLevel? level,
    double? cpaMeters,
    double? tcpaSeconds,
    DateTime? lastUpdated,
    DateTime? cooldownUntil,
    DateTime? divergingSince,
    String? vesselName,
    bool clearDivergingSince = false,
  }) {
    return CpaVesselAlert(
      vesselId: vesselId,
      vesselName: vesselName ?? this.vesselName,
      level: level ?? this.level,
      cpaMeters: cpaMeters ?? this.cpaMeters,
      tcpaSeconds: tcpaSeconds ?? this.tcpaSeconds,
      firstAlerted: firstAlerted,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      cooldownUntil: cooldownUntil,
      divergingSince: clearDivergingSince ? null : (divergingSince ?? this.divergingSince),
    );
  }
}

class CpaAlertConfig {
  final bool enabled;
  final double warnThresholdMeters;
  final double alarmThresholdMeters;
  final double tcpaThresholdSeconds;
  final String alarmSound;
  final int cooldownSeconds;
  final bool sendCrewAlert;
  final double maxRangeMeters; // Max range filter — ignore vessels beyond this distance

  const CpaAlertConfig({
    this.enabled = true,
    this.warnThresholdMeters = 1852.0, // 1 nm
    this.alarmThresholdMeters = 926.0, // 0.5 nm
    this.tcpaThresholdSeconds = 1800.0, // 30 min
    this.alarmSound = 'foghorn',
    this.cooldownSeconds = 300, // 5 min
    this.sendCrewAlert = false,
    this.maxRangeMeters = 185200.0, // 100 nm
  });

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'warnThresholdMeters': warnThresholdMeters,
        'alarmThresholdMeters': alarmThresholdMeters,
        'tcpaThresholdSeconds': tcpaThresholdSeconds,
        'alarmSound': alarmSound,
        'cooldownSeconds': cooldownSeconds,
        'sendCrewAlert': sendCrewAlert,
        'maxRangeMeters': maxRangeMeters,
      };

  factory CpaAlertConfig.fromJson(Map<String, dynamic> json) {
    return CpaAlertConfig(
      enabled: json['enabled'] as bool? ?? true,
      warnThresholdMeters:
          (json['warnThresholdMeters'] as num?)?.toDouble() ?? 1852.0,
      alarmThresholdMeters:
          (json['alarmThresholdMeters'] as num?)?.toDouble() ?? 926.0,
      tcpaThresholdSeconds:
          (json['tcpaThresholdSeconds'] as num?)?.toDouble() ?? 1800.0,
      alarmSound: json['alarmSound'] as String? ?? 'foghorn',
      cooldownSeconds: json['cooldownSeconds'] as int? ?? 300,
      sendCrewAlert: json['sendCrewAlert'] as bool? ?? true,
      maxRangeMeters:
          (json['maxRangeMeters'] as num?)?.toDouble() ?? 185200.0,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory CpaAlertConfig.fromJsonString(String jsonString) {
    return CpaAlertConfig.fromJson(
        jsonDecode(jsonString) as Map<String, dynamic>);
  }
}
