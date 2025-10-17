import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

/// A radial bar chart that displays multiple data sources as concentric rings
/// Each data source is represented by a ring, with up to 4 paths supported
class RadialBarChart extends StatelessWidget {
  final List<RadialBarData> data;
  final String? title;
  final bool showLegend;
  final bool showLabels;
  final Color? primaryColor;
  final double innerRadius;
  final double gap;

  const RadialBarChart({
    super.key,
    required this.data,
    this.title,
    this.showLegend = true,
    this.showLabels = true,
    this.primaryColor,
    this.innerRadius = 0.4,
    this.gap = 0.08,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.donut_large, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('No data available'),
          ],
        ),
      );
    }

    final colors = _getSeriesColors();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null && title!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 16, right: 16),
            child: Text(
              title!,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
        Expanded(
          child: SfCircularChart(
            legend: Legend(
              isVisible: showLegend && data.length > 1,
              position: LegendPosition.bottom,
              overflowMode: LegendItemOverflowMode.wrap,
              textStyle: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            tooltipBehavior: TooltipBehavior(
              enable: true,
              format: 'point.x: point.y',
              textStyle: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            series: _buildSeries(colors),
          ),
        ),
      ],
    );
  }

  List<RadialBarSeries<RadialBarData, String>> _buildSeries(List<Color> colors) {
    final series = <RadialBarSeries<RadialBarData, String>>[];

    for (int i = 0; i < data.length; i++) {
      final item = data[i];

      // Calculate radius for this ring
      // Each ring gets progressively larger from inside out
      final radiusPerRing = (1.0 - innerRadius) / data.length;
      final thisInnerRadius = innerRadius + (i * radiusPerRing);
      final thisRadius = thisInnerRadius + radiusPerRing - gap;

      series.add(
        RadialBarSeries<RadialBarData, String>(
          name: item.label,
          dataSource: [item],
          xValueMapper: (RadialBarData data, _) => data.label,
          yValueMapper: (RadialBarData data, _) => data.value,
          pointColorMapper: (RadialBarData data, _) => colors[i % colors.length],

          // Ring sizing
          innerRadius: '${(thisInnerRadius * 100).toStringAsFixed(0)}%',
          radius: '${(thisRadius * 100).toStringAsFixed(0)}%',

          // Ring appearance
          gap: '${(gap * 100).toStringAsFixed(0)}%',
          cornerStyle: CornerStyle.bothCurve,

          // Maximum value for the ring (if specified)
          maximumValue: item.maxValue,

          // Track appearance (background ring)
          trackColor: Colors.grey.withValues(alpha: 0.2),
          trackBorderColor: Colors.grey.withValues(alpha: 0.3),
          trackBorderWidth: 1,
          trackOpacity: 0.3,

          // Data labels
          dataLabelSettings: DataLabelSettings(
            isVisible: showLabels,
            labelPosition: ChartDataLabelPosition.outside,
            textStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            builder: (data, point, series, pointIndex, seriesIndex) {
              final radialData = data as RadialBarData;
              final percentage = radialData.maxValue != null
                  ? ((radialData.value / radialData.maxValue!) * 100).toStringAsFixed(0)
                  : radialData.value.toStringAsFixed(1);

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  radialData.unit.isNotEmpty
                      ? '${radialData.formattedValue ?? radialData.value.toStringAsFixed(1)} ${radialData.unit}'
                      : radialData.formattedValue ?? percentage,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return series;
  }

  List<Color> _getSeriesColors() {
    final baseColor = primaryColor ?? Colors.blue;

    // Generate colors with hue shifts for visual distinction
    return List.generate(
      4,
      (index) => _shiftHue(baseColor, index * 90.0),
    );
  }

  Color _shiftHue(Color color, double degrees) {
    final hslColor = HSLColor.fromColor(color);
    final newHue = (hslColor.hue + degrees) % 360;
    return hslColor.withHue(newHue).toColor();
  }
}

/// Data class for a single radial bar in the chart
class RadialBarData {
  final String label;
  final double value;
  final double? maxValue;
  final String unit;
  final String? formattedValue;

  const RadialBarData({
    required this.label,
    required this.value,
    this.maxValue,
    this.unit = '',
    this.formattedValue,
  });
}
