import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../models/tool_config.dart';
import '../../models/tool_definition.dart';
import '../../services/signalk_service.dart';
import '../../services/anchor_alarm_service.dart';
import '../../services/messaging_service.dart';
import '../../models/anchor_state.dart';
import '../../services/tool_registry.dart';
import '../../utils/conversion_utils.dart';

/// Anchor Alarm Tool - Single unified widget with map and controls
///
/// Shows:
/// - Interactive map with anchor position and vessel
/// - Status panel with distance/bearing info
/// - Control panel with drop/raise anchor and rode adjustment
class AnchorAlarmTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const AnchorAlarmTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<AnchorAlarmTool> createState() => _AnchorAlarmToolState();
}

class _AnchorAlarmToolState extends State<AnchorAlarmTool> {
  late AnchorAlarmService _alarmService;
  final MapController _mapController = MapController();
  bool _mapAutoFollow = true;
  double _rodeSliderValue = 30.0;
  bool _showPolarView = false; // Toggle between map and polar view

  @override
  void initState() {
    super.initState();

    // Get messaging service from provider if available
    MessagingService? messagingService;
    try {
      messagingService = Provider.of<MessagingService>(context, listen: false);
    } catch (_) {
      // Messaging service not available
    }

    _alarmService = AnchorAlarmService(
      signalKService: widget.signalKService,
      messagingService: messagingService,
    );
    _alarmService.initialize();
    _alarmService.addListener(_onStateChanged);

    // Configure from tool settings
    _configureFromSettings();
  }

  void _configureFromSettings() {
    final customProps = widget.config.style.customProperties ?? {};

    // Configure SignalK paths from dataSources
    _alarmService.setPaths(AnchorAlarmPaths.fromDataSources(widget.config.dataSources));

    // Alarm sound
    final alarmSound = customProps['alarmSound'] as String? ?? 'foghorn';
    _alarmService.setAlarmSound(alarmSound);

    // Check-in config
    final checkInEnabled = customProps['checkInEnabled'] as bool? ?? false;
    final intervalMinutes = customProps['checkInIntervalMinutes'] as int? ?? 30;
    final gracePeriodSeconds = customProps['checkInGracePeriodSeconds'] as int? ?? 60;

    _alarmService.setCheckInConfig(CheckInConfig(
      enabled: checkInEnabled,
      interval: Duration(minutes: intervalMinutes),
      gracePeriod: Duration(seconds: gracePeriodSeconds),
    ));
  }

  @override
  void dispose() {
    _alarmService.removeListener(_onStateChanged);
    _alarmService.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {});

      // Update slider from current rode length
      final rodeLength = _alarmService.state.rodeLength;
      if (rodeLength != null && (_rodeSliderValue - rodeLength).abs() > 1) {
        _rodeSliderValue = rodeLength.clamp(5.0, 100.0);
      }

