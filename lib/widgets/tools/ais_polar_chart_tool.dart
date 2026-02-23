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
/// - CPA/TCPA calculations using own vessel COG and SOG
class AISPolarChartTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const AISPolarChartTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  // Default paths for AIS chart
  static const _defaultPaths = [
    'navigation.position',              // 0: own position
    'navigation.courseOverGroundTrue',  // 1: own COG for CPA calculation
    'navigation.speedOverGround',       // 2: own SOG for CPA calculation
  ];

  /// Get path at index, using default if not configured
  String _getPath(int index) {
    if (config.dataSources.length > index && config.dataSources[index].path.isNotEmpty) {
      return config.dataSources[index].path;
    }
    return _defaultPaths[index];
  }

  @override
  Widget build(BuildContext context) {
    // Get configuration from custom properties
    final showLabels = config.style.customProperties?['showLabels'] as bool? ?? true;
    final showGrid = config.style.customProperties?['showGrid'] as bool? ?? true;
    final pruneMinutes = config.style.customProperties?['pruneMinutes'] as int? ?? 15;

    // Get paths from data sources (with defaults)
    final positionPath = _getPath(0);
    final cogPath = _getPath(1);
    final sogPath = _getPath(2);

    // Parse vessel color
    final vesselColor = config.style.primaryColor?.toColor();

    // Generate title
    final title = config.style.customProperties?['title'] as String? ?? 'AIS Vessels';

    return AISPolarChart(
      key: ValueKey('ais_chart_$positionPath'),
      signalKService: signalKService,
      positionPath: positionPath,
      cogPath: cogPath,
      sogPath: sogPath,
      title: title,
      vesselColor: vesselColor,
      showLabels: showLabels,
      showGrid: showGrid,
      pruneMinutes: pruneMinutes,
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
      description: 'Display nearby AIS vessels on polar chart with CPA/TCPA calculations',
      category: ToolCategory.ais,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: true,
        minPaths: 1,
        maxPaths: 3,
        styleOptions: const [
          'primaryColor',      // Vessel color
          'title',             // Chart title
          'showLabel',         // Show compass labels (N, NE, E, etc.)
          'showGrid',          // Show grid lines
          'pruneMinutes',      // Minutes before vessel is removed from display
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
        DataSource(path: 'navigation.courseOverGroundTrue', label: 'Own COG'),
        DataSource(path: 'navigation.speedOverGround', label: 'Own SOG'),
      ],
      style: StyleConfig(
        customProperties: {
          'showLabels': true,
          'showGrid': true,
          'title': 'AIS Vessels',
          'pruneMinutes': 15,
        },
      ),
    );
  }
}
