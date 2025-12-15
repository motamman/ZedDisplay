import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/string_extensions.dart';
import '../../utils/color_extensions.dart';
import '../../utils/conversion_utils.dart';
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

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Get data from first data source
    if (widget.config.dataSources.isEmpty) {
      return const Center(child: Text('No data source configured'));
    }

    final dataSource = widget.config.dataSources.first;

    // Use client-side conversions
    final rawValue = ConversionUtils.getRawValue(widget.signalKService, dataSource.path);
    final value = ConversionUtils.getConvertedValue(widget.signalKService, dataSource.path) ?? 0.0;

    // Get style configuration
    final style = widget.config.style;
    final minValue = style.minValue ?? 0.0;
    final maxValue = style.maxValue ?? 100.0;

    // Get label from data source or style
    final label = dataSource.label ?? dataSource.path.toReadableLabel();

    // Get formatted value using client-side conversion
    String? formattedValue;
    if (rawValue != null) {
      formattedValue = ConversionUtils.formatValue(
        widget.signalKService,
        dataSource.path,
        rawValue,
        decimalPlaces: 1,
      );
    }

    // Get unit symbol from conversion info
    final availableUnits = widget.signalKService.getAvailableUnits(dataSource.path);
    final conversionInfo = availableUnits.isNotEmpty
        ? widget.signalKService.getConversionInfo(dataSource.path, availableUnits.first)
        : null;

    // Get unit (prefer style override, fallback to conversion symbol)
    final unit = style.unit ?? conversionInfo?.symbol ?? '';

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
