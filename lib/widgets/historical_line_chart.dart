import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/historical_data.dart';
import 'package:intl/intl.dart';

/// A line chart widget that displays up to 3 historical data series
class HistoricalLineChart extends StatelessWidget {
  final List<ChartDataSeries> series;
  final String title;
  final bool showLegend;
  final bool showGrid;

  const HistoricalLineChart({
    Key? key,
    required this.series,
    this.title = 'Historical Data',
    this.showLegend = true,
    this.showGrid = true,
  }) : super(key: key);

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
            if (showLegend) _buildLegend(context),
            const SizedBox(height: 16),
            Expanded(
              child: _buildChart(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend(BuildContext context) {
    final colors = _getSeriesColors();
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: List.generate(
        series.length,
        (index) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: colors[index],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _getSeriesLabel(series[index]),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(BuildContext context) {
    final colors = _getSeriesColors();

    // Find global min/max for time axis
    DateTime? minTime;
    DateTime? maxTime;
    for (final s in series) {
      for (final point in s.points) {
        if (minTime == null || point.timestamp.isBefore(minTime)) {
          minTime = point.timestamp;
        }
        if (maxTime == null || point.timestamp.isAfter(maxTime)) {
          maxTime = point.timestamp;
        }
      }
    }

    if (minTime == null || maxTime == null) {
      return const Center(child: Text('No data points'));
    }

    // Find global min/max for value axis
    double? minValue;
    double? maxValue;
    for (final s in series) {
      if (s.minValue != null &&
          (minValue == null || s.minValue! < minValue)) {
        minValue = s.minValue;
      }
      if (s.maxValue != null &&
          (maxValue == null || s.maxValue! > maxValue)) {
        maxValue = s.maxValue;
      }
    }

    // Add padding to value range
    final valueRange = (maxValue ?? 1) - (minValue ?? 0);
    final minY = (minValue ?? 0) - valueRange * 0.1;
    final maxY = (maxValue ?? 1) + valueRange * 0.1;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: showGrid,
          drawVerticalLine: true,
          horizontalInterval: (maxY - minY) / 5,
          verticalInterval:
              (maxTime.millisecondsSinceEpoch - minTime.millisecondsSinceEpoch) /
                  5,
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval:
                  (maxTime.millisecondsSinceEpoch - minTime.millisecondsSinceEpoch) /
                      4,
              getTitlesWidget: (value, meta) {
                final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                final formatter = DateFormat('HH:mm');
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    formatter.format(date),
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (maxY - minY) / 5,
              reservedSize: 42,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 10),
                  textAlign: TextAlign.left,
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(
            color: Theme.of(context).dividerColor,
          ),
        ),
        minX: minTime.millisecondsSinceEpoch.toDouble(),
        maxX: maxTime.millisecondsSinceEpoch.toDouble(),
        minY: minY,
        maxY: maxY,
        lineBarsData: List.generate(
          series.length,
          (index) => _buildLineBarsData(
            series[index],
            colors[index],
          ),
        ),
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: Theme.of(context).cardColor.withOpacity(0.9),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final date = DateTime.fromMillisecondsSinceEpoch(
                  spot.x.toInt(),
                );
                final formatter = DateFormat('HH:mm:ss');
                return LineTooltipItem(
                  '${_getSeriesLabel(series[spot.barIndex])}\n${formatter.format(date)}\n${spot.y.toStringAsFixed(2)}',
                  TextStyle(
                    color: colors[spot.barIndex],
                    fontWeight: FontWeight.bold,
                  ),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }

  LineChartBarData _buildLineBarsData(
    ChartDataSeries series,
    Color color,
  ) {
    return LineChartBarData(
      spots: series.points.map((point) {
        return FlSpot(
          point.timestamp.millisecondsSinceEpoch.toDouble(),
          point.value,
        );
      }).toList(),
      isCurved: true,
      color: color,
      barWidth: 2,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: color.withOpacity(0.1),
      ),
    );
  }

  List<Color> _getSeriesColors() {
    return [
      Colors.blue,
      Colors.red,
      Colors.green,
    ];
  }

  String _getSeriesLabel(ChartDataSeries series) {
    // Extract the last part of the path for a shorter label
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
