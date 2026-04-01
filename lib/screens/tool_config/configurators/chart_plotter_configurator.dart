import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/chart_tile_cache_service.dart';
import '../../../services/signalk_service.dart';
import '../../../widgets/chart_plotter/chart_layer_panel.dart';
import '../base_tool_configurator.dart';

/// Configurator for Chart Plotter tool.
///
/// SignalK paths are managed via slotDefinitions (same pattern as wind compass).
/// The standard path selector in the config screen handles path editing.
class ChartPlotterConfigurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'chart_plotter';

  @override
  Size get defaultSize => const Size(4, 4);


  List<Map<String, dynamic>> layers = [];
  int trailMinutes = 10;
  bool showAIS = true;
  bool showRoute = true;
  String hudStyle = 'text';
  String hudPosition = 'bottom';
  String cacheRefresh = 'stale';

  @override
  void reset() {
    layers = [
      {'type': 'base', 'id': 'carto_voyager', 'enabled': true, 'opacity': 1.0},
    ];
    trailMinutes = 10;
    showAIS = true;
    showRoute = true;
    hudStyle = 'text';
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
    final rawLayers = props['layers'] as List?;
    if (rawLayers != null && rawLayers.isNotEmpty) {
      layers = rawLayers.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else {
      // Migrate from old enabledChartIds format
      final oldIds = (props['enabledChartIds'] as List?)?.cast<String>() ?? [];
      layers = [
        {'type': 'base', 'id': 'carto_voyager', 'enabled': true, 'opacity': 1.0},
      ];
      for (final id in oldIds) {
        layers.add({'type': 's57', 'id': id, 'enabled': true, 'opacity': 1.0});
      }
      if (oldIds.isEmpty) {
        layers.add({'type': 's57', 'id': '01CGD_ENCs', 'enabled': true, 'opacity': 1.0});
      }
    }
    trailMinutes = props['trailMinutes'] as int? ?? 10;
    showAIS = props['showAIS'] as bool? ?? true;
    showRoute = props['showRoute'] as bool? ?? true;
    hudStyle = props['hudStyle'] as String? ?? 'text';
    hudPosition = props['hudPosition'] as String? ?? 'bottom';
    cacheRefresh = props['cacheRefresh'] as String? ?? 'stale';
  }

  @override
  ToolConfig getConfig() {
    return ToolConfig(
      dataSources: const [],
      style: StyleConfig(
        customProperties: {
          'layers': layers,
          'trailMinutes': trailMinutes,
          'showAIS': showAIS,
          'showRoute': showRoute,
          'hudStyle': hudStyle,
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
              // Chart layers — reorderable
              Text('Chart Layers',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              const Text(
                'Drag to reorder. Bottom layer renders first.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),
              ChartLayerPanel(
                layers: layers,
                signalKService: signalKService,
                setState: setState,
              ),

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

              // HUD style
              Text('HUD Style',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'text', label: Text('Text')),
                  ButtonSegment(value: 'visual', label: Text('Visual')),
                  ButtonSegment(value: 'off', label: Text('Off')),
                ],
                selected: {hudStyle},
                onSelectionChanged: (v) =>
                    setState(() => hudStyle = v.first),
              ),

              if (hudStyle != 'off') ...[
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

              // Cache management
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

  // Layer list and add-layer picker moved to ChartLayerPanel
}
