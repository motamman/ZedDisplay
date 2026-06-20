import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../models/path_metadata.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../radial_bar_chart.dart';
import '../../utils/string_extensions.dart';
import '../../utils/color_extensions.dart';
import '../common/widget_empty_states.dart';

/// Config-driven radial bar chart tool.
/// Displays up to 4 SignalK paths as concentric rings on an [SfRadialGauge].
class RadialBarChartTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const RadialBarChartTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<RadialBarChartTool> createState() => _RadialBarChartToolState();
}

class _RadialBarChartToolState extends State<RadialBarChartTool>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  /// Raw SI value for a data source, preferring the unconverted [original].
  double? _getRawValue(DataSource ds) {
    final dataPoint = ds.resolve(widget.signalKService);
    if (dataPoint?.original is num) {
      return (dataPoint!.original as num).toDouble();
    }
    if (dataPoint?.value is num) {
      return (dataPoint!.value as num).toDouble();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!widget.signalKService.isConnected) {
      return const WidgetDisconnectedState();
    }

    if (widget.config.dataSources.isEmpty) {
      return const WidgetEmptyState(message: 'No data sources configured');
    }

    final style = widget.config.style;
    final showValue = style.showValue ?? true;
    final showUnit = style.showUnit ?? true;
    final showLegend = style.showLabel ?? true;

    final globalMin = style.minValue ?? 0.0;
    final globalMax = style.maxValue ?? 100.0;

    final colors = _buildPalette(
      style.primaryColor?.toColor(),
      widget.config.dataSources.length,
    );

    final segments = <RadialBarSegment>[];
    for (int i = 0; i < widget.config.dataSources.length; i++) {
      final ds = widget.config.dataSources[i];
      final metadata = widget.signalKService.metadataStore.get(ds.path);

      final rawValue = _getRawValue(ds);
      final isFresh = ds.isFresh(widget.signalKService, ttlSeconds: style.ttlSeconds);
      final hasData = isFresh && rawValue != null;

      // Per-path max override (whole numbers arrive as int from JSON).
      final pathMax = (style.customProperties?['maxValue_${ds.path}'] as num?)
          ?.toDouble();
      final minValue = globalMin;
      final maxValue = pathMax ?? globalMax;

      final displayValue =
          hasData ? (metadata?.convert(rawValue) ?? rawValue) : minValue;

      final valueText = hasData
          ? (showUnit
              ? metadata.formatOrRaw(rawValue, decimals: 1)
              : (metadata?.convert(rawValue) ?? rawValue).toStringAsFixed(1))
          : '--';

      segments.add(
        RadialBarSegment(
          label: ds.label ?? ds.path.toReadableLabel(),
          value: displayValue,
          minValue: minValue,
          maxValue: maxValue,
          valueText: valueText,
          color: colors[i % colors.length],
          hasData: hasData,
        ),
      );
    }

    final props = style.customProperties;
    final title = props?['title'] as String? ?? '';
    final showTicks = props?['showTicks'] as bool? ?? false;
    final divisions = props?['divisions'] as int? ?? 10;
    final innerRadius = (props?['innerRadius'] as num?)?.toDouble() ?? 0.35;
    final gap = (props?['gap'] as num?)?.toDouble() ?? 0.04;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: RadialBarChart(
          segments: segments,
          title: title.isNotEmpty ? title : null,
          showValues: showValue,
          showLegend: showLegend,
          showTicks: showTicks,
          divisions: divisions,
          innerRadius: innerRadius,
          gap: gap,
        ),
      ),
    );
  }

  /// Generate [count] cohesive colour variants spanning the rings, faintest
  /// on the outermost ring (index 0) and most saturated on the innermost.
  List<Color> _buildPalette(Color? primaryColor, int count) {
    final baseColor = primaryColor ?? Colors.blue;
    final n = count > 0 ? count : 1;
    return List.generate(n, (index) => _createColorVariant(baseColor, index, n));
  }

  Color _createColorVariant(Color baseColor, int index, int total) {
    final hslColor = HSLColor.fromColor(baseColor);

    // position: 1.0 on the outer ring (faint) -> 0.0 on the inner ring (full
    // strength). A single ring stays at full strength.
    final position = total <= 1 ? 0.0 : 1 - (index / (total - 1));

    const lightnessRange = 0.3;
    const saturationRange = 0.2;

    final baseLightness = hslColor.lightness;
    final targetLightness = baseLightness < 0.5
        ? baseLightness + (lightnessRange * position)
        : baseLightness - (lightnessRange * (1 - position));

    final targetSaturation =
        (hslColor.saturation - (saturationRange * position)).clamp(0.3, 1.0);

    return hslColor
        .withLightness(targetLightness.clamp(0.2, 0.8))
        .withSaturation(targetSaturation)
        .toColor();
  }
}

/// Builder for radial bar chart tools
class RadialBarChartBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'radial_bar_chart',
      name: 'Radial Bar Chart',
      description: 'Concentric gauge rings displaying up to 4 values',
      category: ToolCategory.instruments,
      configSchema: ConfigSchema(
        allowsMinMax: true,
        allowsColorCustomization: true,
        allowsMultiplePaths: true,
        minPaths: 1,
        maxPaths: 4,
        styleOptions: const [
          'minValue',
          'maxValue',
          'primaryColor',
          'showValue', // toggle value labels
          'showLabel', // toggle legend
          'showUnit', // append unit symbol to values
          'title',
          'showTicks',
          'divisions',
          'innerRadius',
          'gap',
        ],
        allowsUnitSelection: false,
        allowsVisibilityToggles: true,
        allowsTTL: true,
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return RadialBarChartTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
