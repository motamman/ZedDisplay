import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for weather alerts tool
class WeatherAlertsConfigurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'weather_alerts';

  @override
  Size get defaultSize => const Size(2, 2);

  // State
  bool compact = false;

  @override
  void reset() {
    compact = false;
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    compact = tool.config.style.customProperties?['compact'] as bool? ?? false;
  }

  @override
  ToolConfig getConfig() {
    return ToolConfig(
      dataSources: [],
      style: StyleConfig(
        customProperties: {
          'compact': compact,
        },
      ),
    );
  }

  @override
  String? validate() {
    return null; // No validation needed
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
                'Weather Alerts',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Displays NWS weather alerts for your location',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),

              // Data source info
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue.shade400),
                          const SizedBox(width: 8),
                          const Text(
                            'Data Source',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Alerts are fetched from SignalK at:\nenvironment.outside.nws.alert.*\n\n'
                        'Requires NWS Alerts plugin configured in SignalK.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),

              // Display Options
              Text(
                'Display Options',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),

              SwitchListTile(
                title: const Text('Compact Mode'),
                subtitle: const Text('Show condensed view with tap to expand'),
                value: compact,
                onChanged: (value) {
                  setState(() => compact = value);
                },
              ),

              const SizedBox(height: 16),

              // Severity legend
              Text(
                'Alert Severity Levels',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),

              _buildSeverityLegend(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSeverityLegend(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _severityRow('Extreme', Colors.purple.shade700, 'Tornado, Hurricane'),
            _severityRow('Severe', Colors.red.shade700, 'Severe Thunderstorm, Blizzard'),
            _severityRow('Moderate', Colors.orange.shade700, 'Winter Storm, Wind Advisory'),
            _severityRow('Minor', Colors.yellow.shade700, 'Frost, Freeze'),
          ],
        ),
      ),
    );
  }

  Widget _severityRow(String level, Color color, String examples) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: Text(
              level,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              examples,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
