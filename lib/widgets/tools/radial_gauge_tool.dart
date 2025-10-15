import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../radial_gauge.dart';

/// Config-driven radial gauge tool
class RadialGaugeTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const RadialGaugeTool({
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
    final value = signalKService.getConvertedValue(dataSource.path) ?? 0.0;

    // Get style configuration
    final style = config.style;
    final minValue = style.minValue ?? 0.0;
    final maxValue = style.maxValue ?? 100.0;

    // Get label from data source or style
    final label = dataSource.label ?? _getDefaultLabel(dataSource.path);

    // Get formatted value from plugin if available
    final formattedValue = dataPoint?.formatted;

    // Get unit (prefer style override, fallback to server's unit)
    // Only used if no formatted value
    final unit = style.unit ??
                 signalKService.getUnitSymbol(dataSource.path) ??
                 '';

    // Parse color from hex string
    Color primaryColor = Colors.blue;
    if (style.primaryColor != null) {
      try {
        final colorString = style.primaryColor!.replaceAll('#', '');
        primaryColor = Color(int.parse('FF$colorString', radix: 16));
      } catch (e) {
        // Keep default color if parsing fails
      }
    }

    return RadialGauge(
      value: value,
      minValue: minValue,
      maxValue: maxValue,
      label: style.showLabel == true ? label : '',
      unit: style.showUnit == true ? unit : '',
      formattedValue: formattedValue,
      primaryColor: primaryColor,
    );
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

/// Builder for radial gauge tools
class RadialGaugeBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'radial_gauge',
      name: 'Radial Gauge',
      description: 'Circular gauge with arc display for numeric values',
      category: ToolCategory.gauge,
      configSchema: ConfigSchema(
        allowsMinMax: true,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 1,
        maxPaths: 1,
        styleOptions: const [
          'minValue',
          'maxValue',
          'unit',
          'primaryColor',
          'showLabel',
          'showUnit',
        ],
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return RadialGaugeTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
