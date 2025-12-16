import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../models/zone_data.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/string_extensions.dart';
import '../../utils/color_extensions.dart';
import '../../utils/conversion_utils.dart';
import 'mixins/zones_mixin.dart';

/// Available linear gauge styles
enum LinearGaugeStyle {
  bar,        // Filled bar (default)
  thermometer, // Thermometer style
  step,       // Stepped/segmented
  bullet,     // Bullet chart style
}

/// Config-driven linear (bar) gauge powered by Syncfusion
class LinearGaugeTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const LinearGaugeTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<LinearGaugeTool> createState() => _LinearGaugeToolState();
}

class _LinearGaugeToolState extends State<LinearGaugeTool> with ZonesMixin, AutomaticKeepAliveClientMixin {
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
    final style = widget.config.style;

    // Use client-side conversions
    final rawSIValue = ConversionUtils.getRawValue(widget.signalKService, dataSource.path);
    final convertedValue = ConversionUtils.getConvertedValue(widget.signalKService, dataSource.path);

    // Get style configuration
    final minValue = style.minValue ?? 0.0;
    final maxValue = style.maxValue ?? 100.0;

    // Check if data is fresh (within TTL threshold)
    final isDataFresh = widget.signalKService.isDataFresh(
      dataSource.path,
      source: dataSource.source,
      ttlSeconds: style.ttlSeconds,
    );

    // If data is stale, show minimum value and "--" text
    final value = isDataFresh ? (convertedValue ?? 0.0) : minValue;

    // Get label from data source or derive from path
    final label = dataSource.label ?? dataSource.path.toReadableLabel();

    // Check if we should show the unit
    final showUnit = style.showUnit ?? true;

    // Get formatted value using client-side conversion, or show "--" if stale
    String? formattedValue;
    if (isDataFresh && rawSIValue != null) {
      formattedValue = ConversionUtils.formatValue(
        widget.signalKService,
        dataSource.path,
        rawSIValue,
        decimalPlaces: 1,
        includeUnit: showUnit,
      );
    } else {
      formattedValue = '--';
    }


    // Parse color from hex string
    final primaryColor = style.primaryColor?.toColor(
      fallback: Colors.blue
    ) ?? Colors.blue;

