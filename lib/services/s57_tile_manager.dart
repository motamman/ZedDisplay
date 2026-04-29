import 'dart:async';
import 'dart:io' show gzip;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:s52_dart/s52_dart.dart';
import 'package:vector_tile/vector_tile.dart' as vt;

import 'chart_tile_cache_service.dart';

enum S57GeomKind { point, line, polygon }

/// One chart's published bounds + zoom range + tile URL template.
/// Built by the V3 tool from `signalKService.getResources('charts')`
/// and handed to the tile manager via [S57TileManager.setCharts].
///
/// `urlTemplate` is the canonical SignalK chart `url` field — each
/// provider plugin (signalk-charts-provider-simple, signalk-charts,
/// etc.) registers its own template per chart. Substitution is
/// `{z}`/`{x}`/`{y}` per OpenLayers convention. The V3 tool forwards
/// this map to `ChartTileServerService.setChartUpstreamTemplates` so
/// the local cache proxy can resolve the right upstream per chartId.
class ChartDescriptor {
  const ChartDescriptor({
    required this.id,
    required this.west,
    required this.south,
    required this.east,
    required this.north,
    required this.minZoom,
    required this.maxZoom,
    this.urlTemplate,
  });

  final String id;
  final double west;
  final double south;
  final double east;
  final double north;
  final int minZoom;
  final int maxZoom;
  final String? urlTemplate;

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
}

class S57TileKey {
  const S57TileKey(this.z, this.x, this.y);
  final int z;
  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      other is S57TileKey && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);
}

class S57WorldGeometry {
  const S57WorldGeometry._(this.kind, this.points, this.lines, this.rings);

  factory S57WorldGeometry.point(LatLng p) =>
      S57WorldGeometry._(S57GeomKind.point, [p], const [], const []);
  factory S57WorldGeometry.multiPoint(List<LatLng> ps) =>
      S57WorldGeometry._(S57GeomKind.point, ps, const [], const []);
  factory S57WorldGeometry.line(List<List<LatLng>> ls) =>
      S57WorldGeometry._(S57GeomKind.line, const [], ls, const []);
  factory S57WorldGeometry.polygon(List<List<List<LatLng>>> rs) =>
      S57WorldGeometry._(S57GeomKind.polygon, const [], const [], rs);

  final S57GeomKind kind;
  final List<LatLng> points;
  final List<List<LatLng>> lines;
  final List<List<List<LatLng>>> rings;
}

class S57StyledFeature {
  const S57StyledFeature({
    required this.objectClass,
    required this.geometry,
    required this.instructions,
    required this.attributes,
    required this.displayPriority,
    required this.chartId,
  });
  final String objectClass;
  final S57WorldGeometry geometry;
  final List<S52Instruction> instructions;
  final Map<String, Object?> attributes;
  final int displayPriority;
  /// Originating chart file (matches the id from
  /// `signalKService.getResources('charts')`). Painter filters by this
  /// to honour the user's per-chart on/off toggle without refetching.
  final String chartId;
}

class S57ParsedTile {
  const S57ParsedTile({required this.features});
  factory S57ParsedTile.empty() => const S57ParsedTile(features: []);
  final List<S57StyledFeature> features;
}

/// Owns tile lifecycle for the S-57 vector overlay: pyramid math, MVT
/// fetch + parse + s52_dart styling, viewport-aware caching with
/// eviction, and gesture debounce. Mirrors what OpenLayers'
/// `VectorTileSource` gave V1 for free. Listeners (ChangeNotifier) fire
/// when tiles arrive, when eviction shrinks the cache, or when viewport
/// freshness changes — so the painter widget can rebuild.
class S57TileManager extends ChangeNotifier {
  S57TileManager({
    required this.engine,
    required this.urlBuilderForChart,
    List<ChartDescriptor> charts = const [],
    this.headersBuilder,
    this.freshnessProbe,
    this.refreshInterval = const Duration(milliseconds: 200),
    this.minZoom = 9,
    this.maxZoom = 16,
    this.maxTilesPerRefresh = 128,
  }) : _charts = charts;

