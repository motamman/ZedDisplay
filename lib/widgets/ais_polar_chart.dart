import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'dart:math' as math;
import '../services/signalk_service.dart';

/// AIS Polar Chart that displays nearby vessels relative to own position
///
/// Shows:
/// - Own vessel at center (0,0)
/// - Other vessels plotted at relative bearing and distance
/// - Compass-style display with 8 cardinal directions
class AISPolarChart extends StatefulWidget {
  final SignalKService signalKService;
  final String positionPath; // Path to own position
  final String cogPath;      // Path to own COG for CPA calculation
  final String sogPath;      // Path to own SOG for CPA calculation
  final String title;
  final Color? vesselColor;
  final bool showLabels;
  final bool showGrid;
  final int pruneMinutes;    // Minutes before vessel is removed from display
  final bool colorByShipType; // Color vessels by AIS ship type
  final bool showProjectedPositions; // Show projected course lines

  const AISPolarChart({
    super.key,
    required this.signalKService,
    this.positionPath = 'navigation.position',
    this.cogPath = 'navigation.courseOverGroundTrue',
    this.sogPath = 'navigation.speedOverGround',
    this.title = 'AIS Vessels',
    this.vesselColor,
    this.showLabels = true,
    this.showGrid = true,
    this.pruneMinutes = 15,
    this.colorByShipType = true,
    this.showProjectedPositions = true,
  });

  @override
  State<AISPolarChart> createState() => _AISPolarChartState();
}

