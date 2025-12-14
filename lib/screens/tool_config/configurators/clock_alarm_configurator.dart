import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for Clock & Alarm tool
/// Provides face style selection only - alarms are managed within the tool itself
class ClockAlarmConfigurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'clock_alarm';

  @override
  Size get defaultSize => const Size(2, 2);

  // Configuration state
  String faceStyle = 'analog';

  static const Map<String, String> faceStyleNames = {
    'analog': 'Analog',
    'digital': 'Digital',
    'minimal': 'Minimal',
    'nautical': 'Nautical',
    'modern': 'Modern',
  };

  static const Map<String, String> faceStyleDescriptions = {
    'analog': 'Classic analog clock with hour markers and sweeping hands',
    'digital': 'Large digital time display with seconds and date',
    'minimal': 'Clean minimalist digital display showing only time',
    'nautical': 'Maritime-inspired analog face with ship\'s bell markers',
    'modern': 'Contemporary analog design with dot markers',
  };

  @override
  void reset() {
    faceStyle = 'analog';
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    final style = tool.config.style;
    if (style.customProperties != null) {
      faceStyle = style.customProperties!['faceStyle'] as String? ?? 'analog';
    }
  }

  @override
  ToolConfig getConfig() {
    return ToolConfig(
      dataSources: const [],
      style: StyleConfig(
        customProperties: {
          'faceStyle': faceStyle,
        },
      ),
    );
  }

  @override
  String? validate() {
    // No validation needed - face style always has a valid default
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
                'Clock Face Style',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose how the clock displays the time',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),

              // Face style options
              RadioGroup<String>(
                groupValue: faceStyle,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => faceStyle = value);
                  }
                },
                child: Column(
                  children: faceStyleNames.entries.map((entry) {
                    final styleId = entry.key;
                    final styleName = entry.value;
                    final description = faceStyleDescriptions[styleId] ?? '';

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

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // Info about alarms
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
                          Icons.alarm,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Managing Alarms',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Alarms are managed directly in the clock widget:\n'
                      '• Long-press the clock to open the alarms panel\n'
                      '• Add, edit, or delete alarms from the panel\n'
                      '• Alarms are stored in SignalK and persist across sessions',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Text(
                'The clock color can be customized using the color picker in the main settings above.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha(179),
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}
