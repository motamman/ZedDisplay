import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';

/// Config-driven slider tool for sending numeric values to SignalK paths
class SliderTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const SliderTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<SliderTool> createState() => _SliderToolState();
}

class _SliderToolState extends State<SliderTool> {
  bool _isSending = false;
  double? _currentSliderValue;

  @override
  Widget build(BuildContext context) {
    // Get data from first data source
    if (widget.config.dataSources.isEmpty) {
      return const Center(child: Text('No data source configured'));
    }

    final dataSource = widget.config.dataSources.first;
    final dataPoint = widget.signalKService.getValue(dataSource.path, source: dataSource.source);
    final style = widget.config.style;

    // Get min/max values from style config
    final minValue = style.minValue ?? 0.0;
    final maxValue = style.maxValue ?? 100.0;

    // Get current value from SignalK or use slider value
    double currentValue;
    if (_currentSliderValue != null) {
      currentValue = _currentSliderValue!;
    } else {
      // Use converted value if available (from units-preference plugin)
      final convertedValue = widget.signalKService.getConvertedValue(dataSource.path);
      if (convertedValue != null) {
        currentValue = convertedValue;
      } else {
        currentValue = minValue;
      }
    }

    // Clamp value to range
    currentValue = currentValue.clamp(minValue, maxValue);

    // Get label from data source or style
    final label = dataSource.label ?? _getDefaultLabel(dataSource.path);

    // Parse color from hex string
    Color primaryColor = Theme.of(context).colorScheme.primary;
    if (style.primaryColor != null) {
      try {
        final colorString = style.primaryColor!.replaceAll('#', '');
        primaryColor = Color(int.parse('FF$colorString', radix: 16));
      } catch (e) {
        // Keep default color if parsing fails
      }
    }

    // Get unit
    final unit = style.unit ?? dataPoint?.symbol ?? '';

    // Get decimal places from customProperties
    final decimalPlaces = style.customProperties?['decimalPlaces'] as int? ?? 1;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (style.showLabel == true) ...[
              Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
            ],

            // Current value display
            if (style.showValue == true) ...[
              Text(
                '${currentValue.toStringAsFixed(decimalPlaces)}${style.showUnit == true ? " $unit" : ""}',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Min/Max labels
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${minValue.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  '${maxValue.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),

            // Syncfusion Slider - wrapped to prevent parent scroll interference
            GestureDetector(
              onHorizontalDragStart: (_) {}, // Block parent scroll
              onHorizontalDragUpdate: (_) {},
              onHorizontalDragEnd: (_) {},
              child: SfSliderTheme(
                data: SfSliderThemeData(
                  activeTrackHeight: 6,
                  inactiveTrackHeight: 6,
                  activeTrackColor: primaryColor,
                  inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
                  thumbColor: primaryColor,
                  thumbRadius: 12,
                  overlayColor: primaryColor.withValues(alpha: 0.2),
                  overlayRadius: 24,
                  tooltipBackgroundColor: primaryColor,
                ),
                child: SfSlider(
                  value: currentValue,
                  min: minValue,
                  max: maxValue,
                  stepSize: (maxValue - minValue) / ((maxValue - minValue) * (10 * (decimalPlaces + 1))).clamp(10, 1000),
                  enableTooltip: true,
                  numberFormat: NumberFormat.decimalPatternDigits(decimalDigits: decimalPlaces),
                  onChanged: _isSending ? null : (value) {
                    setState(() {
                      _currentSliderValue = value;
                    });
                  },
                  onChangeEnd: (value) => _sendValue(value, dataSource.path),
                ),
              ),
            ),

            const SizedBox(height: 4),

            // Path info
            Text(
              dataSource.path,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            // Sending indicator
            if (_isSending) ...[
              const SizedBox(height: 8),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _sendValue(double value, String path) async {
    setState(() {
      _isSending = true;
    });

    try {
      // Get decimal places and round the value before sending
      final decimalPlaces = widget.config.style.customProperties?['decimalPlaces'] as int? ?? 1;
      final multiplier = pow(10, decimalPlaces).toDouble();
      final roundedValue = (value * multiplier).round() / multiplier;

      await widget.signalKService.sendPutRequest(path, roundedValue);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_getDefaultLabel(path)} set to ${roundedValue.toStringAsFixed(decimalPlaces)}'),
            duration: const Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set value: $e'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _currentSliderValue = null; // Reset to sync with server value
        });
      }
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

/// Builder for slider tools
class SliderToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'slider',
      name: 'Slider',
      description: 'Slider control for sending numeric values to SignalK paths',
      category: ToolCategory.control,
      configSchema: ConfigSchema(
        allowsMinMax: true,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 1,
        maxPaths: 1,
        styleOptions: const [
          'minValue',
          'maxValue',
          'primaryColor',
          'showLabel',
          'showValue',
          'showUnit',
        ],
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return SliderTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
