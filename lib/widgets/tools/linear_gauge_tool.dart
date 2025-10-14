import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';

enum LinearGaugeOrientation { horizontal, vertical }

/// Config-driven linear (bar) gauge
class LinearGaugeTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const LinearGaugeTool({
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
    final value = signalKService.getConvertedValue(dataSource.path) ?? 0.0;

    // Get style configuration
    final style = config.style;
    final minValue = style.minValue ?? 0.0;
    final maxValue = style.maxValue ?? 100.0;

    // Get label from data source or derive from path
    final label = dataSource.label ?? _getDefaultLabel(dataSource.path);

    // Get unit (prefer style override, fallback to server's unit)
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

    // Get orientation from custom properties
    final orientation = style.customProperties?['orientation'] == 'vertical'
        ? LinearGaugeOrientation.vertical
        : LinearGaugeOrientation.horizontal;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: orientation == LinearGaugeOrientation.horizontal
          ? _buildHorizontalGauge(
              context,
              value,
              minValue,
              maxValue,
              label,
              unit,
              primaryColor,
              style,
            )
          : _buildVerticalGauge(
              context,
              value,
              minValue,
              maxValue,
              label,
              unit,
              primaryColor,
              style,
            ),
    );
  }

  Widget _buildHorizontalGauge(
    BuildContext context,
    double value,
    double minValue,
    double maxValue,
    String label,
    String unit,
    Color primaryColor,
    StyleConfig style,
  ) {
    final normalizedValue = ((value - minValue) / (maxValue - minValue)).clamp(0.0, 1.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (style.showLabel == true && label.isNotEmpty)
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        if (style.showLabel == true && label.isNotEmpty) const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    children: [
                      FractionallySizedBox(
                        widthFactor: normalizedValue,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                primaryColor,
                                primaryColor.withValues(alpha: 0.7),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (style.showValue == true)
              SizedBox(
                width: 80,
                child: Text(
                  '${value.toStringAsFixed(1)} ${style.showUnit == true ? unit : ''}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              minValue.toStringAsFixed(0),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            Text(
              maxValue.toStringAsFixed(0),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVerticalGauge(
    BuildContext context,
    double value,
    double minValue,
    double maxValue,
    String label,
    String unit,
    Color primaryColor,
    StyleConfig style,
  ) {
    final normalizedValue = ((value - minValue) / (maxValue - minValue)).clamp(0.0, 1.0);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (style.showLabel == true && label.isNotEmpty)
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (style.showLabel == true && label.isNotEmpty) const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FractionallySizedBox(
                        heightFactor: normalizedValue,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                primaryColor,
                                primaryColor.withValues(alpha: 0.7),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (style.showValue == true)
              Text(
                '${value.toStringAsFixed(1)} ${style.showUnit == true ? unit : ''}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ],
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

/// Builder for linear gauge tools
class LinearGaugeBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'linear_gauge',
      name: 'Linear Gauge',
      description: 'Horizontal or vertical bar gauge for numeric values',
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
          'showValue',
          'showUnit',
          'orientation', // 'horizontal' or 'vertical'
        ],
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return LinearGaugeTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
