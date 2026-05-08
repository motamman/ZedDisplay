import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart' show BuiltInMapCachingProvider;
import 'package:http/http.dart' as http;

import '../models/weather_layer_metadata.dart';
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
  WeatherDataService(this._auth) {
    // Match the server's own refresh cadence —
    // `routePlanning/routing/settings.py:138` sets
    // `wind_refresh_poll_seconds = 3 * 3600` and `:130` sets
    // `stofs_refresh_poll_seconds = 3 * 3600`. The server polls for a
    // new HRES cycle / STOFS run every 3 hours; without a matching
    // client bump, past-hour tiles stay `immutable` for 24 h and we
    // would serve the pre-refresh forecast forever.
    _refreshTimer = Timer.periodic(
      const Duration(hours: 3),
      (_) {
        _cacheNonce = DateTime.now().millisecondsSinceEpoch;
        _vectorCache.clear();
        _vectorLru.clear();
        unawaited(_fetchAllMetadata());
        notifyListeners();
      },
    );
    unawaited(_fetchAllMetadata());
  }

  final RoutePlannerAuthService _auth;
  Timer? _refreshTimer;

  String _baseUrl = 'https://router.zeddisplay.com';
  String get baseUrl => _baseUrl;
  set baseUrl(String v) {
    final trimmed = v.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed == _baseUrl) return;
    _baseUrl = trimmed;
    _vectorCache.clear();
    _vectorLru.clear();
    _metadata.clear();
    unawaited(_fetchAllMetadata());
    notifyListeners();
  }

  // ===== Per-layer metadata (legend + freshness) =====
  //
  // Keyed by layer path (e.g. `/wind`, `/roughness`). Populated
  // asynchronously; tiles that don't yet have metadata simply hide
  // their legend expansion until it lands.
  static const List<String> _metadataPaths = [
    '/wind',
    '/currents',
    '/wind-heatmap',
    '/current-heatmap',
    '/roughness',
    '/wave-heatmap',
    '/precip-heatmap',
    '/depth',
    '/temperature',
    '/sst',
  ];
  final Map<String, WeatherLayerMetadata> _metadata = {};
  WeatherLayerMetadata? metadataFor(String path) => _metadata[path];

  // -------------------------------------------------------------------
  // Tile load instrumentation.
  //
  // The chart plotter's `_WeatherTileProvider` calls into these counters
  // when flutter_map asks it for a tile image. We track:
  //   - `_inFlight[path]` — number of tile requests currently awaiting
  //     a decoded image or error. Drives the player's per-hour gating
  //     (advance only when in-flight reaches 0, with a 5 s max-wait
  //     fallback) and the per-layer status chips on the player strip.
  //   - `_tileLastSuccess[path]` — wall-clock of the most recent
  //     successfully-decoded tile for that layer.
  //   - `_tileLastError[path]` — the most recent error object, kept
  //     until either a fresh success arrives or the user reloads.
  // All updates `notifyListeners` so the strip can rebuild.
  // -------------------------------------------------------------------

  final Map<String, int> _inFlight = {};
  final Map<String, DateTime> _tileLastSuccess = {};
  final Map<String, Object?> _tileLastError = {};

  int inFlightCount(String path) => _inFlight[path] ?? 0;
  DateTime? tileLastSuccess(String path) => _tileLastSuccess[path];
  Object? tileLastError(String path) => _tileLastError[path];

  /// Has *any* tile for `path` ever resolved successfully on this
  /// service instance? Useful for distinguishing "still waiting on
  /// the very first fetch" from "loaded and current".
  bool hasEverLoaded(String path) => _tileLastSuccess.containsKey(path);

  void recordTileStart(String path) {
    _inFlight[path] = (_inFlight[path] ?? 0) + 1;
    notifyListeners();
  }

  void recordTileSuccess(String path) {
    final n = _inFlight[path] ?? 0;
    if (n > 0) _inFlight[path] = n - 1;
    _tileLastSuccess[path] = DateTime.now();
    // Successful fetch trumps any stale error from a previous attempt.
    _tileLastError.remove(path);
    notifyListeners();
  }

  void recordTileError(String path, Object error) {
    final n = _inFlight[path] ?? 0;
    if (n > 0) _inFlight[path] = n - 1;
    _tileLastError[path] = error;
    notifyListeners();
  }

  Future<void> _fetchAllMetadata() => refreshMetadata();

  /// Re-fetch every layer's metadata in parallel. Public so the
  /// chart-layer sheet's Weather tab can drive a manual refresh
  /// when the user thinks the legend / unit info is stale (server
  /// was slow to publish, container just woke up, etc.).
  Future<void> refreshMetadata() async {
    await Future.wait(_metadataPaths.map(_fetchMetadata));
    notifyListeners();
  }

  Future<void> _fetchMetadata(String path) async {
    final uri = Uri.parse('$_baseUrl$path/metadata');
    try {
      final resp = await http
          .get(uri, headers: _auth.authorisedHeaders())
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return;
      final json = jsonDecode(resp.body);
      if (json is! Map<String, dynamic>) return;
      _metadata[path] = WeatherLayerMetadata.fromJson(json);
    } catch (_) {
      // Silent fail — the UI falls back to "no legend".
    }
  }

  /// Monotonically-increasing nonce appended to every tile URL so a
  /// reload produces a new cache key. flutter_map also keeps an
  /// on-disk cache (`BuiltInMapCachingProvider`, enabled by default in
  /// `NetworkTileImageProvider`, keyed on URL, respects the server's
  /// `Cache-Control: immutable` for 24 h) — that cache is wiped
  /// separately in `reloadTiles()` below.
  int _cacheNonce = DateTime.now().millisecondsSinceEpoch;
  int get cacheNonce => _cacheNonce;

  /// Hard wipe of every cache in the tile path:
  ///   1. In-service vector LRU (mine).
  ///   2. `BuiltInMapCachingProvider` singleton — destroys the worker
  ///      AND deletes the on-disk `fm_cache` directory. Next tile
  ///      request re-initialises a fresh, empty cache.
  ///   3. Flutter's global `PaintingBinding.instance.imageCache` via
  ///      a nonce bump + key swap — flutter_map's in-widget
  ///      `_tileImageManager` keys decoded images on `ImageProvider`,
  ///      which keys on URL, so a new URL is a miss.
  Future<void> reloadTiles() async {
    final oldNonce = _cacheNonce;
    _cacheNonce = DateTime.now().millisecondsSinceEpoch;
    _vectorCache.clear();
    _vectorLru.clear();
    // Tile-load indicators are bound to the (path, current nonce)
    // pairing. Cache wipe means the next fetch is the new "first"
    // load, so reset success / error / in-flight maps too — without
    // this, a stale "loaded ✓" chip would persist across the wipe
    // until the next tile actually arrived.
    _inFlight.clear();
    _tileLastSuccess.clear();
    _tileLastError.clear();
    debugPrint(
        '[WeatherDataService] reloadTiles() called: nonce $oldNonce -> $_cacheNonce');
    try {
      await BuiltInMapCachingProvider.getOrCreateInstance()
          .destroy(deleteCache: true);
      debugPrint('[WeatherDataService] on-disk tile cache destroyed');
    } catch (e) {
      debugPrint('[WeatherDataService] tile cache wipe failed: $e');
    }
    // Pull fresh metadata too — server's `last_update` may have
    // advanced since initial load.
    unawaited(_fetchAllMetadata());
    debugPrint(
        '[WeatherDataService] next heatmap URL template: '
        '${heatmapUrlTemplate('/roughness')}');
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

  /// URL template consumed by `TileLayer.urlTemplate`. `{z}`, `{x}`,
  /// and `{y}` are substituted by flutter_map. `t=` is the current
  /// reference hour. `v=` is a cache-busting nonce — flutter_map's
  /// in-widget cache keys on the full URL string, and the only way to
  /// force a refetch when the server's rendering has changed (same
  /// hour) is to make the template differ.
  String heatmapUrlTemplate(String path) =>
      '$_baseUrl$path/{z}/{x}/{y}.png?t=$hourParam&v=$_cacheNonce';

  /// Headers that every tile request (raster and JSON) must carry.
  Map<String, String> get authHeaders => _auth.authorisedHeaders();

  /// Default zoom floors. Standardised at **5** for every layer.
  ///
  /// These are floors, not server gates: when server metadata
  /// publishes a tighter `minzoom`, that wins via
  /// `_effectiveMinZoom`'s `max(metadata, fallback)` clamp.
  static const int zoomFloorWindBarbs = 5;
  static const int zoomFloorCurrents = 5;
  static const int zoomFloorWindHeatmap = 5;
  static const int zoomFloorCurrentHeatmap = 5;
  static const int zoomFloorSeaState = 5;
  static const int zoomFloorWaveHeatmap = 5;
  static const int zoomFloorPrecipHeatmap = 5;
  static const int zoomFloorDepth = 5;
  /// `/temperature`: 2-metre air temperature heatmap PNG (ECMWF
  /// HRES `2t`/`t2m`). Server returns 204 below z=5.
  static const int zoomFloorTemperature = 5;
  /// `/sst`: sea-surface skin temperature heatmap PNG (ECMWF HRES
  /// `skt`); land cells alpha-masked via the OSM land polygon
  /// raster. Server returns 204 below z=5.
  static const int zoomFloorSst = 5;

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
    final key = '$path|$z|$x|$y|$hour|$_cacheNonce';
    final cached = _vectorCache[key];
    if (cached != null) {
      _touchLru(key);
      return cached;
    }
    final uri = Uri.parse(
        '$_baseUrl$path/$z/$x/$y.json?t=$hour&v=$_cacheNonce');
    try {
      final resp = await http
          .get(uri, headers: _auth.authorisedHeaders())
          .timeout(const Duration(seconds: 15));
      // Return null on any non-success / malformed-shape so the
      // overlay treats it as a transient failure and retries on the
      // next camera tick. Returning `const []` here would be
      // indistinguishable from "tile is legitimately empty" and get
      // memoized by the overlay's fingerprint.
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      if (data is! List) return null;
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
    _refreshTimer?.cancel();
    _vectorCache.clear();
    _vectorLru.clear();
    super.dispose();
  }

  static DateTime _hourBucket(DateTime t) {
    final u = t.toUtc();
    return DateTime.utc(u.year, u.month, u.day, u.hour);
  }
}
