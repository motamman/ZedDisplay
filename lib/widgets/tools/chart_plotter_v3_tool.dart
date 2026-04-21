import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:s52_dart/s52_dart.dart';

import '../../config/app_colors.dart';
import '../../config/chart_constants.dart';
import '../../models/path_metadata.dart';
import '../../models/tool_config.dart';
import '../../models/tool_definition.dart';
import '../../services/chart_download_manager.dart';
import '../../services/chart_tile_cache_service.dart';
import '../../services/chart_tile_server_service.dart';
import '../../services/route_arrival_monitor.dart';
import '../../services/s57_tile_manager.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../ais_vessel_detail_sheet.dart';
import '../chart_plotter/chart_hud.dart';
import '../chart_plotter/chart_layer_panel.dart';
import '../chart_plotter/chart_route_panel.dart';
import '../countdown_confirmation_overlay.dart';

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
  S57TileManager? _tileManager;
  final _mapController = MapController();

  // Route state — mirrors V1's field set so ChartRouteState /
  // ChartRouteCallbacks plug in unchanged. `[lon, lat]` pairs match
  // SignalK's GeoJSON route geometry on the wire.
  String? _activeRouteHref;
  List<List<double>>? _routeCoords;
  List<String>? _waypointNames;
  int? _routePointIndex;
  int? _routePointTotal;
  bool _routeReversed = false;
  Timer? _routePollTimer;
  RouteArrivalMonitor? _arrivalMonitor;
  StreamSubscription<RouteArrivalEvent>? _arrivalSub;


  // Ruler state. Matches V1's model: two endpoints (red + blue) that
  // can each snap to the own vessel ('self') or an AIS vessel id, and
  // reposition automatically when their snap target moves.
  bool _rulerVisible = false;
  LatLng? _rulerRed;
  LatLng? _rulerBlue;
  String? _rulerRedSnap; // null | 'self' | vesselId
  String? _rulerBlueSnap;

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
  double? _ownSog; // m/s
  Timer? _vesselTimer;
  bool _autoFollow = true;
  int _lastVesselPushMs = 0;
  int _lastAisPushMs = 0;
  // Auto-zoom re-engages with auto-follow and disables on a user
  // pinch/scroll so the user can override without fighting us.
  bool _autoZoom = true;
  LatLng? _tapHalo;
  // Set in FlutterMap's onMapReady. Anything that touches
  // `_mapController.camera` / `.move()` must short-circuit until
  // this flips, otherwise MapController throws "You need to have
  // the FlutterMap widget rendered at least once".
  bool _mapReady = false;
  // 'north-up' keeps map north = screen top; 'heading-up' rotates
  // the map so the boat's bow is always screen-up. Matches V1's two
  // modes (chart_plotter_tool.dart:68).
  String _viewMode = 'north-up';

  // Vessel trail — sliding window of recent positions with timestamps
  // (epoch ms). V1 defaults to 10 minutes (chart_plotter_tool.dart:
  // 141-142) and reads the override from `customProperties.trailMinutes`.
  // Trail appends are throttled to 2 s with a 5 m movement threshold.
  final List<LatLng> _trailPoints = [];
  final List<int> _trailTimestamps = [];
  int _lastTrailPushMs = 0;
  int get _trailMinutes {
    final v = widget.config.style.customProperties?['trailMinutes'];
    if (v is num) return v.toInt();
    return 10;
  }

  /// S-57 object classes (e.g. `RESARE`, `SUBTLN`, `M_QUAL`) the user
  /// has chosen to hide via the configurator. Features with a matching
  /// `objectClass` are skipped in the painter so their geometry still
  /// parses and lives in the cache (for future re-enable) but nothing
  /// prints.
  Set<String> get _hiddenClasses {
    final raw = widget.config.style.customProperties?['hiddenClasses'];
    if (raw is List) {
      return raw.map((e) => e.toString()).toSet();
    }
    return const <String>{};
  }

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
    // V1 subscribes the chart plotter to the AIS vessels endpoint on
    // first connect. Without this the registry stays empty and no
    // traffic ever paints, even on a server broadcasting AIS.
    _ensureAisSubscribed();
  }

  bool _aisSubscribed = false;
  void _ensureAisSubscribed() {
    if (_aisSubscribed || !widget.signalKService.isConnected) return;
    _aisSubscribed = true;
    widget.signalKService.loadAndSubscribeAISVessels();
  }

  @override
  void dispose() {
    _routePollTimer?.cancel();
    _vesselTimer?.cancel();
    _stopArrivalMonitor();
    _tileManager?.removeListener(_onTileManagerChanged);
    _tileManager?.dispose();
    super.dispose();
  }

  void _onTileManagerChanged() {
    if (mounted) setState(() {});
  }

  /// Arrival monitor wiring matches V1 (chart_plotter_tool.dart:463-494).
  /// On each arrival, V1 pops a countdown confirmation: the last
  /// waypoint just reports; intermediate waypoints offer next-waypoint
  /// auto-advance.
  void _startArrivalMonitor() {
    _stopArrivalMonitor();
    _arrivalMonitor = RouteArrivalMonitor(signalKService: widget.signalKService);
    _arrivalSub = _arrivalMonitor!.arrivalStream.listen(_onWaypointArrival);
    _arrivalMonitor!.start();
  }

  void _stopArrivalMonitor() {
    _arrivalSub?.cancel();
    _arrivalSub = null;
    _arrivalMonitor?.dispose();
    _arrivalMonitor = null;
  }

  void _onWaypointArrival(RouteArrivalEvent event) {
    if (!mounted || _routeCoords == null) return;
    if (event.isLastWaypoint) {
      showCountdownConfirmation(
        context: context,
        title: 'Final Waypoint Reached',
        action: 'End Route',
      );
    } else {
      showCountdownConfirmation(
        context: context,
        title:
            'Waypoint ${event.pointIndex + 1}/${event.pointTotal} Reached',
        action: 'Next Waypoint',
      ).then((confirmed) {
        if (confirmed == true) _advanceWaypoint();
      });
    }
  }

  Future<void> _advanceWaypoint() async {
    final idx = _routePointIndex;
    final total = _routePointTotal;
    if (idx == null || total == null) return;
    final nextIdx = idx + 1;
    if (nextIdx >= total) return;
    try {
      await widget.signalKService.setActiveRoutePointIndex(nextIdx);
      await _pollCourseAPI();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Advance failed: $e')));
      }
    }
  }

  void _refreshVessel() {
    // Piggy-back on the tick to retry subscribe; initState can run
    // before the connection comes up, in which case the first call
    // is a no-op and this finally fires on a later tick.
    _ensureAisSubscribed();

    double? getNum(String path) {
      final d = widget.signalKService.getValue(path);
      return d?.value is num ? (d!.value as num).toDouble() : null;
    }

    final posData = widget.signalKService.getValue('navigation.position');
    double? lat, lon;
    if (posData?.value is Map) {
      final pos = posData!.value as Map;
      lat = (pos['latitude'] as num?)?.toDouble();
      lon = (pos['longitude'] as num?)?.toDouble();
    }
    final heading = getNum('navigation.headingTrue');
    final cog = getNum('navigation.courseOverGroundTrue');
    final sog = getNum('navigation.speedOverGround');

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // AIS refresh is independent of own-vessel presence: a receive-
    // only chartplotter (handheld with no GPS) still wants to see
    // traffic. Only own-vessel state is gated on a valid fix below.
    // Throttled to 1 s per V1 (chart_plotter_tool.dart:307-309).
    if (_aisEnabled && mounted && nowMs - _lastAisPushMs >= 1000) {
      _lastAisPushMs = nowMs;
      setState(() {
        _refreshAisVessels();
        _refreshRulerSnaps();
      });
    }

    if (lat == null || lon == null) return;
    final changed = lat != _ownLat ||
        lon != _ownLon ||
        heading != _ownHeading ||
        cog != _ownCog ||
        sog != _ownSog;
    if (!changed) return;
    // Throttle vessel state updates to V1's 500 ms cadence
    // (chart_plotter_tool.dart:297-299) so rapid WS deltas don't
    // cause setState-per-delta churn.
    if (nowMs - _lastVesselPushMs < 500) return;
    _lastVesselPushMs = nowMs;
    if (mounted) {
      setState(() {
        _ownLat = lat;
        _ownLon = lon;
        _ownHeading = heading;
        _ownCog = cog;
        _ownSog = sog;
        _appendTrailPoint(lat!, lon!);
        _refreshRulerSnaps();
      });
    }
    if (_mapReady) {
      // fitCamera handles centering when auto-zoom is on; only fall
      // back to a bare move when auto-zoom is disabled by the user.
      if (_autoFollow) {
        if (_autoZoom) {
          _applyAutoZoom();
        } else {
          _mapController.move(LatLng(lat, lon), _mapController.camera.zoom);
        }
      }
      if (_viewMode == 'heading-up' && heading != null) {
        final rotDeg = -heading * 180 / math.pi;
        if ((rotDeg - _mapController.camera.rotation).abs() > 0.5) {
          _mapController.rotate(rotDeg);
        }
      }
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
      final sog = v.sogMs ?? 0.0;
      final kind = _aisKindFor(v.navState, sog);
      out.add(_AisRenderable(
        id: v.vesselId,
        position: LatLng(lat, lon),
        // Freeboard rotates by heading when known, otherwise COG. Zero
        // is an acceptable fallback — the symbol stays upright.
        bearingRadians: v.headingTrueRad ?? v.cogRad ?? 0.0,
        name: v.name ?? '',
        color: _aisShipTypeColor(v.aisShipType, v.aisClass),
        alpha: _aisFreshnessAlpha(v.aisStatus, v.lastSeen),
        stale: _aisIsStale(v.aisStatus, v.lastSeen),
        kind: kind,
        projections: _aisShowPaths
            ? _projectAhead(lat, lon, v.cogRad, sog)
            : const [],
      ));
    }
    _aisVessels = out;
  }

  /// Ship-type / AIS-class palette — ported verbatim from V1's
  /// `shipTypeColor` in chart_webview.dart so the two plotters render
  /// the same traffic in the same colours.
  Color _aisShipTypeColor(int? type, String? aisClass) {
    if (type == null) {
      return aisClass == 'A' ? const Color(0xFFBDBDBD) : const Color(0xFF9E9E9E);
    }
    if (type == 36) return const Color(0xFF9C27B0); // sailing
    switch (type ~/ 10) {
      case 1:
      case 2:
        return const Color(0xFF00BCD4); // fishing, towing
      case 3:
        return const Color(0xFFFFC107); // special craft
      case 4:
      case 5:
        return const Color(0xFF009688); // HSC
      case 6:
        return const Color(0xFF2196F3); // passenger
      case 7:
        return const Color(0xFF388E3C); // cargo
      case 8:
        return const Color(0xFF795548); // tanker
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  double _aisFreshnessAlpha(String? status, DateTime? lastSeen) {
    if (status == 'confirmed') return 1.0;
    if (status == 'unconfirmed') return 0.5;
    if (status == 'lost' || status == 'remove') return 0.2;
    if (lastSeen == null) return 0.2;
    final ageMin = DateTime.now().difference(lastSeen).inSeconds / 60.0;
    if (ageMin < 3) return 1.0;
    if (ageMin < 10) return 0.7;
    return 0.3;
  }

  bool _aisIsStale(String? status, DateTime? lastSeen) {
    if (status == 'lost' || status == 'remove') return true;
    if (lastSeen == null) return true;
    return DateTime.now().difference(lastSeen).inMinutes >= 10;
  }

  _AisKind _aisKindFor(String? navState, double sogMs) {
    if (navState == 'moored') return _AisKind.moored;
    if (navState == 'anchored') return _AisKind.anchored;
    if (sogMs < 0.1) return _AisKind.slow;
    return _AisKind.moving;
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

  /// V1's trail rules, ported verbatim (chart_plotter_tool.dart:332-356):
  ///   • push throttle: 2 000 ms between samples
  ///   • movement threshold: <5 m (metres² < 25 via equirectangular)
  ///   • retention: trailMinutes (default 10)
  void _appendTrailPoint(double lat, double lon) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastTrailPushMs < 2000) return;
    if (_trailPoints.isNotEmpty) {
      final last = _trailPoints.last;
      final dx = (lon - last.longitude) *
          math.cos(lat * math.pi / 180) *
          111320;
      final dy = (lat - last.latitude) * 111320;
      if (dx * dx + dy * dy < 25) return; // <5m
    }
    _lastTrailPushMs = nowMs;
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
        final newReversed = activeRoute['reverse'] == true;
        final hrefChanged = href != null && href != _activeRouteHref;
        if (hrefChanged) {
          _activeRouteHref = href;
          await _fetchRoute(href);
          _startArrivalMonitor();
        }
        if (mounted) {
          setState(() {
            _routePointIndex = newIndex;
            _routePointTotal = newTotal;
            _routeReversed = newReversed;
          });
        }
      } else if (_activeRouteHref != null) {
        _stopArrivalMonitor();
        if (mounted) {
          setState(() {
            _activeRouteHref = null;
            _routeCoords = null;
            _waypointNames = null;
            _routePointIndex = null;
            _routePointTotal = null;
            _routeReversed = false;
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

  /// V1's tap routing priority (chart_webview.dart:1020-1138):
  ///   1. Waypoint (small — precise hit radius ~14 px)
  ///   2. AIS vessel (20 px — sprite target)
  ///   3. S-57 feature (30 px, grouped within 30 px, priority-sorted)
  /// Tap halo feedback is painted for 2 s regardless.
  void _onMapTap(TapPosition tapPosition, LatLng latLng) {
    _showTapHalo(latLng);

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
            ownSogMs: _ownSog,
          );
          return;
        }
      }
    }

    _showFeaturePopoverForTap(latLng, tapScreen);
  }

  /// 2-second yellow tap halo, parity with V1 (chart_webview.dart:1020-1032).
  void _showTapHalo(LatLng latLng) {
    setState(() => _tapHalo = latLng);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _tapHalo == latLng) {
        setState(() => _tapHalo = null);
      }
    });
  }

  /// Hit-test every parsed feature against the tap within a 30 px
  /// tolerance. Clickable layers are the same 31-entry list V1 uses
  /// (chart_webview.dart:1003-1015). Results are grouped by spatial
  /// proximity (30 px), each group sorted by display priority and
  /// geometry kind, then structures-before-equipment within the
  /// winning group.
  void _showFeaturePopoverForTap(LatLng tap, Offset tapScreen) {
    const hitRadiusPx = 30.0;
    const groupRadiusPx = 30.0;
    final camera = _mapController.camera;

    // Active-zoom-only hit-test. Cross-zoom retention keeps tiles at
    // z±1 in the cache as fallback fill for the painter, but tapping
    // should match what the user perceives as "the chart" — the active
    // layer on top. Iterating all retained tiles would surface every
    // feature 3× (one per retained zoom).
    final activeZ = camera.zoom.round().clamp(9, 16);
    final hits = <_TappedFeature>[];
    // Dedup signature → already-added flag. Same real-world feature can
    // appear in N adjacent tiles (MVT splits long lines / large polygons
    // at tile boundaries and re-emits the attributes per tile). Without
    // this we'd see N identical entries in the popover.
    final seenSig = <String>{};
    final tileMap = _tileManager?.tiles ?? const <S57TileKey, S57ParsedTile>{};
    for (final entry in tileMap.entries) {
      if (entry.key.z != activeZ) continue;
      for (final f in entry.value.features) {
        if (!_clickableLayers.contains(f.objectClass)) continue;
        // Closest point on the feature's actual geometry, not a
        // degenerate first-vertex / midpoint stand-in. Lets taps
        // anywhere along a contour line or inside a depth area
        // register against the right feature.
        final closest = _featureClosestPoint(f, tapScreen, camera);
        if (closest == null) continue;
        if ((closest - tapScreen).distanceSquared >
            hitRadiusPx * hitRadiusPx) {
          continue;
        }
        final sig = _featureSignature(f);
        if (!seenSig.add(sig)) continue;
        hits.add(_TappedFeature(
          layer: f.objectClass,
          properties: Map.of(f.attributes),
          screenPos: closest,
          displayPriority: f.displayPriority,
          kind: f.geometry.kind,
        ));
      }
    }
    if (hits.isEmpty) return;

    // Group features within `groupRadiusPx` of each other. Points only
    // — lines / areas get their own singleton groups because their
    // centroid is harder to compute and V1 doesn't group them either.
    final groups = <_TapGroup>[];
    for (final h in hits) {
      if (h.isPoint) {
        var merged = false;
        for (final g in groups) {
          if (!g.isPoint) continue;
          if ((h.screenPos - g.center).distanceSquared <=
              groupRadiusPx * groupRadiusPx) {
            g.members.add(h);
            if (h.displayPriority > g.maxPriority) {
              g.maxPriority = h.displayPriority;
            }
            merged = true;
            break;
          }
        }
        if (!merged) {
          groups.add(_TapGroup(
            center: h.screenPos,
            kind: h.kind,
            maxPriority: h.displayPriority,
            members: [h],
          ));
        }
      } else {
        groups.add(_TapGroup(
          center: h.screenPos,
          kind: h.kind,
          maxPriority: h.displayPriority,
          members: [h],
        ));
      }
    }

    // Winning group: geometry kind first (point > line > polygon),
    // priority within the same kind. Areas like RESARE have higher
    // S-52 displayPriority than buoys but cover the whole viewport, so
    // a priority-first sort lets the area swallow every tap that lands
    // anywhere inside it. Kind-first ensures the symbol the user
    // actually aimed at always wins over the background area context.
    groups.sort((a, b) {
      final ra = _kindRank(a.kind);
      final rb = _kindRank(b.kind);
      if (ra != rb) return ra.compareTo(rb);
      return b.maxPriority.compareTo(a.maxPriority);
    });
    final winner = groups.first;

    // Structures first, equipment after (LIGHTS/FOGSIG/TOPMAR etc. are
    // ancillary to the host buoy/beacon). chart_webview.dart:1115-1122.
    const equipment = {
      'LIGHTS',
      'FOGSIG',
      'TOPMAR',
      'RTPBCN',
      'RADSTA',
      'RDOSTA',
    };
    winner.members.sort((a, b) {
      final aEq = equipment.contains(a.layer) ? 1 : 0;
      final bEq = equipment.contains(b.layer) ? 1 : 0;
      if (aEq != bEq) return aEq.compareTo(bEq);
      return b.displayPriority.compareTo(a.displayPriority);
    });

    _showFeatureSheet(winner.members, tap);
  }

  /// Closest screen-space point on the feature's geometry to `tap`.
  /// Used both for hit-testing (compare distance to a radius) and as
  /// the popover group anchor. Returns null if the feature has no
  /// usable geometry.
  ///
  ///   * Point: nearest of the feature's points to the tap.
  ///   * Line: perpendicular foot on the nearest segment across all
  ///     polylines.
  ///   * Polygon: the tap itself when inside the outer ring (and not
  ///     in a hole) — distance zero. Otherwise the closest edge point.
  Offset? _featureClosestPoint(
      S57StyledFeature f, Offset tap, MapCamera camera) {
    final origin = camera.pixelOrigin;
    Offset project(LatLng p) => camera.projectAtZoom(p) - origin;
    switch (f.geometry.kind) {
      case S57GeomKind.point:
        Offset? best;
        var bestDist2 = double.infinity;
        for (final p in f.geometry.points) {
          final s = project(p);
          final d2 = (s - tap).distanceSquared;
          if (d2 < bestDist2) {
            bestDist2 = d2;
            best = s;
          }
        }
        return best;
      case S57GeomKind.line:
        Offset? best;
        var bestDist2 = double.infinity;
        for (final line in f.geometry.lines) {
          if (line.length < 2) continue;
          var prev = project(line.first);
          for (var i = 1; i < line.length; i++) {
            final curr = project(line[i]);
            final c = _closestPointOnSegment(tap, prev, curr);
            final d2 = (c - tap).distanceSquared;
            if (d2 < bestDist2) {
              bestDist2 = d2;
              best = c;
            }
            prev = curr;
          }
        }
        return best;
      case S57GeomKind.polygon:
        // Edge-proximity only — interior taps do NOT count as hits.
        // RESARE / regulation areas / large administrative polygons
        // cover most of the visible water; treating "inside polygon"
        // as a hit means every tap "hits" them and they crowd out
        // every symbol the user actually meant. Users who want area
        // info tap the visible boundary (or a contour line where the
        // area is bounded by one).
        Offset? best;
        var bestDist2 = double.infinity;
        for (final polygon in f.geometry.rings) {
          for (final ring in polygon) {
            if (ring.length < 2) continue;
            var prev = project(ring.first);
            for (var i = 1; i < ring.length; i++) {
              final curr = project(ring[i]);
              final c = _closestPointOnSegment(tap, prev, curr);
              final d2 = (c - tap).distanceSquared;
              if (d2 < bestDist2) {
                bestDist2 = d2;
                best = c;
              }
              prev = curr;
            }
          }
        }
        return best;
    }
  }

  static Offset _closestPointOnSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return a;
    var t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lenSq;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    return Offset(a.dx + t * dx, a.dy + t * dy);
  }

  /// Stable identity for a feature across tile boundaries: same
  /// real-world object emitted in N adjacent tiles always produces the
  /// same string. Built from objectClass plus the sorted attribute set,
  /// which is what the upstream MVT carries identically per tile copy.
  static String _featureSignature(S57StyledFeature f) {
    final parts = f.attributes.entries
        .where((e) => e.value != null)
        .map((e) => '${e.key}=${e.value}')
        .toList()
      ..sort();
    return '${f.objectClass}|${parts.join('|')}';
  }

  static int _kindRank(S57GeomKind k) {
    switch (k) {
      case S57GeomKind.point:
        return 0;
      case S57GeomKind.line:
        return 1;
      case S57GeomKind.polygon:
        return 2;
    }
  }

  void _showFeatureSheet(List<_TappedFeature> members, LatLng tap) {
    // Pass the PathMetadata objects straight down; the card uses
    // `metadata.format(...)` / `metadata.convert(...)` per CLAUDE.md's
    // SSOT rule. Falling back to raw SI + 'm' when no metadata is
    // registered for the category.
    final store = widget.signalKService.metadataStore;
    final depthMeta = store.getByCategory('depth');
    final heightMeta = store.getByCategory('height');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBackgroundDark,
      barrierColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      // Constrain to ~half the screen so the map above stays tappable
      // without the sheet trying to grow into it.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Material drag handle — Flutter wires its own
            // GestureDetector so swipe-down here flings the sheet to
            // dismiss directly.
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: 40,
                height: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.all(Radius.circular(2)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  const Icon(Icons.place, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${tap.latitude.toStringAsFixed(5)}, '
                      '${tap.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: members.length,
                itemBuilder: (_, i) => _FeatureCard(
                  member: members[i],
                  depth: depthMeta,
                  height: heightMeta,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Same 31-entry clickable layer set as V1 (chart_webview.dart:1004-1015).
  static const _clickableLayers = {
    'LIGHTS',
    'BOYLAT', 'BOYCAR', 'BOYISD', 'BOYSAW', 'BOYSPP',
    'BCNLAT', 'BCNCAR', 'BCNISD', 'BCNSAW', 'BCNSPP', 'TOPMAR',
    'RTPBCN', 'RDOSTA', 'RADSTA', 'FOGSIG', 'LITFLT', 'LITVES',
    'OBSTRN', 'UWTROC', 'WRECKS',
    'LNDMRK', 'SLCONS', 'BRIDGE', 'OFSPLF', 'PILBOP',
    'CRANES', 'GATCON', 'MORFAC', 'BERTHS', 'HRBFAC', 'SMCFAC',
    'CBLSUB', 'CBLOHD', 'PIPSOL', 'PIPOHD',
    'CGUSTA', 'RSCSTA', 'SISTAT', 'SISTAW',
    'DISMAR', 'CURENT', 'FSHFAC', 'CONVYR',
    'RESARE', 'ACHARE',
  };

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
      // Depth display unit + factor from the user's MetadataStore
      // preset (CLAUDE.md SSOT). Falls back to metres × 1.0 if no
      // depth metadata is registered yet (e.g. SignalK still
      // connecting). Reactive updates after first build aren't
      // wired — reload the chart to pick up a unit change.
      final depthMeta =
          widget.signalKService.metadataStore.getByCategory('depth');
      final engine = S52StyleEngine(
        lookups: lookups,
        options: S52Options(
          displayCategory: S52DisplayCategory.other,
          depthUnit: depthMeta?.symbol ?? 'm',
          depthConversionFactor: depthMeta?.convert(1.0) ?? 1.0,
        ),
        csProcedures: standardCsProcedures,
      );
      final manager = S57TileManager(
        engine: engine,
        urlBuilder: _buildTileUrl,
        freshnessProbe: _probeViewportFreshness,
      );
      manager.addListener(_onTileManagerChanged);
      setState(() {
        _engine = engine;
        _colorTable = colors;
        _spriteAtlas = sprites;
        _spriteImage = spriteImage;
        _tileManager = manager;
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

  /// URL builder for the tile manager. Prefers the local cached proxy
  /// (cache-first, background-refresh) when the shared tile server is
  /// running. Falls back to direct upstream otherwise — tests and dev
  /// environments don't always have the proxy wired.
  String _buildTileUrl(S57TileKey key) {
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

  TileFreshness _probeViewportFreshness(
      List<(int z, int x, int y)> viewportTiles) {
    return context
        .read<ChartTileCacheService>()
        .getViewportFreshness(viewportTiles);
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
              // Lock pan gestures while auto-follow is on — the map
              // stays glued to the vessel. Pinch/scroll zoom and
              // double-tap zoom remain enabled so the user can change
              // scale around the vessel without disengaging follow.
              // Tap the "snap to vessel" button to unlock.
              interactionOptions: InteractionOptions(
                flags: _autoFollow
                    ? InteractiveFlag.all &
                        ~(InteractiveFlag.drag |
                            InteractiveFlag.flingAnimation)
                    : InteractiveFlag.all,
              ),
              onMapEvent: (e) {
                // User pinch/scroll zoom kills auto-zoom but leaves
                // auto-follow intact (V1 chart_webview.dart:1271-1278).
                if (e.source == MapEventSource.scrollWheel ||
                    e.source == MapEventSource.doubleTap ||
                    e.source == MapEventSource.multiFingerGestureStart ||
                    e.source == MapEventSource.onMultiFinger) {
                  if (_autoZoom && mounted) {
                    setState(() => _autoZoom = false);
                  }
                }
                _tileManager?.scheduleRefresh(_mapController.camera);
              },
              onMapReady: () {
                _mapReady = true;
                // Center on vessel immediately if we already have a
                // fix from the 1 s vessel timer (which can run before
                // the map finishes initializing). Avoids the brief
                // flash of the hardcoded `_initialCenter` (LI Sound)
                // that the camera starts on.
                if (_ownLat != null && _ownLon != null) {
                  _mapController.move(
                    LatLng(_ownLat!, _ownLon!),
                    _mapController.camera.zoom,
                  );
                }
                _tileManager?.refreshNow(_mapController.camera);
              },
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
              if (s57Layer != null && _tileManager != null)
                Opacity(
                  opacity: s57Opacity,
                  child: _S57OverlayLayer(
                    tileCache: _tileManager!.tiles,
                    generation: _tileManager!.generation,
                    colorTable: _colorTable!,
                    spriteAtlas: _spriteAtlas!,
                    spriteImage: _spriteImage!,
                    hiddenClasses: _hiddenClasses,
                  ),
                ),
              if (_tapHalo != null)
                _TapHaloLayer(point: _tapHalo!),
              if (_trailPoints.length >= 2)
                _TrailOverlayLayer(
                  points: _trailPoints,
                  timestamps: _trailTimestamps,
                ),
              if (_rulerVisible &&
                  _rulerRed != null &&
                  _rulerBlue != null)
                _RulerLayer(
                  red: _rulerRed!,
                  blue: _rulerBlue!,
                  distance: _distanceMetadata(),
                ),
              if (_routeCoords != null)
                _RouteOverlayLayer(
                  coords: _routeCoords!,
                  activeIndex: _routePointIndex,
                  reversed: _routeReversed,
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
                  headingRad: _ownHeading,
                  cogRad: _ownCog,
                  sogMs: _ownSog,
                ),
              _MetadataScaleBar(distance: _distanceMetadata()),
              // DragMarkers must be the LAST FlutterMap child. Later
              // children sit on top in the Stack and get gesture
              // priority — otherwise the overlays above (route, AIS,
              // own-vessel, scale) swallow the hit test for the
              // ruler endpoints.
              if (_rulerVisible &&
                  _rulerRed != null &&
                  _rulerBlue != null)
                DragMarkers(
                  markers: [
                    DragMarker(
                      point: _rulerRed!,
                      size: const Size(44, 44),
                      rotateMarker: false,
                      onDragUpdate: (details, latLng) =>
                          _onRulerDrag('red', latLng),
                      builder: (_, _, _) => _rulerHandleVisual(
                        const Color(0xCCF44336),
                      ),
                    ),
                    DragMarker(
                      point: _rulerBlue!,
                      size: const Size(44, 44),
                      rotateMarker: false,
                      onDragUpdate: (details, latLng) =>
                          _onRulerDrag('blue', latLng),
                      builder: (_, _, _) => _rulerHandleVisual(
                        const Color(0xCC2196F3),
                      ),
                    ),
                  ],
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
              freshness:
                  _tileManager?.viewportFreshness ?? TileFreshness.uncached,
              connected: widget.signalKService.isConnected,
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: _MapControls(
              autoFollow: _autoFollow,
              headingUp: _viewMode == 'heading-up',
              rulerVisible: _rulerVisible,
              aisEnabled: _aisEnabled,
              aisActiveOnly: _aisActiveOnly,
              aisShowPaths: _aisShowPaths,
              onLayers: () => _showLayerSheet(context),
              onRoutes: () => _showRouteManager(context),
              onDownload: () => _showDownloadSheet(context),
              onToggleFollow: () {
                // V1 re-engages auto-zoom whenever auto-follow turns
                // back on (chart_webview.dart:1395).
                setState(() {
                  _autoFollow = !_autoFollow;
                  if (_autoFollow) _autoZoom = true;
                });
                if (_autoFollow &&
                    _mapReady &&
                    _ownLat != null &&
                    _ownLon != null) {
                  _mapController.move(
                    LatLng(_ownLat!, _ownLon!),
                    _mapController.camera.zoom,
                  );
                }
              },
              onToggleViewMode: _toggleViewMode,
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
          if (_rulerVisible && _rulerRed != null && _rulerBlue != null)
            Positioned(
              top: 8,
              left: 8,
              child: _RulerReadout(
                signalKService: widget.signalKService,
                a: _rulerRed!,
                b: _rulerBlue!,
              ),
            ),
          // V1 only shows the compass rose in heading-up mode (it's
          // redundant in north-up where the whole chart already points
          // north). Counter-rotates against the current heading so its
          // internal N arrow stays aligned with the rotated map frame.
          if (_viewMode == 'heading-up')
            Positioned(
              top: _rulerVisible ? 130 : 80,
              left: 8,
              child: Transform.rotate(
                angle: -(_ownHeading ?? 0.0),
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.6),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: CustomPaint(painter: _CompassRosePainter()),
                ),
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

  /// Flip between north-up and heading-up. In north-up we reset the
  /// map rotation to 0; heading-up applies the current heading on the
  /// next tick. Matches V1's one-shot behaviour (chart_plotter_tool.dart:
  /// 364-368).
  void _toggleViewMode() {
    setState(() {
      _viewMode = _viewMode == 'north-up' ? 'heading-up' : 'north-up';
    });
    if (_viewMode == 'north-up' && _mapReady) {
      _mapController.rotate(0);
    }
  }

  /// Toggle the ruler overlay. V1 seeds endpoints at `center ± 80px`
  /// in screen pixels (chart_webview.dart:1930-1932). We match that so
  /// the handles land where a user's thumbs would expect.
  void _toggleRuler() {
    setState(() {
      _rulerVisible = !_rulerVisible;
      if (!_rulerVisible) {
        _rulerRedSnap = null;
        _rulerBlueSnap = null;
        return;
      }
      if (_rulerRed == null || _rulerBlue == null) {
        final camera = _mapController.camera;
        final size = camera.size;
        final centerScreen = Offset(size.width / 2, size.height / 2);
        _rulerRed = camera.offsetToCrs(centerScreen - const Offset(80, 0));
        _rulerBlue = camera.offsetToCrs(centerScreen + const Offset(80, 0));
      }
    });
  }

  /// Pulled-out drag handler so snap logic can live alongside the
  /// endpoint update. Snap candidates: the own-vessel marker (20px)
  /// and any AIS vessel (20px) — matching V1's hitTolerance.
  void _onRulerDrag(String end, LatLng raw) {
    final camera = _mapController.camera;
    final rawScreen = camera.latLngToScreenOffset(raw);
    const snapRadiusSq = 20.0 * 20.0;
    LatLng snapped = raw;
    String? snapId;
    if (_ownLat != null && _ownLon != null) {
      final selfScreen =
          camera.latLngToScreenOffset(LatLng(_ownLat!, _ownLon!));
      if ((selfScreen - rawScreen).distanceSquared <= snapRadiusSq) {
        snapped = LatLng(_ownLat!, _ownLon!);
        snapId = 'self';
      }
    }
    if (snapId == null) {
      for (final v in _aisVessels) {
        final s = camera.latLngToScreenOffset(v.position);
        if ((s - rawScreen).distanceSquared <= snapRadiusSq) {
          snapped = v.position;
          snapId = v.id;
          break;
        }
      }
    }
    setState(() {
      if (end == 'red') {
        _rulerRed = snapped;
        _rulerRedSnap = snapId;
      } else {
        _rulerBlue = snapped;
        _rulerBlueSnap = snapId;
      }
    });
  }

  /// Reposition snapped ruler endpoints when their target vessel
  /// moves. Called from the vessel + AIS refresh paths.
  void _refreshRulerSnaps() {
    if (!_rulerVisible) return;
    LatLng? targetFor(String? id) {
      if (id == null) return null;
      if (id == 'self' && _ownLat != null && _ownLon != null) {
        return LatLng(_ownLat!, _ownLon!);
      }
      for (final v in _aisVessels) {
        if (v.id == id) return v.position;
      }
      return null;
    }

    final newRed = targetFor(_rulerRedSnap);
    final newBlue = targetFor(_rulerBlueSnap);
    if (newRed != null && newRed != _rulerRed) _rulerRed = newRed;
    if (newBlue != null && newBlue != _rulerBlue) _rulerBlue = newBlue;
  }

  /// Visual-only widget for the ruler endpoint. Matches V1's
  /// 12 px circle with a 2 px white stroke, centred in a 44 px hit
  /// box (the wider hit target is picked up by DragMarker's size).
  Widget _rulerHandleVisual(Color fill) {
    return Center(
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    );
  }

  /// Distance metadata (SI = metres). Consumers must use
  /// `metadata.convert(m)` and `metadata.convertToSI(display)` per
  /// the project's single-source-of-truth rule — no factor shortcuts,
  /// since they silently break for non-linear formulas (e.g. °K → °F).
  PathMetadata? _distanceMetadata() =>
      widget.signalKService.metadataStore.getByCategory('distance');

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

  /// Distance in metres from a point to the nearest land bounding box.
  /// Uses equirectangular approximation — good enough for a zoom
  /// heuristic at sub-degree scales.
  double _nearestLandMeters(double lat, double lon) {
    final landBounds = _tileManager?.landBounds;
    if (landBounds == null || landBounds.isEmpty) return double.infinity;
    final mPerDegLat = 111320.0;
    final mPerDegLon = 111320.0 * math.cos(lat * math.pi / 180);
    var best = double.infinity;
    for (final b in landBounds) {
      final dLat = math.max(
          0.0, math.max(b.south - lat, lat - b.north));
      final dLon = math.max(
          0.0, math.max(b.west - lon, lon - b.east));
      final dx = dLon * mPerDegLon;
      final dy = dLat * mPerDegLat;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d < best) best = d;
    }
    return best;
  }

  /// V1's auto-zoom policy (chart_webview.dart:1345-1371). Only kicks
  /// in when moving (>0.3 m/s) and auto-zoom is engaged. If land is
  /// within 15 min at current speed, tightens to `nearestLand * 1.3`;
  /// otherwise a 30-min look-ahead area. Camera fit clamped to 10..16.
  void _applyAutoZoom() {
    if (!_autoFollow || !_autoZoom || !_mapReady) return;
    final sog = _ownSog ?? 0.0;
    if (sog <= 0.3) return;
    final lat = _ownLat;
    final lon = _ownLon;
    if (lat == null || lon == null) return;

    double nearestLand = double.infinity;
    if (sog > 0.5) {
      nearestLand = _nearestLandMeters(lat, lon);
    }
    final landThreshold = sog * 900; // 15 min
    double bufferDist;
    if (nearestLand < landThreshold && nearestLand.isFinite) {
      bufferDist = math.max(nearestLand * 1.3, 300);
    } else {
      bufferDist = math.max(sog * 1800, 500);
    }

    // Convert metres to lat/lon deltas so we can build a LatLngBounds.
    final dLat = bufferDist / 111320.0;
    final dLon = bufferDist / (111320.0 * math.cos(lat * math.pi / 180));
    final bounds = LatLngBounds(
      LatLng(lat - dLat, lon - dLon),
      LatLng(lat + dLat, lon + dLon),
    );
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        maxZoom: 16,
        minZoom: 10,
      ),
    );
  }

}

class _S57OverlayLayer extends StatelessWidget {
  const _S57OverlayLayer({
    required this.tileCache,
    required this.generation,
    required this.colorTable,
    required this.spriteAtlas,
    required this.spriteImage,
    this.hiddenClasses = const <String>{},
  });
  final Map<S57TileKey, S57ParsedTile> tileCache;
  final int generation;
  final S52ColorTable colorTable;
  final SpriteAtlas spriteAtlas;
  final ui.Image spriteImage;
  final Set<String> hiddenClasses;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _S57Painter(
          camera: camera,
          tiles: tileCache,
          generation: generation,
          colorTable: colorTable,
          spriteAtlas: spriteAtlas,
          spriteImage: spriteImage,
          hiddenClasses: hiddenClasses,
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
    required this.generation,
    required this.colorTable,
    required this.spriteAtlas,
    required this.spriteImage,
    this.hiddenClasses = const <String>{},
  });
  final MapCamera camera;
  final Map<S57TileKey, S57ParsedTile> tiles;
  // Cache-mutation counter from the manager. Compared in shouldRepaint
  // because `tiles` is a stable reference (the manager mutates in
  // place), so reference comparison alone misses evictions.
  final int generation;
  final S52ColorTable colorTable;
  final SpriteAtlas spriteAtlas;
  final ui.Image spriteImage;
  // S-57 object classes the user has hidden via the configurator.
  // Features whose `objectClass` is in this set are skipped in the
  // draw pass — the geometry still lives in the parsed tile cache.
  final Set<String> hiddenClasses;

  @override
  void paint(Canvas canvas, Size size) {
    if (tiles.isEmpty) return;
    // Canonical flutter_map layer coordinate space: pixel positions
    // relative to `camera.pixelOrigin` (the top-left of the viewport
    // at the current zoom). `MobileLayerTransformer` handles rotation
    // around this painter, so we don't touch rotation here.
    final origin = camera.pixelOrigin;
    Offset project(LatLng p) => camera.projectAtZoom(p) - origin;

    // Cross-zoom fallback ordering: tiles farther from the active zoom
    // draw first (under), active-z tiles draw last (on top). Within the
    // same z-distance, lower-z (less detail) draws under higher-z.
    // This eliminates blank gaps during zoom transitions — adjacent-z
    // tiles fill in until the active-z fetch arrives.
    final activeZ = camera.zoom.round();
    final sorted = tiles.entries.toList()
      ..sort((a, b) {
        final da = (a.key.z - activeZ).abs();
        final db = (b.key.z - activeZ).abs();
        if (da != db) return db.compareTo(da);
        return a.key.z.compareTo(b.key.z);
      });

    // Three passes by geometry kind — polygons (area fills + patterns)
    // on the bottom, lines in the middle, points on top. This
    // approximates S-52's priority bands (group1 areas → line symbols
    // → point symbols) without needing per-feature priority data from
    // the engine. A finer-grained priority sort lives behind a later
    // task, once the lookup row's priority is threaded through.
    for (final kind in _paintOrder) {
      for (final entry in sorted) {
        for (final f in entry.value.features) {
          if (f.geometry.kind != kind) continue;
          if (hiddenClasses.contains(f.objectClass)) continue;
          _paintFeature(canvas, f, project);
        }
      }
    }
  }

  static const _paintOrder = [
    S57GeomKind.polygon,
    S57GeomKind.line,
    S57GeomKind.point,
  ];

  void _paintFeature(
      Canvas canvas, S57StyledFeature f, Offset Function(LatLng) project) {
    for (final instruction in f.instructions) {
      if (instruction is S52Symbol && f.geometry.kind == S57GeomKind.point) {
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
      } else if (instruction is S52LineStyle) {
        // S-52 uses LS() for both polyline geometries AND polygon
        // outlines (e.g. RESARE's dashed magenta border, EXEZNE's
        // patterned edge). Walk lines for line features, walk every
        // ring for polygon features. Point features fall through —
        // both collections are empty.
        final paint = Paint()
          ..color = _resolve(instruction.colorCode)
          ..strokeWidth = instruction.width.toDouble().clamp(1, 4)
          ..style = PaintingStyle.stroke;
        final dash = _dashIntervals(instruction.pattern);
        for (final line in f.geometry.lines) {
          final path = _linePath(line, project);
          canvas.drawPath(dash == null ? path : _dashPath(path, dash), paint);
        }
        for (final polygon in f.geometry.rings) {
          for (final ring in polygon) {
            final path = _linePath(ring, project);
            canvas.drawPath(dash == null ? path : _dashPath(path, dash), paint);
          }
        }
      } else if (instruction is S52LineComplex) {
        // Same logic for complex (sprite-stamped) lines on both line
        // and polygon outlines.
        _paintLineComplex(canvas, instruction.patternName, f, project);
      } else if (instruction is S52AreaColor &&
          f.geometry.kind == S57GeomKind.polygon) {
        // S-52 AC(CODE,TRANS): TRANS is a 0–4 transparency level.
        // 4 = fully transparent → skip the draw entirely.
        if (instruction.transparency >= 4) continue;
        final base = _resolve(instruction.colorCode);
        final paint = Paint()
          ..color = base.withAlpha(instruction.transparencyAlpha)
          ..style = PaintingStyle.fill;
        for (final polygon in f.geometry.rings) {
          canvas.drawPath(_polygonPath(polygon, project), paint);
        }
      } else if (instruction is S52AreaPattern &&
          f.geometry.kind == S57GeomKind.polygon) {
        _paintAreaPattern(canvas, instruction.patternName, f, project);
      } else if (instruction is S52TextLiteral &&
          f.geometry.kind == S57GeomKind.point) {
        // Computed labels from CS procedures — currently only SOUNDG02
        // depth soundings. Kept on the canvas because soundings are
        // core navigation info; everything else (object names,
        // formatted descriptions) is suppressed below to declutter.
        _paintText(canvas, instruction.text, f.geometry.points, project);
      }
      // Suppressed — attribute-driven labels (S52Text, e.g. OBJNAM
      // buoy/light names) and printf-formatted labels (S52TextFormatted)
      // overwhelm the canvas without OL-style decluttering. Tap a
      // feature to see these in the popover.
    }
  }

  /// Stamp a sprite repeatedly along the line's polylines, rotated to
  /// match each segment direction. S-52's LC() complex lines assume a
  /// tile spacing equal to the sprite's native width; we keep it
  /// simple and do the same. Uses `PathMetric.extractPath` to walk at
  /// fixed intervals with correct tangent direction per stamp.
  void _paintLineComplex(
    Canvas canvas,
    String patternName,
    S57StyledFeature f,
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

    void stampAlong(ui.Path path) {
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

    for (final line in f.geometry.lines) {
      stampAlong(_linePath(line, project));
    }
    // Polygon outlines: stamp around every ring (outer + holes). S-52
    // uses LC() on areas (e.g. NAVARE51 around fairways) the same way
    // it uses LC() on linear navarea boundaries.
    for (final polygon in f.geometry.rings) {
      for (final ring in polygon) {
        stampAlong(_linePath(ring, project));
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
    S57StyledFeature f,
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
      old.generation != generation ||
      old.colorTable != colorTable ||
      old.spriteAtlas != spriteAtlas ||
      old.spriteImage != spriteImage ||
      old.hiddenClasses.length != hiddenClasses.length ||
      !old.hiddenClasses.containsAll(hiddenClasses);
}

/// Paints the vessel's recent track. Matches V1's gradient-faded
/// 5-segment rendering (chart_webview.dart:1220-1249). Trail divides
/// into up to 5 equal-length segments; segment alpha ramps from 0.15
/// at the oldest to 0.8 at the newest. All segments are blue
/// `rgba(33,150,243,α)` stroked at width 2 with dash 6-4.
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
    final screen = points
        .map((p) => camera.projectAtZoom(p) - origin)
        .toList(growable: false);

    // V1 splits the polyline into `min(n-1, 5)` chunks. Each chunk's
    // alpha = 0.15 + 0.65 * (i / (segCount - 1)) → 0.15 … 0.8.
    final segCount = math.min(screen.length - 1, 5);
    final segLen = (screen.length / segCount).floor();
    for (var s = 0; s < segCount; s++) {
      final start = s * segLen;
      final end = s == segCount - 1 ? screen.length : (s + 1) * segLen + 1;
      if (end - start < 2) continue;
      final alpha = segCount == 1
          ? 0.8
          : 0.15 + 0.65 * (s / (segCount - 1));
      final path = ui.Path()..moveTo(screen[start].dx, screen[start].dy);
      for (var i = start + 1; i < end; i++) {
        path.lineTo(screen[i].dx, screen[i].dy);
      }
      canvas.drawPath(
        _dash(path, const [6, 4]),
        Paint()
          ..color = Color.fromRGBO(33, 150, 243, alpha)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  ui.Path _dash(ui.Path source, List<double> intervals) {
    final out = ui.Path();
    for (final metric in source.computeMetrics()) {
      double d = 0;
      var on = true;
      var i = 0;
      while (d < metric.length) {
        final next = d + intervals[i % intervals.length];
        if (on) {
          out.addPath(
            metric.extractPath(d, next.clamp(0, metric.length)),
            Offset.zero,
          );
        }
        d = next;
        on = !on;
        i++;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _TrailPainter old) =>
      old.camera != camera ||
      old.points.length != points.length ||
      (points.isNotEmpty && old.points.last != points.last);
}

/// Scale bar matching V1's OpenLayers `ScaleLine` configuration
/// (chart_webview.dart:992-998):
///   `{ units: 'nautical'|'metric'|'imperial', bar: true, steps: 4,
///      text: true, minWidth: 120 }`
///
/// That renders a 4-step checkered bar (alternating black/white
/// segments with tick separators), a "0" label at the left and the
/// total value+unit label at the right. Units come from
/// MetadataStore's `distance` category via `convertToSI`/`format`
/// per the SSOT rule — no factor multiplication.
class _MetadataScaleBar extends StatelessWidget {
  const _MetadataScaleBar({required this.distance});
  final PathMetadata? distance;

  // Candidate rounded display-unit totals. First segment has length
  // total/steps, so we pick totals that divide by 4 cleanly where
  // possible. V1's OL uses an internal table; this set covers the
  // same magnitudes for metric / nautical / imperial preferences.
  static const _niceTotals = <double>[
    0.001, 0.002, 0.004, 0.01, 0.02, 0.04, 0.1, 0.2, 0.4,
    1, 2, 4, 10, 20, 40, 100, 200, 400,
    1000, 2000, 4000,
  ];

  static const _steps = 4;
  static const _minWidth = 120.0; // matches OL's `minWidth: 120`

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final center = camera.center;
    const dist = Distance();
    // px-per-metre at current zoom via a 1 km east offset.
    final eastLatLng = dist.offset(center, 1000, 90);
    final pxPerMetre =
        (camera.projectAtZoom(eastLatLng).dx -
                camera.projectAtZoom(center).dx)
            .abs() /
            1000.0;
    if (pxPerMetre <= 0) return const SizedBox.shrink();

    double displayToMetres(double display) =>
        distance?.convertToSI(display) ?? display;

    // Smallest total whose pixel width is ≥ minWidth. V1 renders the
    // first candidate that clears minWidth; if none do (extremely
    // zoomed-in), fall back to the largest available.
    double chosenDisplay = _niceTotals.last;
    double chosenMetres = displayToMetres(chosenDisplay);
    for (final t in _niceTotals) {
      final m = displayToMetres(t);
      final px = m * pxPerMetre;
      if (px >= _minWidth) {
        chosenDisplay = t;
        chosenMetres = m;
        break;
      }
    }
    final barWidthPx = chosenMetres * pxPerMetre;
    if (!barWidthPx.isFinite || barWidthPx <= 0) {
      return const SizedBox.shrink();
    }

    final decimals = chosenDisplay < 0.01
        ? 3
        : chosenDisplay < 1
            ? 2
            : 0;
    final endLabel = distance?.format(chosenMetres, decimals: decimals) ??
        '${chosenMetres.toStringAsFixed(decimals)} m';

    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 64),
        child: CustomPaint(
          size: Size(barWidthPx + 40, 28),
          painter: _StepBarPainter(
            widthPx: barWidthPx,
            steps: _steps,
            endLabel: endLabel,
          ),
        ),
      ),
    );
  }
}

/// 4-step checkered scale bar. Alternating black + white rectangles
/// with black outline and tick separators; "0" label at the left
/// end, total+unit label at the right end. Labels have a dark
/// shadow so they read against any basemap colour.
class _StepBarPainter extends CustomPainter {
  _StepBarPainter({
    required this.widthPx,
    required this.steps,
    required this.endLabel,
  });
  final double widthPx;
  final int steps;
  final String endLabel;

  @override
  void paint(Canvas canvas, Size size) {
    const barHeight = 6.0;
    final barY = size.height - 14;
    final segW = widthPx / steps;

    final outlinePaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final blackFill = Paint()..color = Colors.black;
    final whiteFill = Paint()..color = Colors.white;

    // Alternating filled segments — segment 0 black, 1 white, 2 black, 3 white.
    for (var i = 0; i < steps; i++) {
      final rect = Rect.fromLTWH(i * segW, barY, segW, barHeight);
      canvas.drawRect(rect, i.isEven ? blackFill : whiteFill);
    }
    // Outline the full bar.
    canvas.drawRect(
      Rect.fromLTWH(0, barY, widthPx, barHeight),
      outlinePaint,
    );
    // Tick marks above the bar at each segment boundary (inclusive).
    for (var i = 0; i <= steps; i++) {
      final x = i * segW;
      canvas.drawLine(
        Offset(x, barY - 4),
        Offset(x, barY),
        outlinePaint,
      );
    }

    // "0" at the left, total label at the right — both sit above the
    // bar, centred on their endpoint tick.
    _drawLabel(canvas, '0', Offset(0, barY - 4));
    _drawLabel(canvas, endLabel, Offset(widthPx, barY - 4));
  }

  void _drawLabel(Canvas canvas, String text, Offset tickTop) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          shadows: [Shadow(color: Color(0xE6000000), blurRadius: 2)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        tickTop.dx - painter.width / 2,
        tickTop.dy - painter.height - 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _StepBarPainter old) =>
      old.widthPx != widthPx ||
      old.steps != steps ||
      old.endLabel != endLabel;
}

class _TappedFeature {
  _TappedFeature({
    required this.layer,
    required this.properties,
    required this.screenPos,
    required this.displayPriority,
    required this.kind,
  });
  final String layer;
  final Map<String, Object?> properties;
  final Offset screenPos;
  final int displayPriority;
  final S57GeomKind kind;
  bool get isPoint => kind == S57GeomKind.point;
}

class _TapGroup {
  _TapGroup({
    required this.center,
    required this.kind,
    required this.maxPriority,
    required this.members,
  });
  final Offset center;
  final S57GeomKind kind;
  int maxPriority;
  final List<_TappedFeature> members;
  bool get isPoint => kind == S57GeomKind.point;
}

/// Renders one grouped feature's attributes. All formatting rules
/// are ported from V1 (chart_webview.dart:2216-2331):
///   • Depth attrs (DEPTH/VALSOU/DRVAL1/DRVAL2/VALDCO) use depth
///     metadata factor/unit — convert raw metres to user preference.
///   • Height attrs (HEIGHT/VERLEN/HORLEN/HORWID) use height metadata.
///   • SIGPER shown as seconds ("Xs" — V1 convention).
///   • VALNMR shown in nautical miles ("X NM" — S-57 stores the
///     value in NM directly per IHO spec, so no conversion needed).
///   • CONRAD / CONVIS → "Yes" / "No".
///   • COLOUR / WATLEV / CATOBS / CATWRK / BOYSHP / BCNSHP / CATLAM /
///     CATCAM / CATLIT / LITCHR / CONDTN / STATUS / RESTRN / COLPAT /
///     TOPSHP / CATSPM are code-decoded via lookup tables.
///   • Attribute order matches V1's _displayOrder; unknown keys are
///     skipped the same way V1 does.
class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.member,
    required this.depth,
    required this.height,
  });
  final _TappedFeature member;
  final PathMetadata? depth;
  final PathMetadata? height;

  static const _depthKeys = {'DEPTH', 'VALSOU', 'DRVAL1', 'DRVAL2', 'VALDCO'};
  static const _heightKeys = {'HEIGHT', 'VERLEN', 'HORLEN', 'HORWID'};

  static const _displayOrder = [
    'OBJNAM', 'NOBJNM', 'INFORM', 'NINFOM',
    'DEPTH', 'VALSOU', 'DRVAL1', 'DRVAL2', 'VALDCO',
    'CATWRK', 'CATOBS', 'WATLEV',
    'CATLAM', 'CATCAM', 'CATSPM', 'BOYSHP', 'BCNSHP', 'TOPSHP',
    'COLOUR', 'COLPAT', 'LITCHR', 'CATLIT', 'SIGPER', 'VALNMR',
    'HEIGHT', 'RESTRN', 'CONDTN', 'STATUS', 'CONRAD', 'CONVIS',
    'VERLEN', 'HORLEN', 'HORWID',
  ];

  static const _attributeLabels = <String, String>{
    'OBJNAM': 'Name', 'NOBJNM': 'Local Name',
    'INFORM': 'Information', 'NINFOM': 'Note',
    'DEPTH': 'Depth', 'VALSOU': 'Depth',
    'DRVAL1': 'Min Depth', 'DRVAL2': 'Max Depth',
    'VALDCO': 'Contour Depth',
    'CATWRK': 'Type', 'CATOBS': 'Type', 'WATLEV': 'Water Level',
    'CATLAM': 'Lateral', 'CATCAM': 'Cardinal', 'CATSPM': 'Purpose',
    'BOYSHP': 'Shape', 'BCNSHP': 'Shape', 'TOPSHP': 'Top Mark',
    'COLOUR': 'Colour', 'COLPAT': 'Pattern',
    'LITCHR': 'Character', 'CATLIT': 'Category',
    'SIGPER': 'Period', 'VALNMR': 'Range',
    'HEIGHT': 'Height', 'RESTRN': 'Restriction',
    'CONDTN': 'Condition', 'STATUS': 'Status',
    'CONRAD': 'Radar Conspicuous', 'CONVIS': 'Visually Conspicuous',
    'VERLEN': 'Vertical Clearance',
    'HORLEN': 'Length', 'HORWID': 'Width',
  };

  static const _objectClassNames = <String, String>{
    'SOUNDG': 'Sounding', 'DEPCNT': 'Depth Contour', 'DEPARE': 'Depth Area',
    'DRGARE': 'Dredged Area', 'COALNE': 'Coastline', 'LNDARE': 'Land Area',
    'BUAARE': 'Built-up Area', 'LAKARE': 'Lake', 'RIVERS': 'River',
    'CANALS': 'Canal', 'SEAARE': 'Sea Area',
    'LIGHTS': 'Light', 'BOYLAT': 'Lateral Buoy',
    'BOYCAR': 'Cardinal Buoy', 'BOYSAW': 'Safe Water Buoy',
    'BOYSPP': 'Special Purpose Buoy', 'BOYISD': 'Isolated Danger Buoy',
    'BCNLAT': 'Lateral Beacon', 'BCNCAR': 'Cardinal Beacon',
    'BCNSPP': 'Special Purpose Beacon', 'BCNSAW': 'Safe Water Beacon',
    'BCNISD': 'Isolated Danger Beacon',
    'TOPMAR': 'Topmark', 'DAYMAR': 'Daymark',
    'FOGSIG': 'Fog Signal', 'RTPBCN': 'Radar Transponder',
    'RDOSTA': 'Radio Station', 'RADSTA': 'Radar Station',
    'LITFLT': 'Light Float', 'LITVES': 'Light Vessel',
    'WRECKS': 'Wreck', 'OBSTRN': 'Obstruction', 'UWTROC': 'Underwater Rock',
    'LNDMRK': 'Landmark', 'SLCONS': 'Shoreline Construction',
    'BRIDGE': 'Bridge', 'OFSPLF': 'Offshore Platform',
    'PILBOP': 'Pilot Boarding Place', 'CRANES': 'Crane',
    'MORFAC': 'Mooring Facility', 'BERTHS': 'Berth',
    'HRBFAC': 'Harbour Facility', 'SMCFAC': 'Small Craft Facility',
    'CBLSUB': 'Submarine Cable', 'CBLOHD': 'Overhead Cable',
    'PIPSOL': 'Submarine Pipeline', 'PIPOHD': 'Overhead Pipeline',
    'CGUSTA': 'Coast Guard Station', 'RSCSTA': 'Rescue Station',
    'SISTAT': 'Signal Station', 'SISTAW': 'Storm Signal Station',
    'DISMAR': 'Distance Mark', 'CURENT': 'Current',
    'FSHFAC': 'Fishing Facility', 'ACHARE': 'Anchorage Area',
    'RESARE': 'Restricted Area', 'FAIRWY': 'Fairway',
    'TSSLPT': 'TSS Lane', 'TSSBND': 'TSS Boundary',
    'NAVLNE': 'Navigation Line', 'RECTRC': 'Recommended Track',
    'GATCON': 'Gate', 'CONVYR': 'Conveyor',
    'PRDARE': 'Production Area', 'VEGATN': 'Vegetation',
    'LNDRGN': 'Land Region', 'DMPGRD': 'Dumping Ground',
    'CBLARE': 'Cable Area', 'SPLARE': 'Sea-plane Landing Area',
  };

  static const _decodeTables = <String, Map<String, String>>{
    'COLOUR': {'1': 'White', '2': 'Black', '3': 'Red', '4': 'Green', '5': 'Blue', '6': 'Yellow', '7': 'Grey', '8': 'Brown', '9': 'Amber', '10': 'Violet', '11': 'Orange', '12': 'Magenta', '13': 'Pink'},
    'WATLEV': {'1': 'Partly submerged', '2': 'Always dry', '3': 'Always under water', '4': 'Covers and uncovers', '5': 'Awash', '6': 'Subject to flooding', '7': 'Floating'},
    'CATOBS': {'1': 'Snag/stump', '2': 'Wellhead', '3': 'Diffuser', '4': 'Crib', '5': 'Fish haven', '6': 'Foul area', '7': 'Foul ground', '8': 'Ice boom', '9': 'Ground tackle', '10': 'Boom'},
    'CATWRK': {'1': 'Non-dangerous', '2': 'Dangerous', '3': 'Distributed remains', '4': 'Mast showing', '5': 'Hull showing'},
    'BOYSHP': {'1': 'Conical (nun)', '2': 'Can (cylindrical)', '3': 'Spherical', '4': 'Pillar', '5': 'Spar', '6': 'Barrel', '7': 'Super-buoy', '8': 'Ice buoy'},
    'BCNSHP': {'1': 'Stake/pole', '2': 'Withy', '3': 'Tower', '4': 'Lattice', '5': 'Pile', '6': 'Cairn', '7': 'Buoyant'},
    'CATLAM': {'1': 'Port', '2': 'Starboard', '3': 'Preferred channel starboard', '4': 'Preferred channel port'},
    'CATCAM': {'1': 'North', '2': 'East', '3': 'South', '4': 'West'},
    'CATLIT': {'1': 'Directional', '4': 'Leading', '5': 'Aero', '6': 'Air obstruction', '7': 'Fog detector', '8': 'Flood', '9': 'Strip', '10': 'Subsidiary', '11': 'Spotlight', '12': 'Front', '13': 'Rear', '14': 'Lower', '15': 'Upper'},
    'LITCHR': {'1': 'Fixed', '2': 'Flashing', '3': 'Long flashing', '4': 'Quick flashing', '5': 'Very quick flashing', '6': 'Ultra quick flashing', '7': 'Isophase', '8': 'Occulting', '9': 'Interrupted quick', '10': 'Interrupted very quick', '11': 'Morse code', '12': 'Fixed/flashing', '25': 'Quick + long flash', '26': 'VQ + long flash', '27': 'UQ + long flash', '28': 'Alternating', '29': 'Fixed & alternating flashing'},
    'CONDTN': {'1': 'Under construction', '2': 'Ruined', '3': 'Under reclamation', '5': 'Planned'},
    'STATUS': {'1': 'Permanent', '2': 'Occasional', '3': 'Recommended', '4': 'Not in use', '5': 'Intermittent', '6': 'Reserved', '7': 'Temporary', '8': 'Private', '9': 'Mandatory', '11': 'Extinguished', '12': 'Illuminated', '13': 'Historic', '14': 'Public', '15': 'Synchronized', '16': 'Watched', '17': 'Un-watched', '18': 'Doubtful'},
    'RESTRN': {'1': 'Anchoring prohibited', '2': 'Anchoring restricted', '3': 'Fishing prohibited', '4': 'Fishing restricted', '5': 'Trawling prohibited', '6': 'Trawling restricted', '7': 'Entry prohibited', '8': 'Entry restricted', '9': 'Dredging prohibited', '10': 'Dredging restricted', '11': 'Diving prohibited', '12': 'Diving restricted', '13': 'No wake', '14': 'Area to be avoided', '27': 'Speed restricted'},
    'COLPAT': {'1': 'Horizontal stripes', '2': 'Vertical stripes', '3': 'Diagonal stripes', '4': 'Squared', '5': 'Border stripes', '6': 'Single colour'},
    'TOPSHP': {'1': 'Cone point up', '2': 'Cone point down', '3': 'Sphere', '4': 'Two spheres', '5': 'Cylinder', '6': 'Board', '7': 'X-shape', '8': 'Upright cross', '9': 'Cube point up', '10': 'Two cones point-to-point', '11': 'Two cones base-to-base', '12': 'Rhombus', '13': 'Two cones point up', '14': 'Two cones point down', '33': 'Flag'},
    'CATSPM': {'1': 'Firing danger', '2': 'Target', '3': 'Marker ship', '4': 'Degaussing range', '5': 'Barge', '6': 'Cable', '7': 'Spoil ground', '8': 'Outfall', '9': 'ODAS', '10': 'Recording', '11': 'Seaplane anchorage', '12': 'Recreation zone', '13': 'Private', '14': 'Mooring', '15': 'LANBY', '16': 'Leading', '17': 'Measured distance', '18': 'Notice', '19': 'TSS', '20': 'No anchoring', '21': 'No berthing', '22': 'No overtaking', '23': 'No two-way traffic', '24': 'Reduced wake', '25': 'Speed limit', '26': 'Stop', '27': 'Warning', '28': 'Sound ship siren', '39': 'Environmental', '45': 'AIS', '51': 'No entry'},
  };

  String _format(String key, Object? val) {
    if (val == null) return '';
    final s = val.toString();
    if (s.isEmpty) return '';
    // Depth values arrive from S-57 in metres (SI). Use
    // `metadata.format()` so the user's configured unit + precision
    // wins, with the formula applied correctly (including any offset).
    if (_depthKeys.contains(key)) {
      final n = num.tryParse(s);
      if (n == null) return s;
      return depth?.format(n.toDouble(), decimals: 1) ??
          '${n.toStringAsFixed(1)} m';
    }
    if (_heightKeys.contains(key)) {
      final n = num.tryParse(s);
      if (n == null) return s;
      return height?.format(n.toDouble(), decimals: 1) ??
          '${n.toStringAsFixed(1)} m';
    }
    // V1 hardcodes these next two. SIGPER is a signal period in
    // seconds (no alt unit in the S-57 spec) and VALNMR is nominal
    // visibility range in nautical miles per IHO S-57. Matching V1.
    if (key == 'SIGPER') return '${s}s';
    if (key == 'VALNMR') return '$s NM';
    if (key == 'CONRAD' || key == 'CONVIS') return s == '1' ? 'Yes' : 'No';
    final table = _decodeTables[key];
    if (table != null) {
      final parts = s.split(',').map((p) => table[p.trim()] ?? p.trim());
      return parts.join(', ');
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final props = member.properties;
    final rows = <Widget>[
      Text(
        _objectClassNames[member.layer] ?? member.layer,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      const SizedBox(height: 6),
    ];
    for (final key in _displayOrder) {
      if (!props.containsKey(key)) continue;
      final display = _format(key, props[key]);
      if (display.isEmpty) continue;
      final label = _attributeLabels[key] ?? key;
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text(label,
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 13)),
            ),
            Expanded(
              child: Text(display,
                  style:
                      const TextStyle(color: Colors.white, fontSize: 13)),
            ),
          ],
        ),
      ));
    }
    return Card(
      color: const Color(0xFF2A2A3E),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        ),
      ),
    );
  }
}