      // Auto-follow vessel if enabled
      if (_mapAutoFollow && _alarmService.state.vesselPosition != null) {
        final pos = _alarmService.state.vesselPosition!;
        try {
          _mapController.move(
            LatLng(pos.latitude, pos.longitude),
            _mapController.camera.zoom,
          );
        } catch (_) {
          // Map not ready yet
        }
      }
    }
  }

  Color _getPrimaryColor() {
    final colorStr = widget.config.style.primaryColor;
    if (colorStr != null && colorStr.startsWith('#')) {
      try {
        return Color(int.parse(colorStr.substring(1), radix: 16) | 0xFF000000);
      } catch (_) {}
    }
    return Colors.blue;
  }

  void _centerOnAnchor() {
    final anchorPos = _alarmService.state.anchorPosition;
    if (anchorPos != null) {
      _mapController.move(
        LatLng(anchorPos.latitude, anchorPos.longitude),
        _mapController.camera.zoom,
      );
      setState(() => _mapAutoFollow = false);
    }
  }

  void _centerOnVessel() {
    final vesselPos = _alarmService.state.vesselPosition;
    if (vesselPos != null) {
      _mapController.move(
        LatLng(vesselPos.latitude, vesselPos.longitude),
        _mapController.camera.zoom,
      );
    }
  }

  void _toggleAutoFollow() {
    setState(() {
      _mapAutoFollow = !_mapAutoFollow;
      if (_mapAutoFollow) {
        _centerOnVessel();
      }
    });
  }

  Future<void> _dropAnchor() async {
    final success = await _alarmService.dropAnchor();
    if (success && mounted) {
      // Set rode length to distance from bow + 10%
      final gpsFromBow = _alarmService.gpsFromBow;
      if (gpsFromBow != null && gpsFromBow > 0) {
        final rodeLength = gpsFromBow * 1.1;
        await _alarmService.setRodeLength(rodeLength);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anchor dropped'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _raiseAnchor() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Raise Anchor'),
        content: const Text('Are you sure you want to raise the anchor and disable the alarm?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Raise Anchor'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _alarmService.raiseAnchor();
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Anchor raised'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _setRodeLength(double length) async {
    await _alarmService.setRodeLength(length);
  }

  // Format distance with user's preferred units
  String _formatDistance(double? meters, String path) {
    if (meters == null) return '--';
    return ConversionUtils.formatValue(
      widget.signalKService,
      path,
      meters,
      decimalPlaces: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _alarmService.state;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Main view - map or polar
          Positioned.fill(
            child: _showPolarView ? _buildPolarView(state) : _buildMap(state),
          ),

          // View controls (top right)
          Positioned(
            top: 8,
            right: 8,
            child: Column(
              children: [
                // Map/Polar toggle
                _buildMapButton(
                  icon: _showPolarView ? Icons.map : Icons.radar,
                  onPressed: () => setState(() => _showPolarView = !_showPolarView),
                ),
                const SizedBox(height: 8),
                if (!_showPolarView) ...[
                  _buildMapButton(
                    icon: Icons.add,
                    onPressed: () => _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom + 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildMapButton(
                    icon: Icons.remove,
                    onPressed: () => _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom - 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildMapButton(
                    icon: Icons.anchor,
                    onPressed: _centerOnAnchor,
                  ),
                  const SizedBox(height: 4),
                  _buildMapButton(
                    icon: _mapAutoFollow ? Icons.gps_fixed : Icons.gps_not_fixed,
                    onPressed: _toggleAutoFollow,
                    color: _mapAutoFollow ? _getPrimaryColor() : null,
                  ),
                ],
              ],
            ),
          ),

          // Status panel (top left)
          Positioned(
            top: 8,
            left: 8,
            child: _buildStatusPanel(state),
          ),

          // Control panel (bottom)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildControlPanel(state),
          ),

          // Check-in overlay
          if (_alarmService.awaitingCheckIn)
            Positioned.fill(
              child: _buildCheckInOverlay(),
            ),

          // Alarm overlay
          if (state.alarmState.isAlarming)
            Positioned.fill(
              child: _buildAlarmOverlay(state),
            ),
        ],
      ),
    );
  }

  Widget _buildMapButton({
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

  Widget _buildMap(AnchorState state) {
    final vesselPos = state.vesselPosition;
    final anchorPos = state.anchorPosition;

    // Default center
    LatLng center = LatLng(0, 0);
    if (anchorPos != null) {
      center = LatLng(anchorPos.latitude, anchorPos.longitude);
    } else if (vesselPos != null) {
      center = LatLng(vesselPos.latitude, vesselPos.longitude);
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 16,
        minZoom: 5,
        maxZoom: 18,
        onPositionChanged: (position, hasGesture) {
          if (hasGesture && _mapAutoFollow) {
            setState(() => _mapAutoFollow = false);
          }
        },
      ),
      children: [
        // Base map
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.zennora.signalk',
        ),
        // OpenSeaMap overlay
        TileLayer(
          urlTemplate: 'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.zennora.signalk',
        ),
        // Track history
        if (_alarmService.trackHistory.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _alarmService.trackHistory
                    .map((p) => LatLng(p.latitude, p.longitude))
                    .toList(),
                color: Colors.blue.withValues(alpha: 0.7),
                strokeWidth: 2,
              ),
            ],
          ),
        // Alarm radius circle
        if (anchorPos != null && state.maxRadius != null)
          CircleLayer(
            circles: [
              // Alarm radius (red)
              CircleMarker(
                point: LatLng(anchorPos.latitude, anchorPos.longitude),
                radius: state.maxRadius!,
                useRadiusInMeter: true,
                color: Colors.red.withValues(alpha: 0.1),
                borderColor: Colors.red,
                borderStrokeWidth: 2,
              ),
              // Current distance indicator
              if (state.currentRadius != null)
                CircleMarker(
                  point: LatLng(anchorPos.latitude, anchorPos.longitude),
                  radius: state.currentRadius!,
                  useRadiusInMeter: true,
                  color: Colors.transparent,
                  borderColor: _getDistanceColor(state),
                  borderStrokeWidth: 1,
                ),
            ],
          ),
        // Markers
        MarkerLayer(
          markers: [
            // Anchor position
            if (anchorPos != null)
              Marker(
                point: LatLng(anchorPos.latitude, anchorPos.longitude),
                width: 32,
                height: 32,
                child: const Icon(Icons.anchor, color: Colors.brown, size: 28),
              ),
            // Vessel position
            if (vesselPos != null)
              Marker(
                point: LatLng(vesselPos.latitude, vesselPos.longitude),
                width: 28,
                height: 28,
                child: Transform.rotate(
                  angle: (state.vesselHeading ?? 0) * math.pi / 180,
                  child: const Icon(Icons.navigation, color: Colors.green, size: 24),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Build polar/radar view as fallback when maps unavailable
  Widget _buildPolarView(AnchorState state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? Colors.grey.shade900 : Colors.grey.shade100;

    if (!state.isActive || state.anchorPosition == null) {
      return Container(
        color: backgroundColor,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.anchor_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'Drop anchor to see polar view',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // Calculate range - use max of alarm radius or current distance, with some padding
    final maxRadius = state.maxRadius ?? 50.0;
    final currentRadius = state.currentRadius ?? 0.0;
    final displayRange = math.max(maxRadius, currentRadius) * 1.3;

    // Build data points for the chart
    final chartData = <_PolarPoint>[];

    // Anchor at center (0, 0)
    chartData.add(_PolarPoint(x: 0, y: 0, label: 'Anchor', type: 'anchor'));

    // Vessel position relative to anchor
    if (state.vesselPosition != null && state.anchorPosition != null) {
      final bearing = state.bearingTrue ?? 0; // radians
      final distance = state.currentRadius ?? 0;

      // Convert polar to cartesian (bearing is from vessel TO anchor, so we flip it)
      // North is up (positive Y), East is right (positive X)
      final vesselBearing = bearing + math.pi; // flip direction
      final x = distance * math.sin(vesselBearing);
      final y = distance * math.cos(vesselBearing);

      chartData.add(_PolarPoint(x: x, y: y, label: 'Vessel', type: 'vessel'));
    }

    // Build circle data for alarm radius
    final alarmCircle = _generateCirclePoints(maxRadius, 36);
    final currentCircle = currentRadius > 0 ? _generateCirclePoints(currentRadius, 36) : <_PolarPoint>[];

    // Build track history points relative to anchor
    final trackPoints = <_PolarPoint>[];
    if (state.anchorPosition != null) {
      final anchorLat = state.anchorPosition!.latitude;
      final anchorLon = state.anchorPosition!.longitude;
      const distance = Distance();

      // Add historical track points
      for (final point in _alarmService.trackHistory) {
        // Calculate distance and bearing from anchor to track point
        final dist = distance.as(
          LengthUnit.Meter,
          LatLng(anchorLat, anchorLon),
          LatLng(point.latitude, point.longitude),
        );
        final bearing = distance.bearing(
          LatLng(anchorLat, anchorLon),
          LatLng(point.latitude, point.longitude),
        ) * math.pi / 180; // Convert to radians

        // Convert to cartesian (bearing is from anchor to point)
        // North is up (positive Y), East is right (positive X)
        final x = dist * math.sin(bearing);
        final y = dist * math.cos(bearing);

        trackPoints.add(_PolarPoint(x: x, y: y, label: '', type: 'track'));
      }

      // Always add current vessel position as last point to connect track to vessel
      if (state.vesselPosition != null) {
        final vesselBearing = (state.bearingTrue ?? 0) + math.pi; // flip direction
        final vesselDist = state.currentRadius ?? 0;
        final vx = vesselDist * math.sin(vesselBearing);
        final vy = vesselDist * math.cos(vesselBearing);
        trackPoints.add(_PolarPoint(x: vx, y: vy, label: '', type: 'track'));
      }
    }

    return Container(
      color: backgroundColor,
      child: Center(
        child: AspectRatio(
          aspectRatio: 1.0,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: SfCartesianChart(
          plotAreaBackgroundColor: Colors.transparent,
          margin: const EdgeInsets.all(5),
          primaryXAxis: NumericAxis(
            minimum: -displayRange,
            maximum: displayRange,
            isVisible: false,
            majorGridLines: const MajorGridLines(width: 0),
          ),
          primaryYAxis: NumericAxis(
            minimum: -displayRange,
            maximum: displayRange,
            isVisible: false,
            majorGridLines: const MajorGridLines(width: 0),
          ),
          plotAreaBorderWidth: 0,
          annotations: _buildPolarAnnotations(displayRange, isDark),
          series: <CartesianSeries>[
            // Grid circles
            ..._buildPolarGridSeries(displayRange, isDark),

            // Track history line (connects all points)
            if (trackPoints.isNotEmpty)
              LineSeries<_PolarPoint, double>(
                dataSource: trackPoints,
                xValueMapper: (p, _) => p.x,
                yValueMapper: (p, _) => p.y,
                color: Colors.blue,
                width: 2,
                animationDuration: 0,
              ),

            // Track history points (dots along the track, larger than line)
            if (trackPoints.isNotEmpty)
              ScatterSeries<_PolarPoint, double>(
                dataSource: trackPoints,
                xValueMapper: (p, _) => p.x,
                yValueMapper: (p, _) => p.y,
                color: Colors.blue,
                animationDuration: 0,
                markerSettings: const MarkerSettings(
                  height: 5,
                  width: 5,
                  shape: DataMarkerType.circle,
                ),
              ),

            // Alarm radius circle (red)
            LineSeries<_PolarPoint, double>(
              dataSource: alarmCircle,
              xValueMapper: (p, _) => p.x,
              yValueMapper: (p, _) => p.y,
              color: Colors.red.withValues(alpha: 0.7),
              width: 2,
              animationDuration: 0,
            ),

            // Current distance circle (color-coded)
            if (currentCircle.isNotEmpty)
              LineSeries<_PolarPoint, double>(
                dataSource: currentCircle,
                xValueMapper: (p, _) => p.x,
                yValueMapper: (p, _) => p.y,
                color: _getDistanceColor(state).withValues(alpha: 0.5),
                width: 1,
                dashArray: const <double>[5, 3],
                animationDuration: 0,
              ),

            // Anchor point (center)
            ScatterSeries<_PolarPoint, double>(
              dataSource: chartData.where((p) => p.type == 'anchor').toList(),
              xValueMapper: (p, _) => p.x,
              yValueMapper: (p, _) => p.y,
              color: Colors.brown,
              animationDuration: 0,
              markerSettings: const MarkerSettings(
                height: 16,
                width: 16,
                shape: DataMarkerType.diamond,
                borderColor: Colors.white,
                borderWidth: 2,
              ),
            ),

            // Vessel point
            ScatterSeries<_PolarPoint, double>(
              dataSource: chartData.where((p) => p.type == 'vessel').toList(),
              xValueMapper: (p, _) => p.x,
              yValueMapper: (p, _) => p.y,
              color: Colors.green,
              animationDuration: 0,
              markerSettings: const MarkerSettings(
                height: 14,
                width: 14,
                shape: DataMarkerType.triangle,
                borderColor: Colors.white,
                borderWidth: 2,
              ),
            ),
          ],
            ),
          ),
        ),
      ),
    );
  }

  List<_PolarPoint> _generateCirclePoints(double radius, int segments) {
    final points = <_PolarPoint>[];
    for (int i = 0; i <= segments; i++) {
      final angle = (i / segments) * 2 * math.pi;
      points.add(_PolarPoint(
        x: radius * math.cos(angle),
        y: radius * math.sin(angle),
        label: '',
        type: 'circle',
      ));
    }
    return points;
  }

  List<CartesianChartAnnotation> _buildPolarAnnotations(double range, bool isDark) {
    final textColor = isDark ? Colors.white70 : Colors.black54;
    final annotations = <CartesianChartAnnotation>[];

    // Compass labels
    final labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final labelRadius = range * 0.92;

    for (int i = 0; i < 8; i++) {
      final angle = (i * 45) * math.pi / 180;
      final x = labelRadius * math.sin(angle);
      final y = labelRadius * math.cos(angle);

      annotations.add(CartesianChartAnnotation(
        widget: Text(
          labels[i],
          style: TextStyle(
            fontSize: 10,
            color: textColor,
            fontWeight: i == 0 ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        coordinateUnit: CoordinateUnit.point,
        x: x,
        y: y,
      ));
    }

    // Distance labels at grid circles (25%, 50%, 75%)
    for (final fraction in [0.25, 0.5, 0.75]) {
      final distanceMeters = range * fraction;
      final distanceLabel = _formatDistance(distanceMeters, 'navigation.anchor.currentRadius');

      // Place label on the right side (East direction)
      annotations.add(CartesianChartAnnotation(
        widget: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: BoxDecoration(
            color: isDark ? Colors.black54 : Colors.white70,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            distanceLabel,
            style: TextStyle(
              fontSize: 9,
              color: textColor,
            ),
          ),
        ),
        coordinateUnit: CoordinateUnit.point,
        x: distanceMeters + 5,
        y: 0,
      ));
    }

    // Center label
    annotations.add(CartesianChartAnnotation(
      widget: Icon(Icons.anchor, size: 12, color: Colors.brown),
      coordinateUnit: CoordinateUnit.point,
      x: 0,
      y: 0,
    ));

    return annotations;
  }

  List<LineSeries<_PolarPoint, double>> _buildPolarGridSeries(double range, bool isDark) {
    final gridColor = isDark ? Colors.white24 : Colors.black12;
    final series = <LineSeries<_PolarPoint, double>>[];

    // Concentric circles at 25%, 50%, 75%
    for (final fraction in [0.25, 0.5, 0.75]) {
      final circlePoints = _generateCirclePoints(range * fraction, 36);
      series.add(LineSeries<_PolarPoint, double>(
        dataSource: circlePoints,
        xValueMapper: (p, _) => p.x,
        yValueMapper: (p, _) => p.y,
        color: gridColor,
        width: 0.5,
        animationDuration: 0,
      ));
    }

    // Cardinal lines (N-S, E-W)
    series.add(LineSeries<_PolarPoint, double>(
      dataSource: [
        _PolarPoint(x: 0, y: range, label: '', type: 'grid'),   // North
        _PolarPoint(x: 0, y: -range, label: '', type: 'grid'),  // South
      ],
      xValueMapper: (p, _) => p.x,
      yValueMapper: (p, _) => p.y,
      color: gridColor,
      width: 0.5,
      animationDuration: 0,
    ));
    series.add(LineSeries<_PolarPoint, double>(
      dataSource: [
        _PolarPoint(x: -range, y: 0, label: '', type: 'grid'),
        _PolarPoint(x: range, y: 0, label: '', type: 'grid'),
      ],
      xValueMapper: (p, _) => p.x,
      yValueMapper: (p, _) => p.y,
      color: gridColor,
      width: 0.5,
      animationDuration: 0,
    ));

    return series;
  }

  Color _getDistanceColor(AnchorState state) {
    final percentage = state.radiusPercentage ?? 0;
    if (percentage >= 100) return Colors.red;
    if (percentage >= 80) return Colors.orange;
    if (percentage >= 60) return Colors.yellow;
    return Colors.green;
  }

  Widget _buildStatusPanel(AnchorState state) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                state.isActive ? Icons.anchor : Icons.anchor_outlined,
                color: state.isActive ? Colors.orange : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                state.isActive ? 'ANCHORED' : 'NOT SET',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: state.isActive ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ),
          if (state.isActive) ...[
            const SizedBox(height: 6),
            _buildStatusRow('Distance', _formatDistance(state.currentRadius, 'navigation.anchor.currentRadius')),
            _buildStatusRow('Alarm', _formatDistance(state.maxRadius, 'navigation.anchor.maxRadius')),
            _buildStatusRow('Rode', _formatDistance(state.rodeLength, 'navigation.anchor.rodeLength')),
            if (state.bearingDegrees != null)
              _buildStatusRow('Bearing', '${state.bearingDegrees!.toStringAsFixed(0)}°'),
            _buildStatusRow('Track', '${_alarmService.trackHistory.length} pts'),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 55,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel(AnchorState state) {
    // Get unit info for rode length display
    final availableUnits = widget.signalKService.getAvailableUnits('navigation.anchor.rodeLength');
    final unitSymbol = availableUnits.isNotEmpty
        ? widget.signalKService.getConversionInfo('navigation.anchor.rodeLength', availableUnits.first)?.symbol ?? 'm'
        : 'm';

    // Convert current slider value to display units
    final displayValue = ConversionUtils.convertValue(
      widget.signalKService,
      'navigation.anchor.rodeLength',
      _rodeSliderValue,
    ) ?? _rodeSliderValue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: state.isActive ? null : _dropAnchor,
                  icon: const Icon(Icons.anchor, size: 18),
                  label: const Text('Drop'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: state.isActive ? _raiseAnchor : null,
                  icon: const Icon(Icons.eject, size: 18),
                  label: const Text('Raise'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),

          // Rode length slider (only when active)
          if (state.isActive) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text('Rode: ', style: TextStyle(color: Colors.black87, fontSize: 12)),
                Text(
                  '${displayValue.toStringAsFixed(0)} $unitSymbol',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 14),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: Colors.blue,
                      inactiveTrackColor: Colors.blue.shade100,
                      thumbColor: Colors.blue,
                      overlayColor: Colors.blue.withValues(alpha: 0.2),
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    ),
                    child: Slider(
                      value: _rodeSliderValue,
                      min: 5,
                      max: 100,
                      divisions: 19,
                      onChanged: (value) => setState(() => _rodeSliderValue = value),
                      onChangeEnd: _setRodeLength,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCheckInOverlay() {
    final deadline = _alarmService.checkInDeadline;
    final remaining = deadline != null
        ? deadline.difference(DateTime.now())
        : Duration.zero;

    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber, size: 60, color: Colors.orange),
            const SizedBox(height: 12),
            const Text(
              'ANCHOR WATCH CHECK-IN',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Time remaining: ${_formatDuration(remaining)}',
              style: const TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _alarmService.acknowledgeCheckIn(),
              icon: const Icon(Icons.check),
              label: const Text("I'm Watching"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlarmOverlay(AnchorState state) {
    final distanceDisplay = _formatDistance(state.currentRadius, 'navigation.anchor.currentRadius');

    return Container(
      color: Colors.red.shade900.withValues(alpha: 0.9),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning, size: 80, color: Colors.white),
            const SizedBox(height: 12),
            Text(
              state.alarmMessage ?? 'ANCHOR ALARM',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Distance: $distanceDisplay',
              style: const TextStyle(fontSize: 20, color: Colors.white),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _alarmService.acknowledgeAlarm(),
              icon: const Icon(Icons.check),
              label: const Text('Acknowledge'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.isNegative) return '0:00';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Builder for Anchor Alarm Tool
class AnchorAlarmToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'anchor_alarm',
      name: 'Anchor Alarm',
      description: 'Monitor anchor position with map display, alarms, and check-in system',
      category: ToolCategory.navigation,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: true,
        minPaths: 0,
        maxPaths: 8,
        styleOptions: const [],
      ),
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: [
        DataSource(path: 'navigation.anchor.position', label: 'Anchor Position'),
        DataSource(path: 'navigation.anchor.maxRadius', label: 'Alarm Radius'),
        DataSource(path: 'navigation.anchor.currentRadius', label: 'Current Distance'),
        DataSource(path: 'navigation.anchor.rodeLength', label: 'Rode Length'),
        DataSource(path: 'navigation.anchor.bearingTrue', label: 'Bearing to Anchor'),
        DataSource(path: 'navigation.position', label: 'Vessel Position'),
        DataSource(path: 'navigation.headingTrue', label: 'Vessel Heading'),
        DataSource(path: 'sensors.gps.fromBow', label: 'GPS from Bow'),
      ],
      style: StyleConfig(
        customProperties: {
          'alarmSound': 'foghorn',
          'checkInEnabled': false,
          'checkInIntervalMinutes': 30,
          'checkInGracePeriodSeconds': 60,
        },
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return AnchorAlarmTool(
      config: config,
      signalKService: signalKService,
    );
  }
}

/// Data point for polar chart
class _PolarPoint {
  final double x;
  final double y;
  final String label;
  final String type;

  _PolarPoint({
    required this.x,
    required this.y,
    required this.label,
    required this.type,
  });
}
