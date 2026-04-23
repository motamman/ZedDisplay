import 'package:flutter/material.dart' show Color;

/// One colour stop in a weather-layer legend. `value` is always in the
/// SI unit the server ships — m/s for wind/current speed, a
/// dimensionless index for roughness. The UI converts for display via
/// `MetadataStore`.
class LegendStop {
  const LegendStop({
    required this.value,
    required this.color,
    required this.units,
  });

  final double value;
  final Color color;
  final String units;
}

/// Parsed `GET /<layer>/metadata` payload from the route-planner
/// server. One instance per weather layer. Primarily drives the legend
/// strip + freshness chip that appear under each toggle in the chart
/// plotter's layer sheet.
class WeatherLayerMetadata {
  const WeatherLayerMetadata({
    required this.id,
    required this.title,
    required this.legendTitle,
    required this.valueUnits,
    required this.stops,
    this.description,
    this.valueMin,
    this.valueMax,
    this.serverTime,
    this.lastUpdate,
    this.refreshCadence,
    this.attribution,
  });

  final String id;
  final String title;
  final String legendTitle;
  final String valueUnits;
  final double? valueMin;
  final double? valueMax;
  final List<LegendStop> stops;
  final DateTime? serverTime;
  final DateTime? lastUpdate;
  final String? refreshCadence;
  final String? attribution;
  final String? description;

  factory WeatherLayerMetadata.fromJson(Map<String, dynamic> j) {
    final legend = j['legend'] as Map<String, dynamic>? ?? const {};
    final rawStops = legend['stops'] as List? ?? const [];
    final stops = rawStops
        .whereType<Map<String, dynamic>>()
        .map(_parseStop)
        .whereType<LegendStop>()
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    final units = j['units'] as Map<String, dynamic>? ?? const {};
    final valueRange = j['value_range'] as Map<String, dynamic>? ?? const {};

    return WeatherLayerMetadata(
      id: (j['id'] as String?) ?? '',
      title: (j['title'] as String?) ?? '',
      description: j['description'] as String?,
      legendTitle: (legend['title'] as String?) ?? '',
      valueUnits: (valueRange['units'] as String?) ??
          (units['speed'] as String?) ??
          '',
      valueMin: (valueRange['min'] as num?)?.toDouble(),
      valueMax: (valueRange['max'] as num?)?.toDouble(),
      stops: stops,
      serverTime: _parseTs(j['server_time']),
      lastUpdate: _parseTs(j['last_update']),
      refreshCadence: j['refresh_cadence'] as String?,
      attribution: j['attribution'] as String?,
    );
  }

  static LegendStop? _parseStop(Map<String, dynamic> m) {
    final value = (m['value'] as num?)?.toDouble();
    final colorStr = m['color'] as String?;
    if (value == null || colorStr == null) return null;
    final color = _parseHexColor(colorStr);
    if (color == null) return null;
    return LegendStop(
      value: value,
      color: color,
      units: (m['units'] as String?) ?? '',
    );
  }

  /// Accepts `#RRGGBB` or `#AARRGGBB`; returns null on malformed input.
  static Color? _parseHexColor(String s) {
    var hex = s.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length == 6) {
      final v = int.tryParse(hex, radix: 16);
      return v == null ? null : Color(0xFF000000 | v);
    }
    if (hex.length == 8) {
      final v = int.tryParse(hex, radix: 16);
      return v == null ? null : Color(v);
    }
    return null;
  }

  static DateTime? _parseTs(dynamic v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v);
  }
}
