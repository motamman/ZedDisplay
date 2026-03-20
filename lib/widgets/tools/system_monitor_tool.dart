import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart' as intl;
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/diagnostic_service.dart';
import '../../services/tool_registry.dart';
import '../../main.dart' as main;

/// Data point for memory history chart
class _MemoryDataPoint {
  final DateTime timestamp;
  final int totalMemoryMB;
  final int usedMemoryMB;
  final int appMemoryMB;

  _MemoryDataPoint({
    required this.timestamp,
    required this.totalMemoryMB,
    required this.usedMemoryMB,
    required this.appMemoryMB,
  });
}

/// System monitor tool that tracks app, device, and SignalK connection health
class SystemMonitorTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const SystemMonitorTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<SystemMonitorTool> createState() => _SystemMonitorToolState();
}

class _SystemMonitorToolState extends State<SystemMonitorTool> with AutomaticKeepAliveClientMixin {
  final _battery = Battery();
  final _deviceInfo = DeviceInfoPlugin();

  Timer? _updateTimer;

  // System metrics
  int _batteryLevel = 0;
  BatteryState _batteryState = BatteryState.unknown;
  int _totalMemoryMB = 0;
  int _freeMemoryMB = 0;

  // App metrics
  Duration _appUptime = Duration.zero;
  int _appMemoryMB = 0;
  int _startMemoryMB = 0;
  int _peakMemoryMB = 0;
  String _lastExitStatus = 'Unknown';

  // Memory history tracking
  final List<_MemoryDataPoint> _memoryHistory = [];
  int _chartDurationMinutes = 2;
  int get _maxHistoryPoints => (_chartDurationMinutes * 60) ~/ 5; // Points at 5s intervals