class _AISPolarChartState extends State<AISPolarChart>
    with AutomaticKeepAliveClientMixin {
  Timer? _highlightTimer;
  final List<_VesselPoint> _vessels = [];

  // Own position
  double? _ownLat;
  double? _ownLon;
  DateTime? _lastPositionUpdate;

  // Range control (stored in meters - SI unit)
  bool _autoRange = true;
  double _manualRange = 9260.0; // ~5 nautical miles in meters as default
  double _calculatedRange = 9260.0;

  // Highlighted vessel (for tap-to-highlight)
  String? _highlightedVesselMMSI;

  // Vessel details overlay (non-blocking, replaces modal bottom sheet)
  String? _detailsVesselMMSI;

  // Cache CPA/TCPA values per vessel to prevent disappearing
  final Map<String, ({double cpa, double tcpa})> _cachedCPA = {};

  // Map controller for centering on own vessel
  final MapController _mapController = MapController();


  @override
  bool get wantKeepAlive => true;

  bool _hasSubscribed = false;
  bool _hasLoadedAIS = false;
  bool _showMapView = false; // Toggle between polar chart and map view
  bool _mapAutoFollow = true; // Auto-follow own vessel on map
  bool _fullScreenRadar = false; // Full-screen radar/map mode
  bool _showVesselListOverlay = false; // Vessel list overlay in fullscreen

  // Throttle updates to prevent ANR on tablets
  DateTime? _lastUpdate;
  static const _updateThrottle = Duration(milliseconds: 500);

  /// Helper to get raw SI value from a data point
  double? _getRawValue(String path) {
    final dataPoint = widget.signalKService.getValue(path);
    if (dataPoint?.original is num) {
      return (dataPoint!.original as num).toDouble();
    }
    if (dataPoint?.value is num) {
      return (dataPoint!.value as num).toDouble();
    }
    return null;
  }

  /// Helper to get converted display value using MetadataStore
  double? _getConverted(String path, double? rawValue) {
    if (rawValue == null) return null;
    final metadata = widget.signalKService.metadataStore.get(path);
    return metadata?.convert(rawValue) ?? rawValue;
  }

  @override
  void initState() {
    super.initState();
    // Listen for own-vessel position updates from SignalK service
    widget.signalKService.addListener(_onServiceUpdate);

    // Listen to AIS vessel registry for AIS-specific updates
    widget.signalKService.aisVesselRegistry.addListener(_onAISUpdate);

    // Set registry prune timeout from widget parameter
    widget.signalKService.aisVesselRegistry.pruneMinutes = widget.pruneMinutes;

    // Subscribe to own vessel position - check if connected first
    _subscribeIfConnected();

    // Load existing vessels from REST, then subscribe for real-time updates
    // Only call once per widget instance
    if (!_hasLoadedAIS) {
      _hasLoadedAIS = true;
      widget.signalKService.loadAndSubscribeAISVessels();
    }

    // Fetch immediately on init
    _updateVesselData();
  }

  void _subscribeIfConnected() {
    if (!_hasSubscribed && widget.signalKService.isConnected) {
      widget.signalKService.subscribeToAutopilotPaths([widget.positionPath]);
      _hasSubscribed = true;
    }
  }

  void _onServiceUpdate() {
    if (!mounted) return;

    // Try to subscribe if we haven't yet (in case connection happened after init)
    _subscribeIfConnected();

    // Re-trigger AIS load after reconnect — the manager's _aisInitialLoadDone
    // was reset by disconnect(), but widget's _hasLoadedAIS survived
    if (widget.signalKService.isConnected &&
        widget.signalKService.aisVesselRegistry.count == 0 &&
        _hasLoadedAIS) {
      _hasLoadedAIS = false;
      widget.signalKService.loadAndSubscribeAISVessels();
      _hasLoadedAIS = true;
    }

    // Only update own-vessel position from service updates
    final positionData = widget.signalKService.getValue(widget.positionPath);
    if (positionData?.value is Map) {
      final positionMap = positionData!.value as Map<String, dynamic>;
      final lat = positionMap['latitude'];
      final lon = positionMap['longitude'];
      if (lat is num && lon is num) {
        final newLat = lat.toDouble();
        final newLon = lon.toDouble();
        final positionChanged = _ownLat != newLat || _ownLon != newLon;
        _ownLat = newLat;
        _ownLon = newLon;
        _lastPositionUpdate = positionData.timestamp;

        if (positionChanged && _mapAutoFollow && _showMapView) {
          _centerMapOnSelf();
        }
      }
    }
  }

  void _onAISUpdate() {
    if (!mounted) return;

    // Throttle updates to prevent ANR on tablets
    final now = DateTime.now();
    if (_lastUpdate != null && now.difference(_lastUpdate!) < _updateThrottle) {
      return;
    }
    _lastUpdate = now;

    _fetchNearbyVessels();
  }

  @override
  void dispose() {
    widget.signalKService.removeListener(_onServiceUpdate);
    widget.signalKService.aisVesselRegistry.removeListener(_onAISUpdate);
    _highlightTimer?.cancel();
    super.dispose();
  }

  void _highlightVessel(String mmsi) {
    setState(() {
      _highlightedVesselMMSI = mmsi;
      _detailsVesselMMSI = mmsi;
    });
    _highlightTimer?.cancel();
    if (_showMapView) {
      _centerMapOnVessel(mmsi);
    }
  }

  void _centerMapOnVessel(String mmsi) {
    final vessel = _vessels.cast<_VesselPoint?>().firstWhere(
      (v) => v!.mmsi == mmsi,
      orElse: () => null,
    );
    if (vessel != null && vessel.latitude != null && vessel.longitude != null) {
      _mapController.move(
        LatLng(vessel.latitude!, vessel.longitude!),
        _mapController.camera.zoom,
      );
      _mapAutoFollow = false;
    }
  }

  void _dismissVesselDetails() {
    setState(() {
      _detailsVesselMMSI = null;
      _highlightedVesselMMSI = null;
    });
  }

  /// Extract extra vessel data from the SignalK data cache
  Map<String, String> _getExtraVesselData(String mmsi) {
    final extra = <String, String>{};
    final cache = widget.signalKService.latestData;
    final prefix = 'vessels.$mmsi';

    // Callsign
    final comm = cache['$prefix.communication']?.value;
    if (comm is Map) {
      final callsign = comm['callsignVhf'] as String?;
      if (callsign != null) extra['Callsign'] = callsign;
    }

    // Destination
    final dest = cache['$prefix.navigation.destination.commonName']?.value;
    if (dest is String && dest.isNotEmpty) extra['Destination'] = dest;

    // Ship type name from server (richer than our local decode)
    final aisType = cache['$prefix.design.aisShipType']?.value;
    if (aisType is Map) {
      final typeName = aisType['name'] as String?;
      if (typeName != null) extra['Ship Type'] = typeName;
    }

    // Beam
    final beam = cache['$prefix.design.beam']?.value;
    if (beam is num) extra['Beam'] = _formatLength(beam.toDouble());

    // Length
    final length = cache['$prefix.design.length']?.value;
    if (length is Map) {
      final overall = length['overall'];
      if (overall is num) extra['Length'] = _formatLength(overall.toDouble());
    } else if (length is num) {
      extra['Length'] = _formatLength(length.toDouble());
    }

    // Draft
    final draft = cache['$prefix.design.draft']?.value;
    if (draft is Map) {
      final current = draft['current'];
      if (current is num) extra['Draft'] = _formatLength(current.toDouble());
    } else if (draft is num) {
      extra['Draft'] = _formatLength(draft.toDouble());
    }

    // AIS class
    final aisClass = cache['$prefix.sensors.ais.class']?.value;
    if (aisClass is String) extra['AIS Class'] = aisClass;

    // AIS status from sk-ais-status-plugin
    final aisStatus = cache['$prefix.sensors.ais.status']?.value;
    if (aisStatus is String) extra['AIS Status'] = aisStatus;

    // IMO / registrations
    final reg = cache['$prefix.registrations']?.value;
    if (reg is Map) {
      final imo = reg['imo'] as String?;
      if (imo != null) extra['IMO'] = imo;
    }

    return extra;
  }

  Widget _buildVesselDetailsOverlay(String mmsi) {
    final vessel = _vessels.cast<_VesselPoint?>().firstWhere(
      (v) => v!.mmsi == mmsi,
      orElse: () => null,
    );
    final extraData = _getExtraVesselData(mmsi);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white70 : Colors.black54;
    final sectionColor = isDark ? Colors.white38 : Colors.black38;

    final vesselName = vessel?.name ?? extraData['name'] ?? 'Unknown Vessel';
    final displayMMSI = _extractMMSI(mmsi);
    final shipTypeLabel = extraData['Ship Type'] ?? _getShipTypeLabel(vessel?.aisShipType);
    final typeColor = _getVesselTypeColor(vessel?.aisShipType, aisClass: vessel?.aisClass);
    final heading = vessel?.headingTrue ?? vessel?.cog ?? 0.0;
    final icon = vessel != null
        ? _getVesselIcon(vessel.aisShipType, vessel.navState, sogRaw: vessel.sogRaw)
        : Icons.navigation;

    // Build dimensions string
    String? dimensionsStr;
    final parts = <String>[];
    if (extraData.containsKey('Length') && extraData.containsKey('Beam')) {
      parts.add('${extraData['Length']!} x ${extraData['Beam']!}');
    } else {
      if (extraData.containsKey('Length')) parts.add(extraData['Length']!);
      if (extraData.containsKey('Beam')) parts.add('beam ${extraData['Beam']!}');
    }
    if (extraData.containsKey('Draft')) parts.add('draft ${extraData['Draft']!}');
    if (parts.isNotEmpty) dimensionsStr = parts.join(', ');

    return DraggableScrollableSheet(
      initialChildSize: 0.4,
      maxChildSize: 0.65,
      minChildSize: 0.15,
      snap: true,
      snapSizes: const [0.15, 0.4],
      builder: (_, scrollController) {
        return NotificationListener<DraggableScrollableNotification>(
          onNotification: (notification) {
            // Dismiss when dragged to minimum size
            if (notification.extent <= notification.minExtent) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _dismissVesselDetails();
              });
            }
            return false;
          },
          child: Container(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Header with icon and name
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Transform.rotate(
                      angle: heading * math.pi / 180,
                      child: Icon(icon, color: typeColor, size: 32,
                        shadows: [Shadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 2)],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vesselName,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'MMSI: $displayMMSI',
                            style: TextStyle(fontSize: 13, color: subtitleColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Ship type chip
                Wrap(
                  spacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: typeColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(shipTypeLabel, style: TextStyle(fontSize: 12, color: typeColor, fontWeight: FontWeight.w600)),
                    ),
                    if (extraData.containsKey('AIS Class'))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: subtitleColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('Class ${extraData['AIS Class']!}', style: TextStyle(fontSize: 12, color: subtitleColor)),
                      ),
                    if (extraData.containsKey('AIS Status'))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: subtitleColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(extraData['AIS Status']!, style: TextStyle(fontSize: 12, color: subtitleColor)),
                      ),
                  ],
                ),

                // Identity section
                if (extraData.containsKey('Callsign') || extraData.containsKey('IMO') || extraData.containsKey('Destination'))
                  ...[
                    _sectionHeader('Identity', sectionColor),
                    if (extraData.containsKey('Callsign'))
                      _detailRow('Callsign', extraData['Callsign']!, subtitleColor, textColor),
                    if (extraData.containsKey('IMO'))
                      _detailRow('IMO', extraData['IMO']!, subtitleColor, textColor),
                    if (extraData.containsKey('Destination'))
                      _detailRow('Destination', extraData['Destination']!, subtitleColor, textColor),
                  ],

                // Dimensions section
                if (dimensionsStr != null)
                  ...[
                    _sectionHeader('Dimensions', sectionColor),
                    _detailRow('Size', dimensionsStr, subtitleColor, textColor),
                  ],

                // Navigation section
                if (vessel != null) ...[
                  _sectionHeader('Navigation', sectionColor),
                  if (vessel.navState != null)
                    _detailRow('Nav Status', vessel.navState!, subtitleColor, textColor),
                  if (vessel.sogRaw != null)
                    _detailRow('SOG', '${_convertSpeed(vessel.sogRaw!).toStringAsFixed(1)} ${_getSpeedUnit()}', subtitleColor, textColor),
                  if (vessel.cog != null)
                    _detailRow('COG', '${vessel.cog!.toStringAsFixed(1)}${_getAngleSymbol()}', subtitleColor, textColor),
                  if (vessel.headingTrue != null)
                    _detailRow('Heading', '${vessel.headingTrue!.toStringAsFixed(1)}${_getAngleSymbol()}', subtitleColor, textColor),

                  // Relative section
                  _sectionHeader('Relative', sectionColor),
                  _detailRow('Bearing', '${vessel.bearing.toStringAsFixed(1)}${_getAngleSymbol()}', subtitleColor, textColor),
                  _detailRow('Distance', '${_convertDistance(vessel.distance).toStringAsFixed(2)} ${_getDistanceUnit()}', subtitleColor, textColor),
                  if (vessel.cpa != null)
                    _detailRow('CPA', '${_convertDistance(vessel.cpa!).toStringAsFixed(2)} ${_getDistanceUnit()}', subtitleColor, textColor),
                  if (vessel.tcpa != null && vessel.tcpa!.isFinite && vessel.tcpa! > 0)
                    _detailRow('TCPA', _formatTCPA(vessel.tcpa!), subtitleColor, textColor),

                  // Position section
                  _sectionHeader('Position', sectionColor),
                  if (vessel.latitude != null && vessel.longitude != null)
                    _detailRow('Lat/Lon', '${vessel.latitude!.toStringAsFixed(5)}, ${vessel.longitude!.toStringAsFixed(5)}', subtitleColor, textColor),
                  if (vessel.timestamp != null)
                    _detailRow('Last Update', '${_formatTimeSince(vessel.timestamp!)} ago', subtitleColor, textColor),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.8),
      ),
    );
  }

  Widget _detailRow(String label, String value, Color labelColor, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(fontSize: 13, color: labelColor)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: valueColor)),
          ),
        ],
      ),
    );
  }

  void _updateVesselData() {
    // Get own position - it's an object with latitude and longitude
    final positionData = widget.signalKService.getValue(widget.positionPath);

    if (positionData?.value is Map) {
      final positionMap = positionData!.value as Map<String, dynamic>;
      final lat = positionMap['latitude'];
      final lon = positionMap['longitude'];

      if (lat is num && lon is num) {
        _ownLat = lat.toDouble();
        _ownLon = lon.toDouble();
        _lastPositionUpdate = positionData.timestamp;
        _fetchNearbyVessels();
      }
    }
  }

  void _fetchNearbyVessels() {
    if (_ownLat == null || _ownLon == null) return;

    // Read directly from AIS vessel registry (indexed, already pruned)
    final registryVessels = widget.signalKService.aisVesselRegistry.vessels;

    // Build new vessel list
    final newVessels = <_VesselPoint>[];

    // Convert COG/heading from radians to degrees for display using MetadataStore
    final cogMetadata = widget.signalKService.metadataStore.get('navigation.courseOverGroundTrue');
    final headingMetadata = widget.signalKService.metadataStore.get('navigation.headingTrue');

    for (final entry in registryVessels.entries) {
      final vessel = entry.value;
      if (!vessel.hasPosition) continue;

      final lat = vessel.latitude!;
      final lon = vessel.longitude!;
      final bearing = _calculateBearing(_ownLat!, _ownLon!, lat, lon);
      final distance = _calculateDistance(_ownLat!, _ownLon!, lat, lon);

      // Convert COG from radians to display units (degrees) via MetadataStore
      final cogDisplay = vessel.cogRad != null
          ? (cogMetadata?.convert(vessel.cogRad!) ?? (vessel.cogRad! * 180 / math.pi))
          : null;

      // Convert heading from radians to display units (degrees) via MetadataStore
      final headingDisplay = vessel.headingTrueRad != null
          ? (headingMetadata?.convert(vessel.headingTrueRad!) ?? (vessel.headingTrueRad! * 180 / math.pi))
          : null;

      // Determine freshness: plugin status or timestamp-based
      final isLive = vessel.aisStatus == 'confirmed' ||
          (vessel.aisStatus == null && vessel.ageMinutes < 3);

      // Calculate CPA/TCPA — uses radians directly for trig
      final cpaTcpa = _calculateCPATCPAForVessel(
        bearing: bearing,
        distance: distance,
        vesselCogRad: vessel.cogRad,
        vesselSogMs: vessel.sogMs,
      );

      double? finalCpa;
      double? finalTcpa;

      if (cpaTcpa != null) {
        final previous = _cachedCPA[vessel.vesselId];
        if (previous != null) {
          final diff = (cpaTcpa.cpa - previous.cpa).abs();
          final pctChange = previous.cpa > 0 ? diff / previous.cpa : 1.0;

          if (diff < 50 && pctChange < 0.1) {
            finalCpa = previous.cpa;
            finalTcpa = previous.tcpa;
          } else {
            finalCpa = cpaTcpa.cpa;
            finalTcpa = cpaTcpa.tcpa;
            _cachedCPA[vessel.vesselId] = cpaTcpa;
          }
        } else {
          finalCpa = cpaTcpa.cpa;
          finalTcpa = cpaTcpa.tcpa;
          _cachedCPA[vessel.vesselId] = cpaTcpa;
        }
      } else {
        final previous = _cachedCPA[vessel.vesselId];
        if (previous != null) {
          finalCpa = previous.cpa;
          finalTcpa = previous.tcpa;
        }
      }

      newVessels.add(_VesselPoint(
        name: vessel.name,
        mmsi: vessel.vesselId,
        bearing: bearing,
        distance: distance,
        cog: cogDisplay,
        cogRad: vessel.cogRad,
        sogRaw: vessel.sogMs,
        isLive: isLive,
        timestamp: vessel.lastSeen,
        cpa: finalCpa,
        tcpa: finalTcpa,
        aisShipType: vessel.aisShipType,
        navState: vessel.navState,
        headingTrue: headingDisplay,
        latitude: lat,
        longitude: lon,
        aisClass: vessel.aisClass,
        aisStatus: vessel.aisStatus,
      ));
    }

    // Clean stale cache entries for vessels no longer in range
    final currentMMSIs = newVessels.map((v) => v.mmsi).toSet();
    _cachedCPA.removeWhere((key, _) => !currentMMSIs.contains(key));

    // Update state once with all vessels
    setState(() {
      _vessels.clear();
      _vessels.addAll(newVessels);

      // Auto-calculate range if in auto mode (distances are now in meters)
      if (_autoRange && _vessels.isNotEmpty) {
        final maxDistance = _vessels.map((v) => v.distance).reduce((a, b) => a > b ? a : b);
        _calculatedRange = maxDistance * 1.2; // 20% padding, auto-fit to farthest vessel
      }
    });
  }

  double _getDisplayRange() {
    return _autoRange ? _calculatedRange : _manualRange;
  }

  void _zoomIn() {
    if (_showMapView) {
      // Map view: zoom in on map
      final currentZoom = _mapController.camera.zoom;
      _mapController.move(_mapController.camera.center, currentZoom + 1);
    } else {
      // Polar view: decrease range (in meters)
      setState(() {
        _autoRange = false;
        _manualRange = (_manualRange / 1.5).clamp(50.0, double.infinity); // min 50m
      });
    }
  }

  void _zoomOut() {
    if (_showMapView) {
      // Map view: zoom out on map
      final currentZoom = _mapController.camera.zoom;
      _mapController.move(_mapController.camera.center, currentZoom - 1);
    } else {
      // Polar view: increase range (in meters)
      setState(() {
        _autoRange = false;
        _manualRange = (_manualRange * 1.5).clamp(50.0, double.infinity); // min 50m
      });
    }
  }

  void _toggleAutoRange() {
    setState(() {
      _autoRange = !_autoRange;
      if (_autoRange && _vessels.isNotEmpty) {
        // Recalculate range when switching to auto (in meters)
        final maxDistance = _vessels.map((v) => v.distance).reduce((a, b) => a > b ? a : b);
        _calculatedRange = maxDistance * 1.2; // 20% padding, auto-fit to farthest vessel
      }
    });
  }

  void _centerMapOnSelf() {
    if (_ownLat != null && _ownLon != null) {
      _mapController.move(LatLng(_ownLat!, _ownLon!), _mapController.camera.zoom);
    }
  }

  void _toggleAutoFollow() {
    setState(() {
      _mapAutoFollow = !_mapAutoFollow;
      // If enabling auto-follow, immediately center on vessel
      if (_mapAutoFollow) {
        _centerMapOnSelf();
      }
    });
  }

  /// Calculate bearing from point 1 to point 2 (in degrees, 0-360)
  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final lat1Rad = lat1 * math.pi / 180;
    final lat2Rad = lat2 * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;

    final y = math.sin(dLon) * math.cos(lat2Rad);
    final x = math.cos(lat1Rad) * math.sin(lat2Rad) -
        math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(dLon);

    final bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360; // Normalize to 0-360
  }

  /// Calculate distance between two points (in meters - SI unit)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    final R = 6371000.0; // Earth radius in meters
    final lat1Rad = lat1 * math.pi / 180;
    final lat2Rad = lat2 * math.pi / 180;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1Rad) * math.cos(lat2Rad) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return R * c; // Returns meters
  }

  /// Convert distance from meters to user's preferred unit using MetadataStore
  double _convertDistance(double meters) {
    final metadata = widget.signalKService.metadataStore.getByCategory('distance');
    if (metadata != null) return metadata.convert(meters) ?? meters;
    // Fallback to category-based conversion
    return widget.signalKService.convertByCategory('distance', meters) ?? meters;
  }

  /// Get distance unit symbol from MetadataStore
  String _getDistanceUnit() {
    final metadata = widget.signalKService.metadataStore.getByCategory('distance');
    if (metadata?.symbol != null) return metadata!.symbol!;
    return widget.signalKService.getSymbolForCategory('distance') ?? 'm';
  }

  /// Convert and format a length value (beam/length/draft) using MetadataStore
  String _formatLength(double meters) {
    final metadata = widget.signalKService.metadataStore.getByCategory('length');
    if (metadata != null) {
      final converted = metadata.convert(meters);
      return '${converted?.toStringAsFixed(1) ?? meters.toStringAsFixed(1)} ${metadata.symbol ?? 'm'}';
    }
    return '${meters.toStringAsFixed(1)} m';
  }

  /// Get angle symbol from MetadataStore
  String _getAngleSymbol() {
    return widget.signalKService.metadataStore.get(widget.cogPath)?.symbol ?? '°';
  }

  /// Convert speed from m/s to user's preferred unit using SOG path's displayUnits
  double _convertSpeed(double metersPerSecond) {
    final metadata = widget.signalKService.metadataStore.get(widget.sogPath);
    return metadata?.convert(metersPerSecond) ?? metersPerSecond;
  }

  /// Get speed unit symbol from SOG path's displayUnits
  String _getSpeedUnit() {
    final metadata = widget.signalKService.metadataStore.get(widget.sogPath);
    return metadata?.symbol ?? 'm/s';
  }

  /// Decode AIS ship type integer to human-readable label
  String _getShipTypeLabel(int? type) {
    if (type == null) return 'Unknown';
    if (type >= 20 && type <= 29) return 'Wing in Ground';
    if (type == 30) return 'Fishing';
    if (type == 31 || type == 32) return 'Towing';
    if (type == 33) return 'Dredging';
    if (type == 34) return 'Diving ops';
    if (type == 35) return 'Military';
    if (type == 36) return 'Sailing';
    if (type == 37) return 'Pleasure craft';
    if (type >= 40 && type <= 49) return 'High speed craft';
    if (type == 50) return 'Pilot vessel';
    if (type == 51) return 'SAR';
    if (type == 52) return 'Tug';
    if (type == 53) return 'Port tender';
    if (type == 55) return 'Law enforcement';
    if (type >= 60 && type <= 69) return 'Passenger';
    if (type >= 70 && type <= 79) return 'Cargo';
    if (type >= 80 && type <= 89) return 'Tanker';
    return 'Other ($type)';
  }

  /// Get vessel type color based on AIS ship type code (MarineTraffic convention)
  Color _getVesselTypeColor(int? aisShipType, {String? aisClass}) {
    if (aisShipType == null) {
      return aisClass == 'A' ? Colors.grey.shade400 : Colors.grey;
    }

    // Special case: sailing vessel
    if (aisShipType == 36) return Colors.purple;

    final firstDigit = aisShipType ~/ 10;
    switch (firstDigit) {
      case 1:
      case 2:
        return Colors.cyan; // Fishing, towing
      case 3:
        return Colors.orange; // Special craft (SAR, tug, pilot)
      case 4:
      case 5:
        return Colors.teal; // High-speed craft, special
      case 6:
        return Colors.blue; // Passenger
      case 7:
        return Colors.green.shade700; // Cargo
      case 8:
        return Colors.red.shade700; // Tanker
      default:
        return Colors.grey; // Other/unknown
    }
  }

  /// Get vessel icon based on motion state (type is conveyed by color)
  IconData _getVesselIcon(int? aisShipType, String? navState, {double? sogRaw}) {
    if (navState == 'anchored') return Icons.anchor;
    if (navState == 'moored') return Icons.local_parking;
    // Stationary: SOG ≈ 0 (< 0.1 m/s)
    if (sogRaw != null && sogRaw < 0.1) return Icons.circle;
    return Icons.navigation; // Moving chevron
  }

  /// Get freshness opacity based on plugin status or data age
  double _getFreshnessOpacity(DateTime? timestamp, {String? aisStatus}) {
    if (aisStatus != null) {
      switch (aisStatus) {
        case 'confirmed': return 1.0;
        case 'unconfirmed': return 0.5;
        case 'lost': return 0.2;
        default: return 0.2;
      }
    }
    // Timestamp fallback when plugin not installed
    if (timestamp == null) return 0.2;
    final ageMinutes = DateTime.now().difference(timestamp).inMinutes;
    if (ageMinutes < 3) return 1.0;
    if (ageMinutes < 7) return 0.6;
    if (ageMinutes < 10) return 0.3;
    return 0.2;
  }

  /// Check if vessel data is stale — plugin status or timestamp
  bool _isStale(DateTime? timestamp, {String? aisStatus}) {
    if (aisStatus != null) return aisStatus == 'lost' || aisStatus == 'remove';
    if (timestamp == null) return true;
    return DateTime.now().difference(timestamp).inMinutes >= 10;
  }

  /// Calculate projected positions for a vessel
  /// Returns list of (lat, lon, bearing, distance) for each time interval
  List<({double lat, double lon, double bearing, double distance})> _calculateProjectedPositions(
    _VesselPoint vessel,
  ) {
    if (vessel.sogRaw == null || vessel.sogRaw! < 0.1) return [];
    if (vessel.latitude == null || vessel.longitude == null) return [];
    if (vessel.cogRad == null) return [];

    final intervals = [30.0, 60.0, 900.0, 1800.0]; // 30s, 1m, 15m, 30m
    final results = <({double lat, double lon, double bearing, double distance})>[];
    final cogRad = vessel.cogRad!;

    for (final t in intervals) {
      final distanceM = vessel.sogRaw! * t;
      // Great-circle projection
      final lat1 = vessel.latitude! * math.pi / 180;
      final lon1 = vessel.longitude! * math.pi / 180;
      final angularDist = distanceM / 6371000.0;

      final lat2 = math.asin(
        math.sin(lat1) * math.cos(angularDist) +
        math.cos(lat1) * math.sin(angularDist) * math.cos(cogRad),
      );
      final lon2 = lon1 + math.atan2(
        math.sin(cogRad) * math.sin(angularDist) * math.cos(lat1),
        math.cos(angularDist) - math.sin(lat1) * math.sin(lat2),
      );

      final projLat = lat2 * 180 / math.pi;
      final projLon = lon2 * 180 / math.pi;

      // Calculate bearing/distance from own vessel to projected point
      final bearing = _calculateBearing(_ownLat!, _ownLon!, projLat, projLon);
      final distance = _calculateDistance(_ownLat!, _ownLon!, projLat, projLon);

      results.add((lat: projLat, lon: projLon, bearing: bearing, distance: distance));
    }

    return results;
  }

  void _toggleFullScreen() {
    setState(() {
      _fullScreenRadar = !_fullScreenRadar;
      if (!_fullScreenRadar) {
        _showVesselListOverlay = false;
      }
    });
  }

  void _toggleVesselListOverlay() {
    setState(() {
      _showVesselListOverlay = !_showVesselListOverlay;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!widget.signalKService.isConnected) {
      return Card(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              const Text('Not connected to SignalK server'),
            ],
          ),
        ),
      );
    }

    if (_ownLat == null || _ownLon == null) {
      return Card(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.gps_off, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              const Text('Waiting for GPS position...'),
            ],
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final vesselColor = widget.vesselColor ?? Colors.red;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 600;

            final radarWidget = _showMapView
                ? _buildMapView(vesselColor, isDark)
                : Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: _buildRadarChart(vesselColor, isDark),
                      ),
                    ),
                  );

            final listWidget = _buildVesselList(context, isDark);

            final radarClipped = ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: radarWidget,
            );
            final listClipped = ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: listWidget,
            );

            // Radar with overlay controls and vessel details
            final radarWithOverlay = Stack(
              children: [
                Positioned.fill(child: radarClipped),
                // Status badge (top left)
                Positioned(
                  top: 8,
                  left: 8,
                  child: _buildStatusBadge(context),
                ),
                // View controls (top right, below info button)
                Positioned(
                  top: 40,
                  right: 8,
                  child: _buildOverlayControls(context),
                ),
              ],
            );

            Widget layoutContent;

            if (_fullScreenRadar) {
              // Full-screen radar/map with optional vessel list overlay
              layoutContent = Stack(
                children: [
                  Positioned.fill(child: radarWithOverlay),
                  if (_showVesselListOverlay && _detailsVesselMMSI == null)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: constraints.maxHeight * 0.45,
                      child: Container(
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.85),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                          ),
                        ),
                        child: listWidget,
                      ),
                    ),
                ],
              );
            } else if (isWide) {
              // Side-by-side: radar left (50%), list right (50%)
              layoutContent = Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: radarWithOverlay),
                  const SizedBox(width: 8),
                  Expanded(child: listClipped),
                ],
              );
            } else {
              // Stacked: radar top (50%), list below (50%)
              layoutContent = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 1,
                    child: radarWithOverlay,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    flex: 1,
                    child: listClipped,
                  ),
                ],
              );
            }

            // Vessel details overlay rises from bottom of entire widget
            if (_detailsVesselMMSI != null) {
              return Stack(
                children: [
                  Positioned.fill(child: layoutContent),
                  Positioned.fill(
                    child: _buildVesselDetailsOverlay(_detailsVesselMMSI!),
                  ),
                ],
              );
            }
            return layoutContent;
          },
        ),
      ),
    );
  }

  /// Build status badge showing vessel count (top left overlay)
  Widget _buildStatusBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.directions_boat, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            '${_vessels.length} vessels',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  /// Build overlay controls (top right, vertical column like anchor alarm)
  Widget _buildOverlayControls(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Fullscreen toggle
        _buildOverlayButton(
          icon: _fullScreenRadar ? Icons.fullscreen_exit : Icons.fullscreen,
          onPressed: _toggleFullScreen,
        ),
        const SizedBox(height: 4),
        // Vessel list overlay (only when fullscreen)
        if (_fullScreenRadar)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _buildOverlayButton(
              icon: Icons.list,
              onPressed: _toggleVesselListOverlay,
              color: _showVesselListOverlay ? Colors.blue : null,
            ),
          ),
        // Map/Polar toggle
        _buildOverlayButton(
          icon: _showMapView ? Icons.radar : Icons.map,
          onPressed: () => setState(() => _showMapView = !_showMapView),
        ),
        const SizedBox(height: 8),
        // Zoom controls
        _buildOverlayButton(
          icon: Icons.add,
          onPressed: _zoomIn,
        ),
        const SizedBox(height: 4),
        _buildOverlayButton(
          icon: Icons.remove,
          onPressed: _zoomOut,
        ),
        // Auto-range toggle (polar view only)
        if (!_showMapView) ...[
          const SizedBox(height: 8),
          _buildOverlayButton(
            icon: _autoRange ? Icons.auto_fix_high : Icons.auto_fix_off,
            onPressed: _toggleAutoRange,
            color: _autoRange ? Colors.blue : null,
          ),
        ],
        // Map-specific controls
        if (_showMapView) ...[
          const SizedBox(height: 8),
          _buildOverlayButton(
            icon: Icons.my_location,
            onPressed: _centerMapOnSelf,
          ),
          const SizedBox(height: 4),
          _buildOverlayButton(
            icon: _mapAutoFollow ? Icons.gps_fixed : Icons.gps_not_fixed,
            onPressed: _toggleAutoFollow,
            color: _mapAutoFollow ? Colors.blue : null,
          ),
        ],
      ],
    );
  }

  Widget _buildOverlayButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(6),
      elevation: 2,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Icon(icon, color: color ?? Colors.black87, size: 18),
        ),
      ),
    );
  }

  Widget _buildRadarChart(Color vesselColor, bool isDark) {
    // Convert vessel positions to Cartesian coordinates
    final vesselPoints = _vesselsToCartesian();
    final displayRange = _getDisplayRange();

    // Expand axis range to accommodate labels (labels are at 1.15 * range)
    final axisRange = displayRange * 1.25;

    // Build vessel annotations (replaces ScatterSeries for per-point rotation)
    final vesselAnnotations = <CartesianChartAnnotation>[];
    for (final point in vesselPoints) {
      final isHighlighted = point.mmsi == _highlightedVesselMMSI;
      final heading = point.heading ?? 0.0;
      final icon = _getVesselIcon(point.aisShipType, point.navState, sogRaw: point.sogRaw);
      final typeColor = point.color;
      final opacity = point.freshnessOpacity;

      final stale = _isStale(point.timestamp, aisStatus: point.aisStatus);
      final iconSize = isHighlighted ? 40.0 : 32.0;
      final iconWidget = Transform.rotate(
        angle: heading * math.pi / 180,
        child: Icon(
          icon,
          color: isHighlighted
              ? Colors.yellow
              : typeColor.withValues(alpha: opacity),
          size: iconSize,
          shadows: isHighlighted
              ? [const Shadow(color: Colors.orange, blurRadius: 4)]
              : null,
        ),
      );

      vesselAnnotations.add(CartesianChartAnnotation(
        widget: GestureDetector(
          onTap: () => _highlightVessel(point.mmsi),
          child: stale && !isHighlighted
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    iconWidget,
                    Icon(Icons.close, color: Colors.red, size: iconSize * 0.8),
                  ],
                )
              : iconWidget,
        ),
        coordinateUnit: CoordinateUnit.point,
        x: point.x,
        y: point.y,
      ));
    }

    // Build projected position line series
    final projectionSeries = <CartesianSeries>[];
    if (!widget.showProjectedPositions) {
      // Skip projection calculations
    } else {
    // Limit to closest ~20 moving vessels within display range
    final movingVessels = _vessels
        .where((v) => v.sogRaw != null && v.sogRaw! > 0.1 && v.distance <= displayRange)
        .toList()
      ..sort((a, b) => a.distance.compareTo(b.distance));
    final limitedVessels = movingVessels.take(20);

    for (final vessel in limitedVessels) {
      final projections = _calculateProjectedPositions(vessel);
      if (projections.isEmpty) continue;

      final typeColor = _getVesselTypeColor(vessel.aisShipType, aisClass: vessel.aisClass);
      final isHighlighted = vessel.mmsi == _highlightedVesselMMSI;

      // Build line from vessel position through projected points
      final vesselAngle = (vessel.bearing - 90) * math.pi / 180;
      final vesselX = vessel.distance * math.cos(vesselAngle);
      final vesselY = vessel.distance * math.sin(vesselAngle);

      final linePoints = <_CartesianPoint>[
        _CartesianPoint(x: vesselX, y: vesselY, label: '', mmsi: ''),
      ];

      for (final proj in projections) {
        final projAngle = (proj.bearing - 90) * math.pi / 180;
        final projX = proj.distance * math.cos(projAngle);
        final projY = proj.distance * math.sin(projAngle);
        linePoints.add(_CartesianPoint(x: projX, y: projY, label: '', mmsi: ''));
      }

      projectionSeries.add(LineSeries<_CartesianPoint, double>(
        dataSource: linePoints,
        xValueMapper: (_CartesianPoint point, _) => point.x,
        yValueMapper: (_CartesianPoint point, _) => point.y,
        color: isHighlighted ? Colors.yellow.withValues(alpha: 0.7) : typeColor.withValues(alpha: 0.4),
        width: isHighlighted ? 2 : 1,
        dashArray: const <double>[4, 3],
        animationDuration: 0,
      ));

      // Add growing scatter dots at each projected position
      const projectionDotSizes = [4.0, 6.0, 10.0, 14.0];
      for (var i = 0; i < projections.length && i < projectionDotSizes.length; i++) {
        final proj = projections[i];
        final projAngle = (proj.bearing - 90) * math.pi / 180;
        final projX = proj.distance * math.cos(projAngle);
        final projY = proj.distance * math.sin(projAngle);
        final dotColor = isHighlighted ? Colors.yellow.withValues(alpha: 0.8) : typeColor.withValues(alpha: 0.5);
        projectionSeries.add(ScatterSeries<_CartesianPoint, double>(
          dataSource: [_CartesianPoint(x: projX, y: projY, label: '', mmsi: '')],
          xValueMapper: (_CartesianPoint point, _) => point.x,
          yValueMapper: (_CartesianPoint point, _) => point.y,
          color: dotColor,
          markerSettings: MarkerSettings(
            isVisible: true,
            width: projectionDotSizes[i],
            height: projectionDotSizes[i],
            shape: DataMarkerType.circle,
            borderWidth: 0,
            color: dotColor,
          ),
          animationDuration: 0,
        ));
      }
    }
    } // end showProjectedPositions

    return SfCartesianChart(
      plotAreaBackgroundColor: Colors.transparent,
      margin: const EdgeInsets.all(5),
      primaryXAxis: NumericAxis(
        minimum: -axisRange,
        maximum: axisRange,
        isVisible: false,
        majorGridLines: const MajorGridLines(width: 0),
      ),
      primaryYAxis: NumericAxis(
        minimum: -axisRange,
        maximum: axisRange,
        isVisible: false,
        majorGridLines: const MajorGridLines(width: 0),
        isInversed: true, // Flip Y-axis so North is at top
      ),
      plotAreaBorderWidth: 0,
      annotations: [
        if (widget.showLabels) ..._buildCompassAnnotations(displayRange, isDark),
        ..._buildRangeLabels(displayRange, isDark),
        ...vesselAnnotations,
      ],
      series: <CartesianSeries>[
        // Circular grid
        if (widget.showGrid)
          ..._buildGridSeries(displayRange, isDark),
        // Center point (own vessel)
        ScatterSeries<_CartesianPoint, double>(
          dataSource: [_CartesianPoint(x: 0, y: 0, label: 'Own', mmsi: 'self', color: Colors.green)],
          xValueMapper: (_CartesianPoint point, _) => point.x,
          yValueMapper: (_CartesianPoint point, _) => point.y,
          color: Colors.green,
          animationDuration: 0,
          markerSettings: const MarkerSettings(
            height: 12,
            width: 12,
            shape: DataMarkerType.circle,
            borderColor: Colors.white,
            borderWidth: 2,
          ),
        ),
        // Projected position lines
        ...projectionSeries,
      ],
    );
  }

  /// Build circular grid lines as chart series
  List<CartesianSeries> _buildGridSeries(double maxRange, bool isDark) {
    final gridColor = isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.15);
    final radialColor = isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.2);

    final series = <CartesianSeries>[];

    // Concentric circles (4 rings)
    for (int i = 1; i <= 4; i++) {
      final radius = maxRange / 4 * i;
      final circlePoints = <_CartesianPoint>[];

      for (int angle = 0; angle <= 360; angle += 5) {
        final angleRad = angle * math.pi / 180;
        circlePoints.add(_CartesianPoint(
          x: radius * math.cos(angleRad),
          y: radius * math.sin(angleRad),
          label: '',
          mmsi: '',
        ));
      }

      series.add(LineSeries<_CartesianPoint, double>(
        dataSource: circlePoints,
        xValueMapper: (_CartesianPoint point, _) => point.x,
        yValueMapper: (_CartesianPoint point, _) => point.y,
        color: gridColor,
        width: 1,
        animationDuration: 0,
      ));
    }

    // Radial lines (16 directions)
    for (int i = 0; i < 16; i++) {
      final angle = i * math.pi / 8 - math.pi / 2; // Start from North
      series.add(LineSeries<_CartesianPoint, double>(
        dataSource: [
          _CartesianPoint(x: 0, y: 0, label: '', mmsi: ''),
          _CartesianPoint(
            x: maxRange * math.cos(angle),
            y: maxRange * math.sin(angle),
            label: '',
            mmsi: '',
          ),
        ],
        xValueMapper: (_CartesianPoint point, _) => point.x,
        yValueMapper: (_CartesianPoint point, _) => point.y,
        color: radialColor,
        width: 1,
        animationDuration: 0,
      ));
    }

    return series;
  }

  /// Build map view with OpenStreetMap + OpenSeaMap overlay
  Widget _buildMapView(Color vesselColor, bool isDark) {
    if (_ownLat == null || _ownLon == null) {
      return const Center(child: Text('Waiting for position...'));
    }

    // Get own vessel heading/COG for arrow rotation (client-side conversion from radians to degrees)
    // Prefer COG over heading, fallback to headingMagnetic
    double? ownHeading;
    final cogTrueRaw = _getRawValue('navigation.courseOverGroundTrue');
    final cogTrue = _getConverted('navigation.courseOverGroundTrue', cogTrueRaw);
    final cogMagneticRaw = _getRawValue('navigation.courseOverGroundMagnetic');
    final cogMagnetic = _getConverted('navigation.courseOverGroundMagnetic', cogMagneticRaw);
    final headingMagneticRaw = _getRawValue('navigation.headingMagnetic');
    final headingMagnetic = _getConverted('navigation.headingMagnetic', headingMagneticRaw);
    ownHeading = cogTrue ?? cogMagnetic ?? headingMagnetic ?? 0.0;

    // Calculate bounds to fit all vessels
    double minLat = _ownLat!;
    double maxLat = _ownLat!;
    double minLon = _ownLon!;
    double maxLon = _ownLon!;

    for (final vessel in _vessels) {
      if (vessel.latitude != null && vessel.longitude != null) {
        minLat = math.min(minLat, vessel.latitude!);
        maxLat = math.max(maxLat, vessel.latitude!);
        minLon = math.min(minLon, vessel.longitude!);
        maxLon = math.max(maxLon, vessel.longitude!);
      }
    }

    // Add padding to bounds
    final latPadding = (maxLat - minLat) * 0.1;
    final lonPadding = (maxLon - minLon) * 0.1;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: LatLng(_ownLat!, _ownLon!),
        initialZoom: 12,
        minZoom: 5,
        maxZoom: 18,
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds(
            LatLng(minLat - latPadding, minLon - lonPadding),
            LatLng(maxLat + latPadding, maxLon + lonPadding),
          ),
          padding: const EdgeInsets.all(50),
        ),
        onPositionChanged: (position, hasGesture) {
          // Disable auto-follow when user manually pans/drags the map
          if (hasGesture && _mapAutoFollow) {
            setState(() {
              _mapAutoFollow = false;
            });
          }
        },
      ),
      children: [
        // OpenStreetMap base layer
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.zennora.signalk',
        ),
        // OpenSeaMap overlay
        TileLayer(
          urlTemplate: 'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.zennora.signalk',
        ),
        // Projected position polylines
        if (widget.showProjectedPositions)
          PolylineLayer(
            polylines: [
              ..._vessels
                  .where((v) => v.sogRaw != null && v.sogRaw! > 0.1 && v.latitude != null && v.longitude != null)
                  .take(20)
                  .map((vessel) {
                final projections = _calculateProjectedPositions(vessel);
                if (projections.isEmpty) return null;

                final typeColor = _getVesselTypeColor(vessel.aisShipType, aisClass: vessel.aisClass);
                final isHighlighted = vessel.mmsi == _highlightedVesselMMSI;
                return Polyline(
                  points: [
                    LatLng(vessel.latitude!, vessel.longitude!),
                    ...projections.map((p) => LatLng(p.lat, p.lon)),
                  ],
                  color: isHighlighted ? Colors.yellow.withValues(alpha: 0.9) : typeColor.withValues(alpha: 0.8),
                  strokeWidth: isHighlighted ? 4 : 3,
                  pattern: const StrokePattern.dotted(),
                );
              }).whereType<Polyline>(),
            ],
          ),
        // Vessel markers
        MarkerLayer(
          markers: [
            // Own vessel (green arrow, larger than others)
            Marker(
              point: LatLng(_ownLat!, _ownLon!),
              width: 44,
              height: 44,
              child: Transform.rotate(
                angle: ownHeading * math.pi / 180, // Convert degrees to radians
                child: Icon(
                  Icons.navigation,
                  color: Colors.green,
                  size: 38,
                  shadows: [Shadow(color: Colors.black, blurRadius: 3)],
                ),
              ),
            ),
            // Other vessels
            ..._vessels.map((vessel) {
              if (vessel.latitude == null || vessel.longitude == null) return null;

              final lat = vessel.latitude!;
              final lon = vessel.longitude!;

              // Prefer headingTrue over COG for rotation (display degrees)
              final heading = vessel.headingTrue ?? vessel.cog ?? 0.0;
              final isHighlighted = vessel.mmsi == _highlightedVesselMMSI;
              final typeColor = widget.colorByShipType
                  ? _getVesselTypeColor(vessel.aisShipType, aisClass: vessel.aisClass)
                  : _getVesselFreshnessColor(vessel.timestamp);
              final freshnessOpacity = widget.colorByShipType
                  ? _getFreshnessOpacity(vessel.timestamp, aisStatus: vessel.aisStatus)
                  : 1.0;
              final icon = _getVesselIcon(vessel.aisShipType, vessel.navState, sogRaw: vessel.sogRaw);
              final stale = _isStale(vessel.timestamp, aisStatus: vessel.aisStatus);
              final iconSize = isHighlighted ? 48.0 : 32.0;
              final iconWidget = Transform.rotate(
                angle: heading * math.pi / 180,
                child: Icon(
                  icon,
                  color: isHighlighted
                      ? Colors.yellow
                      : typeColor,
                  size: iconSize,
                  shadows: [
                    Shadow(
                      color: isHighlighted ? Colors.orange : Colors.black,
                      blurRadius: isHighlighted ? 6 : 3,
                    ),
                  ],
                ),
              );

              return Marker(
                point: LatLng(lat, lon),
                width: isHighlighted ? 56 : 40,
                height: isHighlighted ? 56 : 40,
                child: GestureDetector(
                  onTap: () => _highlightVessel(vessel.mmsi),
                  child: stale && !isHighlighted
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            iconWidget,
                            Icon(Icons.close, color: Colors.red, size: iconSize * 0.8),
                          ],
                        )
                      : iconWidget,
                ),
              );
            }).whereType<Marker>(),
            // Projected position tick marks
            if (widget.showProjectedPositions)
              ..._vessels
                  .where((v) => v.sogRaw != null && v.sogRaw! > 0.1 && v.latitude != null && v.longitude != null)
                  .take(20)
                  .expand((vessel) {
                final projections = _calculateProjectedPositions(vessel);
                final typeColor = _getVesselTypeColor(vessel.aisShipType, aisClass: vessel.aisClass);
                final isHighlighted = vessel.mmsi == _highlightedVesselMMSI;
                const projectionDotSizes = [6.0, 10.0, 16.0, 22.0];
                return projections.indexed.map((indexedProj) {
                  final (i, p) = indexedProj;
                  final size = i < projectionDotSizes.length ? projectionDotSizes[i] : 10.0;
                  final tapSize = math.max(size, 24.0);
                  return Marker(
                    point: LatLng(p.lat, p.lon),
                    width: tapSize,
                    height: tapSize,
                    child: GestureDetector(
                      onTap: () => _highlightVessel(vessel.mmsi),
                      child: Center(
                        child: Container(
                          width: size,
                          height: size,
                          decoration: BoxDecoration(
                            color: isHighlighted ? Colors.yellow.withValues(alpha: 0.9) : typeColor.withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isHighlighted ? Colors.orange : Colors.black54,
                              width: isHighlighted ? 1.0 : 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                });
              }),
          ],
        ),
      ],
    );
  }

  /// Build compass label annotations
  List<CartesianChartAnnotation> _buildCompassAnnotations(double maxRange, bool isDark) {
    // 16 compass directions
    final labels = [
      'N', 'NNE', 'NE', 'ENE',
      'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW',
      'W', 'WNW', 'NW', 'NNW'
    ];
    final annotations = <CartesianChartAnnotation>[];

    for (int i = 0; i < 16; i++) {
      final angle = i * math.pi / 8 - math.pi / 2; // Start from North
      final labelRadius = maxRange * 1.15; // 15% beyond max
      final x = labelRadius * math.cos(angle);
      final y = labelRadius * math.sin(angle);

      annotations.add(CartesianChartAnnotation(
        widget: Text(
          labels[i],
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        coordinateUnit: CoordinateUnit.point,
        x: x,
        y: y,
      ));
    }

    return annotations;
  }

  /// Build range labels on the circles (maxRange is in meters)
  List<CartesianChartAnnotation> _buildRangeLabels(double maxRange, bool isDark) {
    final annotations = <CartesianChartAnnotation>[];

    // Add distance labels at the top (North) of each circle
    for (int i = 1; i <= 4; i++) {
      final rangeMeters = maxRange / 4 * i;
      final rangeConverted = _convertDistance(rangeMeters);

      annotations.add(CartesianChartAnnotation(
        widget: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            rangeConverted.toStringAsFixed(1),
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        coordinateUnit: CoordinateUnit.point,
        x: 0,
        y: rangeMeters,
      ));
    }

    return annotations;
  }

  /// Convert vessel positions from polar to Cartesian
  List<_CartesianPoint> _vesselsToCartesian() {
    return _vessels.map((vessel) {
      // Convert bearing to radians (0° = North, 90° = East)
      final angleRad = (vessel.bearing - 90) * math.pi / 180;

      final x = vessel.distance * math.cos(angleRad);
      final y = vessel.distance * math.sin(angleRad);

      final color = widget.colorByShipType
          ? _getVesselTypeColor(vessel.aisShipType, aisClass: vessel.aisClass)
          : _getVesselFreshnessColor(vessel.timestamp);

      return _CartesianPoint(
        x: x,
        y: y,
        label: vessel.name ?? _extractMMSI(vessel.mmsi),
        mmsi: vessel.mmsi,
        color: color,
        heading: vessel.headingTrue ?? vessel.cog,
        aisShipType: vessel.aisShipType,
        navState: vessel.navState,
        sogRaw: vessel.sogRaw,
        timestamp: vessel.timestamp,
        freshnessOpacity: widget.colorByShipType
            ? _getFreshnessOpacity(vessel.timestamp, aisStatus: vessel.aisStatus)
            : 1.0,
        aisClass: vessel.aisClass,
        aisStatus: vessel.aisStatus,
      );
    }).toList();
  }

  /// Build vessel list
  Widget _buildVesselList(BuildContext context, bool isDark) {
    if (_vessels.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'No vessels in range',
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
          ),
        ),
      );
    }

    // Sort by distance
    final sortedVessels = List<_VesselPoint>.from(_vessels)
      ..sort((a, b) => a.distance.compareTo(b.distance));

    // Calculate time since last update
    String lastUpdateText = 'No data';
    if (_lastPositionUpdate != null) {
      final elapsed = DateTime.now().difference(_lastPositionUpdate!);
      if (elapsed.inSeconds < 60) {
        lastUpdateText = '${elapsed.inSeconds}s ago';
      } else if (elapsed.inMinutes < 60) {
        lastUpdateText = '${elapsed.inMinutes}m ago';
      } else {
        lastUpdateText = '${elapsed.inHours}h ago';
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
            child: Text(
              'Last update: $lastUpdateText',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
            itemCount: sortedVessels.length,
            itemBuilder: (context, index) {
              final vessel = sortedVessels[index];
              // Use cached CPA/TCPA values from vessel
              final cpa = vessel.cpa;
              final tcpa = vessel.tcpa;

              // Type-based color with freshness opacity (or plain freshness color)
              final typeColor = widget.colorByShipType
                  ? _getVesselTypeColor(vessel.aisShipType, aisClass: vessel.aisClass)
                  : _getVesselFreshnessColor(vessel.timestamp);
              final freshnessOpacity = widget.colorByShipType
                  ? _getFreshnessOpacity(vessel.timestamp, aisStatus: vessel.aisStatus)
                  : 1.0;
              final displayColor = typeColor.withValues(alpha: freshnessOpacity);
              final vesselIcon = _getVesselIcon(vessel.aisShipType, vessel.navState, sogRaw: vessel.sogRaw);
              final stale = _isStale(vessel.timestamp, aisStatus: vessel.aisStatus);
              final iconWidget = Transform.rotate(
                angle: ((vessel.headingTrue ?? vessel.cog ?? 0.0) * math.pi / 180),
                child: Icon(
                  vesselIcon,
                  color: displayColor,
                  size: 20,
                ),
              );

              return ListTile(
                dense: true,
                onTap: () => _highlightVessel(vessel.mmsi),
                leading: stale
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          iconWidget,
                          const Icon(Icons.close, color: Colors.red, size: 16),
                        ],
                      )
                    : iconWidget,
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        vessel.name ?? _extractMMSI(vessel.mmsi),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: displayColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (vessel.timestamp != null)
                      Text(
                        _formatTimeSince(vessel.timestamp!),
                        style: TextStyle(
                          fontSize: 10,
                          color: typeColor.withValues(alpha: freshnessOpacity * 0.7),
                        ),
                      ),
                  ],
                ),
                subtitle: Row(
                  children: [
                    Text(
                      '${_convertDistance(vessel.distance).toStringAsFixed(1)}${_getDistanceUnit()}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    const SizedBox(width: 8),
                    if (vessel.cog != null)
                      Text(
                        'COG ${vessel.cog!.toStringAsFixed(0)}${_getAngleSymbol()}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    const SizedBox(width: 8),
                    if (vessel.sogRaw != null)
                      Text(
                        'SOG ${_convertSpeed(vessel.sogRaw!).toStringAsFixed(1)}${_getSpeedUnit()}',
                        style: const TextStyle(fontSize: 11),
                      ),
                  ],
                ),
                trailing: cpa != null
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cpa < 926 ? Colors.red.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2), // 926m = 0.5nm
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'CPA ${_convertDistance(cpa).toStringAsFixed(2)}${_getDistanceUnit()}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: cpa < 926 ? Colors.red : Colors.orange, // 926m = 0.5nm
                              ),
                            ),
                            if (tcpa != null && tcpa.isFinite && tcpa > 0)
                              Text(
                                'TCPA ${_formatTCPA(tcpa)}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: cpa < 926 ? Colors.red : Colors.orange,
                                ),
                              ),
                          ],
                        ),
                      )
                    : null,
              );
            },
          ),
        ),
        ],
      ),
    );
  }

  /// Extract MMSI number from vessel ID (e.g., "urn:mrn:imo:mmsi:368346080" -> "368346080")
  String _extractMMSI(String vesselId) {
    // Try to extract MMSI from URN format
    if (vesselId.contains(':')) {
      final parts = vesselId.split(':');
      return parts.last; // Return the last part (the MMSI number)
    }
    return vesselId; // Return as-is if not in URN format
  }

  /// Format time since last update
  String _formatTimeSince(DateTime timestamp) {
    final elapsed = DateTime.now().difference(timestamp);
    if (elapsed.inSeconds < 60) {
      return '${elapsed.inSeconds}s';
    } else if (elapsed.inMinutes < 60) {
      return '${elapsed.inMinutes}m';
    } else {
      return '${elapsed.inHours}h';
    }
  }

  /// Get vessel freshness color based on data age
  /// < 3 min: green (live), 3-10 min: orange (stale), > 10 min: red (old)
  Color _getVesselFreshnessColor(DateTime? timestamp) {
    if (timestamp == null) return Colors.red;

    final ageMinutes = DateTime.now().difference(timestamp).inMinutes;
    if (ageMinutes < 3) {
      return Colors.green;
    } else if (ageMinutes < 10) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  /// Format TCPA (time to closest point of approach) in seconds
  String _formatTCPA(double tcpaSeconds) {
    if (tcpaSeconds < 60) {
      return '${tcpaSeconds.toStringAsFixed(0)}s';
    } else if (tcpaSeconds < 3600) {
      final minutes = tcpaSeconds / 60;
      return '${minutes.toStringAsFixed(1)}m';
    } else {
      final hours = tcpaSeconds / 3600;
      return '${hours.toStringAsFixed(1)}h';
    }
  }

  /// Calculate CPA/TCPA for a vessel given its parameters
  /// Returns (cpa: distance in meters, tcpa: time in seconds)
  ({double cpa, double tcpa})? _calculateCPATCPAForVessel({
    required double bearing,
    required double distance,
    required double? vesselCogRad,
    required double? vesselSogMs,
  }) {
    // Get own vessel COG (raw SI = radians) and SOG (raw SI = m/s)
    final ownCogRad = _getRawValue(widget.cogPath);
    final ownSogMs = _getRawValue(widget.sogPath) ?? 0.0;

    // Own vessel velocity components (m/s)
    double ownVx = 0.0;
    double ownVy = 0.0;
    if (ownSogMs > 0.01) {
      if (ownCogRad == null) return null; // Moving but no direction
      ownVx = ownSogMs * math.sin(ownCogRad);
      ownVy = ownSogMs * math.cos(ownCogRad);
    }

    // Target vessel velocity components (m/s)
    double targetVx = 0.0;
    double targetVy = 0.0;
    final targetSogMs = vesselSogMs ?? 0.0;
    if (targetSogMs > 0.01 && vesselCogRad != null) {
      targetVx = targetSogMs * math.sin(vesselCogRad);
      targetVy = targetSogMs * math.cos(vesselCogRad);
    }

    // Relative velocity (target relative to own)
    final relVx = targetVx - ownVx;
    final relVy = targetVy - ownVy;
    final relSpeedSq = relVx * relVx + relVy * relVy;

    if (relSpeedSq < 0.0001) {
      // Vessels moving parallel, CPA is current distance
      return (cpa: distance, tcpa: double.infinity);
    }

    // Current relative position (target relative to own) in meters
    final bearingRad = bearing * math.pi / 180;
    final relX = distance * math.sin(bearingRad);
    final relY = distance * math.cos(bearingRad);

    // Time to CPA (dot product method)
    final tcpa = -(relX * relVx + relY * relVy) / relSpeedSq;

    if (tcpa < 0) {
      // CPA is in the past, vessels diverging
      return (cpa: distance, tcpa: 0);
    }

    // Position at CPA
    final cpaX = relX + relVx * tcpa;
    final cpaY = relY + relVy * tcpa;
    final cpa = math.sqrt(cpaX * cpaX + cpaY * cpaY);

    return (cpa: cpa, tcpa: tcpa);
  }

}

