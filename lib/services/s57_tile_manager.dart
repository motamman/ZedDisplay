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
  });
  final String objectClass;
  final S57WorldGeometry geometry;
  final List<S52Instruction> instructions;
  final Map<String, Object?> attributes;
  final int displayPriority;
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
    required this.urlBuilder,
    this.freshnessProbe,
    this.refreshInterval = const Duration(milliseconds: 200),
    this.minZoom = 9,
    this.maxZoom = 16,
    this.maxTilesPerRefresh = 128,
  });

  final S52StyleEngine engine;
  final String Function(S57TileKey key) urlBuilder;
  final TileFreshness Function(List<(int z, int x, int y)>)? freshnessProbe;
  /// Minimum gap between viewport refreshes. Acts as a leading-edge
  /// throttle: the first event after the gap fires immediately so
  /// continuous pans keep loading tiles; subsequent events within the
  /// window collapse into a single trailing fire at window's end.
  final Duration refreshInterval;
  final int minZoom;
  final int maxZoom;
  final int maxTilesPerRefresh;

  final Map<S57TileKey, S57ParsedTile> _tileCache = {};
  final Set<S57TileKey> _inflight = {};
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

  Future<void> _ensureTile(S57TileKey key) async {
    if (_tileCache.containsKey(key) || _inflight.contains(key)) return;
    _inflight.add(key);
    try {
      final url = urlBuilder(key);
      final resp = await http.get(Uri.parse(url));
      // Window may have shifted while we waited — drop late arrivals
      // from outside the current viewport rather than caching them
      // (which would race the next eviction and briefly paint stale).
      final window = _activeWindow;
      if (_disposed) return;
      if (window != null && !_inWindow(key, window)) return;
      if (resp.statusCode != 200) {
        _tileCache[key] = S57ParsedTile.empty();
        _bumpAndNotify();
        return;
      }
      Uint8List bytes = resp.bodyBytes;
      // Tiles may arrive gzipped; the decoder expects raw protobuf.
      if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
        bytes = Uint8List.fromList(gzip.decode(bytes));
      }
      final decoded = vt.VectorTile.fromBytes(bytes: bytes);
      final parsed = _parse(decoded, key);
      _tileCache[key] = parsed;
      _indexLandExtents(key, parsed);
      _bumpAndNotify();
    } catch (_) {
      _tileCache[key] = S57ParsedTile.empty();
      _bumpAndNotify();
    } finally {
      _inflight.remove(key);
    }
  }

  S57ParsedTile _parse(vt.VectorTile tile, S57TileKey key) {
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
    _inflight.clear();
    _landBounds.clear();
    _landIndexedTiles.clear();
    _activeWindow = null;
    _viewportFreshness = TileFreshness.uncached;
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
