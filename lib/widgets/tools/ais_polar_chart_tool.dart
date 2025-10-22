import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/color_extensions.dart';
import '../ais_polar_chart.dart';

/// Config-driven AIS polar chart tool
///
/// This tool visualizes nearby AIS vessels in polar coordinates:
/// - Own vessel at center (0,0)
/// - Other vessels plotted at relative bearing and distance
class AISPolarChartTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const AISPolarChartTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  Widget build(BuildContext context) {
    // Get configuration from custom properties
    final showLabels = config.style.customProperties?['showLabels'] as bool? ?? true;
    final showGrid = config.style.customProperties?['showGrid'] as bool? ?? true;

    // Get position path from data sources (default to navigation.position)
    final positionPath = config.dataSources.isNotEmpty
        ? config.dataSources[0].path
        : 'navigation.position';

    // Parse vessel color
    final vesselColor = config.style.primaryColor?.toColor();

    // Generate title
    final title = config.style.customProperties?['title'] as String? ?? 'AIS Vessels';

    return AISPolarChart(
      signalKService: signalKService,
      positionPath: positionPath,
      title: title,
      vesselColor: vesselColor,
      showLabels: showLabels,
      showGrid: showGrid,
    );
  }
}

/// Builder for AIS polar chart tools
class AISPolarChartBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'ais_polar_chart',
      name: 'AIS Polar Chart',
      description: 'Display nearby AIS vessels on polar chart relative to own position',
      category: ToolCategory.chart,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 1,
        maxPaths: 1,
        styleOptions: const [
          'primaryColor',      // Vessel color
          'title',             // Chart title
          'showLabel',         // Show compass labels (N, NE, E, etc.)
          'showGrid',          // Show grid lines
        ],
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return AISPolarChartTool(
      config: config,
      signalKService: signalKService,
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: [
        DataSource(path: 'navigation.position', label: 'Own Position'),
      ],
      style: StyleConfig(
        customProperties: {
          'showLabels': true,
          'showGrid': true,
          'title': 'AIS Vessels',
        },
      ),
    );
  }
}
