import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
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
  final String positionPath; // Path to own position (default: navigation.position)
  final String title;
  final double maxRangeNm; // Maximum range in nautical miles (0 = auto)
  final Duration updateInterval;
  final Color? vesselColor;
  final bool showLabels;
  final bool showGrid;

  const AISPolarChart({
    super.key,
    required this.signalKService,
    this.positionPath = 'navigation.position',
    this.title = 'AIS Vessels',
    this.maxRangeNm = 0, // 0 = auto-scale
    this.updateInterval = const Duration(seconds: 10),
    this.vesselColor,
    this.showLabels = true,
    this.showGrid = true,
  });

  @override
  State<AISPolarChart> createState() => _AISPolarChartState();
}

class _AISPolarChartState extends State<AISPolarChart>
    with AutomaticKeepAliveClientMixin {
  Timer? _updateTimer;
  final List<_VesselPoint> _vessels = [];

  // Own position
  double? _ownLat;
  double? _ownLon;

  // Auto-calculated range
  double _calculatedRange = 5.0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _startRealTimeUpdates();
    // Fetch immediately on init
    _updateVesselData();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _startRealTimeUpdates() {
    _updateTimer = Timer.periodic(widget.updateInterval, (_) {
      if (mounted) {
        _updateVesselData();
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
          _ownLat = lat.toDouble();
          _ownLon = lon.toDouble();

          _vessels.clear();
          _fetchNearbyVessels();
        }
      }
    });
  }

  void _fetchNearbyVessels() async {
    if (_ownLat == null || _ownLon == null) return;

    final aisVessels = await widget.signalKService.getAllAISVessels();
    print('AIS DEBUG: Found ${aisVessels.length} vessels from SignalK');

    if (!mounted) return;

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

        print('AIS DEBUG: Vessel $vesselId - bearing: $bearing°, distance: ${distance.toStringAsFixed(2)}nm');

        newVessels.add(_VesselPoint(
          name: name,
          mmsi: vesselId,
          bearing: bearing,
          distance: distance,
          cog: cog,
          sog: sog,
        ));
      }
    }

    // Update state once with all vessels
    if (mounted) {
      setState(() {
        _vessels.clear();
        _vessels.addAll(newVessels);

        // Auto-calculate range if needed
        if (widget.maxRangeNm == 0 && _vessels.isNotEmpty) {
          final maxDistance = _vessels.map((v) => v.distance).reduce((a, b) => a > b ? a : b);
          _calculatedRange = (maxDistance * 1.2).clamp(1.0, 50.0); // 20% padding, min 1nm, max 50nm
        }
      });
    }

    print('AIS DEBUG: ${_vessels.length} vessels, range: ${_getDisplayRange().toStringAsFixed(1)}nm');
  }

  double _getDisplayRange() {
    return widget.maxRangeNm > 0 ? widget.maxRangeNm : _calculatedRange;
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

  /// Calculate distance between two points (in nautical miles)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    final R = 3440.065; // Earth radius in nautical miles
    final lat1Rad = lat1 * math.pi / 180;
    final lat2Rad = lat2 * math.pi / 180;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1Rad) * math.cos(lat2Rad) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return R * c;
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
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: _buildRadarChart(vesselColor, isDark),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: _buildVesselList(context, isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            widget.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        Text(
          '${_vessels.length} vessels',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey,
              ),
        ),
        const SizedBox(width: 8),
        Text(
          '${_getDisplayRange().toStringAsFixed(1)} nm${widget.maxRangeNm == 0 ? ' (auto)' : ''}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey,
              ),
        ),
      ],
    );
  }

  Widget _buildRadarChart(Color vesselColor, bool isDark) {
    // Convert vessel positions to Cartesian coordinates
    final vesselPoints = _vesselsToCartesian();
    final displayRange = _getDisplayRange();

    return SfCartesianChart(
      plotAreaBackgroundColor: Colors.transparent,
      margin: const EdgeInsets.all(20),
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
          dataSource: [_CartesianPoint(x: 0, y: 0, label: 'Own')],
          xValueMapper: (_CartesianPoint point, _) => point.x,
          yValueMapper: (_CartesianPoint point, _) => point.y,
          color: Colors.green,
          markerSettings: const MarkerSettings(
            height: 12,
            width: 12,
            shape: DataMarkerType.circle,
            borderColor: Colors.white,
            borderWidth: 2,
          ),
        ),
        // AIS vessels
        if (vesselPoints.isNotEmpty)
          ScatterSeries<_CartesianPoint, double>(
            dataSource: vesselPoints,
            xValueMapper: (_CartesianPoint point, _) => point.x,
            yValueMapper: (_CartesianPoint point, _) => point.y,
            color: vesselColor,
            markerSettings: MarkerSettings(
              height: 8,
              width: 8,
              shape: DataMarkerType.triangle,
              borderColor: vesselColor,
              borderWidth: 1,
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
        ));
      }

      series.add(LineSeries<_CartesianPoint, double>(
        dataSource: circlePoints,
        xValueMapper: (_CartesianPoint point, _) => point.x,
        yValueMapper: (_CartesianPoint point, _) => point.y,
        color: gridColor,
        width: 1,
      ));
    }

    // Radial lines (16 directions)
    for (int i = 0; i < 16; i++) {
      final angle = i * math.pi / 8 - math.pi / 2; // Start from North
      series.add(LineSeries<_CartesianPoint, double>(
        dataSource: [
          _CartesianPoint(x: 0, y: 0, label: ''),
          _CartesianPoint(
            x: maxRange * math.cos(angle),
            y: maxRange * math.sin(angle),
            label: '',
          ),
        ],
        xValueMapper: (_CartesianPoint point, _) => point.x,
        yValueMapper: (_CartesianPoint point, _) => point.y,
        color: radialColor,
        width: 1,
      ));
    }

    return series;
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

  /// Build range labels on the circles
  List<CartesianChartAnnotation> _buildRangeLabels(double maxRange, bool isDark) {
    final annotations = <CartesianChartAnnotation>[];

    // Add distance labels at the top (North) of each circle
    for (int i = 1; i <= 4; i++) {
      final range = maxRange / 4 * i;

      annotations.add(CartesianChartAnnotation(
        widget: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${range.toStringAsFixed(1)}',
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        coordinateUnit: CoordinateUnit.point,
        x: 0,
        y: range,
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
        label: vessel.mmsi,
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

    return ListView.builder(
      itemCount: sortedVessels.length,
      itemBuilder: (context, index) {
        final vessel = sortedVessels[index];
        final cpa = _calculateCPA(vessel);

        return ListTile(
          dense: true,
          leading: const Icon(
            Icons.navigation,
            color: Colors.grey,
            size: 20,
          ),
          title: Text(
            vessel.name ?? vessel.mmsi.substring(vessel.mmsi.length > 15 ? vessel.mmsi.length - 15 : 0),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Row(
            children: [
              Text(
                '${vessel.distance.toStringAsFixed(1)}nm',
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
                    color: cpa < 0.5 ? Colors.red.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'CPA ${cpa.toStringAsFixed(2)}nm',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cpa < 0.5 ? Colors.red : Colors.orange,
                    ),
                  ),
                )
              : null,
        );
      },
    );
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

  _VesselPoint({
    this.name,
    required this.mmsi,
    required this.bearing,
    required this.distance,
    this.cog,
    this.sog,
  });
}

class _CartesianPoint {
  final double x;
  final double y;
  final String label;

  _CartesianPoint({
    required this.x,
    required this.y,
    required this.label,
  });
}
