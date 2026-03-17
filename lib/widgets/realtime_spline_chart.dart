import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'dart:async';
import '../services/signalk_service.dart';
import '../models/zone_data.dart';
import '../models/tool_config.dart';
import '../utils/chart_axis_utils.dart';

/// Static cache to preserve chart data across widget disposal (screen lock, swipe, reconnect).
class _RealtimeChartCache {
  static final Map<String, _CachedChartState> _cache = {};

  static void save(String key, _CachedChartState state) => _cache[key] = state;
  static _CachedChartState? get(String key) => _cache[key];
}

class _CachedChartState {
  final List<List<_ChartData>> seriesData;
  final Set<int> hiddenSeries;
  final double cachedMinY;
  final double cachedMaxY;
  final double cachedSecondaryMinY;
  final double cachedSecondaryMaxY;

  _CachedChartState({
    required this.seriesData,
    required this.hiddenSeries,
    required this.cachedMinY,
    required this.cachedMaxY,
    required this.cachedSecondaryMinY,
    required this.cachedSecondaryMaxY,
  });
}

/// A real-time spline chart that displays live data from up to 3 SignalK paths
class RealtimeSplineChart extends StatefulWidget {
  final List<DataSource> dataSources;
  final SignalKService signalKService;
  final String title;
  final int maxDataPoints;
  final Duration updateInterval;
  final bool showLegend;
  final bool showGrid;
  final Color? primaryColor;
  final List<ZoneDefinition>? zones;
  final bool showZones;
  final bool showMovingAverage;
  final int movingAverageWindow;
  final bool showValue;

  const RealtimeSplineChart({
    super.key,
    required this.dataSources,
    required this.signalKService,
    this.title = 'Live Data',
    this.maxDataPoints = 50,
    this.updateInterval = const Duration(milliseconds: 500),
    this.showLegend = true,
    this.showGrid = true,
    this.primaryColor,
    this.zones,
    this.showZones = true,
    this.showMovingAverage = false,
    this.movingAverageWindow = 5,
    this.showValue = true,
  });

  @override
  State<RealtimeSplineChart> createState() => _RealtimeSplineChartState();
}

