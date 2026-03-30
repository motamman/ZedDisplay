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

  static const _navPaths = [
    'navigation.position',
    'navigation.headingTrue',
    'navigation.courseOverGroundTrue',
    'navigation.speedOverGround',
    'environment.depth.belowTransducer',
  ];

  static const _routePaths = [
    'navigation.course.calcValues.bearingTrue',
    'navigation.course.calcValues.crossTrackError',
    'navigation.course.calcValues.distance',
    'navigation.course.activeRoute',
    'navigation.courseGreatCircle.nextPoint.position',
  ];

  WebViewController? _controller;
  bool _mapReady = false;
  bool _autoFollow = true;
  bool _autoZoom = true;
  String _viewMode = 'north-up';
  DateTime _lastVesselPush = DateTime(0);
  DateTime _lastAISPush = DateTime(0);
  bool _hasLoadedAIS = false;

  // Route overlay
  String? _activeRouteHref;
  List<List<double>>? _routeCoords;
  List<String>? _waypointNames;
  int? _routePointIndex;
  int? _routePointTotal;
  RouteArrivalMonitor? _arrivalMonitor;
  StreamSubscription<RouteArrivalEvent>? _arrivalSub;

  // ---------------------------------------------------------------------------
  // Config accessors
  // ---------------------------------------------------------------------------

  String get _hudPosition =>
      widget.config.style.customProperties?['hudPosition'] as String? ??
      'bottom';

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    widget.signalKService.subscribeToPaths(
      [..._navPaths, ..._routePaths],
      ownerId: _ownerId,
    );
    widget.signalKService.addListener(_onSignalKUpdate);
    widget.signalKService.aisVesselRegistry.addListener(_onAISUpdate);
    _ensureAISLoaded();
  }

  @override
  void dispose() {
    _stopArrivalMonitor();
    widget.signalKService.aisVesselRegistry.removeListener(_onAISUpdate);
    widget.signalKService.removeListener(_onSignalKUpdate);
    _resetSwipeBlock();
    widget.signalKService.unsubscribeFromPaths(
      [..._navPaths, ..._routePaths],
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
  }

  void _onAutoFollowChanged(bool autoFollow, {bool? autoZoom}) {
    if (mounted) {
      setState(() {
        _autoFollow = autoFollow;
        if (autoZoom != null) _autoZoom = autoZoom;
      });
    }
  }

  void _onSignalKUpdate() {
    if (!_mapReady || _controller == null) return;
    // Re-load AIS on reconnect
    if (widget.signalKService.isConnected && !_hasLoadedAIS) {
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
    final posData = widget.signalKService.getValue('navigation.position');
    if (posData?.value is! Map) return;
    final pos = posData!.value as Map;
    final lat = (pos['latitude'] as num?)?.toDouble();
    final lon = (pos['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) return;

    final heading = _numValue('navigation.headingTrue');
    final cog = _numValue('navigation.courseOverGroundTrue');
    final sog = _numValue('navigation.speedOverGround');

    _controller!.runJavaScript(
      'updateVesselPosition($lat, $lon, ${heading ?? 'null'}, ${cog ?? 'null'}, ${sog ?? 0})',
    );
  }

  void _toggleViewMode() {
    final newMode = _viewMode == 'north-up' ? 'heading-up' : 'north-up';
    setState(() => _viewMode = newMode);
    _controller?.runJavaScript("setViewMode('$newMode')");
  }

  void _disableAutoFollow() {
    setState(() {
      _autoFollow = false;
      _autoZoom = false;
    });
    _controller?.runJavaScript('setAutoFollow(false)');
  }

  void _reCenter() {
    setState(() {
      _autoFollow = true;
      _autoZoom = true;
    });
    _controller?.runJavaScript('setAutoFollow(true)');
  }

  // ---------------------------------------------------------------------------
  // Active route
  // ---------------------------------------------------------------------------

  void _checkActiveRoute() {
    final data = widget.signalKService.getValue('navigation.course.activeRoute');
    if (data?.value is Map) {
      final m = data!.value as Map;
      final href = m['href'] as String?;
      _routePointIndex = m['pointIndex'] as int?;
      _routePointTotal = m['pointTotal'] as int?;

      if (href != null && href != _activeRouteHref) {
        _activeRouteHref = href;
        _fetchRoute(href);
        _startArrivalMonitor();
      }
    } else if (_activeRouteHref != null) {
      // Route deactivated
      _activeRouteHref = null;
      _routeCoords = null;
      _waypointNames = null;
      _routePointIndex = null;
      _routePointTotal = null;
      _stopArrivalMonitor();
      _controller?.runJavaScript('updateRoute(null)');
      if (mounted) setState(() {});
    }
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
    if (_routePointIndex! + 1 >= _routePointTotal!) return;

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
        body: jsonEncode({'value': _routePointIndex! + 1}),
      );
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
    final registry = widget.signalKService.aisVesselRegistry.vessels;
    final ownCogRad = _numValue('navigation.courseOverGroundTrue');
    final ownSogMs = _numValue('navigation.speedOverGround') ?? 0.0;

    // Own position for bearing/distance/CPA
    final posData = widget.signalKService.getValue('navigation.position');
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
        'projections': projections.map((p) => {'lat': p.lat, 'lon': p.lon}).toList(),
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
    final cogMeta = store.get('navigation.courseOverGroundTrue');
    final sogMeta = store.get('navigation.speedOverGround');
    final hdgMeta = store.get('navigation.headingTrue');
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
    final posData = widget.signalKService.getValue('navigation.position');
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
        ownCogRad: _numValue('navigation.courseOverGroundTrue'),
        ownSogMs: _numValue('navigation.speedOverGround') ?? 0.0,
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

  String _formatValue(String path, {int decimals = 1}) {
    final data = widget.signalKService.getValue(path);
    if (data?.value == null || data!.value is! num) return '--';
    final rawValue = (data.value as num).toDouble();
    final metadata = widget.signalKService.metadataStore.get(path);
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
            _hudItem('SOG', _formatValue('navigation.speedOverGround')),
            _hudItem('COG', _formatValue('navigation.courseOverGroundTrue', decimals: 0)),
            _hudItem('DPT', _formatValue('environment.depth.belowTransducer', decimals: 1)),
            _hudItem('DTW', _formatValue('navigation.course.calcValues.distance', decimals: 1)),
            _hudItem('BRG', _formatValue('navigation.course.calcValues.bearingTrue', decimals: 0)),
            _hudItem('XTE', _formatValue('navigation.course.calcValues.crossTrackError', decimals: 1)),
            if (_routeCoords != null &&
                _routePointIndex != null &&
                _routePointTotal != null &&
                _routePointIndex! + 1 < _routePointTotal!)
              GestureDetector(
                onTap: _advanceWaypoint,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.skip_next, color: Colors.white70, size: 24),
                ),
              ),
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
        ChartWebView(
          baseUrl: widget.signalKService.httpBaseUrl,
          authToken: widget.signalKService.authToken?.token,
          onReady: _onWebViewReady,
          onAutoFollowChanged: _onAutoFollowChanged,
          onAISVesselClick: _onAISVesselClick,
        ),
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
                icon: _autoFollow && _autoZoom
                    ? Icons.my_location
                    : Icons.location_searching,
                onPressed: _autoFollow && _autoZoom ? _disableAutoFollow : _reCenter,
                tooltip: _autoFollow && _autoZoom
                    ? 'Auto-follow on (tap to disable)'
                    : 'Re-center & auto-follow',
              ),
            ],
          ),
        ),
      ],
    );
  }
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
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
        styleOptions: const [],
        allowsUnitSelection: false,
        allowsVisibilityToggles: false,
        allowsTTL: false,
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
