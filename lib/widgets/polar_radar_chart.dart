import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import 'dart:math' as math;
import '../services/signalk_service.dart';

/// A polar radar chart that displays velocity and angle data from SignalK
///
/// This chart plots data in polar coordinates with:
/// - Angular position determined by the angle path (e.g., wind direction, course)
/// - Radial distance determined by the magnitude path (e.g., wind speed, boat speed)
///
/// The chart uses a compass-style display with 8 cardinal/intercardinal directions
class PolarRadarChart extends StatefulWidget {
  final String anglePath;
  final String magnitudePath;
  final String? angleLabel;
  final String? magnitudeLabel;
  final SignalKService signalKService;
  final String title;
  final Duration historyDuration; // Time window for data (e.g., last 60 seconds)
  final Duration updateInterval;
  final Color? primaryColor;
  final Color? fillColor;
  final bool showLabels;
  final bool showGrid;
  final double maxMagnitude; // Max value for radial axis (auto if 0)

  const PolarRadarChart({
    super.key,
    required this.anglePath,
    required this.magnitudePath,
    this.angleLabel,
    this.magnitudeLabel,
    required this.signalKService,
    this.title = 'Polar Chart',
    this.historyDuration = const Duration(seconds: 60),
    this.updateInterval = const Duration(milliseconds: 500),
    this.primaryColor,
    this.fillColor,
    this.showLabels = true,
    this.showGrid = true,
    this.maxMagnitude = 0, // 0 = auto-scale
  });

  @override
  State<PolarRadarChart> createState() => _PolarRadarChartState();
}

