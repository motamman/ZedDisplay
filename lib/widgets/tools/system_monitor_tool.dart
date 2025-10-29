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
import '../../services/tool_registry.dart';
import '../../main.dart' as main;

/// System monitor tool that tracks app and device performance
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

class _SystemMonitorToolState extends State<SystemMonitorTool> {
  final _battery = Battery();
  final _deviceInfo = DeviceInfoPlugin();

  Timer? _updateTimer;

  // System metrics
  int _batteryLevel = 0;
  BatteryState _batteryState = BatteryState.unknown;
  String _deviceModel = 'Unknown';
  String _osVersion = 'Unknown';
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
  int _chartDurationMinutes = 2; // Default 2 minutes
  int get _maxHistoryPoints => (_chartDurationMinutes * 60) ~/ 2; // Points at 2s intervals

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
    _loadChartDuration();
    _checkLastExit();
    _markAppRunning();
    _startMonitoring();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _markAppExitedCleanly();
    super.dispose();
  }

  void _startMonitoring() {
    _updateMetrics();

    // Update every 2 seconds
    _updateTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        _updateMetrics();
      }
    });
  }

  Future<void> _loadDeviceInfo() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        setState(() {
          _deviceModel = '${androidInfo.manufacturer} ${androidInfo.model}';
          _osVersion = 'Android ${androidInfo.version.release}';
          // Note: totalMemory not available in device_info_plus, will get from /proc/meminfo
        });
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        setState(() {
          _deviceModel = iosInfo.model;
          _osVersion = 'iOS ${iosInfo.systemVersion}';
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

      if (wasRunning) {
        // App didn't exit cleanly last time
        setState(() {
          _lastExitStatus = 'Crashed or Force Killed';
        });
      } else {
        setState(() {
          _lastExitStatus = 'Clean Exit';
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error checking last exit: $e');
      }
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
      if (kDebugMode) {
        print('Error loading chart duration: $e');
      }
    }
  }

  Future<void> _saveChartDuration(int minutes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('system_monitor_chart_duration', minutes);
    } catch (e) {
      if (kDebugMode) {
        print('Error saving chart duration: $e');
      }
    }
  }

  Future<void> _markAppRunning() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('system_monitor_app_running', true);
    } catch (e) {
      if (kDebugMode) {
        print('Error marking app running: $e');
      }
    }
  }

  Future<void> _markAppExitedCleanly() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('system_monitor_app_running', false);
    } catch (e) {
      if (kDebugMode) {
        print('Error marking clean exit: $e');
      }
    }
  }

  int _getAppMemoryMB() {
    if (!Platform.isAndroid) return 0;

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

  Future<void> _updateMetrics() async {
    try {
      // Update battery
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;

      // Update uptime (using actual app start time from main.dart)
      final uptime = DateTime.now().difference(main.appStartTime);

      // On Android, we can get memory info from /proc/meminfo
      int freeMem = 0;
      int totalMem = 0;
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
              // Stop once we have both
              if (totalMem > 0 && freeMem > 0) break;
            }
          }
        } catch (e) {
          // Ignore errors reading memory info
        }
      }

      // Get app memory usage
      final appMem = _getAppMemoryMB();

      if (mounted) {
        setState(() {
          _batteryLevel = level;
          _batteryState = state;
          _appUptime = uptime;
          if (totalMem > 0) {
            _totalMemoryMB = totalMem;
          }
          if (freeMem > 0) {
            _freeMemoryMB = freeMem;
          }
          if (appMem > 0) {
            _appMemoryMB = appMem;
            // Track starting memory
            if (_startMemoryMB == 0) {
              _startMemoryMB = appMem;
            }
            // Track peak memory
            if (appMem > _peakMemoryMB) {
              _peakMemoryMB = appMem;
            }
          }

          // Add to memory history
          if (totalMem > 0 && appMem > 0) {
            _memoryHistory.add(_MemoryDataPoint(
              timestamp: DateTime.now(),
              totalMemoryMB: totalMem,
              usedMemoryMB: totalMem - freeMem,
              appMemoryMB: appMem,
            ));

            // Keep only last N points
            if (_memoryHistory.length > _maxHistoryPoints) {
              _memoryHistory.removeAt(0);
            }
          }
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error updating metrics: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  'System Monitor',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  _buildSection(
                    'Device Info',
                    [
                      _buildMetric('Model', _deviceModel),
                      _buildMetric('OS', _osVersion),
                      if (_totalMemoryMB > 0)
                        _buildMetric('Total Memory', '${_totalMemoryMB} MB'),
                    ],
                  ),
                  const Divider(),
                  _buildSection(
                    'Battery',
                    [
                      _buildMetric(
                        'Level',
                        '$_batteryLevel%',
                        valueColor: _getBatteryColor(),
                      ),
                      _buildMetric('Status', _getBatteryStatus()),
                    ],
                  ),
                  const Divider(),
                  _buildSection(
                    'Memory',
                    [
                      if (_freeMemoryMB > 0 && _totalMemoryMB > 0) ...[
                        _buildMetric('Used', '${_totalMemoryMB - _freeMemoryMB} MB'),
                        _buildMetric('Free', '$_freeMemoryMB MB'),
                        _buildMetric(
                          'Usage',
                          '${(((_totalMemoryMB - _freeMemoryMB) / _totalMemoryMB) * 100).toStringAsFixed(1)}%',
                        ),
                      ] else
                        _buildMetric('Info', 'Not available'),
                    ],
                  ),
                  const Divider(),
                  _buildSection(
                    'App Memory',
                    [
                      if (_appMemoryMB > 0) ...[
                        _buildMetric('Current', '$_appMemoryMB MB'),
                        if (_startMemoryMB > 0)
                          _buildMetric('At Start', '$_startMemoryMB MB'),
                        if (_peakMemoryMB > 0)
                          _buildMetric('Peak', '$_peakMemoryMB MB'),
                        if (_startMemoryMB > 0)
                          _buildMetric(
                            'Growth',
                            '${_appMemoryMB >= _startMemoryMB ? '+' : ''}${_appMemoryMB - _startMemoryMB} MB',
                            valueColor: _appMemoryMB > _startMemoryMB * 2 ? Colors.orange : null,
                          ),
                      ] else
                        _buildMetric('Info', 'Not available'),
                    ],
                  ),
                  const Divider(),
                  // Memory history chart
                  if (_memoryHistory.length > 1)
                    Padding(
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
                                      // Trim history if new duration is shorter
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
                    ),
                  if (_memoryHistory.length > 1)
                    const Divider(),
                  _buildSection(
                    'App Runtime',
                    [
                      _buildMetric('Uptime', _formatDuration(_appUptime)),
                      _buildMetric(
                        'Started',
                        _formatTime(main.appStartTime),
                      ),
                      _buildMetric(
                        'Last Exit',
                        _lastExitStatus,
                        valueColor: _lastExitStatus.contains('Crashed') ? Colors.red : Colors.green,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

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

  Widget _buildMetric(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: valueColor,
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
        labelFormat: '{value} MB',
        majorGridLines: MajorGridLines(
          width: 1,
          color: Colors.grey.withValues(alpha: 0.2),
        ),
        axisLine: const AxisLine(width: 0),
        labelStyle: const TextStyle(fontSize: 10),
      ),
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
        // Total memory (base layer)
        StackedAreaSeries<_MemoryDataPoint, DateTime>(
          name: 'Total',
          dataSource: _memoryHistory,
          xValueMapper: (_MemoryDataPoint data, _) => data.timestamp,
          yValueMapper: (_MemoryDataPoint data, _) => data.totalMemoryMB,
          color: Colors.blue.withValues(alpha: 0.2),
          borderColor: Colors.blue,
          borderWidth: 2,
        ),
        // Used memory (stacked on top)
        StackedAreaSeries<_MemoryDataPoint, DateTime>(
          name: 'Used',
          dataSource: _memoryHistory,
          xValueMapper: (_MemoryDataPoint data, _) => data.timestamp,
          yValueMapper: (_MemoryDataPoint data, _) => data.usedMemoryMB,
          color: Colors.orange.withValues(alpha: 0.3),
          borderColor: Colors.orange,
          borderWidth: 2,
        ),
        // App memory (stacked on top)
        StackedAreaSeries<_MemoryDataPoint, DateTime>(
          name: 'App',
          dataSource: _memoryHistory,
          xValueMapper: (_MemoryDataPoint data, _) => data.timestamp,
          yValueMapper: (_MemoryDataPoint data, _) => data.appMemoryMB,
          color: Colors.green.withValues(alpha: 0.5),
          borderColor: Colors.green,
          borderWidth: 2,
        ),
      ],
    );
  }
}

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

/// Builder for system monitor tool
class SystemMonitorBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'system_monitor',
      name: 'System Monitor',
      description: 'Monitor app and device performance metrics',
      category: ToolCategory.system,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
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
