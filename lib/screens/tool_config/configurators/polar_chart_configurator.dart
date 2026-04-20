import 'package:flutter/material.dart';
import '../../../config/navigation_constants.dart';
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

  /// AIS polar chart maximum range in meters (SI). The dropdown presents
  /// values in nautical miles (navigation standard) but persistence uses
  /// SI so the config survives unit-preference changes.
  double maxRangeMeters = 5.0 * NavigationConstants.metersPerNauticalMile;

  int updateIntervalSeconds = 10; // For ais_polar_chart (stored as seconds in UI, milliseconds in config)
  int pruneMinutes = 15; // For ais_polar_chart - minutes before vessel removed from display
  bool colorByShipType = true; // For ais_polar_chart - color vessels by AIS type
  bool showProjectedPositions = true; // For ais_polar_chart - show projected course lines
  String vesselLookupService = 'vesselfinder'; // For ais_polar_chart - external lookup service

  @override
  void reset() {
    historySeconds = 60;
    maxRangeMeters = 5.0 * NavigationConstants.metersPerNauticalMile;
    updateIntervalSeconds = 10;
    pruneMinutes = 15;
    colorByShipType = true;
    showProjectedPositions = true;
    vesselLookupService = 'vesselfinder';
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
      maxRangeMeters = NavigationConstants.readDistanceMeters(
        style.customProperties,
        siKey: 'maxRangeMeters',
        legacyNmKey: 'maxRangeNm',
        defaultMeters: 5.0 * NavigationConstants.metersPerNauticalMile,
      );
      pruneMinutes = style.customProperties!['pruneMinutes'] as int? ?? 15;
      colorByShipType = style.customProperties!['colorByShipType'] as bool? ?? true;
      showProjectedPositions = style.customProperties!['showProjectedPositions'] as bool? ?? true;
      vesselLookupService = style.customProperties!['vesselLookupService'] as String? ?? 'vesselfinder';

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
      customProps['maxRangeMeters'] = maxRangeMeters;
      // Convert seconds to milliseconds for storage
      customProps['updateInterval'] = updateIntervalSeconds * 1000;
      customProps['pruneMinutes'] = pruneMinutes;
      customProps['colorByShipType'] = colorByShipType;
      customProps['showProjectedPositions'] = showProjectedPositions;
      customProps['vesselLookupService'] = vesselLookupService;
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
      if (maxRangeMeters < 0) {
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

              // AIS Polar Chart - Maximum Range.
              // Dropdown options are keyed in meters (SI) so persistence is
              // immune to later unit-preference changes, but labels stay in
              // nautical miles — the navigation standard for AIS ranges.
              if (_toolTypeId == 'ais_polar_chart') ...[
                Builder(builder: (_) {
                  const nmOptions = [0.0, 1.0, 2.0, 5.0, 10.0, 20.0];
                  final items = nmOptions.map((nm) {
                    final meters = nm * NavigationConstants.metersPerNauticalMile;
                    final label = nm == 0.0
                        ? 'Auto (fit all vessels)'
                        : nm == 1.0
                            ? '1 nautical mile'
                            : '${nm.toStringAsFixed(0)} nautical miles';
                    return DropdownMenuItem(value: meters, child: Text(label));
                  }).toList();
                  return DropdownButtonFormField<double>(
                    decoration: const InputDecoration(
                      labelText: 'Maximum Range',
                      border: OutlineInputBorder(),
                      helperText: 'Display vessels within this range (0 = auto)',
                    ),
                    initialValue: maxRangeMeters,
                    items: items,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => maxRangeMeters = value);
                      }
                    },
                  );
                }),
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
                SwitchListTile(
                  title: const Text('Color by ship type'),
                  subtitle: const Text('Use MarineTraffic-style type colors'),
                  value: colorByShipType,
                  onChanged: (value) {
                    setState(() => colorByShipType = value);
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Show projected positions'),
                  subtitle: const Text('Draw course lines from moving vessels'),
                  value: showProjectedPositions,
                  onChanged: (value) {
                    setState(() => showProjectedPositions = value);
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Vessel Lookup Service',
                    border: OutlineInputBorder(),
                    helperText: 'External service for vessel details',
                  ),
                  initialValue: vesselLookupService,
                  items: const [
                    DropdownMenuItem(value: 'vesselfinder', child: Text('VesselFinder')),
                    DropdownMenuItem(value: 'marinetraffic', child: Text('MarineTraffic')),
                    DropdownMenuItem(value: 'myshiptracking', child: Text('MyShipTracking')),
                    DropdownMenuItem(value: 'none', child: Text('None')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => vesselLookupService = value);
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
