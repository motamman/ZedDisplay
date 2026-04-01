import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/chart_constants.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/chart_tile_cache_service.dart';
import '../../../services/signalk_service.dart';
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

  // Base map options and descriptions from chart_constants.dart

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
              _buildLayerList(signalKService, setState),
              const SizedBox(height: 8),
              _buildAddLayerButton(signalKService, setState),

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

  Widget _buildLayerList(
      SignalKService signalKService, void Function(VoidCallback) setState) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: layers.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex--;
          final item = layers.removeAt(oldIndex);
          layers.insert(newIndex, item);
        });
      },
      itemBuilder: (context, index) {
        final layer = layers[index];
        final type = layer['type'] as String;
        final id = layer['id'] as String;
        final enabled = layer['enabled'] as bool? ?? true;
        final opacity = (layer['opacity'] as num?)?.toDouble() ?? 1.0;

        String name;
        IconData icon;
        if (type == 'base') {
          name = baseMapNames[id] ?? id;
          icon = Icons.map_outlined;
        } else {
          name = id;
          icon = Icons.layers;
        }

        return Card(
          key: ValueKey('$type:$id:$index'),
          child: Column(
            children: [
              ListTile(
                leading: ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_handle, color: Colors.grey),
                ),
                title: Row(
                  children: [
                    Icon(icon, size: 16, color: enabled ? Colors.white70 : Colors.white24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(name,
                          style: TextStyle(
                            color: enabled ? Colors.white : Colors.white38,
                            fontSize: 14,
                          )),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: type == 'base' ? Colors.blue.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        type == 'base' ? 'Base' : 'S-57',
                        style: TextStyle(
                          fontSize: 10,
                          color: type == 'base' ? Colors.blue : Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: enabled,
                      onChanged: (v) => setState(() => layer['enabled'] = v),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () => setState(() => layers.removeAt(index)),
                      constraints: const BoxConstraints.tightFor(width: 32),
                    ),
                  ],
                ),
              ),
              // Opacity slider
              Padding(
                padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
                child: Row(
                  children: [
                    const Text('Opacity', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Expanded(
                      child: Slider(
                        value: opacity,
                        min: 0.1,
                        max: 1.0,
                        divisions: 9,
                        label: '${(opacity * 100).round()}%',
                        onChanged: (v) =>
                            setState(() => layer['opacity'] = double.parse(v.toStringAsFixed(1))),
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text('${(opacity * 100).round()}%',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                          textAlign: TextAlign.right),
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

  Widget _buildAddLayerButton(
      SignalKService signalKService, void Function(VoidCallback) setState) {
    return Builder(
      builder: (ctx) => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add Layer'),
          onPressed: () {
            final existingIds = layers.map((l) => l['id'] as String).toSet();

            // Build available options
            final options = <Map<String, String>>[];
            for (final entry in baseMapNames.entries) {
              if (!existingIds.contains(entry.key)) {
                options.add({
                  'type': 'base',
                  'id': entry.key,
                  'name': entry.value,
                  'desc': baseMapDescriptions[entry.key] ?? '',
                });
              }
            }

            showModalBottomSheet(
              context: ctx,
              backgroundColor: const Color(0xFF1E1E2E),
              builder: (sheetCtx) => FutureBuilder<Map<String, dynamic>>(
                future: signalKService.getResources('charts'),
                builder: (_, snapshot) {
                  // Add S-57 charts from server
                  final allOptions = List<Map<String, String>>.from(options);
                  final charts = snapshot.data ?? {};
                  for (final entry in charts.entries) {
                    if (!existingIds.contains(entry.key)) {
                      final data = entry.value as Map<String, dynamic>;
                      allOptions.add({
                        'type': 's57',
                        'id': entry.key,
                        'name': data['name'] as String? ?? entry.key,
                      });
                    }
                  }

                  if (allOptions.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('All available layers already added',
                          style: TextStyle(color: Colors.white54)),
                    );
                  }

                  return ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: allOptions.map((opt) {
                      final isBase = opt['type'] == 'base';
                      return ListTile(
                        leading: Icon(
                          isBase ? Icons.map_outlined : Icons.layers,
                          color: isBase ? Colors.blue : Colors.green,
                        ),
                        title: Text(opt['name']!,
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                            opt['desc']?.isNotEmpty == true
                                ? opt['desc']!
                                : (isBase ? 'Base map' : 'S-57 chart'),
                            style: const TextStyle(color: Colors.white38, fontSize: 12)),
                        onTap: () {
                          Navigator.pop(sheetCtx);
                          setState(() {
                            layers.add({
                              'type': opt['type']!,
                              'id': opt['id']!,
                              'enabled': true,
                              'opacity': 1.0,
                            });
                          });
                        },
                      );
                    }).toList(),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
