import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../models/tool_config.dart';
import '../../models/tool_definition.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../services/route_arrival_monitor.dart';
import '../../models/ais_favorite.dart';
import '../../services/ais_favorites_service.dart';
import '../../services/dashboard_service.dart';
import '../../services/find_home_target_service.dart';
import '../../utils/cpa_utils.dart';
import '../../widgets/countdown_confirmation_overlay.dart';
import '../../services/chart_tile_cache_service.dart';
import '../../services/chart_tile_server_service.dart';
import '../../services/chart_download_manager.dart';
import '../../services/tool_service.dart';
import 'chart_webview.dart';

/// Chart Plotter — OpenLayers-based unified navigation chart.
class ChartPlotterTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const ChartPlotterTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<ChartPlotterTool> createState() => _ChartPlotterToolState();
}

class _ChartPlotterToolState extends State<ChartPlotterTool>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static const _ownerId = 'chart_plotter';

  // DataSource indices — matches getDefaultConfig() order
  static const _dsPosition = 0;
  static const _dsHeading = 1;
  static const _dsCog = 2;
  static const _dsSog = 3;
  static const _dsDepth = 4;
  static const _dsBearing = 5;
  static const _dsXte = 6;
  static const _dsDtw = 7;
  // ignore: unused_field
  static const _dsActiveRoute = 8; // subscribed; read via REST
  // ignore: unused_field
  static const _dsNextPoint = 9; // subscribed; read via REST

  WebViewController? _controller;
  bool _mapReady = false;
  bool _autoFollow = true;
  String _viewMode = 'north-up';
  DateTime _lastVesselPush = DateTime(0);
  DateTime _lastAISPush = DateTime(0);
  bool _hasLoadedAIS = false;

  // AIS controls
  bool _aisEnabled = true;
  bool _aisActiveOnly = false;
  bool _aisShowPaths = true;

  // Ruler
  bool _rulerVisible = false;
  double? _rulerDistM;
  double? _rulerBearingFromRed;
  double? _rulerBearingFromBlue;

  // Chart layers (live state — synced to JS and saved to config)
  late List<Map<String, dynamic>> _layers;

  // Tile freshness
  TileFreshness _viewportFreshness = TileFreshness.uncached;
  Timer? _freshnessRetryTimer;
  Map<String, dynamic>? _lastViewportData;

  // Vessel trail
  final List<List<double>> _trailPoints = []; // [[lon, lat], ...]
  final List<int> _trailTimestamps = []; // epoch ms, parallel list
  DateTime _lastTrailPush = DateTime(0);

  // Route overlay
  String? _activeRouteHref;
  List<List<double>>? _routeCoords;
  List<String>? _waypointNames;
  int? _routePointIndex;
  int? _routePointTotal;
  bool _routeReversed = false;
  RouteArrivalMonitor? _arrivalMonitor;
  StreamSubscription<RouteArrivalEvent>? _arrivalSub;

  // ---------------------------------------------------------------------------
  // Config accessors
  // ---------------------------------------------------------------------------

  // Fallback defaults when dataSources is empty (legacy configs)
  static const _fallbackPaths = [
    'navigation.position',          // 0: position
    'navigation.headingTrue',       // 1: heading
    'navigation.courseOverGroundTrue', // 2: COG
    'navigation.speedOverGround',   // 3: SOG
    'environment.depth.belowTransducer', // 4: depth
    'navigation.course.calcValues.bearingTrue', // 5: bearing
    'navigation.course.calcValues.crossTrackError', // 6: XTE
    'navigation.course.calcValues.distance', // 7: DTW
    'navigation.course.activeRoute', // 8: active route
    'navigation.courseGreatCircle.nextPoint.position', // 9: next point
  ];

  /// Read a SignalK path from dataSources by index, falling back to defaults.
  String _dsPath(int index) {
    if (widget.config.dataSources.length > index) {
      return widget.config.dataSources[index].path;
    }
    return index < _fallbackPaths.length ? _fallbackPaths[index] : '';
  }

  /// All configured paths (for subscribe/unsubscribe).
  List<String> get _allPaths {
    if (widget.config.dataSources.isNotEmpty) {
      return widget.config.dataSources.map((ds) => ds.path).toList();
    }
    return List.from(_fallbackPaths);
  }

  int get _trailMinutes =>
      widget.config.style.customProperties?['trailMinutes'] as int? ?? 10;

  String get _hudPosition =>
      widget.config.style.customProperties?['hudPosition'] as String? ??
      'bottom';

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    // Initialize layer config from widget config
    final rawLayers = widget.config.style.customProperties?['layers'] as List?;
    _layers = rawLayers != null
        ? rawLayers.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : [
            {'type': 'base', 'id': 'carto_voyager', 'enabled': true, 'opacity': 1.0},
            {'type': 's57', 'id': '01CGD_ENCs', 'enabled': true, 'opacity': 1.0},
          ];
    widget.signalKService.subscribeToPaths(
      _allPaths,
      ownerId: _ownerId,
    );
    widget.signalKService.addListener(_onSignalKUpdate);
    widget.signalKService.aisVesselRegistry.addListener(_onAISUpdate);
    _ensureAISLoaded();
  }

  @override
  void dispose() {
    _freshnessRetryTimer?.cancel();
    _stopArrivalMonitor();
    widget.signalKService.aisVesselRegistry.removeListener(_onAISUpdate);
    widget.signalKService.removeListener(_onSignalKUpdate);
    _resetSwipeBlock();
    widget.signalKService.unsubscribeFromPaths(
      _allPaths,
      ownerId: _ownerId,
    );
    super.dispose();
  }

  void _ensureAISLoaded() {
    if (!_hasLoadedAIS && widget.signalKService.isConnected) {
      _hasLoadedAIS = true;
      widget.signalKService.loadAndSubscribeAISVessels();
    }
  }

  // ---------------------------------------------------------------------------
  // WebView bridge
  // ---------------------------------------------------------------------------

  void _onWebViewReady(WebViewController controller) {
    _controller = controller;
    _mapReady = true;
    _pushVesselPosition();
    _pushAISVessels();
    if (_routeCoords != null) _pushRoute();
    // Push scale bar units
    final distMeta = widget.signalKService.metadataStore.getByCategory('distance');
    final scaleUnits = _mapDistSymbolToOLUnits(distMeta?.symbol);
    _controller!.runJavaScript("setScaleBarUnits('$scaleUnits')");
    // Configure tile server with upstream URL and auth token
    try {
      final tileServer = context.read<ChartTileServerService>();
      final refreshStr = widget.config.style.customProperties?['cacheRefresh'] as String? ?? 'stale';
      tileServer.configure(
        upstreamBaseUrl: widget.signalKService.httpBaseUrl,
        authToken: widget.signalKService.authToken?.token,
        refreshThreshold: refreshStr == 'aging' ? TileFreshness.aging : TileFreshness.stale,
      );
    } catch (_) {}
  }

  void _onViewportChanged(Map<String, dynamic> data) {
    if (!mounted) return;
    _lastViewportData = data;
    _freshnessRetryTimer?.cancel();
    _updateFreshness(data);
  }

  void _updateFreshness(Map<String, dynamic> viewport) {
    try {
      final cacheService = context.read<ChartTileCacheService>();
      final zoom = (viewport['zoom'] as num).toInt();
      final minLon = (viewport['minLon'] as num).toDouble();
      final minLat = (viewport['minLat'] as num).toDouble();
      final maxLon = (viewport['maxLon'] as num).toDouble();
      final maxLat = (viewport['maxLat'] as num).toDouble();

      // Only check tile freshness at zooms where S-57 tiles exist (9-16)
      if (zoom < 9) {
        setState(() => _viewportFreshness = TileFreshness.uncached);
        return;
      }
      final z = zoom.clamp(9, 16);
      final x0 = ChartDownloadManager.lonToTileX(minLon, z);
      final x1 = ChartDownloadManager.lonToTileX(maxLon, z);
      final y0 = ChartDownloadManager.latToTileY(maxLat, z);
      final y1 = ChartDownloadManager.latToTileY(minLat, z);

      final tiles = <(int, int, int)>[];
      for (int x = x0; x <= x1; x++) {
        for (int y = y0; y <= y1; y++) {
          tiles.add((z, x, y));
        }
      }

      final freshness = cacheService.getViewportFreshness(tiles);
      if (mounted) setState(() => _viewportFreshness = freshness);

      // If not fully fresh, re-check after tiles have had time to cache via proxy
      if (freshness != TileFreshness.fresh && _lastViewportData != null) {
        _freshnessRetryTimer?.cancel();
        _freshnessRetryTimer = Timer(const Duration(seconds: 3), () {
          if (mounted && _lastViewportData != null) {
            _updateFreshness(_lastViewportData!);
          }
        });
      }
    } catch (_) {}
  }

  void _onAutoFollowChanged(bool autoFollow, {bool? autoZoom}) {
    if (mounted) {
      setState(() {
        _autoFollow = autoFollow;
        // autoZoom handled on JS side only
      });
    }
  }

  void _onSignalKUpdate() {
    if (!_mapReady || _controller == null) return;
    // Reset AIS flag on disconnect so we re-subscribe on reconnect
    if (!widget.signalKService.isConnected) {
      _hasLoadedAIS = false;
    } else if (!_hasLoadedAIS) {
      _ensureAISLoaded();
    }
    // Check for route changes
    _checkActiveRoute();
    final now = DateTime.now();
    if (now.difference(_lastVesselPush).inMilliseconds < 500) return;
    _lastVesselPush = now;
    _pushVesselPosition();
    // Push route on every throttled update (activeIndex may change)
    if (_routeCoords != null) _pushRoute();
  }

  void _onAISUpdate() {
    if (!_mapReady || _controller == null) return;
    final now = DateTime.now();
    if (now.difference(_lastAISPush).inMilliseconds < 1000) return;
    _lastAISPush = now;
    _pushAISVessels();
  }

  void _pushVesselPosition() {
    final posData = widget.signalKService.getValue(_dsPath(_dsPosition));
    if (posData?.value is! Map) return;
    final pos = posData!.value as Map;
    final lat = (pos['latitude'] as num?)?.toDouble();
    final lon = (pos['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) return;

    final heading = _numValue(_dsPath(_dsHeading));
    final cog = _numValue(_dsPath(_dsCog));
    final sog = _numValue(_dsPath(_dsSog));

    _controller!.runJavaScript(
      'updateVesselPosition($lat, $lon, ${heading ?? 'null'}, ${cog ?? 'null'}, ${sog ?? 0})',
    );

    // Trail: append point if moved >5m from last
    _collectTrailPoint(lon, lat);
  }

  void _collectTrailPoint(double lon, double lat) {
    if (_trailPoints.isNotEmpty) {
      final last = _trailPoints.last;
      final dx = (lon - last[0]) * math.cos(lat * math.pi / 180) * 111320;
      final dy = (lat - last[1]) * 111320;
      if (dx * dx + dy * dy < 25) return; // <5m, skip
    }
    _trailPoints.add([lon, lat]);
    _trailTimestamps.add(DateTime.now().millisecondsSinceEpoch);

    // Trim old points
    final cutoff =
        DateTime.now().millisecondsSinceEpoch - _trailMinutes * 60000;
    while (_trailTimestamps.isNotEmpty && _trailTimestamps.first < cutoff) {
      _trailTimestamps.removeAt(0);
      _trailPoints.removeAt(0);
    }

    // Throttled push (every 2s)
    final now = DateTime.now();
    if (now.difference(_lastTrailPush).inSeconds >= 2) {
      _lastTrailPush = now;
      _pushTrail();
    }
  }

  void _pushTrail() {
    if (_trailPoints.length < 2 || _controller == null || !_mapReady) return;
    final json = jsonEncode(_trailPoints);
    _controller!.runJavaScript('updateTrail(${_escapeForJS(json)})');
  }

  void _toggleViewMode() {
    final newMode = _viewMode == 'north-up' ? 'heading-up' : 'north-up';
    setState(() => _viewMode = newMode);
    _controller?.runJavaScript("setViewMode('$newMode')");
  }

  void _disableAutoFollow() {
    setState(() {
      _autoFollow = false;
    });
    _controller?.runJavaScript('setAutoFollow(false)');
  }

  void _reCenter() {
    setState(() {
      _autoFollow = true;
    });
    _controller?.runJavaScript('setAutoFollow(true)');
  }

  // ---------------------------------------------------------------------------
  // Active route
  // ---------------------------------------------------------------------------

  DateTime _lastRoutePoll = DateTime(0);

  void _checkActiveRoute() {
    // activeRoute data is v2-only — not in WS deltas.
    // Poll v2 REST endpoint every 3 seconds.
    final now = DateTime.now();
    if (now.difference(_lastRoutePoll).inSeconds < 3) return;
    _lastRoutePoll = now;
    _pollCourseAPI();
  }

  Future<void> _pollCourseAPI() async {
    final url = '${widget.signalKService.httpBaseUrl}'
        '/signalk/v2/api/vessels/self/navigation/course';
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          if (widget.signalKService.authToken?.token != null)
            'Authorization': 'Bearer ${widget.signalKService.authToken!.token}',
        },
      );
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final activeRoute = data['activeRoute'] as Map<String, dynamic>?;

      if (activeRoute != null) {
        final href = activeRoute['href'] as String?;
        _routePointIndex = activeRoute['pointIndex'] as int?;
        _routePointTotal = activeRoute['pointTotal'] as int?;
        _routeReversed = activeRoute['reverse'] == true;

        if (href != null && href != _activeRouteHref) {
          _activeRouteHref = href;
          _fetchRoute(href);
          _startArrivalMonitor();
        } else if (_routeCoords != null) {
          _pushRoute();
        }
        if (mounted) setState(() {});
      } else if (_activeRouteHref != null) {
        _activeRouteHref = null;
        _routeCoords = null;
        _waypointNames = null;
        _routePointIndex = null;
        _routePointTotal = null;
        _routeReversed = false;
        _stopArrivalMonitor();
        _controller?.runJavaScript('updateRoute(null)');
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _fetchRoute(String href) async {
    final routeId = href.split('/').last;
    final data = await widget.signalKService.getResource('routes', routeId);
    if (data == null) return;
    final feature = data['feature'] as Map?;
    final geometry = feature?['geometry'] as Map?;
    _routeCoords = (geometry?['coordinates'] as List?)
        ?.map((c) => [(c[0] as num).toDouble(), (c[1] as num).toDouble()])
        .toList();
    final meta = (feature?['properties'] as Map?)?['coordinatesMeta'] as List?;
    _waypointNames = meta?.map((m) => (m['name'] as String?) ?? '').toList();
    _pushRoute();
    if (mounted) setState(() {});
  }

  void _pushRoute() {
    if (_routeCoords == null || _controller == null || !_mapReady) return;
    final json = jsonEncode({
      'coords': _routeCoords,
      'names': _waypointNames,
      'activeIndex': _routePointIndex,
      'reverse': _routeReversed,
    });
    _controller!.runJavaScript('updateRoute(${_escapeForJS(json)})');
  }

  // ---------------------------------------------------------------------------
  // Waypoint arrival & advance
  // ---------------------------------------------------------------------------

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
        title: 'Waypoint ${event.pointIndex + 1}/${event.pointTotal} Reached',
        action: 'Next Waypoint',
      ).then((confirmed) {
        if (confirmed) _advanceWaypoint();
      });
    }
  }

  Future<void> _advanceWaypoint() async {
    if (_routePointIndex == null || _routePointTotal == null) return;
    final nextIdx = _routePointIndex! + 1;
    if (nextIdx >= _routePointTotal!) return;

    final url = '${widget.signalKService.httpBaseUrl}'
        '/signalk/v2/api/vessels/self/navigation/course/activeRoute/pointIndex';
    try {
      await http.put(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (widget.signalKService.authToken?.token != null)
            'Authorization': 'Bearer ${widget.signalKService.authToken!.token}',
        },
        body: jsonEncode({'value': nextIdx}),
      );
      _lastRoutePoll = DateTime(0);
      await _pollCourseAPI();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Advance failed: $e')),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // AIS targets
  // ---------------------------------------------------------------------------

  void _pushAISVessels() {
    if (!_aisEnabled) {
      _controller!.runJavaScript('updateAISVessels(${_escapeForJS(jsonEncode([]))})');
      return;
    }

    final registry = widget.signalKService.aisVesselRegistry.vessels;
    final ownCogRad = _numValue(_dsPath(_dsCog));
    final ownSogMs = _numValue(_dsPath(_dsSog)) ?? 0.0;

    // Own position for bearing/distance/CPA
    final posData = widget.signalKService.getValue(_dsPath(_dsPosition));
    double? ownLat, ownLon;
    if (posData?.value is Map) {
      final pos = posData!.value as Map;
      ownLat = (pos['latitude'] as num?)?.toDouble();
      ownLon = (pos['longitude'] as num?)?.toDouble();
    }

    final vessels = <Map<String, dynamic>>[];
    for (final entry in registry.entries) {
      final v = entry.value;
      if (!v.hasPosition) continue;

      // Active-only filter: hide stale vessels (lost, removed, or unseen 10+ min)
      if (_aisActiveOnly) {
        if (v.aisStatus == 'lost' || v.aisStatus == 'remove') continue;
        if (v.lastSeen.difference(DateTime.now()).inMinutes.abs() >= 10) continue;
      }

      // CPA/TCPA (needs own position)
      double? cpa, tcpa;
      if (ownLat != null && ownLon != null) {
        final bearing = CpaUtils.calculateBearing(ownLat, ownLon, v.latitude!, v.longitude!);
        final distance = CpaUtils.calculateDistance(ownLat, ownLon, v.latitude!, v.longitude!);
        final result = CpaUtils.calculateCpaTcpa(
          bearingDeg: bearing,
          distanceM: distance,
          ownCogRad: ownCogRad,
          ownSogMs: ownSogMs,
          targetCogRad: v.cogRad,
          targetSogMs: v.sogMs,
        );
        cpa = result?.cpa;
        tcpa = result?.tcpa;
      }
      // Sanitize non-finite values — jsonEncode chokes on Infinity/NaN
      if (cpa != null && !cpa.isFinite) cpa = null;
      if (tcpa != null && !tcpa.isFinite) tcpa = null;

      final projections = _calculateProjections(v);

      vessels.add({
        'id': v.vesselId,
        'name': v.name,
        'lat': v.latitude,
        'lon': v.longitude,
        'cogRad': v.cogRad != null && v.cogRad!.isFinite ? v.cogRad : null,
        'sogMs': v.sogMs != null && v.sogMs!.isFinite ? v.sogMs : null,
        'hdgRad': v.headingTrueRad != null && v.headingTrueRad!.isFinite ? v.headingTrueRad : null,
        'shipType': v.aisShipType,
        'navState': v.navState,
        'aisClass': v.aisClass,
        'aisStatus': v.aisStatus,
        'lastSeen': v.lastSeen.millisecondsSinceEpoch,
        'cpa': cpa,
        'tcpa': tcpa,
        'projections': _aisShowPaths ? projections.map((p) => {'lat': p.lat, 'lon': p.lon}).toList() : [],
      });
    }

    final json = jsonEncode(vessels);
    _controller!.runJavaScript('updateAISVessels(${_escapeForJS(json)})');
  }

  /// Great-circle projected positions at 30s, 1m, 15m, 30m intervals.
  List<({double lat, double lon})> _calculateProjections(dynamic vessel) {
    final sogMs = (vessel.sogMs as double?) ?? 0.0;
    final cogRad = vessel.cogRad as double?;
    final lat = vessel.latitude as double?;
    final lon = vessel.longitude as double?;
    if (sogMs < 0.1 || cogRad == null || lat == null || lon == null) return [];

    const intervals = [30.0, 60.0, 900.0, 1800.0];
    final results = <({double lat, double lon})>[];
    for (final t in intervals) {
      final d = sogMs * t;
      final lat1 = lat * math.pi / 180;
      final lon1 = lon * math.pi / 180;
      final a = d / 6371000.0;
      final lat2 = math.asin(
        math.sin(lat1) * math.cos(a) +
        math.cos(lat1) * math.sin(a) * math.cos(cogRad),
      );
      final lon2 = lon1 + math.atan2(
        math.sin(cogRad) * math.sin(a) * math.cos(lat1),
        math.cos(a) - math.sin(lat1) * math.sin(lat2),
      );
      results.add((lat: lat2 * 180 / math.pi, lon: lon2 * 180 / math.pi));
    }
    return results;
  }

  void _onRulerUpdate(Map<String, dynamic> data) {
    if (!mounted) return;
    setState(() {
      _rulerDistM = (data['distM'] as num?)?.toDouble();
      _rulerBearingFromRed = (data['bearingFromRed'] as num?)?.toDouble();
      _rulerBearingFromBlue = (data['bearingFromBlue'] as num?)?.toDouble();
    });
  }

  void _toggleRuler() {
    setState(() => _rulerVisible = !_rulerVisible);
    _controller?.runJavaScript('showRuler($_rulerVisible)');
    if (_rulerVisible) {
      _pushRulerUnits();
    }
  }

  void _pushRulerUnits() {
    final distMeta = widget.signalKService.metadataStore.getByCategory('distance');
    final factor = distMeta?.convert(1.0) ?? 0.000539957;
    final symbol = distMeta?.symbol ?? 'nm';
    _controller?.runJavaScript('updateRulerUnits($factor, ${jsonEncode(symbol)})');
  }

  void _showDownloadDialog() async {
    if (_controller == null) return;
    // Get current viewport from JS
    final result = await _controller!.runJavaScriptReturningResult('getViewportTileInfo()');
    final viewportJson = result is String ? result : result.toString();
    // Strip quotes if wrapped
    final cleaned = viewportJson.startsWith('"') ? viewportJson.substring(1, viewportJson.length - 1) : viewportJson;
    final viewport = jsonDecode(cleaned.replaceAll(r'\"', '"')) as Map<String, dynamic>;
    final minLon = (viewport['minLon'] as num).toDouble();
    final minLat = (viewport['minLat'] as num).toDouble();
    final maxLon = (viewport['maxLon'] as num).toDouble();
    final maxLat = (viewport['maxLat'] as num).toDouble();

    if (!mounted) return;

    ChartDownloadManager? downloadManager;
    try {
      downloadManager = context.read<ChartDownloadManager>();
    } catch (_) {
      return;
    }

    var minZoom = 9;
    var maxZoom = 16;
    final nameController = TextEditingController(text: 'Area ${DateTime.now().toString().substring(0, 16)}');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final estimate = downloadManager!.estimateTileCount(
            minLon: minLon, minLat: minLat,
            maxLon: maxLon, maxLat: maxLat,
            minZoom: minZoom, maxZoom: maxZoom,
          );
          final estimatedMB = (estimate * 10 / 1024).toStringAsFixed(1);

          return Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E2E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
                )),
                const Text('Download Charts', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  '${minLat.toStringAsFixed(2)}°N to ${maxLat.toStringAsFixed(2)}°N, '
                  '${minLon.toStringAsFixed(2)}°E to ${maxLon.toStringAsFixed(2)}°E',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Region name',
                    hintStyle: TextStyle(color: Colors.white38),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.green)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  const Text('Zoom: ', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Expanded(
                    child: RangeSlider(
                      values: RangeValues(minZoom.toDouble(), maxZoom.toDouble()),
                      min: 9, max: 16,
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
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 12),
                // Download progress (if downloading)
                ListenableBuilder(
                  listenable: downloadManager,
                  builder: (_, _) {
                    if (downloadManager!.status == DownloadStatus.downloading) {
                      return Column(children: [
                        LinearProgressIndicator(value: downloadManager.progress),
                        const SizedBox(height: 4),
                        Text('${downloadManager.downloadedTiles} of ${downloadManager.totalTiles}',
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => downloadManager!.cancel(),
                          child: const Text('Cancel', style: TextStyle(color: Colors.red)),
                        ),
                      ]);
                    }
                    if (downloadManager.status == DownloadStatus.completed) {
                      return const Text('Download complete!',
                        style: TextStyle(color: Colors.green, fontSize: 14, fontWeight: FontWeight.w500));
                    }
                    if (downloadManager.status == DownloadStatus.error) {
                      return Text(downloadManager.errorMessage ?? 'Download failed',
                        style: const TextStyle(color: Colors.red, fontSize: 13));
                    }
                    // idle/cancelled — show download + flush buttons
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
                          onPressed: () {
                            downloadManager!.downloadArea(
                              minLon: minLon, minLat: minLat,
                              maxLon: maxLon, maxLat: maxLat,
                              minZoom: minZoom, maxZoom: maxZoom,
                              baseUrl: widget.signalKService.httpBaseUrl,
                              authToken: widget.signalKService.authToken?.token,
                              regionName: nameController.text,
                            );
                          },
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
                          onPressed: () {
                            downloadManager!.downloadArea(
                              minLon: minLon, minLat: minLat,
                              maxLon: maxLon, maxLat: maxLat,
                              minZoom: minZoom, maxZoom: maxZoom,
                              baseUrl: widget.signalKService.httpBaseUrl,
                              authToken: widget.signalKService.authToken?.token,
                              regionName: nameController.text,
                              flush: true,
                            );
                          },
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
    ).whenComplete(() {
      downloadManager?.reset();
    });
  }

  void _pushLayers() {
    if (_controller == null || !_mapReady) return;
    final json = jsonEncode(_layers);
    _controller!.runJavaScript('updateLayers(${_escapeForJS(json)})');
    _saveLayerConfig();
  }

  void _saveLayerConfig() {
    final toolId = widget.config.style.customProperties?['_toolId'] as String?;
    if (toolId == null) return;
    try {
      final toolService = context.read<ToolService>();
      final tool = toolService.getTool(toolId);
      if (tool == null) return;
      final updatedProps = {
        ...?tool.config.style.customProperties,
        'layers': _layers,
      };
      final updatedTool = tool.copyWith(
        config: ToolConfig(
          vesselId: tool.config.vesselId,
          dataSources: tool.config.dataSources,
          style: StyleConfig(
            minValue: tool.config.style.minValue,
            maxValue: tool.config.style.maxValue,
            unit: tool.config.style.unit,
            primaryColor: tool.config.style.primaryColor,
            secondaryColor: tool.config.style.secondaryColor,
            showLabel: tool.config.style.showLabel,
            showValue: tool.config.style.showValue,
            showUnit: tool.config.style.showUnit,
            ttlSeconds: tool.config.style.ttlSeconds,
            customProperties: updatedProps,
          ),
        ),
      );
      toolService.saveTool(updatedTool);
    } catch (_) {}
  }

  static const _baseMapNames = <String, String>{
    'carto_voyager': 'CartoDB Voyager',
    'carto_dark': 'CartoDB Dark Matter',
    'carto_light': 'CartoDB Positron',
    'esri_ocean': 'Esri Ocean',
    'esri_satellite': 'Esri Satellite',
  };

  static const _baseMapDescriptions = <String, String>{
    'carto_voyager': 'Street map with muted colors',
    'carto_dark': 'Dark map for night use',
    'carto_light': 'Light minimal background',
    'esri_ocean': 'Ocean bathymetry',
    'esri_satellite': 'Aerial/satellite imagery',
  };

  void _showLayersPanel() {
    _controller?.runJavaScript('setMapInteractive(false)');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.45,
          maxChildSize: 0.7,
          minChildSize: 0.2,
          snap: true,
          snapSizes: const [0.2, 0.45],
          builder: (_, scrollController) => Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E2E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              children: [
                // Drag handle + header
                Center(child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(top: 8, bottom: 8),
                  decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
                )),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    const Icon(Icons.layers, color: Colors.white70),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Chart Layers',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                    // Add layer button
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
                      onPressed: () => _showAddLayerPicker(ctx, setSheetState),
                    ),
                  ]),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Drag to reorder. Top of list = bottom of map.',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
                ),
                const SizedBox(height: 4),
                // Reorderable layer list
                Expanded(
                  child: ReorderableListView.builder(
                    scrollController: scrollController,
                    itemCount: _layers.length,
                    onReorder: (oldIndex, newIndex) {
                      setSheetState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final item = _layers.removeAt(oldIndex);
                        _layers.insert(newIndex, item);
                      });
                      _pushLayers();
                    },
                    itemBuilder: (_, index) {
                      final layer = _layers[index];
                      final type = layer['type'] as String;
                      final id = layer['id'] as String;
                      final enabled = layer['enabled'] as bool? ?? true;
                      final opacity = (layer['opacity'] as num?)?.toDouble() ?? 1.0;
                      final name = type == 'base' ? (_baseMapNames[id] ?? id) : id;

                      return Card(
                        key: ValueKey('$type:$id:$index'),
                        color: const Color(0xFF2A2A3E),
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        child: Column(children: [
                          ListTile(
                            dense: true,
                            leading: ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle, color: Colors.grey, size: 20),
                            ),
                            title: Row(children: [
                              Icon(
                                type == 'base' ? Icons.map_outlined : Icons.layers,
                                size: 14,
                                color: enabled ? Colors.white70 : Colors.white24,
                              ),
                              const SizedBox(width: 6),
                              Expanded(child: Text(name,
                                style: TextStyle(
                                  color: enabled ? Colors.white : Colors.white38,
                                  fontSize: 13,
                                ))),
                            ]),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(
                                  value: enabled,
                                  onChanged: (v) {
                                    setSheetState(() => layer['enabled'] = v);
                                    _pushLayers();
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 16, color: Colors.white38),
                                  constraints: const BoxConstraints.tightFor(width: 28),
                                  onPressed: () {
                                    setSheetState(() => _layers.removeAt(index));
                                    _pushLayers();
                                  },
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(48, 0, 12, 4),
                            child: Row(children: [
                              Expanded(
                                child: Slider(
                                  value: opacity,
                                  min: 0.1, max: 1.0, divisions: 9,
                                  onChanged: enabled ? (v) {
                                    setSheetState(() => layer['opacity'] = double.parse(v.toStringAsFixed(1)));
                                    _pushLayers();
                                  } : null,
                                ),
                              ),
                              SizedBox(width: 32, child: Text(
                                '${(opacity * 100).round()}%',
                                style: const TextStyle(fontSize: 10, color: Colors.white38),
                                textAlign: TextAlign.right,
                              )),
                            ]),
                          ),
                        ]),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      _controller?.runJavaScript('setMapInteractive(true)');
    });
  }

  void _showAddLayerPicker(BuildContext ctx, void Function(VoidCallback) setSheetState) {
    final existingIds = _layers.map((l) => l['id'] as String).toSet();
    final options = <Map<String, String>>[];
    for (final entry in _baseMapNames.entries) {
      if (!existingIds.contains(entry.key)) {
        options.add({'type': 'base', 'id': entry.key, 'name': entry.value,
          'desc': _baseMapDescriptions[entry.key] ?? ''});
      }
    }

    showModalBottomSheet(
      context: ctx,
      backgroundColor: const Color(0xFF1E1E2E),
      builder: (pickerCtx) => FutureBuilder<Map<String, dynamic>>(
        future: widget.signalKService.getResources('charts'),
        builder: (_, snapshot) {
          final allOptions = List<Map<String, String>>.from(options);
          final charts = snapshot.data ?? {};
          for (final entry in charts.entries) {
            if (!existingIds.contains(entry.key)) {
              final data = entry.value as Map<String, dynamic>;
              allOptions.add({
                'type': 's57', 'id': entry.key,
                'name': data['name'] as String? ?? entry.key,
                'desc': data['description'] as String? ?? 'S-57 chart',
              });
            }
          }
          if (allOptions.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text('All available layers added',
                style: TextStyle(color: Colors.white54)),
            );
          }
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: allOptions.map((opt) {
              final isBase = opt['type'] == 'base';
              return ListTile(
                leading: Icon(
                  isBase ? Icons.map_outlined : Icons.layers,
                  color: isBase ? Colors.blue : Colors.green,
                ),
                title: Text(opt['name']!, style: const TextStyle(color: Colors.white)),
                subtitle: Text(opt['desc'] ?? '',
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
                onTap: () {
                  Navigator.pop(pickerCtx);
                  setSheetState(() {
                    _layers.add({
                      'type': opt['type']!,
                      'id': opt['id']!,
                      'enabled': true,
                      'opacity': 1.0,
                    });
                  });
                  _pushLayers();
                },
              );
            }).toList(),
          );
        },
      ),
    );
  }

  String _mapDistSymbolToOLUnits(String? symbol) {
    if (symbol == null) return 'nautical';
    final s = symbol.toLowerCase();
    if (s == 'nm' || s == 'nmi') return 'nautical';
    if (s == 'mi') return 'imperial';
    return 'metric';
  }

  String _escapeForJS(String json) {
    // Wrap in single quotes, escape internal single quotes and backslashes
    return "'${json.replaceAll('\\', '\\\\').replaceAll("'", "\\'")}'";
  }

  // ---------------------------------------------------------------------------
  // AIS vessel detail sheet
  // ---------------------------------------------------------------------------

  void _onAISVesselClick(String vesselId) {
    final vessel = widget.signalKService.aisVesselRegistry.vessels[vesselId];
    if (vessel == null) return;
    _showVesselDetail(vesselId);
  }

  void _showVesselDetail(String vesselId) {
    final vessel = widget.signalKService.aisVesselRegistry.vessels[vesselId];
    if (vessel == null) return;

    final store = widget.signalKService.metadataStore;
    final cogMeta = store.get(_dsPath(_dsCog));
    final sogMeta = store.get(_dsPath(_dsSog));
    final hdgMeta = store.get(_dsPath(_dsHeading));
    final distMeta = store.getByCategory('distance');
    final lenMeta = store.getByCategory('length');

    String fmtAngle(double? rad) {
      if (rad == null) return '--';
      final v = cogMeta?.convert(rad) ?? (rad * 180 / math.pi);
      return '${v.toStringAsFixed(1)}${cogMeta?.symbol ?? '°'}';
    }
    String fmtSpeed(double? ms) {
      if (ms == null) return '--';
      final v = sogMeta?.convert(ms) ?? ms;
      return '${v.toStringAsFixed(1)} ${sogMeta?.symbol ?? 'm/s'}';
    }
    String fmtHeading(double? rad) {
      if (rad == null) return '--';
      final v = hdgMeta?.convert(rad) ?? (rad * 180 / math.pi);
      return '${v.toStringAsFixed(1)}${hdgMeta?.symbol ?? '°'}';
    }
    String fmtDist(double? m) {
      if (m == null) return '--';
      final v = distMeta?.convert(m) ?? m;
      return '${v.toStringAsFixed(2)} ${distMeta?.symbol ?? 'm'}';
    }
    String fmtLength(double meters) {
      final v = lenMeta?.convert(meters) ?? meters;
      return '${v.toStringAsFixed(1)} ${lenMeta?.symbol ?? 'm'}';
    }

    // CPA/TCPA
    double? ownLat, ownLon;
    final posData = widget.signalKService.getValue(_dsPath(_dsPosition));
    if (posData?.value is Map) {
      final pos = posData!.value as Map;
      ownLat = (pos['latitude'] as num?)?.toDouble();
      ownLon = (pos['longitude'] as num?)?.toDouble();
    }
    double? bearing, distance, cpa, tcpa;
    if (ownLat != null && ownLon != null && vessel.hasPosition) {
      bearing = CpaUtils.calculateBearing(ownLat, ownLon, vessel.latitude!, vessel.longitude!);
      distance = CpaUtils.calculateDistance(ownLat, ownLon, vessel.latitude!, vessel.longitude!);
      final result = CpaUtils.calculateCpaTcpa(
        bearingDeg: bearing,
        distanceM: distance,
        ownCogRad: _numValue(_dsPath(_dsCog)),
        ownSogMs: _numValue(_dsPath(_dsSog)) ?? 0.0,
        targetCogRad: vessel.cogRad,
        targetSogMs: vessel.sogMs,
      );
      cpa = result?.cpa;
      tcpa = result?.tcpa;
      if (cpa != null && !cpa.isFinite) cpa = null;
      if (tcpa != null && !tcpa.isFinite) tcpa = null;
    }

    // Extra data from cache (callsign, destination, dimensions, IMO, AIS status)
    final cache = widget.signalKService.latestData;
    final prefix = 'vessels.${vessel.vesselId}';
    String? callsign, destination, shipTypeName, imo, aisStatusFromCache;
    final comm = cache['$prefix.communication']?.value;
    if (comm is Map) callsign = comm['callsignVhf'] as String?;
    final dest = cache['$prefix.navigation.destination.commonName']?.value;
    if (dest is String && dest.isNotEmpty) destination = dest;
    final aisType = cache['$prefix.design.aisShipType']?.value;
    if (aisType is Map) shipTypeName = aisType['name'] as String?;
    final reg = cache['$prefix.registrations']?.value;
    if (reg is Map) imo = reg['imo'] as String?;
    final aisStatusVal = cache['$prefix.sensors.ais.status']?.value;
    if (aisStatusVal is String) aisStatusFromCache = aisStatusVal;
    final aisClassFromCache = cache['$prefix.sensors.ais.class']?.value as String?;

    // Dimensions
    String? lengthStr, beamStr, draftStr;
    final beamVal = cache['$prefix.design.beam']?.value;
    if (beamVal is num) beamStr = fmtLength(beamVal.toDouble());
    final lengthVal = cache['$prefix.design.length']?.value;
    if (lengthVal is Map) {
      final overall = lengthVal['overall'];
      if (overall is num) lengthStr = fmtLength(overall.toDouble());
    } else if (lengthVal is num) {
      lengthStr = fmtLength(lengthVal.toDouble());
    }
    final draftVal = cache['$prefix.design.draft']?.value;
    if (draftVal is Map) {
      final current = draftVal['current'];
      if (current is num) draftStr = fmtLength(current.toDouble());
    } else if (draftVal is num) {
      draftStr = fmtLength(draftVal.toDouble());
    }
    String? dimensionsStr;
    final dimParts = <String>[];
    if (lengthStr != null && beamStr != null) {
      dimParts.add('$lengthStr x $beamStr');
    } else {
      if (lengthStr != null) dimParts.add(lengthStr);
      if (beamStr != null) dimParts.add('beam $beamStr');
    }
    if (draftStr != null) dimParts.add('draft $draftStr');
    if (dimParts.isNotEmpty) dimensionsStr = dimParts.join(', ');

    final mmsi = _extractMMSI(vessel.vesselId);
    final vesselName = vessel.name ?? 'Unknown Vessel';
    final typeLabel = shipTypeName ?? _shipTypeLabel(vessel.aisShipType);
    final typeColor = _shipTypeColor(vessel.aisShipType, vessel.aisClass);
    final heading = (vessel.headingTrueRad ?? vessel.cogRad ?? 0.0);

    // CPA color coding
    const alarmThreshold = 926.0; // 0.5 nm
    const warnThreshold = 1852.0; // 1 nm
    Color cpaColor(double? cpaM) {
      if (cpaM == null) return Colors.white;
      if (cpaM < alarmThreshold) return Colors.red;
      if (cpaM < warnThreshold) return Colors.orange;
      return Colors.white;
    }

    // Vessel icon for header
    IconData vesselIcon;
    if (vessel.navState == 'anchored') {
      vesselIcon = Icons.anchor;
    } else if (vessel.navState == 'moored') {
      vesselIcon = Icons.local_parking;
    } else if ((vessel.sogMs ?? 0) < 0.1) {
      vesselIcon = Icons.circle;
    } else {
      vesselIcon = Icons.navigation;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        maxChildSize: 0.65,
        minChildSize: 0.15,
        snap: true,
        snapSizes: const [0.15, 0.4],
        builder: (_, scrollController) => StatefulBuilder(
          builder: (sheetCtx, setSheetState) => NotificationListener<DraggableScrollableNotification>(
          onNotification: (notification) {
            if (notification.extent <= notification.minExtent) {
              Navigator.of(sheetContext).pop();
            }
            return false;
          },
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E2E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, -2))],
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                // Drag handle
                Center(child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
                )),
                // Header with icon, name, action buttons
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Transform.rotate(
                      angle: heading,
                      child: Icon(vesselIcon, color: typeColor, size: 32,
                        shadows: [Shadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 2)]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(vesselName,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text('MMSI: $mmsi',
                          style: const TextStyle(color: Colors.white54, fontSize: 13)),
                      ],
                    )),
                    // Favorite toggle
                    Builder(builder: (_) {
                      final favService = sheetCtx.read<AISFavoritesService>();
                      final isFav = favService.isFavorite(mmsi);
                      return IconButton(
                        icon: Icon(isFav ? Icons.favorite : Icons.favorite_border,
                          color: isFav ? Colors.red : Colors.white70),
                        tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
                        onPressed: () {
                          if (isFav) {
                            favService.removeFavorite(mmsi);
                          } else {
                            favService.addFavorite(AISFavorite(
                              mmsi: mmsi,
                              name: vesselName,
                            ));
                          }
                          setSheetState(() {});
                        },
                      );
                    }),
                    // VesselFinder lookup
                    IconButton(
                      icon: const Icon(Icons.travel_explore, color: Colors.white70),
                      tooltip: 'Look up on VesselFinder',
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => _VesselLookupPage(
                            url: 'https://www.vesselfinder.com/vessels/details/$mmsi',
                            title: 'VesselFinder',
                          ),
                        ));
                      },
                    ),
                    // Track in Find Home
                    Builder(builder: (_) {
                      final dashService = context.read<DashboardService>();
                      final findHomeScreen = dashService.findScreenWithToolType('find_home');
                      if (findHomeScreen == null) return const SizedBox.shrink();
                      return IconButton(
                        icon: const Icon(Icons.home_outlined, color: Colors.white70),
                        tooltip: 'Track in Find Home',
                        onPressed: () {
                          final targetService = context.read<FindHomeTargetService>();
                          targetService.setAisTarget(vesselId, vesselName);
                          dashService.setActiveScreen(findHomeScreen.$1);
                          Navigator.of(sheetContext).pop();
                        },
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 6),
                // Chips: type, class, status
                Wrap(spacing: 8, children: [
                  _typeChip(typeLabel, typeColor),
                  if (aisClassFromCache != null || vessel.aisClass != null)
                    _chip('Class ${aisClassFromCache ?? vessel.aisClass}'),
                  if (aisStatusFromCache != null || vessel.aisStatus != null)
                    _chip(aisStatusFromCache ?? vessel.aisStatus!),
                  if (vessel.navState != null)
                    _chip(vessel.navState!),
                ]),

                // Identity section
                if (callsign != null || imo != null || destination != null) ...[
                  _section('Identity'),
                  if (callsign != null) _row('Callsign', callsign),
                  if (imo != null) _row('IMO', imo),
                  if (destination != null) _row('Destination', destination),
                ],

                // Relative section
                if (bearing != null) ...[
                  _section('Relative'),
                  _row('Bearing', '${bearing.toStringAsFixed(1)}${cogMeta?.symbol ?? '°'}'),
                  if (distance != null) _row('Distance', fmtDist(distance)),
                  if (cpa != null) _rowColored('CPA', fmtDist(cpa), cpaColor(cpa)),
                  if (tcpa != null && tcpa.isFinite && tcpa > 0)
                    _rowColored('TCPA', _fmtTCPA(tcpa), cpaColor(cpa)),
                ],

                // Dimensions section
                if (dimensionsStr != null) ...[
                  _section('Dimensions'),
                  _row('Size', dimensionsStr),
                ],

                // Navigation section
                _section('Navigation'),
                if (vessel.navState != null) _row('Nav Status', vessel.navState!),
                _row('SOG', fmtSpeed(vessel.sogMs)),
                _row('COG', fmtAngle(vessel.cogRad)),
                _row('Heading', fmtHeading(vessel.headingTrueRad)),

                // Position section
                _section('Position'),
                if (vessel.hasPosition)
                  _row('Lat/Lon', '${vessel.latitude!.toStringAsFixed(5)}, ${vessel.longitude!.toStringAsFixed(5)}'),
                _row('Last Update', '${_formatTimeSince(vessel.lastSeen)} ago'),
              ],
            ),
          ),
        )),
      ),
    );
  }

  Widget _typeChip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
  );

  Widget _chip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
    child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.white54)),
  );

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(title.toUpperCase(),
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white38, letterSpacing: 0.8)),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13))),
      Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500))),
    ]),
  );

  Widget _rowColored(String label, String value, Color valueColor) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13))),
      Expanded(child: Text(value, style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.w500))),
    ]),
  );

  String _fmtTCPA(double seconds) {
    if (seconds < 60) return '${seconds.toStringAsFixed(0)}s';
    if (seconds < 3600) return '${(seconds / 60).toStringAsFixed(1)}m';
    return '${(seconds / 3600).toStringAsFixed(1)}h';
  }

  static String _formatTimeSince(DateTime timestamp) {
    final elapsed = DateTime.now().difference(timestamp);
    if (elapsed.inSeconds < 60) return '${elapsed.inSeconds}s';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m';
    return '${elapsed.inHours}h';
  }

  static String _extractMMSI(String vesselId) {
    final match = RegExp(r'(\d{9})').firstMatch(vesselId);
    return match?.group(1) ?? vesselId;
  }

  static String _shipTypeLabel(int? type) {
    if (type == null) return 'Unknown';
    if (type == 30) return 'Fishing';
    if (type == 31 || type == 32) return 'Towing';
    if (type == 35) return 'Military';
    if (type == 36) return 'Sailing';
    if (type == 37) return 'Pleasure craft';
    if (type == 50) return 'Pilot vessel';
    if (type == 51) return 'SAR';
    if (type == 52) return 'Tug';
    if (type >= 60 && type <= 69) return 'Passenger';
    if (type >= 70 && type <= 79) return 'Cargo';
    if (type >= 80 && type <= 89) return 'Tanker';
    return 'Other ($type)';
  }

  static Color _shipTypeColor(int? type, String? aisClass) {
    if (type == null) return aisClass == 'A' ? Colors.grey.shade400 : Colors.grey;
    if (type == 36) return Colors.purple;
    switch (type ~/ 10) {
      case 1: case 2: return Colors.cyan;
      case 3: return Colors.amber;
      case 4: case 5: return Colors.teal;
      case 6: return Colors.blue;
      case 7: return Colors.green.shade700;
      case 8: return Colors.brown;
      default: return Colors.grey;
    }
  }

  // ---------------------------------------------------------------------------
  // Vessel data (raw SI from single WS)
  // ---------------------------------------------------------------------------

  double? _numValue(String path) {
    final data = widget.signalKService.getValue(path);
    return data?.value is num ? (data!.value as num).toDouble() : null;
  }

  // ---------------------------------------------------------------------------
  // HUD — ALL values via MetadataStore
  // ---------------------------------------------------------------------------

  String _formatValue(String path, {int decimals = 1, String? fallbackCategory, String? fallbackPath}) {
    final data = widget.signalKService.getValue(path);
    if (data?.value == null || data!.value is! num) return '--';
    final rawValue = (data.value as num).toDouble();
    final store = widget.signalKService.metadataStore;
    final metadata = store.get(path)
        ?? (fallbackPath != null ? store.get(fallbackPath) : null)
        ?? (fallbackCategory != null ? store.getByCategory(fallbackCategory) : null);
    if (metadata != null) {
      return metadata.format(rawValue, decimals: decimals);
    }
    return rawValue.toStringAsFixed(decimals);
  }

  Widget _buildHUD() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: _hudPosition == 'bottom' ? 0 : null,
      top: _hudPosition == 'top' ? 0 : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _hudItem('SOG', _formatValue(_dsPath(_dsSog), fallbackCategory: 'speed')),
            _hudItem('COG', _formatValue(_dsPath(_dsCog), decimals: 0, fallbackCategory: 'angle')),
            _hudItem('DPT', _formatValue(_dsPath(_dsDepth), decimals: 1, fallbackCategory: 'depth')),
            _hudItem('DTW', _formatValue(_dsPath(_dsDtw), decimals: 1, fallbackCategory: 'distance')),
            _hudItem('BRG', _formatValue(_dsPath(_dsBearing), decimals: 0, fallbackPath: _dsPath(_dsCog), fallbackCategory: 'angle')),
            _hudItem('XTE', _formatValue(_dsPath(_dsXte), decimals: 1, fallbackCategory: 'distance')),
            if (_routeCoords != null &&
                _routePointIndex != null &&
                _routePointTotal != null &&
                _routePointIndex! + 1 < _routePointTotal!) ...[
              GestureDetector(
                onTap: _advanceWaypoint,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.skip_next, color: Colors.white70, size: 24),
                ),
              ),
              GestureDetector(
                onTap: _fastForwardToNearest,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.fast_forward, color: Colors.white70, size: 24),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hudItem(String label, String value) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      );

  // ---------------------------------------------------------------------------
  // Route management UI
  // ---------------------------------------------------------------------------

  void _showRouteManager() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.45,
        maxChildSize: 0.7,
        minChildSize: 0.2,
        snap: true,
        snapSizes: const [0.2, 0.45],
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: _routeCoords != null
              ? _buildActiveRoutePanel(sheetCtx, scrollController)
              : _buildRouteList(sheetCtx, scrollController),
        ),
      ),
    );
  }

  /// Shows list of available routes to activate.
  Widget _buildRouteList(BuildContext sheetCtx, ScrollController scrollController) {
    return FutureBuilder<Map<String, dynamic>>(
      future: widget.signalKService.getResources('routes'),
      builder: (context, snapshot) {
        final routes = snapshot.data;
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            Center(child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
            )),
            const Text('Routes', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (!snapshot.hasData)
              const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ))
            else if (routes == null || routes.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No routes on server', style: TextStyle(color: Colors.white54)),
              )
            else
              ...routes.entries.map((entry) {
                final id = entry.key;
                final data = entry.value as Map<String, dynamic>;
                final name = data['name'] as String? ?? id;
                final desc = data['description'] as String?;
                final distM = data['distance'] as num?;
                final distMeta = widget.signalKService.metadataStore.getByCategory('distance');
                final distStr = distM != null
                    ? '${(distMeta?.convert(distM.toDouble()) ?? distM).toStringAsFixed(1)} ${distMeta?.symbol ?? 'm'}'
                    : null;
                final feature = data['feature'] as Map?;
                final coords = (feature?['geometry'] as Map?)?['coordinates'] as List?;
                final wptCount = coords?.length ?? 0;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.route, color: Colors.white54),
                  title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    [if (distStr != null) distStr, '$wptCount waypoints', if (desc != null) desc] // ignore: use_null_aware_elements
                        .join(' · '),
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Transform.flip(
                          flipX: true,
                          child: const Icon(Icons.play_arrow, color: Colors.red, size: 22),
                        ),
                        tooltip: 'Activate reversed',
                        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          _activateRoute(id, reverse: true);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.play_arrow, color: Colors.green, size: 22),
                        tooltip: 'Activate forward',
                        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          _activateRoute(id);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.white38, size: 18),
                        tooltip: 'Edit route',
                        constraints: const BoxConstraints.tightFor(width: 32, height: 36),
                        onPressed: () => _showEditRouteDialog(sheetCtx, id, name, data),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 18),
                        tooltip: 'Delete route',
                        constraints: const BoxConstraints.tightFor(width: 32, height: 36),
                        onPressed: () => _showDeleteRouteDialog(sheetCtx, id, name),
                      ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  /// Shows active route info with deactivate/advance controls.
  Widget _buildActiveRoutePanel(BuildContext sheetCtx, ScrollController scrollController) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Center(child: Container(
          width: 40, height: 4,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
        )),
        Row(children: [
          const Icon(Icons.route, color: Colors.green, size: 24),
          const SizedBox(width: 8),
          const Expanded(child: Text('Active Route',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
          // Reverse route
          IconButton(
            icon: const Icon(Icons.swap_horiz, color: Colors.orange),
            tooltip: 'Reverse route',
            onPressed: () {
              Navigator.of(sheetCtx).pop();
              _reverseRoute();
            },
          ),
          // Deactivate
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
            tooltip: 'Deactivate route',
            onPressed: () {
              Navigator.of(sheetCtx).pop();
              _clearCourse();
            },
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          'Waypoint ${(_routePointIndex ?? 0) + 1} of ${_routePointTotal ?? _routeCoords?.length ?? 0}',
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        // DTW / BRG / XTE with MetadataStore fallbacks
        Builder(builder: (_) {
          final store = widget.signalKService.metadataStore;
          final distMeta = store.get(_dsPath(_dsDtw)) ?? store.getByCategory('distance');
          final brgMeta = store.get(_dsPath(_dsBearing)) ?? store.get(_dsPath(_dsCog));
          final xteMeta = store.get(_dsPath(_dsXte)) ?? store.getByCategory('distance');

          String fmt(String path, dynamic meta, {int dec = 1}) {
            final d = widget.signalKService.getValue(path);
            if (d?.value == null || d!.value is! num) return '--';
            final raw = (d.value as num).toDouble();
            if (meta != null) return meta.format(raw, decimals: dec) as String;
            return raw.toStringAsFixed(dec);
          }

          return Row(children: [
            Text('DTW: ${fmt(_dsPath(_dsDtw), distMeta)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(width: 16),
            Text('BRG: ${fmt(_dsPath(_dsBearing), brgMeta, dec: 0)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(width: 16),
            Text('XTE: ${fmt(_dsPath(_dsXte), xteMeta)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ]);
        }),
        const Divider(color: Colors.white24, height: 20),
        // Waypoint list
        if (_routeCoords != null)
          ...List.generate(_routeCoords!.length, (i) {
            final isActive = i == _routePointIndex;
            final isPast = _routePointIndex != null && i < _routePointIndex!;
            final name = (_waypointNames != null && i < _waypointNames!.length && _waypointNames![i].isNotEmpty)
                ? _waypointNames![i]
                : 'WPT ${i + 1}';
            // Leg distance from previous waypoint
            String? legDist;
            if (i > 0) {
              final distMeta = widget.signalKService.metadataStore.getByCategory('distance');
              final prev = _routeCoords![i - 1];
              final cur = _routeCoords![i];
              final m = CpaUtils.calculateDistance(prev[1], prev[0], cur[1], cur[0]);
              final v = distMeta?.convert(m) ?? m;
              legDist = '${v.toStringAsFixed(1)} ${distMeta?.symbol ?? 'm'}';
            }
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                isActive ? Icons.flag : isPast ? Icons.check_circle : Icons.circle_outlined,
                color: isActive ? Colors.green : isPast ? Colors.white24 : Colors.white54,
                size: 20,
              ),
              title: Text(name, style: TextStyle(
                color: isActive ? Colors.green : isPast ? Colors.white38 : Colors.white,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              )),
              subtitle: legDist != null
                  ? Text(legDist, style: TextStyle(
                      color: isPast ? Colors.white24 : Colors.white38, fontSize: 11))
                  : null,
              trailing: !isPast && !isActive && _routePointIndex != null && i > _routePointIndex!
                  ? IconButton(
                      icon: const Icon(Icons.near_me, size: 18, color: Colors.white54),
                      tooltip: 'Skip to this waypoint',
                      onPressed: () => _skipToWaypoint(i),
                    )
                  : null,
            );
          }),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Route editing
  // ---------------------------------------------------------------------------

  void _showEditRouteDialog(BuildContext sheetCtx, String routeId, String currentName, Map<String, dynamic> routeData) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Rename Route', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Route name',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.green)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(sheetCtx);
              Navigator.pop(ctx);
              routeData['name'] = controller.text;
              await widget.signalKService.putResource('routes', routeId, routeData);
              if (mounted) {
                nav.pop();
                _showRouteManager();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteRouteDialog(BuildContext sheetCtx, String routeId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Delete Route', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete "$name"?\n\nThis cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(sheetCtx);
              Navigator.pop(ctx);
              await widget.signalKService.deleteResource('routes', routeId);
              if (mounted) {
                nav.pop();
                _showRouteManager();
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// Get the route ID from the active route href
  String? get _activeRouteId {
    if (_activeRouteHref == null) return null;
    return _activeRouteHref!.split('/').last;
  }

  /// Save current route coords/names to the server
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
          'coordinatesMeta': _waypointNames?.map((n) => {'name': n}).toList() ?? [],
        },
      },
    };
    await widget.signalKService.putResource('routes', routeId, routeData);
  }

  void _onWaypointDrag(int index, double lon, double lat) {
    if (_routeCoords == null || index < 0 || index >= _routeCoords!.length) return;
    _routeCoords![index] = [lon, lat];
    _pushRoute();
    _saveRouteToServer();
  }

  void _showWaypointEditDialog(int index) {
    if (_routeCoords == null || index < 0 || index >= _routeCoords!.length) return;
    final currentName = (_waypointNames != null && index < _waypointNames!.length)
        ? _waypointNames![index]
        : '';
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text('Waypoint ${index + 1}', style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Waypoint name',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.green)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Delete waypoint
              _routeCoords!.removeAt(index);
              _waypointNames?.removeAt(index);
              _pushRoute();
              _saveRouteToServer();
              if (mounted) setState(() {});
            },
            child: const Text('Delete Waypoint', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (_waypointNames != null && index < _waypointNames!.length) {
                _waypointNames![index] = controller.text;
              }
              _saveRouteToServer();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAddWaypointDialog(int afterIndex, double lon, double lat) {
    if (_routeCoords == null) return;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Add Waypoint', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Waypoint name (optional)',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.green)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              final insertAt = afterIndex + 1;
              _routeCoords!.insert(insertAt, [lon, lat]);
              _waypointNames?.insert(insertAt, controller.text);
              _pushRoute();
              _saveRouteToServer();
              if (mounted) setState(() {});
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _activateRoute(String routeId, {bool reverse = false}) async {
    final url = '${widget.signalKService.httpBaseUrl}'
        '/signalk/v2/api/vessels/self/navigation/course/activeRoute';
    try {
      await http.put(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (widget.signalKService.authToken?.token != null)
            'Authorization': 'Bearer ${widget.signalKService.authToken!.token}',
        },
        body: jsonEncode({
          'href': '/resources/routes/$routeId',
          'pointIndex': 0,
          'reverse': reverse,
          'arrivalCircle': 100,
        }),
      );
      _lastRoutePoll = DateTime(0);
      await _pollCourseAPI();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Activate failed: $e')));
      }
    }
  }

  Future<void> _reverseRoute() async {
    // Stop arrival monitor during reverse to prevent spurious arrival events
    _stopArrivalMonitor();
    final url = '${widget.signalKService.httpBaseUrl}'
        '/signalk/v2/api/vessels/self/navigation/course/activeRoute/reverse';
    try {
      await http.put(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (widget.signalKService.authToken?.token != null)
            'Authorization': 'Bearer ${widget.signalKService.authToken!.token}',
        },
        body: '{}',
      );
      // Jump to start of the new direction
      await _skipToWaypoint(0);
      _startArrivalMonitor();
    } catch (e) {
      _startArrivalMonitor(); // restart even on failure
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reverse failed: $e')));
      }
    }
  }

  Future<void> _clearCourse() async {
    final url = '${widget.signalKService.httpBaseUrl}'
        '/signalk/v2/api/vessels/self/navigation/course';
    try {
      await http.delete(
        Uri.parse(url),
        headers: {
          if (widget.signalKService.authToken?.token != null)
            'Authorization': 'Bearer ${widget.signalKService.authToken!.token}',
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Clear failed: $e')));
      }
    }
  }

  Future<void> _skipToWaypoint(int pointIndex) async {
    final url = '${widget.signalKService.httpBaseUrl}'
        '/signalk/v2/api/vessels/self/navigation/course/activeRoute/pointIndex';
    try {
      await http.put(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (widget.signalKService.authToken?.token != null)
            'Authorization': 'Bearer ${widget.signalKService.authToken!.token}',
        },
        body: jsonEncode({'value': pointIndex}),
      );
      _lastRoutePoll = DateTime(0);
      await _pollCourseAPI();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Skip failed: $e')));
      }
    }
  }

  Future<void> _fastForwardToNearest() async {
    if (_routeCoords == null) return;
    final posData = widget.signalKService.getValue(_dsPath(_dsPosition));
    if (posData?.value is! Map) return;
    final pos = posData!.value as Map;
    final vLat = (pos['latitude'] as num?)?.toDouble();
    final vLon = (pos['longitude'] as num?)?.toDouble();
    if (vLat == null || vLon == null) return;

    double minDist = double.infinity;
    int closestCoordIdx = 0;
    for (int i = 0; i < _routeCoords!.length; i++) {
      final d = CpaUtils.calculateDistance(vLat, vLon, _routeCoords![i][1], _routeCoords![i][0]);
      if (d < minDist) { minDist = d; closestCoordIdx = i; }
    }

    final pointIdx = _routeReversed
        ? _routeCoords!.length - 1 - closestCoordIdx
        : closestCoordIdx;
    await _skipToWaypoint(pointIdx);
  }

  // ---------------------------------------------------------------------------
  // Swipe coordination
  // ---------------------------------------------------------------------------

  void _resetSwipeBlock() {
    try {
      context.read<ValueNotifier<bool>>().value = false;
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  Widget _mapButton({
    required IconData icon,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          icon: Icon(icon, color: Colors.white, size: 20),
          onPressed: onPressed,
          tooltip: tooltip,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Stack(
      children: [
        Builder(builder: (context) {
          final depthMeta = widget.signalKService.metadataStore.getByCategory('depth');
          final factor = depthMeta?.convert(1.0) ?? 1.0;
          final symbol = depthMeta?.symbol ?? 'm';
          int? tilePort;
          try {
            final tileServer = context.read<ChartTileServerService>();
            if (tileServer.isRunning) tilePort = tileServer.port;
          } catch (_) {}
          return ChartWebView(
            baseUrl: widget.signalKService.httpBaseUrl,
            authToken: widget.signalKService.authToken?.token,
            onReady: _onWebViewReady,
            onAutoFollowChanged: _onAutoFollowChanged,
            onAISVesselClick: _onAISVesselClick,
            onWaypointDrag: _onWaypointDrag,
            onWaypointLongPress: _showWaypointEditDialog,
            onRouteLineAdd: _showAddWaypointDialog,
            onRulerUpdate: _onRulerUpdate,
            onViewportChanged: _onViewportChanged,
            localTileServerPort: tilePort,
            layers: _layers,
            depthUnit: symbol,
            depthConversionFactor: factor,
          );
        }),
        ListenableBuilder(
          listenable: widget.signalKService,
          builder: (context, _) => _buildHUD(),
        ),
        // Map controls — top right
        Positioned(
          top: 8,
          right: 8,
          child: Column(
            children: [
              _mapButton(
                icon: _viewMode == 'north-up'
                    ? Icons.navigation_outlined
                    : Icons.navigation,
                onPressed: _toggleViewMode,
                tooltip: _viewMode == 'north-up' ? 'Heading up' : 'North up',
              ),
              _mapButton(
                icon: _autoFollow ? Icons.my_location : Icons.location_searching,
                onPressed: _autoFollow ? _disableAutoFollow : _reCenter,
                tooltip: _autoFollow ? 'Snap to vessel (on)' : 'Snap to vessel (off)',
              ),
              _mapButton(
                icon: _routeCoords != null ? Icons.route : Icons.alt_route,
                onPressed: _showRouteManager,
                tooltip: 'Routes',
              ),
              _mapButton(
                icon: _aisEnabled ? Icons.sailing : Icons.sailing_outlined,
                onPressed: () {
                  setState(() => _aisEnabled = !_aisEnabled);
                  if (_mapReady && _controller != null) _pushAISVessels();
                },
                tooltip: _aisEnabled ? 'AIS on' : 'AIS off',
              ),
              if (_aisEnabled) ...[
                _mapButton(
                  icon: _aisActiveOnly ? Icons.filter_alt : Icons.filter_alt_outlined,
                  onPressed: () {
                    setState(() => _aisActiveOnly = !_aisActiveOnly);
                    if (_mapReady && _controller != null) _pushAISVessels();
                  },
                  tooltip: _aisActiveOnly ? 'Active only' : 'All vessels',
                ),
                _mapButton(
                  icon: _aisShowPaths ? Icons.timeline : Icons.timeline_outlined,
                  onPressed: () {
                    setState(() => _aisShowPaths = !_aisShowPaths);
                    if (_mapReady && _controller != null) _pushAISVessels();
                  },
                  tooltip: _aisShowPaths ? 'Paths on' : 'Paths off',
                ),
              ],
              _mapButton(
                icon: Icons.layers,
                onPressed: _showLayersPanel,
                tooltip: 'Layers',
              ),
              _mapButton(
                icon: _rulerVisible ? Icons.straighten : Icons.straighten_outlined,
                onPressed: _toggleRuler,
                tooltip: 'Ruler',
              ),
              _mapButton(
                icon: Icons.download_outlined,
                onPressed: _showDownloadDialog,
                tooltip: 'Download charts',
              ),
            ],
          ),
        ),
        // Ruler info overlay
        if (_rulerVisible && _rulerDistM != null)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Builder(builder: (_) {
                final distMeta = widget.signalKService.metadataStore.getByCategory('distance');
                final dist = distMeta?.convert(_rulerDistM!) ?? _rulerDistM!;
                final distSym = distMeta?.symbol ?? 'm';
                final distStr = dist < 1
                    ? dist.toStringAsFixed(3)
                    : (dist < 10 ? dist.toStringAsFixed(2) : dist.toStringAsFixed(1));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 10, height: 10,
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text('${_rulerBearingFromRed?.toStringAsFixed(1) ?? '--'}°',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 10, height: 10,
                          decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text('${_rulerBearingFromBlue?.toStringAsFixed(1) ?? '--'}°',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('$distStr $distSym',
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                );
              }),
            ),
          ),
        // Tile freshness indicator
        Positioned(
          bottom: 52,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: switch (_viewportFreshness) {
                      TileFreshness.fresh => Colors.green,
                      TileFreshness.aging => Colors.yellow,
                      TileFreshness.stale => Colors.orange,
                      TileFreshness.uncached => widget.signalKService.isConnected
                          ? Colors.red
                          : Colors.grey,
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  switch (_viewportFreshness) {
                    TileFreshness.fresh => 'Fresh',
                    TileFreshness.aging => '15d+',
                    TileFreshness.stale => '30d+',
                    TileFreshness.uncached => widget.signalKService.isConnected
                        ? 'No cache'
                        : 'Offline',
                  },
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
        // Compass rose — heading-up mode only
        if (_viewMode == 'heading-up')
          Positioned(
            top: _rulerVisible ? 130 : 80,
            left: 8,
            child: ListenableBuilder(
              listenable: widget.signalKService,
              builder: (context, _) {
                final heading = _numValue(_dsPath(_dsHeading)) ?? 0.0;
                return Transform.rotate(
                  angle: -heading,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.6),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: CustomPaint(
                      painter: _CompassRosePainter(),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Compass Rose Painter
// =============================================================================

class _CompassRosePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 4;

    // North arrow (red)
    final northPaint = Paint()..color = Colors.red..style = PaintingStyle.fill;
    final northPath = Path()
      ..moveTo(center.dx, center.dy - r)
      ..lineTo(center.dx - 5, center.dy - 2)
      ..lineTo(center.dx + 5, center.dy - 2)
      ..close();
    canvas.drawPath(northPath, northPaint);

    // South arrow (white)
    final southPaint = Paint()..color = Colors.white54..style = PaintingStyle.fill;
    final southPath = Path()
      ..moveTo(center.dx, center.dy + r)
      ..lineTo(center.dx - 5, center.dy + 2)
      ..lineTo(center.dx + 5, center.dy + 2)
      ..close();
    canvas.drawPath(southPath, southPaint);

    // Cardinal tick marks (E, W)
    final tickPaint = Paint()..color = Colors.white54..strokeWidth = 1.5;
    canvas.drawLine(Offset(center.dx + r, center.dy), Offset(center.dx + r - 6, center.dy), tickPaint);
    canvas.drawLine(Offset(center.dx - r, center.dy), Offset(center.dx - r + 6, center.dy), tickPaint);

    // "N" label
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'N',
        style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(center.dx - textPainter.width / 2, center.dy - r + 10));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// =============================================================================
// Builder
// =============================================================================

class ChartPlotterBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'chart_plotter',
      name: 'Chart Plotter',
      description: 'Interactive chart plotter with S-57 charts, AIS, route, and nav data',
      category: ToolCategory.navigation,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: true,
        minPaths: 10,
        maxPaths: 10,
        styleOptions: const [],
        allowsUnitSelection: false,
        allowsVisibilityToggles: false,
        allowsTTL: false,
        slotDefinitions: const [
          SlotDefinition(roleLabel: 'Position', defaultPath: 'navigation.position'),
          SlotDefinition(roleLabel: 'Heading', defaultPath: 'navigation.headingTrue'),
          SlotDefinition(roleLabel: 'COG', defaultPath: 'navigation.courseOverGroundTrue'),
          SlotDefinition(roleLabel: 'SOG', defaultPath: 'navigation.speedOverGround'),
          SlotDefinition(roleLabel: 'Depth', defaultPath: 'environment.depth.belowTransducer'),
          SlotDefinition(roleLabel: 'Bearing to WP', defaultPath: 'navigation.course.calcValues.bearingTrue'),
          SlotDefinition(roleLabel: 'Cross Track Error', defaultPath: 'navigation.course.calcValues.crossTrackError'),
          SlotDefinition(roleLabel: 'Distance to WP', defaultPath: 'navigation.course.calcValues.distance'),
          SlotDefinition(roleLabel: 'Active Route', defaultPath: 'navigation.course.activeRoute'),
          SlotDefinition(roleLabel: 'Next Point', defaultPath: 'navigation.courseGreatCircle.nextPoint.position'),
        ],
      ),
      defaultWidth: 4,
      defaultHeight: 4,
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: const [],
      style: StyleConfig(
        customProperties: {
          'trailMinutes': 10,
          'showAIS': true,
          'showRoute': true,
          'hudPosition': 'bottom',
        },
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return ChartPlotterTool(
      config: config,
      signalKService: signalKService,
    );
  }
}

// =============================================================================
// Vessel lookup WebView (VesselFinder / MarineTraffic)
// =============================================================================

class _VesselLookupPage extends StatefulWidget {
  final String url;
  final String title;
  const _VesselLookupPage({required this.url, required this.title});

  @override
  State<_VesselLookupPage> createState() => _VesselLookupPageState();
}

class _VesselLookupPageState extends State<_VesselLookupPage> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _isLoading = true),
        onPageFinished: (_) => setState(() => _isLoading = false),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
