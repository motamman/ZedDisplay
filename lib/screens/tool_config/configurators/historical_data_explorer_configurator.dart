import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for Historical Data Explorer tool
class HistoricalDataExplorerConfigurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'historical_data_explorer';

  @override
  Size get defaultSize => const Size(4, 3);

  // State
  double? homeportLat;
  double? homeportLon;
  bool showSeaMap = true;
  String defaultAggregation = 'average';
  String defaultDateRange = '7d';

  @override
  void reset() {
    homeportLat = null;
    homeportLon = null;
    showSeaMap = true;
    defaultAggregation = 'average';
    defaultDateRange = '7d';
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    final props = tool.config.style.customProperties ?? {};
    homeportLat = (props['homeportLat'] as num?)?.toDouble();
    homeportLon = (props['homeportLon'] as num?)?.toDouble();
    showSeaMap = props['showSeaMap'] as bool? ?? true;
    defaultAggregation = props['defaultAggregation'] as String? ?? 'average';
    defaultDateRange = props['defaultDateRange'] as String? ?? '7d';
  }

  @override
  ToolConfig getConfig() {
    return ToolConfig(
      dataSources: const [],
      style: StyleConfig(
        customProperties: {
          if (homeportLat != null) 'homeportLat': homeportLat,
          if (homeportLon != null) 'homeportLon': homeportLon,
          'showSeaMap': showSeaMap,
          'defaultAggregation': defaultAggregation,
          'defaultDateRange': defaultDateRange,
        },
      ),
    );
  }

  @override
  String? validate() {
    if (homeportLat != null && (homeportLat! < -90 || homeportLat! > 90)) {
      return 'Latitude must be between -90 and 90';
    }
    if (homeportLon != null && (homeportLon! < -180 || homeportLon! > 180)) {
      return 'Longitude must be between -180 and 180';
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
                'Historical Data Explorer',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Explore historical data by drawing areas on a map',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),

              // Data source info
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue.shade400),
                          const SizedBox(width: 8),
                          const Text(
                            'Requirements',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Requires signalk-parquet plugin with spatial query support '
                        '(bbox/radius parameters on the History API).',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),

              // Map Options
              Text(
                'Map Options',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),

              SwitchListTile(
                title: const Text('Show Sea Map'),
                subtitle: const Text('OpenSeaMap overlay with nautical charts'),
                value: showSeaMap,
                onChanged: (value) {
                  setState(() => showSeaMap = value);
                },
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),

              // Homeport Position
              Text(
                'Homeport Position',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Optional fixed position for quick map centering',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: homeportLat?.toString() ?? '',
                      decoration: const InputDecoration(
                        labelText: 'Latitude',
                        hintText: '40.646',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (value) {
                        homeportLat = double.tryParse(value);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: homeportLon?.toString() ?? '',
                      decoration: const InputDecoration(
                        labelText: 'Longitude',
                        hintText: '-73.981',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (value) {
                        homeportLon = double.tryParse(value);
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),

              // Query Defaults
              Text(
                'Query Defaults',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                initialValue: defaultAggregation,
                decoration: const InputDecoration(
                  labelText: 'Default Aggregation',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'average', child: Text('Average')),
                  DropdownMenuItem(value: 'min', child: Text('Min')),
                  DropdownMenuItem(value: 'max', child: Text('Max')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => defaultAggregation = value);
                  }
                },
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                initialValue: defaultDateRange,
                decoration: const InputDecoration(
                  labelText: 'Default Date Range',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: '1d', child: Text('Last 24 hours')),
                  DropdownMenuItem(value: '7d', child: Text('Last 7 days')),
                  DropdownMenuItem(value: '30d', child: Text('Last 30 days')),
                  DropdownMenuItem(value: '90d', child: Text('Last 90 days')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => defaultDateRange = value);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
