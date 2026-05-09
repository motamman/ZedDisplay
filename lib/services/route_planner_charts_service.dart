import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/service_constants.dart';
import 'route_planner_auth_service.dart';

/// Per-chart metadata as exposed by the route planner's `/charts`
/// endpoint. Bounds are EPSG:4326 (geographic), zoom range is the
/// MBTiles native zoom range. The tile manager uses [intersectsTile]
/// to skip fetches that would otherwise 404.
class ChartDescriptor {
  const ChartDescriptor({
    required this.id,
    required this.west,
    required this.south,
    required this.east,
    required this.north,
    required this.minZoom,
    required this.maxZoom,
  });

  final String id;
  final double west;
  final double south;
  final double east;
  final double north;
  final int minZoom;
  final int maxZoom;

  bool intersectsTile(int z, int x, int y) {
    if (z < minZoom || z > maxZoom) return false;
    final n = 1 << z;
    final tileWest = x * 360.0 / n - 180.0;
    final tileEast = (x + 1) * 360.0 / n - 180.0;
    final tileNorth = _tileYToLat(y, n);
    final tileSouth = _tileYToLat(y + 1, n);
    return tileEast >= west &&
        tileWest <= east &&
        tileNorth >= south &&
        tileSouth <= north;
  }

  static double _tileYToLat(int y, int n) {
    final m = math.pi * (1 - 2 * y / n);
    return math.atan((math.exp(m) - math.exp(-m)) / 2) * 180.0 / math.pi;
  }

  factory ChartDescriptor.fromJson(Map<String, dynamic> j) {
    final b = j['bounds'];
    if (b is! Map) {
      throw FormatException('ChartDescriptor missing bounds map: ${j['id']}');
    }
    return ChartDescriptor(
      id: j['id'] as String,
      west: (b['west'] as num).toDouble(),
      south: (b['south'] as num).toDouble(),
      east: (b['east'] as num).toDouble(),
      north: (b['north'] as num).toDouble(),
      minZoom: (j['minzoom'] as num).toInt(),
      maxZoom: (j['maxzoom'] as num).toInt(),
    );
  }
}

/// Wraps the route-planner `/charts` endpoint. Caches the returned
/// catalog and exposes it as `List<ChartDescriptor>`. Mirrors the
/// `RoutePlannerBoatsService` shape: settable [baseUrl], `lastError`
/// for snackbar surfacing, `loading` for spinner gating.
///
/// Refreshes are explicit — call [refresh] from the chart plotter on
/// init so the catalog is ready when `_layers` seeds. The service does
/// not poll; the catalog only changes when the operator restarts the
/// router with new MBTiles, so a one-shot fetch per session is enough.
class RoutePlannerChartsService extends ChangeNotifier {
  RoutePlannerChartsService({required RoutePlannerAuthService auth})
      : _auth = auth;

  final RoutePlannerAuthService _auth;

  // Bumped every time `baseUrl` flips. An in-flight `refresh()` reads
  // the epoch at start; if it changes before the response lands, the
  // refresh discards the result rather than repopulating state that
  // belongs to the old server.
  int _catalogEpoch = 0;

  String _baseUrl = 'https://router.zeddisplay.com';
  String get baseUrl => _baseUrl;
  set baseUrl(String v) {
    final trimmed = v.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed == _baseUrl) return;
    _baseUrl = trimmed;
    _catalogEpoch++;
    // Drop the loading flag too — the in-flight request from the old
    // server is now orphaned, and we want the next `refresh()` to fire
    // immediately rather than wait for the abandoned one to finish.
    _loading = false;
    // Catalog and any prior error message belong to the old server —
    // drop both so listeners that re-seed off the catalog (chart
    // plotter's `_layersSeededFromCatalog`) and snackbars driven by
    // `lastError` see clean state for the next refresh.
    _charts = const [];
    _chartById = const {};
    _lastError = null;
    // A fresh server is a fresh authority. Drop the "we've ever seen
    // a catalog" flag so the chart plotter's reconcile won't drop
    // persisted s57 entries based on the old server's catalog.
    _hasLoaded = false;
    notifyListeners();
  }

  List<ChartDescriptor> _charts = const [];
  List<ChartDescriptor> get charts => _charts;
  Map<String, ChartDescriptor> _chartById = const {};

  bool _loading = false;
  bool get loading => _loading;

  /// `true` once a `refresh()` against the current `baseUrl` has
  /// returned a parseable list. Stays `true` across subsequent
  /// failures so the chart plotter can distinguish "catalog never
  /// arrived (don't reconcile yet)" from "catalog is empty (drop
  /// stale s57 rows)". Reset only when [baseUrl] changes.
  bool _hasLoaded = false;
  bool get hasLoaded => _hasLoaded;

  String? _lastError;
  String? get lastError => _lastError;
  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_loading) return;
    final epoch = _catalogEpoch;
    final requestBaseUrl = _baseUrl;
    _loading = true;
    notifyListeners();
    try {
      final uri = Uri.parse('$requestBaseUrl/charts');
      final resp = await http
          .get(uri, headers: _auth.authorisedHeaders())
          .timeout(ServiceConstants.shortHttpTimeout);
      // Drop the response if the user flipped `baseUrl` while we were
      // awaiting — writing this catalog back would clobber the cleared
      // state intended for the new server.
      if (epoch != _catalogEpoch) return;
      if (resp.statusCode != 200) {
        _lastError = 'GET /charts failed: HTTP ${resp.statusCode}';
        return;
      }
      final j = jsonDecode(resp.body);
      if (j is! List) {
        _lastError = 'GET /charts: expected JSON list';
        return;
      }
      // Skip malformed entries individually rather than failing the
      // whole catalog — one router config typo shouldn't blank every
      // s57 layer in the panel.
      final parsed = <ChartDescriptor>[];
      for (final entry in j.whereType<Map<String, dynamic>>()) {
        try {
          parsed.add(ChartDescriptor.fromJson(entry));
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Skipping malformed chart entry: $e');
          }
        }
      }
      _charts = List.unmodifiable(parsed);
      _chartById = {for (final c in parsed) c.id: c};
      _lastError = null;
      // Catalog has now successfully arrived from this server. The
      // chart plotter will treat empty catalogs as authoritative
      // from this point on (and drop stale s57 rows).
      _hasLoaded = true;
    } catch (e) {
      // Same epoch guard for errors — a network failure against the
      // old server shouldn't surface as a snackbar after the user
      // already moved on to a new one.
      if (epoch == _catalogEpoch) {
        _lastError = 'GET /charts error: $e';
      }
    } finally {
      // Only release the loading flag if we still own the request.
      // The setter already cleared it on epoch flip, and a stale
      // refresh has no business toggling state for the new server.
      if (epoch == _catalogEpoch) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  ChartDescriptor? byId(String id) => _chartById[id];
}
