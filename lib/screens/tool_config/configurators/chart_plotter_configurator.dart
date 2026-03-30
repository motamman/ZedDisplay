import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for Chart Plotter tool
class ChartPlotterConfigurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'chart_plotter';

  @override
  Size get defaultSize => const Size(4, 4);

  List<String> enabledChartIds = [];
  int trailMinutes = 10;
  bool showAIS = true;
  bool showRoute = true;
  String hudPosition = 'bottom';

  @override
  void reset() {
    enabledChartIds = [];
    trailMinutes = 10;
    showAIS = true;
    showRoute = true;
    hudPosition = 'bottom';
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    final props = tool.config.style.customProperties ?? {};
    enabledChartIds =
        (props['enabledChartIds'] as List?)?.cast<String>() ?? [];
    trailMinutes = props['trailMinutes'] as int? ?? 10;
    showAIS = props['showAIS'] as bool? ?? true;
    showRoute = props['showRoute'] as bool? ?? true;
    hudPosition = props['hudPosition'] as String? ?? 'bottom';
  }

  @override
  ToolConfig getConfig() {
    return ToolConfig(
      dataSources: const [],
      style: StyleConfig(
        customProperties: {
          'enabledChartIds': enabledChartIds,
          'trailMinutes': trailMinutes,
          'showAIS': showAIS,
          'showRoute': showRoute,
          'hudPosition': hudPosition,
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
              // Chart layer selection
              Text('Chart Layers',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              const Text(
                'Select which SignalK chart layers to display',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),
              _buildChartSelector(signalKService, setState),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // Display toggles
              Text('Display',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Show AIS Targets'),
                subtitle: const Text('Nearby vessel markers and COG vectors'),
                value: showAIS,
                onChanged: (v) => setState(() => showAIS = v),
              ),
              SwitchListTile(
                title: const Text('Show Active Route'),
                subtitle: const Text('Route line, waypoints, active leg'),
                value: showRoute,
                onChanged: (v) => setState(() => showRoute = v),
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              // Trail length
              Text('Trail Length',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              const Text(
                'How many minutes of vessel track to display',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: trailMinutes.toDouble(),
                      min: 1,
                      max: 60,
                      divisions: 59,
                      label: '$trailMinutes min',
                      onChanged: (v) =>
                          setState(() => trailMinutes = v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${trailMinutes}m',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              // HUD position
              Text('HUD Position',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'top', label: Text('Top')),
                  ButtonSegment(value: 'bottom', label: Text('Bottom')),
                ],
                selected: {hudPosition},
                onSelectionChanged: (v) =>
                    setState(() => hudPosition = v.first),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChartSelector(
      SignalKService signalKService, void Function(VoidCallback) setState) {
    return FutureBuilder<Map<String, dynamic>>(
      future: signalKService.getResources('charts'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final charts = snapshot.data ?? {};
        if (charts.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No charts available on server',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return Column(
          children: charts.entries.map((entry) {
            final chartId = entry.key;
            final chartData = entry.value as Map<String, dynamic>;
            final name = chartData['name'] as String? ?? chartId;
            final description = chartData['description'] as String?;
            final isEnabled = enabledChartIds.contains(chartId);

            return CheckboxListTile(
              title: Text(name),
              subtitle: description != null ? Text(description) : null,
              value: isEnabled,
              onChanged: (checked) {
                setState(() {
                  if (checked == true) {
                    enabledChartIds.add(chartId);
                  } else {
                    enabledChartIds.remove(chartId);
                  }
                });
              },
            );
          }).toList(),
        );
      },
    );
  }
}