class _TapHaloLayer extends StatelessWidget {
  const _TapHaloLayer({required this.point});
  final LatLng point;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _TapHaloPainter(camera: camera, point: point),
        size: Size.infinite,
      ),
    );
  }
}

class _TapHaloPainter extends CustomPainter {
  _TapHaloPainter({required this.camera, required this.point});
  final MapCamera camera;
  final LatLng point;

  @override
  void paint(Canvas canvas, Size size) {
    final c = camera.projectAtZoom(point) - camera.pixelOrigin;
    canvas.drawCircle(
      c,
      30,
      Paint()
        ..color = const Color(0x1AFFFF00)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      c,
      30,
      Paint()
        ..color = const Color(0xCCFFFF00)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _TapHaloPainter old) =>
      old.camera != camera || old.point != point;
}

/// Verbatim port of V1's `_CompassRosePainter`
/// (chart_plotter_tool.dart:1440-1482). Red north arrow + label,
/// faded south arrow, E/W cardinal tick marks.
class _CompassRosePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 4;

    final northPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    final northPath = ui.Path()
      ..moveTo(center.dx, center.dy - r)
      ..lineTo(center.dx - 5, center.dy - 2)
      ..lineTo(center.dx + 5, center.dy - 2)
      ..close();
    canvas.drawPath(northPath, northPaint);

