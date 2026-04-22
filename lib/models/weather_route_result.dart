/// Dart mirrors of the GeoJSON returned by GET /api/v1/routes/{id}/result.
///
/// The server returns a FeatureCollection containing exactly one LineString
/// Feature (`properties` = route summary) and one Point Feature per
/// waypoint (`properties` = per-waypoint environmental data).
/// Mirrors `routePlanning/routing/output/route.py`.
library;

class WeatherRouteSummary {
  const WeatherRouteSummary({
    this.totalDistanceM,
    this.totalTimeS,
    this.motoringTimeS,
    this.sailingTimeS,
    this.departure,
    this.arrival,
    this.waypointCount,
    this.maxSwhM,
    this.avgSwhM,
  });

  final double? totalDistanceM;
  final double? totalTimeS;
  final double? motoringTimeS;
  final double? sailingTimeS;
  final DateTime? departure;
  final DateTime? arrival;
  final int? waypointCount;
  final double? maxSwhM;
  final double? avgSwhM;

  factory WeatherRouteSummary.fromProperties(Map<String, dynamic> p) {
    DateTime? parseTs(dynamic v) {
      if (v is String && v.isNotEmpty) {
        return DateTime.tryParse(v);
      }
      return null;
    }

    return WeatherRouteSummary(
      totalDistanceM: (p['total_distance_m'] as num?)?.toDouble(),
      totalTimeS: (p['total_time_s'] as num?)?.toDouble(),
      motoringTimeS: (p['motoring_time_s'] as num?)?.toDouble(),
      sailingTimeS: (p['sailing_time_s'] as num?)?.toDouble(),
      departure: parseTs(p['departure']),
      arrival: parseTs(p['arrival']),
      waypointCount: (p['waypoint_count'] as num?)?.toInt(),
      maxSwhM: (p['max_swh_m'] as num?)?.toDouble(),
      avgSwhM: (p['avg_swh_m'] as num?)?.toDouble(),
    );
  }
}

/// A single waypoint on the computed route. All units are SI / degrees;
/// conversions to knots, nm etc. happen at the UI boundary.
class WeatherRouteWaypoint {
  const WeatherRouteWaypoint({
    required this.lat,
    required this.lon,
    this.time,
    this.sogMs,
    this.cogDeg,
    this.outgoingCogDeg,
    this.depthM,
    this.mode,
    this.twaDeg,
    this.windMs,
    this.windDirDeg,
    this.currentMs,
    this.currentDirDeg,
    this.currentUMs,
    this.currentVMs,
    this.swhM,
    this.mwpS,
    this.mwdDeg,
    this.leg,
    this.role,
  });

  final double lat;
  final double lon;
  final DateTime? time;
  final double? sogMs;
  final double? cogDeg;
  final double? outgoingCogDeg;
  final double? depthM;
  final String? mode; // 'sailing' | 'motoring'
  final double? twaDeg;
  final double? windMs;
  final double? windDirDeg;
  final double? currentMs;
  final double? currentDirDeg;
  final double? currentUMs;
  final double? currentVMs;
  final double? swhM;
  final double? mwpS;
  final double? mwdDeg;
  final String? leg;
  final String? role; // 'via' for user-specified, else null

  bool get isSailing => mode == 'sailing';
  bool get isMotoring => mode == 'motoring';
  bool get isVia => role == 'via';

  factory WeatherRouteWaypoint.fromFeature(Map<String, dynamic> feature) {
    final geometry = feature['geometry'] as Map<String, dynamic>?;
    final coords = geometry?['coordinates'] as List?;
    final lon = coords != null && coords.length >= 2
        ? (coords[0] as num).toDouble()
        : 0.0;
    final lat = coords != null && coords.length >= 2
        ? (coords[1] as num).toDouble()
        : 0.0;
    final p = (feature['properties'] as Map<String, dynamic>?) ?? const {};
    final time = p['time'] is String
        ? DateTime.tryParse(p['time'] as String)
        : null;
    return WeatherRouteWaypoint(
      lat: (p['lat'] as num?)?.toDouble() ?? lat,
      lon: (p['lon'] as num?)?.toDouble() ?? lon,
      time: time,
      sogMs: (p['sog_ms'] as num?)?.toDouble(),
      cogDeg: (p['cog_deg'] as num?)?.toDouble(),
      outgoingCogDeg: (p['outgoing_cog_deg'] as num?)?.toDouble(),
      depthM: (p['depth_m'] as num?)?.toDouble(),
      mode: p['mode'] as String?,
      twaDeg: (p['twa_deg'] as num?)?.toDouble(),
      windMs: (p['wind_ms'] as num?)?.toDouble(),
      windDirDeg: (p['wind_dir_deg'] as num?)?.toDouble(),
      currentMs: (p['current_ms'] as num?)?.toDouble(),
      currentDirDeg: (p['current_dir_deg'] as num?)?.toDouble(),
      currentUMs: (p['current_u_ms'] as num?)?.toDouble(),
      currentVMs: (p['current_v_ms'] as num?)?.toDouble(),
      swhM: (p['swh_m'] as num?)?.toDouble(),
      mwpS: (p['mwp_s'] as num?)?.toDouble(),
      mwdDeg: (p['mwd_deg'] as num?)?.toDouble(),
      leg: p['leg'] as String?,
      role: p['role'] as String?,
    );
  }
}

/// Parsed `/result` response — one polyline of coords + ordered waypoints +
/// summary stats. Waypoints are in the same order as the LineString coords.
class WeatherRouteResult {
  const WeatherRouteResult({
    required this.coords,
    required this.waypoints,
    required this.summary,
  });

  /// `[lon, lat]` pairs, matching the GeoJSON convention used elsewhere
  /// in the codebase (see `chart_plotter_v3_tool.dart:_routeCoords`).
  final List<List<double>> coords;
  final List<WeatherRouteWaypoint> waypoints;
  final WeatherRouteSummary summary;

  bool get isEmpty => coords.isEmpty;
  bool get isNotEmpty => coords.isNotEmpty;

  factory WeatherRouteResult.fromGeoJson(Map<String, dynamic> fc) {
    final features = (fc['features'] as List?) ?? const [];
    List<List<double>> lineCoords = const [];
    WeatherRouteSummary summary = const WeatherRouteSummary();
    final waypoints = <WeatherRouteWaypoint>[];

    for (final f in features) {
      if (f is! Map<String, dynamic>) continue;
      final geom = f['geometry'] as Map<String, dynamic>?;
      final type = geom?['type'] as String?;
      if (type == 'LineString') {
        final raw = geom?['coordinates'] as List? ?? const [];
        lineCoords = raw
            .whereType<List>()
            .where((c) => c.length >= 2)
            .map<List<double>>((c) => [
                  (c[0] as num).toDouble(),
                  (c[1] as num).toDouble(),
                ])
            .toList(growable: false);
        final props = f['properties'] as Map<String, dynamic>?;
        if (props != null) {
          summary = WeatherRouteSummary.fromProperties(props);
        }
      } else if (type == 'Point') {
        waypoints.add(WeatherRouteWaypoint.fromFeature(f));
      }
    }

    return WeatherRouteResult(
      coords: lineCoords,
      waypoints: waypoints,
      summary: summary,
    );
  }
}
