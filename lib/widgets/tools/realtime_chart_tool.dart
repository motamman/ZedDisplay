import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../models/zone_data.dart';
import '../../services/signalk_service.dart';
import '../../services/zones_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/color_extensions.dart';
import '../realtime_spline_chart.dart';

/// Config-driven real-time chart tool
class RealtimeChartTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const RealtimeChartTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<RealtimeChartTool> createState() => _RealtimeChartToolState();
}

class _RealtimeChartToolState extends State<RealtimeChartTool> {
  ZonesService? _zonesService;
  List<ZoneDefinition>? _zones;

  @override
  void initState() {
    super.initState();
    _initializeZonesService();
  }

  void _initializeZonesService() {
    // Wait for SignalK to be connected before fetching zones
    // This ensures the auth token is available
    if (kDebugMode) {
      print('🔌 Initializing zones service. SignalK connected: ${widget.signalKService.isConnected}');
    }

    if (widget.signalKService.isConnected) {
      _createZonesServiceAndFetch();
    } else {
      // Listen for connection and fetch zones once connected
      if (kDebugMode) {
        print('   Waiting for SignalK connection...');
      }
      widget.signalKService.addListener(_onSignalKConnectionChanged);
    }
  }

  void _onSignalKConnectionChanged() {
    if (kDebugMode) {
      print('🔔 SignalK connection changed. Connected: ${widget.signalKService.isConnected}, ZonesService: ${_zonesService != null ? "exists" : "null"}');
    }

    if (widget.signalKService.isConnected && _zonesService == null) {
      widget.signalKService.removeListener(_onSignalKConnectionChanged);
      _createZonesServiceAndFetch();
    }
  }

  void _createZonesServiceAndFetch() {
    final token = widget.signalKService.authToken;
    if (kDebugMode) {
      print('🔑 Creating ZonesService with token: ${token != null ? "present (${token.token.substring(0, 20)}...)" : "NULL"}');
      print('   Server: ${widget.signalKService.serverUrl}');
      print('   Secure: ${widget.signalKService.useSecureConnection}');
    }

    _zonesService = ZonesService(
      serverUrl: widget.signalKService.serverUrl,
      useSecureConnection: widget.signalKService.useSecureConnection,
      authToken: token,
    );
    _fetchZones();
  }

  @override
  void dispose() {
    widget.signalKService.removeListener(_onSignalKConnectionChanged);
    super.dispose();
  }

  Future<void> _fetchZones() async {
    if (_zonesService == null || widget.config.dataSources.isEmpty) {
      return;
    }

    try {
      // Fetch zones for the first path (primary data source)
      final firstPath = widget.config.dataSources.first.path;
      final pathZones = await _zonesService!.fetchZones(firstPath);

      if (mounted && pathZones != null && pathZones.hasZones) {
        setState(() {
          _zones = pathZones.zones;
        });
      }
    } catch (e) {
      // Silently fail - zones are optional
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.config.dataSources.isEmpty) {
      return const Center(child: Text('No data sources configured'));
    }

    // Get configuration from custom properties
    final maxDataPoints = widget.config.style.customProperties?['maxDataPoints'] as int? ?? 50;
    final updateIntervalMs = widget.config.style.customProperties?['updateInterval'] as int? ?? 500;
    final showLegend = widget.config.style.customProperties?['showLegend'] as bool? ?? true;
    final showGrid = widget.config.style.customProperties?['showGrid'] as bool? ?? true;
    final showMovingAverage = widget.config.style.customProperties?['showMovingAverage'] as bool? ?? false;
    final movingAverageWindow = widget.config.style.customProperties?['movingAverageWindow'] as int? ?? 5;

    // Parse primary color
    final primaryColor = widget.config.style.primaryColor?.toColor();

    // Generate title from data sources
    final title = widget.config.style.customProperties?['title'] as String? ??
                  _generateTitle(widget.config.dataSources);

    // Check if zones should be shown (can be disabled via config)
    final showZones = widget.config.style.customProperties?['showZones'] as bool? ?? true;

    return RealtimeSplineChart(
      dataSources: widget.config.dataSources,
      signalKService: widget.signalKService,
      title: title,
      maxDataPoints: maxDataPoints,
      updateInterval: Duration(milliseconds: updateIntervalMs),
      showLegend: showLegend,
      showGrid: showGrid,
      primaryColor: primaryColor,
      zones: _zones,
      showZones: showZones,
      showMovingAverage: showMovingAverage,
      movingAverageWindow: movingAverageWindow,
      showValue: widget.config.style.showValue ?? true,
    );
  }

  String _generateTitle(List<DataSource> dataSources) {
    if (dataSources.length == 1) {
      // Use custom label if available
      if (dataSources[0].label != null && dataSources[0].label!.isNotEmpty) {
        return dataSources[0].label!;
      }
      // Otherwise generate from path
      final parts = dataSources[0].path.split('.');
      return parts.length > 2
          ? parts.sublist(parts.length - 2).join('.')
          : dataSources[0].path;
    }
    return 'Live Data (${dataSources.length} series)';
  }
}

/// Builder for real-time chart tools
class RealtimeChartBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'realtime_chart',
      name: 'Real-Time Chart',
      description: 'Live spline chart showing real-time data for up to 3 paths',
      category: ToolCategory.chart,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: true,
        minPaths: 1,
        maxPaths: 3,
        styleOptions: const [
          'primaryColor',
          'showLabel',
          'showValue', // Show current value in unit label (default: true)
          'maxDataPoints', // Number of data points to display (default: 50)
          'updateInterval', // Update interval in milliseconds (default: 500)
          'showLegend',
          'showGrid',
          'showZones', // Show zone bands from SignalK metadata (default: true)
          'showMovingAverage', // Show moving average line (default: false)
          'movingAverageWindow', // Moving average window size in data points (default: 5)
        ],
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return RealtimeChartTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
