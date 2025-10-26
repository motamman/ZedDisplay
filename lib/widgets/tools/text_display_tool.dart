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

    // Parse color from hex string
    final textColor = config.style.primaryColor?.toColor(
      fallback: Theme.of(context).colorScheme.onSurface
    ) ?? Theme.of(context).colorScheme.onSurface;

    // Get font size from config or use default
    final fontSize = config.style.fontSize ?? 48.0;

    // Get the data point to check if it's an object
    final dataPoint = signalKService.getValue(dataSource.path);

    // Check if the value is an object (Map)
    if (dataPoint?.value is Map) {
      return _buildObjectDisplay(context, dataPoint!.value as Map, label, textColor, fontSize);
    }

    // Use client-side conversions for scalar values
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

  Widget _buildObjectDisplay(BuildContext context, Map objectValue, String label, Color textColor, double fontSize) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (config.style.showLabel == true && label.isNotEmpty)
            Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: fontSize * 0.35,
                  fontWeight: FontWeight.w300,
                  color: UIConstants.withSubtleOpacity(textColor),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          if (config.style.showLabel == true && label.isNotEmpty)
            SizedBox(height: fontSize * 0.15),
          // Display each property as label: value
          ...objectValue.entries.map((entry) {
            final propertyKey = entry.key.toString();
            final propertyLabel = propertyKey.toReadableLabel();
            final propertyValue = _formatPropertyValue(propertyKey, entry.value);

            return Padding(
              padding: EdgeInsets.symmetric(vertical: fontSize * 0.05),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$propertyLabel: ',
                    style: TextStyle(
                      fontSize: fontSize * 0.4,
                      fontWeight: FontWeight.w500,
                      color: UIConstants.withSubtleOpacity(textColor),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      propertyValue,
                      style: TextStyle(
                        fontSize: fontSize * 0.5,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _formatPropertyValue(String propertyKey, dynamic value) {
    if (value == null) return '--';

    // Check if this is latitude or longitude
    final keyLower = propertyKey.toLowerCase();
    if (value is num) {
      if (keyLower.contains('lat')) {
        return _formatLatitude(value.toDouble());
      } else if (keyLower.contains('lon')) {
        return _formatLongitude(value.toDouble());
      }
      // Use toString() to avoid rounding - shows natural precision
      return value.toString();
    }

    if (value is String) return value;
    if (value is bool) return value ? 'Yes' : 'No';
    return value.toString();
  }

  String _formatLatitude(double degrees) {
    final hemisphere = degrees >= 0 ? 'N' : 'S';
    final absDegrees = degrees.abs();
    final deg = absDegrees.floor();
    final minDecimal = (absDegrees - deg) * 60;
    final min = minDecimal.floor();
    final sec = (minDecimal - min) * 60;

    return '$deg° ${min.toString().padLeft(2, '0')}\' ${sec.toStringAsFixed(2).padLeft(5, '0')}" $hemisphere';
  }

  String _formatLongitude(double degrees) {
    final hemisphere = degrees >= 0 ? 'E' : 'W';
    final absDegrees = degrees.abs();
    final deg = absDegrees.floor();
    final minDecimal = (absDegrees - deg) * 60;
    final min = minDecimal.floor();
    final sec = (minDecimal - min) * 60;

    return '$deg° ${min.toString().padLeft(2, '0')}\' ${sec.toStringAsFixed(2).padLeft(5, '0')}" $hemisphere';
  }

}

/// Builder for text display tools
class TextDisplayBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'text_display',
      name: 'Text Display',
      description: 'Large value display with label and unit. Automatically stacks object properties as label: value pairs.',
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