class _RealtimeSplineChartState extends State<RealtimeSplineChart> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  late List<List<_ChartData>> _seriesData;
  Timer? _updateTimer;
  double _cachedMinY = 0;
  double _cachedMaxY = 100;

  // Dual Y-axis support
  String? _primaryAxisBaseUnit;
  String? _secondaryAxisBaseUnit;
  double _cachedSecondaryMinY = 0;
  double _cachedSecondaryMaxY = 100;

  // Track which series are hidden (by index)
  late Set<int> _hiddenSeries;

  @override
  bool get wantKeepAlive => true; // Keep accumulated data points alive

  String get _cacheKey => widget.dataSources.map((ds) => ds.path).join('|');

  @override
  void initState() {
    super.initState();

    // Restore from static cache if available (survives swipe/screen lock)
    final cached = _RealtimeChartCache.get(_cacheKey);
    if (cached != null && cached.seriesData.length == widget.dataSources.length) {
      _seriesData = cached.seriesData;
      _hiddenSeries = Set.from(cached.hiddenSeries);
      _cachedMinY = cached.cachedMinY;
      _cachedMaxY = cached.cachedMaxY;
      _cachedSecondaryMinY = cached.cachedSecondaryMinY;
      _cachedSecondaryMaxY = cached.cachedSecondaryMaxY;
    } else {
      _seriesData = List.generate(widget.dataSources.length, (_) => []);
      _hiddenSeries = {};
    }

    // Determine axis units for dual Y-axis support
    _determineAxisUnits();

    // Initialize range with defaults if no cached data
    if (cached == null) {
      final initialRange = _calculateYAxisRange(isSecondary: false);
      _cachedMinY = initialRange.min;
      _cachedMaxY = initialRange.max;

      if (_secondaryAxisBaseUnit != null) {
        final secondaryRange = _calculateYAxisRange(isSecondary: true);
        _cachedSecondaryMinY = secondaryRange.min;
        _cachedSecondaryMaxY = secondaryRange.max;
      }
    }

    _startRealTimeUpdates();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Determine primary and secondary axis base units from data sources.
  void _determineAxisUnits() {
    final units = ChartAxisUtils.determineAxisUnits(
      widget.dataSources,
      widget.signalKService.metadataStore,
    );
    _primaryAxisBaseUnit = units.primary;
    _secondaryAxisBaseUnit = units.secondary;
  }

  @override
  void dispose() {
    // Save state to static cache before disposal
    _RealtimeChartCache.save(_cacheKey, _CachedChartState(
      seriesData: _seriesData,
      hiddenSeries: _hiddenSeries,
      cachedMinY: _cachedMinY,
      cachedMaxY: _cachedMaxY,
      cachedSecondaryMinY: _cachedSecondaryMinY,
      cachedSecondaryMaxY: _cachedSecondaryMaxY,
    ));
    WidgetsBinding.instance.removeObserver(this);
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(RealtimeSplineChart oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle changes in dataSources count
    if (widget.dataSources.length != oldWidget.dataSources.length) {
      // Resize series data arrays
      while (_seriesData.length < widget.dataSources.length) {
        _seriesData.add([]);
      }
      // If dataSources were removed, trim the arrays
      if (_seriesData.length > widget.dataSources.length) {
        _seriesData = _seriesData.sublist(0, widget.dataSources.length);
      }
      // Re-determine axis units with new data sources
      _determineAxisUnits();
    }
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
      // Re-check axis units if not yet determined (metadata may have arrived)
      if (_primaryAxisBaseUnit == null && widget.dataSources.length > 1) {
        _determineAxisUnits();
      }

      final now = DateTime.now();
      final timeValue = now.millisecondsSinceEpoch;

      for (int i = 0; i < widget.dataSources.length; i++) {
        final dataSource = widget.dataSources[i];
        // Use MetadataStore (single source of truth) for conversions
        final dataPoint = widget.signalKService.getValue(dataSource.path);
        double? value;
        if (dataPoint?.value is num) {
          final rawValue = (dataPoint!.value as num).toDouble();
          final metadata = widget.signalKService.metadataStore.get(dataSource.path);
          value = metadata?.convert(rawValue) ?? rawValue;
        }

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

      // Recalculate Y-axis ranges after data update
      final range = _calculateYAxisRange(isSecondary: false);
      _cachedMinY = range.min;
      _cachedMaxY = range.max;

      if (_secondaryAxisBaseUnit != null) {
        final secondaryRange = _calculateYAxisRange(isSecondary: true);
        _cachedSecondaryMinY = secondaryRange.min;
        _cachedSecondaryMaxY = secondaryRange.max;
      }

      // Save to static cache on each update to guard against unexpected disposal
      _RealtimeChartCache.save(_cacheKey, _CachedChartState(
        seriesData: _seriesData,
        hiddenSeries: _hiddenSeries,
        cachedMinY: _cachedMinY,
        cachedMaxY: _cachedMaxY,
        cachedSecondaryMinY: _cachedSecondaryMinY,
        cachedSecondaryMaxY: _cachedSecondaryMaxY,
      ));
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

    if (widget.dataSources.isEmpty) {
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

    // Get unit symbols for axis labels (match historical chart pattern)
    String? primaryUnit;
    String? secondaryUnit;
    if (widget.dataSources.isNotEmpty) {
      primaryUnit = widget.signalKService.metadataStore.get(widget.dataSources.first.path)?.symbol;
      if (_secondaryAxisBaseUnit != null) {
        for (final ds in widget.dataSources) {
          // Use same fallback chain as ChartAxisUtils.getUnitKey()
          final unitKey = ChartAxisUtils.getUnitKey(
            ds.path,
            widget.signalKService.metadataStore,
            storedBaseUnit: ds.baseUnit,
          );
          if (unitKey == _secondaryAxisBaseUnit) {
            secondaryUnit = widget.signalKService.metadataStore.get(ds.path)?.symbol;
            break;
          }
        }
      }
    }

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
                  margin: const EdgeInsets.only(right: 40),
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
                zoomPanBehavior: ZoomPanBehavior(
                  enablePinching: true,
                  enablePanning: true,
                  enableDoubleTapZooming: true,
                  zoomMode: ZoomMode.x,
                ),
                // Legend - compact to maximize chart height, wrap if needed
                legend: Legend(
                  isVisible: widget.showLegend,
                  position: LegendPosition.bottom,
                  overflowMode: LegendItemOverflowMode.wrap,
                  itemPadding: 4,
                  iconHeight: 10,
                  iconWidth: 10,
                  textStyle: const TextStyle(fontSize: 11),
                ),
                onLegendTapped: (LegendTapArgs args) {
                  // Track which series are hidden so MA follows
                  final index = args.seriesIndex ?? 0;
                  // Toggle after a short delay to let chart update first
                  Future.microtask(() {
                    if (mounted) {
                      setState(() {
                        if (_hiddenSeries.contains(index)) {
                          _hiddenSeries.remove(index);
                        } else {
                          _hiddenSeries.add(index);
                        }
                      });
                    }
                  });
                },
                tooltipBehavior: TooltipBehavior(
                  enable: true,
                  format: 'point.y',
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
                  name: 'primaryYAxis',
                  axisLabelFormatter: (AxisLabelRenderDetails details) {
                    return ChartAxisLabel(
                      ChartAxisUtils.formatAxisValue(details.value.toDouble(), unit: primaryUnit),
                      details.textStyle,
                    );
                  },
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
                // Secondary Y-axis (right side) when paths have different base units
                axes: _secondaryAxisBaseUnit != null ? <ChartAxis>[
                  NumericAxis(
                    name: 'secondaryYAxis',
                    opposedPosition: true,  // Right side
                    axisLabelFormatter: (AxisLabelRenderDetails details) {
                      return ChartAxisLabel(
                        ChartAxisUtils.formatAxisValue(details.value.toDouble(), unit: secondaryUnit),
                        details.textStyle,
                      );
                    },
                    minimum: _cachedSecondaryMinY,
                    maximum: _cachedSecondaryMaxY,
                    majorGridLines: MajorGridLines(
                      width: widget.showGrid ? 1 : 0,
                      dashArray: const <double>[5, 5],  // Dashed grid lines
                      color: Colors.grey.withValues(alpha: 0.2),
                    ),
                    axisLine: const AxisLine(width: 1),
                    labelStyle: const TextStyle(fontSize: 10),
                  ),
                ] : <ChartAxis>[],
                series: [
                  // Main data series
                  ...List.generate(
                    widget.dataSources.length,
                    (index) {
                      final ds = widget.dataSources[index];
                      final unitKey = ChartAxisUtils.getUnitKey(
                        ds.path,
                        widget.signalKService.metadataStore,
                        storedBaseUnit: ds.baseUnit,
                      );
                      final axisName = ChartAxisUtils.getAxisName(
                        unitKey,
                        _primaryAxisBaseUnit,
                        _secondaryAxisBaseUnit,
                      );

                      return SplineSeries<_ChartData, int>(
                        name: _getSeriesLabelWithUnit(ds, index),
                        dataSource: _hiddenSeries.contains(index) ? [] : _seriesData[index],
                        xValueMapper: (_ChartData data, _) => data.time,
                        yValueMapper: (_ChartData data, _) => data.value,
                        yAxisName: axisName,  // Assign to correct axis
                        color: _hiddenSeries.contains(index) ? colors[index].withValues(alpha: 0.3) : colors[index],
                        width: 2,
                        splineType: SplineType.natural,
                        animationDuration: 0, // No animation for real-time updates
                        markerSettings: const MarkerSettings(
                          isVisible: false,
                        ),
                        trendlines: widget.showMovingAverage ? <Trendline>[
                          Trendline(
                            type: TrendlineType.movingAverage,
                            period: widget.movingAverageWindow,
                            color: colors[index].withValues(alpha: 0.6),
                            width: 2,
                            dashArray: const <double>[5, 5],
                          ),
                        ] : null,
                      );
                    },
                  ),
                ],
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

  String _getSeriesLabel(DataSource dataSource) {
    // Use custom label if provided
    if (dataSource.label != null && dataSource.label!.isNotEmpty) {
      return dataSource.label!;
    }

    // Otherwise, generate label from path
    final pathParts = dataSource.path.split('.');
    final shortPath = pathParts.length > 2
        ? pathParts.sublist(pathParts.length - 2).join('.')
        : dataSource.path;
    return shortPath;
  }

  /// Get series label with user's preferred display unit symbol.
  /// Example: "Speed (kn)" or "Water Temp (F)"
  String _getSeriesLabelWithUnit(DataSource dataSource, int index) {
    final baseLabel = _getSeriesLabel(dataSource);
    final symbol = widget.signalKService.metadataStore.get(dataSource.path)?.symbol;

    final data = _seriesData[index];

    // Build label with optional unit symbol and current value
    String label = baseLabel;
    if (symbol != null && symbol.isNotEmpty) {
      label = '$label ($symbol)';
    }

    // Append current value if showValue is enabled and we have data
    if (widget.showValue && data.isNotEmpty) {
      final currentValue = data.last.value.toStringAsFixed(1);
      label = '$label: $currentValue';
    }

    return label;
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

  /// Calculate Y-axis range based on current data.
  /// If [isSecondary] is true, only considers series assigned to secondary axis.
  ({double min, double max}) _calculateYAxisRange({required bool isSecondary}) {
    double? minValue;
    double? maxValue;

    // Find min/max across series assigned to the specified axis
    for (int i = 0; i < _seriesData.length; i++) {
      // Check if this series belongs to the axis we're calculating
      final ds = widget.dataSources[i];
      final unitKey = ChartAxisUtils.getUnitKey(
        ds.path,
        widget.signalKService.metadataStore,
        storedBaseUnit: ds.baseUnit,
      );
      final assignment = ChartAxisUtils.getAxisAssignment(
        unitKey,
        _primaryAxisBaseUnit,
        _secondaryAxisBaseUnit,
      );

      final belongsToAxis = isSecondary
          ? assignment == 'secondary'
          : assignment == 'primary';

      if (!belongsToAxis) continue;

      for (final point in _seriesData[i]) {
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
