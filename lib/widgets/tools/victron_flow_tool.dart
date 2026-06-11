import 'dart:math' as math;
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
  // Optional SignalK source per path (null = Auto / active source).
  final String? currentSource;
  final String? voltageSource;
  final String? powerSource;
  final String? frequencySource;
  final String? stateSource;

  const PowerSourceConfig({
    required this.name,
    required this.icon,
    this.currentPath,
    this.voltagePath,
    this.powerPath,
    this.frequencyPath,
    this.statePath,
    this.currentSource,
    this.voltageSource,
    this.powerSource,
    this.frequencySource,
    this.stateSource,
    this.primaryMetric = 'power',
  });

  /// Which metric is the headline value (and drives the flow speed):
  /// 'power' (default) | 'current' | 'voltage'.
  final String primaryMetric;

  factory PowerSourceConfig.fromMap(Map<String, dynamic> map) {
    return PowerSourceConfig(
      name: map['name'] as String? ?? 'Source',
      icon: map['icon'] as String? ?? 'power',
      currentPath: map['currentPath'] as String?,
      voltagePath: map['voltagePath'] as String?,
      powerPath: map['powerPath'] as String?,
      frequencyPath: map['frequencyPath'] as String?,
      statePath: map['statePath'] as String?,
      currentSource: map['currentSource'] as String?,
      voltageSource: map['voltageSource'] as String?,
      powerSource: map['powerSource'] as String?,
      frequencySource: map['frequencySource'] as String?,
      stateSource: map['stateSource'] as String?,
      primaryMetric: map['primaryMetric'] as String? ?? 'power',
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
    if (currentSource != null) 'currentSource': currentSource,
    if (voltageSource != null) 'voltageSource': voltageSource,
    if (powerSource != null) 'powerSource': powerSource,
    if (frequencySource != null) 'frequencySource': frequencySource,
    if (stateSource != null) 'stateSource': stateSource,
    'primaryMetric': primaryMetric,
  };

  /// Flow-animation magnitude. Power is the default driver (scaled /100 so its
  /// speed is comparable to current); a 'current' primary prefers current.
  /// Voltage/other primaries fall back to power→current — voltage is not a
  /// flow magnitude.
  double getPrimaryValue(SignalKService service) {
    double? read(String? path, String? src, {bool scale = false}) {
      if (path == null) return null;
      final d = service.getValue(path, source: src);
      if (d?.value is! num) return null;
      final v = (d!.value as num).toDouble().abs();
      return scale ? v / 100 : v;
    }
    final c = read(currentPath, currentSource);
    final p = read(powerPath, powerSource, scale: true);
    if (primaryMetric == 'current') return c ?? p ?? 0;
    return p ?? c ?? 0;
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
  // Optional SignalK source per path (null = Auto / active source).
  final String? currentSource;
  final String? voltageSource;
  final String? powerSource;
  final String? frequencySource;

  const PowerLoadConfig({
    required this.name,
    required this.icon,
    this.currentPath,
    this.voltagePath,
    this.powerPath,
    this.frequencyPath,
    this.currentSource,
    this.voltageSource,
    this.powerSource,
    this.frequencySource,
    this.primaryMetric = 'power',
  });

  /// Which metric is the headline value (and drives the flow speed):
  /// 'power' (default) | 'current' | 'voltage'.
  final String primaryMetric;

  factory PowerLoadConfig.fromMap(Map<String, dynamic> map) {
    return PowerLoadConfig(
      name: map['name'] as String? ?? 'Load',
      icon: map['icon'] as String? ?? 'power',
      currentPath: map['currentPath'] as String?,
      voltagePath: map['voltagePath'] as String?,
      powerPath: map['powerPath'] as String?,
      frequencyPath: map['frequencyPath'] as String?,
      currentSource: map['currentSource'] as String?,
      voltageSource: map['voltageSource'] as String?,
      powerSource: map['powerSource'] as String?,
      frequencySource: map['frequencySource'] as String?,
      primaryMetric: map['primaryMetric'] as String? ?? 'power',
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'icon': icon,
    if (currentPath != null) 'currentPath': currentPath,
    if (voltagePath != null) 'voltagePath': voltagePath,
    if (powerPath != null) 'powerPath': powerPath,
    if (frequencyPath != null) 'frequencyPath': frequencyPath,
    if (currentSource != null) 'currentSource': currentSource,
    if (voltageSource != null) 'voltageSource': voltageSource,
    if (powerSource != null) 'powerSource': powerSource,
    if (frequencySource != null) 'frequencySource': frequencySource,
    'primaryMetric': primaryMetric,
  };

  /// See [PowerSourceConfig.getPrimaryValue] — same rule: power-first
  /// (scaled /100), current-first when primaryMetric == 'current'.
  double getPrimaryValue(SignalKService service) {
    double? read(String? path, String? src, {bool scale = false}) {
      if (path == null) return null;
      final d = service.getValue(path, source: src);
      if (d?.value is! num) return null;
      final v = (d!.value as num).toDouble().abs();
      return scale ? v / 100 : v;
    }
    final c = read(currentPath, currentSource);
    final p = read(powerPath, powerSource, scale: true);
    if (primaryMetric == 'current') return c ?? p ?? 0;
    return p ?? c ?? 0;
  }

  bool get hasAnyPath => currentPath != null || voltagePath != null || powerPath != null;
}

/// Battery configuration paths
class BatteryConfig {
  final String name;
  final String? socPath;
  final String? voltagePath;
  final String? currentPath;
  final String? powerPath;
  final String? timeRemainingPath;
  final String? temperaturePath;
  // Optional SignalK source per path (null = Auto / active source).
  final String? socSource;
  final String? voltageSource;
  final String? currentSource;
  final String? powerSource;
  final String? timeRemainingSource;
  final String? temperatureSource;

  const BatteryConfig({
    this.name = 'Battery',
    this.socPath,
    this.voltagePath,
    this.currentPath,
    this.powerPath,
    this.timeRemainingPath,
    this.temperaturePath,
    this.socSource,
    this.voltageSource,
    this.currentSource,
    this.powerSource,
    this.timeRemainingSource,
    this.temperatureSource,
  });

  factory BatteryConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const BatteryConfig();
    return BatteryConfig(
      name: map['name'] as String? ?? 'Battery',
      socPath: map['socPath'] as String?,
      voltagePath: map['voltagePath'] as String?,
      currentPath: map['currentPath'] as String?,
      powerPath: map['powerPath'] as String?,
      timeRemainingPath: map['timeRemainingPath'] as String?,
      temperaturePath: map['temperaturePath'] as String?,
      socSource: map['socSource'] as String?,
      voltageSource: map['voltageSource'] as String?,
      currentSource: map['currentSource'] as String?,
      powerSource: map['powerSource'] as String?,
      timeRemainingSource: map['timeRemainingSource'] as String?,
      temperatureSource: map['temperatureSource'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    if (socPath != null) 'socPath': socPath,
    if (voltagePath != null) 'voltagePath': voltagePath,
    if (currentPath != null) 'currentPath': currentPath,
    if (powerPath != null) 'powerPath': powerPath,
    if (timeRemainingPath != null) 'timeRemainingPath': timeRemainingPath,
    if (temperaturePath != null) 'temperaturePath': temperaturePath,
    if (socSource != null) 'socSource': socSource,
    if (voltageSource != null) 'voltageSource': voltageSource,
    if (currentSource != null) 'currentSource': currentSource,
    if (powerSource != null) 'powerSource': powerSource,
    if (timeRemainingSource != null) 'timeRemainingSource': timeRemainingSource,
    if (temperatureSource != null) 'temperatureSource': temperatureSource,
  };

  /// Get the primary value for flow animation (current or power)
  double getPrimaryValue(SignalKService service) {
    if (currentPath != null) {
      final data = service.getValue(currentPath!, source: currentSource);
      if (data?.value is num) return (data!.value as num).toDouble().abs();
    }
    if (powerPath != null) {
      final data = service.getValue(powerPath!, source: powerSource);
      if (data?.value is num) return (data!.value as num).toDouble().abs() / 100;
    }
    return 0;
  }

  bool get hasAnyPath =>
      socPath != null ||
      voltagePath != null ||
      currentPath != null ||
      powerPath != null ||
      timeRemainingPath != null ||
      temperaturePath != null;
}

List<PowerSourceConfig> _defaultPowerSources() => [
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

List<PowerLoadConfig> _defaultPowerLoads() => [
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

BatteryConfig _defaultBatteryConfig() => const BatteryConfig(
  name: 'House',
  socPath: 'electrical.batteries.house.capacity.stateOfCharge',
  voltagePath: 'electrical.batteries.house.voltage',
  currentPath: 'electrical.batteries.house.current',
  powerPath: 'electrical.batteries.house.power',
  timeRemainingPath: 'electrical.batteries.house.capacity.timeRemaining',
  temperaturePath: 'electrical.batteries.house.temperature',
);

/// Parsed Power Flow configuration. Single source of truth shared by the
/// widget (rendering) and the builder (subscription path collection), so the
/// paths the central subscription manager subscribes always match the paths
/// the widget reads.
class _VictronConfig {
  final List<PowerSourceConfig> sources;
  final List<PowerLoadConfig> loads;
  final List<BatteryConfig> batteries;
  final String? inverterStatePath;
  final String? inverterStateSource;
  // Writable mode path + tap-to-set options (On / Off / Charger Only /
  // Inverter Only). Empty path → tapping the inverter box does nothing.
  final String? inverterModePath;
  final List<Map<String, dynamic>> inverterModeOptions;
  const _VictronConfig({
    required this.sources,
    required this.loads,
    required this.batteries,
    required this.inverterStatePath,
    required this.inverterStateSource,
    required this.inverterModePath,
    required this.inverterModeOptions,
  });
}

/// Whether a live mode value matches a configured option value: numbers
/// compare numerically, everything else case-insensitively (so "On"/"on"
/// match). Pure + top-level so it's unit-testable.
bool victronModeValuesMatch(dynamic live, dynamic option) {
  if (live == null || option == null) return false;
  if (live is num && option is num) return live == option;
  return live.toString().trim().toLowerCase() ==
      option.toString().trim().toLowerCase();
}

/// Standard Victron VE.Bus mode positions used when nothing is configured.
List<Map<String, dynamic>> _defaultInverterModeOptions() => [
      {'label': 'On', 'value': 'on'},
      {'label': 'Off', 'value': 'off'},
      {'label': 'Charger Only', 'value': 'charger only'},
      {'label': 'Inverter Only', 'value': 'inverter only'},
    ];

_VictronConfig _parseVictronConfig(ToolConfig config) {
  final customProps = config.style.customProperties ?? {};

  final sourcesData = customProps['sources'] as List<dynamic>?;
  final sources = (sourcesData != null && sourcesData.isNotEmpty)
      ? sourcesData
          .whereType<Map<String, dynamic>>()
          .map((m) => PowerSourceConfig.fromMap(m))
          .toList()
      : _defaultPowerSources();

  final loadsData = customProps['loads'] as List<dynamic>?;
  final loads = (loadsData != null && loadsData.isNotEmpty)
      ? loadsData
          .whereType<Map<String, dynamic>>()
          .map((m) => PowerLoadConfig.fromMap(m))
          .toList()
      : _defaultPowerLoads();

  final batteriesData = customProps['batteries'] as List<dynamic>?;
  final List<BatteryConfig> batteries;
  if (batteriesData != null && batteriesData.isNotEmpty) {
    batteries = batteriesData
        .whereType<Map<String, dynamic>>()
        .map((m) => BatteryConfig.fromMap(m))
        .toList();
  } else {
    // Backward compat: single 'battery' map → wrap in list
    final singleBattery =
        BatteryConfig.fromMap(customProps['battery'] as Map<String, dynamic>?);
    batteries =
        singleBattery.hasAnyPath ? [singleBattery] : [_defaultBatteryConfig()];
  }

  return _VictronConfig(
    sources: sources,
    loads: loads,
    batteries: batteries,
    inverterStatePath:
        customProps['inverterStatePath'] as String? ?? 'electrical.inverter.state',
    inverterStateSource: customProps['inverterStateSource'] as String?,
    inverterModePath: (customProps['inverterModePath'] as String?)?.trim(),
    inverterModeOptions: (customProps['inverterModeOptions'] as List<dynamic>?)
            ?.whereType<Map>()
            .map((m) => m.cast<String, dynamic>())
            .toList() ??
        _defaultInverterModeOptions(),
  );
}

/// All SignalK paths a Power Flow tool reads, for the central subscription
/// manager. Mirrors what the widget renders (same parse + default fallbacks).
List<String> victronRequiredPaths(ToolConfig config) {
  final c = _parseVictronConfig(config);
  final paths = <String>[];
  for (final s in c.sources) {
    if (s.currentPath != null) paths.add(s.currentPath!);
    if (s.voltagePath != null) paths.add(s.voltagePath!);
    if (s.powerPath != null) paths.add(s.powerPath!);
    if (s.frequencyPath != null) paths.add(s.frequencyPath!);
    if (s.statePath != null) paths.add(s.statePath!);
  }
  for (final l in c.loads) {
    if (l.currentPath != null) paths.add(l.currentPath!);
    if (l.voltagePath != null) paths.add(l.voltagePath!);
    if (l.powerPath != null) paths.add(l.powerPath!);
    if (l.frequencyPath != null) paths.add(l.frequencyPath!);
  }
  for (final b in c.batteries) {
    if (b.socPath != null) paths.add(b.socPath!);
    if (b.voltagePath != null) paths.add(b.voltagePath!);
    if (b.currentPath != null) paths.add(b.currentPath!);
    if (b.powerPath != null) paths.add(b.powerPath!);
    if (b.timeRemainingPath != null) paths.add(b.timeRemainingPath!);
    if (b.temperaturePath != null) paths.add(b.temperaturePath!);
  }
  if (c.inverterStatePath != null) paths.add(c.inverterStatePath!);
  // Subscribe the mode path too so the tap menu can highlight the active mode.
  if (c.inverterModePath != null && c.inverterModePath!.isNotEmpty) {
    paths.add(c.inverterModePath!);
  }
  return paths;
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
  late List<BatteryConfig> _batteryConfigs;
  late String? _inverterStatePath;
  late String? _inverterStateSource;
  late String? _inverterModePath;
  late List<Map<String, dynamic>> _inverterModeOptions;
  late Color _primaryColor;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
    // Subscriptions are owned centrally by the dashboard/tool subscription
    // manager (see VictronFlowToolBuilder.requiredPaths) — the widget is a
    // pure reader and just repaints on delta. This keeps it on the same
    // single source of truth as every other tool and recovers on reconnect.
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
    final c = _parseVictronConfig(widget.config);
    _sources = c.sources;
    _loads = c.loads;
    _batteryConfigs = c.batteries;
    _inverterStatePath = c.inverterStatePath;
    _inverterStateSource = c.inverterStateSource;
    _inverterModePath = c.inverterModePath;
    _inverterModeOptions = c.inverterModeOptions;
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

  @override
  void dispose() {
    _animController.dispose();
    widget.signalKService.removeListener(_onDataUpdate);
    super.dispose();
  }

  void _onDataUpdate() {
    if (mounted) setState(() {});
  }

  double? _getPathValue(String? path, [String? source]) {
    if (path == null || path.isEmpty) return null;
    final data = widget.signalKService.getValue(path, source: source);
    if (data?.value is num) {
      return (data!.value as num).toDouble();
    }
    return null;
  }

  String? _getPathStringValue(String? path, [String? source]) {
    if (path == null || path.isEmpty) return null;
    final data = widget.signalKService.getValue(path, source: source);
    if (data?.value != null) {
      return data!.value.toString();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Build flow data for painter
    final sourceFlows = _sources.map((s) => s.getPrimaryValue(widget.signalKService)).toList();
    final loadFlows = _loads.map((l) => l.getPrimaryValue(widget.signalKService)).toList();
    final batteryCurrents = _batteryConfigs.map((b) => _getPathValue(b.currentPath, b.currentSource) ?? 0.0).toList();

    return Stack(
      children: [
        LayoutBuilder(
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
                    batteryCount: _batteryConfigs.length,
                    batteryCurrents: batteryCurrents,
                    primaryColor: _primaryColor,
                  ),
                  child: child,
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 32, 12, 12),
                child: _buildFlowDiagram(constraints),
              ),
            );
          },
        ),
      ],
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
        // Center column - Inverter & Batteries
        Expanded(
          flex: 4,
          child: Column(
            children: [
              Expanded(flex: 2, child: _buildInverterBox()),
              const SizedBox(height: 28),
              Expanded(
                flex: _batteryConfigs.length == 1
                    ? 3
                    : _batteryConfigs.length * 2,
                child: _buildBatteriesContainer(),
              ),
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
    Gradient? backgroundGradient,
    bool drawBorder = true,
    VoidCallback? onTap,
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

    final inner = Padding(
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

    // Always paint the normal bgColor as the base. A backgroundGradient (the
    // battery SOC fill) is layered ON TOP of it rather than replacing it, so
    // the unfilled — transparent — portion of the gradient reveals the bare
    // container background ("visible but not filled").
    final box = Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: drawBorder ? Border.all(color: border, width: 2) : null,
      ),
      clipBehavior: backgroundGradient != null ? Clip.antiAlias : Clip.none,
      child: backgroundGradient == null
          ? inner
          : Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: backgroundGradient),
                  ),
                ),
                inner,
              ],
            ),
    );
    if (onTap == null) return box;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: box,
    );
  }

  Widget _buildSourceBox(PowerSourceConfig source) {
    final state = _getPathStringValue(source.statePath, source.stateSource);
    final headline = _formatPrimary(
      source.primaryMetric,
      currentPath: source.currentPath, currentSource: source.currentSource,
      voltagePath: source.voltagePath, voltageSource: source.voltageSource,
      powerPath: source.powerPath, powerSource: source.powerSource,
    );
    final secondary = _buildSecondaryLine(
      source.primaryMetric,
      currentPath: source.currentPath, currentSource: source.currentSource,
      voltagePath: source.voltagePath, voltageSource: source.voltageSource,
      powerPath: source.powerPath, powerSource: source.powerSource,
      frequencyPath: source.frequencyPath, frequencySource: source.frequencySource,
    );

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
                      headline,
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
                          secondary,
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
                  headline,
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                ),
                if (state != null)
                  Text(_formatState(state), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                Text(
                  secondary,
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
    final headline = _formatPrimary(
      load.primaryMetric,
      currentPath: load.currentPath, currentSource: load.currentSource,
      voltagePath: load.voltagePath, voltageSource: load.voltageSource,
      powerPath: load.powerPath, powerSource: load.powerSource,
    );
    final secondary = _buildSecondaryLine(
      load.primaryMetric,
      currentPath: load.currentPath, currentSource: load.currentSource,
      voltagePath: load.voltagePath, voltageSource: load.voltageSource,
      powerPath: load.powerPath, powerSource: load.powerSource,
      frequencyPath: load.frequencyPath, frequencySource: load.frequencySource,
    );

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
                      headline,
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
                      secondary,
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
                  headline,
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                ),
                Text(
                  secondary,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Secondary metrics line — every available metric EXCEPT the one chosen as
  /// the primary headline (so it isn't duplicated). Current appears here
  /// whenever it isn't the primary.
  /// Format the value at [path] via MetadataStore (single source of truth for
  /// the unit symbol); falls back to a plain SI [suffix] only when the server
  /// has no metadata for the path. Returns null when there's no value, so
  /// callers can omit absent metrics.
  String? _fmtMetric(String? path, String? src, String suffix, int decimals) {
    final v = _getPathValue(path, src);
    if (v == null) return null;
    final meta = (path != null && path.isNotEmpty)
        ? widget.signalKService.metadataStore.get(path)
        : null;
    return meta != null
        ? meta.format(v, decimals: decimals)
        : '${v.toStringAsFixed(decimals)}$suffix';
  }

  /// Secondary metrics line — every available metric EXCEPT the primary
  /// headline, formatted via MetadataStore (so it respects server unit
  /// metadata rather than hardcoding symbols).
  String _buildSecondaryLine(
    String primaryMetric, {
    String? currentPath,
    String? currentSource,
    String? voltagePath,
    String? voltageSource,
    String? powerPath,
    String? powerSource,
    String? frequencyPath,
    String? frequencySource,
  }) {
    final parts = <String>[];
    void add(String? s) {
      if (s != null) parts.add(s);
    }
    if (primaryMetric != 'current') add(_fmtMetric(currentPath, currentSource, 'A', 1));
    if (primaryMetric != 'voltage') add(_fmtMetric(voltagePath, voltageSource, 'V', 1));
    add(_fmtMetric(frequencyPath, frequencySource, 'Hz', 0));
    if (primaryMetric != 'power') add(_fmtMetric(powerPath, powerSource, 'W', 0));
    return parts.isEmpty ? '--' : parts.join('  ');
  }

  /// Headline string for a source/load's chosen [metric] (via MetadataStore).
  String _formatPrimary(
    String metric, {
    String? currentPath,
    String? currentSource,
    String? voltagePath,
    String? voltageSource,
    String? powerPath,
    String? powerSource,
  }) {
    switch (metric) {
      case 'current':
        return _fmtMetric(currentPath, currentSource, 'A', 1) ?? '--A';
      case 'voltage':
        return _fmtMetric(voltagePath, voltageSource, 'V', 1) ?? '--V';
      case 'power':
      default:
        return _fmtMetric(powerPath, powerSource, 'W', 0) ?? '--W';
    }
  }

  Widget _buildInverterBox() {
    final state = _getPathStringValue(_inverterStatePath, _inverterStateSource);
    final borderColor = HSLColor.fromColor(_primaryColor).withLightness(0.7).toColor();
    // Tappable only when a writable mode path + options are configured.
    final canSetMode = (_inverterModePath?.isNotEmpty ?? false) &&
        _inverterModeOptions.isNotEmpty;

    return _buildComponentBox(
      title: 'Inverter / Charger',
      icon: Icons.electrical_services,
      borderColor: borderColor,
      onTap: canSetMode ? _showInverterModeSnackbar : null,
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

  /// Tap handler for the inverter/charger box: a SnackBar offering the four
  /// configured mode options; tapping one PUTs its value to the mode path.
  void _showInverterModeSnackbar() {
    final path = _inverterModePath;
    if (path == null || path.isEmpty || _inverterModeOptions.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: ListenableBuilder(
          // Rebuild on every SignalK delta so the highlighted (active) option
          // tracks the live mode — including changes made outside this widget
          // while the snackbar is open, and the correct state at first build.
          listenable: widget.signalKService,
          builder: (context, _) {
            final current = widget.signalKService.getValue(path)?.value ??
                _getPathStringValue(_inverterStatePath, _inverterStateSource);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text('Set inverter / charger mode'),
                ),
                // One full-width button per line. Active = filled + checked;
                // inactive = darker grey with black text.
                for (final opt in _inverterModeOptions)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: victronModeValuesMatch(current, opt['value'])
                        ? FilledButton.icon(
                            onPressed: () {
                              messenger.hideCurrentSnackBar();
                              _putInverterMode(path, opt);
                            },
                            icon: const Icon(Icons.check, size: 18),
                            label: Text(opt['label'] as String? ?? ''),
                          )
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade600,
                              foregroundColor: Colors.black,
                            ),
                            onPressed: () {
                              messenger.hideCurrentSnackBar();
                              _putInverterMode(path, opt);
                            },
                            child: Text(opt['label'] as String? ?? ''),
                          ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _putInverterMode(String path, Map<String, dynamic> option) async {
    try {
      // Values are enum/state tokens, not unit-bearing — sent as-is.
      await widget.signalKService.sendPutRequest(path, option['value']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mode → ${option['label']}'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to set mode: $e'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// All batteries inside ONE bordered container. The flow painter targets the
  /// battery-area edges, so flows terminate at this container's edge.
  Widget _buildBatteriesContainer() {
    final borderColor =
        HSLColor.fromColor(_primaryColor).withLightness(0.7).toColor();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          for (int i = 0; i < _batteryConfigs.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            Expanded(child: _buildBatteryBox(_batteryConfigs[i])),
          ],
        ],
      ),
    );
  }

  Widget _buildBatteryBox(BatteryConfig battery) {
    final soc = _getPathValue(battery.socPath, battery.socSource);
    // Voltage/power are formatted for display via _fmtMetric (by path); only
    // current is needed here, to derive the charge/discharge state.
    final current = _getPathValue(battery.currentPath, battery.currentSource);
    final timeRemaining = _getPathValue(battery.timeRemainingPath, battery.timeRemainingSource);
    final temp = _getPathValue(battery.temperaturePath, battery.temperatureSource);

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

    // Blue fill proportional to state of charge — a left→right "fuel gauge":
    // the box is filled with the primary blue up to the SOC fraction, and the
    // remainder is left transparent so the bare container background shows
    // through (visible, but not filled). The gradient is painted OVER the
    // box's normal bgColor by _buildComponentBox (see backgroundGradient).
    final socFrac = (soc ?? 0).clamp(0.0, 1.0);
    final filledColor = HSLColor.fromColor(_primaryColor)
        .withLightness(0.5)
        .withSaturation(0.7)
        .toColor()
        .withValues(alpha: 0.95);
    final socGradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [filledColor, filledColor, Colors.transparent, Colors.transparent],
      stops: [0.0, socFrac, socFrac, 1.0],
    );

    return _buildComponentBox(
      title: battery.name,
      icon: Icons.battery_std,
      backgroundGradient: socGradient,
      drawBorder: false,
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
                          Builder(
                            builder: (context) {
                              final tempPath = battery.temperaturePath ?? 'electrical.batteries.house.temperature';
                              final metadata = widget.signalKService.metadataStore.get(tempPath);
                              final formatted = metadata?.format(temp, decimals: 0) ?? temp.toStringAsFixed(0);
                              return Text(formatted, style: const TextStyle(color: Colors.white70, fontSize: 13));
                            },
                          ),
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
                        Text(_fmtMetric(battery.voltagePath, battery.voltageSource, 'V', 2) ?? '--V', style: TextStyle(color: stateColor, fontSize: 13)),
                        Text(_fmtMetric(battery.currentPath, battery.currentSource, 'A', 1) ?? '--A', style: TextStyle(color: stateColor, fontSize: 13)),
                        Text(_fmtMetric(battery.powerPath, battery.powerSource, 'W', 0) ?? '--W', style: TextStyle(color: stateColor, fontSize: 13)),
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
                      Builder(
                        builder: (context) {
                          final tempPath = battery.temperaturePath ?? 'electrical.batteries.house.temperature';
                          final metadata = widget.signalKService.metadataStore.get(tempPath);
                          final formatted = metadata?.format(temp, decimals: 0) ?? temp.toStringAsFixed(0);
                          return Text(formatted, style: const TextStyle(color: Colors.white70, fontSize: 14));
                        },
                      ),
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
                  '${_fmtMetric(battery.voltagePath, battery.voltageSource, 'V', 2) ?? '--V'}  '
                  '${_fmtMetric(battery.currentPath, battery.currentSource, 'A', 1) ?? '--A'}  '
                  '${_fmtMetric(battery.powerPath, battery.powerSource, 'W', 0) ?? '--W'}',
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
  final int batteryCount;
  final List<double> batteryCurrents;
  final Color primaryColor;

  _FlowLinesPainter({
    required this.animValue,
    required this.sourceCount,
    required this.loadCount,
    required this.sourceFlows,
    required this.loadFlows,
    required this.batteryCount,
    required this.batteryCurrents,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final inactivePaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.3)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Match layout: padding LTRB(12, 32, 12, 12), gaps 70, flex 3:4:3
    const paddingLeft = 12.0;
    const paddingTop = 32.0;
    const paddingRight = 12.0;
    const paddingBottom = 12.0;
    const gap = 70.0;
    final contentWidth = size.width - paddingLeft - paddingRight;
    final colWidthUnit = (contentWidth - gap * 2) / 10;

    final leftColRight = paddingLeft + colWidthUnit * 3;
    final centerColLeft = leftColRight + gap;
    final centerColRight = centerColLeft + colWidthUnit * 4;
    final rightColLeft = centerColRight + gap;

    // Calculate source row positions with proportional spacing
    final contentHeight = size.height - paddingTop - paddingBottom;

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
      sourceRowCenters.add(paddingTop + sourceRowHeight * i + sourceSpacing * i + sourceRowHeight / 2);
    }

    // Calculate load row positions
    final loadGaps = loadGapCount * loadSpacing;
    final loadRowHeight = (contentHeight - loadGaps) / (loadCount < 3 ? 3 : loadCount); // Account for spacer

    List<double> loadRowCenters = [];
    for (int i = 0; i < loadCount; i++) {
      loadRowCenters.add(paddingTop + loadRowHeight * i + loadSpacing * i + loadRowHeight / 2);
    }

    // Center column: inverter (flex 2) and batteries (flex 3 total) with 28px gap
    final batteryFlex = batteryCount == 1 ? 3 : batteryCount * 2;
    final totalFlex = 2 + batteryFlex;
    // Batteries now live in ONE container (no outer inter-battery gaps), so
    // flows terminate at the container's top / left / right edges.
    final inverterHeight = (contentHeight - 28) * 2 / totalFlex;
    final totalBatteryHeight = (contentHeight - 28) * batteryFlex / totalFlex;
    final inverterBottom = paddingTop + inverterHeight;
    final inverterCenter = paddingTop + inverterHeight / 2;

    // Battery container top edge (inverter→battery line) and vertical center
    // (source↔battery / battery↔load lines).
    final firstBatteryTop = inverterBottom + 28;
    final batteryAreaCenter = firstBatteryTop + totalBatteryHeight / 2;

    final midX = leftColRight + gap / 2;

    // Draw source flows
    int lineIndex = 0;
    for (int i = 0; i < sourceCount; i++) {
      final flow = i < sourceFlows.length ? sourceFlows[i] : 0.0;
      final isActive = flow > 0.1;
      final phaseOffset = lineIndex * 0.17;
      lineIndex++;

      if (i == 0) {
        // First source goes to inverter
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
        // Other sources go to battery area center
        final yOffset = (i - 1) * 10.0 - 5;
        _drawAnimatedPath(
          canvas,
          [
            Offset(leftColRight, sourceRowCenters[i]),
            Offset(midX, sourceRowCenters[i]),
            Offset(midX, batteryAreaCenter + yOffset),
            Offset(centerColLeft, batteryAreaCenter + yOffset),
          ],
          isActive,
          flow,
          inactivePaint,
          true,
          phaseOffset: phaseOffset,
        );
      }
    }

    // Inverter to/from battery area (vertical)
    final primaryCurrent = batteryCurrents.isNotEmpty ? batteryCurrents[0] : 0.0;
    final primaryCharging = primaryCurrent > 0;
    final primaryDischarging = primaryCurrent < 0;
    _drawAnimatedLine(
      canvas,
      Offset((centerColLeft + centerColRight) / 2, inverterBottom),
      Offset((centerColLeft + centerColRight) / 2, firstBatteryTop),
      primaryCharging || primaryDischarging,
      primaryCurrent.abs(),
      inactivePaint,
      primaryCharging,
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
        // First load from inverter
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
        // Other loads from battery area center
        final yOffset = (i - 1) * 10.0 - 5;
        _drawAnimatedPath(
          canvas,
          [
            Offset(centerColRight, batteryAreaCenter + yOffset),
            Offset(midXRight, batteryAreaCenter + yOffset),
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
  List<String> requiredPaths(ToolConfig config) => victronRequiredPaths(config);

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
        allowsDataSources: false,
        allowsUnitSelection: false,
        allowsVisibilityToggles: false,
        allowsTTL: false,
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
          'batteries': [
            {
              'name': 'House',
              'socPath': 'electrical.batteries.house.capacity.stateOfCharge',
              'voltagePath': 'electrical.batteries.house.voltage',
              'currentPath': 'electrical.batteries.house.current',
              'powerPath': 'electrical.batteries.house.power',
              'timeRemainingPath': 'electrical.batteries.house.capacity.timeRemaining',
              'temperaturePath': 'electrical.batteries.house.temperature',
            },
          ],
        },
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return VictronFlowTool(config: config, signalKService: signalKService);
  }
}
