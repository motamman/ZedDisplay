import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../models/tool_config.dart';
import '../../models/tool_definition.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';

/// Configuration for a power source (e.g., Shore, Solar, Alternator, Generator)
class PowerSourceConfig {
  final String name;
  final String icon;
  final String? currentPath;
  final String? voltagePath;
  final String? powerPath;
  final String? frequencyPath;
  final String? statePath;

  const PowerSourceConfig({
    required this.name,
    required this.icon,
    this.currentPath,
    this.voltagePath,
    this.powerPath,
    this.frequencyPath,
    this.statePath,
  });

  factory PowerSourceConfig.fromMap(Map<String, dynamic> map) {
    return PowerSourceConfig(
      name: map['name'] as String? ?? 'Source',
      icon: map['icon'] as String? ?? 'power',
      currentPath: map['currentPath'] as String?,
      voltagePath: map['voltagePath'] as String?,
      powerPath: map['powerPath'] as String?,
      frequencyPath: map['frequencyPath'] as String?,
      statePath: map['statePath'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'icon': icon,
    if (currentPath != null) 'currentPath': currentPath,
    if (voltagePath != null) 'voltagePath': voltagePath,
    if (powerPath != null) 'powerPath': powerPath,
    if (frequencyPath != null) 'frequencyPath': frequencyPath,
    if (statePath != null) 'statePath': statePath,
  };

  /// Get the primary value for flow animation (current or power)
  double getPrimaryValue(SignalKService service) {
    // Prefer current, fall back to power
    if (currentPath != null) {
      final data = service.getValue(currentPath!);
      if (data?.value is num) return (data!.value as num).toDouble().abs();
    }
    if (powerPath != null) {
      final data = service.getValue(powerPath!);
      if (data?.value is num) return (data!.value as num).toDouble().abs() / 100;
    }
    return 0;
  }

  bool get hasAnyPath => currentPath != null || voltagePath != null || powerPath != null;
}

/// Configuration for a power load (e.g., AC Loads, DC Loads, specific circuits)
class PowerLoadConfig {
  final String name;
  final String icon;
  final String? currentPath;
  final String? voltagePath;
  final String? powerPath;
  final String? frequencyPath;

  const PowerLoadConfig({
    required this.name,
    required this.icon,
    this.currentPath,
    this.voltagePath,
    this.powerPath,
    this.frequencyPath,
  });

  factory PowerLoadConfig.fromMap(Map<String, dynamic> map) {
    return PowerLoadConfig(
      name: map['name'] as String? ?? 'Load',
      icon: map['icon'] as String? ?? 'power',
      currentPath: map['currentPath'] as String?,
      voltagePath: map['voltagePath'] as String?,
      powerPath: map['powerPath'] as String?,
      frequencyPath: map['frequencyPath'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'icon': icon,
    if (currentPath != null) 'currentPath': currentPath,
    if (voltagePath != null) 'voltagePath': voltagePath,
    if (powerPath != null) 'powerPath': powerPath,
    if (frequencyPath != null) 'frequencyPath': frequencyPath,
  };

  double getPrimaryValue(SignalKService service) {
    if (currentPath != null) {
      final data = service.getValue(currentPath!);
      if (data?.value is num) return (data!.value as num).toDouble().abs();
    }
    if (powerPath != null) {
      final data = service.getValue(powerPath!);
      if (data?.value is num) return (data!.value as num).toDouble().abs() / 100;
    }
    return 0;
  }

  bool get hasAnyPath => currentPath != null || voltagePath != null || powerPath != null;
}

/// Battery configuration paths
class BatteryConfig {
  final String? socPath;
  final String? voltagePath;
  final String? currentPath;
  final String? powerPath;
  final String? timeRemainingPath;
  final String? temperaturePath;

  const BatteryConfig({
    this.socPath,
    this.voltagePath,
    this.currentPath,
    this.powerPath,
    this.timeRemainingPath,
    this.temperaturePath,
  });

  factory BatteryConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const BatteryConfig();
    return BatteryConfig(
      socPath: map['socPath'] as String?,
      voltagePath: map['voltagePath'] as String?,
      currentPath: map['currentPath'] as String?,
      powerPath: map['powerPath'] as String?,
      timeRemainingPath: map['timeRemainingPath'] as String?,
      temperaturePath: map['temperaturePath'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    if (socPath != null) 'socPath': socPath,
    if (voltagePath != null) 'voltagePath': voltagePath,
    if (currentPath != null) 'currentPath': currentPath,
    if (powerPath != null) 'powerPath': powerPath,
    if (timeRemainingPath != null) 'timeRemainingPath': timeRemainingPath,
    if (temperaturePath != null) 'temperaturePath': temperaturePath,
  };
}

/// Victron Power Flow Tool - Visual power flow diagram with animated flow lines
class VictronFlowTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const VictronFlowTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<VictronFlowTool> createState() => _VictronFlowToolState();
}

class _VictronFlowToolState extends State<VictronFlowTool> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late List<PowerSourceConfig> _sources;
  late List<PowerLoadConfig> _loads;
  late BatteryConfig _batteryConfig;
  late String? _inverterStatePath;
  late Color _primaryColor;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
    widget.signalKService.addListener(_onDataUpdate);
    _parseConfig();
  }

  @override
  void didUpdateWidget(VictronFlowTool oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      _parseConfig();
    }
  }

  void _parseConfig() {
    final customProps = widget.config.style.customProperties ?? {};

    // Parse sources
    final sourcesData = customProps['sources'] as List<dynamic>?;
    if (sourcesData != null && sourcesData.isNotEmpty) {
      _sources = sourcesData
          .whereType<Map<String, dynamic>>()
          .map((m) => PowerSourceConfig.fromMap(m))
          .toList();
    } else {
      _sources = _getDefaultSources();
    }

    // Parse loads
    final loadsData = customProps['loads'] as List<dynamic>?;
    if (loadsData != null && loadsData.isNotEmpty) {
      _loads = loadsData
          .whereType<Map<String, dynamic>>()
          .map((m) => PowerLoadConfig.fromMap(m))
          .toList();
    } else {
      _loads = _getDefaultLoads();
    }

    // Parse battery config
    _batteryConfig = BatteryConfig.fromMap(customProps['battery'] as Map<String, dynamic>?);
    if (_batteryConfig.socPath == null) {
      _batteryConfig = _getDefaultBatteryConfig();
    }

    // Parse inverter state path
    _inverterStatePath = customProps['inverterStatePath'] as String? ??
        'electrical.inverter.state';

    // Parse primary color
    _primaryColor = _parseColor(widget.config.style.primaryColor);
  }

  Color _parseColor(String? colorStr) {
    if (colorStr != null && colorStr.isNotEmpty) {
      try {
        final hexColor = colorStr.replaceAll('#', '');
        return Color(int.parse('FF$hexColor', radix: 16));
      } catch (_) {}
    }
    return Colors.blue;
  }

  List<PowerSourceConfig> _getDefaultSources() => [
    const PowerSourceConfig(
      name: 'Shore',
      icon: 'power',
      currentPath: 'electrical.shore.current',
      voltagePath: 'electrical.shore.voltage',
      powerPath: 'electrical.shore.power',
      frequencyPath: 'electrical.shore.frequency',
    ),
    const PowerSourceConfig(
      name: 'Solar',
      icon: 'wb_sunny_outlined',
      currentPath: 'electrical.solar.current',
      voltagePath: 'electrical.solar.voltage',
      powerPath: 'electrical.solar.power',
      statePath: 'electrical.solar.chargingMode',
    ),
    const PowerSourceConfig(
      name: 'Alternator',
      icon: 'settings_input_svideo',
      currentPath: 'electrical.alternator.current',
      voltagePath: 'electrical.alternator.voltage',
      powerPath: 'electrical.alternator.power',
      statePath: 'electrical.alternator.state',
    ),
  ];

  List<PowerLoadConfig> _getDefaultLoads() => [
    const PowerLoadConfig(
      name: 'AC Loads',
      icon: 'outlet',
      currentPath: 'electrical.ac.load.current',
      voltagePath: 'electrical.ac.load.voltage',
      powerPath: 'electrical.ac.load.power',
      frequencyPath: 'electrical.ac.load.frequency',
    ),
    const PowerLoadConfig(
      name: 'DC Loads',
      icon: 'flash_on',
      currentPath: 'electrical.dc.load.current',
      voltagePath: 'electrical.dc.load.voltage',
      powerPath: 'electrical.dc.load.power',
    ),
  ];

  BatteryConfig _getDefaultBatteryConfig() => const BatteryConfig(
    socPath: 'electrical.batteries.house.capacity.stateOfCharge',
    voltagePath: 'electrical.batteries.house.voltage',
    currentPath: 'electrical.batteries.house.current',
    powerPath: 'electrical.batteries.house.power',
    timeRemainingPath: 'electrical.batteries.house.capacity.timeRemaining',
    temperaturePath: 'electrical.batteries.house.temperature',
  );

  @override
  void dispose() {
    _animController.dispose();
    widget.signalKService.removeListener(_onDataUpdate);
    super.dispose();
  }

  void _onDataUpdate() {
    if (mounted) setState(() {});
  }

  double? _getPathValue(String? path) {
    if (path == null || path.isEmpty) return null;
    final data = widget.signalKService.getValue(path);
    if (data?.value is num) {
      return (data!.value as num).toDouble();
    }
    return null;
  }

  String? _getPathStringValue(String? path) {
    if (path == null || path.isEmpty) return null;
    final data = widget.signalKService.getValue(path);
    if (data?.value != null) {
      return data!.value.toString();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Get battery current for flow direction
    final batteryCurrent = _getPathValue(_batteryConfig.currentPath) ?? 0;

    // Build flow data for painter
    final sourceFlows = _sources.map((s) => s.getPrimaryValue(widget.signalKService)).toList();
    final loadFlows = _loads.map((l) => l.getPrimaryValue(widget.signalKService)).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedBuilder(
          animation: _animController,
          builder: (context, child) {
            return CustomPaint(
              painter: _FlowLinesPainter(
                animValue: _animController.value,
                sourceCount: _sources.length,
                loadCount: _loads.length,
                sourceFlows: sourceFlows,
                loadFlows: loadFlows,
                batteryCharging: batteryCurrent > 0,
                batteryDischarging: batteryCurrent < 0,
                batteryCurrent: batteryCurrent.abs(),
                primaryColor: _primaryColor,
              ),
              child: child,
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _buildFlowDiagram(constraints),
          ),
        );
      },
    );
  }

  Widget _buildFlowDiagram(BoxConstraints constraints) {
    // Calculate proportional spacing based on number of cards
    final availableHeight = constraints.maxHeight;
    final sourceCount = _sources.length;
    final loadCount = _loads.length;

    // Base spacing calculation: more cards = less spacing
    // Allocate ~15% of height to gaps, distributed among gaps
    final sourceGapCount = sourceCount > 1 ? sourceCount - 1 : 0;
    final loadGapCount = loadCount > 1 ? loadCount - 1 : 0;

    final sourceSpacing = sourceGapCount > 0
        ? (availableHeight * 0.15 / sourceGapCount).clamp(12.0, 40.0)
        : 0.0;
    final loadSpacing = loadGapCount > 0
        ? (availableHeight * 0.15 / loadGapCount).clamp(12.0, 40.0)
        : 0.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left column - Power sources
        Expanded(
          flex: 3,
          child: Column(
            children: [
              for (int i = 0; i < _sources.length; i++) ...[
                if (i > 0) SizedBox(height: sourceSpacing),
                Expanded(child: _buildSourceBox(_sources[i])),
              ],
            ],
          ),
        ),
        const SizedBox(width: 70),
        // Center column - Inverter & Battery
        Expanded(
          flex: 4,
          child: Column(
            children: [
              Expanded(flex: 2, child: _buildInverterBox()),
              const SizedBox(height: 28),
              Expanded(flex: 3, child: _buildBatteryBox()),
            ],
          ),
        ),
        const SizedBox(width: 70),
        // Right column - Loads
        Expanded(
          flex: 3,
          child: Column(
            children: [
              for (int i = 0; i < _loads.length; i++) ...[
                if (i > 0) SizedBox(height: loadSpacing),
                Expanded(child: _buildLoadBox(_loads[i])),
              ],
              if (_loads.length < 3) const Spacer(),
            ],
          ),
        ),
      ],
    );
  }

  IconData _getIconData(String iconName) {
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

  Widget _buildComponentBox({
    required String title,
    required IconData icon,
    required Widget content,
    Color? borderColor,
    Color? backgroundColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Create shade variants from primary color
    final baseColor = _primaryColor;
    final defaultBg = isDark
        ? HSLColor.fromColor(baseColor).withLightness(0.2).withSaturation(0.4).toColor()
        : HSLColor.fromColor(baseColor).withLightness(0.95).toColor();
    final defaultBorder = HSLColor.fromColor(baseColor).withLightness(0.6).toColor();

    final bgColor = backgroundColor ?? defaultBg;
    final border = borderColor ?? defaultBorder;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 2),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _buildSourceBox(PowerSourceConfig source) {
    final current = _getPathValue(source.currentPath);
    final voltage = _getPathValue(source.voltagePath);
    final power = _getPathValue(source.powerPath);
    final frequency = _getPathValue(source.frequencyPath);
    final state = _getPathStringValue(source.statePath);

    return _buildComponentBox(
      title: source.name,
      icon: _getIconData(source.icon),
      content: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 150;

          if (isWide) {
            // Horizontal layout for wide cards
            return Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      current != null ? '${current.toStringAsFixed(1)}A' : '--A',
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (state != null)
                          Text(_formatState(state), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        Text(
                          _buildSecondaryLine(voltage, frequency, power),
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          // Vertical layout for narrow cards
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current != null ? '${current.toStringAsFixed(1)}A' : '--A',
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                ),
                if (state != null)
                  Text(_formatState(state), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                Text(
                  _buildSecondaryLine(voltage, frequency, power),
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadBox(PowerLoadConfig load) {
    final current = _getPathValue(load.currentPath);
    final voltage = _getPathValue(load.voltagePath);
    final power = _getPathValue(load.powerPath);
    final frequency = _getPathValue(load.frequencyPath);

    return _buildComponentBox(
      title: load.name,
      icon: _getIconData(load.icon),
      content: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 150;

          if (isWide) {
            // Horizontal layout for wide cards
            return Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      current != null ? '${current.toStringAsFixed(1)}A' : '--A',
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      _buildSecondaryLine(voltage, frequency, power),
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ),
              ],
            );
          }

          // Vertical layout for narrow cards
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current != null ? '${current.toStringAsFixed(1)}A' : '--A',
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                ),
                Text(
                  _buildSecondaryLine(voltage, frequency, power),
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _buildSecondaryLine(double? voltage, double? frequency, double? power) {
    final parts = <String>[];
    if (voltage != null) {
      parts.add(voltage > 50 ? '${voltage.toStringAsFixed(0)}V' : '${voltage.toStringAsFixed(2)}V');
    }
    if (frequency != null) parts.add('${frequency.toStringAsFixed(0)}Hz');
    if (power != null) {
      parts.add(power > 100 ? '${power.toStringAsFixed(0)}W' : '${power.toStringAsFixed(2)}W');
    }
    return parts.isEmpty ? '--' : parts.join('  ');
  }

  Widget _buildInverterBox() {
    final state = _getPathStringValue(_inverterStatePath);
    final borderColor = HSLColor.fromColor(_primaryColor).withLightness(0.7).toColor();

    return _buildComponentBox(
      title: 'Inverter / Charger',
      icon: Icons.electrical_services,
      borderColor: borderColor,
      content: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _formatState(state ?? 'Off'),
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildBatteryBox() {
    final soc = _getPathValue(_batteryConfig.socPath);
    final voltage = _getPathValue(_batteryConfig.voltagePath);
    final current = _getPathValue(_batteryConfig.currentPath);
    final power = _getPathValue(_batteryConfig.powerPath);
    final timeRemaining = _getPathValue(_batteryConfig.timeRemainingPath);
    final temp = _getPathValue(_batteryConfig.temperaturePath);

    final isCharging = (current ?? 0) > 0;
    final isDischarging = (current ?? 0) < 0;

    String stateText = 'Idle';
    if (isCharging) stateText = 'Charging';
    if (isDischarging) stateText = 'Discharging';

    String timeText = '';
    if (timeRemaining != null && timeRemaining > 0) {
      final hours = timeRemaining ~/ 3600;
      final minutes = (timeRemaining % 3600) ~/ 60;
      if (hours > 24) {
        timeText = '${hours ~/ 24}d ${hours % 24}h';
      } else {
        timeText = '${hours}h ${minutes}m';
      }
    }

    final bgColor = HSLColor.fromColor(_primaryColor).withLightness(0.5).withSaturation(0.6).toColor().withValues(alpha: 0.9);
    final borderColor = HSLColor.fromColor(_primaryColor).withLightness(0.7).toColor();

    return _buildComponentBox(
      title: 'Battery',
      icon: Icons.battery_std,
      backgroundColor: bgColor,
      borderColor: borderColor,
      content: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 200;
          final stateColor = isCharging ? Colors.greenAccent : (isDischarging ? Colors.orangeAccent : Colors.white70);

          if (isWide) {
            // Horizontal layout for wide cards
            return Row(
              children: [
                // SOC on left
                Expanded(
                  flex: 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      soc != null ? '${(soc * 100).toStringAsFixed(0)}%' : '--%',
                      style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Status in middle
                Expanded(
                  flex: 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(stateText, style: TextStyle(color: stateColor, fontSize: 14, fontWeight: FontWeight.w500)),
                        if (timeText.isNotEmpty)
                          Text(timeText, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        if (temp != null)
                          Text('${(temp - 273.15).toStringAsFixed(0)}°C', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // V/A/W on right
                Expanded(
                  flex: 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${voltage?.toStringAsFixed(2) ?? '--'}V', style: TextStyle(color: stateColor, fontSize: 13)),
                        Text('${current?.toStringAsFixed(1) ?? '--'}A', style: TextStyle(color: stateColor, fontSize: 13)),
                        Text('${power?.toStringAsFixed(0) ?? '--'}W', style: TextStyle(color: stateColor, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          // Vertical layout for narrow cards
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      soc != null ? '${(soc * 100).toStringAsFixed(0)}%' : '--%',
                      style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                    ),
                    if (temp != null) ...[
                      const SizedBox(width: 16),
                      Text('${(temp - 273.15).toStringAsFixed(0)}°C', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(stateText, style: TextStyle(color: stateColor, fontSize: 14)),
                    if (timeText.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(timeText, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${voltage?.toStringAsFixed(2) ?? '--'}V  ${current?.toStringAsFixed(1) ?? '--'}A  ${power?.toStringAsFixed(0) ?? '--'}W',
                  style: TextStyle(color: stateColor, fontSize: 13),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatState(String state) {
    if (state.isEmpty) return 'Off';
    return state
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}' : '')
        .join(' ');
  }
}

/// Animated flow lines painter - now supports variable source/load counts
class _FlowLinesPainter extends CustomPainter {
  final double animValue;
  final int sourceCount;
  final int loadCount;
  final List<double> sourceFlows;
  final List<double> loadFlows;
  final bool batteryCharging;
  final bool batteryDischarging;
  final double batteryCurrent;
  final Color primaryColor;

  _FlowLinesPainter({
    required this.animValue,
    required this.sourceCount,
    required this.loadCount,
    required this.sourceFlows,
    required this.loadFlows,
    required this.batteryCharging,
    required this.batteryDischarging,
    required this.batteryCurrent,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final inactivePaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.3)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Match layout: padding 12, gaps 70, flex 3:4:3
    const padding = 12.0;
    const gap = 70.0;
    final contentWidth = size.width - padding * 2;
    final colWidthUnit = (contentWidth - gap * 2) / 10;

    final leftColRight = padding + colWidthUnit * 3;
    final centerColLeft = leftColRight + gap;
    final centerColRight = centerColLeft + colWidthUnit * 4;
    final rightColLeft = centerColRight + gap;

    // Calculate source row positions with proportional spacing
    final contentHeight = size.height - padding * 2;

    // Proportional spacing: 15% of height distributed among gaps, clamped 12-40
    final sourceGapCount = sourceCount > 1 ? sourceCount - 1 : 0;
    final loadGapCount = loadCount > 1 ? loadCount - 1 : 0;
    final sourceSpacing = sourceGapCount > 0
        ? (contentHeight * 0.15 / sourceGapCount).clamp(12.0, 40.0)
        : 0.0;
    final loadSpacing = loadGapCount > 0
        ? (contentHeight * 0.15 / loadGapCount).clamp(12.0, 40.0)
        : 0.0;

    final sourceGaps = sourceGapCount * sourceSpacing;
    final sourceRowHeight = (contentHeight - sourceGaps) / sourceCount;

    List<double> sourceRowCenters = [];
    for (int i = 0; i < sourceCount; i++) {
      sourceRowCenters.add(padding + sourceRowHeight * i + sourceSpacing * i + sourceRowHeight / 2);
    }

    // Calculate load row positions
    final loadGaps = loadGapCount * loadSpacing;
    final loadRowHeight = (contentHeight - loadGaps) / (loadCount < 3 ? 3 : loadCount); // Account for spacer

    List<double> loadRowCenters = [];
    for (int i = 0; i < loadCount; i++) {
      loadRowCenters.add(padding + loadRowHeight * i + loadSpacing * i + loadRowHeight / 2);
    }

    // Center column: inverter (flex 2) and battery (flex 3) with 28px gap
    final inverterHeight = (contentHeight - 28) * 2 / 5;
    final batteryHeight = (contentHeight - 28) * 3 / 5;
    final inverterBottom = padding + inverterHeight;
    final batteryTop = inverterBottom + 28;
    final batteryCenter = batteryTop + batteryHeight / 2;
    final inverterCenter = padding + inverterHeight / 2;

    final midX = leftColRight + gap / 2;

    // Draw source flows
    int lineIndex = 0;
    for (int i = 0; i < sourceCount; i++) {
      final flow = i < sourceFlows.length ? sourceFlows[i] : 0.0;
      final isActive = flow > 0.1;
      final phaseOffset = lineIndex * 0.17; // Stagger by ~17% of cycle
      lineIndex++;

      if (i == 0) {
        // First source goes to inverter (like Shore) - orthogonal routing
        _drawAnimatedPath(
          canvas,
          [
            Offset(leftColRight, sourceRowCenters[i]),
            Offset(midX, sourceRowCenters[i]),
            Offset(midX, inverterCenter),
            Offset(centerColLeft, inverterCenter),
          ],
          isActive,
          flow,
          inactivePaint,
          true,
          phaseOffset: phaseOffset,
        );
      } else {
        // Other sources go to battery with corner routing
        final yOffset = (i - 1) * 10.0 - 5; // Spread the lines vertically
        _drawAnimatedPath(
          canvas,
          [
            Offset(leftColRight, sourceRowCenters[i]),
            Offset(midX, sourceRowCenters[i]),
            Offset(midX, batteryCenter + yOffset),
            Offset(centerColLeft, batteryCenter + yOffset),
          ],
          isActive,
          flow,
          inactivePaint,
          true,
          phaseOffset: phaseOffset,
        );
      }
    }

    // Inverter to/from Battery (vertical)
    _drawAnimatedLine(
      canvas,
      Offset((centerColLeft + centerColRight) / 2, inverterBottom),
      Offset((centerColLeft + centerColRight) / 2, batteryTop),
      batteryCharging || batteryDischarging,
      batteryCurrent,
      inactivePaint,
      batteryCharging,
      phaseOffset: lineIndex * 0.17,
    );
    lineIndex++;

    // Draw load flows
    final midXRight = centerColRight + gap / 2;
    for (int i = 0; i < loadCount; i++) {
      final flow = i < loadFlows.length ? loadFlows[i] : 0.0;
      final isActive = flow > 0.1;
      final phaseOffset = lineIndex * 0.17;
      lineIndex++;

      if (i == 0) {
        // First load from inverter (like AC loads) - orthogonal routing
        _drawAnimatedPath(
          canvas,
          [
            Offset(centerColRight, inverterCenter),
            Offset(midXRight, inverterCenter),
            Offset(midXRight, loadRowCenters[i]),
            Offset(rightColLeft, loadRowCenters[i]),
          ],
          isActive,
          flow,
          inactivePaint,
          true,
          phaseOffset: phaseOffset,
        );
      } else {
        // Other loads from battery - orthogonal routing
        final yOffset = (i - 1) * 10.0 - 5;
        _drawAnimatedPath(
          canvas,
          [
            Offset(centerColRight, batteryCenter + yOffset),
            Offset(midXRight, batteryCenter + yOffset),
            Offset(midXRight, loadRowCenters[i]),
            Offset(rightColLeft, loadRowCenters[i]),
          ],
          isActive,
          flow,
          inactivePaint,
          true,
          phaseOffset: phaseOffset,
        );
      }
    }
  }

  void _drawAnimatedLine(Canvas canvas, Offset start, Offset end, bool active, double current, Paint inactivePaint, bool forward, {double phaseOffset = 0.0}) {
    // Draw dots at endpoints
    final dotPaint = Paint()
      ..color = active ? primaryColor : primaryColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(start, 5, dotPaint);
    canvas.drawCircle(end, 5, dotPaint);

    // Draw the solid line
    final linePaint = Paint()
      ..color = active ? primaryColor.withValues(alpha: 0.6) : primaryColor.withValues(alpha: 0.2)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawLine(start, end, linePaint);

    if (!active) return;

    // Calculate animation speed based on current using defined scale
    final speed = _currentToSpeed(current);

    // Calculate line length and direction
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = math.sqrt(dx * dx + dy * dy);

    // Calculate angle for arrow direction
    double angle = math.atan2(dy, dx);
    if (!forward) angle += math.pi; // Reverse direction

    // Fixed spacing between sprites (in pixels)
    const spriteSpacing = 25.0;
    final numSprites = (length / spriteSpacing).floor().clamp(2, 8);

    // Cycle length includes a gap at the end for natural flow
    final cycleLength = 1.0 + (1.0 / numSprites);

    // Extra distance for sprite to travel beyond endpoint (as fraction of line)
    // Allows head+tail to fully exit under the destination card
    // Use minimum of 0.15 (15%) to ensure visible extension on short lines
    final exitExtension = math.max(30.0 / length, 0.15);

    for (int i = 0; i < numSprites; i++) {
      final baseT = (forward ? animValue : 1 - animValue) * speed;

      // Simple unique offset per sprite using golden ratio for max spread
      final golden = 0.618033988749;
      final spriteHash = ((i + 1) * golden + phaseOffset * 7.3) % 1.0;
      final jitterStrength = 0.3 / (1.0 + speed * speed * 0.15);
      final jitter = (spriteHash - 0.5) * jitterStrength;

      var t = (baseT + (i / numSprites) + phaseOffset + jitter) % cycleLength;

      if (t > 1.0 + exitExtension) continue;

      final x = start.dx + dx * t;
      final y = start.dy + dy * t;
      _drawMeteorSprite(canvas, Offset(x, y), angle, primaryColor);
    }
  }

  void _drawMeteorSprite(Canvas canvas, Offset center, double angle, Color color) {
    _drawMeteorSpriteSimple(canvas, center, angle, color);
  }

  void _drawMeteorSpriteSimple(Canvas canvas, Offset center, double angle, Color color) {
    const tailLength = 18.0;

    final tailDx = -math.cos(angle) * tailLength;
    final tailDy = -math.sin(angle) * tailLength;

    // Tail - multiple segments fading out
    const segments = 5;
    for (int i = 0; i < segments; i++) {
      final t1 = i / segments;
      final t2 = (i + 1) / segments;

      final start = Offset(
        center.dx + tailDx * t1,
        center.dy + tailDy * t1,
      );
      final end = Offset(
        center.dx + tailDx * t2,
        center.dy + tailDy * t2,
      );

      // Fade from bright to transparent
      final alpha = 0.6 * (1 - t1);
      final width = 4.0 * (1 - t1 * 0.5);

      final segPaint = Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.5 + t1 * 2);
      canvas.drawLine(start, end, segPaint);
    }

    _drawMeteorHead(canvas, center, color);
  }

  void _drawMeteorSpriteOnPath(Canvas canvas, List<Offset> points, List<double> segmentLengths, double distanceAlongPath, double totalLength, bool forward, Color color, {double phaseOffset = 0.0}) {
    const tailLength = 18.0;
    const segments = 5;

    // Get head position
    final head = _getPointOnPath(points, segmentLengths, distanceAlongPath, totalLength, phaseOffset: phaseOffset);

    // Draw tail segments by tracing back along path
    for (int i = 0; i < segments; i++) {
      final t1 = i / segments;
      final t2 = (i + 1) / segments;

      final dist1 = forward
          ? distanceAlongPath - tailLength * t1
          : distanceAlongPath + tailLength * t1;
      final dist2 = forward
          ? distanceAlongPath - tailLength * t2
          : distanceAlongPath + tailLength * t2;

      final start = _getPointOnPath(points, segmentLengths, dist1, totalLength, phaseOffset: phaseOffset);
      final end = _getPointOnPath(points, segmentLengths, dist2, totalLength, phaseOffset: phaseOffset);

      // Fade from bright to transparent
      final alpha = 0.6 * (1 - t1);
      final width = 4.0 * (1 - t1 * 0.5);

      final segPaint = Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.5 + t1 * 2);
      canvas.drawLine(start, end, segPaint);
    }

    _drawMeteorHead(canvas, head, color);
  }

  Offset _getPointOnPath(List<Offset> points, List<double> segmentLengths, double distance, double totalLength, {double phaseOffset = 0.0}) {
    // Clamp distance to valid range
    if (distance <= 0) return points.first;
    if (distance >= totalLength) return points.last;

    double accumulated = 0;
    for (int i = 0; i < segmentLengths.length; i++) {
      if (accumulated + segmentLengths[i] >= distance) {
        final segT = (distance - accumulated) / segmentLengths[i];
        return Offset(
          points[i].dx + (points[i + 1].dx - points[i].dx) * segT,
          points[i].dy + (points[i + 1].dy - points[i].dy) * segT,
        );
      }
      accumulated += segmentLengths[i];
    }
    return points.last;
  }

  void _drawMeteorHead(Canvas canvas, Offset center, Color color) {
    // Colored glow around head
    final glowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(center, 6, glowPaint);

    // Bright white head with soft blur
    final headPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(center, 3, headPaint);
  }

  void _drawAnimatedPath(Canvas canvas, List<Offset> points, bool active, double current, Paint inactivePaint, bool forward, {double phaseOffset = 0.0}) {
    if (points.length < 2) return;

    // Draw dots at endpoints
    final dotPaint = Paint()
      ..color = active ? primaryColor : primaryColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(points.first, 5, dotPaint);
    canvas.drawCircle(points.last, 5, dotPaint);

    // Draw curved path with rounded corners
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    const cornerRadius = 15.0;

    for (int i = 1; i < points.length - 1; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final next = points[i + 1];

      // Calculate direction vectors
      final d1x = curr.dx - prev.dx;
      final d1y = curr.dy - prev.dy;
      final d2x = next.dx - curr.dx;
      final d2y = next.dy - curr.dy;

      // Normalize and get distances
      final len1 = math.sqrt(d1x * d1x + d1y * d1y);
      final len2 = math.sqrt(d2x * d2x + d2y * d2y);

      // Calculate how far back from corner to start curve
      final radius = math.min(cornerRadius, math.min(len1, len2) / 2);

      // Point before corner
      final beforeX = curr.dx - (d1x / len1) * radius;
      final beforeY = curr.dy - (d1y / len1) * radius;

      // Point after corner
      final afterX = curr.dx + (d2x / len2) * radius;
      final afterY = curr.dy + (d2y / len2) * radius;

      // Draw line to before corner, then curve through corner
      path.lineTo(beforeX, beforeY);
      path.quadraticBezierTo(curr.dx, curr.dy, afterX, afterY);
    }
    path.lineTo(points.last.dx, points.last.dy);

    final linePaint = Paint()
      ..color = active ? primaryColor.withValues(alpha: 0.6) : primaryColor.withValues(alpha: 0.2)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);

    if (!active) return;

    // Calculate total path length
    double totalLength = 0;
    List<double> segmentLengths = [];
    for (int i = 1; i < points.length; i++) {
      final dx = points[i].dx - points[i - 1].dx;
      final dy = points[i].dy - points[i - 1].dy;
      final len = math.sqrt(dx * dx + dy * dy);
      segmentLengths.add(len);
      totalLength += len;
    }

    // Calculate animation speed based on current using defined scale
    final speed = _currentToSpeed(current);

    // Fixed spacing between sprites (in pixels)
    const spriteSpacing = 25.0;
    final numSprites = (totalLength / spriteSpacing).floor().clamp(2, 8);

    // Cycle length includes a gap at the end for natural flow
    final cycleLength = 1.0 + (1.0 / numSprites);

    // Extra distance for sprite to travel beyond endpoint
    // Use minimum of 0.15 (15%) to ensure visible extension on short lines
    final exitExtension = math.max(30.0 / totalLength, 0.15);

    for (int i = 0; i < numSprites; i++) {
      final baseT = (forward ? animValue : 1 - animValue) * speed;

      // Simple unique offset per sprite using golden ratio for max spread
      final golden = 0.618033988749;
      final spriteHash = ((i + 1) * golden + phaseOffset * 7.3) % 1.0;
      final jitterStrength = 0.3 / (1.0 + speed * speed * 0.15);
      final jitter = (spriteHash - 0.5) * jitterStrength;

      var t = (baseT + (i / numSprites) + phaseOffset + jitter) % cycleLength;

      if (t > 1.0 + exitExtension) continue;

      var distanceAlongPath = t * totalLength;
      _drawMeteorSpriteOnPath(canvas, points, segmentLengths, distanceAlongPath, totalLength, forward, primaryColor, phaseOffset: phaseOffset);
    }
  }

  /// Power-law scale: maps current (0.1A to 200A) to speed (0.1 to 8.0)
  /// Uses current^0.58 - keeps low end slow, faster at high end
  double _currentToSpeed(double current) {
    const minCurrent = 0.1;
    const maxCurrent = 200.0;

    final clampedCurrent = current.abs().clamp(minCurrent, maxCurrent);

    // Power law: speed = 0.38 * current^0.58
    // Derived from: 0.1A → 0.1, 200A → 8.0
    return 0.38 * math.pow(clampedCurrent, 0.58);
  }

  @override
  bool shouldRepaint(covariant _FlowLinesPainter oldDelegate) => true;
}

/// Builder for Victron Flow Tool
class VictronFlowToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'victron_flow',
      name: 'Power Flow',
      description: 'Visual power flow diagram with customizable sources and loads',
      category: ToolCategory.electrical,
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
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: [], // No longer using dataSources, paths are in customProperties
      style: StyleConfig(
        customProperties: {
          'sources': [
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
          ],
          'loads': [
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
          ],
          'inverterStatePath': 'electrical.inverter.state',
          'battery': {
            'socPath': 'electrical.batteries.house.capacity.stateOfCharge',
            'voltagePath': 'electrical.batteries.house.voltage',
            'currentPath': 'electrical.batteries.house.current',
            'powerPath': 'electrical.batteries.house.power',
            'timeRemainingPath': 'electrical.batteries.house.capacity.timeRemaining',
            'temperaturePath': 'electrical.batteries.house.temperature',
          },
        },
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return VictronFlowTool(config: config, signalKService: signalKService);
  }
}