    // Get orientation, style variant, tick labels, and pointer mode from custom properties
    final isVertical = style.customProperties?['orientation'] == 'vertical';
    final gaugeStyleStr = style.customProperties?['gaugeStyle'] as String? ?? 'bar';
    final gaugeStyle = _parseGaugeStyle(gaugeStyleStr);
    final showTickLabels = style.customProperties?['showTickLabels'] as bool? ?? false;
    final divisions = style.customProperties?['divisions'] as int? ?? 10;
    final pointerOnly = style.customProperties?['pointerOnly'] as bool? ?? false;
    final showZones = style.customProperties?['showZones'] as bool? ?? true;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: !isVertical
          ? _buildHorizontalGauge(
              context,
              value,
              minValue,
              maxValue,
              label,
              formattedValue,
              primaryColor,
              style,
              gaugeStyle,
              showTickLabels,
              divisions,
              pointerOnly,
              zones,
              showZones,
            )
          : _buildVerticalGauge(
              context,
              value,
              minValue,
              maxValue,
              label,
              formattedValue,
              primaryColor,
              style,
              gaugeStyle,
              showTickLabels,
              divisions,
              pointerOnly,
              zones,
              showZones,
            ),
    );
  }

  LinearGaugeStyle _parseGaugeStyle(String styleStr) {
    switch (styleStr.toLowerCase()) {
      case 'thermometer':
        return LinearGaugeStyle.thermometer;
      case 'step':
        return LinearGaugeStyle.step;
      case 'bullet':
        return LinearGaugeStyle.bullet;
      default:
        return LinearGaugeStyle.bar;
    }
  }

  Widget _buildHorizontalGauge(
    BuildContext context,
    double value,
    double minValue,
    double maxValue,
    String label,
    String? formattedValue,
    Color primaryColor,
    StyleConfig style,
    LinearGaugeStyle gaugeStyle,
    bool showTickLabels,
    int divisions,
    bool pointerOnly,
    List<ZoneDefinition>? zones,
    bool showZones,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (style.showLabel == true && label.isNotEmpty)
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        if (style.showLabel == true && label.isNotEmpty) const SizedBox(height: 8),
        Expanded(
          child: SfLinearGauge(
            minimum: minValue,
            maximum: maxValue,
            interval: (maxValue - minValue) / divisions,

            // Axis styling
            showTicks: showTickLabels,
            showLabels: showTickLabels,
            axisLabelStyle: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
            ),
            axisTrackStyle: LinearAxisTrackStyle(
              thickness: _getTrackThickness(gaugeStyle),
              edgeStyle: _getEdgeStyle(gaugeStyle),
              borderWidth: 1,
              borderColor: Colors.grey.withValues(alpha: 0.3),
              color: Colors.grey.withValues(alpha: 0.2),
            ),

            // Bar or range pointers based on style (hidden in pointer-only mode)
            barPointers: pointerOnly ? null : _getBarPointers(
              value,
              minValue,
              maxValue,
              primaryColor,
              gaugeStyle,
            ),

            // Ranges for step style and zones
            ranges: _buildAllRanges(
              gaugeStyle,
              pointerOnly,
              value,
              minValue,
              maxValue,
              primaryColor,
              divisions,
              zones,
              showZones,
            ),

            // Marker pointers - always show in pointer-only mode
            markerPointers: _getMarkerPointers(
              value,
              formattedValue,
              primaryColor,
              style,
              gaugeStyle,
              maxValue,
              pointerOnly,
              false, // isVertical
              _getTrackThickness(gaugeStyle),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalGauge(
    BuildContext context,
    double value,
    double minValue,
    double maxValue,
    String label,
    String? formattedValue,
    Color primaryColor,
    StyleConfig style,
    LinearGaugeStyle gaugeStyle,
    bool showTickLabels,
    int divisions,
    bool pointerOnly,
    List<ZoneDefinition>? zones,
    bool showZones,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (style.showLabel == true && label.isNotEmpty)
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              if (style.showLabel == true && label.isNotEmpty) const SizedBox(height: 8),
              Expanded(
                child: SfLinearGauge(
                  minimum: minValue,
                  maximum: maxValue,
                  interval: (maxValue - minValue) / divisions,
                  orientation: LinearGaugeOrientation.vertical,

                  // Axis styling
                  showTicks: showTickLabels,
                  showLabels: showTickLabels,
                  axisLabelStyle: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                  ),
                  axisTrackStyle: LinearAxisTrackStyle(
                    thickness: _getTrackThickness(gaugeStyle),
                    edgeStyle: _getEdgeStyle(gaugeStyle),
                    borderWidth: 1,
                    borderColor: Colors.grey.withValues(alpha: 0.3),
                    color: Colors.grey.withValues(alpha: 0.2),
                  ),

                  // Bar or range pointers based on style (hidden in pointer-only mode)
                  barPointers: pointerOnly ? null : _getBarPointers(
                    value,
                    minValue,
                    maxValue,
                    primaryColor,
                    gaugeStyle,
                  ),

                  // Ranges for step style and zones
                  ranges: _buildAllRanges(
                    gaugeStyle,
                    pointerOnly,
                    value,
                    minValue,
                    maxValue,
                    primaryColor,
                    divisions,
                    zones,
                    showZones,
                  ),

                  // Marker pointers - always show in pointer-only mode
                  markerPointers: _getMarkerPointers(
                    value,
                    formattedValue,
                    primaryColor,
                    style,
                    gaugeStyle,
                    minValue,
                    pointerOnly,
                    true, // isVertical
                    _getTrackThickness(gaugeStyle),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  double _getTrackThickness(LinearGaugeStyle gaugeStyle) {
    switch (gaugeStyle) {
      case LinearGaugeStyle.thermometer:
        return 50;
      case LinearGaugeStyle.bullet:
        return 30;
      case LinearGaugeStyle.step:
        return 40;
      default:
        return 40;
    }
  }

  LinearEdgeStyle _getEdgeStyle(LinearGaugeStyle gaugeStyle) {
    switch (gaugeStyle) {
      case LinearGaugeStyle.thermometer:
        return LinearEdgeStyle.endCurve;
      case LinearGaugeStyle.step:
        return LinearEdgeStyle.bothFlat;
      default:
        return LinearEdgeStyle.bothCurve;
    }
  }

  List<LinearBarPointer>? _getBarPointers(
    double value,
    double minValue,
    double maxValue,
    Color primaryColor,
    LinearGaugeStyle gaugeStyle,
  ) {
    if (gaugeStyle == LinearGaugeStyle.step) {
      return null; // Use ranges instead
    }

    if (gaugeStyle == LinearGaugeStyle.bullet) {
      // Bullet chart has thin background bar
      return [
        LinearBarPointer(
          value: value.clamp(minValue, maxValue),
          thickness: 15,
          edgeStyle: LinearEdgeStyle.bothCurve,
          color: primaryColor,
        ),
      ];
    }

    return [
      LinearBarPointer(
        value: value.clamp(minValue, maxValue),
        thickness: _getTrackThickness(gaugeStyle),
        edgeStyle: _getEdgeStyle(gaugeStyle),
        color: primaryColor,
      ),
    ];
  }

  List<LinearGaugeRange>? _getStepRanges(
    double value,
    double minValue,
    double maxValue,
    Color primaryColor,
    int divisions,
  ) {
    final ranges = <LinearGaugeRange>[];
    final stepSize = (maxValue - minValue) / divisions;

    for (int i = 0; i < divisions; i++) {
      final stepStart = minValue + (i * stepSize);
      final stepEnd = stepStart + stepSize;

      // Only fill up to current value
      if (value >= stepStart) {
        final endValue = value < stepEnd ? value : stepEnd;
        ranges.add(
          LinearGaugeRange(
            startValue: stepStart,
            endValue: endValue,
            color: primaryColor.withValues(alpha: 0.9 - (i * 0.05)),
            position: LinearElementPosition.cross,
            startWidth: 40,
            endWidth: 40,
          ),
        );
      }
    }

    return ranges;
  }

  List<LinearMarkerPointer>? _getMarkerPointers(
    double value,
    String? formattedValue,
    Color primaryColor,
    StyleConfig style,
    LinearGaugeStyle gaugeStyle,
    double anchorValue,
    bool pointerOnly,
    bool isVertical,
    double trackThickness,
  ) {
    final pointers = <LinearMarkerPointer>[];

    // Pointer-only mode OR bullet style needs a shape marker
    if (pointerOnly || gaugeStyle == LinearGaugeStyle.bullet) {
      // Size pointer relative to track thickness
      final pointerSize = trackThickness * 0.8;
      final offset = trackThickness * 0.75;

      pointers.add(
        LinearWidgetPointer(
          value: value.clamp(style.minValue ?? 0.0, style.maxValue ?? 100.0),
          position: LinearElementPosition.cross,
          offset: isVertical ? -offset : offset, // Left side for vertical (negative), below for horizontal
          child: CustomPaint(
            size: Size(pointerSize, pointerSize),
            painter: _TrianglePainter(
              color: primaryColor.withValues(alpha: 0.9),
              direction: isVertical ? AxisDirection.right : AxisDirection.down,
            ),
          ),
        ),
      );
    }

    // Value label - positioned at the bar level (like tanks tool)
    if (style.showValue == true) {
      final displayText = formattedValue ?? '--';
      final clampedValue = value.clamp(style.minValue ?? 0.0, style.maxValue ?? 100.0);

      pointers.add(
        LinearWidgetPointer(
          value: clampedValue,
          position: LinearElementPosition.inside,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              displayText,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _getContrastColor(primaryColor),
              ),
            ),
          ),
        ),
      );
    }

    return pointers.isEmpty ? null : pointers;
  }

  /// Build all ranges including step ranges and zone ranges
  List<LinearGaugeRange>? _buildAllRanges(
    LinearGaugeStyle gaugeStyle,
    bool pointerOnly,
    double value,
    double minValue,
    double maxValue,
    Color primaryColor,
    int divisions,
    List<ZoneDefinition>? zones,
    bool showZones,
  ) {
    final ranges = <LinearGaugeRange>[];

    // Add step ranges if applicable
    if (gaugeStyle == LinearGaugeStyle.step && !pointerOnly) {
      final stepRanges = _getStepRanges(value, minValue, maxValue, primaryColor, divisions);
      if (stepRanges != null) {
        ranges.addAll(stepRanges);
      }
    }

    // Add zone ranges
    if (showZones && zones != null && zones.isNotEmpty) {
      ranges.addAll(_buildZoneRanges(zones, minValue, maxValue));
    }

    return ranges.isEmpty ? null : ranges;
  }

  /// Build zone ranges for linear gauge (above ticks, below bar)
  List<LinearGaugeRange> _buildZoneRanges(
    List<ZoneDefinition> zones,
    double minValue,
    double maxValue,
  ) {
    return zones.map((zone) {
      final lower = zone.lower ?? minValue;
      final upper = zone.upper ?? maxValue;

      return LinearGaugeRange(
        startValue: lower.clamp(minValue, maxValue),
        endValue: upper.clamp(minValue, maxValue),
        color: _getZoneColor(zone.state),
        startWidth: 8,
        endWidth: 8,
        position: LinearElementPosition.inside, // Between ticks and bar
        rangeShapeType: LinearRangeShapeType.curve,
      );
    }).toList();
  }

  /// Get color for a zone state
  Color _getZoneColor(ZoneState state) {
    switch (state) {
      case ZoneState.nominal:
        return Colors.blue.withValues(alpha: 0.5);
      case ZoneState.alert:
        return Colors.yellow.shade600.withValues(alpha: 0.6);
      case ZoneState.warn:
        return Colors.orange.withValues(alpha: 0.6);
      case ZoneState.alarm:
        return Colors.red.withValues(alpha: 0.6);
      case ZoneState.emergency:
        return Colors.red.shade900.withValues(alpha: 0.6);
      case ZoneState.normal:
        return Colors.grey.withValues(alpha: 0.5);
    }
  }

  /// Get contrasting text color for readability on colored background
  Color _getContrastColor(Color color) {
    final luminance = color.computeLuminance();
    return luminance > 0.5 ? Colors.black87 : Colors.white;
  }
}

/// Builder for linear gauge tools
class LinearGaugeBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'linear_gauge',
      name: 'Linear Gauge',
      description: 'Horizontal or vertical bar gauge for numeric values',
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
          'orientation', // 'horizontal' or 'vertical'
          'gaugeStyle', // 'bar', 'thermometer', 'step', 'bullet'
        ],
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return LinearGaugeTool(
      config: config,
      signalKService: signalKService,
    );
  }
}