  final S52StyleEngine engine;
  /// Builds the upstream URL for one chart's view of a tile. Called
  /// once per (chart, tile) on fan-out — the manager fetches every
  /// chart whose bounds intersect the tile in parallel and merges the
  /// resulting features into the tile cache. Switching to per-chart
  /// URLs (vs. the old dispatched single-URL `/tiles/{z}/{x}/{y}`) is
  /// what avoids the rectangular cuts at chart boundaries.
  final String Function(String chartId, S57TileKey key) urlBuilderForChart;

  /// Charts the manager fetches from. Updated in place via [setCharts]
  /// when the user adds/removes layers; the manager fans out across
  /// every chart whose bounds intersect the requested tile. Toggling a
  /// chart's enabled state is NOT modeled here — the painter filters
  /// rendered features by chartId so toggle is instant and free of
  /// network refetches. Keep `_charts` to the set actually wired in
  /// the layer panel (enabled or disabled) so disabling a chart hides
  /// it via the painter without dropping the in-memory features.
  List<ChartDescriptor> _charts;
  List<ChartDescriptor> get charts => _charts;

  /// Optional per-request header builder — used to inject
  /// `Authorization: Bearer <token>` when fetching tiles directly
  /// from an authenticated upstream (no local proxy in the chain).
  final Map<String, String> Function()? headersBuilder;
  final TileFreshness Function(List<(int z, int x, int y)>)? freshnessProbe;
  /// Minimum gap between viewport refreshes. Acts as a leading-edge
  /// throttle: the first event after the gap fires immediately so
  /// continuous pans keep loading tiles; subsequent events within the
  /// window collapse into a single trailing fire at window's end.
  final Duration refreshInterval;
  final int minZoom;
  final int maxZoom;
  final int maxTilesPerRefresh;