    final southPaint = Paint()
      ..color = Colors.white54
      ..style = PaintingStyle.fill;
    final southPath = ui.Path()
      ..moveTo(center.dx, center.dy + r)
      ..lineTo(center.dx - 5, center.dy + 2)
      ..lineTo(center.dx + 5, center.dy + 2)
      ..close();
    canvas.drawPath(southPath, southPaint);

    final tickPaint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(center.dx + r, center.dy),
        Offset(center.dx + r - 6, center.dy), tickPaint);
    canvas.drawLine(Offset(center.dx - r, center.dy),
        Offset(center.dx - r + 6, center.dy), tickPaint);

    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'N',
        style: TextStyle(
          color: Colors.red,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - r + 10),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

enum _AisKind { moving, slow, moored, anchored }

/// Compact, painter-friendly snapshot of an AIS vessel. Only the
/// fields the painter actually reads are kept so the per-frame hot
/// loop stays cheap.
class _AisRenderable {
  const _AisRenderable({
    required this.id,
    required this.position,
    required this.bearingRadians,
    required this.name,
    required this.color,
    required this.alpha,
    required this.stale,
    required this.kind,
    required this.projections,
  });
  final String id;
  final LatLng position;
  final double bearingRadians;
  final String name;
  final Color color;
  final double alpha;
  final bool stale;
  final _AisKind kind;
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
          // V1 hides labels below zoom 13 where the map is too zoomed
          // out for names to be readable anyway; mirror that here.
          showNames: camera.zoom >= 13,
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
    required this.showNames,
  });
  final MapCamera camera;
  final List<_AisRenderable> vessels;
  final bool showPaths;
  final bool showNames;

  // V1's vessel-arrow SVG shape (0..16 × 0..24) re-centred to the
  // pivot at (8, 12) so rotation happens about the visual midpoint.
  // Path in SVG coords:
  //   M 8 1  L 2 19  L 5.5 16.5  L 8 21  L 10.5 16.5  L 14 19  Z
  // Translated by (-8, -12):
  static final _vesselPath = ui.Path()
    ..moveTo(0, -11)
    ..lineTo(-6, 7)
    ..lineTo(-2.5, 4.5)
    ..lineTo(0, 9)
    ..lineTo(2.5, 4.5)
    ..lineTo(6, 7)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final origin = camera.pixelOrigin;
    for (final v in vessels) {
      if (showPaths && v.projections.isNotEmpty) {
        _paintProjections(canvas, v, origin);
      }
      final center = camera.projectAtZoom(v.position) - origin;
      switch (v.kind) {
        case _AisKind.moving:
          _paintMoving(canvas, v, center);
          break;
        case _AisKind.slow:
          _paintSlow(canvas, v, center);
          break;
        case _AisKind.moored:
          _paintMoored(canvas, v, center);
          break;
        case _AisKind.anchored:
          _paintAnchored(canvas, v, center);
          break;
      }
      if (v.stale) _paintStaleX(canvas, center);
      if (showNames && v.name.isNotEmpty) {
        _paintName(canvas, v, center);
      }
    }
  }

  void _paintProjections(Canvas canvas, _AisRenderable v, Offset origin) {
    final start = camera.projectAtZoom(v.position) - origin;
    final dashPath = ui.Path()..moveTo(start.dx, start.dy);
    for (final p in v.projections) {
      final s = camera.projectAtZoom(p) - origin;
      dashPath.lineTo(s.dx, s.dy);
    }
    final dashed = _dashOne(dashPath, const [4, 4]);
    final lineColor = v.color.withValues(alpha: v.alpha * 0.6);
    canvas.drawPath(
      dashed,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Dot sizes match V1's [3, 4, 6, 8] for 30s, 1m, 15m, 30m.
    const dotR = [3.0, 4.0, 6.0, 8.0];
    final dotFill = Paint()..color = v.color.withValues(alpha: v.alpha * 0.7);
    final dotStroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (var i = 0; i < v.projections.length; i++) {
      final p = camera.projectAtZoom(v.projections[i]) - origin;
      final r = i < dotR.length ? dotR[i] : 4.0;
      canvas.drawCircle(p, r, dotFill);
      canvas.drawCircle(p, r, dotStroke);
    }
  }

  // Reuses the outer-painter dash helper's idea in one place.
  ui.Path _dashOne(ui.Path source, List<double> intervals) {
    final out = ui.Path();
    for (final metric in source.computeMetrics()) {
      double d = 0;
      var on = true;
      var i = 0;
      while (d < metric.length) {
        final span = intervals[i % intervals.length];
        final next = d + span;
        if (on) {
          out.addPath(
            metric.extractPath(d, next.clamp(0, metric.length)),
            Offset.zero,
          );
        }
        d = next;
        on = !on;
        i++;
      }
    }
    return out;
  }

  void _paintMoving(Canvas canvas, _AisRenderable v, Offset center) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(v.bearingRadians);
    // V1 applies a scale of 1.2 on the moving arrow for visibility.
    canvas.scale(1.2);
    canvas.drawPath(
      _vesselPath,
      Paint()..color = v.color.withValues(alpha: v.alpha),
    );
    canvas.drawPath(
      _vesselPath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    canvas.restore();
  }

  void _paintSlow(Canvas canvas, _AisRenderable v, Offset center) {
    // V1 renders stationary vessels as a 5-radius circle.
    canvas.drawCircle(
      center,
      5,
      Paint()..color = v.color.withValues(alpha: v.alpha),
    );
    canvas.drawCircle(
      center,
      5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _paintMoored(Canvas canvas, _AisRenderable v, Offset center) {
    // Mooring-buoy cue: filled disk with a horizontal blue band,
    // grey rim. Simplified from V1's SVG — same visual language.
    final disk = Paint()..color = v.color.withValues(alpha: v.alpha);
    final rim = Paint()
      ..color = const Color(0xFF666666)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final band = Paint()..color = const Color(0xFF1565C0);
    const r = 7.0;
    canvas.drawCircle(center, r, disk);
    canvas.save();
    canvas.clipPath(ui.Path()..addOval(Rect.fromCircle(center: center, radius: r)));
    canvas.drawRect(
      Rect.fromLTWH(center.dx - r, center.dy - r * 0.24, r * 2, r * 0.48),
      band,
    );
    canvas.restore();
    canvas.drawCircle(center, r, rim);
  }

  void _paintAnchored(Canvas canvas, _AisRenderable v, Offset center) {
    // V1 renders the Material Design anchor glyph sized 20×20 in the
    // ship-type colour (chart_webview.dart:1173-1181, comment says
    // "same as Icons.anchor in Flutter"). Use the icon font directly
    // so we match the exact glyph without shipping a sprite.
    final icon = Icons.anchor;
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 20,
          color: v.color.withValues(alpha: v.alpha),
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  void _paintStaleX(Canvas canvas, Offset center) {
    final paint = Paint()
      ..color = const Color(0xCCFF0000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const r = 7.0;
    canvas.drawLine(
      center.translate(-r, -r),
      center.translate(r, r),
      paint,
    );
    canvas.drawLine(
      center.translate(-r, r),
      center.translate(r, -r),
      paint,
    );
  }

  void _paintName(Canvas canvas, _AisRenderable v, Offset center) {
    final painter = TextPainter(
      text: TextSpan(
        text: v.name,
        style: TextStyle(
          color: v.color.withValues(alpha: math.max(v.alpha, 0.8)),
          fontSize: 11,
          fontWeight: FontWeight.w500,
          shadows: const [
            Shadow(color: Color(0x80000000), blurRadius: 2),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - 18 - painter.height),
    );
  }

  @override
  bool shouldRepaint(covariant _AisPainter old) =>
      old.camera != camera ||
      old.vessels != vessels ||
      old.showPaths != showPaths ||
      old.showNames != showNames;
}


/// Full-fidelity ruler renderer. Matches V1's on-map output:
///   • Dashed red half-line (red → midpoint), `rgba(244,67,54,0.7)` w3 dash 8-4
///   • Dashed blue half-line (midpoint → blue), `rgba(33,150,243,0.7)`
///   • Perpendicular tick marks at "nice" intervals (3-10 per ruler)
///   • Red bearing label at red endpoint (red→blue angle, offsetY -18)
///   • Blue bearing label at blue endpoint (blue→red angle)
///   • White distance label at midpoint (offsetY +16) with unit symbol
class _RulerLayer extends StatelessWidget {
  const _RulerLayer({
    required this.red,
    required this.blue,
    required this.distance,
  });
  final LatLng red;
  final LatLng blue;
  final PathMetadata? distance;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _RulerPainter(
          camera: camera,
          red: red,
          blue: blue,
          distance: distance,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.camera,
    required this.red,
    required this.blue,
    required this.distance,
  });
  final MapCamera camera;
  final LatLng red;
  final LatLng blue;
  final PathMetadata? distance;

  // "Nice" display-unit step table. Mirrors chart_webview.dart:1814.
  static const _niceCandidates = [
    0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5,
    1.0, 2.0, 5.0, 10.0, 25.0, 50.0, 100.0, 250.0, 500.0,
  ];

  double _niceInterval(double totalDisplay) {
    for (final c in _niceCandidates) {
      final ticks = totalDisplay / c;
      if (ticks >= 3 && ticks <= 10) return c;
    }
    return totalDisplay / 5;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final origin = camera.pixelOrigin;
    final pRed = camera.projectAtZoom(red) - origin;
    final pBlue = camera.projectAtZoom(blue) - origin;
    final mid = Offset(
      (pRed.dx + pBlue.dx) / 2,
      (pRed.dy + pBlue.dy) / 2,
    );

    // Half-lines (dashed). V1 uses lineDash [8, 4] on stroke 3.
    const redLineColor = Color(0xB3F44336); // alpha 0.7
    const blueLineColor = Color(0xB32196F3);
    final redPath = ui.Path()
      ..moveTo(pRed.dx, pRed.dy)
      ..lineTo(mid.dx, mid.dy);
    final bluePath = ui.Path()
      ..moveTo(mid.dx, mid.dy)
      ..lineTo(pBlue.dx, pBlue.dy);
    final dashed = [8.0, 4.0];
    canvas.drawPath(
      _dashPath(redPath, dashed),
      Paint()
        ..color = redLineColor
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      _dashPath(bluePath, dashed),
      Paint()
        ..color = blueLineColor
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );

    // Distance + bearings in WGS84 via haversine / great circle.
    final distM = _haversine(red, blue);
    final bearingRB = _bearing(red, blue);
    final bearingBR = _bearing(blue, red);
    // Display value via MetadataStore.convert — never assume a linear
    // factor, because formulas may include offsets.
    final distDisplay = distance?.convert(distM) ?? distM;

    // Tick marks — perpendicular 16px (8 each side), up to 20 ticks.
    final dx = pBlue.dx - pRed.dx;
    final dy = pBlue.dy - pRed.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len > 0 && distDisplay > 0) {
      final dirX = dx / len;
      final dirY = dy / len;
      final perpX = -dirY;
      final perpY = dirX;
      const tickHalf = 8.0;
      final interval = _niceInterval(distDisplay);
      final tickCount = (distDisplay / interval).floor();
      final blackPaint = Paint()
        ..color = const Color(0x99000000)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      final whitePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      for (var i = 1; i <= tickCount && i <= 20; i++) {
        final frac = (interval * i) / distDisplay;
        if (frac >= 1) break;
        final tx = pRed.dx + dx * frac;
        final ty = pRed.dy + dy * frac;
        final from = Offset(tx + perpX * tickHalf, ty + perpY * tickHalf);
        final to = Offset(tx - perpX * tickHalf, ty - perpY * tickHalf);
        canvas.drawLine(from, to, blackPaint);
        canvas.drawLine(from, to, whitePaint);
      }
    }

    // Bearing labels at endpoints, offsetY -18 (above the marker).
    final bearingStyle = const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      shadows: [Shadow(color: Color(0xCC000000), blurRadius: 3)],
    );
    _drawLabel(
      canvas,
      pRed.translate(0, -18),
      '${bearingRB.toStringAsFixed(1)}°',
      bearingStyle.copyWith(color: const Color(0xFFF44336)),
    );
    _drawLabel(
      canvas,
      pBlue.translate(0, -18),
      '${bearingBR.toStringAsFixed(1)}°',
      bearingStyle.copyWith(color: const Color(0xFF2196F3)),
    );

    // Distance label at midpoint, offsetY +16 (below the centre).
    // Precision varies with magnitude (V1 chart_webview.dart:1873).
    final decimals = distDisplay < 1 ? 3 : (distDisplay < 10 ? 2 : 1);
    final distLabel = distance?.format(distM, decimals: decimals) ??
        '${distM.toStringAsFixed(decimals)} m';
    _drawLabel(
      canvas,
      mid.translate(0, 16),
      distLabel,
      const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        shadows: [Shadow(color: Color(0xCC000000), blurRadius: 3)],
      ),
    );
  }

  void _drawLabel(Canvas canvas, Offset anchor, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(
      canvas,
      Offset(anchor.dx - painter.width / 2, anchor.dy - painter.height / 2),
    );
  }

  ui.Path _dashPath(ui.Path source, List<double> intervals) {
    final out = ui.Path();
    for (final metric in source.computeMetrics()) {
      double d = 0;
      var on = true;
      var i = 0;
      while (d < metric.length) {
        final next = d + intervals[i % intervals.length];
        if (on) {
          out.addPath(
            metric.extractPath(d, next.clamp(0, metric.length)),
            Offset.zero,
          );
        }
        d = next;
        on = !on;
        i++;
      }
    }
    return out;
  }

  double _haversine(LatLng a, LatLng b) {
    const r = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(h)));
  }

  double _bearing(LatLng from, LatLng to) {
    final la1 = from.latitude * math.pi / 180;
    final la2 = to.latitude * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(la2);
    final x = math.cos(la1) * math.sin(la2) -
        math.sin(la1) * math.cos(la2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.camera != camera ||
      old.red != red ||
      old.blue != blue ||
      old.distance != distance;
}

/// Ruler info panel — matches V1's top-left overlay
/// (chart_plotter_tool.dart:1311-1360). Layout: red painted dot +
/// bearing Red→Blue on row one, blue dot + Blue→Red on row two,
/// distance with unit symbol on row three (bold 15 px). Distance
/// precision: <1 → 3 decimals, <10 → 2 decimals, else 1 decimal.
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
    final distM = _haversine(a, b);
    final bearingRed = _bearing(a, b); // red → blue
    final bearingBlue = _bearing(b, a); // blue → red
    final distMeta =
        signalKService.metadataStore.getByCategory('distance');
    final dist = distMeta?.convert(distM) ?? distM;
    final distSym = distMeta?.symbol ?? 'm';
    final distStr = dist < 1
        ? dist.toStringAsFixed(3)
        : (dist < 10 ? dist.toStringAsFixed(2) : dist.toStringAsFixed(1));

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
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${bearingRed.toStringAsFixed(1)}°',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ]),
          const SizedBox(height: 2),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${bearingBlue.toStringAsFixed(1)}°',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            '$distStr $distSym',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  double _haversine(LatLng a, LatLng b) {
    const r = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(h)));
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

