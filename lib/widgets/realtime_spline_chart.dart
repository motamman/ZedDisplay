import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'dart:async';
import '../services/signalk_service.dart';

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
  });

  @override
  State<RealtimeSplineChart> createState() => _RealtimeSplineChartState();
}

class _RealtimeSplineChartState extends State<RealtimeSplineChart> {
  late List<List<_ChartData>> _seriesData;
  Timer? _updateTimer;
  int _time = 0;

  @override
  void initState() {
    super.initState();
    _seriesData = List.generate(widget.paths.length, (_) => []);
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
      for (int i = 0; i < widget.paths.length; i++) {
        final path = widget.paths[i];
        final value = widget.signalKService.getConvertedValue(path);

        if (value != null) {
          _seriesData[i].add(_ChartData(_time, value));

          // Keep only maxDataPoints
          if (_seriesData[i].length > widget.maxDataPoints) {
            _seriesData[i].removeAt(0);
          }
        }
      }
      _time++;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                    text: 'Time',
                    textStyle: TextStyle(fontSize: 12),
                  ),
                ),
                primaryYAxis: NumericAxis(
                  labelFormat: unit != null ? '{value} $unit' : '{value}',
                  majorGridLines: MajorGridLines(
                    width: widget.showGrid ? 1 : 0,
                    color: Colors.grey.withValues(alpha: 0.2),
                  ),
                  axisLine: const AxisLine(width: 1),
                  labelStyle: const TextStyle(fontSize: 10),
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
}

class _ChartData {
  final int time;
  final double value;

  _ChartData(this.time, this.value);
}
