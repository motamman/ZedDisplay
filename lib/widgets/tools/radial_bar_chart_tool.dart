import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../radial_bar_chart.dart';
import '../../utils/string_extensions.dart';
import '../../utils/color_extensions.dart';
import '../../utils/conversion_utils.dart';

/// Config-driven radial bar chart tool
/// Displays up to 4 SignalK paths as concentric circular rings
class RadialBarChartTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const RadialBarChartTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  Widget build(BuildContext context) {
    // Check connection
    if (!signalKService.isConnected) {
      return const Card(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 48, color: Colors.grey),
              SizedBox(height: 16),
              Text('Not connected to SignalK server'),
            ],
          ),
        ),
      );
    }

    // Check data sources
    if (config.dataSources.isEmpty) {
      return const Card(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.donut_large, size: 48, color: Colors.grey),
              SizedBox(height: 16),
              Text('No data sources configured'),
            ],
          ),
        ),
      );
    }

    // Build radial bar data from data sources using client-side conversions
    final radialBars = <RadialBarData>[];
    for (final dataSource in config.dataSources) {
      final value = ConversionUtils.getConvertedValue(signalKService, dataSource.path) ?? 0.0;
      final label = dataSource.label ?? dataSource.path.toReadableLabel();
      final unit = signalKService.getUnitSymbol(dataSource.path) ?? '';

      // Get max value from style config or custom properties for this specific path
      final maxValue = config.style.maxValue ??
                       config.style.customProperties?['maxValue_${dataSource.path}'] as double?;

      // Format value with appropriate decimal places
      final formattedValue = value.toStringAsFixed(1);

      radialBars.add(
        RadialBarData(
          label: label,
          value: value,
          maxValue: maxValue,
          unit: unit,
          formattedValue: formattedValue,
        ),
      );
    }

    // Parse primary color from config
    final primaryColor = config.style.primaryColor?.toColor();

    // Get configuration from custom properties
    final title = config.style.customProperties?['title'] as String? ?? '';
    final showLegend = config.style.customProperties?['showLegend'] as bool? ?? true;
    final showLabels = config.style.customProperties?['showLabels'] as bool? ?? true;
    final innerRadius = config.style.customProperties?['innerRadius'] as double? ?? 0.4;
    final gap = config.style.customProperties?['gap'] as double? ?? 0.08;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: RadialBarChart(
          data: radialBars,
          title: title.isNotEmpty ? title : null,
          showLegend: showLegend,
          showLabels: showLabels,
          primaryColor: primaryColor,
          innerRadius: innerRadius,
          gap: gap,
        ),
      ),
    );
  }
}

/// Builder for radial bar chart tools
class RadialBarChartBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'radial_bar_chart',
      name: 'Radial Bar Chart',
      description: 'Circular chart displaying up to 4 values as concentric rings',
      category: ToolCategory.chart,
      configSchema: ConfigSchema(
        allowsMinMax: true,
        allowsColorCustomization: true,
        allowsMultiplePaths: true,
        minPaths: 1,
        maxPaths: 4,
        styleOptions: const [
          'primaryColor',
          'title',
          'showLegend',
          'showLabels',
          'innerRadius', // 0.0 to 1.0, default 0.4
          'gap', // gap between rings, 0.0 to 0.2, default 0.08
        ],
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return RadialBarChartTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
