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
class HistoricalLineChart extends StatefulWidget {
  final List<ChartDataSeries> series;
  final String title;
  final bool showLegend;
  final bool showGrid;
  final SignalKService? signalKService;
  final ChartStyle chartStyle;
  final Color? primaryColor;
  final String? primaryAxisBaseUnit;     // For dual Y-axis support
  final String? secondaryAxisBaseUnit;   // For dual Y-axis support
  final String duration;                 // For X-axis date format

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
    this.duration = '1h',
  });

  @override
  State<HistoricalLineChart> createState() => _HistoricalLineChartState();
}

class _HistoricalLineChartState extends State<HistoricalLineChart> {
  // 3-state visibility: 0 = all visible, 1 = raw hidden (MA only), 2 = all hidden
  final Map<int, int> _seriesVisibility = {};

  /// Build a label showing the full data time range, e.g. "Mar 15 2:00 PM – Mar 15 4:00 PM"
  String _dataRangeLabel() {
    DateTime? earliest;
    DateTime? latest;
    for (final s in widget.series) {
      for (final p in s.points) {
        if (earliest == null || p.timestamp.isBefore(earliest)) {
          earliest = p.timestamp;
        }
        if (latest == null || p.timestamp.isAfter(latest)) {
          latest = p.timestamp;
        }
      }
    }
    if (earliest == null || latest == null) return '';
    final sameDay = earliest.year == latest.year &&
        earliest.month == latest.month &&
        earliest.day == latest.day;
    if (sameDay) {
      final dayFmt = DateFormat('MMM d');
      final timeFmt = DateFormat('h:mm a');
      return '${dayFmt.format(earliest)} ${timeFmt.format(earliest)} – ${timeFmt.format(latest)}';
    }
    final fmt = DateFormat('MMM d h:mm a');
    return '${fmt.format(earliest)} – ${fmt.format(latest)}';
  }

  /// Map duration to initial zoom factor so longer windows start zoomed in
  double _initialZoomFactor() {
    switch (widget.duration) {
      case '2h':  return 0.5;
      case '6h':  return 0.333;
      case '12h': return 0.25;
      case '1d':  return 0.25;
      case '2d':  return 0.25;
      case '1w':  return 0.143;
      default:    return 1.0;
    }
  }

  /// Check if a parent index has a paired smoothed series
  bool _hasSmoothedSeries(int parentIndex) {
    if (parentIndex < 0 || parentIndex >= widget.series.length) return false;
    final parentPath = widget.series[parentIndex].path;
    return widget.series.any((s) =>
      s.isSmoothed && s.path == parentPath);
  }

