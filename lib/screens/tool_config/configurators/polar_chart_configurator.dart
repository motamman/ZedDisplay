import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for polar chart tools: polar_radar_chart, ais_polar_chart
class PolarChartConfigurator extends ToolConfigurator {
  final String _toolTypeId;

  PolarChartConfigurator(this._toolTypeId);

  @override
  String get toolTypeId => _toolTypeId;

  @override
  Size get defaultSize => const Size(4, 4);

  // Polar chart-specific state variables
  int historySeconds = 60; // For polar_radar_chart
  double maxRangeNm = 5.0; // For ais_polar_chart
  int updateIntervalSeconds = 10; // For ais_polar_chart (stored as seconds in UI, milliseconds in config)
  int pruneMinutes = 15; // For ais_polar_chart - minutes before vessel removed from display

  @override
  void reset() {
    historySeconds = 60;
    maxRangeNm = 5.0;
    updateIntervalSeconds = 10;
    pruneMinutes = 15;
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    final style = tool.config.style;
    if (style.customProperties != null) {
      historySeconds = style.customProperties!['historySeconds'] as int? ?? 60;
      maxRangeNm = (style.customProperties!['maxRangeNm'] as num?)?.toDouble() ?? 5.0;
      pruneMinutes = style.customProperties!['pruneMinutes'] as int? ?? 15;

      // Convert milliseconds back to seconds for UI
      final updateIntervalMs = style.customProperties!['updateInterval'] as int? ?? 10000;
      updateIntervalSeconds = (updateIntervalMs / 1000).round();
    }
  }

  @override
  ToolConfig getConfig() {
    // Only include relevant properties based on tool type
    final Map<String, dynamic> customProps = {};

    if (_toolTypeId == 'polar_radar_chart') {
      customProps['historySeconds'] = historySeconds;
    } else if (_toolTypeId == 'ais_polar_chart') {
      customProps['maxRangeNm'] = maxRangeNm;
      // Convert seconds to milliseconds for storage
      customProps['updateInterval'] = updateIntervalSeconds * 1000;
      customProps['pruneMinutes'] = pruneMinutes;
    }

    return ToolConfig(
      dataSources: const [],
      style: StyleConfig(
        customProperties: customProps,
      ),
    );
  }

  @override
  String? validate() {
    if (_toolTypeId == 'polar_radar_chart' && historySeconds < 1) {
      return 'History seconds must be at least 1';
    }
    if (_toolTypeId == 'ais_polar_chart') {
      if (maxRangeNm < 0) {
        return 'Max range cannot be negative';
      }
      if (updateIntervalSeconds < 1) {
        return 'Update interval must be at least 1 second';
      }
      if (pruneMinutes < 1) {
        return 'Prune time must be at least 1 minute';
      }
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
              Text(
                '${_getChartTypeName()} Settings',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),

              // Polar Radar Chart - Time Window
              if (_toolTypeId == 'polar_radar_chart') ...[
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Time Window',
                    border: OutlineInputBorder(),
                    helperText: 'How much historical data to show',
                  ),
                  initialValue: historySeconds,
                  items: const [
                    DropdownMenuItem(value: 30, child: Text('30 seconds')),
                    DropdownMenuItem(value: 60, child: Text('1 minute')),
                    DropdownMenuItem(value: 120, child: Text('2 minutes')),
                    DropdownMenuItem(value: 300, child: Text('5 minutes')),
                    DropdownMenuItem(value: 600, child: Text('10 minutes')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => historySeconds = value);
                    }
                  },
                ),
              ],

              // AIS Polar Chart - Maximum Range
              if (_toolTypeId == 'ais_polar_chart') ...[
                DropdownButtonFormField<double>(
                  decoration: const InputDecoration(
                    labelText: 'Maximum Range',
                    border: OutlineInputBorder(),
                    helperText: 'Display vessels within this range (0 = auto)',
                  ),
                  initialValue: maxRangeNm,
                  items: const [
                    DropdownMenuItem(value: 0.0, child: Text('Auto (fit all vessels)')),
                    DropdownMenuItem(value: 1.0, child: Text('1 nautical mile')),
                    DropdownMenuItem(value: 2.0, child: Text('2 nautical miles')),
                    DropdownMenuItem(value: 5.0, child: Text('5 nautical miles')),
                    DropdownMenuItem(value: 10.0, child: Text('10 nautical miles')),
                    DropdownMenuItem(value: 20.0, child: Text('20 nautical miles')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => maxRangeNm = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Update Interval',
                    border: OutlineInputBorder(),
                    helperText: 'How often to refresh vessel data',
                  ),
                  initialValue: updateIntervalSeconds,
                  items: const [
                    DropdownMenuItem(value: 5, child: Text('5 seconds')),
                    DropdownMenuItem(value: 10, child: Text('10 seconds')),
                    DropdownMenuItem(value: 15, child: Text('15 seconds')),
                    DropdownMenuItem(value: 30, child: Text('30 seconds')),
                    DropdownMenuItem(value: 60, child: Text('1 minute')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => updateIntervalSeconds = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Vessel Timeout',
                    border: OutlineInputBorder(),
                    helperText: 'Remove vessels with no data after this time',
                  ),
                  initialValue: pruneMinutes,
                  items: const [
                    DropdownMenuItem(value: 5, child: Text('5 minutes')),
                    DropdownMenuItem(value: 10, child: Text('10 minutes')),
                    DropdownMenuItem(value: 15, child: Text('15 minutes')),
                    DropdownMenuItem(value: 20, child: Text('20 minutes')),
                    DropdownMenuItem(value: 30, child: Text('30 minutes')),
                    DropdownMenuItem(value: 60, child: Text('1 hour')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => pruneMinutes = value);
                    }
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _getChartTypeName() {
    switch (_toolTypeId) {
      case 'polar_radar_chart':
        return 'Polar Chart';
      case 'ais_polar_chart':
        return 'AIS Chart';
      default:
        return 'Polar Chart';
    }
  }
}