/// Custom painter for drawing a triangle pointer
class _TrianglePainter extends CustomPainter {
  final Color color;
  final AxisDirection direction;

  _TrianglePainter({required this.color, required this.direction});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();

    switch (direction) {
      case AxisDirection.down:
        // Triangle pointing down
        path.moveTo(size.width / 2, size.height); // Bottom center (tip)
        path.lineTo(0, 0); // Top left
        path.lineTo(size.width, 0); // Top right
        break;
      case AxisDirection.up:
        // Triangle pointing up
        path.moveTo(size.width / 2, 0); // Top center (tip)
        path.lineTo(0, size.height); // Bottom left
        path.lineTo(size.width, size.height); // Bottom right
        break;
      case AxisDirection.right:
        // Triangle pointing right
        path.moveTo(size.width, size.height / 2); // Right center (tip)
        path.lineTo(0, 0); // Top left
        path.lineTo(0, size.height); // Bottom left
        break;
      case AxisDirection.left:
        // Triangle pointing left
        path.moveTo(0, size.height / 2); // Left center (tip)
        path.lineTo(size.width, 0); // Top right
        path.lineTo(size.width, size.height); // Bottom right
        break;
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter oldDelegate) =>
      color != oldDelegate.color || direction != oldDelegate.direction;
}
