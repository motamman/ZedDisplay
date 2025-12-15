import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/color_extensions.dart';
import '../polar_radar_chart.dart';

/// Config-driven polar radar chart tool
///
/// This tool visualizes data in polar coordinates:
/// - First path: angle/direction (e.g., wind direction, course)
/// - Second path: magnitude/velocity (e.g., wind speed, boat speed)
class PolarRadarChartTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const PolarRadarChartTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  Widget build(BuildContext context) {
    if (config.dataSources.length < 2) {
      return const Center(
        child: Text('Polar chart requires 2 paths:\n1. Angle/Direction\n2. Magnitude/Velocity'),
      );
    }

    // First path is angle, second is magnitude
    final anglePath = config.dataSources[0].path;
    final magnitudePath = config.dataSources[1].path;

    // Get custom labels from data sources
    final angleLabel = config.dataSources[0].label;
    final magnitudeLabel = config.dataSources[1].label;

    // Get configuration from custom properties
    final historySeconds = config.style.customProperties?['historySeconds'] as int? ?? 60;
    final updateIntervalMs = config.style.customProperties?['updateInterval'] as int? ?? 500;
    final showLabels = config.style.customProperties?['showLabels'] as bool? ?? true;
    final showGrid = config.style.customProperties?['showGrid'] as bool? ?? true;
    final maxMagnitude = (config.style.customProperties?['maxMagnitude'] as num?)?.toDouble() ?? 0.0;

    // Parse primary and fill colors
    final primaryColor = config.style.primaryColor?.toColor();

    final fillColor = (config.style.customProperties?['fillColor'] as String?)?.toColor();

    // Generate title
    final title = config.style.customProperties?['title'] as String? ??
                  _generateTitle(anglePath, magnitudePath);

    return PolarRadarChart(
      anglePath: anglePath,
      magnitudePath: magnitudePath,
      angleLabel: angleLabel,
      magnitudeLabel: magnitudeLabel,
      signalKService: signalKService,
      title: title,
      historyDuration: Duration(seconds: historySeconds),
      updateInterval: Duration(milliseconds: updateIntervalMs),
      primaryColor: primaryColor,
      fillColor: fillColor,
      showLabels: showLabels,
      showGrid: showGrid,
      maxMagnitude: maxMagnitude,
    );
  }

  String _generateTitle(String anglePath, String magnitudePath) {
    final angleParts = anglePath.split('.');
    final magParts = magnitudePath.split('.');

    final angleShort = angleParts.length > 2
        ? angleParts.sublist(angleParts.length - 2).join('.')
        : anglePath;
    final magShort = magParts.length > 2
        ? magParts.sublist(magParts.length - 2).join('.')
        : magnitudePath;

    return '$magShort vs $angleShort';
  }
}

/// Builder for polar radar chart tools
class PolarRadarChartBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'polar_radar_chart',
      name: 'Polar Radar Chart',
      description: 'Polar chart showing magnitude vs angle with area fill (e.g., wind speed/direction)',
      category: ToolCategory.navigation,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: true,
        minPaths: 2,
        maxPaths: 2,
        styleOptions: const [
          'primaryColor',      // Border color
          'fillColor',         // Area fill color
          'title',             // Chart title
          'showLabel',         // Show compass labels (N, NE, E, etc.)
          'showGrid',          // Show grid lines
          'historySeconds',    // Time window in seconds to keep data (default: 60)
          'updateInterval',    // Update interval in milliseconds (default: 500)
          'maxMagnitude',      // Max value for radial axis (0 = auto-scale)
        ],
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return PolarRadarChartTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