/// Paints the own vessel. Matches V1's composition (chart_webview.dart:
/// 1285-1324): solid-blue heading line out 800 m, dashed-orange COG
/// vector sized to a 3-minute projection, and the chevron marker at
/// `#2196f3` × 0.9 alpha with a white outline, scaled 1.6×.
class _OwnVesselLayer extends StatelessWidget {
  const _OwnVesselLayer({
    required this.lat,
    required this.lon,
    required this.headingRad,
    required this.cogRad,
    required this.sogMs,
  });
  final double lat;
  final double lon;
  final double? headingRad;
  final double? cogRad;
  final double? sogMs;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _OwnVesselPainter(
          camera: camera,
          position: LatLng(lat, lon),
          headingRad: headingRad,
          cogRad: cogRad,
          sogMs: sogMs,
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
    required this.headingRad,
    required this.cogRad,
    required this.sogMs,
  });
  final MapCamera camera;
  final LatLng position;
  final double? headingRad;
  final double? cogRad;
  final double? sogMs;

  // Exact SVG path from V1's `vesselSvgSrc` (chart_webview.dart:1152),
  // recentred to (0,0) so rotate/scale pivot about the chevron midpoint.
  //   Source: M 8 1 L 2 19 L 5.5 16.5 L 8 21 L 10.5 16.5 L 14 19 Z
  //   (translated by -8, -12 → in painter-local space)
  static final _chevronPath = ui.Path()
    ..moveTo(0, -11)
    ..lineTo(-6, 7)
    ..lineTo(-2.5, 4.5)
    ..lineTo(0, 9)
    ..lineTo(2.5, 4.5)
    ..lineTo(6, 7)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final origin = camera.pixelOrigin;
    final center = camera.projectAtZoom(position) - origin;

    // Heading line — solid blue, great-circle forward-projected 800 m.
    if (headingRad != null) {
      final end = _forward(position, headingRad!, 800);
      final pe = camera.projectAtZoom(end) - origin;
      canvas.drawLine(
        center,
        pe,
        Paint()
          ..color = const Color(0xB32196F3) // 0.7 alpha
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }

    // COG vector — dashed orange, length = max(sog*180, 200) m so
    // the arrow reaches a 3-minute lookahead or stays visible at rest.
    if (cogRad != null && sogMs != null && sogMs! > 0.1) {
      final len = math.max(sogMs! * 180.0, 200.0);
      final end = _forward(position, cogRad!, len);
      final pe = camera.projectAtZoom(end) - origin;
      final path = ui.Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(pe.dx, pe.dy);
      canvas.drawPath(
        _dashed(path, const [8, 4]),
        Paint()
          ..color = const Color(0xCCFF9800) // 0.8 alpha
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }

    // Chevron marker — blue fill, white outline, scale 1.6× like V1.
    final rotation = headingRad ?? cogRad ?? 0.0;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.scale(1.6);
    canvas.drawPath(
      _chevronPath,
      Paint()..color = const Color(0xE62196F3), // 0.9 alpha
    );
    canvas.drawPath(
      _chevronPath,
      Paint()
        ..color = const Color(0xE6FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    canvas.restore();
  }

  /// Great-circle forward projection — lat/lon + bearing (rad) + distance (m)
  /// → new lat/lon. Same maths the AIS painter uses.
  LatLng _forward(LatLng start, double bearingRad, double distM) {
    final lat1 = start.latitude * math.pi / 180;
    final lon1 = start.longitude * math.pi / 180;
    final a = distM / 6371000.0;
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(a) +
          math.cos(lat1) * math.sin(a) * math.cos(bearingRad),
    );
    final lon2 = lon1 +
        math.atan2(
          math.sin(bearingRad) * math.sin(a) * math.cos(lat1),
          math.cos(a) - math.sin(lat1) * math.sin(lat2),
        );
    return LatLng(lat2 * 180 / math.pi, lon2 * 180 / math.pi);
  }

  ui.Path _dashed(ui.Path source, List<double> intervals) {
    final out = ui.Path();
    for (final metric in source.computeMetrics()) {
      double d = 0;
      var on = true;
      var i = 0;
      while (d < metric.length) {
        final next = d + intervals[i % intervals.length];
        if (on) {
          out.addPath(
            metric.extractPath(d, next.clamp(0, metric.length)),
            Offset.zero,
          );
        }
        d = next;
        on = !on;
        i++;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _OwnVesselPainter old) =>
      old.camera != camera ||
      old.position != position ||
      old.headingRad != headingRad ||
      old.cogRad != cogRad ||
      old.sogMs != sogMs;
}

/// Paints the active route in V1's colours + shapes (chart_webview.dart:
/// 1546-1613). Base polyline green at 0.6 alpha width 3; a bright
/// active-leg overlay (prev → next waypoint) at 0.95 alpha width 5;
/// triangular waypoint markers pointing along the route direction,
/// sized 12 for the next waypoint and 7 otherwise, with alpha rules
/// 0.3 past / 0.95 next / 0.7 future. Only the next waypoint gets a
/// white outline. `reversed` inverts what counts as past vs future.
class _RouteOverlayLayer extends StatelessWidget {
  const _RouteOverlayLayer({
    required this.coords,
    required this.activeIndex,
    required this.reversed,
  });
  final List<List<double>> coords;
  final int? activeIndex;
  final bool reversed;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _RoutePainter(
          camera: camera,
          coords: coords,
          activeIndex: activeIndex,
          reversed: reversed,
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
    required this.reversed,
  });
  final MapCamera camera;
  final List<List<double>> coords;
  final int? activeIndex;
  final bool reversed;

  @override
  void paint(Canvas canvas, Size size) {
    if (coords.length < 2) return;
    final origin = camera.pixelOrigin;
    Offset project(List<double> lonLat) =>
        camera.projectAtZoom(LatLng(lonLat[1], lonLat[0])) - origin;

    final points =
        coords.map(project).toList(growable: false);

    // Base polyline — faded green.
    final basePath = ui.Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 1; i < points.length; i++) {
      basePath.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(
      basePath,
      Paint()
        ..color = const Color(0x994CAF50) // 0.6 alpha
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );

    // Active leg overlay (prev → active waypoint). Direction-aware so
    // reversed routes highlight the correct segment.
    final ai = activeIndex;
    if (ai != null) {
      final prevIdx = reversed ? ai + 1 : ai - 1;
      if (prevIdx >= 0 &&
          prevIdx < points.length &&
          ai >= 0 &&
          ai < points.length) {
        canvas.drawLine(
          points[prevIdx],
          points[ai],
          Paint()
            ..color = const Color(0xF24CAF50) // 0.95 alpha
            ..strokeWidth = 5
            ..style = PaintingStyle.stroke,
        );
      }
    }

    // Waypoint triangles — direction by next leg (or previous in reverse).
    for (var i = 0; i < points.length; i++) {
      final isNext = i == ai;
      final isPast = ai != null && (reversed ? i > ai : i < ai);
      final size = isNext ? 12.0 : 7.0;
      final alpha = isPast ? 0.3 : (isNext ? 0.95 : 0.7);
      // Rotation = atan2(dx, dy) of the next-step vector. dy is
      // world-up in screen coords here (flutter_map projects y-down),
      // but V1's OpenLayers uses the same convention relative to the
      // camera transform applied by MobileLayerTransformer, so the
      // same formula reproduces the pointing angle.
      int toIdx;
      if (reversed) {
        toIdx = i > 0 ? i - 1 : i;
      } else {
        toIdx = i < points.length - 1 ? i + 1 : i;
      }
      final dx = points[toIdx].dx - points[i].dx;
      final dy = points[toIdx].dy - points[i].dy;
      final rot = (dx == 0 && dy == 0) ? 0.0 : math.atan2(dx, -dy);
      final path = _triangle(size);
      canvas.save();
      canvas.translate(points[i].dx, points[i].dy);
      canvas.rotate(rot);
      canvas.drawPath(
        path,
        Paint()
          ..color =
              Color.fromRGBO(76, 175, 80, alpha), // rgba(76,175,80,alpha)
      );
      if (isNext) {
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
      }
      canvas.restore();
    }
  }

  /// Equilateral triangle pointing up (bow along +y is toward the
  /// next waypoint before rotation; V1 uses OpenLayers RegularShape
  /// with points=3 which is the same equilateral).
  ui.Path _triangle(double radius) {
    final path = ui.Path();
    for (var i = 0; i < 3; i++) {
      final theta = -math.pi / 2 + i * 2 * math.pi / 3;
      final x = radius * math.cos(theta);
      final y = radius * math.sin(theta);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) =>
      old.camera != camera ||
      old.coords != coords ||
      old.activeIndex != activeIndex ||
      old.reversed != reversed;
}

class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.autoFollow,
    required this.headingUp,
    required this.rulerVisible,
    required this.aisEnabled,
    required this.aisActiveOnly,
    required this.aisShowPaths,
    required this.onLayers,
    required this.onRoutes,
    required this.onDownload,
    required this.onToggleFollow,
    required this.onToggleViewMode,
    required this.onToggleRuler,
    required this.onToggleAis,
    required this.onToggleAisActive,
    required this.onToggleAisPaths,
  });
  final bool autoFollow;
  final bool headingUp;
  final bool rulerVisible;
  final bool aisEnabled;
  final bool aisActiveOnly;
  final bool aisShowPaths;
  final VoidCallback onLayers;
  final VoidCallback onRoutes;
  final VoidCallback onDownload;
  final VoidCallback onToggleFollow;
  final VoidCallback onToggleViewMode;
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
              headingUp ? Icons.navigation : Icons.navigation_outlined,
              color: Colors.white,
              size: 20,
            ),
            tooltip: headingUp ? 'Heading-up' : 'North-up',
            onPressed: onToggleViewMode,
          ),
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
              'Chart Plotter failed to initialise',
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
      name: 'Chart Plotter',
      description:
          'Interactive chart plotter with S-57 charts, AIS, route, and '
          'nav data. Native-paint pipeline: OSM basemap via flutter_map '
          'plus S-57 overlay rendered by s52_dart through a Flutter '
          'CustomPainter.',
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
        // No SignalK paths to configure — the chart plotter pulls its
        // own-vessel and route data from fixed well-known paths via
        // SignalKService. Hides the "Configure Data Sources" section in
        // the config screen.
        allowsDataSources: false,
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
