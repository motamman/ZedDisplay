import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/string_extensions.dart';
import '../../utils/color_extensions.dart';

/// Config-driven dropdown tool for sending numeric values to SignalK paths
class DropdownTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const DropdownTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<DropdownTool> createState() => _DropdownToolState();
}

class _DropdownToolState extends State<DropdownTool> {
  bool _isSending = false;
  double? _currentSelectedValue;

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

    // Get decimal places from customProperties
    final decimalPlaces = style.customProperties?['decimalPlaces'] as int? ?? 1;

    // Get step size from customProperties (default to 10 steps)
    final stepSize = style.customProperties?['stepSize'] as double? ?? ((maxValue - minValue) / 10);

    // Get current value from SignalK or use selected value
    double currentValue;
    if (_currentSelectedValue != null) {
      currentValue = _currentSelectedValue!;
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

    // Generate dropdown options based on min, max, and step
    final List<double> dropdownValues = [];
    for (double value = minValue; value <= maxValue; value += stepSize) {
      dropdownValues.add(value);
    }
    // Ensure maxValue is included if not already
    if (dropdownValues.last < maxValue) {
      dropdownValues.add(maxValue);
    }

    // Find the closest dropdown value to current value
    double closestValue = dropdownValues.reduce((a, b) =>
      (a - currentValue).abs() < (b - currentValue).abs() ? a : b
    );

    // Get label from data source or style
    final label = dataSource.label ?? dataSource.path.toReadableLabel();

    // Parse color from hex string
    final primaryColor = style.primaryColor?.toColor(
      fallback: Theme.of(context).colorScheme.primary
    ) ?? Theme.of(context).colorScheme.primary;

    // Get unit
    final unit = style.unit ?? dataPoint?.symbol ?? '';

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
                '${closestValue.toStringAsFixed(decimalPlaces)}${style.showUnit == true ? " $unit" : ""}',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Dropdown button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: primaryColor, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<double>(
                value: closestValue,
                isExpanded: true,
                underline: const SizedBox(),
                icon: Icon(Icons.arrow_drop_down, color: primaryColor),
                dropdownColor: Theme.of(context).cardColor,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
                items: dropdownValues.map((double value) {
                  return DropdownMenuItem<double>(
                    value: value,
                    child: Center(
                      child: Text(
                        '${value.toStringAsFixed(decimalPlaces)}${unit.isNotEmpty ? " $unit" : ""}',
                      ),
                    ),
                  );
                }).toList(),
                onChanged: _isSending ? null : (value) {
                  if (value != null) {
                    setState(() {
                      _currentSelectedValue = value;
                    });
                    _sendValue(value, dataSource.path);
                  }
                },
              ),
            ),

            const SizedBox(height: 8),

            // Min/Max labels
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Min: ${minValue.toStringAsFixed(decimalPlaces)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  'Max: ${maxValue.toStringAsFixed(decimalPlaces)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
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
            content: Text('${path.toReadableLabel()} set to ${roundedValue.toStringAsFixed(decimalPlaces)}'),
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
          _currentSelectedValue = null; // Reset to sync with server value
        });
      }
    }
  }
}

/// Builder for dropdown tools
class DropdownToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'dropdown',
      name: 'Dropdown',
      description: 'Dropdown selector for sending numeric values to SignalK paths',
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
          'unit',
        ],
      ),
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: [
        DataSource(
          path: 'electrical.batteries.house.capacity.stateOfCharge',
          label: 'Battery SOC',
        ),
      ],
      style: StyleConfig(
        minValue: 0,
        maxValue: 100,
        unit: '%',
        primaryColor: '#2196F3',
        showLabel: true,
        showValue: true,
        showUnit: true,
        customProperties: {
          'decimalPlaces': 0,
          'stepSize': 10.0,
        },
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return DropdownTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
