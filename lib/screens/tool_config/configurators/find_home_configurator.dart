import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for Find Home tool
class FindHomeConfigurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'find_home';

  @override
  Size get defaultSize => const Size(2, 3);

  int feedbackInterval = 10;
  String alertSound = 'whistle';

  static const Map<String, String> soundNames = {
    'bell': 'Bell',
    'foghorn': 'Foghorn',
    'chimes': 'Chimes',
    'ding': 'Ding',
    'whistle': 'Whistle',
    'dog': 'Dog Bark',
  };

  @override
  void reset() {
    feedbackInterval = 10;
    alertSound = 'whistle';
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    final props = tool.config.style.customProperties ?? {};
    feedbackInterval = (props['feedbackInterval'] as int?) ?? 10;
    alertSound = props['alertSound'] as String? ?? 'whistle';
  }

  @override
  ToolConfig getConfig() {
    return ToolConfig(
      dataSources: const [],
      style: StyleConfig(
        customProperties: {
          'feedbackInterval': feedbackInterval,
          'alertSound': alertSound,
        },
      ),
    );
  }

  @override
  String? validate() {
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
              // Alert Sound
              Text(
                'Alert Sound',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              DropdownMenu<String>(
                initialSelection: alertSound,
                expandedInsets: EdgeInsets.zero,
                dropdownMenuEntries: soundNames.entries.map((e) {
                  return DropdownMenuEntry(value: e.key, label: e.value);
                }).toList(),
                onSelected: (value) {
                  if (value != null) {
                    setState(() => alertSound = value);
                  }
                },
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // Feedback Interval
              Text(
                'Feedback Interval',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'How often vibration and sound alerts fire when off course',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: feedbackInterval.toDouble(),
                      min: 5,
                      max: 60,
                      divisions: 11,
                      label: '${feedbackInterval}s',
                      onChanged: (value) {
                        setState(() => feedbackInterval = value.round());
                      },
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${feedbackInterval}s',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
