import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';

/// Config-driven text display for large numeric values
class TextDisplayTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const TextDisplayTool({
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
    final dataPoint = signalKService.getValue(dataSource.path, source: dataSource.source);

    // Get label from data source or derive from path
    final label = dataSource.label ?? _getDefaultLabel(dataSource.path);

    // Use formatted string from plugin if available, otherwise format manually
    String displayValue;
    String displayUnit;

    if (dataPoint?.formatted != null) {
      // Plugin provides pre-formatted value like "12.6 kn"
      displayValue = dataPoint!.formatted!;
      displayUnit = ''; // Unit is already in formatted string
    } else {
      // Fallback: format manually
      final numValue = dataPoint?.converted ?? (dataPoint?.value is num ? (dataPoint!.value as num).toDouble() : 0.0);
      displayValue = numValue.toStringAsFixed(1);
      displayUnit = config.style.unit ??
                    signalKService.getUnitSymbol(dataSource.path) ??
                    '';
    }

    // Parse color from hex string
    Color textColor = Theme.of(context).colorScheme.onSurface;
    if (config.style.primaryColor != null) {
      try {
        final colorString = config.style.primaryColor!.replaceAll('#', '');
        textColor = Color(int.parse('FF$colorString', radix: 16));
      } catch (e) {
        // Keep default color if parsing fails
      }
    }

    // Get font size from config or use default
    final fontSize = config.style.fontSize ?? 48.0;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (config.style.showLabel == true && label.isNotEmpty)
            Text(
              label,
              style: TextStyle(
                fontSize: fontSize * 0.35,
                fontWeight: FontWeight.w300,
                color: textColor.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          if (config.style.showLabel == true && label.isNotEmpty)
            SizedBox(height: fontSize * 0.15),
          if (config.style.showValue == true)
            Text(
              displayValue,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          if (config.style.showUnit == true && displayUnit.isNotEmpty)
            SizedBox(height: fontSize * 0.1),
          if (config.style.showUnit == true && displayUnit.isNotEmpty)
            Text(
              displayUnit,
              style: TextStyle(
                fontSize: fontSize * 0.35,
                fontWeight: FontWeight.w300,
                color: textColor.withValues(alpha: 0.7),
              ),
            ),
        ],
      ),
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

/// Builder for text display tools
class TextDisplayBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'text_display',
      name: 'Text Display',
      description: 'Large numeric value display with label and unit',
      category: ToolCategory.display,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 1,
        maxPaths: 1,
        styleOptions: const [
          'unit',
          'primaryColor',
          'fontSize',
          'showLabel',
          'showValue',
          'showUnit',
        ],
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return TextDisplayTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
