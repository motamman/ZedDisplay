import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../compass_gauge.dart';

/// Config-driven compass gauge tool
class CompassGaugeTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const CompassGaugeTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  Widget build(BuildContext context) {
    // Get data from first data source
    if (config.dataSources.isEmpty) {
      return const Center(child: Text('No data source configured'));
    }

    final dataSource = config.dataSources.first;
    final dataPoint = signalKService.getValue(dataSource.path);
    final heading = signalKService.getConvertedValue(dataSource.path) ?? 0.0;

    // Get label from data source or style
    final label = dataSource.label ?? _getDefaultLabel(dataSource.path);

    // Get formatted value from plugin if available
    final formattedValue = dataPoint?.formatted;

    // Parse color from hex string
    Color primaryColor = Colors.red;
    if (config.style.primaryColor != null) {
      try {
        final colorString = config.style.primaryColor!.replaceAll('#', '');
        primaryColor = Color(int.parse('FF$colorString', radix: 16));
      } catch (e) {
        // Keep default color if parsing fails
      }
    }

    // Get tick labels and compass style from custom properties
    final showTickLabels = config.style.customProperties?['showTickLabels'] as bool? ?? false;
    final compassStyleStr = config.style.customProperties?['compassStyle'] as String? ?? 'classic';
    final compassStyle = _parseCompassStyle(compassStyleStr);

    return CompassGauge(
      heading: heading,
      label: config.style.showLabel == true ? label : '',
      formattedValue: formattedValue,
      primaryColor: primaryColor,
      showTickLabels: showTickLabels,
      compassStyle: compassStyle,
    );
  }

  CompassStyle _parseCompassStyle(String styleStr) {
    switch (styleStr.toLowerCase()) {
      case 'arc':
        return CompassStyle.arc;
      case 'minimal':
        return CompassStyle.minimal;
      case 'rose':
        return CompassStyle.rose;
      default:
        return CompassStyle.classic;
    }
  }

  /// Extract a readable label from the path
  String _getDefaultLabel(String path) {
    final parts = path.split('.');
    if (parts.isEmpty) return path;

    // Get the last part and make it readable
    final lastPart = parts.last;

    // Convert camelCase to Title Case
    final result = lastPart.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)}',
    ).trim();

    return result.isEmpty ? lastPart : result;
  }
}

/// Builder for compass gauge tools
class CompassGaugeBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'compass',
      name: 'Compass Gauge',
      description: 'Circular compass display for heading/bearing values',
      category: ToolCategory.compass,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 1,
        maxPaths: 1,
        styleOptions: const [
          'primaryColor',
          'showLabel',
          'compassStyle', // 'classic', 'arc', 'minimal', 'rose'
        ],
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return CompassGaugeTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
