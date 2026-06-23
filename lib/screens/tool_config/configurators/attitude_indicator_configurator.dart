import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for the attitude (heel/pitch) indicator tool.
///
/// Manages display options only — the attitude data path is handled by the
/// standard data source picker. Title text + visibility follow the same
/// "Show Label" pattern as other tools (e.g. Tanks).
class AttitudeIndicatorConfigurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'attitude_indicator';

  @override
  Size get defaultSize => const Size(2, 2);

  // State - style options only, NOT the data path.
  bool showTitle = true;
  String title = 'Attitude';
  bool showDigitalValues = true;
  bool showGrid = true;
  double maxPitch = 30.0;
  double maxRoll = 45.0;

  @override
  void reset() {
    showTitle = true;
    title = 'Attitude';
    showDigitalValues = true;
    showGrid = true;
    maxPitch = 30.0;
    maxRoll = 45.0;
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    final props = tool.config.style.customProperties;
    if (props != null) {
      showTitle = props['showTitle'] as bool? ?? true;
      title = (props['title'] as String?)?.trim().isNotEmpty == true
          ? (props['title'] as String).trim()
          : 'Attitude';
      showDigitalValues = props['showDigitalValues'] as bool? ?? true;
      showGrid = props['showGrid'] as bool? ?? true;
      maxPitch = (props['maxPitch'] as num?)?.toDouble() ?? 30.0;
      maxRoll = (props['maxRoll'] as num?)?.toDouble() ?? 45.0;
    }
  }

  @override
  ToolConfig getConfig() {
    // Only return style config - dataSources come from the standard picker.
    return ToolConfig(
      dataSources: [],
      style: StyleConfig(
        customProperties: {
          'showTitle': showTitle,
          'title': title.trim().isEmpty ? 'Attitude' : title.trim(),
          'showDigitalValues': showDigitalValues,
          'showGrid': showGrid,
          'maxPitch': maxPitch,
          'maxRoll': maxRoll,
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
                'Display Options',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),

              // Title
              SwitchListTile(
                title: const Text('Show Title'),
                subtitle: const Text('Display a title above the indicator'),
                value: showTitle,
                onChanged: (value) {
                  setState(() => showTitle = value);
                },
              ),
              if (showTitle)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextFormField(
                    initialValue: title,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      hintText: 'e.g., Attitude',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      title = value;
                    },
                  ),
                ),
              const SizedBox(height: 8),

              SwitchListTile(
                title: const Text('Show Digital Values'),
                subtitle: const Text('Display numeric heel & pitch readouts'),
                value: showDigitalValues,
                onChanged: (value) {
                  setState(() => showDigitalValues = value);
                },
              ),

              SwitchListTile(
                title: const Text('Show Pitch Ladder'),
                subtitle: const Text('Display the horizon grid lines'),
                value: showGrid,
                onChanged: (value) {
                  setState(() => showGrid = value);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
