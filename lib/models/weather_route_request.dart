/// Dart mirrors of the route-planner POST /api/v1/routes request body.
///
/// Every field is on-the-wire SI and matches the Pydantic models at
/// `routePlanning/routing/routers/routes.py` (RouteRequest, LatLon,
/// VesselOverride). Optional fields serialise to absent keys when null.
library;

enum RouteMode {
  /// Sail-first: only motor when wind can't drive the boat.
  sailMax,
  /// Whichever is faster at each step.
  fastest,
  /// Motor the whole way, ignoring sails.
  motor;

  String get wire {
    switch (this) {
      case RouteMode.sailMax:
        return 'sail_max';
      case RouteMode.fastest:
        return 'fastest';
      case RouteMode.motor:
        return 'motor';
    }
  }

  String get label {
    switch (this) {
      case RouteMode.sailMax:
        return 'Sail max';
      case RouteMode.fastest:
        return 'Fastest';
      case RouteMode.motor:
        return 'Motor';
    }
  }

  static RouteMode fromWire(String? s) {
    switch (s) {
      case 'fastest':
        return RouteMode.fastest;
      case 'motor':
        return RouteMode.motor;
      case 'sail_max':
      default:
        return RouteMode.sailMax;
    }
  }
}

class LatLon {
  const LatLon({required this.lat, required this.lon});
  final double lat;
  final double lon;

  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon};

  factory LatLon.fromJson(Map<String, dynamic> j) => LatLon(
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
      );
}

/// Per-request vessel parameters. Any unset field falls through to the
/// server's default vessel.yaml. Units match the server: meters,
/// meters/second.
class VesselOverride {
  const VesselOverride({
    this.name,
    this.draught,
    this.airDraft,
    this.loa,
    this.beam,
    this.motorSpeedMs,
  });

  final String? name;
  final double? draught;
  final double? airDraft;
  final double? loa;
  final double? beam;
  final double? motorSpeedMs;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (name != null) m['name'] = name;
    if (draught != null) m['draught'] = draught;
    if (airDraft != null) m['air_draft'] = airDraft;
    if (loa != null) m['loa'] = loa;
    if (beam != null) m['beam'] = beam;
    if (motorSpeedMs != null) m['motor_speed_ms'] = motorSpeedMs;
    return m;
  }
}

class WeatherRouteRequest {
  const WeatherRouteRequest({
    required this.start,
    required this.end,
    this.waypoints = const [],
    this.mode = RouteMode.sailMax,
    this.departure,
    this.sailThresh,
    this.tackPenalty,
    this.owStep,
    this.isoStep,
    this.landBuffer,
    this.shoreStep,
    this.underKeelClearance,
    this.simplify,
    this.polar,
    this.vessel,
  });

  final LatLon start;
  final LatLon end;
  final List<LatLon> waypoints;
  final RouteMode mode;
  final DateTime? departure;
  final double? sailThresh;
  final double? tackPenalty;
  final double? owStep;
  final double? isoStep;
  final int? landBuffer;
  final double? shoreStep;
  final double? underKeelClearance;
  final double? simplify;
  final String? polar;
  final VesselOverride? vessel;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'start': start.toJson(),
      'end': end.toJson(),
      'mode': mode.wire,
    };
    if (waypoints.isNotEmpty) {
      m['waypoints'] = waypoints.map((w) => w.toJson()).toList();
    }
    if (departure != null) {
      m['departure'] = departure!.toUtc().toIso8601String();
    }
    if (sailThresh != null) m['sail_thresh'] = sailThresh;
    if (tackPenalty != null) m['tack_penalty'] = tackPenalty;
    if (owStep != null) m['ow_step'] = owStep;
    if (isoStep != null) m['iso_step'] = isoStep;
    if (landBuffer != null) m['land_buffer'] = landBuffer;
    if (shoreStep != null) m['shore_step'] = shoreStep;
    if (underKeelClearance != null) {
      m['under_keel_clearance'] = underKeelClearance;
    }
    if (simplify != null) m['simplify'] = simplify;
    if (polar != null && polar!.isNotEmpty) m['polar'] = polar;
    if (vessel != null) {
      final v = vessel!.toJson();
      if (v.isNotEmpty) m['vessel'] = v;
    }
    return m;
  }
}
