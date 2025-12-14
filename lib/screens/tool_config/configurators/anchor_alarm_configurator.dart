import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for Anchor Alarm tool
/// Provides alarm sound and check-in settings
class AnchorAlarmConfigurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'anchor_alarm';

  @override
  Size get defaultSize => const Size(2, 2);

  // Alarm settings
  String alarmSound = 'foghorn';
  bool checkInEnabled = false;
  int checkInIntervalMinutes = 30;
  int checkInGracePeriodSeconds = 60;

  static const Map<String, String> alarmSoundNames = {
    'bell': 'Bell',
    'foghorn': 'Foghorn',
    'chimes': 'Chimes',
    'ding': 'Ding',
    'whistle': 'Whistle',
    'dog': 'Dog Bark',
  };

  @override
  void reset() {
    alarmSound = 'foghorn';
    checkInEnabled = false;
    checkInIntervalMinutes = 30;
    checkInGracePeriodSeconds = 60;
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    final props = tool.config.style.customProperties ?? {};
    alarmSound = props['alarmSound'] as String? ?? 'foghorn';
    checkInEnabled = props['checkInEnabled'] as bool? ?? false;
    checkInIntervalMinutes = props['checkInIntervalMinutes'] as int? ?? 30;
    checkInGracePeriodSeconds = props['checkInGracePeriodSeconds'] as int? ?? 60;
  }

  @override
  ToolConfig getConfig() {
    return ToolConfig(
      dataSources: const [], // Paths handled by standard path selector
      style: StyleConfig(
        customProperties: {
          'alarmSound': alarmSound,
          'checkInEnabled': checkInEnabled,
          'checkInIntervalMinutes': checkInIntervalMinutes,
          'checkInGracePeriodSeconds': checkInGracePeriodSeconds,
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
              // Alarm Sound Section
              Text(
                'Alarm Sound',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              DropdownMenu<String>(
                initialSelection: alarmSound,
                expandedInsets: EdgeInsets.zero,
                dropdownMenuEntries: alarmSoundNames.entries.map((e) {
                  return DropdownMenuEntry(value: e.key, label: e.value);
                }).toList(),
                onSelected: (value) {
                  if (value != null) {
                    setState(() => alarmSound = value);
                  }
                },
              ),

              const SizedBox(height: 24),

              // Check-In Section
              Text(
                'Anchor Watch Check-In',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Periodic check-in to ensure crew is monitoring the anchor',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Enable Check-In'),
                subtitle: const Text('Require periodic acknowledgment'),
                value: checkInEnabled,
                onChanged: (value) {
                  setState(() => checkInEnabled = value);
                },
              ),
              if (checkInEnabled) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: checkInIntervalMinutes.toString(),
                        decoration: const InputDecoration(
                          labelText: 'Interval (minutes)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          final parsed = int.tryParse(value);
                          if (parsed != null && parsed > 0) {
                            checkInIntervalMinutes = parsed;
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        initialValue: checkInGracePeriodSeconds.toString(),
                        decoration: const InputDecoration(
                          labelText: 'Grace Period (seconds)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          final parsed = int.tryParse(value);
                          if (parsed != null && parsed > 0) {
                            checkInGracePeriodSeconds = parsed;
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 24),

              // Info about paths
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
                          Icons.info_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'SignalK Paths',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Use the Data Sources section above to customize SignalK paths '
                      'if your setup differs from the defaults.',
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
