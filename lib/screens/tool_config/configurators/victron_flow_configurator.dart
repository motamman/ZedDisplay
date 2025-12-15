import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../../../widgets/config/path_selector.dart';
import '../base_tool_configurator.dart';

/// Configurator for Victron Power Flow tool
/// Uses path selector dialogs for each of the 26 paths
class VictronFlowConfigurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'victron_flow';

  @override
  Size get defaultSize => const Size(4, 4);

  final List<String> _paths = List.filled(26, '');

  static const _defaultPaths = [
    'electrical.shore.current',
    'electrical.shore.voltage',
    'electrical.shore.frequency',
    'electrical.shore.power',
    'electrical.solar.current',
    'electrical.solar.voltage',
    'electrical.solar.power',
    'electrical.solar.chargingMode',
    'electrical.alternator.current',
    'electrical.alternator.voltage',
    'electrical.alternator.power',
    'electrical.alternator.state',
    'electrical.inverter.state',
    'electrical.batteries.house.capacity.stateOfCharge',
    'electrical.batteries.house.voltage',
    'electrical.batteries.house.current',
    'electrical.batteries.house.power',
    'electrical.batteries.house.capacity.timeRemaining',
    'electrical.batteries.house.temperature',
    'electrical.ac.load.current',
    'electrical.ac.load.voltage',
    'electrical.ac.load.frequency',
    'electrical.ac.load.power',
    'electrical.dc.load.current',
    'electrical.dc.load.voltage',
    'electrical.dc.load.power',
  ];

  static const _pathLabels = [
    'Shore Current',
    'Shore Voltage',
    'Shore Frequency',
    'Shore Power',
    'Solar Current',
    'Solar Voltage',
    'Solar Power',
    'Solar State',
    'Alternator Current',
    'Alternator Voltage',
    'Alternator Power',
    'Alternator State',
    'Inverter State',
    'Battery SOC',
    'Battery Voltage',
    'Battery Current',
    'Battery Power',
    'Battery Time Remaining',
    'Battery Temperature',
    'AC Loads Current',
    'AC Loads Voltage',
    'AC Loads Frequency',
    'AC Loads Power',
    'DC Loads Current',
    'DC Loads Voltage',
    'DC Loads Power',
  ];

  @override
  void reset() {
    for (int i = 0; i < 26; i++) {
      _paths[i] = _defaultPaths[i];
    }
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    reset();
    final dataSources = tool.config.dataSources;
    for (int i = 0; i < dataSources.length && i < 26; i++) {
      _paths[i] = dataSources[i].path;
    }
  }

  @override
  ToolConfig getConfig() {
    return ToolConfig(
      dataSources: List.generate(26, (i) => DataSource(
        path: _paths[i],
        label: _pathLabels[i],
      )),
      style: StyleConfig(),
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
              _buildSection(context, setState, signalKService, 'Shore Power', Icons.power, 0, 4),
              const SizedBox(height: 16),
              _buildSection(context, setState, signalKService, 'Solar', Icons.wb_sunny_outlined, 4, 4),
              const SizedBox(height: 16),
              _buildSection(context, setState, signalKService, 'Alternator', Icons.settings_input_svideo, 8, 4),
              const SizedBox(height: 16),
              _buildSection(context, setState, signalKService, 'Inverter', Icons.electrical_services, 12, 1),
              const SizedBox(height: 16),
              _buildSection(context, setState, signalKService, 'Battery', Icons.battery_std, 13, 6),
              const SizedBox(height: 16),
              _buildSection(context, setState, signalKService, 'AC Loads', Icons.outlet, 19, 4),
              const SizedBox(height: 16),
              _buildSection(context, setState, signalKService, 'DC Loads', Icons.power, 23, 3),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSection(
    BuildContext context,
    StateSetter setState,
    SignalKService signalKService,
    String title,
    IconData icon,
    int startIndex,
    int count,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        ...List.generate(count, (i) {
          final index = startIndex + i;
          return _buildPathSelector(context, setState, signalKService, index);
        }),
      ],
    );
  }

  Widget _buildPathSelector(BuildContext context, StateSetter setState, SignalKService signalKService, int index) {
    final isDefault = _paths[index] == _defaultPaths[index];

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.grey.shade300),
        ),
        leading: CircleAvatar(
          radius: 14,
          backgroundColor: isDefault ? Colors.grey.shade200 : Colors.blue.shade100,
          child: Text('${index + 1}', style: const TextStyle(fontSize: 11)),
        ),
        title: Text(_pathLabels[index], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        subtitle: Text(
          _paths[index].isEmpty ? 'Tap to select path' : _paths[index],
          style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: _paths[index].isEmpty ? Colors.red : Colors.grey.shade600),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isDefault)
              IconButton(
                icon: const Icon(Icons.restore, size: 18),
                tooltip: 'Reset to default',
                onPressed: () {
                  setState(() => _paths[index] = _defaultPaths[index]);
                },
              ),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
        onTap: () async {
          await showDialog(
            context: context,
            builder: (ctx) => PathSelectorDialog(
              signalKService: signalKService,
              onSelect: (path) {
                setState(() => _paths[index] = path);
              },
            ),
          );
        },
      ),
    );
  }
}
