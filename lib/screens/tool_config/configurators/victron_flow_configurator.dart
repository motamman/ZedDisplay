import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../../../widgets/config/path_selector.dart';
import '../base_tool_configurator.dart';

/// Configurator for Power Flow tool with customizable sources and loads
class VictronFlowConfigurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'victron_flow';

  @override
  Size get defaultSize => const Size(4, 4);

  // Sources configuration
  List<Map<String, dynamic>> _sources = [];

  // Loads configuration
  List<Map<String, dynamic>> _loads = [];

  // Battery configuration
  Map<String, String> _battery = {};

  // Inverter state path
  String _inverterStatePath = 'electrical.inverter.state';

  // Primary color for the tool
  String? _primaryColor;

  // Available icons for sources/loads
  static const _availableIcons = [
    'power',
    'wb_sunny_outlined',
    'settings_input_svideo',
    'electrical_services',
    'outlet',
    'bolt',
    'flash_on',
    'local_gas_station',
    'air',
    'lightbulb',
    'kitchen',
    'ac_unit',
    'water_drop',
    'battery_std',
  ];

  static IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'power':
        return Icons.power;
      case 'wb_sunny':
      case 'wb_sunny_outlined':
        return Icons.wb_sunny_outlined;
      case 'settings_input_svideo':
        return Icons.settings_input_svideo;
      case 'electrical_services':
        return Icons.electrical_services;
      case 'outlet':
        return Icons.outlet;
      case 'battery_std':
        return Icons.battery_std;
      case 'local_gas_station':
        return Icons.local_gas_station;
      case 'air':
        return Icons.air;
      case 'bolt':
        return Icons.bolt;
      case 'flash_on':
        return Icons.flash_on;
      case 'lightbulb':
        return Icons.lightbulb;
      case 'kitchen':
        return Icons.kitchen;
      case 'ac_unit':
        return Icons.ac_unit;
      case 'water_drop':
        return Icons.water_drop;
      default:
        return Icons.power;
    }
  }

  @override
  void reset() {
    _sources = [
      {
        'name': 'Shore',
        'icon': 'power',
        'currentPath': 'electrical.shore.current',
        'voltagePath': 'electrical.shore.voltage',
        'powerPath': 'electrical.shore.power',
        'frequencyPath': 'electrical.shore.frequency',
      },
      {
        'name': 'Solar',
        'icon': 'wb_sunny_outlined',
        'currentPath': 'electrical.solar.current',
        'voltagePath': 'electrical.solar.voltage',
        'powerPath': 'electrical.solar.power',
        'statePath': 'electrical.solar.chargingMode',
      },
      {
        'name': 'Alternator',
        'icon': 'settings_input_svideo',
        'currentPath': 'electrical.alternator.current',
        'voltagePath': 'electrical.alternator.voltage',
        'powerPath': 'electrical.alternator.power',
        'statePath': 'electrical.alternator.state',
      },
    ];

    _loads = [
      {
        'name': 'AC Loads',
        'icon': 'outlet',
        'currentPath': 'electrical.ac.load.current',
        'voltagePath': 'electrical.ac.load.voltage',
        'powerPath': 'electrical.ac.load.power',
        'frequencyPath': 'electrical.ac.load.frequency',
      },
      {
        'name': 'DC Loads',
        'icon': 'flash_on',
        'currentPath': 'electrical.dc.load.current',
        'voltagePath': 'electrical.dc.load.voltage',
        'powerPath': 'electrical.dc.load.power',
      },
    ];

    _battery = {
      'socPath': 'electrical.batteries.house.capacity.stateOfCharge',
      'voltagePath': 'electrical.batteries.house.voltage',
      'currentPath': 'electrical.batteries.house.current',
      'powerPath': 'electrical.batteries.house.power',
      'timeRemainingPath': 'electrical.batteries.house.capacity.timeRemaining',
      'temperaturePath': 'electrical.batteries.house.temperature',
    };

    _inverterStatePath = 'electrical.inverter.state';
    _primaryColor = null;
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    reset();
    final customProps = tool.config.style.customProperties ?? {};

    // Load sources
    final sourcesData = customProps['sources'] as List<dynamic>?;
    if (sourcesData != null && sourcesData.isNotEmpty) {
      _sources = sourcesData.map((s) => Map<String, dynamic>.from(s as Map)).toList();
    }

    // Load loads
    final loadsData = customProps['loads'] as List<dynamic>?;
    if (loadsData != null && loadsData.isNotEmpty) {
      _loads = loadsData.map((l) => Map<String, dynamic>.from(l as Map)).toList();
    }

    // Load battery config
    final batteryData = customProps['battery'] as Map<String, dynamic>?;
    if (batteryData != null) {
      _battery = batteryData.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    }

    // Load inverter path
    _inverterStatePath = customProps['inverterStatePath'] as String? ?? 'electrical.inverter.state';

    // Load primary color
    _primaryColor = tool.config.style.primaryColor;
  }

  @override
  ToolConfig getConfig() {
    return ToolConfig(
      dataSources: [], // No longer using dataSources
      style: StyleConfig(
        primaryColor: _primaryColor,
        customProperties: {
          'sources': _sources,
          'loads': _loads,
          'battery': _battery,
          'inverterStatePath': _inverterStatePath,
        },
      ),
    );
  }

  @override
  String? validate() {
    if (_sources.isEmpty) {
      return 'At least one power source is required';
    }
    if (_loads.isEmpty) {
      return 'At least one load is required';
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
              // Color Section
              _buildSectionHeader(context, 'Appearance', Icons.palette, Colors.purple),
              const SizedBox(height: 8),
              _buildColorPicker(context, setState),
              const SizedBox(height: 24),

              // Power Sources Section
              _buildSectionHeader(context, 'Power Sources', Icons.bolt, Colors.orange),
              const SizedBox(height: 8),
              _buildSourcesList(context, setState, signalKService),
              _buildAddButton(context, 'Add Source', () {
                final newSource = {
                  'name': 'New Source',
                  'icon': 'power',
                  'currentPath': '',
                  'voltagePath': '',
                  'powerPath': '',
                };
                setState(() {
                  _sources.add(newSource);
                });
                // Immediately open name editor for the new source
                _showNameEditor(context, setState, 'New Source', (newName) {
                  setState(() => newSource['name'] = newName);
                });
              }),

              const SizedBox(height: 24),

              // Loads Section
              _buildSectionHeader(context, 'Power Loads', Icons.electrical_services, Colors.blue),
              const SizedBox(height: 8),
              _buildLoadsList(context, setState, signalKService),
              _buildAddButton(context, 'Add Load', () {
                final newLoad = {
                  'name': 'New Load',
                  'icon': 'flash_on',
                  'currentPath': '',
                  'voltagePath': '',
                  'powerPath': '',
                };
                setState(() {
                  _loads.add(newLoad);
                });
                // Immediately open name editor for the new load
                _showNameEditor(context, setState, 'New Load', (newName) {
                  setState(() => newLoad['name'] = newName);
                });
              }),

              const SizedBox(height: 24),

              // Inverter Section
              _buildSectionHeader(context, 'Inverter / Charger', Icons.electrical_services, Colors.purple),
              const SizedBox(height: 8),
              _buildPathTile(context, setState, signalKService, 'State Path', _inverterStatePath, (path) {
                setState(() => _inverterStatePath = path);
              }),

              const SizedBox(height: 24),

              // Battery Section
              _buildSectionHeader(context, 'Battery', Icons.battery_std, Colors.green),
              const SizedBox(height: 8),
              _buildBatteryConfig(context, setState, signalKService),
            ],
          ),
        );
      },
    );
  }

  Color _getColor() {
    if (_primaryColor != null && _primaryColor!.isNotEmpty) {
      try {
        final hexColor = _primaryColor!.replaceAll('#', '');
        return Color(int.parse('FF$hexColor', radix: 16));
      } catch (e) {
        // Invalid color, use default
      }
    }
    return Colors.blue;
  }

  Widget _buildColorPicker(BuildContext context, StateSetter setState) {
    final currentColor = _getColor();

    return Card(
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: currentColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade400, width: 2),
          ),
        ),
        title: const Text('Base Color'),
        subtitle: Text(_primaryColor ?? 'Default (Blue)'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_primaryColor != null)
              IconButton(
                icon: const Icon(Icons.restore, size: 20),
                tooltip: 'Reset to default',
                onPressed: () => setState(() => _primaryColor = null),
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => _showColorPicker(context, setState),
      ),
    );
  }

  void _showColorPicker(BuildContext context, StateSetter setState) {
    Color pickedColor = _getColor();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pick a color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickedColor,
            onColorChanged: (color) {
              pickedColor = color;
            },
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                _primaryColor = '#${pickedColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
              });
              Navigator.pop(ctx);
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildAddButton(BuildContext context, String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
    );
  }

  Widget _buildSourcesList(BuildContext context, StateSetter setState, SignalKService signalKService) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _sources.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex--;
          final item = _sources.removeAt(oldIndex);
          _sources.insert(newIndex, item);
        });
      },
      itemBuilder: (context, index) {
        return _buildSourceCard(context, setState, signalKService, index);
      },
    );
  }

  Widget _buildSourceCard(BuildContext context, StateSetter setState, SignalKService signalKService, int index) {
    final source = _sources[index];
    final name = source['name'] as String? ?? 'Source';
    final icon = source['icon'] as String? ?? 'power';

    return Card(
      key: ValueKey('source_$index'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle, color: Colors.grey),
            ),
            const SizedBox(width: 8),
            _buildIconButton(context, setState, icon, (newIcon) {
              setState(() => source['icon'] = newIcon);
            }),
          ],
        ),
        title: _buildEditableName(context, setState, name, (newName) {
          setState(() => source['name'] = newName);
        }),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              onPressed: _sources.length > 1 ? () {
                setState(() => _sources.removeAt(index));
              } : null,
              tooltip: 'Remove source',
            ),
            const Icon(Icons.expand_more),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                _buildPathTile(context, setState, signalKService, 'Current', source['currentPath'] ?? '', (path) {
                  setState(() => source['currentPath'] = path);
                }),
                _buildPathTile(context, setState, signalKService, 'Voltage', source['voltagePath'] ?? '', (path) {
                  setState(() => source['voltagePath'] = path);
                }),
                _buildPathTile(context, setState, signalKService, 'Power', source['powerPath'] ?? '', (path) {
                  setState(() => source['powerPath'] = path);
                }),
                _buildPathTile(context, setState, signalKService, 'Frequency (opt)', source['frequencyPath'] ?? '', (path) {
                  setState(() => source['frequencyPath'] = path);
                }),
                _buildPathTile(context, setState, signalKService, 'State (opt)', source['statePath'] ?? '', (path) {
                  setState(() => source['statePath'] = path);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadsList(BuildContext context, StateSetter setState, SignalKService signalKService) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _loads.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex--;
          final item = _loads.removeAt(oldIndex);
          _loads.insert(newIndex, item);
        });
      },
      itemBuilder: (context, index) {
        return _buildLoadCard(context, setState, signalKService, index);
      },
    );
  }

  Widget _buildLoadCard(BuildContext context, StateSetter setState, SignalKService signalKService, int index) {
    final load = _loads[index];
    final name = load['name'] as String? ?? 'Load';
    final icon = load['icon'] as String? ?? 'power';

    return Card(
      key: ValueKey('load_$index'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle, color: Colors.grey),
            ),
            const SizedBox(width: 8),
            _buildIconButton(context, setState, icon, (newIcon) {
              setState(() => load['icon'] = newIcon);
            }),
          ],
        ),
        title: _buildEditableName(context, setState, name, (newName) {
          setState(() => load['name'] = newName);
        }),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              onPressed: _loads.length > 1 ? () {
                setState(() => _loads.removeAt(index));
              } : null,
              tooltip: 'Remove load',
            ),
            const Icon(Icons.expand_more),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                _buildPathTile(context, setState, signalKService, 'Current', load['currentPath'] ?? '', (path) {
                  setState(() => load['currentPath'] = path);
                }),
                _buildPathTile(context, setState, signalKService, 'Voltage', load['voltagePath'] ?? '', (path) {
                  setState(() => load['voltagePath'] = path);
                }),
                _buildPathTile(context, setState, signalKService, 'Power', load['powerPath'] ?? '', (path) {
                  setState(() => load['powerPath'] = path);
                }),
                _buildPathTile(context, setState, signalKService, 'Frequency (opt)', load['frequencyPath'] ?? '', (path) {
                  setState(() => load['frequencyPath'] = path);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryConfig(BuildContext context, StateSetter setState, SignalKService signalKService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildPathTile(context, setState, signalKService, 'State of Charge', _battery['socPath'] ?? '', (path) {
              setState(() => _battery['socPath'] = path);
            }),
            _buildPathTile(context, setState, signalKService, 'Voltage', _battery['voltagePath'] ?? '', (path) {
              setState(() => _battery['voltagePath'] = path);
            }),
            _buildPathTile(context, setState, signalKService, 'Current', _battery['currentPath'] ?? '', (path) {
              setState(() => _battery['currentPath'] = path);
            }),
            _buildPathTile(context, setState, signalKService, 'Power', _battery['powerPath'] ?? '', (path) {
              setState(() => _battery['powerPath'] = path);
            }),
            _buildPathTile(context, setState, signalKService, 'Time Remaining', _battery['timeRemainingPath'] ?? '', (path) {
              setState(() => _battery['timeRemainingPath'] = path);
            }),
            _buildPathTile(context, setState, signalKService, 'Temperature', _battery['temperaturePath'] ?? '', (path) {
              setState(() => _battery['temperaturePath'] = path);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildPathTile(BuildContext context, StateSetter setState, SignalKService signalKService, String label, String currentPath, ValueChanged<String> onChanged) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        currentPath.isEmpty ? 'Not configured' : currentPath,
        style: TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          color: currentPath.isEmpty ? Colors.grey : Colors.blue.shade700,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (currentPath.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () => onChanged(''),
              tooltip: 'Clear',
            ),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
      onTap: () async {
        await showDialog(
          context: context,
          builder: (ctx) => PathSelectorDialog(
            signalKService: signalKService,
            onSelect: onChanged,
          ),
        );
      },
    );
  }

  Widget _buildIconButton(BuildContext context, StateSetter setState, String currentIcon, ValueChanged<String> onChanged) {
    return InkWell(
      onTap: () => _showIconPicker(context, setState, currentIcon, onChanged),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(_getIconData(currentIcon), size: 20),
      ),
    );
  }

  void _showIconPicker(BuildContext context, StateSetter setState, String currentIcon, ValueChanged<String> onChanged) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Icon'),
        content: SizedBox(
          width: 280,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _availableIcons.length,
            itemBuilder: (context, index) {
              final iconName = _availableIcons[index];
              final isSelected = iconName == currentIcon;
              return InkWell(
                onTap: () {
                  onChanged(iconName);
                  Navigator.pop(ctx);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                        : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: isSelected
                        ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
                        : null,
                  ),
                  child: Icon(
                    _getIconData(iconName),
                    color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade700,
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableName(BuildContext context, StateSetter setState, String currentName, ValueChanged<String> onChanged) {
    return InkWell(
      onTap: () => _showNameEditor(context, setState, currentName, onChanged),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              currentName,
              style: const TextStyle(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.edit, size: 14, color: Colors.grey),
        ],
      ),
    );
  }

  void _showNameEditor(BuildContext context, StateSetter setState, String currentName, ValueChanged<String> onChanged) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              onChanged(value);
            }
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                onChanged(controller.text);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
