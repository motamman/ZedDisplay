import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/ais_favorite.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/ais_favorites_service.dart';
import '../../../services/historical_data_service.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for chart tools (historical and realtime)
class ChartConfigurator extends ToolConfigurator {
  final String _toolTypeId;

  ChartConfigurator([this._toolTypeId = 'historical_chart']);

  @override
  String get toolTypeId => _toolTypeId;

  bool get isRealtime => _toolTypeId == 'realtime_chart';

  @override
  Size get defaultSize => const Size(4, 3);

  // Chart-specific state variables
  String chartStyle = 'area'; // area, line, column, stepLine
  String chartDuration = '1h';
  int? chartResolution; // null means auto (historical only)
  bool chartShowLegend = true;
  bool chartShowGrid = true;
  bool chartAutoRefresh = false; // historical only
  int chartRefreshInterval = 60; // historical only
  bool chartShowMovingAverage = false;
  String chartSmoothingType = 'sma'; // 'sma' or 'ema'
  int chartMovingAverageWindow = 5; // SMA window or EMA alpha*100
  String chartTitle = '';
  String chartContext = 'vessels.self'; // historical only

  // Vessel context picker state (not persisted in config)
  bool _lookupOtherVessels = false;
  List<String> _availableContexts = ['vessels.self'];
  bool _contextsLoading = false;

  @override
  void reset() {
    chartStyle = 'area';
    chartDuration = isRealtime ? '5m' : '1h';
    chartResolution = null;
    chartShowLegend = true;
    chartShowGrid = true;
    chartAutoRefresh = false;
    chartRefreshInterval = 60;
    chartShowMovingAverage = false;
    chartSmoothingType = 'sma';
    chartMovingAverageWindow = 5;
    chartTitle = '';
    chartContext = 'vessels.self';
    _lookupOtherVessels = false;
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    final style = tool.config.style;
    if (style.customProperties != null) {
      chartStyle = style.customProperties!['chartStyle'] as String? ?? 'area';
      chartDuration = style.customProperties!['duration'] as String? ?? (isRealtime ? '5m' : '1h');
      chartResolution = style.customProperties!['resolution'] as int?;
      chartShowLegend = style.customProperties!['showLegend'] as bool? ?? true;
      chartShowGrid = style.customProperties!['showGrid'] as bool? ?? true;
      chartAutoRefresh = style.customProperties!['autoRefresh'] as bool? ?? false;
      chartRefreshInterval = style.customProperties!['refreshInterval'] as int? ?? 60;
      chartShowMovingAverage = style.customProperties!['showMovingAverage'] as bool? ?? false;
      chartSmoothingType = style.customProperties!['smoothingType'] as String? ?? 'sma';
      chartMovingAverageWindow = style.customProperties!['movingAverageWindow'] as int? ?? 5;
      chartTitle = style.customProperties!['title'] as String? ?? '';
      chartContext = style.customProperties!['context'] as String? ?? 'vessels.self';
      _lookupOtherVessels = chartContext != 'vessels.self';
    }
  }

  /// Convert duration string to maxDataPoints for realtime chart.
  /// For short durations: 2 points/sec (500ms updates)
  /// For longer durations: reduced density to keep points manageable
  int _durationToMaxDataPoints(String duration) {
    switch (duration) {
      case '1m':
        return 120;    // 2/sec × 60s
      case '5m':
        return 300;    // 1/sec × 300s
      case '15m':
        return 450;    // 0.5/sec × 900s
      case '30m':
        return 600;    // 0.33/sec × 1800s
      case '1h':
        return 720;    // 0.2/sec × 3600s
      case '2h':
        return 720;    // 0.1/sec × 7200s
      case '6h':
        return 720;    // ~0.03/sec
      case '12h':
        return 720;    // ~0.017/sec
      default:
        return 300;    // Default 5 minutes
    }
  }

  @override
  ToolConfig getConfig() {
    final customProperties = <String, dynamic>{
      'chartStyle': chartStyle,
      'duration': chartDuration,
      'showLegend': chartShowLegend,
      'showGrid': chartShowGrid,
      'showMovingAverage': chartShowMovingAverage,
      'smoothingType': chartSmoothingType,
      'movingAverageWindow': chartMovingAverageWindow,
      'title': chartTitle,
    };

    if (isRealtime) {
      // Convert duration to maxDataPoints for realtime
      customProperties['maxDataPoints'] = _durationToMaxDataPoints(chartDuration);
    } else {
      // Historical-only properties
      customProperties['resolution'] = chartResolution;
      customProperties['autoRefresh'] = chartAutoRefresh;
      customProperties['refreshInterval'] = chartRefreshInterval;
      if (chartContext != 'vessels.self') {
        customProperties['context'] = chartContext;
      }
    }

    return ToolConfig(
      dataSources: const [], // Will be filled by parent screen
      style: StyleConfig(
        customProperties: customProperties,
      ),
    );
  }

