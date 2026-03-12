import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for Sun/Moon Arc tool
class SunMoonArcConfigurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'sun_moon_arc';

  @override
  Size get defaultSize => const Size(4, 2);

  // Configuration state
  String arcStyle = 'half';
  bool use24HourFormat = false;
  bool showInteriorTime = false;
  bool showMoonMarkers = true;
  bool showSecondaryIcons = true;

  static const Map<String, String> arcStyleNames = {
    'half': 'Half (180°)',
    'threeQuarter': 'Three-Quarter (270°)',
    'wide': 'Wide (320°)',
    'full': 'Full (355°)',
  };

  static const Map<String, String> arcStyleDescriptions = {
    'half': 'Classic semicircle arc, compact horizontal layout',
    'threeQuarter': 'Three-quarter circle with more vertical space',
    'wide': 'Nearly full circle, shows most of the day at once',
    'full': 'Near-complete circle, immersive 24-hour view',
  };

  @override
  void reset() {
    arcStyle = 'half';
    use24HourFormat = false;
    showInteriorTime = false;
    showMoonMarkers = true;
    showSecondaryIcons = true;
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    final style = tool.config.style;
    if (style.customProperties != null) {
      arcStyle = style.customProperties!['arcStyle'] as String? ?? 'half';
      use24HourFormat = style.customProperties!['use24HourFormat'] as bool? ?? false;
      showInteriorTime = style.customProperties!['showInteriorTime'] as bool? ?? false;
      showMoonMarkers = style.customProperties!['showMoonMarkers'] as bool? ?? true;
      showSecondaryIcons = style.customProperties!['showSecondaryIcons'] as bool? ?? true;
    }
  }

  @override
  ToolConfig getConfig() {
    return ToolConfig(
      dataSources: const [],
      style: StyleConfig(
        customProperties: {
          'arcStyle': arcStyle,
          'use24HourFormat': use24HourFormat,
          'showInteriorTime': showInteriorTime,
          'showMoonMarkers': showMoonMarkers,
          'showSecondaryIcons': showSecondaryIcons,
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
              // Arc Style
              Text(
                'Arc Style',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose how the arc is shaped',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              RadioGroup<String>(
                groupValue: arcStyle,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => arcStyle = value);
                  }
                },
                child: Column(
                  children: arcStyleNames.entries.map((entry) {
                    final styleId = entry.key;
                    final styleName = entry.value;
                    final description = arcStyleDescriptions[styleId] ?? '';

                    return RadioListTile<String>(
                      title: Text(styleName),
                      subtitle: Text(
                        description,
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: styleId,
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              // Display Options
              Text(
                'Display Options',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),

              SwitchListTile(
                title: const Text('24-Hour Format'),
                subtitle: const Text('Show times as 14:30 instead of 2:30 PM'),
                value: use24HourFormat,
                onChanged: (value) {
                  setState(() => use24HourFormat = value);
                },
              ),

              SwitchListTile(
                title: const Text('Show Interior Time'),
                subtitle: const Text('Display current time and date inside the arc'),
                value: showInteriorTime,
                onChanged: (value) {
                  setState(() => showInteriorTime = value);
                },
              ),

              SwitchListTile(
                title: const Text('Show Moon Markers'),
                subtitle: const Text('Display moonrise, moonset, and moon phase on arc'),
                value: showMoonMarkers,
                onChanged: (value) {
                  setState(() => showMoonMarkers = value);
                },
              ),

              SwitchListTile(
                title: const Text('Show Secondary Icons'),
                subtitle: const Text('Display twilight, golden hour, and dawn/dusk icons'),
                value: showSecondaryIcons,
                onChanged: (value) {
                  setState(() => showSecondaryIcons = value);
                },
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              // Info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withAlpha(77),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withAlpha(77),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.wb_sunny,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'How It Works',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Sun and moon times are computed locally from the boat\'s GPS position '
                      '(navigation.position). No server-side sun/moon plugin required.\n\n'
                      'The arc shows a 24-hour window centered on the current time, with '
                      'twilight color segments, sunrise/sunset markers, and optional moon tracking.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
