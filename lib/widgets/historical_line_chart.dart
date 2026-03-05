import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../models/historical_data.dart';
import '../services/signalk_service.dart';
import '../utils/chart_axis_utils.dart';
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
///
/// Smoothed series (SMA/EMA) are rendered as dashed lines when provided
/// from the server via path:aggregation:smoothing:param syntax.
class HistoricalLineChart extends StatelessWidget {
  final List<ChartDataSeries> series;
  final String title;
  final bool showLegend;
  final bool showGrid;
  final SignalKService? signalKService;
  final ChartStyle chartStyle;
  final Color? primaryColor;
  final String? primaryAxisBaseUnit;     // For dual Y-axis support
  final String? secondaryAxisBaseUnit;   // For dual Y-axis support

  const HistoricalLineChart({
    super.key,
    required this.series,
    this.title = 'Historical Data',
    this.showLegend = true,
    this.showGrid = true,
    this.signalKService,
    this.chartStyle = ChartStyle.area,
    this.primaryColor,
    this.primaryAxisBaseUnit,
    this.secondaryAxisBaseUnit,
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

    // Get unit symbol from first series using MetadataStore (single source of truth)
    String? primaryUnit;
    String? secondaryUnit;
    if (signalKService != null && series.isNotEmpty) {
      primaryUnit = signalKService!.metadataStore.get(series.first.path)?.symbol;
      // Find secondary unit if we have a secondary axis
      if (secondaryAxisBaseUnit != null) {
        for (final s in series) {
          final baseUnit = signalKService!.metadataStore.get(s.path)?.baseUnit;
          if (baseUnit == secondaryAxisBaseUnit) {
            secondaryUnit = signalKService!.metadataStore.get(s.path)?.symbol;
            break;
          }
        }
      }
    }

    // Calculate Y-axis ranges
    final primaryRange = _calculateAxisRange(isSecondary: false);
    final secondaryRange = secondaryAxisBaseUnit != null
        ? _calculateAxisRange(isSecondary: true)
        : null;

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
        format: 'point.x\npoint.y',
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
        name: 'primaryYAxis',
        labelFormat: primaryUnit != null ? '{value} $primaryUnit' : '{value}',
        minimum: primaryRange.min,
        maximum: primaryRange.max,
        majorGridLines: MajorGridLines(
          width: showGrid ? 1 : 0,
          color: Colors.grey.withValues(alpha: 0.2),
        ),
        axisLine: const AxisLine(width: 1),
        labelStyle: const TextStyle(fontSize: 10),
      ),

      // Secondary Y-axis (right side) when paths have different base units
      axes: secondaryAxisBaseUnit != null && secondaryRange != null ? <ChartAxis>[
        NumericAxis(
          name: 'secondaryYAxis',
          opposedPosition: true,  // Right side
          labelFormat: secondaryUnit != null ? '{value} $secondaryUnit' : '{value}',
          minimum: secondaryRange.min,
          maximum: secondaryRange.max,
          majorGridLines: MajorGridLines(
            width: showGrid ? 1 : 0,
            dashArray: const <double>[5, 5],  // Dashed grid lines
            color: Colors.grey.withValues(alpha: 0.2),
          ),
          axisLine: const AxisLine(width: 1),
          labelStyle: const TextStyle(fontSize: 10),
        ),
      ] : <ChartAxis>[],

      // Series data - smoothed series are styled differently (dashed line)
      series: List.generate(
        series.length,
        (index) => _buildSeries(series[index], colors[index % colors.length]),
      ),
    );
  }

  /// Calculate Y-axis range for primary or secondary axis.
  ({double min, double max}) _calculateAxisRange({required bool isSecondary}) {
    double? minValue;
    double? maxValue;

    for (final s in series) {
      // Determine which axis this series belongs to using the helper
      String? unitKey;
      if (signalKService != null) {
        unitKey = ChartAxisUtils.getUnitKey(
          s.path,
          signalKService!.metadataStore,
        );
      }
      final assignment = ChartAxisUtils.getAxisAssignment(
        unitKey,
        primaryAxisBaseUnit,
        secondaryAxisBaseUnit,
      );

      final belongsToAxis = isSecondary
          ? assignment == 'secondary'
          : assignment == 'primary';

      if (!belongsToAxis) continue;

      if (s.minValue != null && (minValue == null || s.minValue! < minValue)) {
        minValue = s.minValue;
      }
      if (s.maxValue != null && (maxValue == null || s.maxValue! > maxValue)) {
        maxValue = s.maxValue;
      }
    }

    // If no data, use default range
    if (minValue == null || maxValue == null) {
      return (min: 0, max: 100);
    }

    // Add 15% padding
    final range = maxValue - minValue;
    final padding = range > 0 ? range * 0.15 : 10.0;

    return (
      min: minValue - padding,
      max: maxValue + padding,
    );
  }

  /// Build series based on chart style
  /// Smoothed series (SMA/EMA) are rendered as dashed spline lines
  CartesianSeries<_ChartPoint, DateTime> _buildSeries(
    ChartDataSeries seriesData,
    Color color,
  ) {
    final dataPoints = seriesData.points
        .map((point) => _ChartPoint(point.timestamp, point.value))
        .toList();

    // Determine axis assignment using the helper
    String? unitKey;
    if (signalKService != null) {
      unitKey = ChartAxisUtils.getUnitKey(
        seriesData.path,
        signalKService!.metadataStore,
      );
    }
    final axisName = ChartAxisUtils.getAxisName(
      unitKey,
      primaryAxisBaseUnit,
      secondaryAxisBaseUnit,
    );

    // Get label with display unit
    final label = _getSeriesLabelWithUnit(seriesData);

    // Smoothed series always render as dashed spline line
    if (seriesData.isSmoothed) {
      return SplineSeries<_ChartPoint, DateTime>(
        name: label,
        dataSource: dataPoints,
        xValueMapper: (_ChartPoint point, _) => point.timestamp,
        yValueMapper: (_ChartPoint point, _) => point.value,
        yAxisName: axisName,
        color: color,
        width: 3,
        dashArray: const <double>[8, 4],
        splineType: SplineType.natural,
        markerSettings: const MarkerSettings(
          isVisible: false,
        ),
      );
    }

    switch (chartStyle) {
      case ChartStyle.line:
        return SplineSeries<_ChartPoint, DateTime>(
          name: label,
          dataSource: dataPoints,
          xValueMapper: (_ChartPoint point, _) => point.timestamp,
          yValueMapper: (_ChartPoint point, _) => point.value,
          yAxisName: axisName,
          color: color,
          width: 2,
          splineType: SplineType.natural,
          markerSettings: const MarkerSettings(
            isVisible: false,
          ),
        );

      case ChartStyle.column:
        return ColumnSeries<_ChartPoint, DateTime>(
          name: label,
          dataSource: dataPoints,
          xValueMapper: (_ChartPoint point, _) => point.timestamp,
          yValueMapper: (_ChartPoint point, _) => point.value,
          yAxisName: axisName,
          color: color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        );

      case ChartStyle.stepLine:
        return StepLineSeries<_ChartPoint, DateTime>(
          name: label,
          dataSource: dataPoints,
          xValueMapper: (_ChartPoint point, _) => point.timestamp,
          yValueMapper: (_ChartPoint point, _) => point.value,
          yAxisName: axisName,
          color: color,
          width: 2,
          markerSettings: const MarkerSettings(
            isVisible: false,
          ),
        );

      case ChartStyle.area:
        return SplineAreaSeries<_ChartPoint, DateTime>(
          name: label,
          dataSource: dataPoints,
          xValueMapper: (_ChartPoint point, _) => point.timestamp,
          yValueMapper: (_ChartPoint point, _) => point.value,
          yAxisName: axisName,
          // Use gradient for fill to keep line solid while fading the area
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.4),
              color.withValues(alpha: 0.05),
            ],
          ),
          borderColor: color,
          borderWidth: 2.5,
          splineType: SplineType.natural,
          markerSettings: const MarkerSettings(
            isVisible: false,
          ),
        );
    }
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
      return series.label!;
    }

    // Extract the last part of the path for a shorter label
    final pathParts = series.path.split('.');
    final shortPath = pathParts.length > 2
        ? pathParts.sublist(pathParts.length - 2).join('.')
        : series.path;

    // Append smoothing info if this is a smoothed series
    if (series.isSmoothed) {
      final smoothingType = series.smoothing!.toUpperCase();
      if (series.window != null) {
        if (series.smoothing == 'ema') {
          return '$shortPath ($smoothingType α=${series.window! / 1000})';
        }
        return '$shortPath ($smoothingType ${series.window})';
      }
      return '$shortPath ($smoothingType)';
    }

    return shortPath;
  }

  /// Get series label with user's preferred display unit symbol.
  /// Example: "Speed (kn)" or "Water Temp (F)"
  String _getSeriesLabelWithUnit(ChartDataSeries seriesData) {
    final baseLabel = _getSeriesLabel(seriesData);
    final symbol = signalKService?.metadataStore.get(seriesData.path)?.symbol;

    if (symbol != null && symbol.isNotEmpty) {
      return '$baseLabel ($symbol)';
    }
    return baseLabel;
  }
}

/// Chart data point class for Syncfusion
class _ChartPoint {
  final DateTime timestamp;
  final double value;

  _ChartPoint(this.timestamp, this.value);
}
