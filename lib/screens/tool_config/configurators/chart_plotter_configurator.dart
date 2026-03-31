import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/chart_tile_cache_service.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for Chart Plotter tool.
///
/// SignalK paths are managed via dataSources (same pattern as autopilot).
/// The standard path selector in the config screen handles path editing.
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
  String cacheRefresh = 'stale'; // 'aging' or 'stale'

  @override
  void reset() {
    enabledChartIds = [];
    trailMinutes = 10;
    showAIS = true;
    showRoute = true;
    hudPosition = 'bottom';
    cacheRefresh = 'stale';
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
    cacheRefresh = props['cacheRefresh'] as String? ?? 'stale';
  }

  @override
  ToolConfig getConfig() {
    return ToolConfig(
      dataSources: const [], // Paths managed by standard path selector
      style: StyleConfig(
        customProperties: {
          'enabledChartIds': enabledChartIds,
          'trailMinutes': trailMinutes,
          'showAIS': showAIS,
          'showRoute': showRoute,
          'hudPosition': hudPosition,
          'cacheRefresh': cacheRefresh,
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
              Text('Trail Duration',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 5, label: Text('5 min')),
                  ButtonSegment(value: 15, label: Text('15 min')),
                  ButtonSegment(value: 60, label: Text('60 min')),
                ],
                selected: {trailMinutes},
                onSelectionChanged: (v) =>
                    setState(() => trailMinutes = v.first),
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

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              // Cache refresh
              Text('Auto-Refresh Charts',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              const Text(
                'Automatically re-fetch cached tiles when they reach this age',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'aging', label: Text('15 days')),
                  ButtonSegment(value: 'stale', label: Text('30 days')),
                ],
                selected: {cacheRefresh},
                onSelectionChanged: (v) =>
                    setState(() => cacheRefresh = v.first),
              ),

              const SizedBox(height: 16),

              // Flush cache
              Builder(builder: (ctx) {
                ChartTileCacheService? cacheService;
                try {
                  cacheService = ctx.read<ChartTileCacheService>();
                } catch (_) {}
                if (cacheService == null) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${cacheService.cachedTileCount} tiles cached',
                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.delete_sweep),
                        label: const Text('Clear Tile Cache'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                        onPressed: () async {
                          await cacheService!.clearCache();
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                );
              }),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'SignalK paths are configured in the Paths tab above.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
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
