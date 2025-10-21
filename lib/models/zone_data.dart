/// Model classes for SignalK Zone data from units-preference API
class PathZones {
  final String path;
  final String baseUnit;
  final String targetUnit;
  final String displayFormat;
  final List<ZoneDefinition> zones;
  final DateTime timestamp;

  PathZones({
    required this.path,
    required this.baseUnit,
    required this.targetUnit,
    required this.displayFormat,
    required this.zones,
    required this.timestamp,
  });

  factory PathZones.fromJson(Map<String, dynamic> json) {
    return PathZones(
      path: json['path'] ?? '',
      baseUnit: json['baseUnit'] ?? '',
      targetUnit: json['targetUnit'] ?? '',
      displayFormat: json['displayFormat'] ?? '0.0',
      zones: (json['zones'] as List?)
              ?.map((z) => ZoneDefinition.fromJson(z))
              .toList() ??
          [],
      timestamp: DateTime.parse(
        json['timestamp'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'baseUnit': baseUnit,
      'targetUnit': targetUnit,
      'displayFormat': displayFormat,
      'zones': zones.map((z) => z.toJson()).toList(),
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Check if zones are defined
  bool get hasZones => zones.isNotEmpty;
}

class ZoneDefinition {
  final ZoneState state;
  final double? lower;
  final double? upper;
  final String? message;

  ZoneDefinition({
    required this.state,
    this.lower,
    this.upper,
    this.message,
  });

  factory ZoneDefinition.fromJson(Map<String, dynamic> json) {
    return ZoneDefinition(
      state: ZoneState.fromString(json['state'] ?? 'normal'),
      lower: json['lower']?.toDouble(),
      upper: json['upper']?.toDouble(),
      message: json['message'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'state': state.value,
      if (lower != null) 'lower': lower,
      if (upper != null) 'upper': upper,
      if (message != null) 'message': message,
    };
  }

  /// Check if this zone is unbounded below
  bool get isUnboundedBelow => lower == null;

  /// Check if this zone is unbounded above
  bool get isUnboundedAbove => upper == null;

  /// Check if a value falls within this zone
  bool contains(double value) {
    final aboveLower = lower == null || value >= lower!;
    final belowUpper = upper == null || value <= upper!;
    return aboveLower && belowUpper;
  }
}

/// SignalK zone states
enum ZoneState {
  normal('normal'),
  nominal('nominal'),
  alert('alert'),
  warn('warn'),
  alarm('alarm'),
  emergency('emergency');

  final String value;
  const ZoneState(this.value);

  factory ZoneState.fromString(String value) {
    return ZoneState.values.firstWhere(
      (e) => e.value == value.toLowerCase(),
      orElse: () => ZoneState.normal,
    );
  }
}

/// Response for bulk zones query
class BulkZonesResponse {
  final Map<String, PathZones> zones;
  final DateTime timestamp;

  BulkZonesResponse({
    required this.zones,
    required this.timestamp,
  });

  factory BulkZonesResponse.fromJson(Map<String, dynamic> json) {
    final zonesMap = <String, PathZones>{};
    final zonesData = json['zones'] as Map<String, dynamic>? ?? {};

    for (final entry in zonesData.entries) {
      zonesMap[entry.key] = PathZones.fromJson({
        'path': entry.key,
        ...entry.value as Map<String, dynamic>,
      });
    }

    return BulkZonesResponse(
      zones: zonesMap,
      timestamp: DateTime.parse(
        json['timestamp'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }
}
