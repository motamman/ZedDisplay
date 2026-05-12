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
    this.startOriginal,
    this.startAnchor,
    this.startSnapDistanceM,
    this.endOriginal,
    this.endAnchor,
    this.endSnapDistanceM,
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

  /// Where the user clicked the start pin. Present whenever the
  /// router had to snap the route's actual start away from this
  /// point because the clicked cell wasn't navigable. `[lon, lat]`
  /// pair matching the GeoJSON convention. Absent when the click
  /// landed on an already-navigable cell.
  final List<double>? startOriginal;

  /// Where the route actually begins — same coords as the first
  /// `Point` feature. Always equals `coords.first` of the
  /// LineString.
  final List<double>? startAnchor;

  /// Haversine distance from [startOriginal] to [startAnchor], in
  /// metres. `null` (or `0`) means no snap was applied.
  final double? startSnapDistanceM;

  /// Same shape as [startOriginal] but for the route's end.
  final List<double>? endOriginal;
  final List<double>? endAnchor;
  final double? endSnapDistanceM;

  factory WeatherRouteSummary.fromProperties(Map<String, dynamic> p) {
    DateTime? parseTs(dynamic v) {
      if (v is String && v.isNotEmpty) {
        return DateTime.tryParse(v);
      }
      return null;
    }

    List<double>? parseLonLat(dynamic v) {
      if (v is! List || v.length < 2) return null;
      final lon = (v[0] as num?)?.toDouble();
      final lat = (v[1] as num?)?.toDouble();
      if (lon == null || lat == null) return null;
      return [lon, lat];
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
      startOriginal: parseLonLat(p['start_original']),
      startAnchor: parseLonLat(p['start_anchor']),
      startSnapDistanceM:
          (p['start_snap_distance_m'] as num?)?.toDouble(),
      endOriginal: parseLonLat(p['end_original']),
      endAnchor: parseLonLat(p['end_anchor']),
      endSnapDistanceM:
          (p['end_snap_distance_m'] as num?)?.toDouble(),
    );
  }

  /// Inverse of [fromProperties] — produces a wire-compatible map so a
  /// summary can be cached locally and re-parsed through the same
  /// pipeline. Null fields are omitted to keep the payload tight.
  Map<String, dynamic> toProperties() {
    final m = <String, dynamic>{};
    if (totalDistanceM != null) m['total_distance_m'] = totalDistanceM;
    if (totalTimeS != null) m['total_time_s'] = totalTimeS;
    if (motoringTimeS != null) m['motoring_time_s'] = motoringTimeS;
    if (sailingTimeS != null) m['sailing_time_s'] = sailingTimeS;
    if (departure != null) m['departure'] = departure!.toUtc().toIso8601String();
    if (arrival != null) m['arrival'] = arrival!.toUtc().toIso8601String();
    if (waypointCount != null) m['waypoint_count'] = waypointCount;
    if (maxSwhM != null) m['max_swh_m'] = maxSwhM;
    if (avgSwhM != null) m['avg_swh_m'] = avgSwhM;
    if (startOriginal != null) m['start_original'] = startOriginal;
    if (startAnchor != null) m['start_anchor'] = startAnchor;
    if (startSnapDistanceM != null) {
      m['start_snap_distance_m'] = startSnapDistanceM;
    }
    if (endOriginal != null) m['end_original'] = endOriginal;
    if (endAnchor != null) m['end_anchor'] = endAnchor;
    if (endSnapDistanceM != null) {
      m['end_snap_distance_m'] = endSnapDistanceM;
    }
    return m;
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
    this.legDistanceM,
    this.legTimeS,
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

  /// Distance of the leg DEPARTING this waypoint (this → next), in
  /// metres. Server-rounded to 0.1 m. Null on the arrival waypoint
  /// (no next leg). Authoritative — clients should not re-derive
  /// from haversine. Pairs with [legTimeS].
  final double? legDistanceM;

  /// Duration of the leg DEPARTING this waypoint (this → next), in
  /// seconds. Server-rounded to 0.1 s. Null on the arrival waypoint
  /// (no next leg). Reflects the route timing — for sailing legs
  /// this includes the polar-derived speed under wind/current at
  /// the leg's start time, so `legDistanceM / legTimeS` is the
  /// effective leg SOG (which can differ from `sogMs`, which is
  /// the SOG ARRIVING at this waypoint).
  final double? legTimeS;

  bool get isSailing => mode == 'sailing';
  bool get isMotoring => mode == 'motoring';
  bool get isVia => role == 'via';

  /// Copy with overridden coords. Used to build the synthetic START
  /// / END waypoint cards: those cards show the user's clicked point
  /// (`start_original` / `end_original`) but borrow the weather /
  /// timing fields from the route's actual first / last waypoint
  /// (the clicked point itself has no weather sample from the
  /// server). Only `lat` / `lon` are overridable because that's all
  /// the virtual cards need.
  WeatherRouteWaypoint copyWith({double? lat, double? lon}) =>
      WeatherRouteWaypoint(
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        time: time,
        sogMs: sogMs,
        cogDeg: cogDeg,
        outgoingCogDeg: outgoingCogDeg,
        depthM: depthM,
        mode: mode,
        twaDeg: twaDeg,
        windMs: windMs,
        windDirDeg: windDirDeg,
        currentMs: currentMs,
        currentDirDeg: currentDirDeg,
        currentUMs: currentUMs,
        currentVMs: currentVMs,
        swhM: swhM,
        mwpS: mwpS,
        mwdDeg: mwdDeg,
        leg: leg,
        role: role,
        legDistanceM: legDistanceM,
        legTimeS: legTimeS,
      );

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
      legDistanceM: (p['leg_distance_m'] as num?)?.toDouble(),
      legTimeS: (p['leg_time_s'] as num?)?.toDouble(),
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
