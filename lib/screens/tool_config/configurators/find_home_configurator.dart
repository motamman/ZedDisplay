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
  String trackCogPath = 'navigation.courseOverGroundTrue';
  String trackSogPath = 'navigation.speedOverGround';

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
    trackCogPath = 'navigation.courseOverGroundTrue';
    trackSogPath = 'navigation.speedOverGround';
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
    trackCogPath = props['trackCogPath'] as String? ?? 'navigation.courseOverGroundTrue';
    trackSogPath = props['trackSogPath'] as String? ?? 'navigation.speedOverGround';
  }

  @override
  ToolConfig getConfig() {
    return ToolConfig(
      dataSources: const [],
      style: StyleConfig(
        customProperties: {
          'feedbackInterval': feedbackInterval,
          'alertSound': alertSound,
          'trackCogPath': trackCogPath,
          'trackSogPath': trackSogPath,
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

              // Track Mode Paths
              Text(
                'Track Mode Paths',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'SignalK paths used for vessel position when Track mode is on',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: trackCogPath,
                decoration: const InputDecoration(
                  labelText: 'COG Path',
                  hintText: 'navigation.courseOverGroundTrue',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                onChanged: (value) {
                  trackCogPath = value.trim().isEmpty
                      ? 'navigation.courseOverGroundTrue'
                      : value.trim();
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: trackSogPath,
                decoration: const InputDecoration(
                  labelText: 'SOG Path',
                  hintText: 'navigation.speedOverGround',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                onChanged: (value) {
                  trackSogPath = value.trim().isEmpty
                      ? 'navigation.speedOverGround'
                      : value.trim();
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
