import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for radial and linear gauge tools
class GaugeConfigurator extends ToolConfigurator {
  final String _toolTypeId;

  GaugeConfigurator(this._toolTypeId);

  @override
  String get toolTypeId => _toolTypeId;

  @override
  Size get defaultSize => const Size(2, 2);

  // Gauge-specific state variables (6 total)
  bool showTickLabels = false;
  bool pointerOnly = false;
  int divisions = 10;
  String orientation = 'horizontal';
  String gaugeStyle = 'arc'; // For radial: arc, full, half, threequarter
  String linearGaugeStyle = 'bar'; // For linear: bar, thermometer, step, bullet

  @override
  void reset() {
    showTickLabels = false;
    pointerOnly = false;
    divisions = 10;
    orientation = 'horizontal';
    gaugeStyle = 'arc';
    linearGaugeStyle = 'bar';
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    final style = tool.config.style;
    if (style.customProperties != null) {
      showTickLabels = style.customProperties!['showTickLabels'] as bool? ?? false;
      pointerOnly = style.customProperties!['pointerOnly'] as bool? ?? false;
      divisions = style.customProperties!['divisions'] as int? ?? 10;
      orientation = style.customProperties!['orientation'] as String? ?? 'horizontal';
      gaugeStyle = style.customProperties!['gaugeStyle'] as String? ?? 'arc';
      linearGaugeStyle = style.customProperties!['gaugeStyle'] as String? ?? 'bar';
    }
  }

  @override
  ToolConfig getConfig() {
    return ToolConfig(
      dataSources: const [],
      style: StyleConfig(
        customProperties: {
          'showTickLabels': showTickLabels,
          'pointerOnly': pointerOnly,
          'divisions': divisions,
          'orientation': orientation,
          'gaugeStyle': _toolTypeId == 'radial_gauge' ? gaugeStyle : linearGaugeStyle,
        },
      ),
    );
  }

  @override
  String? validate() {
    if (divisions < 2) {
      return 'Divisions must be at least 2';
    }
    if (divisions > 50) {
      return 'Divisions cannot exceed 50';
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
                '${_toolTypeId == 'radial_gauge' ? 'Radial' : 'Linear'} Gauge Configuration',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),

              // Gauge Style
              if (_toolTypeId == 'radial_gauge')
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Gauge Style',
                    border: OutlineInputBorder(),
                    helperText: 'Shape of the radial gauge',
                  ),
                  initialValue: gaugeStyle,
                  items: const [
                    DropdownMenuItem(value: 'arc', child: Text('Arc (180°)')),
                    DropdownMenuItem(value: 'half', child: Text('Half Circle (180°)')),
                    DropdownMenuItem(value: 'threequarter', child: Text('Three Quarter (270°)')),
                    DropdownMenuItem(value: 'full', child: Text('Full Circle (360°)')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => gaugeStyle = value);
                    }
                  },
                ),

              // Linear Gauge Style
              if (_toolTypeId == 'linear_gauge') ...[
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Gauge Style',
                    border: OutlineInputBorder(),
                    helperText: 'Visual style of the linear gauge',
                  ),
                  initialValue: linearGaugeStyle,
                  items: const [
                    DropdownMenuItem(value: 'bar', child: Text('Bar (horizontal/vertical)')),
                    DropdownMenuItem(value: 'thermometer', child: Text('Thermometer')),
                    DropdownMenuItem(value: 'step', child: Text('Step/Ladder')),
                    DropdownMenuItem(value: 'bullet', child: Text('Bullet Chart')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => linearGaugeStyle = value);
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Orientation (linear only)
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Orientation',
                    border: OutlineInputBorder(),
                  ),
                  initialValue: orientation,
                  items: const [
                    DropdownMenuItem(value: 'horizontal', child: Text('Horizontal')),
                    DropdownMenuItem(value: 'vertical', child: Text('Vertical')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => orientation = value);
                    }
                  },
                ),
              ],
              const SizedBox(height: 16),

              // Divisions
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Divisions (tick marks)',
                  border: OutlineInputBorder(),
                  helperText: 'Number of major divisions on the gauge',
                ),
                keyboardType: TextInputType.number,
                initialValue: divisions.toString(),
                onChanged: (value) {
                  final parsed = int.tryParse(value);
                  if (parsed != null && parsed > 0) {
                    setState(() => divisions = parsed);
                  }
                },
              ),
              const SizedBox(height: 8),

              // Show Tick Labels
              SwitchListTile(
                title: const Text('Show Tick Labels'),
                subtitle: const Text('Display numbers at tick marks'),
                value: showTickLabels,
                onChanged: (value) {
                  setState(() => showTickLabels = value);
                },
              ),

              // Pointer Only
              SwitchListTile(
                title: const Text('Pointer Only Mode'),
                subtitle: Text(_toolTypeId == 'radial_gauge'
                    ? 'Show needle pointer without filled arc'
                    : 'Show triangle pointer without filled bar'),
                value: pointerOnly,
                onChanged: (value) {
                  setState(() => pointerOnly = value);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
