import 'package:flutter/material.dart';
import '../../config/chart_constants.dart';
import '../../services/signalk_service.dart';

/// Reusable chart layer management panel.
///
/// Used by both the runtime chart plotter (bottom sheet) and the configurator.
/// Displays a reorderable list of base map and S-57 chart layers with
/// enable/disable toggles and opacity sliders.
class ChartLayerPanel extends StatelessWidget {
  final List<Map<String, dynamic>> layers;
  final SignalKService signalKService;
  final void Function(VoidCallback fn) setState;
  final VoidCallback? onLayersChanged;

  const ChartLayerPanel({
    super.key,
    required this.layers,
    required this.signalKService,
    required this.setState,
    this.onLayersChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildLayerList(context),
        const SizedBox(height: 8),
        _buildAddLayerButton(context),
      ],
    );
  }

  Widget _buildLayerList(BuildContext context) {
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
        final enabled = layer['enabled'] as bool? ?? true;
        final opacity = (layer['opacity'] as num?)?.toDouble() ?? 1.0;
        final name = type == 'base' ? (baseMapNames[id] ?? id) : id;

        return Card(
          key: ValueKey('$type:$id:$index'),
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
                  type == 'base' ? Icons.map_outlined : Icons.layers,
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
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: enabled,
                    onChanged: (v) {
                      setState(() => layer['enabled'] = v);
                      onLayersChanged?.call();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.white38),
                    constraints: const BoxConstraints.tightFor(width: 28),
                    onPressed: () {
                      setState(() => layers.removeAt(index));
                      onLayersChanged?.call();
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(48, 0, 12, 4),
              child: Row(children: [
                Expanded(
                  child: Slider(
                    value: opacity,
                    min: 0.1, max: 1.0, divisions: 9,
                    onChanged: enabled ? (v) {
                      setState(() => layer['opacity'] = double.parse(v.toStringAsFixed(1)));
                      onLayersChanged?.call();
                    } : null,
                  ),
                ),
                SizedBox(width: 32, child: Text(
                  '${(opacity * 100).round()}%',
                  style: const TextStyle(fontSize: 10, color: Colors.white38),
                  textAlign: TextAlign.right,
                )),
              ]),
            ),
          ]),
        );
      },
    );
  }

  Widget _buildAddLayerButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add Layer'),
          onPressed: () => _showAddLayerPicker(context),
        ),
      ),
    );
  }

  void _showAddLayerPicker(BuildContext ctx) {
    final existingIds = layers.map((l) => l['id'] as String).toSet();
    final options = <Map<String, String>>[];
    for (final entry in baseMapNames.entries) {
      if (!existingIds.contains(entry.key)) {
        options.add({
          'type': 'base', 'id': entry.key, 'name': entry.value,
          'desc': baseMapDescriptions[entry.key] ?? '',
        });
      }
    }

    showModalBottomSheet(
      context: ctx,
      backgroundColor: const Color(0xFF1E1E2E),
      builder: (pickerCtx) => FutureBuilder<Map<String, dynamic>>(
        future: signalKService.getResources('charts'),
        builder: (_, snapshot) {
          final allOptions = List<Map<String, String>>.from(options);
          final charts = snapshot.data ?? {};
          for (final entry in charts.entries) {
            if (!existingIds.contains(entry.key)) {
              final data = entry.value as Map<String, dynamic>;
              allOptions.add({
                'type': 's57', 'id': entry.key,
                'name': data['name'] as String? ?? entry.key,
                'desc': data['description'] as String? ?? 'S-57 chart',
              });
            }
          }
          if (allOptions.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text('All available layers added',
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
                title: Text(opt['name']!, style: const TextStyle(color: Colors.white)),
                subtitle: Text(opt['desc'] ?? '',
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
                onTap: () {
                  Navigator.pop(pickerCtx);
                  setState(() {
                    layers.add({
                      'type': opt['type']!,
                      'id': opt['id']!,
                      'enabled': true,
                      'opacity': 1.0,
                    });
                  });
                  onLayersChanged?.call();
                },
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
