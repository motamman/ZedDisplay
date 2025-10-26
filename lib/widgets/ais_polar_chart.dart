import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/signalk_service.dart';
import '../utils/conversion_utils.dart';

/// AIS Polar Chart that displays nearby vessels relative to own position
///
/// Shows:
/// - Own vessel at center (0,0)
/// - Other vessels plotted at relative bearing and distance
/// - Compass-style display with 8 cardinal directions
class AISPolarChart extends StatefulWidget {
  final SignalKService signalKService;
  final String positionPath; // Path to own position (default: navigation.position)
  final String title;
  final Color? vesselColor;
  final bool showLabels;
  final bool showGrid;

  const AISPolarChart({
    super.key,
    required this.signalKService,
    this.positionPath = 'navigation.position',
    this.title = 'AIS Vessels',
    this.vesselColor,
    this.showLabels = true,
    this.showGrid = true,
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

  // Map controller for centering on own vessel
  final MapController _mapController = MapController();

  // Distance conversion from categories endpoint
  String? _distanceFormula;
  String? _distanceSymbol;

  @override
  bool get wantKeepAlive => true;

  bool _hasSubscribed = false;
  bool _hasLoadedAIS = false;
  bool _showMapView = false; // Toggle between polar chart and map view
  bool _mapAutoFollow = true; // Auto-follow own vessel on map

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

    // Fetch distance conversion preferences
    _fetchDistanceConversion();

    // Fetch immediately on init
    _updateVesselData();
  }

  /// Fetch distance conversion formula and symbol from categories endpoint
  Future<void> _fetchDistanceConversion() async {
    try {
      final protocol = widget.signalKService.useSecureConnection ? 'https' : 'http';
      final url = '$protocol://${widget.signalKService.serverUrl}/signalk/v1/categories';

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 5),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final distance = data['distance'] as Map<String, dynamic>?;

        if (distance != null && mounted) {
          setState(() {
            _distanceFormula = distance['formula'] as String?;
            _distanceSymbol = distance['symbol'] as String?;
          });
        }
      }
    } catch (e) {
      // Silently fail, fallback to meters
      if (mounted) {
        setState(() {
          _distanceFormula = null;
          _distanceSymbol = 'm';
        });
      }
    }
  }

  void _subscribeIfConnected() {
    if (!_hasSubscribed && widget.signalKService.isConnected) {
      widget.signalKService.subscribeToAutopilotPaths([widget.positionPath]);
      _hasSubscribed = true;
    }
  }

  void _onServiceUpdate() {
    if (mounted) {
      // Try to subscribe if we haven't yet (in case connection happened after init)
      _subscribeIfConnected();
      _updateVesselData();
    }
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
    setState(() {
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

          _vessels.clear();
          _fetchNearbyVessels();

          // Auto-follow if enabled and in map view
          if (_mapAutoFollow && _showMapView && positionChanged) {
            _centerMapOnSelf();
          }
        }
      }
    });
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
      final sog = vesselData['sog'];

      if (lat != null && lon != null) {
        final bearing = _calculateBearing(_ownLat!, _ownLon!, lat, lon);
        final distance = _calculateDistance(_ownLat!, _ownLon!, lat, lon);

        // Check if vessel data is recent (< 3 minutes old)
        final timestamp = vesselData['timestamp'] as DateTime?;
        // final fromGET = vesselData['fromGET'] as bool? ?? true; // Unused for now
        final isLive = timestamp != null &&
                       DateTime.now().difference(timestamp).inMinutes < 3;

        newVessels.add(_VesselPoint(
          name: name,
          mmsi: vesselId,
          bearing: bearing,
          distance: distance,
          cog: cog,
          sog: sog,
          isLive: isLive,
          timestamp: timestamp,
        ));
      }
    }

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

  /// Convert distance from meters to user's preferred unit using categories endpoint
  double _convertDistance(double meters) {
    if (_distanceFormula == null) {
      return meters; // No conversion available, return raw meters
    }

    // Use the formula from categories endpoint
    final converted = ConversionUtils.evaluateFormula(_distanceFormula!, meters);
    return converted ?? meters; // Fallback to meters if evaluation fails
  }

  /// Get distance unit symbol from categories endpoint
  String _getDistanceUnit() {
    return _distanceSymbol ?? 'm'; // Default to meters if not loaded
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            Expanded(
              flex: 2,
              child: _showMapView
                  ? _buildMapView(vesselColor, isDark)
                  : Center(
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: _buildRadarChart(vesselColor, isDark),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Expanded(
              flex: 1,
              child: _buildVesselList(context, isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title and vessel count on first line
        Row(
          children: [
            Text(
              'AIS Display',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(width: 12),
            Text(
              '${_vessels.length} vessels',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Controls on second line
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Map/Polar toggle
              IconButton(
                icon: Icon(_showMapView ? Icons.radar : Icons.map, size: 20),
                onPressed: () {
                  setState(() {
                    _showMapView = !_showMapView;
                  });
                },
                tooltip: _showMapView ? 'Show Polar Chart' : 'Show Map',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              // Center on self button (only show in map view)
              if (_showMapView)
                IconButton(
                  icon: const Icon(Icons.my_location, size: 20),
                  onPressed: _centerMapOnSelf,
                  tooltip: 'Center on own vessel',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              if (_showMapView) const SizedBox(width: 8),
              // Auto-follow toggle (only show in map view)
              if (_showMapView)
                IconButton(
                  icon: Icon(
                    _mapAutoFollow ? Icons.gps_fixed : Icons.gps_not_fixed,
                    size: 20,
                    color: _mapAutoFollow ? Colors.blue : null,
                  ),
                  onPressed: _toggleAutoFollow,
                  tooltip: _mapAutoFollow ? 'Auto-follow enabled' : 'Auto-follow disabled',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              const SizedBox(width: 16),
              // Zoom out button
              IconButton(
                icon: const Icon(Icons.zoom_out, size: 20),
                onPressed: _zoomOut,
                tooltip: 'Zoom Out',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              // Range display with auto indicator (only show in polar view)
              if (!_showMapView) ...[
                const SizedBox(width: 4),
                InkWell(
                  onTap: _toggleAutoRange,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _autoRange ? Colors.blue.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${_convertDistance(_getDisplayRange()).toStringAsFixed(1)} ${_getDistanceUnit()}${_autoRange ? ' (auto)' : ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _autoRange ? Colors.blue : Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              // Zoom in button
              IconButton(
                icon: const Icon(Icons.zoom_in, size: 20),
                onPressed: _zoomIn,
                tooltip: 'Zoom In',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ],
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
          dataSource: [_CartesianPoint(x: 0, y: 0, label: 'Own', mmsi: 'self')],
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
        // Normal AIS vessels
        if (normalVessels.isNotEmpty)
          ScatterSeries<_CartesianPoint, double>(
            dataSource: normalVessels,
            xValueMapper: (_CartesianPoint point, _) => point.x,
            yValueMapper: (_CartesianPoint point, _) => point.y,
            color: vesselColor,
            animationDuration: 0,
            markerSettings: MarkerSettings(
              height: 8,
              width: 8,
              shape: DataMarkerType.triangle,
              borderColor: vesselColor,
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
    final cogTrue = ConversionUtils.getConvertedValue(widget.signalKService, 'navigation.courseOverGroundTrue');
    final cogMagnetic = ConversionUtils.getConvertedValue(widget.signalKService, 'navigation.courseOverGroundMagnetic');
    final headingMagnetic = ConversionUtils.getConvertedValue(widget.signalKService, 'navigation.headingMagnetic');

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
              final isLive = vessel.isLive;

              return Marker(
                point: LatLng(lat, lon),
                width: 20,
                height: 20,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Rotated navigation arrow
                    Transform.rotate(
                      angle: cog * math.pi / 180, // Convert degrees to radians
                      child: const Icon(
                        Icons.navigation,
                        color: Colors.red,
                        size: 16,
                      ),
                    ),
                    // X overlay for non-live vessels
                    if (!isLive)
                      const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 12,
                      ),
                  ],
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
      );
    }).toList();
  }

  /// Build vessel list
  Widget _buildVesselList(BuildContext context, bool isDark) {
    if (_vessels.isEmpty) {
      return Center(
        child: Text(
          'No vessels in range',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text(
            'Last update: $lastUpdateText',
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
        final cpa = _calculateCPA(vessel);

        return ListTile(
          dense: true,
          onTap: () => _highlightVessel(vessel.mmsi),
          leading: const Icon(
            Icons.navigation,
            color: Colors.grey,
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
                    color: vessel.isLive ? Colors.green : Colors.orange,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (vessel.timestamp != null)
                Text(
                  _formatTimeSince(vessel.timestamp!),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
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
              if (vessel.sog != null)
                Text(
                  'SOG ${vessel.sog!.toStringAsFixed(1)}kn',
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
                  child: Text(
                    'CPA ${_convertDistance(cpa).toStringAsFixed(2)}${_getDistanceUnit()}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cpa < 926 ? Colors.red : Colors.orange, // 926m = 0.5nm
                    ),
                  ),
                )
              : null,
        );
      },
          ),
        ),
      ],
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

  /// Calculate Closest Point of Approach (simplified)
  double? _calculateCPA(_VesselPoint vessel) {
    // Need own vessel COG and SOG for proper CPA calculation
    // For now, return current distance as approximation
    // TODO: Get own vessel COG/SOG and calculate proper CPA
    if (vessel.cog == null || vessel.sog == null) return null;

    // Simplified: just return current distance for now
    // A proper CPA calculation would need relative motion
    return vessel.distance;
  }
}

class _VesselPoint {
  final String? name;
  final String mmsi;
  final double bearing; // Degrees, 0-360
  final double distance; // Nautical miles
  final double? cog; // Course over ground in degrees
  final double? sog; // Speed over ground in knots
  final bool isLive; // True if from WebSocket, false if from initial REST
  final DateTime? timestamp; // Last update time

  _VesselPoint({
    this.name,
    required this.mmsi,
    required this.bearing,
    required this.distance,
    this.cog,
    this.sog,
    this.isLive = false,
    this.timestamp,
  });
}

class _CartesianPoint {
  final double x;
  final double y;
  final String label;
  final String mmsi;

  _CartesianPoint({
    required this.x,
    required this.y,
    required this.label,
    required this.mmsi,
  });
}
