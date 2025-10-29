import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for wind_compass and autopilot tools
class CompassConfigurator extends ToolConfigurator {
  final String _toolTypeId;

  CompassConfigurator(this._toolTypeId);

  @override
  String get toolTypeId => _toolTypeId;

  @override
  Size get defaultSize => const Size(6, 6);

  // Wind compass state variables
  double laylineAngle = 40.0;       // Target AWA angle in degrees
  double targetTolerance = 3.0;     // Acceptable deviation from target
  bool showAWANumbers = true;       // Show numeric AWA display
  bool enableVMG = false;           // Enable VMG optimization

  // Autopilot-specific state variables
  bool headingTrue = false;         // Use true vs magnetic heading
  bool invertRudder = false;        // Invert rudder angle display
  int fadeDelaySeconds = 5;         // Seconds before controls fade

  @override
  void reset() {
    laylineAngle = 40.0;
    targetTolerance = 3.0;
    showAWANumbers = true;
    enableVMG = false;
    headingTrue = false;
    invertRudder = false;
    fadeDelaySeconds = 5;
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    final style = tool.config.style;

    // Load common wind settings
    laylineAngle = style.laylineAngle ?? 40.0;
    targetTolerance = style.targetTolerance ?? 3.0;

    if (style.customProperties != null) {
      showAWANumbers = style.customProperties!['showAWANumbers'] as bool? ?? true;
      enableVMG = style.customProperties!['enableVMG'] as bool? ?? false;

      // Autopilot-specific
      if (_toolTypeId == 'autopilot') {
        headingTrue = style.customProperties!['headingTrue'] as bool? ?? false;
        invertRudder = style.customProperties!['invertRudder'] as bool? ?? false;
        fadeDelaySeconds = style.customProperties!['fadeDelaySeconds'] as int? ?? 5;
      }
    }
  }

  @override
  ToolConfig getConfig() {
    return ToolConfig(
      dataSources: const [],
      style: StyleConfig(
        laylineAngle: laylineAngle,
        targetTolerance: targetTolerance,
        customProperties: {
          'showAWANumbers': showAWANumbers,
          'enableVMG': enableVMG,
          if (_toolTypeId == 'autopilot') ...{
            'headingTrue': headingTrue,
            'invertRudder': invertRudder,
            'fadeDelaySeconds': fadeDelaySeconds,
          },
        },
      ),
    );
  }

  @override
  String? validate() {
    if (laylineAngle < 30 || laylineAngle > 50) {
      return 'Layline angle must be between 30° and 50°';
    }
    if (targetTolerance < 1 || targetTolerance > 10) {
      return 'Target tolerance must be between 1° and 10°';
    }
    if (_toolTypeId == 'autopilot') {
      if (fadeDelaySeconds < 3 || fadeDelaySeconds > 30) {
        return 'Fade delay must be between 3 and 30 seconds';
      }
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
              // Autopilot-specific settings (top)
              if (_toolTypeId == 'autopilot') ...[
                Text(
                  'Autopilot Display Settings',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Use True Heading'),
                  subtitle: const Text('Display true heading instead of magnetic'),
                  value: headingTrue,
                  onChanged: (value) {
                    setState(() => headingTrue = value);
                  },
                ),
                SwitchListTile(
                  title: const Text('Invert Rudder Display'),
                  subtitle: const Text('Reverse rudder angle visualization (for non-standard sensor polarity)'),
                  value: invertRudder,
                  onChanged: (value) {
                    setState(() => invertRudder = value);
                  },
                ),
                const SizedBox(height: 16),
              ],

              // Performance Sailing Settings (common to both)
              Text(
                _toolTypeId == 'autopilot'
                    ? 'Performance Sailing Settings (Wind Mode)'
                    : 'Performance Sailing Settings',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),

              // Target AWA Angle
              ListTile(
                title: const Text('Target AWA Angle'),
                subtitle: Text(
                  '${laylineAngle.toStringAsFixed(0)}° - Optimal close-hauled angle for your boat',
                  style: const TextStyle(fontSize: 12),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              Slider(
                value: laylineAngle,
                min: 30,
                max: 50,
                divisions: 20,
                label: '${laylineAngle.toStringAsFixed(0)}°',
                onChanged: (value) {
                  setState(() => laylineAngle = value);
                },
              ),
              const SizedBox(height: 8),

              // Target Tolerance
              ListTile(
                title: const Text('Target Tolerance'),
                subtitle: Text(
                  '±${targetTolerance.toStringAsFixed(0)}° - Acceptable deviation (green zone)',
                  style: const TextStyle(fontSize: 12),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              Slider(
                value: targetTolerance,
                min: 1,
                max: 10,
                divisions: 9,
                label: '±${targetTolerance.toStringAsFixed(0)}°',
                onChanged: (value) {
                  setState(() => targetTolerance = value);
                },
              ),
              const SizedBox(height: 8),

              // Wind Compass Only: Show AWA Numbers
              if (_toolTypeId == 'wind_compass')
                SwitchListTile(
                  title: const Text('Show AWA Numbers'),
                  subtitle: const Text('Display numeric AWA with performance feedback'),
                  value: showAWANumbers,
                  onChanged: (value) {
                    setState(() => showAWANumbers = value);
                  },
                ),

              // Autopilot Only: Fade Delay
              if (_toolTypeId == 'autopilot') ...[
                ListTile(
                  title: const Text('Control Fade Delay'),
                  subtitle: Text(
                    '${fadeDelaySeconds}s - Seconds before controls fade after activity',
                    style: const TextStyle(fontSize: 12),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                Slider(
                  value: fadeDelaySeconds.toDouble(),
                  min: 3,
                  max: 30,
                  divisions: 27,
                  label: '${fadeDelaySeconds}s',
                  onChanged: (value) {
                    setState(() => fadeDelaySeconds = value.round());
                  },
                ),
                const SizedBox(height: 8),
              ],

              // Enable VMG (both tools)
              SwitchListTile(
                title: const Text('Enable VMG Optimization'),
                subtitle: const Text('Use polar-based dynamic target AWA (varies with wind speed)'),
                value: enableVMG,
                onChanged: (value) {
                  setState(() => enableVMG = value);
                },
              ),

              // VMG Info Box (when enabled)
              if (enableVMG)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'VMG Mode Active',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Target AWA will dynamically adjust based on true wind speed using built-in polar data. Manual target angle is overridden.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
