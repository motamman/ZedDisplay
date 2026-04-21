import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:s52_dart/s52_dart.dart';
import 'package:vector_tile/vector_tile.dart' as vt;

import '../../config/app_colors.dart';
import '../../config/chart_constants.dart';
import '../../models/path_metadata.dart';
import '../../models/tool_config.dart';
import '../../models/tool_definition.dart';
import '../../services/chart_download_manager.dart';
import '../../services/chart_tile_cache_service.dart';
import '../../services/chart_tile_server_service.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../ais_vessel_detail_sheet.dart';
import '../chart_plotter/chart_hud.dart';
import '../chart_plotter/chart_layer_panel.dart';
import '../chart_plotter/chart_route_panel.dart';

/// Chart Plotter V3 — spike: proves the s52_dart → flutter_map pipeline.
///
/// Basemap: OSM raster. Overlay: one MVT tile fetched from the SignalK
/// chart proxy, decoded, fed through `S52StyleEngine`, painted via
/// `CustomPainter`. Scope: points (symbols rendered as dots) and lines
/// only. No text, no patterns, no multi-tile viewport loading.
///
/// Purpose: answer whether pure-Flutter paint driven by s52_dart output
/// is viable for real chart rendering.
class ChartPlotterV3Tool extends StatefulWidget {
  const ChartPlotterV3Tool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  final ToolConfig config;
  final SignalKService signalKService;

  @override
  State<ChartPlotterV3Tool> createState() => _ChartPlotterV3ToolState();
}