class _PolarRadarChartState extends State<PolarRadarChart>
    with AutomaticKeepAliveClientMixin {
  Timer? _updateTimer;
  final List<_PolarDataPoint> _dataHistory = [];

  // Calculated max for auto-scaling
  double _calculatedMax = 10.0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _startRealTimeUpdates();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _startRealTimeUpdates() {
    _updateTimer = Timer.periodic(widget.updateInterval, (_) {
      if (mounted) {
        _updateChartData();
      }
    });
  }

  void _updateChartData() {
    setState(() {
      // Read current angle and magnitude from SignalK using MetadataStore
      // Angle: convert from radians to degrees for display and calculations
      final angleDataPoint = widget.signalKService.getValue(widget.anglePath);
      final angleRaw = (angleDataPoint?.value as num?)?.toDouble();
      final angleMetadata = widget.signalKService.metadataStore.get(widget.anglePath);
      final angleValue = angleRaw != null ? angleMetadata?.convert(angleRaw) ?? angleRaw : null;

      final magnitudeDataPoint = widget.signalKService.getValue(widget.magnitudePath);
      final magnitudeRaw = (magnitudeDataPoint?.value as num?)?.toDouble();
      final magnitudeMetadata = widget.signalKService.metadataStore.get(widget.magnitudePath);
      final magnitudeValue = magnitudeRaw != null ? magnitudeMetadata?.convert(magnitudeRaw) ?? magnitudeRaw : null;

      if (angleValue != null && magnitudeValue != null) {
        final now = DateTime.now();

        // Add to history
        _dataHistory.add(_PolarDataPoint(
          angle: angleValue,
          magnitude: magnitudeValue,
          timestamp: now,
        ));

        // Remove data points older than the time window
        final cutoffTime = now.subtract(widget.historyDuration);
        _dataHistory.removeWhere((point) => point.timestamp.isBefore(cutoffTime));

        // Update calculated max if auto-scaling
        if (widget.maxMagnitude == 0 && _dataHistory.isNotEmpty) {
          final maxInHistory = _dataHistory
              .map((p) => p.magnitude)
              .reduce((a, b) => a > b ? a : b);
          _calculatedMax = maxInHistory * 1.2; // 20% padding
          if (_calculatedMax < 1) _calculatedMax = 10; // Minimum scale
        }
      }
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = widget.primaryColor ?? Colors.blue;
    final fillColor = widget.fillColor ?? primaryColor.withValues(alpha: 0.3);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            Expanded(
              child: _buildRadarChart(primaryColor, fillColor, isDark),
            ),
            const SizedBox(height: 8),
            _buildValueLabels(context),
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'LIVE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildValueLabels(BuildContext context) {
    // Get current values using MetadataStore
    final angleDataPoint = widget.signalKService.getValue(widget.anglePath);
    final angleRaw = (angleDataPoint?.value as num?)?.toDouble();
    final angleMetadata = widget.signalKService.metadataStore.get(widget.anglePath);
    final angleValue = angleRaw != null ? angleMetadata?.convert(angleRaw) ?? angleRaw : null;

    final magnitudeDataPoint = widget.signalKService.getValue(widget.magnitudePath);
    final magnitudeRaw = (magnitudeDataPoint?.value as num?)?.toDouble();
    final magnitudeMetadata = widget.signalKService.metadataStore.get(widget.magnitudePath);
    final magnitudeValue = magnitudeRaw != null ? magnitudeMetadata?.convert(magnitudeRaw) ?? magnitudeRaw : null;

    // Get unit symbols from MetadataStore
    final angleSymbol = angleMetadata?.symbol ?? '°';
    final magnitudeSymbol = magnitudeMetadata?.symbol ?? '';

    // Format display values with units
    final angleDisplay = angleValue != null
        ? '${angleValue.toStringAsFixed(0)}$angleSymbol'
        : '--';
    final magnitudeDisplay = magnitudeValue != null
        ? '${magnitudeValue.toStringAsFixed(1)} $magnitudeSymbol'.trim()
        : '--';

    // Use custom labels if provided, otherwise extract from paths
    final angleLabel = widget.angleLabel ?? () {
      final angleParts = widget.anglePath.split('.');
      return angleParts.length > 1
          ? angleParts.sublist(angleParts.length - 1).join('.')
          : 'Angle';
    }();

    final magnitudeLabel = widget.magnitudeLabel ?? () {
      final magnitudeParts = widget.magnitudePath.split('.');
      return magnitudeParts.length > 1
          ? magnitudeParts.sublist(magnitudeParts.length - 1).join('.')
          : 'Velocity';
    }();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Expanded(
          child: _buildLabel(
            context,
            angleLabel,
            angleDisplay,
            Icons.explore,
            isDark,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildLabel(
            context,
            magnitudeLabel,
            magnitudeDisplay,
            Icons.speed,
            isDark,
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isDark ? Colors.white70 : Colors.black54),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white60 : Colors.black45,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadarChart(Color primaryColor, Color fillColor, bool isDark) {
    // Get max magnitude for scaling
    final maxMag = widget.maxMagnitude > 0 ? widget.maxMagnitude : _calculatedMax;

    // Convert polar data history to radar chart format
    // We use 8 axes representing compass directions: N, NE, E, SE, S, SW, W, NW
    final radarData = _convertToRadarData(maxMag);

    return RadarChart(
      RadarChartData(
        radarShape: RadarShape.circle,
        radarBackgroundColor: Colors.transparent,
        radarBorderData: BorderSide(
          color: isDark ? Colors.white24 : Colors.black12,
          width: 2,
        ),
        gridBorderData: BorderSide(
          color: isDark ? Colors.white12 : Colors.black12,
          width: 1,
        ),
        tickBorderData: BorderSide(
          color: isDark ? Colors.white12 : Colors.black12,
          width: 1,
        ),
        tickCount: 4,
        radarTouchData: RadarTouchData(enabled: false),
        getTitle: (index, angle) {
          if (!widget.showLabels) return const RadarChartTitle(text: '');

          // Labels for 8 compass directions
          final labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
          return RadarChartTitle(
            text: labels[index % 8],
            angle: 0, // Keep text horizontal
          );
        },
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
        ticksTextStyle: TextStyle(
          color: isDark ? Colors.white70 : Colors.black54,
          fontSize: 10,
        ),
        dataSets: [
          RadarDataSet(
            fillColor: fillColor,
            borderColor: primaryColor,
            borderWidth: 3,
            entryRadius: 3,
            dataEntries: radarData,
          ),
        ],
      ),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeInOut,
    );
  }

  /// Convert polar data points to radar chart entries
  /// Projects current angle/magnitude onto 8 compass directions
  List<RadarEntry> _convertToRadarData(double maxMag) {
    // 8 axes at 45-degree intervals: 0°, 45°, 90°, 135°, 180°, 225°, 270°, 315°
    final compassAngles = [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0];
    final values = List<double>.filled(8, 0.0);

    if (_dataHistory.isEmpty) {
      return compassAngles.map((angle) => const RadarEntry(value: 0)).toList();
    }

    // Project recent data points onto compass directions
    // Use a weighted average based on angular distance
    for (final point in _dataHistory) {
      // Find contribution to each compass direction
      for (int i = 0; i < compassAngles.length; i++) {
        final compassAngle = compassAngles[i];
        final angleDiff = _angleDifference(point.angle, compassAngle);

        // Use Gaussian-like weighting: stronger contribution for closer angles
        // Only apply weight if angle is within 60° of the compass direction
        if (angleDiff < 60) {
          final weight = math.exp(-math.pow(angleDiff / 30, 2));
          values[i] = math.max(values[i], point.magnitude * weight);
        }
      }
    }

    // Clamp very small values to 0 (below 1% of max)
    final threshold = maxMag * 0.01;
    return values.map((v) => RadarEntry(value: v < threshold ? 0 : v)).toList();
  }

  /// Calculate the smallest angle difference between two angles
  double _angleDifference(double angle1, double angle2) {
    var diff = (angle1 - angle2).abs();
    if (diff > 180) {
      diff = 360 - diff;
    }
    return diff;
  }
}

class _PolarDataPoint {
  final double angle;
  final double magnitude;
  final DateTime timestamp;

  _PolarDataPoint({
    required this.angle,
    required this.magnitude,
    required this.timestamp,
  });
}
