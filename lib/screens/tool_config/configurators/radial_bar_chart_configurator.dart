import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for the radial bar chart tool.
///
/// Min/max, colour, and the show value/label/unit toggles are handled by the
/// shared style options panel; this adds the ring-specific options.
class RadialBarChartConfigurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'radial_bar_chart';

  @override
  Size get defaultSize => const Size(2, 2);

  String title = '';
  bool showTicks = false;
  int divisions = 10;
  double innerRadius = 0.35;
  double gap = 0.04;

  @override
  void reset() {
    title = '';
    showTicks = false;
    divisions = 10;
    innerRadius = 0.35;
    gap = 0.04;
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    final props = tool.config.style.customProperties;
    if (props != null) {
      title = props['title'] as String? ?? '';
      showTicks = props['showTicks'] as bool? ?? false;
      divisions = props['divisions'] as int? ?? 10;
      innerRadius = (props['innerRadius'] as num?)?.toDouble() ?? 0.35;
      gap = (props['gap'] as num?)?.toDouble() ?? 0.04;
    }
  }

  @override
  ToolConfig getConfig() {
    return ToolConfig(
      dataSources: const [],
      style: StyleConfig(
        customProperties: {
          'title': title,
          'showTicks': showTicks,
          'divisions': divisions,
          'innerRadius': innerRadius,
          'gap': gap,
        },
      ),
    );
  }

  @override
  String? validate() {
    // Divisions only matter when tick marks are shown; don't block a save on a
    // field that's hidden and irrelevant.
    if (!showTicks) return null;
    if (divisions < 2) return 'Divisions must be at least 2';
    if (divisions > 50) return 'Divisions cannot exceed 50';
    return null;
  }

  @override
  Widget buildConfigUI(BuildContext context, SignalKService signalKService) {
    return StatefulBuilder(
      builder: (context, setState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Radial Bar Chart Configuration',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),

            // Title
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Title (optional)',
                border: OutlineInputBorder(),
                helperText: 'Shown above the rings',
              ),
              initialValue: title,
              onChanged: (value) => title = value,
            ),
            const SizedBox(height: 16),

            // Show ticks
            SwitchListTile(
              title: const Text('Show Tick Marks'),
              subtitle: const Text('Display ticks and labels on the outer ring'),
              value: showTicks,
              onChanged: (value) => setState(() => showTicks = value),
            ),

            // Divisions (only relevant when ticks are shown)
            if (showTicks) ...[
              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Divisions (tick marks)',
                  border: OutlineInputBorder(),
                  helperText: 'Number of major divisions on the outer ring',
                ),
                keyboardType: TextInputType.number,
                initialValue: divisions.toString(),
                onChanged: (value) {
                  final parsed = int.tryParse(value);
                  if (parsed != null && parsed > 0) divisions = parsed;
                },
              ),
            ],
            const SizedBox(height: 16),

            // Inner radius (hollow centre)
            Text('Inner Radius: ${(innerRadius * 100).toStringAsFixed(0)}%'),
            Slider(
              value: innerRadius,
              min: 0.0,
              max: 0.8,
              divisions: 16,
              label: '${(innerRadius * 100).toStringAsFixed(0)}%',
              onChanged: (value) => setState(() => innerRadius = value),
            ),

            // Gap between rings
            Text('Ring Gap: ${(gap * 100).toStringAsFixed(0)}%'),
            Slider(
              value: gap,
              min: 0.0,
              max: 0.1,
              divisions: 10,
              label: '${(gap * 100).toStringAsFixed(0)}%',
              onChanged: (value) => setState(() => gap = value),
            ),
          ],
        );
      },
    );
  }
}