  /// Get appropriate date format based on duration
  DateFormat _getDateFormat() {
    switch (widget.duration) {
      case '15m':
      case '30m':
      case '1h':
      case '2h':
        return DateFormat('h:mm a');      // 10:30 AM
      case '6h':
      case '12h':
        return DateFormat('h a');          // 10 AM
      case '1d':
        return DateFormat('h a');          // 10 AM
      case '2d':
      case '1w':
        return DateFormat('E h a');        // Mon 10 AM
      default:
        return DateFormat('h:mm a');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.series.isEmpty) {
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
              widget.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(
              _dataRangeLabel(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
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
    if (widget.signalKService != null && widget.series.isNotEmpty) {
      primaryUnit = widget.signalKService!.metadataStore.get(widget.series.first.path)?.symbol;
      // Find secondary unit if we have a secondary axis
      if (widget.secondaryAxisBaseUnit != null) {
        for (final s in widget.series) {
          // Use same fallback chain as ChartAxisUtils.getUnitKey()
          final unitKey = ChartAxisUtils.getUnitKey(
            s.path,
            widget.signalKService!.metadataStore,
          );
          if (unitKey == widget.secondaryAxisBaseUnit) {
            secondaryUnit = widget.signalKService!.metadataStore.get(s.path)?.symbol;
            break;
          }
        }
      }
    }

    // Calculate Y-axis ranges
    final primaryRange = _calculateAxisRange(isSecondary: false);
    final secondaryRange = widget.secondaryAxisBaseUnit != null
        ? _calculateAxisRange(isSecondary: true)
        : null;

    return SfCartesianChart(
      // Legend configuration - compact to maximize chart height, wrap if needed
      legend: Legend(
        isVisible: widget.showLegend,
        position: LegendPosition.bottom,
        overflowMode: LegendItemOverflowMode.wrap,
        itemPadding: 4,
        iconHeight: 10,
        iconWidth: 10,
        textStyle: const TextStyle(fontSize: 11),
      ),
      // Toggle series visibility when legend item is tapped
      // 3-state cycle for series with smoothed sibling: 0→1→2→0
      // Binary toggle for series without smoothed sibling: 0→2→0
      onLegendTapped: (LegendTapArgs args) {
        final index = args.seriesIndex ?? 0;
        Future.microtask(() {
          if (mounted) {
            setState(() {
              final current = _seriesVisibility[index] ?? 0;
              if (_hasSmoothedSeries(index)) {
                // 3-state: all visible → MA only → all hidden → all visible
                _seriesVisibility[index] = (current + 1) % 3;
              } else {
                // Binary: all visible → all hidden → all visible
                _seriesVisibility[index] = current == 0 ? 2 : 0;
              }
            });
          }
        });
      },
      // Adjust legend icon appearance based on visibility state
      onLegendItemRender: (LegendRenderArgs args) {
        final index = args.seriesIndex ?? 0;
        final state = _seriesVisibility[index] ?? 0;
        // Explicitly set color for every state — Syncfusion caches previous values
        if (state == 1) {
          // MA only: reduce opacity to indicate partial visibility
          args.color = args.color?.withValues(alpha: 0.4);
        } else if (state == 2) {
          // All hidden: grey out
          args.color = Colors.grey.withValues(alpha: 0.3);
        } else {
          // All visible: restore full series color
          args.color = colors[index % colors.length];
        }
      },

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
        zoomMode: ZoomMode.x,
      ),

      // Primary X axis (DateTime) — longer durations start zoomed in on recent data
      primaryXAxis: DateTimeAxis(
        dateFormat: _getDateFormat(),
        initialZoomFactor: _initialZoomFactor(),
        initialZoomPosition: 1.0,
        majorGridLines: MajorGridLines(
          width: widget.showGrid ? 1 : 0,
          color: Colors.grey.withValues(alpha: 0.2),
        ),
        axisLine: const AxisLine(width: 1),
        labelStyle: const TextStyle(fontSize: 10),
      ),

      // Primary Y axis (values)
      primaryYAxis: NumericAxis(
        name: 'primaryYAxis',
        axisLabelFormatter: (AxisLabelRenderDetails details) {
          return ChartAxisLabel(
            ChartAxisUtils.formatAxisValue(details.value.toDouble(), unit: primaryUnit),
            details.textStyle,
          );
        },
        minimum: primaryRange.min,
        maximum: primaryRange.max,
        majorGridLines: MajorGridLines(
          width: widget.showGrid ? 1 : 0,
          color: Colors.grey.withValues(alpha: 0.2),
        ),
        axisLine: const AxisLine(width: 1),
        labelStyle: const TextStyle(fontSize: 10),
      ),

      // Secondary Y-axis (right side) when paths have different base units
      axes: widget.secondaryAxisBaseUnit != null && secondaryRange != null ? <ChartAxis>[
        NumericAxis(
          name: 'secondaryYAxis',
          opposedPosition: true,  // Right side
          axisLabelFormatter: (AxisLabelRenderDetails details) {
            return ChartAxisLabel(
              ChartAxisUtils.formatAxisValue(details.value.toDouble(), unit: secondaryUnit),
              details.textStyle,
            );
          },
          minimum: secondaryRange.min,
          maximum: secondaryRange.max,
          majorGridLines: MajorGridLines(
            width: widget.showGrid ? 1 : 0,
            dashArray: const <double>[5, 5],  // Dashed grid lines
            color: Colors.grey.withValues(alpha: 0.2),
          ),
          axisLine: const AxisLine(width: 1),
          labelStyle: const TextStyle(fontSize: 10),
        ),
      ] : <ChartAxis>[],

      // Series data - smoothed series are styled differently (dashed line)
      // Smoothed series use parent color (same path, not smoothed) for visual grouping
      // When parent series is hidden, smoothed series is also hidden
      series: List.generate(
        widget.series.length,
        (index) {
          final s = widget.series[index];
          // Find the parent index: if smoothed, find parent series index
          int parentIndex = index;
          if (s.isSmoothed) {
            for (int i = 0; i < widget.series.length; i++) {
              if (widget.series[i].path == s.path && !widget.series[i].isSmoothed) {
                parentIndex = i;
                break;
              }
            }
          }
          // Determine visibility from 3-state map
          final state = _seriesVisibility[parentIndex] ?? 0;
          final bool isHidden;
          if (s.isSmoothed) {
            // Smoothed series: hidden only in state 2 (all hidden)
            isHidden = state == 2;
          } else {
            // Raw series: hidden in state 1 (MA only) and state 2 (all hidden)
            isHidden = state >= 1;
          }
          return _buildSeries(s, colors[parentIndex % colors.length], isHidden: isHidden);
        },
      ),
    );
  }

  /// Calculate Y-axis range for primary or secondary axis.
  ({double min, double max}) _calculateAxisRange({required bool isSecondary}) {
    double? minValue;
    double? maxValue;

    for (final s in widget.series) {
      // Determine which axis this series belongs to using the helper
      String? unitKey;
      if (widget.signalKService != null) {
        unitKey = ChartAxisUtils.getUnitKey(
          s.path,
          widget.signalKService!.metadataStore,
        );
      }
      final assignment = ChartAxisUtils.getAxisAssignment(
        unitKey,
        widget.primaryAxisBaseUnit,
        widget.secondaryAxisBaseUnit,
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

    // Don't let padding drag the axis below zero when all data is non-negative
    final paddedMin = minValue >= 0
        ? (minValue - padding).clamp(0.0, double.infinity)
        : minValue - padding;

    return (
      min: paddedMin,
      max: maxValue + padding,
    );
  }

  /// Build series based on chart style
  /// Smoothed series (SMA/EMA) are rendered as dashed spline lines
  CartesianSeries<_ChartPoint, DateTime> _buildSeries(
    ChartDataSeries seriesData,
    Color color, {
    bool isHidden = false,
  }) {
    // Return empty data when series is hidden (like realtime chart)
    final dataPoints = isHidden
        ? <_ChartPoint>[]
        : seriesData.points
            .map((point) => _ChartPoint(point.timestamp, point.value))
            .toList();

    // Determine axis assignment using the helper
    String? unitKey;
    if (widget.signalKService != null) {
      unitKey = ChartAxisUtils.getUnitKey(
        seriesData.path,
        widget.signalKService!.metadataStore,
      );
    }
    final axisName = ChartAxisUtils.getAxisName(
      unitKey,
      widget.primaryAxisBaseUnit,
      widget.secondaryAxisBaseUnit,
    );

    // Get label with display unit
    final label = _getSeriesLabelWithUnit(seriesData);

    // Smoothed series always render as dashed spline line (matching realtime chart style)
    if (seriesData.isSmoothed) {
      return SplineSeries<_ChartPoint, DateTime>(
        name: label,
        dataSource: dataPoints,
        xValueMapper: (_ChartPoint point, _) => point.timestamp,
        yValueMapper: (_ChartPoint point, _) => point.value,
        yAxisName: axisName,
        color: color.withValues(alpha: 0.6),  // Semi-transparent like realtime chart
        width: 2,                              // Match realtime chart width
        dashArray: const <double>[5, 5],       // Match realtime chart dash pattern
        splineType: SplineType.natural,
        isVisibleInLegend: false,              // Hide from legend like realtime chart
        markerSettings: const MarkerSettings(
          isVisible: false,
        ),
      );
    }

    switch (widget.chartStyle) {
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
              color.withValues(alpha: 0.15),
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
    final baseColor = widget.primaryColor ?? Colors.blue;

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
          return '$shortPath ($smoothingType α=${series.window})';
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
    final symbol = widget.signalKService?.metadataStore.get(seriesData.path)?.symbol;

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
