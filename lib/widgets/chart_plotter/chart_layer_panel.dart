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

  /// When non-null, only layers matching the predicate render. The
  /// panel still mutates the master `layers` list on toggle and
  /// reorder — it just shows a slice. Used by the layer sheet's
  /// `Basemaps` / `Charts` tabs to render disjoint subsets while
  /// preserving full-list paint order and persistence.
  final bool Function(Map<String, dynamic>)? filter;

  /// `false` disables the drag-handle column. Useful for tabs that
  /// only ever show one row (or no rows) where reorder would just
  /// be visual noise.
  final bool reorderable;

  const ChartLayerPanel({
    super.key,
    required this.layers,
    required this.setState,
    this.onLayersChanged,
    this.filter,
    this.reorderable = true,
  });

  /// Indices in `layers` (master list) that pass the filter, in
  /// master order. The panel iterates this for itemBuilder, and
  /// uses it to translate visible-index reorder events back to
  /// master-index moves so the master order — and therefore paint
  /// order and persistence — stays correct.
  List<int> _visibleMasterIndices() {
    if (filter == null) {
      return [for (var i = 0; i < layers.length; i++) i];
    }
    final out = <int>[];
    for (var i = 0; i < layers.length; i++) {
      if (filter!(layers[i])) out.add(i);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final visibleIdx = _visibleMasterIndices();
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: visibleIdx.length,
      buildDefaultDragHandles: false,
      onReorder: (oldVisible, newVisible) {
        // Translate visible indices to master indices. The master
        // list is reordered so the dragged row lands immediately
        // before the row that previously sat at `newVisible` in the
        // filtered view; if the user dragged past the last visible
        // row, the move ends up after the previously-last visible
        // master index.
        if (!reorderable) return;
        final n = visibleIdx.length;
        if (oldVisible < 0 || oldVisible >= n) return;
        if (newVisible < 0 || newVisible > n) return;
        setState(() {
          final masterFrom = visibleIdx[oldVisible];
          final item = layers.removeAt(masterFrom);
          // After removeAt, the remaining indices shift. Compute
          // the destination master index from the (still-correct)
          // post-removal pointer to the visible row that should now
          // sit immediately *after* the moved item.
          int masterTo;
          if (newVisible >= n) {
            // Past the last visible row → place after the last
            // remaining visible master index.
            final lastVisibleMaster =
                visibleIdx[n - 1] > masterFrom
                    ? visibleIdx[n - 1] - 1
                    : visibleIdx[n - 1];
            masterTo = lastVisibleMaster + 1;
          } else if (newVisible > oldVisible) {
            // ReorderableListView already adjusts newIndex by +1
            // when dragging downward; we mirror that semantics by
            // dropping into the position previously held by the
            // (newVisible)-th visible row, post-removal.
            final dst = newVisible; // the row that was at newVisible
            // After remove, that row's master index has shifted
            // down by 1 if it was past masterFrom.
            final origMaster = visibleIdx[dst];
            masterTo = origMaster > masterFrom ? origMaster - 1 : origMaster;
          } else {
            final origMaster = visibleIdx[newVisible];
            masterTo = origMaster > masterFrom ? origMaster - 1 : origMaster;
          }
          if (masterTo < 0) masterTo = 0;
          if (masterTo > layers.length) masterTo = layers.length;
          layers.insert(masterTo, item);
        });
        onLayersChanged?.call();
      },
      itemBuilder: (_, index) {
        final layer = layers[visibleIdx[index]];
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
              leading: reorderable
                  ? ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_handle,
                          color: Colors.grey, size: 20),
                    )
                  : const SizedBox(width: 20),
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
