import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
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

  /// Helper to get raw SI value from a data point
  double? _getRawValue(String path) {
    final dataPoint = signalKService.getValue(path);
    if (dataPoint?.original is num) {
      return (dataPoint!.original as num).toDouble();
    }
    if (dataPoint?.value is num) {
      return (dataPoint!.value as num).toDouble();
    }
    return null;
  }

  /// Helper to get converted display value using MetadataStore
  double? _getConverted(String path, double? rawValue) {
    if (rawValue == null) return null;
    final metadata = signalKService.metadataStore.get(path);
    return metadata?.convert(rawValue) ?? rawValue;
  }

  /// Helper to format value with symbol using MetadataStore
  String? _formatValue(String path, double? rawValue) {
    if (rawValue == null) return null;
    final metadata = signalKService.metadataStore.get(path);
    return metadata?.format(rawValue, decimals: 1) ?? rawValue.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    // Get data from data sources (up to 4)
    if (config.dataSources.isEmpty) {
      return const Center(child: Text('No data source configured'));
    }

    final dataSource = config.dataSources.first;

    // Use MetadataStore for conversions
    final rawValue = _getRawValue(dataSource.path);
    final heading = _getConverted(dataSource.path, rawValue) ?? 0.0;

    // Get label from data source or style
    final label = dataSource.label ?? dataSource.path.toReadableLabel();

    // Get formatted value using MetadataStore
    final formattedValue = _formatValue(dataSource.path, rawValue);

    // Parse color from hex string
    final primaryColor = config.style.primaryColor?.toColor(
      fallback: Colors.red
    ) ?? Colors.red;

    // Get tick labels and compass style from custom properties
    final showTickLabels = config.style.customProperties?['showTickLabels'] as bool? ?? false;
    final compassStyleStr = config.style.customProperties?['compassStyle'] as String? ?? 'classic';
    final compassStyle = _parseCompassStyle(compassStyleStr);

    // Get additional headings (2-4) for multi-needle display
    final additionalHeadings = <double>[];
    final additionalLabels = <String>[];
    final additionalColors = <Color>[
      Colors.blue,
      Colors.green,
      Colors.orange,
    ];

    for (int i = 1; i < config.dataSources.length && i < 4; i++) {
      final source = config.dataSources[i];
      final raw = _getRawValue(source.path);
      final value = _getConverted(source.path, raw);
      if (value != null) {
        additionalHeadings.add(value);
        additionalLabels.add(source.label ?? source.path.toReadableLabel());
      }
    }

    return CompassGauge(
      heading: heading,
      label: config.style.showLabel == true ? label : '',
      formattedValue: formattedValue,
      primaryColor: primaryColor,
      showTickLabels: showTickLabels,
      compassStyle: compassStyle,
      showValue: config.style.showValue ?? true,
      additionalHeadings: additionalHeadings.isNotEmpty ? additionalHeadings : null,
      additionalLabels: additionalLabels.isNotEmpty ? additionalLabels : null,
      additionalColors: additionalHeadings.isNotEmpty ? additionalColors : null,
    );
  }

  CompassStyle _parseCompassStyle(String styleStr) {
    switch (styleStr.toLowerCase()) {
      case 'arc':
        return CompassStyle.arc;
      case 'minimal':
        return CompassStyle.minimal;
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
      description: 'Circular compass display for heading/bearing values (supports up to 4 needles)',
      category: ToolCategory.navigation,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: true,
        minPaths: 1,
        maxPaths: 4,
        styleOptions: const [
          'primaryColor',
          'showLabel',
          'showValue',
          'compassStyle', // 'classic', 'arc', 'minimal', 'marine'
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