  // SignalK connection tracking
  DateTime? _connectedSince;
  SignalKConnectionState _lastConnectionState = SignalKConnectionState.disconnected;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
    _loadChartDuration();
    _checkLastExit();
    _markAppRunning();
    widget.signalKService.addListener(_onSignalKChanged);
    _trackConnectionState();
    _startMonitoring();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    widget.signalKService.removeListener(_onSignalKChanged);
    _markAppExitedCleanly();
    super.dispose();
  }

  void _onSignalKChanged() {
    _trackConnectionState();
    if (mounted) setState(() {});
  }

  void _trackConnectionState() {
    final state = widget.signalKService.connectionState;
    if (state == SignalKConnectionState.connected && _lastConnectionState != SignalKConnectionState.connected) {
      _connectedSince = DateTime.now();
    } else if (state != SignalKConnectionState.connected) {
      _connectedSince = null;
    }
    _lastConnectionState = state;
  }

  void _startMonitoring() {
    _updateMetrics();
    _updateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        _updateMetrics();
      }
    });
  }

  Future<void> _loadDeviceInfo() async {
    try {
      if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        setState(() {
          _totalMemoryMB = iosInfo.physicalRamSize;
        });
      } else if (Platform.isMacOS) {
        final macInfo = await _deviceInfo.macOsInfo;
        setState(() {
          _totalMemoryMB = (macInfo.memorySize / (1024 * 1024)).round();
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading device info: $e');
      }
    }
  }

  Future<void> _checkLastExit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wasRunning = prefs.getBool('system_monitor_app_running') ?? false;
      if (mounted) {
        setState(() {
          _lastExitStatus = wasRunning ? 'Crashed or Force Killed' : 'Clean Exit';
        });
      }
    } catch (e) {
      if (kDebugMode) print('Error checking last exit: $e');
    }
  }

  Future<void> _loadChartDuration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final duration = prefs.getInt('system_monitor_chart_duration') ?? 2;
      if (mounted) {
        setState(() {
          _chartDurationMinutes = duration;
        });
      }
    } catch (e) {
      if (kDebugMode) print('Error loading chart duration: $e');
    }
  }

  Future<void> _saveChartDuration(int minutes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('system_monitor_chart_duration', minutes);
    } catch (e) {
      if (kDebugMode) print('Error saving chart duration: $e');
    }
  }

  Future<void> _markAppRunning() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('system_monitor_app_running', true);
    } catch (e) {
      if (kDebugMode) print('Error marking app running: $e');
    }
  }

  Future<void> _markAppExitedCleanly() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('system_monitor_app_running', false);
    } catch (e) {
      if (kDebugMode) print('Error marking clean exit: $e');
    }
  }

  int _getAppMemoryMB() {
    if (Platform.isAndroid) {
      try {
        final status = File('/proc/self/status');
        if (!status.existsSync()) return 0;
        final lines = status.readAsLinesSync();
        for (var line in lines) {
          if (line.startsWith('VmRSS:')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 2) {
              return (int.parse(parts[1]) / 1024).round();
            }
          }
        }
      } catch (e) {
        // Ignore errors
      }
      return 0;
    }
    try {
      final rss = ProcessInfo.currentRss;
      if (rss > 0) return (rss / (1024 * 1024)).round();
    } catch (_) {}
    return 0;
  }

  Future<void> _updateMetrics() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      final uptime = DateTime.now().difference(main.appStartTime);

      int freeMem = 0;
      int totalMem = _totalMemoryMB;
      if (Platform.isAndroid) {
        try {
          final memInfo = File('/proc/meminfo');
          if (await memInfo.exists()) {
            final lines = await memInfo.readAsLines();
            for (var line in lines) {
              if (line.startsWith('MemTotal:')) {
                final parts = line.split(RegExp(r'\s+'));
                if (parts.length >= 2) {
                  totalMem = (int.parse(parts[1]) / 1024).round();
                }
              } else if (line.startsWith('MemAvailable:')) {
                final parts = line.split(RegExp(r'\s+'));
                if (parts.length >= 2) {
                  freeMem = (int.parse(parts[1]) / 1024).round();
                }
              }
              if (totalMem > 0 && freeMem > 0) break;
            }
          }
        } catch (e) {
          // Ignore errors reading memory info
        }
      } else if (Platform.isIOS) {
        try {
          final iosInfo = await _deviceInfo.iosInfo;
          freeMem = iosInfo.availableRamSize;
        } catch (e) {
          // Ignore errors
        }
      }

      final appMem = _getAppMemoryMB();

      if (mounted) {
        setState(() {
          _batteryLevel = level;
          _batteryState = state;
          _appUptime = uptime;
          if (totalMem > 0) _totalMemoryMB = totalMem;
          if (freeMem > 0) _freeMemoryMB = freeMem;
          if (appMem > 0) {
            _appMemoryMB = appMem;
            if (_startMemoryMB == 0) _startMemoryMB = appMem;
            if (appMem > _peakMemoryMB) _peakMemoryMB = appMem;
          }

          if (!Platform.isAndroid) {
            try {
              final maxRss = ProcessInfo.maxRss;
              if (maxRss > 0) _peakMemoryMB = (maxRss / (1024 * 1024)).round();
            } catch (_) {}
          }

          if (appMem > 0) {
            _memoryHistory.add(_MemoryDataPoint(
              timestamp: DateTime.now(),
              totalMemoryMB: totalMem,
              usedMemoryMB: freeMem > 0 ? totalMem - freeMem : 0,
              appMemoryMB: appMem,
            ));
            if (_memoryHistory.length > _maxHistoryPoints) {
              _memoryHistory.removeAt(0);
            }
          }
        });
      }
    } catch (e) {
      if (kDebugMode) print('Error updating metrics: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.monitor_heart, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Device Monitor',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 600;
                  final leftColumn = _buildLeftColumn(theme);
                  final rightColumn = _buildRightColumn(theme);

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: ListView(children: leftColumn)),
                        const SizedBox(width: 16),
                        Expanded(child: ListView(children: rightColumn)),
                      ],
                    );
                  } else {
                    return ListView(
                      children: [...leftColumn, ...rightColumn],
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildLeftColumn(ThemeData theme) {
    return [
      _buildConnectionSection(theme),
      const Divider(),
      _buildPipelineSection(theme),
    ];
  }

  List<Widget> _buildRightColumn(ThemeData theme) {
    return [
      _buildBatterySection(theme),
      const Divider(),
      _buildDeviceMemorySection(theme),
      const Divider(),
      _buildAppMemorySection(theme),
      const Divider(),
      if (_memoryHistory.length > 1) ...[
        _buildMemoryChartSection(theme),
        const Divider(),
      ],
      _buildRuntimeSection(theme),
    ];
  }

  // ── SignalK Connection Section ──

  Widget _buildConnectionSection(ThemeData theme) {
    final sk = widget.signalKService;
    final state = sk.connectionState;
    final reconnects = sk.reconnectAttempt;

    Color stateColor;
    String stateLabel;
    switch (state) {
      case SignalKConnectionState.connected:
        stateColor = Colors.green;
        stateLabel = 'Connected';
        break;
      case SignalKConnectionState.reconnecting:
        stateColor = Colors.orange;
        stateLabel = 'Reconnecting';
        break;
      case SignalKConnectionState.disconnected:
        stateColor = Colors.red;
        stateLabel = 'Disconnected';
        break;
    }

    String? uptimeText;
    if (_connectedSince != null) {
      uptimeText = _formatDuration(DateTime.now().difference(_connectedSince!));
    }

    final serverUrl = sk.serverUrl;
    final vessel = sk.vesselContext;

    return _buildSection(
      'SignalK Connection',
      [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Status', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Chip(
                label: Text(stateLabel, style: const TextStyle(fontSize: 12, color: Colors.white)),
                backgroundColor: stateColor,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ],
          ),
        ),
        _buildMetric('Server', serverUrl, maxWidth: 160),
        if (vessel != null) _buildMetric('Vessel', vessel.replaceFirst('vessels.', ''), maxWidth: 160),
        _buildMetric(
          'Reconnects',
          '$reconnects',
          valueColor: reconnects > 0 ? Colors.orange : null,
        ),
        if (uptimeText != null) _buildMetric('Uptime', uptimeText),
      ],
    );
  }

  // ── Data Pipeline Section ──

  Widget _buildPipelineSection(ThemeData theme) {
    final sk = widget.signalKService;
    final diag = DiagnosticService.instance;

    final metrics = <Widget>[
      _buildMetric('Active paths', '${sk.latestData.length}'),
      _buildMetric('Subscribed', '${sk.subscriptionRegistry.allPaths.length}'),
      _buildMetric('AIS vessels', '${sk.aisVesselRegistry.count}'),
      _buildMetric('Available', '${sk.availablePathsCount}'),
      _buildMetric(
        'Notify total',
        '${sk.notifyCount}',
      ),
      _buildMetric(
        'Notify throttled',
        '${sk.notifyThrottledCount}',
      ),
    ];

    if (diag != null) {
      metrics.add(_buildMetric('WS deltas (interval)', '${diag.wsDeltaCount}'));
      metrics.add(_buildMetric('REST GETs', '${diag.restCallCounts['GET'] ?? 0}'));
    }

    return _buildSection('Data Pipeline', metrics);
  }

  // ── Battery Section ──

  Widget _buildBatterySection(ThemeData theme) {
    final color = _getBatteryColor();
    final isCharging = _batteryState == BatteryState.charging;

    return _buildSection(
      'Battery',
      [
        _buildMetricWithProgress(
          isCharging ? 'Level (charging)' : 'Level',
          '$_batteryLevel%',
          _batteryLevel / 100.0,
          color,
          icon: isCharging ? Icons.bolt : null,
        ),
        _buildMetric('Status', _getBatteryStatus()),
      ],
    );
  }

  // ── Device Memory Section ──

  Widget _buildDeviceMemorySection(ThemeData theme) {
    if (_totalMemoryMB <= 0) {
      return _buildSection('Device Memory', [_buildMetric('Info', 'Not available')]);
    }

    final usedMB = _totalMemoryMB - _freeMemoryMB;
    final usageRatio = _freeMemoryMB > 0 ? usedMB / _totalMemoryMB : 0.0;
    final usagePercent = (usageRatio * 100).toStringAsFixed(1);

    Color color;
    if (usageRatio < 0.6) {
      color = Colors.green;
    } else if (usageRatio < 0.8) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }

    return _buildSection(
      'Device Memory',
      [
        if (_freeMemoryMB > 0) ...[
          _buildMetricWithProgress('Usage', '$usagePercent%', usageRatio, color),
          _buildMetric('Used', '$usedMB MB'),
          _buildMetric('Free', '$_freeMemoryMB MB'),
        ] else ...[
          _buildMetric('Total', '$_totalMemoryMB MB'),
        ],
      ],
    );
  }

  // ── App Memory Section ──

  Widget _buildAppMemorySection(ThemeData theme) {
    if (_appMemoryMB <= 0) {
      return _buildSection('App Memory', [_buildMetric('Info', 'Not available')]);
    }

    final growthMB = _appMemoryMB - _startMemoryMB;
    final growthPercent = _startMemoryMB > 0 ? (growthMB / _startMemoryMB * 100) : 0.0;

    Color growthColor;
    if (growthPercent < 20) {
      growthColor = Colors.green;
    } else if (growthPercent <= 100) {
      growthColor = Colors.orange;
    } else {
      growthColor = Colors.red;
    }

    final progressRatio = _peakMemoryMB > 0 ? (_appMemoryMB / _peakMemoryMB).clamp(0.0, 1.0) : 0.0;

    return _buildSection(
      'App Memory',
      [
        _buildMetricWithProgress('Current', '$_appMemoryMB MB', progressRatio, growthColor),
        if (_startMemoryMB > 0) _buildMetric('At Start', '$_startMemoryMB MB'),
        if (_peakMemoryMB > 0) _buildMetric('Peak', '$_peakMemoryMB MB'),
        if (_startMemoryMB > 0)
          _buildMetric(
            'Growth',
            '${growthMB >= 0 ? '+' : ''}$growthMB MB (${growthPercent.toStringAsFixed(0)}%)',
            valueColor: growthColor,
          ),
      ],
    );
  }

  // ── Memory Chart Section ──

  Widget _buildMemoryChartSection(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Memory History',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              DropdownButton<int>(
                value: _chartDurationMinutes,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 min')),
                  DropdownMenuItem(value: 2, child: Text('2 min')),
                  DropdownMenuItem(value: 5, child: Text('5 min')),
                  DropdownMenuItem(value: 10, child: Text('10 min')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _chartDurationMinutes = value;
                      if (_memoryHistory.length > _maxHistoryPoints) {
                        _memoryHistory.removeRange(0, _memoryHistory.length - _maxHistoryPoints);
                      }
                    });
                    _saveChartDuration(value);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: _buildMemoryChart(),
          ),
        ],
      ),
    );
  }

  // ── Runtime Section ──

  Widget _buildRuntimeSection(ThemeData theme) {
    return _buildSection(
      'App Runtime',
      [
        _buildMetric('Uptime', _formatDuration(_appUptime)),
        _buildMetric('Started', _formatTime(main.appStartTime)),
        _buildMetric(
          'Last Exit',
          _lastExitStatus,
          valueColor: _lastExitStatus.contains('Crashed') ? Colors.red : Colors.green,
        ),
      ],
    );
  }

  // ── Shared Builders ──

  Widget _buildSection(String title, List<Widget> metrics) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        ...metrics,
      ],
    );
  }

  Widget _buildMetric(String label, String value, {Color? valueColor, double? maxWidth}) {
    Widget valueWidget = Text(
      value,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: valueColor,
      ),
      overflow: TextOverflow.ellipsis,
    );

    if (maxWidth != null) {
      valueWidget = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: valueWidget,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          valueWidget,
        ],
      ),
    );
  }

  Widget _buildMetricWithProgress(
    String label,
    String value,
    double progress,
    Color color, {
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  if (icon != null) ...[
                    const SizedBox(width: 4),
                    Icon(icon, size: 16, color: color),
                  ],
                ],
              ),
              Text(
                value,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Color _getBatteryColor() {
    if (_batteryLevel < 20) return Colors.red;
    if (_batteryLevel < 50) return Colors.orange;
    return Colors.green;
  }

  String _getBatteryStatus() {
    switch (_batteryState) {
      case BatteryState.charging:
        return 'Charging';
      case BatteryState.full:
        return 'Full';
      case BatteryState.discharging:
        return 'Discharging';
      case BatteryState.unknown:
      default:
        return 'Unknown';
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  Widget _buildMemoryChart() {
    return SfCartesianChart(
      plotAreaBorderWidth: 0,
      primaryXAxis: DateTimeAxis(
        majorGridLines: const MajorGridLines(width: 0),
        axisLine: const AxisLine(width: 0),
        labelStyle: const TextStyle(fontSize: 10),
        intervalType: DateTimeIntervalType.seconds,
        dateFormat: intl.DateFormat('mm:ss'),
      ),
      primaryYAxis: NumericAxis(
        name: 'systemAxis',
        labelFormat: '{value} MB',
        majorGridLines: MajorGridLines(
          width: 1,
          color: Colors.grey.withValues(alpha: 0.2),
        ),
        axisLine: const AxisLine(width: 0),
        labelStyle: const TextStyle(fontSize: 10, color: Colors.orange),
      ),
      axes: const <ChartAxis>[
        NumericAxis(
          name: 'appAxis',
          opposedPosition: true,
          labelFormat: '{value} MB',
          majorGridLines: MajorGridLines(width: 0),
          axisLine: AxisLine(width: 0),
          labelStyle: TextStyle(fontSize: 10, color: Colors.green),
        ),
      ],
      legend: const Legend(
        isVisible: true,
        position: LegendPosition.bottom,
        overflowMode: LegendItemOverflowMode.wrap,
      ),
      tooltipBehavior: TooltipBehavior(
        enable: true,
        format: 'point.seriesName: point.y MB',
      ),
      series: <CartesianSeries>[
        if (_freeMemoryMB > 0)
          AreaSeries<_MemoryDataPoint, DateTime>(
            name: 'System Used',
            dataSource: _memoryHistory,
            xValueMapper: (_MemoryDataPoint data, _) => data.timestamp,
            yValueMapper: (_MemoryDataPoint data, _) => data.usedMemoryMB,
            yAxisName: 'systemAxis',
            color: Colors.orange.withValues(alpha: 0.3),
            borderColor: Colors.orange,
            borderWidth: 2,
          ),
        AreaSeries<_MemoryDataPoint, DateTime>(
          name: 'App RSS',
          dataSource: _memoryHistory,
          xValueMapper: (_MemoryDataPoint data, _) => data.timestamp,
          yValueMapper: (_MemoryDataPoint data, _) => data.appMemoryMB,
          yAxisName: 'appAxis',
          color: Colors.green.withValues(alpha: 0.5),
          borderColor: Colors.green,
          borderWidth: 2,
        ),
      ],
    );
  }
}

/// Builder for system monitor tool
class SystemMonitorBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'system_monitor',
      name: 'Device Monitor',
      description: 'Monitor device performance metrics',
      category: ToolCategory.system,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
        allowsDataSources: false,
        allowsStyleConfig: false,
        styleOptions: const [],
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return SystemMonitorTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
