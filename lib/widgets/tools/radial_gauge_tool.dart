import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../models/zone_data.dart';
import '../../services/signalk_service.dart';
import '../../services/zones_service.dart';
import '../../services/tool_registry.dart';
import '../radial_gauge.dart';

/// Config-driven radial gauge tool
class RadialGaugeTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const RadialGaugeTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<RadialGaugeTool> createState() => _RadialGaugeToolState();
}

class _RadialGaugeToolState extends State<RadialGaugeTool> {
  ZonesService? _zonesService;
  List<ZoneDefinition>? _zones;

  @override
  void initState() {
    super.initState();
    _initializeZonesService();
  }

  void _initializeZonesService() {
    if (widget.signalKService.isConnected) {
      _createZonesServiceAndFetch();
    } else {
      widget.signalKService.addListener(_onSignalKConnectionChanged);
    }
  }

  void _onSignalKConnectionChanged() {
    if (widget.signalKService.isConnected && _zonesService == null) {
      widget.signalKService.removeListener(_onSignalKConnectionChanged);
      _createZonesServiceAndFetch();
    }
  }

  void _createZonesServiceAndFetch() {
    _zonesService = ZonesService(
      serverUrl: widget.signalKService.serverUrl,
      useSecureConnection: widget.signalKService.useSecureConnection,
    );
    _fetchZones();
  }

  Future<void> _fetchZones() async {
    if (_zonesService == null || widget.config.dataSources.isEmpty) {
      return;
    }

    try {
      final firstPath = widget.config.dataSources.first.path;
      final pathZones = await _zonesService!.fetchZones(firstPath);

      if (mounted && pathZones != null && pathZones.hasZones) {
        setState(() {
          _zones = pathZones.zones;
        });
      }
    } catch (e) {
      // Silently fail - zones are optional
      if (kDebugMode) {
        print('Failed to fetch zones for radial gauge: $e');
      }
    }
  }

  @override
  void dispose() {
    widget.signalKService.removeListener(_onSignalKConnectionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get data from first data source
    if (widget.config.dataSources.isEmpty) {
      return const Center(child: Text('No data source configured'));
    }

    final dataSource = widget.config.dataSources.first;
    final dataPoint = widget.signalKService.getValue(dataSource.path);
    final value = widget.signalKService.getConvertedValue(dataSource.path) ?? 0.0;

    // Get style configuration
    final style = widget.config.style;
    final minValue = style.minValue ?? 0.0;
    final maxValue = style.maxValue ?? 100.0;

    // Get label from data source or style
    final label = dataSource.label ?? _getDefaultLabel(dataSource.path);

    // Get formatted value from plugin if available
    final formattedValue = dataPoint?.formatted;

    // Get unit (prefer style override, fallback to server's unit)
    // Only used if no formatted value
    final unit = style.unit ??
                 widget.signalKService.getUnitSymbol(dataSource.path) ??
                 '';

    // Parse color from hex string
    Color primaryColor = Colors.blue;
    if (style.primaryColor != null) {
      try {
        final colorString = style.primaryColor!.replaceAll('#', '');
        primaryColor = Color(int.parse('FF$colorString', radix: 16));
      } catch (e) {
        // Keep default color if parsing fails
      }
    }

    // Get divisions, tick labels, gauge style, and pointer mode from custom properties
    final divisions = style.customProperties?['divisions'] as int? ?? 10;
    final showTickLabels = style.customProperties?['showTickLabels'] as bool? ?? false;
    final gaugeStyleStr = style.customProperties?['gaugeStyle'] as String? ?? 'arc';
    final gaugeStyle = _parseGaugeStyle(gaugeStyleStr);
    final pointerOnly = style.customProperties?['pointerOnly'] as bool? ?? false;
    final showZones = style.customProperties?['showZones'] as bool? ?? true;

    return RadialGauge(
      value: value,
      minValue: minValue,
      maxValue: maxValue,
      label: style.showLabel == true ? label : '',
      unit: style.showUnit == true ? unit : '',
      formattedValue: formattedValue,
      primaryColor: primaryColor,
      divisions: divisions,
      showTickLabels: showTickLabels,
      gaugeStyle: gaugeStyle,
      pointerOnly: pointerOnly,
      showValue: style.showValue ?? true,
      zones: _zones,
      showZones: showZones,
    );
  }

  RadialGaugeStyle _parseGaugeStyle(String styleStr) {
    switch (styleStr.toLowerCase()) {
      case 'full':
        return RadialGaugeStyle.full;
      case 'half':
        return RadialGaugeStyle.half;
      case 'threequarter':
        return RadialGaugeStyle.threequarter;
      default:
        return RadialGaugeStyle.arc;
    }
  }

  /// Extract a readable label from the path
  String _getDefaultLabel(String path) {
    final parts = path.split('.');
    if (parts.isEmpty) return path;

    // Get the last part and make it readable
    final lastPart = parts.last;

    // Convert camelCase to Title Case
    final result = lastPart.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)}',
    ).trim();

    return result.isEmpty ? lastPart : result;
  }
}

/// Builder for radial gauge tools
class RadialGaugeBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'radial_gauge',
      name: 'Radial Gauge',
      description: 'Circular gauge with arc display for numeric values',
      category: ToolCategory.gauge,
      configSchema: ConfigSchema(
        allowsMinMax: true,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 1,
        maxPaths: 1,
        styleOptions: const [
          'minValue',
          'maxValue',
          'unit',
          'primaryColor',
          'showLabel',
          'showValue',
          'showUnit',
          'gaugeStyle', // 'arc', 'full', 'half', 'threequarter'
        ],
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return RadialGaugeTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
