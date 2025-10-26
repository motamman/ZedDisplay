import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'dart:async';
import '../services/signalk_service.dart';
import '../models/zone_data.dart';
import '../utils/conversion_utils.dart';

/// A real-time spline chart that displays live data from up to 3 SignalK paths
class RealtimeSplineChart extends StatefulWidget {
  final List<String> paths;
  final SignalKService signalKService;
  final String title;
  final int maxDataPoints;
  final Duration updateInterval;
  final bool showLegend;
  final bool showGrid;
  final Color? primaryColor;
  final List<ZoneDefinition>? zones;
  final bool showZones;

  const RealtimeSplineChart({
    super.key,
    required this.paths,
    required this.signalKService,
    this.title = 'Live Data',
    this.maxDataPoints = 50,
    this.updateInterval = const Duration(milliseconds: 500),
    this.showLegend = true,
    this.showGrid = true,
    this.primaryColor,
    this.zones,
    this.showZones = true,
  });

  @override
  State<RealtimeSplineChart> createState() => _RealtimeSplineChartState();
}

class _RealtimeSplineChartState extends State<RealtimeSplineChart> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  late List<List<_ChartData>> _seriesData;
  Timer? _updateTimer;
  DateTime? _startTime;
  double _cachedMinY = 0;
  double _cachedMaxY = 100;

  @override
  bool get wantKeepAlive => true; // Keep accumulated data points alive

  @override
  void initState() {
    super.initState();
    _seriesData = List.generate(widget.paths.length, (_) => []);
    _startTime = DateTime.now();

    // Initialize range with defaults
    final initialRange = _calculateYAxisRange();
    _cachedMinY = initialRange.min;
    _cachedMaxY = initialRange.max;

    _startRealTimeUpdates();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      // Restart updates when app comes back to foreground
      if (_updateTimer == null || !_updateTimer!.isActive) {
        _startRealTimeUpdates();
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Optionally pause timer to save battery
      // Comment out if you want continuous updates via foreground service
      _updateTimer?.cancel();
    }
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
      final now = DateTime.now();
      final timeValue = now.millisecondsSinceEpoch;

      for (int i = 0; i < widget.paths.length; i++) {
        final path = widget.paths[i];
        // Use client-side conversions
        final value = ConversionUtils.getConvertedValue(widget.signalKService, path);

        if (value != null) {
          // Create new list with updated data (don't mutate existing)
          final newData = List<_ChartData>.from(_seriesData[i]);
          newData.add(_ChartData(timeValue, value));

          // Keep only maxDataPoints (sliding window)
          if (newData.length > widget.maxDataPoints) {
            newData.removeAt(0);
          }

          // Replace the list entirely to trigger chart update
          _seriesData[i] = newData;
        }
      }

      // Recalculate Y-axis range after data update
      final range = _calculateYAxisRange();
      _cachedMinY = range.min;
      _cachedMaxY = range.max;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

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

    if (widget.paths.isEmpty) {
      return Card(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.show_chart, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              const Text('No data paths configured'),
            ],
          ),
        ),
      );
    }

    final colors = _getSeriesColors();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get unit from first path
    final unit = widget.signalKService.getUnitSymbol(widget.paths.first);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SfCartesianChart(
                legend: Legend(
                  isVisible: widget.showLegend && widget.paths.length > 1,
                  position: LegendPosition.bottom,
                  overflowMode: LegendItemOverflowMode.wrap,
                ),
                tooltipBehavior: TooltipBehavior(
                  enable: true,
                  format: 'point.y ${unit ?? ''}',
                  textStyle: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                primaryXAxis: NumericAxis(
                  majorGridLines: MajorGridLines(
                    width: widget.showGrid ? 1 : 0,
                    color: Colors.grey.withValues(alpha: 0.2),
                  ),
                  axisLine: const AxisLine(width: 1),
                  labelStyle: const TextStyle(fontSize: 10),
                  title: const AxisTitle(
                    text: 'Time →',
                    textStyle: TextStyle(fontSize: 12),
                  ),
                  // Format time as mm:ss
                  axisLabelFormatter: (AxisLabelRenderDetails details) {
                    final timestamp = details.value.toInt();
                    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
                    return ChartAxisLabel(
                      '${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}',
                      details.textStyle,
                    );
                  },
                  // Auto interval for cleaner labels
                  desiredIntervals: 5,
                ),
                primaryYAxis: NumericAxis(
                  labelFormat: unit != null ? '{value} $unit' : '{value}',
                  majorGridLines: MajorGridLines(
                    width: widget.showGrid ? 1 : 0,
                    color: Colors.grey.withValues(alpha: 0.2),
                  ),
                  axisLine: const AxisLine(width: 1),
                  labelStyle: const TextStyle(fontSize: 10),
                  plotBands: _getPlotBands(),
                  // Dynamic range based on actual data (cached to avoid double calculation)
                  minimum: _cachedMinY,
                  maximum: _cachedMaxY,
                ),
                series: List.generate(
                  widget.paths.length,
                  (index) => SplineSeries<_ChartData, int>(
                    name: _getSeriesLabel(widget.paths[index]),
                    dataSource: _seriesData[index],
                    xValueMapper: (_ChartData data, _) => data.time,
                    yValueMapper: (_ChartData data, _) => data.value,
                    color: colors[index],
                    width: 2,
                    splineType: SplineType.natural,
                    animationDuration: 0, // No animation for real-time updates
                    markerSettings: const MarkerSettings(
                      isVisible: false,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Color> _getSeriesColors() {
    final baseColor = widget.primaryColor ?? Colors.blue;

    return [
      baseColor,
      _shiftHue(baseColor, 120),
      _shiftHue(baseColor, 240),
    ];
  }

  Color _shiftHue(Color color, double degrees) {
    final hslColor = HSLColor.fromColor(color);
    final newHue = (hslColor.hue + degrees) % 360;
    return hslColor.withHue(newHue).toColor();
  }

  String _getSeriesLabel(String path) {
    final pathParts = path.split('.');
    final shortPath = pathParts.length > 2
        ? pathParts.sublist(pathParts.length - 2).join('.')
        : path;
    return shortPath;
  }

  /// Convert zone definitions to plot bands for the chart
  List<PlotBand> _getPlotBands() {
    if (!widget.showZones || widget.zones == null || widget.zones!.isEmpty) {
      return [];
    }

    return widget.zones!.map((zone) {
      final color = _getZoneColor(zone.state);
      return PlotBand(
        isVisible: true,
        start: zone.lower ?? double.negativeInfinity,
        end: zone.upper ?? double.infinity,
        color: color.withValues(alpha: 0.15),
        borderColor: color.withValues(alpha: 0.3),
        borderWidth: 1,
      );
    }).toList();
  }

  /// Get color for a zone state
  Color _getZoneColor(ZoneState state) {
    switch (state) {
      case ZoneState.nominal:
        return Colors.blue;
      case ZoneState.alert:
        return Colors.yellow.shade700;
      case ZoneState.warn:
        return Colors.orange;
      case ZoneState.alarm:
        return Colors.red;
      case ZoneState.emergency:
        return Colors.red.shade900;
      case ZoneState.normal:
        return Colors.grey;
    }
  }

  /// Calculate Y-axis range based on current data
  ({double min, double max}) _calculateYAxisRange() {
    double? minValue;
    double? maxValue;

    // Find min/max across all series
    for (final series in _seriesData) {
      for (final point in series) {
        if (minValue == null || point.value < minValue) {
          minValue = point.value;
        }
        if (maxValue == null || point.value > maxValue) {
          maxValue = point.value;
        }
      }
    }

    // If no data, use default range
    if (minValue == null || maxValue == null) {
      return (min: 0, max: 100);
    }

    // Add 15% padding on each side to prevent clipping
    final range = maxValue - minValue;
    final padding = range > 0 ? range * 0.15 : 10.0; // Use 15% padding, or minimum 10 if range is 0

    return (
      min: minValue - padding,
      max: maxValue + padding,
    );
  }
}

class _ChartData {
  final int time;
  final double value;

  _ChartData(this.time, this.value);
}