class _ChartPlotterV3ToolState extends State<ChartPlotterV3Tool>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static const _initialCenter = LatLng(41.10, -72.80); // Long Island Sound
  static const _initialZoom = 12.0;

  /// Stacked layer definition — `{type: base|s57, id, enabled, opacity}`.
  /// Same shape ChartLayerPanel mutates. For the V3 MVP we honour the
  /// first enabled base layer as the rendered basemap, and the first
  /// enabled s57 layer as the chart source, applying their opacities
  /// to each draw. Richer stacking comes later if V1 parity demands it.
  final List<Map<String, dynamic>> _layers = [
    {'type': 'base', 'id': 'carto_voyager', 'enabled': true, 'opacity': 1.0},
    {'type': 's57', 'id': '01CGD_ENCs', 'enabled': true, 'opacity': 1.0},
  ];

  Map<String, dynamic>? _firstEnabled(String type) {
    for (final l in _layers) {
      if (l['type'] == type && (l['enabled'] as bool? ?? true)) return l;
    }
    return null;
  }

  // Default SignalK paths driving the HUD. Mirrors V1's
  // `_fallbackPaths` so the HUD formats values identically whether
  // the user is on V1 or V3. Index positions are part of the HUD's
  // contract (see ChartPlotterHUD's `_dsSog` et al).
  static const _fallbackPaths = [
    'navigation.position',
    'navigation.headingTrue',
    'navigation.courseOverGroundTrue',
    'navigation.speedOverGround',
    'environment.depth.belowTransducer',
    'navigation.course.calcValues.bearingTrue',
    'navigation.course.calcValues.crossTrackError',
    'navigation.course.calcValues.distance',
    'navigation.course.activeRoute',
    'navigation.courseGreatCircle.nextPoint.position',
  ];

  // HUD controls — mutable surface for a later settings/config pass.
  // ignore: prefer_final_fields
  String _hudStyle = 'text';
  // ignore: prefer_final_fields
  String _hudPosition = 'bottom';

  S52StyleEngine? _engine;
  S52ColorTable? _colorTable;
  SpriteAtlas? _spriteAtlas;
  ui.Image? _spriteImage;
  String? _loadError;
  final Map<_TileKey, _ParsedTile> _tileCache = {};
  final Set<_TileKey> _inflight = {};
  final _mapController = MapController();

  // Route state — mirrors V1's field set so ChartRouteState /
  // ChartRouteCallbacks plug in unchanged. `[lon, lat]` pairs match
  // SignalK's GeoJSON route geometry on the wire.
  String? _activeRouteHref;
  List<List<double>>? _routeCoords;
  List<String>? _waypointNames;
  int? _routePointIndex;
  int? _routePointTotal;
  // `_routeReversed` tracked by the server via activeRoute.reverse; we
  // don't paint direction yet, so no need to hold the flag locally.
  Timer? _routePollTimer;

  TileFreshness _viewportFreshness = TileFreshness.uncached;

  // Ruler state — two draggable endpoints with derived distance +
  // bearings. Positions default to a spread across the current
  // viewport the first time the ruler is enabled so the handles are
  // visible rather than stacked on the centre point.
  bool _rulerVisible = false;
  LatLng? _rulerA;
  LatLng? _rulerB;

  // AIS display toggles + periodic refresh. We pull from
  // `aisVesselRegistry` instead of subscribing because the registry
  // mutates in place — a 1s tick gives live-enough updates without a
  // listener plumbing layer we'd have to design now.
  bool _aisEnabled = true;
  bool _aisActiveOnly = false;
  bool _aisShowPaths = false;
  List<_AisRenderable> _aisVessels = const [];

  // Own-vessel position / heading. Populated on a 1s tick from
  // SignalKService's cached values — same cadence V1 used. Kept as
  // doubles rather than LatLng so the painter can skip null-safe
  // projection on every tick.
  double? _ownLat;
  double? _ownLon;
  double? _ownHeading; // radians
  double? _ownCog; // radians
  Timer? _vesselTimer;
  bool _autoFollow = true;

  // Vessel trail — sliding window of recent positions with timestamps
  // (epoch ms). V1 keeps 30 minutes; matching that here. Parallel
  // lists rather than a struct to keep the painter's hot loop tight.
  final List<LatLng> _trailPoints = [];
  final List<int> _trailTimestamps = [];
  static const _trailMinutes = 30;

  @override
  void initState() {
    super.initState();
    _loadEngine();
    // Configure the cached tile proxy once on mount. The server itself
    // is started at app boot in main.dart; here we just tell it which
    // upstream SignalK server to proxy for and whether to refresh
    // stale tiles eagerly. Wrapped in try/catch because the service
    // might not be present in test environments.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final tileServer = context.read<ChartTileServerService>();
        tileServer.configure(
          upstreamBaseUrl: widget.signalKService.httpBaseUrl,
          authToken: widget.signalKService.authToken?.token,
          refreshThreshold: TileFreshness.stale,
        );
      } catch (_) {}
    });
    // Poll SignalK's course API at the same cadence V1 used — 3s.
    // Cheaper than a full WS subscription and the REST endpoint is
    // authoritative for route/index/total state.
    _pollCourseAPI();
    _routePollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pollCourseAPI(),
    );
    // 1s vessel tick — fast enough that the arrow feels live, slow
    // enough that we aren't rebuilding the whole painter tree every
    // frame. V1 pushes via JS every 1s too.
    _refreshVessel();
    _vesselTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshVessel(),
    );
  }

  @override
  void dispose() {
    _routePollTimer?.cancel();
    _vesselTimer?.cancel();
    super.dispose();
  }

  void _refreshVessel() {
    final posData = widget.signalKService.getValue('navigation.position');
    if (posData?.value is! Map) return;
    final pos = posData!.value as Map;
    final lat = (pos['latitude'] as num?)?.toDouble();
    final lon = (pos['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) return;
    double? getNum(String path) {
      final d = widget.signalKService.getValue(path);
      return d?.value is num ? (d!.value as num).toDouble() : null;
    }

    final heading = getNum('navigation.headingTrue');
    final cog = getNum('navigation.courseOverGroundTrue');
    final changed = lat != _ownLat ||
        lon != _ownLon ||
        heading != _ownHeading ||
        cog != _ownCog;
    if (!changed) return;
    if (mounted) {
      setState(() {
        _ownLat = lat;
        _ownLon = lon;
        _ownHeading = heading;
        _ownCog = cog;
        _appendTrailPoint(lat, lon);
        if (_aisEnabled) _refreshAisVessels();
      });
    }
    if (_autoFollow) {
      _mapController.move(LatLng(lat, lon), _mapController.camera.zoom);
    }
  }

  /// Snapshot the AIS registry into a light-weight renderable list.
  /// Projections are computed here so the painter never touches the
  /// math in paint(). Runs inside setState — caller handles mounting.
  void _refreshAisVessels() {
    final registry = widget.signalKService.aisVesselRegistry.vessels;
    final out = <_AisRenderable>[];
    final now = DateTime.now();
    for (final v in registry.values) {
      if (!v.hasPosition) continue;
      if (_aisActiveOnly) {
        if (v.aisStatus == 'lost' || v.aisStatus == 'remove') continue;
        if (now.difference(v.lastSeen).inMinutes >= 10) continue;
      }
      final lat = v.latitude!;
      final lon = v.longitude!;
      out.add(_AisRenderable(
        id: v.vesselId,
        position: LatLng(lat, lon),
        bearingRadians: v.headingTrueRad ?? v.cogRad ?? 0.0,
        name: v.name ?? '',
        projections: _aisShowPaths
            ? _projectAhead(lat, lon, v.cogRad, v.sogMs ?? 0.0)
            : const [],
      ));
    }
    _aisVessels = out;
  }

  /// Great-circle projected positions at 30s / 1m / 15m / 30m.
  /// Matches V1 so the time bands on the chart read the same as the
  /// AIS detail sheet's intercept numbers.
  List<LatLng> _projectAhead(
      double lat, double lon, double? cogRad, double sogMs) {
    if (sogMs < 0.1 || cogRad == null) return const [];
    const intervals = [30.0, 60.0, 900.0, 1800.0];
    final out = <LatLng>[];
    for (final t in intervals) {
      final d = sogMs * t;
      final lat1 = lat * math.pi / 180;
      final lon1 = lon * math.pi / 180;
      final a = d / 6371000.0;
      final lat2 = math.asin(
        math.sin(lat1) * math.cos(a) +
            math.cos(lat1) * math.sin(a) * math.cos(cogRad),
      );
      final lon2 = lon1 +
          math.atan2(
            math.sin(cogRad) * math.sin(a) * math.cos(lat1),
            math.cos(a) - math.sin(lat1) * math.sin(lat2),
          );
      out.add(LatLng(lat2 * 180 / math.pi, lon2 * 180 / math.pi));
    }
    return out;
  }

  /// Append a trail point if the vessel has moved more than 5m since
  /// the last sample, then trim anything older than the trail window.
  /// Distance is approximated via equirectangular projection — cheap
  /// and accurate enough for trail-point deduplication.
  void _appendTrailPoint(double lat, double lon) {
    if (_trailPoints.isNotEmpty) {
      final last = _trailPoints.last;
      final dx = (lon - last.longitude) *
          math.cos(lat * math.pi / 180) *
          111320;
      final dy = (lat - last.latitude) * 111320;
      if (dx * dx + dy * dy < 25) return; // <5m
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _trailPoints.add(LatLng(lat, lon));
    _trailTimestamps.add(nowMs);
    final cutoff = nowMs - _trailMinutes * 60000;
    while (_trailTimestamps.isNotEmpty && _trailTimestamps.first < cutoff) {
      _trailTimestamps.removeAt(0);
      _trailPoints.removeAt(0);
    }
  }

  Future<void> _pollCourseAPI() async {
    if (!mounted) return;
    try {
      final data = await widget.signalKService.getCourseInfo();
      if (data == null) return;
      final activeRoute = data['activeRoute'] as Map<String, dynamic>?;
      if (activeRoute != null) {
        final href = activeRoute['href'] as String?;
        final newIndex = activeRoute['pointIndex'] as int?;
        final newTotal = activeRoute['pointTotal'] as int?;
        final hrefChanged = href != null && href != _activeRouteHref;
        if (hrefChanged) {
          _activeRouteHref = href;
          await _fetchRoute(href);
        }
        if (mounted) {
          setState(() {
            _routePointIndex = newIndex;
            _routePointTotal = newTotal;
          });
        }
      } else if (_activeRouteHref != null) {
        if (mounted) {
          setState(() {
            _activeRouteHref = null;
            _routeCoords = null;
            _waypointNames = null;
            _routePointIndex = null;
            _routePointTotal = null;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchRoute(String href) async {
    final routeId = href.split('/').last;
    final data = await widget.signalKService.getResource('routes', routeId);
    if (data == null) return;
    final feature = data['feature'] as Map?;
    final geometry = feature?['geometry'] as Map?;
    final coords = (geometry?['coordinates'] as List?)
        ?.map<List<double>>(
            (c) => [(c[0] as num).toDouble(), (c[1] as num).toDouble()])
        .toList();
    final meta = (feature?['properties'] as Map?)?['coordinatesMeta'] as List?;
    final names = meta?.map<String>((m) => (m['name'] as String?) ?? '').toList();
    if (mounted) {
      setState(() {
        _routeCoords = coords;
        _waypointNames = names;
      });
    }
  }

  String? get _activeRouteId => _activeRouteHref?.split('/').last;

  Future<void> _activateRoute(String routeId, {bool reverse = false}) async {
    try {
      await widget.signalKService.activateRoute(routeId, reverse: reverse);
      await _pollCourseAPI();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Activate failed: $e')));
      }
    }
  }

  Future<void> _reverseRoute() async {
    try {
      await widget.signalKService.reverseActiveRoute();
      await _skipToWaypoint(0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Reverse failed: $e')));
      }
    }
  }

  Future<void> _clearCourse() async {
    try {
      await widget.signalKService.clearCourse();
      await _pollCourseAPI();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Clear failed: $e')));
      }
    }
  }

  Future<void> _skipToWaypoint(int pointIndex) async {
    try {
      await widget.signalKService.setActiveRoutePointIndex(pointIndex);
      await _pollCourseAPI();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Skip failed: $e')));
      }
    }
  }

  Future<void> _saveRouteToServer() async {
    final routeId = _activeRouteId;
    if (routeId == null || _routeCoords == null) return;
    final routeData = {
      'feature': {
        'type': 'Feature',
        'geometry': {
          'type': 'LineString',
          'coordinates': _routeCoords,
        },
        'properties': {
          'coordinatesMeta':
              _waypointNames?.map((n) => {'name': n}).toList() ?? [],
        },
      },
    };
    await widget.signalKService.putResource('routes', routeId, routeData);
  }

  /// Tap handler: waypoints first (small radius), then AIS vessels
  /// (larger — sprites are bigger targets), fall through otherwise.
  void _onMapTap(TapPosition tapPosition, LatLng latLng) {
    final camera = _mapController.camera;
    final tapScreen = camera.latLngToScreenOffset(latLng);

    final coords = _routeCoords;
    if (coords != null) {
      const hitRadius = 14.0;
      for (var i = 0; i < coords.length; i++) {
        final wp = camera
            .latLngToScreenOffset(LatLng(coords[i][1], coords[i][0]));
        if ((wp - tapScreen).distanceSquared <= hitRadius * hitRadius) {
          showWaypointEditDialog(
            context,
            index: i,
            routeCoords: coords,
            waypointNames: _waypointNames,
            onChanged: () {
              if (mounted) setState(() {});
            },
            saveRouteToServer: _saveRouteToServer,
          );
          return;
        }
      }
    }

    if (_aisEnabled) {
      const aisHitRadius = 20.0;
      for (final v in _aisVessels) {
        final p = camera.latLngToScreenOffset(v.position);
        if ((p - tapScreen).distanceSquared <=
            aisHitRadius * aisHitRadius) {
          AISVesselDetailSheet.show(
            context,
            signalKService: widget.signalKService,
            vesselId: v.id,
            ownLat: _ownLat,
            ownLon: _ownLon,
            ownCogRad: _ownCog,
            ownSogMs: widget.signalKService
                    .getValue('navigation.speedOverGround')
                    ?.value is num
                ? (widget.signalKService
                        .getValue('navigation.speedOverGround')!
                        .value as num)
                    .toDouble()
                : null,
          );
          return;
        }
      }
    }
  }

  /// Long-press inserts a waypoint after the nearest existing one.
  /// Matches V1's UX: press where you want the new point to live.
  void _onMapLongPress(TapPosition tapPosition, LatLng latLng) {
    final coords = _routeCoords;
    if (coords == null || coords.isEmpty) return;
    final camera = _mapController.camera;
    final tapScreen = camera.latLngToScreenOffset(latLng);
    var nearestIdx = 0;
    var nearestDistSq = double.infinity;
    for (var i = 0; i < coords.length; i++) {
      final wp = camera
          .latLngToScreenOffset(LatLng(coords[i][1], coords[i][0]));
      final d = (wp - tapScreen).distanceSquared;
      if (d < nearestDistSq) {
        nearestDistSq = d;
        nearestIdx = i;
      }
    }
    showAddWaypointDialog(
      context,
      afterIndex: nearestIdx,
      lon: latLng.longitude,
      lat: latLng.latitude,
      routeCoords: coords,
      waypointNames: _waypointNames,
      onChanged: () {
        if (mounted) setState(() {});
      },
      saveRouteToServer: _saveRouteToServer,
    );
  }

  ChartRouteCallbacks get _routeCallbacks => ChartRouteCallbacks(
        activateRoute: _activateRoute,
        reverseRoute: _reverseRoute,
        clearCourse: _clearCourse,
        skipToWaypoint: _skipToWaypoint,
        showRouteManager: () => setState(() {}),
        saveRouteToServer: _saveRouteToServer,
      );

  Future<void> _loadEngine() async {
    try {
      final lookupsRaw =
          await rootBundle.loadString('assets/charts/s57_lookups.json');
      final colorsRaw =
          await rootBundle.loadString('assets/charts/s57_colors.json');
      final spriteJsonRaw =
          await rootBundle.loadString('assets/charts/sprite.json');
      final spritePngBytes =
          (await rootBundle.load('assets/charts/sprite.png'))
              .buffer
              .asUint8List();
      final lookups =
          LookupTable.fromJson(jsonDecode(lookupsRaw) as Map<String, dynamic>);
      final colors = S52ColorTable.fromRawMap(
        (jsonDecode(colorsRaw) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v as String)),
      );
      final sprites = SpriteAtlas.fromJson(
          jsonDecode(spriteJsonRaw) as Map<String, dynamic>);
      final spriteImage = await _decodeImage(spritePngBytes);
      if (!mounted) return;
      setState(() {
        _engine = S52StyleEngine(
          lookups: lookups,
          options: const S52Options(
            displayCategory: S52DisplayCategory.other,
          ),
          csProcedures: standardCsProcedures,
        );
        _colorTable = colors;
        _spriteAtlas = sprites;
        _spriteImage = spriteImage;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _loadError = '$e\n$st');
    }
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<void> _ensureTile(_TileKey key) async {
    if (_tileCache.containsKey(key) || _inflight.contains(key)) return;
    final engine = _engine;
    if (engine == null) return;
    _inflight.add(key);
    try {
      final url = _tileUrl(key);
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode != 200) {
        _tileCache[key] = _ParsedTile.empty();
        return;
      }
      Uint8List bytes = resp.bodyBytes;
      // Tiles may arrive gzipped; the decoder expects raw protobuf.
      if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
        bytes = Uint8List.fromList(gzip.decode(bytes));
      }
      final decoded = vt.VectorTile.fromBytes(bytes: bytes);
      final parsed = _parse(decoded, engine, key);
      _tileCache[key] = parsed;
      if (mounted) setState(() {});
    } catch (_) {
      _tileCache[key] = _ParsedTile.empty();
    } finally {
      _inflight.remove(key);
    }
  }

  /// Prefer the local cached proxy (cache-first, background-refresh)
  /// when the shared tile server is running. Fall back to direct
  /// upstream when it's not available — tests and dev environments
  /// don't always have it wired.
  String _tileUrl(_TileKey key) {
    final chartId =
        (_firstEnabled('s57')?['id'] as String?) ?? '01CGD_ENCs';
    try {
      final server = context.read<ChartTileServerService>();
      if (server.isRunning) {
        return 'http://localhost:${server.port}/tiles/$chartId/${key.z}/${key.x}/${key.y}';
      }
    } catch (_) {}
    return '${widget.signalKService.httpBaseUrl}/plugins/signalk-charts-provider-simple/$chartId/${key.z}/${key.x}/${key.y}';
  }

  _ParsedTile _parse(vt.VectorTile tile, S52StyleEngine engine, _TileKey key) {
    final out = <_StyledFeature>[];
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
        out.add(_StyledFeature(
          geometry: world,
          instructions: instructions,
          attributes: attrs,
        ));
      }
    }
    return _ParsedTile(features: out);
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
  /// means the painter only needs one call per point
  /// (`camera.latLngToScreenOffset`) with no intermediate math, and no
  /// coupling between tile zoom and rendering.
  _WorldGeometry? _geomToLatLng(
      vt.VectorTileFeature feature, int extent, _TileKey key) {
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
        return _WorldGeometry.point(project(g.coordinates));
      case vt.GeometryType.MultiPoint:
        final g = feature.geometry as vt.GeometryMultiPoint;
        return _WorldGeometry.multiPoint(
            g.coordinates.map(project).toList(growable: false));
      case vt.GeometryType.LineString:
        final g = feature.geometry as vt.GeometryLineString;
        return _WorldGeometry.line(
            [g.coordinates.map(project).toList(growable: false)]);
      case vt.GeometryType.MultiLineString:
        final g = feature.geometry as vt.GeometryMultiLineString;
        return _WorldGeometry.line(g.coordinates
            .map((line) => line.map(project).toList(growable: false))
            .toList(growable: false));
      case vt.GeometryType.Polygon:
        final g = feature.geometry as vt.GeometryPolygon;
        return _WorldGeometry.polygon([
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
        return _WorldGeometry.polygon(rings);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loadError != null) {
      return _ErrorState(error: _loadError!);
    }
    if (_engine == null ||
        _colorTable == null ||
        _spriteAtlas == null ||
        _spriteImage == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading S-52 engine …'),
          ],
        ),
      );
    }
    final baseLayer = _firstEnabled('base');
    final s57Layer = _firstEnabled('s57');
    final basemapUrl = baseLayer == null
        ? null
        : baseMapUrls[baseLayer['id'] as String];
    final baseOpacity = (baseLayer?['opacity'] as num?)?.toDouble() ?? 1.0;
    final s57Opacity = (s57Layer?['opacity'] as num?)?.toDouble() ?? 1.0;

    return Container(
      color: AppColors.cardBackgroundDark,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: _initialZoom,
              minZoom: 8,
              maxZoom: 16,
              onMapEvent: (e) {
                // User-initiated drags/flings disable auto-follow.
                // Programmatic moves (our own `move()` in follow mode)
                // come in as MapEventSource.mapController and are ignored.
                if (e is MapEventMoveStart ||
                    e.source == MapEventSource.onDrag ||
                    e.source == MapEventSource.flingAnimationController ||
                    e.source == MapEventSource.doubleTapZoomAnimationController) {
                  if (_autoFollow && mounted) {
                    setState(() => _autoFollow = false);
                  }
                }
                _refreshTiles();
              },
              onMapReady: _refreshTiles,
              onTap: _onMapTap,
              onLongPress: _onMapLongPress,
            ),
            children: [
              if (basemapUrl != null)
                Opacity(
                  opacity: baseOpacity,
                  child: TileLayer(
                    urlTemplate: basemapUrl,
                    userAgentPackageName: 'org.zennora.zed_display',
                    maxZoom: 19,
                  ),
                ),
              if (s57Layer != null)
                Opacity(
                  opacity: s57Opacity,
                  child: _S57OverlayLayer(
                    tileCache: _tileCache,
                    colorTable: _colorTable!,
                    spriteAtlas: _spriteAtlas!,
                    spriteImage: _spriteImage!,
                  ),
                ),
              if (_trailPoints.length >= 2)
                _TrailOverlayLayer(
                  points: _trailPoints,
                  timestamps: _trailTimestamps,
                ),
              if (_rulerVisible && _rulerA != null && _rulerB != null) ...[
                _RulerLineLayer(a: _rulerA!, b: _rulerB!),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _rulerA!,
                      width: 32,
                      height: 32,
                      child: _RulerHandle(
                        color: const Color(0xFFFF5252),
                        onDrag: (ll) =>
                            setState(() => _rulerA = ll),
                      ),
                    ),
                    Marker(
                      point: _rulerB!,
                      width: 32,
                      height: 32,
                      child: _RulerHandle(
                        color: const Color(0xFF4FC3F7),
                        onDrag: (ll) =>
                            setState(() => _rulerB = ll),
                      ),
                    ),
                  ],
                ),
              ],
              if (_routeCoords != null)
                _RouteOverlayLayer(
                  coords: _routeCoords!,
                  activeIndex: _routePointIndex,
                  names: _waypointNames,
                ),
              if (_aisEnabled && _aisVessels.isNotEmpty)
                _AisOverlayLayer(
                  vessels: _aisVessels,
                  showPaths: _aisShowPaths,
                ),
              if (_ownLat != null && _ownLon != null)
                _OwnVesselLayer(
                  lat: _ownLat!,
                  lon: _ownLon!,
                  // Heading wins for bow direction; COG is the fallback
                  // so sailboats without a compass still point sensibly.
                  bearingRadians: _ownHeading ?? _ownCog ?? 0.0,
                ),
              const Scalebar(
                alignment: Alignment.bottomLeft,
                textStyle: TextStyle(color: Colors.white, fontSize: 12),
                lineColor: Colors.white,
                strokeWidth: 2,
                padding: EdgeInsets.fromLTRB(8, 8, 8, 64),
              ),
            ],
          ),
          ChartPlotterHUD(
            signalKService: widget.signalKService,
            hudStyle: _hudStyle,
            hudPosition: _hudPosition,
            paths: _fallbackPaths,
            hasActiveRoute: _routeCoords != null,
            canAdvance: _routeCoords != null &&
                _routePointIndex != null &&
                _routePointTotal != null &&
                _routePointIndex! + 1 < _routePointTotal!,
            onAdvanceWaypoint: () {
              final i = _routePointIndex;
              if (i != null) _skipToWaypoint(i + 1);
            },
          ),
          Positioned(
            bottom: _hudStyle == 'visual' ? 190 : (_hudStyle == 'text' ? 52 : 8),
            right: 8,
            child: _FreshnessChip(
              freshness: _viewportFreshness,
              connected: widget.signalKService.isConnected,
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: _MapControls(
              autoFollow: _autoFollow,
              rulerVisible: _rulerVisible,
              aisEnabled: _aisEnabled,
              aisActiveOnly: _aisActiveOnly,
              aisShowPaths: _aisShowPaths,
              onLayers: () => _showLayerSheet(context),
              onRoutes: () => _showRouteManager(context),
              onDownload: () => _showDownloadSheet(context),
              onToggleFollow: () {
                setState(() => _autoFollow = !_autoFollow);
                if (_autoFollow && _ownLat != null && _ownLon != null) {
                  _mapController.move(
                    LatLng(_ownLat!, _ownLon!),
                    _mapController.camera.zoom,
                  );
                }
              },
              onToggleRuler: _toggleRuler,
              onToggleAis: () {
                setState(() {
                  _aisEnabled = !_aisEnabled;
                  if (_aisEnabled) _refreshAisVessels();
                });
              },
              onToggleAisActive: () {
                setState(() {
                  _aisActiveOnly = !_aisActiveOnly;
                  _refreshAisVessels();
                });
              },
              onToggleAisPaths: () {
                setState(() {
                  _aisShowPaths = !_aisShowPaths;
                  _refreshAisVessels();
                });
              },
            ),
          ),
          if (_rulerVisible && _rulerA != null && _rulerB != null)
            Positioned(
              top: 8,
              left: 8,
              child: _RulerReadout(
                signalKService: widget.signalKService,
                a: _rulerA!,
                b: _rulerB!,
              ),
            ),
        ],
      ),
    );
  }

  void _showRouteManager(BuildContext ctx) {
    showRouteManagerSheet(
      ctx,
      signalKService: widget.signalKService,
      routeState: ChartRouteState(
        routeCoords: _routeCoords,
        waypointNames: _waypointNames,
        routePointIndex: _routePointIndex,
        routePointTotal: _routePointTotal,
        activeRouteId: _activeRouteId,
      ),
      callbacks: _routeCallbacks,
      navPaths: _fallbackPaths,
    );
  }

  /// Toggle the ruler overlay. First enable seeds the two endpoints
  /// roughly 30% / 70% across the current viewport width so they're
  /// immediately visible on either side of centre.
  void _toggleRuler() {
    setState(() {
      _rulerVisible = !_rulerVisible;
      if (_rulerVisible && (_rulerA == null || _rulerB == null)) {
        final bounds = _mapController.camera.visibleBounds;
        final lat = bounds.center.latitude;
        final lonSpan = bounds.east - bounds.west;
        _rulerA = LatLng(lat, bounds.west + lonSpan * 0.3);
        _rulerB = LatLng(lat, bounds.west + lonSpan * 0.7);
      }
    });
  }

  void _showDownloadSheet(BuildContext ctx) {
    ChartDownloadManager? downloadManager;
    try {
      downloadManager = ctx.read<ChartDownloadManager>();
    } catch (_) {
      return;
    }
    final bounds = _mapController.camera.visibleBounds;
    final minLon = bounds.west;
    final minLat = bounds.south;
    final maxLon = bounds.east;
    final maxLat = bounds.north;

    var minZoom = 9;
    var maxZoom = 16;
    final nameController = TextEditingController(
      text: 'Area ${DateTime.now().toString().substring(0, 16)}',
    );

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (_, setSheetState) {
          final estimate = downloadManager!.estimateTileCount(
            minLon: minLon,
            minLat: minLat,
            maxLon: maxLon,
            maxLat: maxLat,
            minZoom: minZoom,
            maxZoom: maxZoom,
          );
          final estimatedMB = (estimate * 10 / 1024).toStringAsFixed(1);

          return Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            decoration: const BoxDecoration(
              color: AppColors.cardBackgroundDark,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[600],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text('Download Charts',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  '${minLat.toStringAsFixed(2)}°N to ${maxLat.toStringAsFixed(2)}°N, '
                  '${minLon.toStringAsFixed(2)}°E to ${maxLon.toStringAsFixed(2)}°E',
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Region name',
                    hintStyle: TextStyle(color: Colors.white38),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.green)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  const Text('Zoom: ',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 13)),
                  Expanded(
                    child: RangeSlider(
                      values: RangeValues(
                          minZoom.toDouble(), maxZoom.toDouble()),
                      min: 9,
                      max: 16,
                      divisions: 7,
                      labels: RangeLabels('$minZoom', '$maxZoom'),
                      onChanged: (v) => setSheetState(() {
                        minZoom = v.start.toInt();
                        maxZoom = v.end.toInt();
                      }),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Text('$estimate tiles (~$estimatedMB MB)',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 12),
                ListenableBuilder(
                  listenable: downloadManager,
                  builder: (context, _) {
                    final mgr = downloadManager!;
                    if (mgr.status == DownloadStatus.downloading) {
                      return Column(children: [
                        LinearProgressIndicator(value: mgr.progress),
                        const SizedBox(height: 4),
                        Text('${mgr.downloadedTiles} of ${mgr.totalTiles}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: mgr.cancel,
                          child: const Text('Cancel',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ]);
                    }
                    if (mgr.status == DownloadStatus.completed) {
                      return const Text('Download complete!',
                          style: TextStyle(
                              color: Colors.green,
                              fontSize: 14,
                              fontWeight: FontWeight.w500));
                    }
                    if (mgr.status == DownloadStatus.error) {
                      return Text(mgr.errorMessage ?? 'Download failed',
                          style: const TextStyle(
                              color: Colors.red, fontSize: 13));
                    }
                    final chartId = (_firstEnabled('s57')?['id'] as String?) ??
                        '01CGD_ENCs';
                    return Column(children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.download),
                          label: const Text('Download New'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => mgr.downloadArea(
                            minLon: minLon,
                            minLat: minLat,
                            maxLon: maxLon,
                            maxLat: maxLat,
                            minZoom: minZoom,
                            maxZoom: maxZoom,
                            baseUrl: widget.signalKService.httpBaseUrl,
                            authToken: widget.signalKService.authToken?.token,
                            regionName: nameController.text,
                            chartId: chartId,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('Flush & Re-download All'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange,
                            side: const BorderSide(color: Colors.orange),
                          ),
                          onPressed: () => mgr.downloadArea(
                            minLon: minLon,
                            minLat: minLat,
                            maxLon: maxLon,
                            maxLat: maxLat,
                            minZoom: minZoom,
                            maxZoom: maxZoom,
                            baseUrl: widget.signalKService.httpBaseUrl,
                            authToken: widget.signalKService.authToken?.token,
                            regionName: nameController.text,
                            chartId: chartId,
                            flush: true,
                          ),
                        ),
                      ),
                    ]);
                  },
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() => downloadManager?.reset());
  }

  void _showLayerSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppColors.cardBackgroundDark,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sbCtx, sbSetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Chart Layers',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                ChartLayerPanel(
                  layers: _layers,
                  signalKService: widget.signalKService,
                  // Re-render the sheet immediately AND the V3 tool so
                  // toggles take effect without closing the sheet.
                  setState: (fn) {
                    sbSetState(fn);
                    if (mounted) setState(fn);
                  },
                  onLayersChanged: () {
                    if (mounted) setState(() {});
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _refreshTiles() {
    final camera = _mapController.camera;
    final zInt = camera.zoom.round().clamp(9, 16);
    final bounds = camera.visibleBounds;
    final x0 = _lonToTileX(bounds.west, zInt);
    final x1 = _lonToTileX(bounds.east, zInt);
    final y0 = _latToTileY(bounds.north, zInt);
    final y1 = _latToTileY(bounds.south, zInt);
    // Clamp to a small window to avoid hammering the server during the
    // spike; real viewport loading is a follow-up.
    final maxTiles = 9;
    int fetched = 0;
    final viewportTiles = <(int, int, int)>[];
    for (var x = x0; x <= x1 && fetched < maxTiles; x++) {
      for (var y = y0; y <= y1 && fetched < maxTiles; y++) {
        _ensureTile(_TileKey(zInt, x, y));
        viewportTiles.add((zInt, x, y));
        fetched++;
      }
    }
    _refreshFreshness(viewportTiles);
  }

  void _refreshFreshness(List<(int, int, int)> viewportTiles) {
    try {
      final cache = context.read<ChartTileCacheService>();
      final f = cache.getViewportFreshness(viewportTiles);
      if (f != _viewportFreshness && mounted) {
        setState(() => _viewportFreshness = f);
      }
    } catch (_) {
      // Cache service not registered in this context (tests); ignore.
    }
  }
}

int _lonToTileX(double lon, int z) =>
    ((lon + 180.0) / 360.0 * (1 << z)).floor();

int _latToTileY(double lat, int z) {
  final rad = lat * math.pi / 180.0;
  return ((1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) /
          2 *
          (1 << z))
      .floor();
}

class _TileKey {
  const _TileKey(this.z, this.x, this.y);
  final int z;
  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      other is _TileKey && other.z == z && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(z, x, y);
}

class _ParsedTile {
  const _ParsedTile({required this.features});
  factory _ParsedTile.empty() => const _ParsedTile(features: []);
  final List<_StyledFeature> features;
}

class _StyledFeature {
  const _StyledFeature({
    required this.geometry,
    required this.instructions,
    required this.attributes,
  });
  final _WorldGeometry geometry;
  final List<S52Instruction> instructions;
  final Map<String, Object?> attributes;
}

enum _GeomKind { point, line, polygon }

class _WorldGeometry {
  const _WorldGeometry._(this.kind, this.points, this.lines, this.rings);

  factory _WorldGeometry.point(LatLng p) =>
      _WorldGeometry._(_GeomKind.point, [p], const [], const []);
  factory _WorldGeometry.multiPoint(List<LatLng> ps) =>
      _WorldGeometry._(_GeomKind.point, ps, const [], const []);
  factory _WorldGeometry.line(List<List<LatLng>> ls) =>
      _WorldGeometry._(_GeomKind.line, const [], ls, const []);
  factory _WorldGeometry.polygon(List<List<List<LatLng>>> rs) =>
      _WorldGeometry._(_GeomKind.polygon, const [], const [], rs);

  final _GeomKind kind;
  final List<LatLng> points;
  final List<List<LatLng>> lines;
  final List<List<List<LatLng>>> rings;
}

class _S57OverlayLayer extends StatelessWidget {
  const _S57OverlayLayer({
    required this.tileCache,
    required this.colorTable,
    required this.spriteAtlas,
    required this.spriteImage,
  });
  final Map<_TileKey, _ParsedTile> tileCache;
  final S52ColorTable colorTable;
  final SpriteAtlas spriteAtlas;
  final ui.Image spriteImage;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _S57Painter(
          camera: camera,
          tiles: tileCache,
          colorTable: colorTable,
          spriteAtlas: spriteAtlas,
          spriteImage: spriteImage,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _S57Painter extends CustomPainter {
  _S57Painter({
    required this.camera,
    required this.tiles,
    required this.colorTable,
    required this.spriteAtlas,
    required this.spriteImage,
  });
  final MapCamera camera;
  final Map<_TileKey, _ParsedTile> tiles;
  final S52ColorTable colorTable;
  final SpriteAtlas spriteAtlas;
  final ui.Image spriteImage;

  @override
  void paint(Canvas canvas, Size size) {
    if (tiles.isEmpty) return;
    // Canonical flutter_map layer coordinate space: pixel positions
    // relative to `camera.pixelOrigin` (the top-left of the viewport
    // at the current zoom). `MobileLayerTransformer` handles rotation
    // around this painter, so we don't touch rotation here.
    final origin = camera.pixelOrigin;
    Offset project(LatLng p) => camera.projectAtZoom(p) - origin;

    // Three passes by geometry kind — polygons (area fills + patterns)
    // on the bottom, lines in the middle, points on top. This
    // approximates S-52's priority bands (group1 areas → line symbols
    // → point symbols) without needing per-feature priority data from
    // the engine. A finer-grained priority sort lives behind a later
    // task, once the lookup row's priority is threaded through.
    for (final kind in _paintOrder) {
      for (final entry in tiles.values) {
        for (final f in entry.features) {
          if (f.geometry.kind != kind) continue;
          _paintFeature(canvas, f, project);
        }
      }
    }
  }

  static const _paintOrder = [
    _GeomKind.polygon,
    _GeomKind.line,
    _GeomKind.point,
  ];

  void _paintFeature(
      Canvas canvas, _StyledFeature f, Offset Function(LatLng) project) {
    for (final instruction in f.instructions) {
      if (instruction is S52Symbol && f.geometry.kind == _GeomKind.point) {
        final meta = spriteAtlas.lookup(instruction.name);
        if (meta == null) {
          // Symbol not in atlas — fall back to a small CHBLK dot so
          // the feature is at least locatable. Useful for catching
          // missing-sprite cases during development.
          final paint = Paint()..color = _resolve('CHBLK');
          for (final p in f.geometry.points) {
            canvas.drawCircle(project(p), 2, paint);
          }
          continue;
        }
        final srcRect = Rect.fromLTWH(
          meta.x.toDouble(),
          meta.y.toDouble(),
          meta.width.toDouble(),
          meta.height.toDouble(),
        );
        final paint = Paint()..filterQuality = FilterQuality.low;
        for (final p in f.geometry.points) {
          final s = project(p);
          final dstRect = Rect.fromLTWH(
            s.dx - meta.pivotX,
            s.dy - meta.pivotY,
            meta.width.toDouble(),
            meta.height.toDouble(),
          );
          canvas.drawImageRect(spriteImage, srcRect, dstRect, paint);
        }
      } else if (instruction is S52LineStyle &&
          f.geometry.kind == _GeomKind.line) {
        final paint = Paint()
          ..color = _resolve(instruction.colorCode)
          ..strokeWidth = instruction.width.toDouble().clamp(1, 4)
          ..style = PaintingStyle.stroke;
        final dash = _dashIntervals(instruction.pattern);
        for (final line in f.geometry.lines) {
          final path = _linePath(line, project);
          canvas.drawPath(dash == null ? path : _dashPath(path, dash), paint);
        }
      } else if (instruction is S52LineComplex &&
          f.geometry.kind == _GeomKind.line) {
        _paintLineComplex(canvas, instruction.patternName, f, project);
      } else if (instruction is S52AreaColor &&
          f.geometry.kind == _GeomKind.polygon) {
        final paint = Paint()
          ..color = _resolve(instruction.colorCode)
          ..style = PaintingStyle.fill;
        for (final polygon in f.geometry.rings) {
          canvas.drawPath(_polygonPath(polygon, project), paint);
        }
      } else if (instruction is S52AreaPattern &&
          f.geometry.kind == _GeomKind.polygon) {
        _paintAreaPattern(canvas, instruction.patternName, f, project);
      } else if (instruction is S52TextLiteral &&
          f.geometry.kind == _GeomKind.point) {
        _paintText(canvas, instruction.text, f.geometry.points, project);
      } else if (instruction is S52Text &&
          f.geometry.kind == _GeomKind.point) {
        final value = f.attributes[instruction.attribute];
        if (value != null) {
          _paintText(canvas, value.toString(), f.geometry.points, project);
        }
      } else if (instruction is S52TextFormatted &&
          f.geometry.kind == _GeomKind.point) {
        final rendered = _formatText(instruction.format, instruction.args, f);
        if (rendered != null) {
          _paintText(canvas, rendered, f.geometry.points, project);
        }
      }
    }
  }

  /// Minimal printf-ish substitution for TE() format strings. S-52
  /// supports full C printf; we cover the common cases used by the
  /// bundled Freeboard lookups: `%s`, `%d`, `%f` and `%.Nf` / `%lf`
  /// variants with optional width. Unknown specifiers pass through
  /// the next attribute as a plain string. Returns null if the format
  /// or attributes are malformed — the caller silently skips.
  String? _formatText(
      String format, List<String> args, _StyledFeature f) {
    // `args` = [format, attr1, attr2, ..., positioning-fields...]. The
    // number of `%` placeholders tells us how many attr slots to pull.
    // Strip surrounding single quotes that the parser preserves.
    String unquote(String s) =>
        s.length >= 2 && s.startsWith("'") && s.endsWith("'")
            ? s.substring(1, s.length - 1)
            : s;
    final fmt = unquote(format);
    final placeholder = RegExp(r'%[-+ 0#]?(\d+)?(?:\.(\d+))?[lh]?([sdifox])');
    final buffer = StringBuffer();
    var cursor = 0;
    var attrIndex = 1; // args[0] is format
    for (final m in placeholder.allMatches(fmt)) {
      buffer.write(fmt.substring(cursor, m.start));
      if (attrIndex >= args.length) return null;
      final attrName = unquote(args[attrIndex]);
      attrIndex++;
      final value = f.attributes[attrName];
      if (value == null) return null;
      final precision = m.group(2);
      final kind = m.group(3);
      String rendered;
      if (kind == 'd' || kind == 'i') {
        rendered =
            (value is num ? value.toInt() : int.tryParse('$value') ?? 0)
                .toString();
      } else if (kind == 'f' || kind == 'lf') {
        final n = value is num ? value.toDouble() : double.tryParse('$value');
        if (n == null) return null;
        rendered = precision == null
            ? n.toString()
            : n.toStringAsFixed(int.parse(precision));
      } else {
        rendered = value.toString();
      }
      buffer.write(rendered);
      cursor = m.end;
    }
    buffer.write(fmt.substring(cursor));
    return buffer.toString();
  }

  /// Stamp a sprite repeatedly along the line's polylines, rotated to
  /// match each segment direction. S-52's LC() complex lines assume a
  /// tile spacing equal to the sprite's native width; we keep it
  /// simple and do the same. Uses `PathMetric.extractPath` to walk at
  /// fixed intervals with correct tangent direction per stamp.
  void _paintLineComplex(
    Canvas canvas,
    String patternName,
    _StyledFeature f,
    Offset Function(LatLng) project,
  ) {
    final meta = spriteAtlas.lookup(patternName);
    if (meta == null) return;
    final srcRect = Rect.fromLTWH(
      meta.x.toDouble(),
      meta.y.toDouble(),
      meta.width.toDouble(),
      meta.height.toDouble(),
    );
    final stamp = meta.width.toDouble();
    if (stamp <= 0) return;
    final paint = Paint()..filterQuality = FilterQuality.low;
    final dstSize = Size(stamp, meta.height.toDouble());
    for (final line in f.geometry.lines) {
      final path = _linePath(line, project);
      for (final metric in path.computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += stamp) {
          final tangent = metric.getTangentForOffset(d);
          if (tangent == null) break;
          canvas.save();
          canvas.translate(tangent.position.dx, tangent.position.dy);
          canvas.rotate(tangent.angle);
          canvas.drawImageRect(
            spriteImage,
            srcRect,
            Rect.fromLTWH(0, -dstSize.height / 2, dstSize.width, dstSize.height),
            paint,
          );
          canvas.restore();
        }
      }
    }
  }

  /// Tile a sprite across the polygon interior. Freeboard's
  /// area-pattern symbols (DRGARE51, ACHARE02, etc.) are designed to
  /// tile seamlessly at their native sprite dimensions. We clip to the
  /// polygon and draw a grid of `drawImageRect` calls over its
  /// bounding box. Crude but correct for visual parity.
  void _paintAreaPattern(
    Canvas canvas,
    String patternName,
    _StyledFeature f,
    Offset Function(LatLng) project,
  ) {
    final meta = spriteAtlas.lookup(patternName);
    if (meta == null) return;
    final srcRect = Rect.fromLTWH(
      meta.x.toDouble(),
      meta.y.toDouble(),
      meta.width.toDouble(),
      meta.height.toDouble(),
    );
    final paint = Paint()..filterQuality = FilterQuality.low;
    for (final polygon in f.geometry.rings) {
      final path = _polygonPath(polygon, project);
      final bounds = path.getBounds();
      if (bounds.isEmpty) continue;
      canvas.save();
      canvas.clipPath(path);
      final w = meta.width.toDouble();
      final h = meta.height.toDouble();
      for (var y = bounds.top; y < bounds.bottom; y += h) {
        for (var x = bounds.left; x < bounds.right; x += w) {
          canvas.drawImageRect(
            spriteImage,
            srcRect,
            Rect.fromLTWH(x, y, w, h),
            paint,
          );
        }
      }
      canvas.restore();
    }
  }

  /// Crude text rendering. Real S-52 uses the TE/TX parameter list for
  /// font, size, colour, justification and per-character offsets.
  /// For the spike we centre the label on the feature point in CHBLK
  /// at a fixed 11pt; that's enough to verify SOUNDG depth labels are
  /// landing in roughly the right place.
  void _paintText(Canvas canvas, String text, List<LatLng> anchors,
      Offset Function(LatLng) project) {
    if (text.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: _resolve('CHBLK'),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    final half = Offset(painter.width / 2, painter.height / 2);
    for (final p in anchors) {
      painter.paint(canvas, project(p) - half);
    }
  }

  /// Map an S-52 line pattern to an on/off interval list in pixels.
  /// Returns null for SOLD (no dashing). Numbers chosen to match the
  /// visual weight of Freeboard's output — the S-52 spec allows
  /// renderer latitude here.
  List<double>? _dashIntervals(S52LinePattern pattern) {
    switch (pattern) {
      case S52LinePattern.solid:
        return null;
      case S52LinePattern.dash:
        return const [6.0, 4.0];
      case S52LinePattern.dott:
        return const [1.5, 3.0];
    }
  }

  /// Rebuild a path as a sequence of dash/gap segments along its
  /// polylines. Works by walking `PathMetric` and extracting sub-paths
  /// at each interval boundary — Flutter's stock approach for dashed
  /// strokes since the framework doesn't expose PathEffect.
  ui.Path _dashPath(ui.Path source, List<double> intervals) {
    final out = ui.Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0.0;
      var on = true;
      var i = 0;
      while (distance < metric.length) {
        final span = intervals[i % intervals.length];
        final next = distance + span;
        if (on) {
          out.addPath(
            metric.extractPath(distance, next.clamp(0, metric.length)),
            Offset.zero,
          );
        }
        distance = next;
        on = !on;
        i++;
      }
    }
    return out;
  }

  ui.Path _linePath(List<LatLng> line, Offset Function(LatLng) project) {
    final path = ui.Path();
    for (var i = 0; i < line.length; i++) {
      final s = project(line[i]);
      if (i == 0) {
        path.moveTo(s.dx, s.dy);
      } else {
        path.lineTo(s.dx, s.dy);
      }
    }
    return path;
  }

  /// Build a single Path covering a polygon and its holes. Using
  /// `PathFillType.evenOdd` lets a single draw call handle outer ring
  /// + holes correctly without separate clip operations.
  ui.Path _polygonPath(
      List<List<LatLng>> rings, Offset Function(LatLng) project) {
    final path = ui.Path()..fillType = ui.PathFillType.evenOdd;
    for (final ring in rings) {
      if (ring.isEmpty) continue;
      for (var i = 0; i < ring.length; i++) {
        final s = project(ring[i]);
        if (i == 0) {
          path.moveTo(s.dx, s.dy);
        } else {
          path.lineTo(s.dx, s.dy);
        }
      }
      path.close();
    }
    return path;
  }

  /// Resolve an S-52 colour code. Falls back to CHBLK so unknown codes
  /// still draw (visible but obviously wrong) rather than crashing.
  Color _resolve(String code) {
    final c = colorTable.lookup(code) ?? colorTable.lookup('CHBLK');
    if (c == null) return const Color(0xFF000000);
    return Color(c.toArgb32());
  }

  @override
  bool shouldRepaint(covariant _S57Painter old) =>
      old.camera != camera ||
      old.tiles != tiles ||
      old.colorTable != colorTable ||
      old.spriteAtlas != spriteAtlas ||
      old.spriteImage != spriteImage;
}

/// Paints the vessel's recent track. Segments fade from opaque at the
/// head (newest) to translucent at the tail (oldest) so the current
/// direction of travel is obvious at a glance.
class _TrailOverlayLayer extends StatelessWidget {
  const _TrailOverlayLayer({required this.points, required this.timestamps});
  final List<LatLng> points;
  final List<int> timestamps;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _TrailPainter(
          camera: camera,
          points: points,
          timestamps: timestamps,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _TrailPainter extends CustomPainter {
  _TrailPainter({
    required this.camera,
    required this.points,
    required this.timestamps,
  });
  final MapCamera camera;
  final List<LatLng> points;
  final List<int> timestamps;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final origin = camera.pixelOrigin;
    final newest = timestamps.last;
    final oldest = timestamps.first;
    final span = (newest - oldest).clamp(1, 1 << 31).toDouble();
    for (var i = 1; i < points.length; i++) {
      final a = camera.projectAtZoom(points[i - 1]) - origin;
      final b = camera.projectAtZoom(points[i]) - origin;
      // Alpha increases linearly with age → newer segments show
      // brighter. Minimum 0.15 so the oldest still reads on screen.
      final age = (newest - timestamps[i]) / span;
      final alpha = (1.0 - age).clamp(0.15, 1.0);
      final paint = Paint()
        ..color = const Color(0xFFFF5252).withValues(alpha: alpha)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(a, b, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrailPainter old) =>
      old.camera != camera ||
      old.points.length != points.length ||
      (points.isNotEmpty && old.points.last != points.last);
}

/// Compact, painter-friendly snapshot of an AIS vessel. Only the
/// fields the painter actually reads are kept so the per-frame hot
/// loop stays cheap.
class _AisRenderable {
  const _AisRenderable({
    required this.id,
    required this.position,
    required this.bearingRadians,
    required this.name,
    required this.projections,
  });
  final String id;
  final LatLng position;
  final double bearingRadians;
  final String name;
  final List<LatLng> projections;
}

class _AisOverlayLayer extends StatelessWidget {
  const _AisOverlayLayer({
    required this.vessels,
    required this.showPaths,
  });
  final List<_AisRenderable> vessels;
  final bool showPaths;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _AisPainter(
          camera: camera,
          vessels: vessels,
          showPaths: showPaths,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _AisPainter extends CustomPainter {
  _AisPainter({
    required this.camera,
    required this.vessels,
    required this.showPaths,
  });
  final MapCamera camera;
  final List<_AisRenderable> vessels;
  final bool showPaths;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = camera.pixelOrigin;
    final trianglePath = ui.Path()
      ..moveTo(0, -9)
      ..lineTo(6, 8)
      ..lineTo(0, 4)
      ..lineTo(-6, 8)
      ..close();
    final fill = Paint()..color = const Color(0xFF4CAF50);
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final pathPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (final v in vessels) {
      if (showPaths && v.projections.isNotEmpty) {
        final start = camera.projectAtZoom(v.position) - origin;
        final path = ui.Path()..moveTo(start.dx, start.dy);
        for (final p in v.projections) {
          final s = camera.projectAtZoom(p) - origin;
          path.lineTo(s.dx, s.dy);
        }
        canvas.drawPath(path, pathPaint);
        for (final p in v.projections) {
          canvas.drawCircle(
              camera.projectAtZoom(p) - origin, 2, pathPaint);
        }
      }
      final c = camera.projectAtZoom(v.position) - origin;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(v.bearingRadians);
      canvas.drawPath(trianglePath, fill);
      canvas.drawPath(trianglePath, stroke);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _AisPainter old) =>
      old.camera != camera ||
      old.vessels != vessels ||
      old.showPaths != showPaths;
}

/// Simple draggable handle for the ruler endpoints. Converts pan
/// deltas into LatLng via the map camera's screen→world projection.
class _RulerHandle extends StatelessWidget {
  const _RulerHandle({required this.color, required this.onDrag});
  final Color color;
  final ValueChanged<LatLng> onDrag;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) {
        // Convert screen delta to a new LatLng by inverse-projecting
        // the current handle centre plus the delta. Uses camera's
        // pixel projection for consistency with layer overlays.
        const handleSize = Size(32, 32);
        final localCenter = d.localPosition +
            Offset(-handleSize.width / 2, -handleSize.height / 2);
        // Actually `d.localPosition` is relative to the handle; we
        // need a world-space delta. Easier route: use globalPosition
        // mapped to the map viewport via `offsetToCrs`.
        final ll = camera.offsetToCrs(d.globalPosition);
        onDrag(ll);
        // localCenter unused — keep the computation honest for future
        // refinements; avoid unused-variable warning with a discard.
        // ignore: unused_local_variable
        final _ = localCenter;
      },
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.8),
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    );
  }
}

/// Draws a thin line between the two ruler endpoints. A dedicated
/// painter makes sure the line sits *behind* the marker handles.
class _RulerLineLayer extends StatelessWidget {
  const _RulerLineLayer({required this.a, required this.b});
  final LatLng a;
  final LatLng b;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _RulerLinePainter(camera: camera, a: a, b: b),
        size: Size.infinite,
      ),
    );
  }
}

class _RulerLinePainter extends CustomPainter {
  _RulerLinePainter({required this.camera, required this.a, required this.b});
  final MapCamera camera;
  final LatLng a;
  final LatLng b;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = camera.pixelOrigin;
    final pa = camera.projectAtZoom(a) - origin;
    final pb = camera.projectAtZoom(b) - origin;
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(pa, pb, paint);
  }

  @override
  bool shouldRepaint(covariant _RulerLinePainter old) =>
      old.camera != camera || old.a != a || old.b != b;
}

/// Pill of distance + bearings between the ruler endpoints. Distance
/// formats via MetadataStore so the units match the rest of the app's
/// navigation HUD rather than hard-coding metres.
class _RulerReadout extends StatelessWidget {
  const _RulerReadout({
    required this.signalKService,
    required this.a,
    required this.b,
  });
  final SignalKService signalKService;
  final LatLng a;
  final LatLng b;

  @override
  Widget build(BuildContext context) {
    final distance = const Distance().as(LengthUnit.Meter, a, b);
    final bearingRed = _bearing(a, b);
    final bearingBlue = _bearing(b, a);
    final distMeta = signalKService.metadataStore
        .getByCategory('shortDistance'); // matches V1 ruler unit hookup
    final distLabel = distMeta.formatOrRaw(distance, decimals: 2,
        siSuffix: 'm');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(distLabel,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('🔴→🔵  ${bearingRed.toStringAsFixed(1)}°',
              style:
                  const TextStyle(color: Colors.white70, fontSize: 11)),
          Text('🔵→🔴  ${bearingBlue.toStringAsFixed(1)}°',
              style:
                  const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  double _bearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final deg = math.atan2(y, x) * 180 / math.pi;
    return (deg + 360) % 360;
  }
}

/// Paints the own vessel as a directional arrow at its current
/// position. Rotation is driven by true heading when available,
/// falling back to COG (the common case for sailboats without a
/// compass sensor).
class _OwnVesselLayer extends StatelessWidget {
  const _OwnVesselLayer({
    required this.lat,
    required this.lon,
    required this.bearingRadians,
  });
  final double lat;
  final double lon;
  final double bearingRadians;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _OwnVesselPainter(
          camera: camera,
          position: LatLng(lat, lon),
          bearingRadians: bearingRadians,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _OwnVesselPainter extends CustomPainter {
  _OwnVesselPainter({
    required this.camera,
    required this.position,
    required this.bearingRadians,
  });
  final MapCamera camera;
  final LatLng position;
  final double bearingRadians;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = camera.pixelOrigin;
    final center = camera.projectAtZoom(position) - origin;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(bearingRadians);

    // Classic chart-plotter boat-arrow: tall isoceles triangle, bow
    // pointing "up" (north in painter-local coords before rotation).
    final path = ui.Path()
      ..moveTo(0, -14)
      ..lineTo(9, 10)
      ..lineTo(0, 5)
      ..lineTo(-9, 10)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = const Color(0xFFFF5252),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OwnVesselPainter old) =>
      old.camera != camera ||
      old.position != position ||
      old.bearingRadians != bearingRadians;
}

/// Paints the active route — a coloured polyline with numbered
/// waypoint circles. The current waypoint is highlighted. Lives on
/// top of the S-57 overlay so it's always visible.
class _RouteOverlayLayer extends StatelessWidget {
  const _RouteOverlayLayer({
    required this.coords,
    required this.activeIndex,
    required this.names,
  });
  final List<List<double>> coords;
  final int? activeIndex;
  final List<String>? names;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _RoutePainter(
          camera: camera,
          coords: coords,
          activeIndex: activeIndex,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({
    required this.camera,
    required this.coords,
    required this.activeIndex,
  });
  final MapCamera camera;
  final List<List<double>> coords;
  final int? activeIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (coords.length < 2) return;
    final origin = camera.pixelOrigin;
    Offset project(List<double> lonLat) =>
        camera.projectAtZoom(LatLng(lonLat[1], lonLat[0])) - origin;

    final line = Paint()
      ..color = const Color(0xFF4FC3F7)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final path = ui.Path();
    for (var i = 0; i < coords.length; i++) {
      final p = project(coords[i]);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, line);

    final waypoint = Paint()..color = const Color(0xFF4FC3F7);
    final active = Paint()..color = const Color(0xFFFFC107);
    final outline = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < coords.length; i++) {
      final p = project(coords[i]);
      final isActive = i == activeIndex;
      canvas.drawCircle(p, isActive ? 8 : 5, isActive ? active : waypoint);
      canvas.drawCircle(p, isActive ? 8 : 5, outline);
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) =>
      old.camera != camera ||
      old.coords != coords ||
      old.activeIndex != activeIndex;
}

class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.autoFollow,
    required this.rulerVisible,
    required this.aisEnabled,
    required this.aisActiveOnly,
    required this.aisShowPaths,
    required this.onLayers,
    required this.onRoutes,
    required this.onDownload,
    required this.onToggleFollow,
    required this.onToggleRuler,
    required this.onToggleAis,
    required this.onToggleAisActive,
    required this.onToggleAisPaths,
  });
  final bool autoFollow;
  final bool rulerVisible;
  final bool aisEnabled;
  final bool aisActiveOnly;
  final bool aisShowPaths;
  final VoidCallback onLayers;
  final VoidCallback onRoutes;
  final VoidCallback onDownload;
  final VoidCallback onToggleFollow;
  final VoidCallback onToggleRuler;
  final VoidCallback onToggleAis;
  final VoidCallback onToggleAisActive;
  final VoidCallback onToggleAisPaths;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              autoFollow ? Icons.my_location : Icons.location_searching,
              color: Colors.white,
              size: 20,
            ),
            tooltip: autoFollow ? 'Snap to vessel (on)' : 'Snap to vessel (off)',
            onPressed: onToggleFollow,
          ),
          IconButton(
            icon: const Icon(Icons.layers, color: Colors.white, size: 20),
            tooltip: 'Chart layers',
            onPressed: onLayers,
          ),
          IconButton(
            icon: const Icon(Icons.route, color: Colors.white, size: 20),
            tooltip: 'Routes',
            onPressed: onRoutes,
          ),
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white, size: 20),
            tooltip: 'Download charts',
            onPressed: onDownload,
          ),
          IconButton(
            icon: Icon(
              rulerVisible ? Icons.straighten : Icons.straighten_outlined,
              color: Colors.white,
              size: 20,
            ),
            tooltip: rulerVisible ? 'Hide ruler' : 'Show ruler',
            onPressed: onToggleRuler,
          ),
          IconButton(
            icon: Icon(
              aisEnabled ? Icons.sailing : Icons.sailing_outlined,
              color: Colors.white,
              size: 20,
            ),
            tooltip: aisEnabled ? 'AIS on' : 'AIS off',
            onPressed: onToggleAis,
          ),
          if (aisEnabled) ...[
            IconButton(
              icon: Icon(
                aisActiveOnly
                    ? Icons.filter_alt
                    : Icons.filter_alt_outlined,
                color: Colors.white,
                size: 20,
              ),
              tooltip: aisActiveOnly ? 'Active only' : 'All vessels',
              onPressed: onToggleAisActive,
            ),
            IconButton(
              icon: Icon(
                aisShowPaths ? Icons.timeline : Icons.linear_scale,
                color: Colors.white,
                size: 20,
              ),
              tooltip: aisShowPaths ? 'Hide projections' : 'Show projections',
              onPressed: onToggleAisPaths,
            ),
          ],
        ],
      ),
    );
  }
}

