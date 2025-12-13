import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Tank type with associated color
class TankType {
  final String id;
  final String name;
  final Color color;

  const TankType(this.id, this.name, this.color);
}

/// Available tank types
const List<TankType> tankTypes = [
  TankType('diesel', 'Diesel', Color(0xFFE91E63)),
  TankType('petrol', 'Petrol', Color(0xFFFF5722)),
  TankType('gasoline', 'Gasoline', Color(0xFFFF5722)),
  TankType('propane', 'Propane', Color(0xFF2E7D32)),
  TankType('freshWater', 'Fresh Water', Color(0xFF2196F3)),
  TankType('blackWater', 'Black Water', Color(0xFF5D4037)),
  TankType('wasteWater', 'Waste Water', Color(0xFF795548)),
  TankType('liveWell', 'Live Well', Color(0xFF4CAF50)),
  TankType('lubrication', 'Lubrication', Color(0xFF9C27B0)),
];

/// Configurator for tanks tool
/// Only manages tank types (for colors) and display options
/// Paths are managed by the standard data source picker
class TanksConfigurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'tanks';

  @override
  Size get defaultSize => const Size(3, 2);

  // State - only style options, NOT paths
  List<String> tankTypeIds = [];
  bool showCapacity = false;
  bool showLabel = false;
  String label = '';
  int _dataSourceCount = 0; // Track how many data sources exist

  @override
  void reset() {
    tankTypeIds = [];
    showCapacity = false;
    showLabel = false;
    label = '';
    _dataSourceCount = 0;
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
    // Defaults will be applied when data sources are added
    tankTypeIds = ['diesel', 'freshWater'];
    _dataSourceCount = 2;
  }

  @override
  void loadFromTool(Tool tool) {
    _dataSourceCount = tool.config.dataSources.length;
    final style = tool.config.style;
    showLabel = style.showLabel ?? false;
    if (style.customProperties != null) {
      showCapacity = style.customProperties!['showCapacity'] as bool? ?? false;
      label = style.customProperties!['label'] as String? ?? '';
      final types = style.customProperties!['tankTypes'];
      if (types is List) {
        tankTypeIds = types.map((t) => t?.toString() ?? 'diesel').toList();
      } else {
        // Infer from paths
        tankTypeIds = tool.config.dataSources.map((ds) => _inferTypeFromPath(ds.path)).toList();
      }
    }
    // Ensure tankTypeIds matches data source count
    while (tankTypeIds.length < _dataSourceCount) {
      tankTypeIds.add('diesel');
    }
  }

  /// Infer tank type from path
  String _inferTypeFromPath(String path) {
    final lowerPath = path.toLowerCase();
    if (lowerPath.contains('diesel')) return 'diesel';
    if (lowerPath.contains('petrol')) return 'petrol';
    if (lowerPath.contains('gasoline')) return 'gasoline';
    if (lowerPath.contains('propane') || lowerPath.contains('lpg')) return 'propane';
    if (lowerPath.contains('fuel')) return 'diesel';
    for (final type in tankTypes) {
      if (lowerPath.contains(type.id.toLowerCase())) {
        return type.id;
      }
    }
    return 'diesel';
  }

  @override
  ToolConfig getConfig() {
    // Only return style config - dataSources come from the standard picker
    return ToolConfig(
      dataSources: [], // Empty - screen manages this
      style: StyleConfig(
        showLabel: showLabel,
        customProperties: {
          'showCapacity': showCapacity,
          'label': label,
          'tankTypes': tankTypeIds,
        },
      ),
    );
  }

  @override
  String? validate() {
    // No validation needed - paths validated by standard system
    return null;
  }

  /// Get color for a tank type ID
  Color _getTypeColor(String typeId) {
    return tankTypes.firstWhere(
      (t) => t.id == typeId,
      orElse: () => tankTypes.first,
    ).color;
  }

  @override
  Widget buildConfigUI(BuildContext context, SignalKService signalKService) {
    return StatefulBuilder(
      builder: (context, setState) {
        // Ensure tankTypeIds has enough entries
        while (tankTypeIds.length < _dataSourceCount) {
          tankTypeIds.add('diesel');
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tank Types',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Set the type for each data source (determines color)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),

              // Tank type for each data source
              if (_dataSourceCount == 0)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Add data sources above to configure tank types'),
                  ),
                )
              else
                ...List.generate(_dataSourceCount, (index) {
                  final typeId = index < tankTypeIds.length ? tankTypeIds[index] : 'diesel';
                  final typeColor = _getTypeColor(typeId);

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          // Color indicator
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: typeColor,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.black12),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Tank ${index + 1}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const Spacer(),
                          // Tank Type Dropdown
                          SizedBox(
                            width: 150,
                            child: DropdownButtonFormField<String>(
                              initialValue: typeId,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: tankTypes.map((type) {
                                return DropdownMenuItem(
                                  value: type.id,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: type.color,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(type.name, style: const TextStyle(fontSize: 13)),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    while (tankTypeIds.length <= index) {
                                      tankTypeIds.add('diesel');
                                    }
                                    tankTypeIds[index] = value;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),

              // Display Options
              Text(
                'Display Options',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),

              // Tool Label
              SwitchListTile(
                title: const Text('Show Label'),
                subtitle: const Text('Display a title above the tanks'),
                value: showLabel,
                onChanged: (value) {
                  setState(() => showLabel = value);
                },
              ),
              if (showLabel)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextFormField(
                    initialValue: label,
                    decoration: const InputDecoration(
                      labelText: 'Label',
                      hintText: 'e.g., Tank Levels',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      label = value;
                    },
                  ),
                ),
              const SizedBox(height: 8),

              SwitchListTile(
                title: const Text('Show Capacity'),
                subtitle: const Text('Display remaining volume (requires capacity data)'),
                value: showCapacity,
                onChanged: (value) {
                  setState(() => showCapacity = value);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Called when data sources change - update tank types list
  void updateDataSourceCount(int count) {
    _dataSourceCount = count;
    // Trim or extend tankTypeIds to match
    if (tankTypeIds.length > count) {
      tankTypeIds = tankTypeIds.sublist(0, count);
    }
    while (tankTypeIds.length < count) {
      tankTypeIds.add('diesel');
    }
  }
}
