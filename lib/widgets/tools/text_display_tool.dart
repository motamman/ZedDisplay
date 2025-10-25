import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/string_extensions.dart';
import '../../utils/color_extensions.dart';
import '../../utils/conversion_utils.dart';
import '../../config/ui_constants.dart';

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

    // Get label from data source or derive from path
    final label = dataSource.label ?? dataSource.path.toReadableLabel();

    // Use client-side conversions
    final rawValue = ConversionUtils.getRawValue(signalKService, dataSource.path);
    final convertedValue = ConversionUtils.getConvertedValue(signalKService, dataSource.path);

    // Format the display value
    String displayValue;
    String displayUnit = '';

    if (rawValue != null && convertedValue != null) {
      // Get formatted value with unit
      final formatted = ConversionUtils.formatValue(
        signalKService,
        dataSource.path,
        rawValue,
        decimalPlaces: 1,
      );
      displayValue = formatted;
      // Unit is already in formatted string, so leave displayUnit empty
    } else {
      // No data available
      displayValue = '--';

      // Get unit symbol from conversion info or style override
      final availableUnits = signalKService.getAvailableUnits(dataSource.path);
      final conversionInfo = availableUnits.isNotEmpty
          ? signalKService.getConversionInfo(dataSource.path, availableUnits.first)
          : null;
      displayUnit = config.style.unit ?? conversionInfo?.symbol ?? '';
    }

    // Parse color from hex string
    final textColor = config.style.primaryColor?.toColor(
      fallback: Theme.of(context).colorScheme.onSurface
    ) ?? Theme.of(context).colorScheme.onSurface;

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
                color: UIConstants.withSubtleOpacity(textColor),
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
                color: UIConstants.withSubtleOpacity(textColor),
              ),
            ),
        ],
      ),
    );
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
