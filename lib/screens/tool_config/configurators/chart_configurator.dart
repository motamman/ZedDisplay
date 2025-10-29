import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for historical chart tool
class ChartConfigurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'historical_chart';

  @override
  Size get defaultSize => const Size(4, 3);

  // Chart-specific state variables (10 total)
  String chartStyle = 'area'; // area, line, column, stepLine
  String chartDuration = '1h';
  int? chartResolution; // null means auto
  bool chartShowLegend = true;
  bool chartShowGrid = true;
  bool chartAutoRefresh = false;
  int chartRefreshInterval = 60;
  bool chartShowMovingAverage = false;
  int chartMovingAverageWindow = 5;
  String chartTitle = '';

  @override
  void reset() {
    chartStyle = 'area';
    chartDuration = '1h';
    chartResolution = null;
    chartShowLegend = true;
    chartShowGrid = true;
    chartAutoRefresh = false;
    chartRefreshInterval = 60;
    chartShowMovingAverage = false;
    chartMovingAverageWindow = 5;
    chartTitle = '';
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    // Use default values (already set in field declarations)
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    final style = tool.config.style;
    if (style.customProperties != null) {
      chartStyle = style.customProperties!['chartStyle'] as String? ?? 'area';
      chartDuration = style.customProperties!['duration'] as String? ?? '1h';
      chartResolution = style.customProperties!['resolution'] as int?;
      chartShowLegend = style.customProperties!['showLegend'] as bool? ?? true;
      chartShowGrid = style.customProperties!['showGrid'] as bool? ?? true;
      chartAutoRefresh = style.customProperties!['autoRefresh'] as bool? ?? false;
      chartRefreshInterval = style.customProperties!['refreshInterval'] as int? ?? 60;
      chartShowMovingAverage = style.customProperties!['showMovingAverage'] as bool? ?? false;
      chartMovingAverageWindow = style.customProperties!['movingAverageWindow'] as int? ?? 5;
      chartTitle = style.customProperties!['title'] as String? ?? '';
    }
  }

  @override
  ToolConfig getConfig() {
    // Note: Common config like dataSources, unit, etc. will be handled by parent screen
    // This only returns chart-specific configuration
    return ToolConfig(
      dataSources: const [], // Will be filled by parent screen
      style: StyleConfig(
        customProperties: {
          'chartStyle': chartStyle,
          'duration': chartDuration,
          'resolution': chartResolution,
          'showLegend': chartShowLegend,
          'showGrid': chartShowGrid,
          'autoRefresh': chartAutoRefresh,
          'refreshInterval': chartRefreshInterval,
          'showMovingAverage': chartShowMovingAverage,
          'movingAverageWindow': chartMovingAverageWindow,
          'title': chartTitle,
        },
      ),
    );
  }

  @override
  String? validate() {
    if (chartRefreshInterval < 1) {
      return 'Refresh interval must be at least 1 second';
    }
    if (chartMovingAverageWindow < 2) {
      return 'Moving average window must be at least 2';
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
                'Chart Configuration',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),

              // Time Duration
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Time Duration',
                  border: OutlineInputBorder(),
                ),
                initialValue: chartDuration,
                items: const [
                  DropdownMenuItem(value: '15m', child: Text('15 minutes')),
                  DropdownMenuItem(value: '30m', child: Text('30 minutes')),
                  DropdownMenuItem(value: '1h', child: Text('1 hour')),
                  DropdownMenuItem(value: '2h', child: Text('2 hours')),
                  DropdownMenuItem(value: '6h', child: Text('6 hours')),
                  DropdownMenuItem(value: '12h', child: Text('12 hours')),
                  DropdownMenuItem(value: '1d', child: Text('1 day')),
                  DropdownMenuItem(value: '2d', child: Text('2 days')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => chartDuration = value);
                  }
                },
              ),
              const SizedBox(height: 16),

              // Data Resolution
              DropdownButtonFormField<int?>(
                decoration: const InputDecoration(
                  labelText: 'Data Resolution',
                  border: OutlineInputBorder(),
                  helperText: 'Auto lets the server optimize for the timeframe',
                ),
                initialValue: chartResolution,
                items: const [
                  DropdownMenuItem(value: null, child: Text('Auto (Recommended)')),
                  DropdownMenuItem(value: 30000, child: Text('30 seconds')),
                  DropdownMenuItem(value: 60000, child: Text('1 minute')),
                  DropdownMenuItem(value: 300000, child: Text('5 minutes')),
                  DropdownMenuItem(value: 600000, child: Text('10 minutes')),
                ],
                onChanged: (value) {
                  setState(() => chartResolution = value);
                },
              ),
              const SizedBox(height: 16),

              // Chart Style
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Chart Style',
                  border: OutlineInputBorder(),
                  helperText: 'Visual style of the chart',
                ),
                initialValue: chartStyle,
                items: const [
                  DropdownMenuItem(value: 'area', child: Text('Area (filled spline)')),
                  DropdownMenuItem(value: 'line', child: Text('Line (spline only)')),
                  DropdownMenuItem(value: 'column', child: Text('Column (vertical bars)')),
                  DropdownMenuItem(value: 'stepLine', child: Text('Step Line (stepped)')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => chartStyle = value);
                  }
                },
              ),
              const SizedBox(height: 16),

              // Show Legend
              SwitchListTile(
                title: const Text('Show Legend'),
                value: chartShowLegend,
                onChanged: (value) {
                  setState(() => chartShowLegend = value);
                },
              ),

              // Show Grid
              SwitchListTile(
                title: const Text('Show Grid'),
                value: chartShowGrid,
                onChanged: (value) {
                  setState(() => chartShowGrid = value);
                },
              ),
              const Divider(),

              // Auto Refresh
              SwitchListTile(
                title: const Text('Auto Refresh'),
                subtitle: const Text('Automatically reload data'),
                value: chartAutoRefresh,
                onChanged: (value) {
                  setState(() => chartAutoRefresh = value);
                },
              ),

              // Refresh Interval (conditional)
              if (chartAutoRefresh)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      labelText: 'Refresh Interval',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: chartRefreshInterval,
                    items: const [
                      DropdownMenuItem(value: 30, child: Text('30 seconds')),
                      DropdownMenuItem(value: 60, child: Text('1 minute')),
                      DropdownMenuItem(value: 120, child: Text('2 minutes')),
                      DropdownMenuItem(value: 300, child: Text('5 minutes')),
                      DropdownMenuItem(value: 600, child: Text('10 minutes')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => chartRefreshInterval = value);
                      }
                    },
                  ),
                ),
              const Divider(),

              // Show Moving Average
              SwitchListTile(
                title: const Text('Show Moving Average'),
                subtitle: const Text('Display smoothed trend line'),
                value: chartShowMovingAverage,
                onChanged: (value) {
                  setState(() => chartShowMovingAverage = value);
                },
              ),

              // Moving Average Window (conditional)
              if (chartShowMovingAverage)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      labelText: 'Moving Average Window',
                      border: OutlineInputBorder(),
                      helperText: 'Number of data points to average',
                    ),
                    initialValue: chartMovingAverageWindow,
                    items: const [
                      DropdownMenuItem(value: 3, child: Text('3 points')),
                      DropdownMenuItem(value: 5, child: Text('5 points')),
                      DropdownMenuItem(value: 10, child: Text('10 points')),
                      DropdownMenuItem(value: 15, child: Text('15 points')),
                      DropdownMenuItem(value: 20, child: Text('20 points')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => chartMovingAverageWindow = value);
                      }
                    },
                  ),
                ),
              const SizedBox(height: 16),

              // Chart Title
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Chart Title',
                  hintText: 'Enter custom chart title (optional)',
                  border: OutlineInputBorder(),
                  helperText: 'Leave empty to auto-generate from data sources',
                ),
                controller: TextEditingController(text: chartTitle),
                onChanged: (value) => chartTitle = value,
              ),
            ],
          ),
        );
      },
    );
  }
}
