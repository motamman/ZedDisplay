import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/conversion_utils.dart';
import '../compass_gauge.dart';
import '../../utils/string_extensions.dart';
import '../../utils/color_extensions.dart';

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

    // Use client-side conversions
    final rawValue = ConversionUtils.getRawValue(signalKService, dataSource.path);
    final heading = ConversionUtils.getConvertedValue(signalKService, dataSource.path) ?? 0.0;

    // Get label from data source or style
    final label = dataSource.label ?? dataSource.path.toReadableLabel();

    // Get formatted value using client-side conversion
    String? formattedValue;
    if (rawValue != null) {
      formattedValue = ConversionUtils.formatValue(
        signalKService,
        dataSource.path,
        rawValue,
        decimalPlaces: 1,
      );
    }

    // Parse color from hex string
    final primaryColor = config.style.primaryColor?.toColor(
      fallback: Colors.red
    ) ?? Colors.red;

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
      showValue: config.style.showValue ?? true,
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
      case 'marine':
        return CompassStyle.marine;
      default:
        return CompassStyle.classic;
    }
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
      category: ToolCategory.gauge,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 1,
        maxPaths: 1,
        styleOptions: const [
          'primaryColor',
          'showLabel',
          'showValue',
          'compassStyle', // 'classic', 'arc', 'minimal', 'rose', 'marine'
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
