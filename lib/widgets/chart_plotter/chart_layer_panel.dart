import 'package:flutter/material.dart';

import '../../config/chart_constants.dart';

/// Reorderable list of every chart-domain layer the user can toggle:
/// the basemaps published in `chart_constants.dart`, the OpenSeaMap
/// seamark overlay, the GEBCO depth overlay, and every S-57 chart
/// the route planner's `/charts` catalog publishes.
///
/// The list is the **whole catalog**, never a user-curated subset:
/// fresh charts from the server appear automatically; charts gone
/// from the server disappear automatically. The user just toggles,
/// reorders, and tunes opacity. There is no add / remove. The
/// chart plotter persists this list across app restarts via
/// `_persistLayerPrefs`.
///
/// Render order = list order: dragging a basemap above another
/// puts it on top in the chart. The S-57 group renders at a fixed
/// position after the basemap/overlay/depth stack — reorder among
/// s57 rows is purely organisational (the s52 painter has its own
/// display-priority logic).
class ChartLayerPanel extends StatelessWidget {
  final List<Map<String, dynamic>> layers;
  final void Function(VoidCallback fn) setState;
  final VoidCallback? onLayersChanged;

  const ChartLayerPanel({
    super.key,
    required this.layers,
    required this.setState,
    this.onLayersChanged,
  });

  @override
  Widget build(BuildContext context) {
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
        onLayersChanged?.call();
      },
      itemBuilder: (_, index) {
        final layer = layers[index];
        final type = layer['type'] as String;
        final id = layer['id'] as String;
        final enabled = layer['enabled'] as bool? ?? false;
        final opacity = (layer['opacity'] as num?)?.toDouble() ?? 1.0;

        // Built-in name + icon per type. Names for base maps come
        // from the shared constants table; the special overlays
        // and the depth tile have hardcoded labels.
        final String name;
        final IconData typeIcon;
        switch (type) {
          case 'base':
            name = baseMapNames[id] ?? id;
            typeIcon = Icons.map_outlined;
            break;
          case 'overlay':
            name = id == 'openseamap' ? 'OpenSeaMap' : id;
            typeIcon = Icons.layers_outlined;
            break;
          case 'depth':
            name = 'Depth';
            typeIcon = Icons.swap_vert;
            break;
          case 's57':
            // S-57 chart entries — name is the chart id from the
            // route planner's `/charts` catalog (e.g. "01CGD_ENCs").
            name = id;
            typeIcon = Icons.layers;
            break;
          default:
            name = id;
            typeIcon = Icons.layers;
        }

        return Card(
          // Stable key: `$type:$id` uniquely identifies a layer
          // row. Including `$index` would break reorder element
          // reuse (keys would shift with every move).
          key: ValueKey('$type:$id'),
          color: const Color(0xFF2A2A3E),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Column(children: [
            ListTile(
              dense: true,
              leading: ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle, color: Colors.grey, size: 20),
              ),
              title: Row(children: [
                Icon(
                  typeIcon,
                  size: 14,
                  color: enabled ? Colors.white70 : Colors.white24,
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(name,
                  style: TextStyle(
                    color: enabled ? Colors.white : Colors.white38,
                    fontSize: 13,
                  ))),
              ]),
              trailing: Switch(
                value: enabled,
                onChanged: (v) {
                  setState(() => layer['enabled'] = v);
                  onLayersChanged?.call();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(48, 0, 12, 4),
              child: Row(children: [
                Expanded(
                  child: Slider(
                    value: opacity,
                    min: 0.1,
                    max: 1.0,
                    divisions: 9,
                    onChanged: enabled
                        ? (v) {
                            setState(() => layer['opacity'] =
                                double.parse(v.toStringAsFixed(1)));
                            onLayersChanged?.call();
                          }
                        : null,
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    '${(opacity * 100).round()}%',
                    style: const TextStyle(
                        fontSize: 10, color: Colors.white38),
                    textAlign: TextAlign.right,
                  ),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}
