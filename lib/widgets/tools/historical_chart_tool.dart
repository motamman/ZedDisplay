import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../models/historical_data.dart';
import '../../services/signalk_service.dart';
import '../../services/historical_data_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/color_extensions.dart';
import '../historical_line_chart.dart';

/// Config-driven historical chart tool
class HistoricalChartTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const HistoricalChartTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<HistoricalChartTool> createState() => _HistoricalChartToolState();
}

class _HistoricalChartToolState extends State<HistoricalChartTool> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  HistoricalDataService? _historicalService;
  List<ChartDataSeries> _chartSeries = [];
  bool _isLoading = false;
  String? _errorMessage;
  Timer? _refreshTimer;
  DateTime? _lastRefreshTime;

  @override
  bool get wantKeepAlive => true; // Keep this widget alive

  @override
  void initState() {
    super.initState();
    _initializeService();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      // Restart auto-refresh timer if it was enabled
      final autoRefresh = widget.config.style.customProperties?['autoRefresh'] as bool? ?? false;
      if (autoRefresh && (_refreshTimer == null || !_refreshTimer!.isActive)) {
        _setupAutoRefresh();
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Pause timer to save battery
      _refreshTimer?.cancel();
    }
  }

  void _initializeService() {
    if (widget.signalKService.isConnected) {
      _historicalService = HistoricalDataService(
        serverUrl: widget.signalKService.serverUrl,
        useSecureConnection: widget.signalKService.useSecureConnection,
      );
      _loadData();
      _setupAutoRefresh();
    }
  }

  void _setupAutoRefresh() {
    _refreshTimer?.cancel();

    final autoRefresh = widget.config.style.customProperties?['autoRefresh'] as bool? ?? false;
    if (autoRefresh) {
      final intervalSeconds = widget.config.style.customProperties?['refreshInterval'] as int? ?? 60;
      _refreshTimer = Timer.periodic(
        Duration(seconds: intervalSeconds),
        (_) => _loadData(),
      );
    }
  }

  @override
  void didUpdateWidget(HistoricalChartTool oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      _loadData();
      _setupAutoRefresh();
    }
  }

  Future<void> _loadData() async {
    if (_historicalService == null || widget.config.dataSources.isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get duration from custom properties (default: 1h)
      final duration = widget.config.style.customProperties?['duration'] as String? ?? '1h';

      // Get resolution from custom properties (null means auto - let API optimize)
      final resolution = widget.config.style.customProperties?['resolution'] as int?;

      // Extract paths from data sources
      final paths = widget.config.dataSources.map((ds) => ds.path).toList();

      final response = await _historicalService!.fetchHistoricalData(
        paths: paths,
        duration: duration,
        resolution: resolution,
      );

      if (kDebugMode) {
        print('📊 Historical response: ${response.values.length} values, ${response.data.length} data rows');
        for (var i = 0; i < response.values.length; i++) {
          print('  Value $i: ${response.values[i].path} (${response.values[i].method})');
        }
      }

      final series = <ChartDataSeries>[];
      for (final dataSource in widget.config.dataSources) {
        final chartSeries = ChartDataSeries.fromHistoricalData(
          response,
          dataSource.path,
        );
        if (kDebugMode) {
          if (chartSeries == null) {
            print('❌ No data for path: ${dataSource.path}');
          } else {
            print('✅ Found ${chartSeries.points.length} points for: ${dataSource.path}');
          }
        }
        if (chartSeries != null && chartSeries.points.isNotEmpty) {
          series.add(chartSeries);
        }
      }

      if (mounted) {
        setState(() {
          _chartSeries = series;
          _isLoading = false;
          _lastRefreshTime = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    if (!widget.signalKService.isConnected) {
      return const Center(
        child: Text('Not connected to SignalK server'),
      );
    }

    if (widget.config.dataSources.isEmpty) {
      return const Center(
        child: Text('No data sources configured'),
      );
    }

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 32),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
      );
    }

    if (_chartSeries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.show_chart, size: 32, color: Colors.grey),
            const SizedBox(height: 8),
            const Text('No data available'),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
      );
    }

    // Get title from custom properties or generate from paths
    final duration = widget.config.style.customProperties?['duration'] as String? ?? '1h';
    final title = widget.config.style.customProperties?['title'] as String? ??
                  'Last $duration';

    final autoRefresh = widget.config.style.customProperties?['autoRefresh'] as bool? ?? false;

    // Get chart style from custom properties
    final chartStyleStr = widget.config.style.customProperties?['chartStyle'] as String? ?? 'area';
    final chartStyle = _parseChartStyle(chartStyleStr);

    // Parse primary color from config
    final primaryColor = widget.config.style.primaryColor?.toColor();

    return Stack(
      children: [
        HistoricalLineChart(
          series: _chartSeries,
          title: title,
          showLegend: widget.config.style.customProperties?['showLegend'] as bool? ?? true,
          showGrid: widget.config.style.customProperties?['showGrid'] as bool? ?? true,
          signalKService: widget.signalKService,
          chartStyle: chartStyle,
          primaryColor: primaryColor,
        ),
        // Refresh button in top-right corner
        Positioned(
          top: 8,
          right: 8,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Auto-refresh indicator
              if (autoRefresh)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.autorenew, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        _lastRefreshTime != null
                            ? '${_lastRefreshTime!.hour.toString().padLeft(2, '0')}:${_lastRefreshTime!.minute.toString().padLeft(2, '0')}'
                            : 'Auto',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              if (autoRefresh) const SizedBox(width: 8),
              // Manual refresh button
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _loadData,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(4),
                ),
                tooltip: 'Refresh chart',
              ),
            ],
          ),
        ),
      ],
    );
  }

  ChartStyle _parseChartStyle(String styleStr) {
    switch (styleStr.toLowerCase()) {
      case 'line':
        return ChartStyle.line;
      case 'column':
        return ChartStyle.column;
      case 'stepline':
        return ChartStyle.stepLine;
      default:
        return ChartStyle.area;
    }
  }
}

/// Builder for historical chart tools
class HistoricalChartBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'historical_chart',
      name: 'Historical Chart',
      description: 'Line chart showing historical data for up to 3 paths',
      category: ToolCategory.chart,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: true,
        minPaths: 1,
        maxPaths: 3,
        styleOptions: const [
          'primaryColor',
          'secondaryColor',
          'showLabel',
        ],
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return HistoricalChartTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