  /// Merged + sorted view across charts — what painters consume. The
  /// per-chart sub-cache below is the source of truth; this is kept
  /// in sync via [_rebuildMerged] on every fan-out arrival.
  final Map<S57TileKey, S57ParsedTile> _tileCache = {};
  /// Per-chart parsed features per tile. `_tileCacheByChart[key][chartId]`
  /// is the single chart's contribution; the merge in [_tileCache]
  /// concatenates these and sorts by displayPriority so cross-chart
  /// z-order matches what S52 expects (a chart-A lighthouse symbol
  /// renders above a chart-B area even if A's fetch arrived first).
  final Map<S57TileKey, Map<String, S57ParsedTile>> _tileCacheByChart = {};
  /// Tracks (chartId, tileKey) pairs currently being fetched. Per-chart
  /// rather than per-tile so two chart fan-outs into the same tile do
  /// not collapse into a single in-flight slot.
  final Set<(String, S57TileKey)> _inflight = {};
  // Bounding boxes of LNDARE polygons. Used by the auto-zoom heuristic
  // to tighten the view when land is close. Survives tile eviction:
  // once we've seen land here, we don't need to re-parse to remember.
  final List<LatLngBounds> _landBounds = [];
  final Set<S57TileKey> _landIndexedTiles = {};
  // Current viewport tile window (zoom + ±1 buffer). Tiles outside
  // this window are evicted on each refresh; in-flight fetches whose
  // window has shifted are discarded post-await rather than briefly
  // racing into the cache.
  ({int z, int x0, int x1, int y0, int y1})? _activeWindow;
  Timer? _refreshTimer;
  // Latest camera handed to the throttle. The trailing-edge fire reads
  // this rather than a captured snapshot so we don't refresh against
  // a stale viewport from the start of the gesture.
  MapCamera? _pendingCamera;
  DateTime _lastRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);
  TileFreshness _viewportFreshness = TileFreshness.uncached;
  bool _disposed = false;

  Map<S57TileKey, S57ParsedTile> get tiles => _tileCache;
  List<LatLngBounds> get landBounds => _landBounds;
  TileFreshness get viewportFreshness => _viewportFreshness;

  /// Bumped on every cache mutation (fetch arrival, eviction, freshness
  /// change). Painters that hold a reference to `tiles` use this in
  /// `shouldRepaint` so they re-render after eviction even when the
  /// camera hasn't moved (which would otherwise short-circuit because
  /// the map reference is stable).
  int get generation => _generation;
  int _generation = 0;

  void _bumpAndNotify() {
    _generation++;
    notifyListeners();
  }

  /// Throttles per-frame map events (~60Hz) into refreshes spaced by
  /// `refreshInterval`. Leading + trailing: fires immediately if the
  /// last refresh is older than the interval (so continuous pans keep
  /// streaming tiles); otherwise schedules one trailing fire at window
  /// end against the latest camera (so the final viewport is right).
  void scheduleRefresh(MapCamera camera) {
    if (_disposed) return;
    _pendingCamera = camera;
    final now = DateTime.now();
    final sinceLast = now.difference(_lastRefreshAt);
    if (sinceLast >= refreshInterval) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      _lastRefreshAt = now;
      _refresh(camera);
      return;
    }
    if (_refreshTimer?.isActive ?? false) return;
    _refreshTimer = Timer(refreshInterval - sinceLast, () {
      _refreshTimer = null;
      final pending = _pendingCamera;
      if (pending == null || _disposed) return;
      _lastRefreshAt = DateTime.now();
      _refresh(pending);
    });
  }

  /// Bypass the throttle — used at first map-ready so the chart paints
  /// without an opening gap.
  void refreshNow(MapCamera camera) {
    if (_disposed) return;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _pendingCamera = camera;
    _lastRefreshAt = DateTime.now();
    _refresh(camera);
  }

  void _refresh(MapCamera camera) {
    if (_disposed) return;
    final zInt = camera.zoom.round().clamp(minZoom, maxZoom);
    final bounds = camera.visibleBounds;
    final x0 = _lonToTileX(bounds.west, zInt);
    final x1 = _lonToTileX(bounds.east, zInt);
    final y0 = _latToTileY(bounds.north, zInt);
    final y1 = _latToTileY(bounds.south, zInt);

    // Retention window: active zoom, ±1 tile buffer around the
    // viewport. Bounds the in-memory parsed cache regardless of how far
    // the user has zoomed/panned over the session, and stops zoom-in
    // detail from sticking on the way back out. Tiles at z ± 1 that
    // geographically overlap this window are also retained so they can
    // act as fallback fill during zoom transitions (mirrors what
    // OpenLayers' `preload: 1` did for V1).
    final window = (z: zInt, x0: x0 - 1, x1: x1 + 1, y0: y0 - 1, y1: y1 + 1);
    _activeWindow = window;
    final sizeBefore = _tileCache.length;
    _tileCache.removeWhere((k, _) => !_overlapsWindow(k, window));
    _tileCacheByChart.removeWhere((k, _) => !_overlapsWindow(k, window));
    final evicted = _tileCache.length != sizeBefore;

    int fetched = 0;
    final viewportTiles = <(int, int, int)>[];
    // Fetch the same ±1 buffer we retain so newly-visible tiles are
    // already loaded before they slide on-screen during a pan. The
    // visible viewport (no buffer) is what we report to the freshness
    // probe — staleness should reflect what the user is actually
    // looking at, not pre-fetch tiles.
    for (var x = x0 - 1; x <= x1 + 1 && fetched < maxTilesPerRefresh; x++) {
      for (var y = y0 - 1; y <= y1 + 1 && fetched < maxTilesPerRefresh; y++) {
        _ensureTile(S57TileKey(zInt, x, y));
        if (x >= x0 && x <= x1 && y >= y0 && y <= y1) {
          viewportTiles.add((zInt, x, y));
        }
        fetched++;
      }
    }
    _refreshFreshness(viewportTiles);
    if (evicted) _bumpAndNotify();
  }

  /// Fan out per chart: for every chart whose bounds intersect the
  /// requested tile, kick off an independent fetch. The merged tile in
  /// [_tileCache] is rebuilt as each chart's response arrives, so the
  /// painter starts rendering features as soon as the first chart
  /// completes instead of waiting for the slowest. Charts whose bounds
  /// don't touch (z,x,y) are skipped — keeps the per-chart endpoint
  /// from 404-flooding when the viewport sits outside one chart's
  /// coverage.
  void _ensureTile(S57TileKey key) {
    final perChart = _tileCacheByChart.putIfAbsent(key, () => {});
    bool kickedAny = false;
    for (final chart in _charts) {
      if (!chart.intersectsTile(key.z, key.x, key.y)) continue;
      if (perChart.containsKey(chart.id)) continue;
      final slot = (chart.id, key);
      if (_inflight.contains(slot)) continue;
      _inflight.add(slot);
      kickedAny = true;
      unawaited(_fetchChartTile(chart.id, key, perChart));
    }
    // Tile sits outside every chart's bounds — record an empty merged
    // entry so the painter doesn't keep asking and the eviction loop
    // sees a key to track.
    if (!kickedAny && perChart.isEmpty && !_tileCache.containsKey(key)) {
      _tileCache[key] = S57ParsedTile.empty();
    }
  }

  Future<void> _fetchChartTile(
    String chartId,
    S57TileKey key,
    Map<String, S57ParsedTile> perChart,
  ) async {
    try {
      final url = urlBuilderForChart(chartId, key);
      final headers = headersBuilder?.call() ?? const <String, String>{};
      debugPrint(
        '[S57TileManager] GET $url  '
        'auth=${headers.containsKey('Authorization') ? 'Bearer[${(headers['Authorization']!.length - 7)}c]' : 'NONE'}',
      );
      final resp = await http.get(Uri.parse(url), headers: headers);
      debugPrint(
        '[S57TileManager] ← ${resp.statusCode} ${resp.bodyBytes.length}B  $url',
      );
      // Window may have shifted while we waited — drop late arrivals
      // from outside the current viewport rather than caching them
      // (which would race the next eviction and briefly paint stale).
      final window = _activeWindow;
      if (_disposed) return;
      if (window != null && !_inWindow(key, window)) return;
      if (resp.statusCode != 200) {
        perChart[chartId] = S57ParsedTile.empty();
        _rebuildMerged(key);
        _bumpAndNotify();
        return;
      }
      Uint8List bytes = resp.bodyBytes;
      // Tiles may arrive gzipped; the decoder expects raw protobuf.
      if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
        bytes = Uint8List.fromList(gzip.decode(bytes));
      }
      final decoded = vt.VectorTile.fromBytes(bytes: bytes);
      final parsed = _parse(decoded, key, chartId);
      perChart[chartId] = parsed;
      _indexLandExtents(key, parsed);
      _rebuildMerged(key);
      _bumpAndNotify();
    } catch (_) {
      perChart[chartId] = S57ParsedTile.empty();
      _rebuildMerged(key);
      _bumpAndNotify();
    } finally {
      _inflight.remove((chartId, key));
    }
  }

  /// Concatenate every chart's contribution for [key] and sort by
  /// `displayPriority` so cross-chart z-order matches what S52 expects
  /// (a high-priority symbol from one chart paints above a low-priority
  /// area from another regardless of fan-out arrival order). Dart's
  /// `List.sort` is not guaranteed stable, so features at the same
  /// priority may swap relative order across rebuilds — fine for S52
  /// since equal-priority features are visually interchangeable.
  void _rebuildMerged(S57TileKey key) {
    final perChart = _tileCacheByChart[key];
    if (perChart == null || perChart.isEmpty) {
      _tileCache[key] = S57ParsedTile.empty();
      return;
    }
    final all = <S57StyledFeature>[];
    for (final pt in perChart.values) {
      all.addAll(pt.features);
    }
    all.sort((a, b) => a.displayPriority.compareTo(b.displayPriority));
    _tileCache[key] = S57ParsedTile(features: all);
  }

  S57ParsedTile _parse(vt.VectorTile tile, S57TileKey key, String chartId) {
    final out = <S57StyledFeature>[];
    for (final layer in tile.layers) {
      for (final feature in layer.features) {
        try {
          feature.decodeGeometry();
          feature.decodeProperties();
        } catch (_) {
          continue;
        }
        final attrs = <String, Object?>{};
        feature.properties?.forEach((k, v) {
          attrs[k] = v.dartStringValue ??
              v.dartIntValue?.toInt() ??
              v.dartDoubleValue ??
              v.dartBoolValue;
        });
        // SCAMIN = minimum display scale denominator. The feature
        // should only be drawn when the viewer's scale denominator is
        // smaller (i.e. zoomed in further). Tile scale ≈ 559e6 / 2^z.
        final scamin = attrs['SCAMIN'];
        if (scamin is num) {
          final tileScaleDenominator = 559082264.0 / (1 << key.z);
          if (scamin.toDouble() < tileScaleDenominator) continue;
        }
        final geomType = _mapGeom(feature.geometryType);
        if (geomType == null) continue;
        final s52 = S52Feature(
          objectClass: layer.name,
          geometryType: geomType,
          attributes: attrs,
          layerName: layer.name,
        );
        final instructions = engine.styleFeature(s52);
        if (instructions.isEmpty) continue;
        final world = _geomToLatLng(feature, layer.extent, key);
        if (world == null) continue;
        // Look up displayPriority via the same table kind the engine
        // chose for styling. Delegating to engine.preferredTableKind
        // so this stays in sync with options.graphicsStyle (paper vs
        // simplified) and options.boundaries (plain vs symbolised) —
        // hardcoding here would diverge if those options change.
        final row = engine.lookups.bestMatch(
          engine.preferredTableKind(geomType),
          layer.name,
          geomType,
          attrs,
        );
        out.add(S57StyledFeature(
          objectClass: layer.name,
          geometry: world,
          instructions: instructions,
          attributes: attrs,
          displayPriority: row?.displayPriority.code ?? 0,
          chartId: chartId,
        ));
      }
    }
    return S57ParsedTile(features: out);
  }

  S52GeometryType? _mapGeom(vt.GeometryType? t) {
    switch (t) {
      case vt.GeometryType.Point:
      case vt.GeometryType.MultiPoint:
        return S52GeometryType.point;
      case vt.GeometryType.LineString:
      case vt.GeometryType.MultiLineString:
        return S52GeometryType.line;
      case vt.GeometryType.Polygon:
      case vt.GeometryType.MultiPolygon:
        return S52GeometryType.area;
      default:
        return null;
    }
  }

  /// Convert tile-local MVT coordinates directly into `LatLng` using
  /// the standard Web-Mercator projection. Storing features in LatLng
  /// means the painter only needs one call per point with no
  /// intermediate math, and no coupling between tile zoom and rendering.
  S57WorldGeometry? _geomToLatLng(
      vt.VectorTileFeature feature, int extent, S57TileKey key) {
    final size = extent * (1 << key.z);
    final x0 = extent * key.x;
    final y0 = extent * key.y;

    LatLng project(List<double> xy) {
      final lon = (xy[0] + x0) * 360.0 / size - 180.0;
      final y2 = 180.0 - (xy[1] + y0) * 360.0 / size;
      final lat =
          360.0 / math.pi * math.atan(math.exp(y2 * math.pi / 180.0)) - 90.0;
      return LatLng(lat, lon);
    }

    switch (feature.geometryType) {
      case vt.GeometryType.Point:
        final g = feature.geometry as vt.GeometryPoint;
        return S57WorldGeometry.point(project(g.coordinates));
      case vt.GeometryType.MultiPoint:
        final g = feature.geometry as vt.GeometryMultiPoint;
        return S57WorldGeometry.multiPoint(
            g.coordinates.map(project).toList(growable: false));
      case vt.GeometryType.LineString:
        final g = feature.geometry as vt.GeometryLineString;
        return S57WorldGeometry.line(
            [g.coordinates.map(project).toList(growable: false)]);
      case vt.GeometryType.MultiLineString:
        final g = feature.geometry as vt.GeometryMultiLineString;
        return S57WorldGeometry.line(g.coordinates
            .map((line) => line.map(project).toList(growable: false))
            .toList(growable: false));
      case vt.GeometryType.Polygon:
        final g = feature.geometry as vt.GeometryPolygon;
        return S57WorldGeometry.polygon([
          g.coordinates
              .map((ring) => ring.map(project).toList(growable: false))
              .toList(growable: false)
        ]);
      case vt.GeometryType.MultiPolygon:
        final g = feature.geometry as vt.GeometryMultiPolygon;
        final rings = (g.coordinates ?? [])
            .map((poly) => poly
                .map((ring) => ring.map(project).toList(growable: false))
                .toList(growable: false))
            .toList(growable: false);
        return S57WorldGeometry.polygon(rings);
      default:
        return null;
    }
  }

  void _indexLandExtents(S57TileKey key, S57ParsedTile tile) {
    if (_landIndexedTiles.contains(key)) return;
    _landIndexedTiles.add(key);
    for (final f in tile.features) {
      if (f.objectClass != 'LNDARE') continue;
      if (f.geometry.kind != S57GeomKind.polygon) continue;
      double? minLat, minLon, maxLat, maxLon;
      for (final ring in f.geometry.rings) {
        for (final poly in ring) {
          for (final p in poly) {
            minLat = minLat == null ? p.latitude : math.min(minLat, p.latitude);
            minLon = minLon == null ? p.longitude : math.min(minLon, p.longitude);
            maxLat = maxLat == null ? p.latitude : math.max(maxLat, p.latitude);
            maxLon = maxLon == null ? p.longitude : math.max(maxLon, p.longitude);
          }
        }
      }
      if (minLat != null) {
        _landBounds.add(LatLngBounds(
          LatLng(minLat, minLon!),
          LatLng(maxLat!, maxLon!),
        ));
      }
    }
  }

  void _refreshFreshness(List<(int z, int x, int y)> viewportTiles) {
    final probe = freshnessProbe;
    if (probe == null) return;
    try {
      final f = probe(viewportTiles);
      if (f != _viewportFreshness) {
        _viewportFreshness = f;
        _bumpAndNotify();
      }
    } catch (_) {
      // probe unavailable (e.g. cache service not registered in tests)
    }
  }

  /// Drop everything. Used on chart-source switch when the URL changes
  /// out from under us.
  void clearCache() {
    _tileCache.clear();
    _tileCacheByChart.clear();
    _inflight.clear();
    _landBounds.clear();
    _landIndexedTiles.clear();
    _activeWindow = null;
    _viewportFreshness = TileFreshness.uncached;
    _bumpAndNotify();
  }

  /// Replace the chart catalog the manager fans out to. Newly-added
  /// charts are picked up on the next viewport refresh; charts that
  /// disappear from the catalog have their cached contributions
  /// dropped from every tile and the merged view rebuilt so stale
  /// features don't keep painting after a delete. The painter still
  /// owns enable/disable filtering — that's handled per-feature via
  /// `chartId` and does not call this.
  void setCharts(List<ChartDescriptor> next) {
    final nextIds = next.map((c) => c.id).toSet();
    final removed = _charts.where((c) => !nextIds.contains(c.id)).toList();
    _charts = next;
    if (removed.isEmpty) {
      _bumpAndNotify();
      return;
    }
    for (final perChart in _tileCacheByChart.values) {
      for (final r in removed) {
        perChart.remove(r.id);
      }
    }
    for (final key in _tileCacheByChart.keys.toList()) {
      _rebuildMerged(key);
    }
    _bumpAndNotify();
  }

  bool _inWindow(S57TileKey k, ({int z, int x0, int x1, int y0, int y1}) w) =>
      k.z == w.z &&
      k.x >= w.x0 &&
      k.x <= w.x1 &&
      k.y >= w.y0 &&
      k.y <= w.y1;

  /// True when the tile's geographic footprint intersects the retention
  /// window. Used by eviction to keep tiles at the active zoom AND at
  /// ±1 (as fallback during zoom transitions). Tiles further away in
  /// zoom are dropped.
  bool _overlapsWindow(
      S57TileKey k, ({int z, int x0, int x1, int y0, int y1}) w) {
    final dz = k.z - w.z;
    if (dz.abs() > 1) return false;
    if (dz == 0) {
      return k.x >= w.x0 && k.x <= w.x1 && k.y >= w.y0 && k.y <= w.y1;
    }
    if (dz < 0) {
      // Lower-zoom tile — covers a 2×2 block (per |dz|) at w.z.
      final scale = 1 << (-dz);
      final kx0 = k.x * scale;
      final kx1 = kx0 + scale - 1;
      final ky0 = k.y * scale;
      final ky1 = ky0 + scale - 1;
      return kx0 <= w.x1 && kx1 >= w.x0 && ky0 <= w.y1 && ky1 >= w.y0;
    }
    // Higher-zoom tile — falls inside one cell at w.z.
    final scale = 1 << dz;
    final kxAtW = k.x ~/ scale;
    final kyAtW = k.y ~/ scale;
    return kxAtW >= w.x0 && kxAtW <= w.x1 && kyAtW >= w.y0 && kyAtW <= w.y1;
  }

  static int _lonToTileX(double lon, int z) =>
      ((lon + 180.0) / 360.0 * (1 << z)).floor();

  static int _latToTileY(double lat, int z) {
    final rad = lat * math.pi / 180.0;
    return ((1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) /
            2 *
            (1 << z))
        .floor();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    super.dispose();
  }
}
