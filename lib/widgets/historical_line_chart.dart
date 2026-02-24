import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../models/historical_data.dart';
import '../services/signalk_service.dart';
import '../utils/conversion_utils.dart';
import 'package:intl/intl.dart';

/// Available chart display styles
enum ChartStyle {
  area,      // Spline area with fill (default)
  line,      // Spline line only
  column,    // Vertical column chart
  stepLine,  // Step line chart
}

/// A line chart widget that displays up to 3 historical data series
/// Now powered by Syncfusion for professional charting
class HistoricalLineChart extends StatelessWidget {
  final List<ChartDataSeries> series;
  final String title;
  final bool showLegend;
  final bool showGrid;
  final SignalKService? signalKService;
  final ChartStyle chartStyle;
  final Color? primaryColor;
  final bool showMovingAverage;
  final int movingAverageWindow;

  const HistoricalLineChart({
    super.key,
    required this.series,
    this.title = 'Historical Data',
    this.showLegend = true,
    this.showGrid = true,
    this.signalKService,
    this.chartStyle = ChartStyle.area,
    this.primaryColor,
    this.showMovingAverage = false,
    this.movingAverageWindow = 5,
  });

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) {
      return Card(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'No data available',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _buildChart(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(BuildContext context) {
    final colors = _getSeriesColors();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get unit symbol from first series (all series should have same unit)
    String? unit;
    if (signalKService != null && series.isNotEmpty) {
      unit = ConversionUtils.getUnitSymbol(signalKService!, series.first.path);
    }

    return SfCartesianChart(
      // Legend configuration
      legend: Legend(
        isVisible: showLegend,
        position: LegendPosition.bottom,
        overflowMode: LegendItemOverflowMode.wrap,
      ),

      // Tooltip configuration
      tooltipBehavior: TooltipBehavior(
        enable: true,
        format: 'point.x\npoint.y ${unit ?? ''}',
        textStyle: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),

      // Zoom/pan behavior
      zoomPanBehavior: ZoomPanBehavior(
        enablePinching: true,
        enablePanning: true,
        enableDoubleTapZooming: true,
      ),

      // Primary X axis (DateTime)
      primaryXAxis: DateTimeAxis(
        dateFormat: DateFormat('HH:mm'),
        majorGridLines: MajorGridLines(
          width: showGrid ? 1 : 0,
          color: Colors.grey.withValues(alpha: 0.2),
        ),
        axisLine: const AxisLine(width: 1),
        labelStyle: const TextStyle(fontSize: 10),
      ),

      // Primary Y axis (values)
      primaryYAxis: NumericAxis(
        labelFormat: unit != null ? '{value} $unit' : '{value}',
        majorGridLines: MajorGridLines(
          width: showGrid ? 1 : 0,
          color: Colors.grey.withValues(alpha: 0.2),
        ),
        axisLine: const AxisLine(width: 1),
        labelStyle: const TextStyle(fontSize: 10),
      ),

      // Series data
      series: [
        // Main data series
        ...List.generate(
          series.length,
          (index) => _buildSeries(series[index], colors[index]),
        ),
        // Moving average series (if enabled)
        if (showMovingAverage)
          ...List.generate(
            series.length,
            (index) => _buildMovingAverageSeries(series[index], colors[index]),
          ),
      ],
    );
  }

  /// Build series based on chart style
  CartesianSeries<_ChartPoint, DateTime> _buildSeries(
    ChartDataSeries seriesData,
    Color color,
  ) {
    final dataPoints = seriesData.points
        .map((point) => _ChartPoint(point.timestamp, point.value))
        .toList();

    switch (chartStyle) {
      case ChartStyle.line:
        return SplineSeries<_ChartPoint, DateTime>(
          name: _getSeriesLabel(seriesData),
          dataSource: dataPoints,
          xValueMapper: (_ChartPoint point, _) => point.timestamp,
          yValueMapper: (_ChartPoint point, _) => point.value,
          color: color,
          width: 2,
          splineType: SplineType.natural,
          markerSettings: const MarkerSettings(
            isVisible: false,
          ),
        );

      case ChartStyle.column:
        return ColumnSeries<_ChartPoint, DateTime>(
          name: _getSeriesLabel(seriesData),
          dataSource: dataPoints,
          xValueMapper: (_ChartPoint point, _) => point.timestamp,
          yValueMapper: (_ChartPoint point, _) => point.value,
          color: color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        );

      case ChartStyle.stepLine:
        return StepLineSeries<_ChartPoint, DateTime>(
          name: _getSeriesLabel(seriesData),
          dataSource: dataPoints,
          xValueMapper: (_ChartPoint point, _) => point.timestamp,
          yValueMapper: (_ChartPoint point, _) => point.value,
          color: color,
          width: 2,
          markerSettings: const MarkerSettings(
            isVisible: false,
          ),
        );

      case ChartStyle.area:
        return SplineAreaSeries<_ChartPoint, DateTime>(
          name: _getSeriesLabel(seriesData),
          dataSource: dataPoints,
          xValueMapper: (_ChartPoint point, _) => point.timestamp,
          yValueMapper: (_ChartPoint point, _) => point.value,
          color: color,
          borderColor: color,
          borderWidth: 2,
          opacity: 0.1, // Area fill opacity
          splineType: SplineType.natural,
          markerSettings: const MarkerSettings(
            isVisible: false,
          ),
        );
    }
  }

  /// Build moving average series
  SplineSeries<_ChartPoint, DateTime> _buildMovingAverageSeries(
    ChartDataSeries seriesData,
    Color color,
  ) {
    final dataPoints = seriesData.points
        .map((point) => _ChartPoint(point.timestamp, point.value))
        .toList();

    // Calculate moving average
    final movingAvgPoints = _calculateMovingAverage(dataPoints, movingAverageWindow);

    return SplineSeries<_ChartPoint, DateTime>(
      name: '${_getSeriesLabel(seriesData)} (MA$movingAverageWindow)',
      dataSource: movingAvgPoints,
      xValueMapper: (_ChartPoint point, _) => point.timestamp,
      yValueMapper: (_ChartPoint point, _) => point.value,
      color: color.withValues(alpha: 0.6),
      width: 2,
      dashArray: const <double>[5, 5], // Dashed line
      splineType: SplineType.natural,
      markerSettings: const MarkerSettings(
        isVisible: false,
      ),
    );
  }

  /// Calculate moving average from data points
  List<_ChartPoint> _calculateMovingAverage(List<_ChartPoint> data, int window) {
    if (data.length < window) return [];

    final result = <_ChartPoint>[];

    for (int i = window - 1; i < data.length; i++) {
      double sum = 0;
      for (int j = 0; j < window; j++) {
        sum += data[i - j].value;
      }
      final avg = sum / window;
      result.add(_ChartPoint(data[i].timestamp, avg));
    }

    return result;
  }

  List<Color> _getSeriesColors() {
    // Use primaryColor for first series, or default to blue
    final baseColor = primaryColor ?? Colors.blue;

    // Generate complementary colors for multiple series
    return [
      baseColor,
      _shiftHue(baseColor, 120), // Complementary color
      _shiftHue(baseColor, 240), // Triadic color
    ];
  }

  /// Shift the hue of a color by a given degree
  Color _shiftHue(Color color, double degrees) {
    final hslColor = HSLColor.fromColor(color);
    final newHue = (hslColor.hue + degrees) % 360;
    return hslColor.withHue(newHue).toColor();
  }

  String _getSeriesLabel(ChartDataSeries series) {
    // Use custom label if provided
    if (series.label != null && series.label!.isNotEmpty) {
      // Still append method suffix for EMA/SMA
      if (series.method == 'ema') {
        return '${series.label} (EMA)';
      } else if (series.method == 'sma') {
        return '${series.label} (SMA)';
      }
      return series.label!;
    }

    // Otherwise, extract the last part of the path for a shorter label
    final pathParts = series.path.split('.');
    final shortPath = pathParts.length > 2
        ? pathParts.sublist(pathParts.length - 2).join('.')
        : series.path;

    if (series.method == 'ema') {
      return '$shortPath (EMA)';
    } else if (series.method == 'sma') {
      return '$shortPath (SMA)';
    }
    return shortPath;
  }
}

/// Chart data point class for Syncfusion
class _ChartPoint {
  final DateTime timestamp;
  final double value;

  _ChartPoint(this.timestamp, this.value);
}
