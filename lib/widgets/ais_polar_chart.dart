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
    // Listen for SignalK service updates (fires on every WebSocket update)
    widget.signalKService.addListener(_onServiceUpdate);

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

    // Throttle updates to prevent ANR on tablets
    final now = DateTime.now();
    if (_lastUpdate != null && now.difference(_lastUpdate!) < _updateThrottle) {
      return;
    }
    _lastUpdate = now;

    // Try to subscribe if we haven't yet (in case connection happened after init)
    _subscribeIfConnected();
    _updateVesselData();
  }

  @override
  void dispose() {
    widget.signalKService.removeListener(_onServiceUpdate);
    _highlightTimer?.cancel();
    super.dispose();
  }

  void _highlightVessel(String mmsi) {
    setState(() {
      _highlightedVesselMMSI = mmsi;
    });

    // Cancel existing timer
    _highlightTimer?.cancel();

    // Reset highlight after 3 seconds
    _highlightTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _highlightedVesselMMSI = null;
        });
      }
    });
  }

  void _updateVesselData() {
    // Get own position - it's an object with latitude and longitude
    final positionData = widget.signalKService.getValue(widget.positionPath);

    if (positionData?.value is Map) {
      final positionMap = positionData!.value as Map<String, dynamic>;
      final lat = positionMap['latitude'];
      final lon = positionMap['longitude'];

      if (lat is num && lon is num) {
        final newLat = lat.toDouble();
        final newLon = lon.toDouble();

        // Check if position changed
        final positionChanged = _ownLat != newLat || _ownLon != newLon;

        _ownLat = newLat;
        _ownLon = newLon;
        _lastPositionUpdate = positionData.timestamp;

        // Fetch vessels (this will call setState once at the end)
        _fetchNearbyVessels();

        // Auto-follow if enabled and in map view
        if (_mapAutoFollow && _showMapView && positionChanged) {
          _centerMapOnSelf();
        }
      }
    }
  }

  void _fetchNearbyVessels() {
    if (_ownLat == null || _ownLon == null) return;

    // Get live vessel data from WebSocket cache (populated by vessels.* subscription)
    final aisVessels = widget.signalKService.getLiveAISVessels();

    // Build new vessel list
    final newVessels = <_VesselPoint>[];

    for (final entry in aisVessels.entries) {
      final vesselId = entry.key;
      final vesselData = entry.value;

      final lat = vesselData['latitude'];
      final lon = vesselData['longitude'];
      final name = vesselData['name'];
      final cog = vesselData['cog'];
      final sogRaw = vesselData['sogRaw'] as double?;

      if (lat != null && lon != null) {
        final bearing = _calculateBearing(_ownLat!, _ownLon!, lat, lon);
        final distance = _calculateDistance(_ownLat!, _ownLon!, lat, lon);

        // Check vessel data age
        final timestamp = vesselData['timestamp'] as DateTime?;
        final now = DateTime.now();
        final ageMinutes = timestamp != null
            ? now.difference(timestamp).inMinutes
            : widget.pruneMinutes + 1; // Treat null timestamp as expired

        // Skip vessels older than prune time
        if (ageMinutes > widget.pruneMinutes) {
          continue;
        }

        // Determine freshness: < 3 min = live, 3-10 min = stale, > 10 min = old
        final isLive = ageMinutes < 3;

        // Calculate CPA/TCPA during fetch with caching
        final cpaTcpa = _calculateCPATCPAForVessel(
          bearing: bearing,
          distance: distance,
          vesselCog: cog,
          vesselSogRaw: sogRaw,
        );

        double? finalCpa;
        double? finalTcpa;

        if (cpaTcpa != null) {
          // New valid calculation - check if change is significant
          final previous = _cachedCPA[vesselId];
          if (previous != null) {
            final diff = (cpaTcpa.cpa - previous.cpa).abs();
            final pctChange = previous.cpa > 0 ? diff / previous.cpa : 1.0;

            if (diff < 50 && pctChange < 0.1) {
              // Insignificant change, keep previous to avoid flicker
              finalCpa = previous.cpa;
              finalTcpa = previous.tcpa;
            } else {
              // Significant change, update
              finalCpa = cpaTcpa.cpa;
              finalTcpa = cpaTcpa.tcpa;
              _cachedCPA[vesselId] = cpaTcpa;
            }
          } else {
            // First calculation for this vessel
            finalCpa = cpaTcpa.cpa;
            finalTcpa = cpaTcpa.tcpa;
            _cachedCPA[vesselId] = cpaTcpa;
          }
        } else {
          // Calculation failed - USE CACHED VALUE (don't clear!)
          final previous = _cachedCPA[vesselId];
          if (previous != null) {
            finalCpa = previous.cpa;
            finalTcpa = previous.tcpa;
          }
        }

        newVessels.add(_VesselPoint(
          name: name,
          mmsi: vesselId,
          bearing: bearing,
          distance: distance,
          cog: cog,
          sogRaw: sogRaw,
          isLive: isLive,
          timestamp: timestamp,
          cpa: finalCpa,
          tcpa: finalTcpa,
        ));
      }
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

  /// Convert distance from meters to user's preferred unit using server unit preferences
  double _convertDistance(double meters) {
    final metadata = widget.signalKService.metadataStore.getByCategory('distance');
    return metadata?.convert(meters) ?? meters;
  }

  /// Get distance unit symbol from server unit preferences
  String _getDistanceUnit() {
    final metadata = widget.signalKService.metadataStore.getByCategory('distance');
    return metadata?.symbol ?? 'm';
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

            // Radar with overlay controls
            final radarWithOverlay = Stack(
              children: [
                Positioned.fill(child: radarClipped),
                // Status badge (top left)
                Positioned(
                  top: 8,
                  left: 8,
                  child: _buildStatusBadge(context),
                ),
                // View controls (top right)
                Positioned(
                  top: 8,
                  right: 8,
                  child: _buildOverlayControls(context),
                ),
              ],
            );

            if (isWide) {
              // Side-by-side: radar left (50%), list right (50%)
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: radarWithOverlay),
                  const SizedBox(width: 8),
                  Expanded(child: listClipped),
                ],
              );
            } else {
              // Stacked: radar top (50%), list below (50%)
              return Column(
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

    // Split vessels into normal and highlighted
    final normalVessels = vesselPoints.where((v) => v.mmsi != _highlightedVesselMMSI).toList();
    final highlightedVessels = vesselPoints.where((v) => v.mmsi == _highlightedVesselMMSI).toList();

    // Expand axis range to accommodate labels (labels are at 1.15 * range)
    final axisRange = displayRange * 1.25;

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
        // Normal AIS vessels with freshness colors
        if (normalVessels.isNotEmpty)
          ScatterSeries<_CartesianPoint, double>(
            dataSource: normalVessels,
            xValueMapper: (_CartesianPoint point, _) => point.x,
            yValueMapper: (_CartesianPoint point, _) => point.y,
            pointColorMapper: (_CartesianPoint point, _) => point.color,
            animationDuration: 0,
            markerSettings: const MarkerSettings(
              height: 8,
              width: 8,
              shape: DataMarkerType.triangle,
              borderWidth: 1,
            ),
          ),
        // Highlighted AIS vessel (double size)
        if (highlightedVessels.isNotEmpty)
          ScatterSeries<_CartesianPoint, double>(
            dataSource: highlightedVessels,
            xValueMapper: (_CartesianPoint point, _) => point.x,
            yValueMapper: (_CartesianPoint point, _) => point.y,
            color: Colors.yellow,
            animationDuration: 0,
            markerSettings: const MarkerSettings(
              height: 16,
              width: 16,
              shape: DataMarkerType.triangle,
              borderColor: Colors.orange,
              borderWidth: 2,
            ),
          ),
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
      final vesselData = widget.signalKService.getLiveAISVessels()[vessel.mmsi];
      if (vesselData != null) {
        final lat = vesselData['latitude'] as double?;
        final lon = vesselData['longitude'] as double?;
        if (lat != null && lon != null) {
          minLat = math.min(minLat, lat);
          maxLat = math.max(maxLat, lat);
          minLon = math.min(minLon, lon);
          maxLon = math.max(maxLon, lon);
        }
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
        // Vessel markers
        MarkerLayer(
          markers: [
            // Own vessel (green arrow, larger than others)
            Marker(
              point: LatLng(_ownLat!, _ownLon!),
              width: 24,
              height: 24,
              child: Transform.rotate(
                angle: ownHeading * math.pi / 180, // Convert degrees to radians
                child: const Icon(
                  Icons.navigation,
                  color: Colors.green,
                  size: 20, // Larger than red arrows (16)
                ),
              ),
            ),
            // Other vessels
            ..._vessels.map((vessel) {
              final vesselData = widget.signalKService.getLiveAISVessels()[vessel.mmsi];
              if (vesselData == null) return null;

              final lat = vesselData['latitude'] as double?;
              final lon = vesselData['longitude'] as double?;
              if (lat == null || lon == null) return null;

              // Get COG for rotation (in degrees)
              final cog = vessel.cog ?? 0.0;
              final isHighlighted = vessel.mmsi == _highlightedVesselMMSI;
              final freshnessColor = _getVesselFreshnessColor(vessel.timestamp);

              return Marker(
                point: LatLng(lat, lon),
                width: isHighlighted ? 32 : 20,
                height: isHighlighted ? 32 : 20,
                child: GestureDetector(
                  onTap: () => _highlightVessel(vessel.mmsi),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Rotated navigation arrow
                      Transform.rotate(
                        angle: cog * math.pi / 180, // Convert degrees to radians
                        child: Icon(
                          Icons.navigation,
                          color: isHighlighted ? Colors.yellow : freshnessColor,
                          size: isHighlighted ? 28 : 16,
                        ),
                      ),
                      // X overlay for old vessels (> 10 min)
                      if (freshnessColor == Colors.red)
                        const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 12,
                        ),
                    ],
                  ),
                ),
              );
            }).whereType<Marker>(),
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

      return _CartesianPoint(
        x: x,
        y: y,
        label: vessel.name ?? _extractMMSI(vessel.mmsi),
        mmsi: vessel.mmsi,
        color: _getVesselFreshnessColor(vessel.timestamp),
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

              // Determine vessel freshness color: green < 3min, orange 3-10min, red > 10min
              final vesselColor = _getVesselFreshnessColor(vessel.timestamp);

              return ListTile(
                dense: true,
                onTap: () => _highlightVessel(vessel.mmsi),
                leading: Icon(
                  Icons.navigation,
                  color: vesselColor,
                  size: 20,
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        vessel.name ?? _extractMMSI(vessel.mmsi),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: vesselColor,
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
                          color: vesselColor.withValues(alpha: 0.7),
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
                        'COG ${vessel.cog!.toStringAsFixed(0)}°',
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
    required double? vesselCog,
    required double? vesselSogRaw,
  }) {
    // Get own vessel COG (in degrees) and SOG (raw SI = m/s) using configured paths
    final ownCogRaw = _getRawValue(widget.cogPath);
    final ownCog = _getConverted(widget.cogPath, ownCogRaw);
    final ownSogMs = _getRawValue(widget.sogPath) ?? 0.0;

    // Own vessel velocity components (m/s)
    double ownVx = 0.0;
    double ownVy = 0.0;
    if (ownSogMs > 0.01) {
      if (ownCog == null) return null; // Moving but no direction
      ownVx = ownSogMs * math.sin(ownCog * math.pi / 180);
      ownVy = ownSogMs * math.cos(ownCog * math.pi / 180);
    }

    // Target vessel velocity components (m/s)
    double targetVx = 0.0;
    double targetVy = 0.0;
    final targetSogMs = vesselSogRaw ?? 0.0;
    if (targetSogMs > 0.01 && vesselCog != null) {
      targetVx = targetSogMs * math.sin(vesselCog * math.pi / 180);
      targetVy = targetSogMs * math.cos(vesselCog * math.pi / 180);
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
  final double? cog; // Course over ground in degrees
  final double? sogRaw; // Speed over ground in m/s (SI)
  final bool isLive; // True if from WebSocket, false if from initial REST
  final DateTime? timestamp; // Last update time
  final double? cpa; // Cached CPA in meters
  final double? tcpa; // Cached TCPA in seconds

  _VesselPoint({
    this.name,
    required this.mmsi,
    required this.bearing,
    required this.distance,
    this.cog,
    this.sogRaw,
    this.isLive = false,
    this.timestamp,
    this.cpa,
    this.tcpa,
  });
}

class _CartesianPoint {
  final double x;
  final double y;
  final String label;
  final String mmsi;
  final Color color;

  _CartesianPoint({
    required this.x,
    required this.y,
    required this.label,
    required this.mmsi,
    this.color = Colors.grey, // Default for grid points
  });
}
