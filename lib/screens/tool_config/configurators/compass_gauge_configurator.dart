import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for the compass gauge tool
class CompassGaugeConfigurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'compass';

  @override
  Size get defaultSize => const Size(4, 4);

  String compassStyle = 'classic';
  bool showTickLabels = false;

  @override
  void reset() {
    compassStyle = 'classic';
    showTickLabels = false;
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    final style = tool.config.style;
    if (style.customProperties != null) {
      compassStyle = style.customProperties!['compassStyle'] as String? ?? 'classic';
      showTickLabels = style.customProperties!['showTickLabels'] as bool? ?? false;
    }
  }

  @override
  ToolConfig getConfig() {
    return ToolConfig(
      dataSources: const [],
      style: StyleConfig(
        customProperties: {
          'compassStyle': compassStyle,
          'showTickLabels': showTickLabels,
        },
      ),
    );
  }

  @override
  String? validate() => null;

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
                'Compass Gauge Configuration',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),

              // Compass Style
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Compass Style',
                  border: OutlineInputBorder(),
                  helperText: 'Visual style of the compass',
                ),
                initialValue: compassStyle,
                items: const [
                  DropdownMenuItem(value: 'classic', child: Text('Classic')),
                  DropdownMenuItem(value: 'arc', child: Text('Arc')),
                  DropdownMenuItem(value: 'minimal', child: Text('Minimal')),
                  DropdownMenuItem(value: 'marine', child: Text('Marine')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => compassStyle = value);
                  }
                },
              ),
              const SizedBox(height: 16),

              // Show Tick Labels
              SwitchListTile(
                title: const Text('Show Tick Labels'),
                subtitle: const Text('Display degree numbers around the compass'),
                value: showTickLabels,
                onChanged: (value) {
                  setState(() => showTickLabels = value);
                },
              ),

            ],
          ),
        );
      },
    );
  }
}
