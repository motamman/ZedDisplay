import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for Position Display tool
/// Provides format selection and display options
class PositionDisplayConfigurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'position_display';

  @override
  Size get defaultSize => const Size(2, 1);

  // Display settings
  String format = 'ddm';
  bool showLabels = true;
  bool compactMode = false;

  static const Map<String, String> formatNames = {
    'dd': 'Decimal Degrees',
    'ddm': 'Degrees Decimal Minutes',
    'dms': 'Degrees Minutes Seconds',
  };

  static const Map<String, String> formatExamples = {
    'dd': '47.605867° N',
    'ddm': "47° 36.352' N",
    'dms': '47° 36\' 21.12" N',
  };

  @override
  void reset() {
    format = 'ddm';
    showLabels = true;
    compactMode = false;
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    final props = tool.config.style.customProperties ?? {};
    format = props['format'] as String? ?? 'ddm';
    showLabels = props['showLabels'] as bool? ?? true;
    compactMode = props['compactMode'] as bool? ?? false;
  }

  @override
  ToolConfig getConfig() {
    return ToolConfig(
      dataSources: const [], // Paths handled by standard path selector
      style: StyleConfig(
        customProperties: {
          'format': format,
          'showLabels': showLabels,
          'compactMode': compactMode,
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
              // Format Section
              Text(
                'Coordinate Format',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),

              // Format options as radio tiles
              ...formatNames.entries.map((entry) {
                final formatId = entry.key;
                final formatName = entry.value;
                final example = formatExamples[formatId] ?? '';

                return RadioListTile<String>(
                  title: Text(formatName),
                  subtitle: Text(
                    example,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                  value: formatId,
                  groupValue: format,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => format = value);
                    }
                  },
                );
              }),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // Display Options
              Text(
                'Display Options',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),

              SwitchListTile(
                title: const Text('Show Labels'),
                subtitle: const Text('Display LAT/LON labels with icons'),
                value: showLabels,
                onChanged: (value) {
                  setState(() => showLabels = value);
                },
              ),

              SwitchListTile(
                title: const Text('Compact Mode'),
                subtitle: const Text('Minimal display without labels or icons'),
                value: compactMode,
                onChanged: (value) {
                  setState(() => compactMode = value);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