  @override
  String? validate() {
    if (!isRealtime && chartRefreshInterval < 1) {
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

              // Time Duration - different options for realtime vs historical
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: isRealtime ? 'Window Duration' : 'Time Duration',
                  border: const OutlineInputBorder(),
                  helperText: isRealtime ? 'How much time to show in the sliding window' : null,
                ),
                initialValue: chartDuration,
                items: isRealtime
                    ? const [
                        // Realtime: minutes and hours
                        DropdownMenuItem(value: '1m', child: Text('1 minute')),
                        DropdownMenuItem(value: '5m', child: Text('5 minutes')),
                        DropdownMenuItem(value: '15m', child: Text('15 minutes')),
                        DropdownMenuItem(value: '30m', child: Text('30 minutes')),
                        DropdownMenuItem(value: '1h', child: Text('1 hour')),
                        DropdownMenuItem(value: '2h', child: Text('2 hours')),
                        DropdownMenuItem(value: '6h', child: Text('6 hours')),
                        DropdownMenuItem(value: '12h', child: Text('12 hours')),
                      ]
                    : const [
                        // Historical: original options
                        DropdownMenuItem(value: '15m', child: Text('15 minutes')),
                        DropdownMenuItem(value: '30m', child: Text('30 minutes')),
                        DropdownMenuItem(value: '1h', child: Text('1 hour')),
                        DropdownMenuItem(value: '2h', child: Text('2 hours')),
                        DropdownMenuItem(value: '6h', child: Text('6 hours')),
                        DropdownMenuItem(value: '12h', child: Text('12 hours')),
                        DropdownMenuItem(value: '1d', child: Text('1 day')),
                        DropdownMenuItem(value: '2d', child: Text('2 days')),
                        DropdownMenuItem(value: '1w', child: Text('1 week')),
                      ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => chartDuration = value);
                  }
                },
              ),
              const SizedBox(height: 16),

              // Data Resolution - historical only
              if (!isRealtime) ...[
                DropdownButtonFormField<int?>(
                  decoration: const InputDecoration(
                    labelText: 'Data Resolution',
                    border: OutlineInputBorder(),
                    helperText: 'Auto lets the server optimize for the timeframe',
                  ),
                  initialValue: chartResolution,
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Auto (Recommended)')),
                    DropdownMenuItem(value: 30, child: Text('30 seconds')),
                    DropdownMenuItem(value: 60, child: Text('1 minute')),
                    DropdownMenuItem(value: 300, child: Text('5 minutes')),
                    DropdownMenuItem(value: 600, child: Text('10 minutes')),
                  ],
                  onChanged: (value) {
                    setState(() => chartResolution = value);
                  },
                ),
                const SizedBox(height: 16),

                // Vessel Context selector
                _buildVesselContextUI(context, signalKService, setState),
                const SizedBox(height: 16),
              ],

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

              // Auto Refresh - historical only
              if (!isRealtime) ...[
                const Divider(),
                SwitchListTile(
                  title: const Text('Auto Refresh'),
                  subtitle: const Text('Automatically reload data'),
                  value: chartAutoRefresh,
                  onChanged: (value) {
                    setState(() => chartAutoRefresh = value);
                  },
                ),
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
              ],

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

              // Moving Average options (conditional)
              if (chartShowMovingAverage) ...[
                // Smoothing Type selector
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Smoothing Type',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: chartSmoothingType,
                    items: const [
                      DropdownMenuItem(value: 'sma', child: Text('Simple Moving Average (SMA)')),
                      DropdownMenuItem(value: 'ema', child: Text('Exponential Moving Average (EMA)')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          chartSmoothingType = value;
                          // Reset window to appropriate default for type
                          chartMovingAverageWindow = value == 'ema' ? 20 : 5;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
                // Window/Alpha parameter
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<int>(
                    decoration: InputDecoration(
                      labelText: chartSmoothingType == 'ema' ? 'EMA Alpha' : 'SMA Window',
                      border: const OutlineInputBorder(),
                      helperText: chartSmoothingType == 'ema'
                          ? 'Higher = more responsive, lower = smoother'
                          : 'Number of data points to average',
                    ),
                    initialValue: chartMovingAverageWindow,
                    items: chartSmoothingType == 'ema'
                        ? const [
                            // EMA alpha values (stored as int, converted to 0.0-1.0 in tool)
                            DropdownMenuItem(value: 10, child: Text('0.1 (Very smooth)')),
                            DropdownMenuItem(value: 20, child: Text('0.2 (Smooth)')),
                            DropdownMenuItem(value: 30, child: Text('0.3 (Balanced)')),
                            DropdownMenuItem(value: 50, child: Text('0.5 (Responsive)')),
                          ]
                        : const [
                            // SMA window sizes
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
              ],
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

  /// Build the vessel context picker UI (historical only).
  Widget _buildVesselContextUI(
    BuildContext context,
    SignalKService signalKService,
    void Function(void Function()) setState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
            _lookupOtherVessels
                ? 'Vessel: ${_contextDisplayName(chartContext, signalKService)}'
                : 'Look up other vessels',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          value: _lookupOtherVessels,
          onChanged: (v) {
            final checked = v ?? false;
            setState(() => _lookupOtherVessels = checked);
            if (checked) {
              _fetchAvailableContexts(signalKService, setState);
            } else {
              setState(() => chartContext = 'vessels.self');
            }
          },
        ),
        if (_lookupOtherVessels) ...[
          if (_contextsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Loading vessels…', style: TextStyle(fontSize: 12)),
                ],
              ),
            )
          else
            _buildContextList(context, signalKService, setState),
        ],
      ],
    );
  }

  Widget _buildContextList(
    BuildContext context,
    SignalKService signalKService,
    void Function(void Function()) setState,
  ) {
    final favService = context.read<AISFavoritesService>();
    final favs = favService.favorites;
    final favMMSIs = favs.map((f) => f.mmsi).toSet();

    final nonSelf = _availableContexts
        .where((c) => c != 'vessels.self')
        .toList();

    // Sort: favorites first, then the rest
    final favContexts = nonSelf.where((c) {
      final m = _extractMMSI(c);
      return m != null && favMMSIs.contains(m);
    }).toList();
    final otherContexts = nonSelf
        .where((c) => !favContexts.contains(c))
        .toList();
    final allContexts = [...favContexts, ...otherContexts];

    if (allContexts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No other vessels found', style: TextStyle(fontSize: 12)),
      );
    }

    return SizedBox(
      height: 120,
      child: RadioGroup<String>(
        groupValue: chartContext,
        onChanged: (v) {
          if (v != null) setState(() => chartContext = v);
        },
        child: ListView.builder(
          itemCount: allContexts.length,
          itemBuilder: (_, i) {
            final c = allContexts[i];
            return RadioListTile<String>(
              dense: true,
              value: c,
              title: Text(
                _contextDisplayName(c, signalKService, favs),
                style: const TextStyle(fontSize: 12),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _fetchAvailableContexts(
    SignalKService signalKService,
    void Function(void Function()) setState,
  ) async {
    if (_contextsLoading || !signalKService.isConnected) return;
    setState(() => _contextsLoading = true);
    try {
      final service = HistoricalDataService(
        serverUrl: signalKService.serverUrl,
        useSecureConnection: signalKService.useSecureConnection,
        authToken: signalKService.authToken,
      );
      final contexts = await service.getAvailableContexts();
      // Ensure vessels.self is always present
      if (!contexts.contains('vessels.self')) {
        contexts.insert(0, 'vessels.self');
      }
      // Remove own vessel's full URN (duplicates vessels.self)
      final ownContext = signalKService.vesselContext;
      if (ownContext != null) {
        contexts.remove(ownContext);
      }
      _availableContexts = contexts;
    } catch (_) {
      // Silently fail — keep existing list
    } finally {
      setState(() => _contextsLoading = false);
    }
  }

  static String? _extractMMSI(String ctx) {
    return RegExp(r'mmsi:(\d+)').firstMatch(ctx)?.group(1);
  }

  static String _contextDisplayName(
    String ctx,
    SignalKService signalKService, [
    List<AISFavorite>? favorites,
  ]) {
    if (ctx == 'vessels.self') {
      final nameData = signalKService.getValue('name');
      final name = nameData?.value is String ? nameData!.value as String : null;
      return name != null ? 'Self ($name)' : 'Self';
    }
    final mmsi = _extractMMSI(ctx);
    if (mmsi != null) {
      if (favorites != null) {
        final fav = favorites.cast<AISFavorite?>().firstWhere(
            (f) => f!.mmsi == mmsi,
            orElse: () => null);
        if (fav != null) return '${fav.name} ($mmsi)';
      }
      return 'MMSI $mmsi';
    }
    final lastDot = ctx.lastIndexOf('.');
    return lastDot >= 0 ? ctx.substring(lastDot + 1) : ctx;
  }
}