class _VesselPoint {
  final String? name;
  final String mmsi;
  final double bearing; // Degrees, 0-360
  final double distance; // Distance in meters (SI)
  final double? cog; // Course over ground in display units (degrees)
  final double? cogRad; // Course over ground in radians (raw SI, for math)
  final double? sogRaw; // Speed over ground in m/s (SI)
  final bool isLive; // True if from WebSocket, false if from initial REST
  final DateTime? timestamp; // Last update time
  final double? cpa; // Cached CPA in meters
  final double? tcpa; // Cached TCPA in seconds
  final int? aisShipType; // AIS ship type code
  final String? navState; // "motoring", "anchored", "moored", "sailing", "fishing"
  final double? headingTrue; // True heading in display units (degrees)
  final double? latitude; // For projected position calculations
  final double? longitude;
  final String? aisClass; // AIS class: "A" or "B"
  final String? aisStatus; // from sk-ais-status-plugin: unconfirmed/confirmed/lost/remove

  _VesselPoint({
    this.name,
    required this.mmsi,
    required this.bearing,
    required this.distance,
    this.cog,
    this.cogRad,
    this.sogRaw,
    this.isLive = false,
    this.timestamp,
    this.cpa,
    this.tcpa,
    this.aisShipType,
    this.navState,
    this.headingTrue,
    this.latitude,
    this.longitude,
    this.aisClass,
    this.aisStatus,
  });
}

class _CartesianPoint {
  final double x;
  final double y;
  final String label;
  final String mmsi;
  final Color color;
  final double? heading; // Heading in degrees for rotation
  final int? aisShipType;
  final String? navState;
  final double? sogRaw;
  final DateTime? timestamp;
  final double freshnessOpacity;
  final String? aisClass;
  final String? aisStatus;

  _CartesianPoint({
    required this.x,
    required this.y,
    required this.label,
    required this.mmsi,
    this.color = Colors.grey, // Default for grid points
    this.heading,
    this.aisShipType,
    this.navState,
    this.sogRaw,
    this.timestamp,
    this.freshnessOpacity = 1.0,
    this.aisClass,
    this.aisStatus,
  });
}
