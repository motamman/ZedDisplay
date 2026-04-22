import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'route_planner_auth_service.dart';

/// One sample from the `/wind/{z}/{x}/{y}.json` or
/// `/currents/{z}/{x}/{y}.json` vector tile endpoints. SI units.
///
/// Wind: `dirDeg` is the meteorological FROM direction.
/// Currents: `dirDeg` is the SET (TO) direction; `uMs` / `vMs` are the
/// east / north components when present on the payload.
class WeatherVectorPoint {
  const WeatherVectorPoint({
    required this.lat,
    required this.lon,
    required this.speedMs,
    required this.dirDeg,
    this.uMs,
    this.vMs,
  });

  final double lat;
  final double lon;
  final double speedMs;
  final double dirDeg;
  final double? uMs;
  final double? vMs;
}

/// Thin wrapper around the route planner's XYZ-tiled weather endpoints.
///
/// Raster heatmaps (wind / current / roughness "sea state") are consumed
/// by flutter_map's `TileLayer` directly — this service hands out the URL
/// templates and auth headers. Vector tile JSON is fetched here because
/// flutter_map has no JSON-tile primitive; a small LRU plus hour-keyed
/// URLs mean each tile is fetched once per hour per session.
///
/// Reference-time precedence is set by the chart plotter: selected
/// waypoint's time → planned departure → now. The service rounds to the
/// UTC hour for URL construction — all four endpoints require hour-
/// truncated `t` and 400 otherwise.
class WeatherDataService extends ChangeNotifier {
  WeatherDataService(this._auth);

  final RoutePlannerAuthService _auth;

  String _baseUrl = 'https://router.zeddisplay.com';
  String get baseUrl => _baseUrl;
  set baseUrl(String v) {
    final trimmed = v.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed == _baseUrl) return;
    _baseUrl = trimmed;
    _vectorCache.clear();
    _vectorLru.clear();
    notifyListeners();
  }

  DateTime _referenceTime = DateTime.now();
  DateTime get referenceTime => _referenceTime;

  /// Updating the reference time is cheap unless the UTC hour changes,
  /// in which case every tile layer rebuilds and every vector tile is
  /// re-fetched (from cache when possible).
  set referenceTime(DateTime v) {
    final oldHour = _hourBucket(_referenceTime);
    final newHour = _hourBucket(v);
    _referenceTime = v;
    if (oldHour != newHour) {
      notifyListeners();
    }
  }

  /// UTC hour string used as the `t=` query param on every endpoint.
  /// Matches the server's `round_t_to_hour` parser exactly.
  String get hourParam {
    final u = _hourBucket(_referenceTime);
    final yyyy = u.year.toString().padLeft(4, '0');
    final mm = u.month.toString().padLeft(2, '0');
    final dd = u.day.toString().padLeft(2, '0');
    final hh = u.hour.toString().padLeft(2, '0');
    return '$yyyy-$mm-${dd}T$hh';
  }

  /// URL template consumed by `TileLayer.urlTemplate`. `{z}`, `{x}`, and
  /// `{y}` are substituted by flutter_map; `t=` is static for the
  /// current reference hour (the layer gets a new template when the
  /// hour flips so tiles for the old hour prune).
  String heatmapUrlTemplate(String path) =>
      '$_baseUrl$path/{z}/{x}/{y}.png?t=$hourParam';

  /// Headers that every tile request (raster and JSON) must carry.
  Map<String, String> get authHeaders => _auth.authorisedHeaders();

  /// Zoom floors mirror the server's gates so we don't hit the network
  /// for a guaranteed-empty response.
  static const int zoomFloorWindBarbs = 6;
  static const int zoomFloorCurrents = 11;
  static const int zoomFloorWindHeatmap = 5;
  static const int zoomFloorCurrentHeatmap = 9;
  static const int zoomFloorSeaState = 9;

  // ===== Vector tile cache =====
  //
  // Keyed by `path|z|x|y|hour`. LRU via parallel list (MRU at end).
  // Small tiles (100-200 points × ~48 bytes each) mean 256 entries fit
  // comfortably in under 2 MB.
  final Map<String, List<WeatherVectorPoint>> _vectorCache = {};
  final List<String> _vectorLru = [];
  static const int _vectorCacheMax = 256;

  /// Fetch one vector tile. Returns cached payload immediately when
  /// available (synchronous), otherwise awaits the HTTP round trip.
  /// Returns `null` on transient failure — callers should treat that
  /// as "try again next camera tick" rather than persist empty.
  Future<List<WeatherVectorPoint>?> fetchVectorTile(
      String path, int z, int x, int y) async {
    final hour = hourParam;
    final key = '$path|$z|$x|$y|$hour';
    final cached = _vectorCache[key];
    if (cached != null) {
      _touchLru(key);
      return cached;
    }
    final uri = Uri.parse('$_baseUrl$path/$z/$x/$y.json?t=$hour');
    try {
      final resp = await http
          .get(uri, headers: _auth.authorisedHeaders())
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body);
      if (data is! List) return const [];
      final points = data
          .whereType<Map<String, dynamic>>()
          .map((m) => WeatherVectorPoint(
                lat: (m['lat'] as num?)?.toDouble() ?? 0.0,
                lon: (m['lon'] as num?)?.toDouble() ?? 0.0,
                speedMs: (m['speed_ms'] as num?)?.toDouble() ?? 0.0,
                dirDeg: (m['dir_deg'] as num?)?.toDouble() ?? 0.0,
                uMs: (m['u_ms'] as num?)?.toDouble(),
                vMs: (m['v_ms'] as num?)?.toDouble(),
              ))
          .toList(growable: false);
      _vectorCache[key] = points;
      _vectorLru.add(key);
      while (_vectorLru.length > _vectorCacheMax) {
        final evict = _vectorLru.removeAt(0);
        _vectorCache.remove(evict);
      }
      return points;
    } catch (_) {
      return null;
    }
  }

  void _touchLru(String key) {
    _vectorLru.remove(key);
    _vectorLru.add(key);
  }

  @override
  void dispose() {
    _vectorCache.clear();
    _vectorLru.clear();
    super.dispose();
  }

  static DateTime _hourBucket(DateTime t) {
    final u = t.toUtc();
    return DateTime.utc(u.year, u.month, u.day, u.hour);
  }
}
