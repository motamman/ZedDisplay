import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for control tools: slider, knob, dropdown, switch, button
class ControlConfigurator extends ToolConfigurator {
  final String _toolTypeId;

  ControlConfigurator(this._toolTypeId);

  @override
  String get toolTypeId => _toolTypeId;

  @override
  Size get defaultSize => const Size(2, 2);

  // Control-specific state variables
  int decimalPlaces = 1;
  double stepSize = 10.0;

  @override
  void reset() {
    decimalPlaces = 1;
    stepSize = 10.0;
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    final style = tool.config.style;
    if (style.customProperties != null) {
      decimalPlaces = style.customProperties!['decimalPlaces'] as int? ?? 1;
      stepSize = (style.customProperties!['stepSize'] as num?)?.toDouble() ?? 10.0;
    }
  }

  @override
  ToolConfig getConfig() {
    // Only include relevant properties based on tool type
    final Map<String, dynamic> customProps = {};

    if (_toolTypeId == 'slider' || _toolTypeId == 'knob') {
      customProps['decimalPlaces'] = decimalPlaces;
    } else if (_toolTypeId == 'dropdown') {
      customProps['decimalPlaces'] = decimalPlaces;
      customProps['stepSize'] = stepSize;
    }
    // switch and button have no custom properties

    return ToolConfig(
      dataSources: const [],
      style: StyleConfig(
        customProperties: customProps,
      ),
    );
  }

  @override
  String? validate() {
    if ((_toolTypeId == 'slider' || _toolTypeId == 'knob' || _toolTypeId == 'dropdown') &&
        decimalPlaces < 0) {
      return 'Decimal places cannot be negative';
    }
    if (_toolTypeId == 'dropdown' && stepSize <= 0) {
      return 'Step size must be greater than 0';
    }
    return null;
  }

  @override
  Widget buildConfigUI(BuildContext context, SignalKService signalKService) {
    return StatefulBuilder(
      builder: (context, setState) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_getToolTypeName()} Configuration',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),

              // Slider, Knob, and Dropdown decimal places
              if (_toolTypeId == 'slider' ||
                  _toolTypeId == 'knob' ||
                  _toolTypeId == 'dropdown') ...[
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Decimal Places',
                    border: OutlineInputBorder(),
                    helperText: 'Number of decimal places to display',
                  ),
                  initialValue: decimalPlaces,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('0 (e.g., 42)')),
                    DropdownMenuItem(value: 1, child: Text('1 (e.g., 42.5)')),
                    DropdownMenuItem(value: 2, child: Text('2 (e.g., 42.50)')),
                    DropdownMenuItem(value: 3, child: Text('3 (e.g., 42.500)')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => decimalPlaces = value);
                    }
                  },
                ),
              ],

              // Dropdown step size
              if (_toolTypeId == 'dropdown') ...[
                const SizedBox(height: 16),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Step Size',
                    border: OutlineInputBorder(),
                    helperText: 'Increment between dropdown values',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  controller: TextEditingController(text: stepSize.toString()),
                  onChanged: (value) {
                    final parsed = double.tryParse(value);
                    if (parsed != null && parsed > 0) {
                      setState(() => stepSize = parsed);
                    }
                  },
                ),
              ],

              // Switch and Button have no custom configuration
              if (_toolTypeId == 'switch' || _toolTypeId == 'button') ...[
                Text(
                  'This tool uses common configuration only. Set data sources, colors, and other options in the main configuration section.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _getToolTypeName() {
    switch (_toolTypeId) {
      case 'slider':
        return 'Slider';
      case 'knob':
        return 'Knob';
      case 'dropdown':
        return 'Dropdown';
      case 'switch':
        return 'Switch';
      case 'button':
        return 'Button';
      default:
        return 'Control';
    }
  }
}
