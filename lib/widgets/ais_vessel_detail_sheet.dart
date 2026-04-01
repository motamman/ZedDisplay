import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/ais_favorite.dart';
import '../models/cpa_alert_state.dart';
import '../services/ais_favorites_service.dart';
import '../services/dashboard_service.dart';
import '../services/find_home_target_service.dart';
import '../services/signalk_service.dart';
import '../utils/cpa_utils.dart';
import '../utils/ship_type_utils.dart' as ship_type;

/// Reusable AIS vessel detail bottom sheet.
///
/// Shows vessel identity, navigation data, CPA/TCPA, dimensions,
/// and action buttons (favorite, VesselFinder, Find Home tracking).
class AISVesselDetailSheet {
  /// Show the vessel detail sheet for [vesselId].
  ///
  /// [ownCogRad] and [ownSogMs] are the own vessel's COG/SOG in SI units,
  /// used for CPA/TCPA calculation.
  static void show(
    BuildContext context, {
    required SignalKService signalKService,
    required String vesselId,
    double? ownLat,
    double? ownLon,
    double? ownCogRad,
    double? ownSogMs,
  }) {
    final vessel = signalKService.aisVesselRegistry.vessels[vesselId];
    if (vessel == null) return;

    final store = signalKService.metadataStore;
    final cogMeta = store.getByCategory('angle');
    final sogMeta = store.getByCategory('speed');
    final hdgMeta = cogMeta; // heading uses same angle metadata
    final distMeta = store.getByCategory('distance');
    final lenMeta = store.getByCategory('length');

    String fmtAngle(double? rad) {
      if (rad == null) return '--';
      if (cogMeta != null) return cogMeta.format(rad, decimals: 1);
      return '${rad.toStringAsFixed(2)} rad';
    }
    String fmtSpeed(double? ms) {
      if (ms == null) return '--';
      if (sogMeta != null) return sogMeta.format(ms, decimals: 1);
      return '${ms.toStringAsFixed(1)} m/s';
    }
    String fmtHeading(double? rad) {
      if (rad == null) return '--';
      if (hdgMeta != null) return hdgMeta.format(rad, decimals: 1);
      return '${rad.toStringAsFixed(2)} rad';
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
    double? bearing, distance, cpa, tcpa;
    if (ownLat != null && ownLon != null && vessel.hasPosition) {
      bearing = CpaUtils.calculateBearing(ownLat, ownLon, vessel.latitude!, vessel.longitude!);
      distance = CpaUtils.calculateDistance(ownLat, ownLon, vessel.latitude!, vessel.longitude!);
      final result = CpaUtils.calculateCpaTcpa(
        bearingDeg: bearing,
        distanceM: distance,
        ownCogRad: ownCogRad,
        ownSogMs: ownSogMs ?? 0.0,
        targetCogRad: vessel.cogRad,
        targetSogMs: vessel.sogMs,
      );
      cpa = result?.cpa;
      tcpa = result?.tcpa;
      if (cpa != null && !cpa.isFinite) cpa = null;
      if (tcpa != null && !tcpa.isFinite) tcpa = null;
    }

    // Extra data from cache
    final cache = signalKService.latestData;
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
    final typeLabel = shipTypeName ?? ship_type.shipTypeLabel(vessel.aisShipType);
    final typeColor = ship_type.shipTypeColor(vessel.aisShipType, aisClass: vessel.aisClass);
    final heading = (vessel.headingTrueRad ?? vessel.cogRad ?? 0.0);

    const cpaDefaults = CpaAlertConfig();
    Color cpaColor(double? cpaM) {
      if (cpaM == null) return Colors.white;
      if (cpaM < cpaDefaults.alarmThresholdMeters) return Colors.red;
      if (cpaM < cpaDefaults.warnThresholdMeters) return Colors.orange;
      return Colors.white;
    }

    final vesselIcon = ship_type.shipTypeIcon(vessel.aisShipType, vessel.navState, sogMs: vessel.sogMs);

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
                          builder: (_) => VesselLookupPage(
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
                  _row('Bearing', '${bearing.toStringAsFixed(1)}°'),
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

  static Widget _typeChip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
  );

  static Widget _chip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
    child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.white54)),
  );

  static Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(title.toUpperCase(),
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white38, letterSpacing: 0.8)),
  );

  static Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13))),
      Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500))),
    ]),
  );

  static Widget _rowColored(String label, String value, Color valueColor) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13))),
      Expanded(child: Text(value, style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.w500))),
    ]),
  );

  static String _fmtTCPA(double seconds) {
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
}

/// Simple WebView page for VesselFinder / MarineTraffic lookups.
class VesselLookupPage extends StatefulWidget {
  final String url;
  final String title;
  const VesselLookupPage({super.key, required this.url, required this.title});

  @override
  State<VesselLookupPage> createState() => _VesselLookupPageState();
}

class _VesselLookupPageState extends State<VesselLookupPage> {
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
