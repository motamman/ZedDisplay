import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../realtime_spline_chart.dart';

/// Config-driven real-time chart tool
class RealtimeChartTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const RealtimeChartTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  Widget build(BuildContext context) {
    if (config.dataSources.isEmpty) {
      return const Center(child: Text('No data sources configured'));
    }

    // Extract paths from data sources
    final paths = config.dataSources.map((ds) => ds.path).toList();

    // Get configuration from custom properties
    final maxDataPoints = config.style.customProperties?['maxDataPoints'] as int? ?? 50;
    final updateIntervalMs = config.style.customProperties?['updateInterval'] as int? ?? 500;
    final showLegend = config.style.customProperties?['showLegend'] as bool? ?? true;
    final showGrid = config.style.customProperties?['showGrid'] as bool? ?? true;

    // Parse primary color
    Color? primaryColor;
    if (config.style.primaryColor != null) {
      try {
        final colorString = config.style.primaryColor!.replaceAll('#', '');
        primaryColor = Color(int.parse('FF$colorString', radix: 16));
      } catch (e) {
        // Keep null if parsing fails
      }
    }

    // Generate title from paths
    final title = config.style.customProperties?['title'] as String? ??
                  _generateTitle(paths);

    return RealtimeSplineChart(
      paths: paths,
      signalKService: signalKService,
      title: title,
      maxDataPoints: maxDataPoints,
      updateInterval: Duration(milliseconds: updateIntervalMs),
      showLegend: showLegend,
      showGrid: showGrid,
      primaryColor: primaryColor,
    );
  }

  String _generateTitle(List<String> paths) {
    if (paths.length == 1) {
      final parts = paths[0].split('.');
      return parts.length > 2
          ? parts.sublist(parts.length - 2).join('.')
          : paths[0];
    }
    return 'Live Data (${paths.length} series)';
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
          'maxDataPoints', // Number of data points to display (default: 50)
          'updateInterval', // Update interval in milliseconds (default: 500)
          'showLegend',
          'showGrid',
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
