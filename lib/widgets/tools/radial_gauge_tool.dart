import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/string_extensions.dart';
import '../../utils/color_extensions.dart';
import 'mixins/zones_mixin.dart';
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

class _RadialGaugeToolState extends State<RadialGaugeTool> with ZonesMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.config.dataSources.isNotEmpty) {
      initializeZones(widget.signalKService, widget.config.dataSources.first.path);
    }
  }

  @override
  void dispose() {
    cleanupZones(widget.signalKService);
    super.dispose();
  }

  /// Helper to get raw SI value from a data point
  double? _getRawValue(String path) {
    final dataPoint = widget.signalKService.getValue(path);
    if (dataPoint?.original is num) {
      return (dataPoint!.original as num).toDouble();
    }
    if (dataPoint?.value is num) {
      return (dataPoint!.value as num).toDouble();
    }
    return null;
  }

  /// Helper to get converted display value using MetadataStore
  double? _getConverted(String path, double? rawValue) {
    if (rawValue == null) return null;
    final metadata = widget.signalKService.metadataStore.get(path);
    return metadata?.convert(rawValue) ?? rawValue;
  }

  /// Helper to format value with symbol using MetadataStore
  String? _formatValue(String path, double? rawValue) {
    if (rawValue == null) return null;
    final metadata = widget.signalKService.metadataStore.get(path);
    return metadata?.format(rawValue, decimals: 1) ?? rawValue.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Get data from first data source
    if (widget.config.dataSources.isEmpty) {
      return const Center(child: Text('No data source configured'));
    }

    final dataSource = widget.config.dataSources.first;

    // Use MetadataStore for conversions
    final rawValue = _getRawValue(dataSource.path);
    final value = _getConverted(dataSource.path, rawValue) ?? 0.0;

    // Get style configuration
    final style = widget.config.style;
    final minValue = style.minValue ?? 0.0;
    final maxValue = style.maxValue ?? 100.0;

    // Get label from data source or style
    final label = dataSource.label ?? dataSource.path.toReadableLabel();

    // Get formatted value using MetadataStore
    final formattedValue = _formatValue(dataSource.path, rawValue);

    // Get unit symbol from MetadataStore (prefer style override, fallback to metadata symbol)
    final metadata = widget.signalKService.metadataStore.get(dataSource.path);
    final unit = style.unit ?? metadata?.symbol ?? '';

    // Parse color from hex string
    final primaryColor = style.primaryColor?.toColor(
      fallback: Colors.blue
    ) ?? Colors.blue;

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
      zones: zones,
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

}

/// Builder for radial gauge tools
class RadialGaugeBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'radial_gauge',
      name: 'Radial Gauge',
      description: 'Circular gauge with arc display for numeric values',
      category: ToolCategory.instruments,
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