class _FreshnessChip extends StatelessWidget {
  const _FreshnessChip({required this.freshness, required this.connected});
  final TileFreshness freshness;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final color = switch (freshness) {
      TileFreshness.fresh => Colors.green,
      TileFreshness.aging => Colors.yellow,
      TileFreshness.stale => Colors.orange,
      TileFreshness.uncached => connected ? Colors.red : Colors.grey,
    };
    final label = switch (freshness) {
      TileFreshness.fresh => 'Fresh',
      TileFreshness.aging => '15d+',
      TileFreshness.stale => '30d+',
      TileFreshness.uncached => connected ? 'No cache' : 'Offline',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.cardBackgroundDark,
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chart Plotter V3 failed to initialise',
              style: TextStyle(
                color: AppColors.alarmRed,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChartPlotterV3Builder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'chart_plotter_v3',
      name: 'Chart Plotter V3 (spike)',
      description:
          'Throwaway spike: OSM basemap via flutter_map + S-57 overlay '
          'rendered by s52_dart via Flutter CustomPainter. Proves the '
          'native-paint pipeline end-to-end.',
      category: ToolCategory.navigation,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
        styleOptions: const [],
        allowsUnitSelection: false,
        allowsVisibilityToggles: false,
        allowsTTL: false,
      ),
      defaultWidth: 6,
      defaultHeight: 6,
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: const [],
      style: StyleConfig(customProperties: const {}),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return ChartPlotterV3Tool(
      config: config,
      signalKService: signalKService,
    );
  }
}
