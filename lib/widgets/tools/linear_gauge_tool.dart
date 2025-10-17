import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';

/// Available linear gauge styles
enum LinearGaugeStyle {
  bar,        // Filled bar (default)
  thermometer, // Thermometer style
  step,       // Stepped/segmented
  bullet,     // Bullet chart style
}

/// Config-driven linear (bar) gauge powered by Syncfusion
class LinearGaugeTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const LinearGaugeTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  Widget build(BuildContext context) {
    // Get data from first data source
    if (config.dataSources.isEmpty) {
      return const Center(child: Text('No data source configured'));
    }

    final dataSource = config.dataSources.first;
    final dataPoint = signalKService.getValue(dataSource.path);
    final value = signalKService.getConvertedValue(dataSource.path) ?? 0.0;

    // Get style configuration
    final style = config.style;
    final minValue = style.minValue ?? 0.0;
    final maxValue = style.maxValue ?? 100.0;

    // Get label from data source or derive from path
    final label = dataSource.label ?? _getDefaultLabel(dataSource.path);

    // Get formatted value from plugin if available
    final formattedValue = dataPoint?.formatted;

    // Get unit (prefer style override, fallback to server's unit)
    final unit = style.unit ??
                signalKService.getUnitSymbol(dataSource.path) ??
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

    // Get orientation, style variant, tick labels, and pointer mode from custom properties
    final isVertical = style.customProperties?['orientation'] == 'vertical';
    final gaugeStyleStr = style.customProperties?['gaugeStyle'] as String? ?? 'bar';
    final gaugeStyle = _parseGaugeStyle(gaugeStyleStr);
    final showTickLabels = style.customProperties?['showTickLabels'] as bool? ?? false;
    final divisions = style.customProperties?['divisions'] as int? ?? 10;
    final pointerOnly = style.customProperties?['pointerOnly'] as bool? ?? false;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: !isVertical
          ? _buildHorizontalGauge(
              context,
              value,
              minValue,
              maxValue,
              label,
              unit,
              formattedValue,
              primaryColor,
              style,
              gaugeStyle,
              showTickLabels,
              divisions,
              pointerOnly,
            )
          : _buildVerticalGauge(
              context,
              value,
              minValue,
              maxValue,
              label,
              unit,
              formattedValue,
              primaryColor,
              style,
              gaugeStyle,
              showTickLabels,
              divisions,
              pointerOnly,
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
    String unit,
    String? formattedValue,
    Color primaryColor,
    StyleConfig style,
    LinearGaugeStyle gaugeStyle,
    bool showTickLabels,
    int divisions,
    bool pointerOnly,
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

            // Range pointers for step style (hidden in pointer-only mode)
            ranges: (gaugeStyle == LinearGaugeStyle.step && !pointerOnly)
                ? _getStepRanges(value, minValue, maxValue, primaryColor, divisions)
                : null,

            // Marker pointers - always show in pointer-only mode
            markerPointers: _getMarkerPointers(
              value,
              formattedValue,
              unit,
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
    String unit,
    String? formattedValue,
    Color primaryColor,
    StyleConfig style,
    LinearGaugeStyle gaugeStyle,
    bool showTickLabels,
    int divisions,
    bool pointerOnly,
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

                  // Range pointers for step style (hidden in pointer-only mode)
                  ranges: (gaugeStyle == LinearGaugeStyle.step && !pointerOnly)
                      ? _getStepRanges(value, minValue, maxValue, primaryColor, divisions)
                      : null,

                  // Marker pointers - always show in pointer-only mode
                  markerPointers: _getMarkerPointers(
                    value,
                    formattedValue,
                    unit,
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
    String unit,
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

    // Value label
    if (style.showValue == true) {
      pointers.add(
        LinearWidgetPointer(
          value: anchorValue,
          position: LinearElementPosition.outside,
          offset: 15,
          child: Text(
            formattedValue ?? '${value.toStringAsFixed(1)} ${style.showUnit == true ? unit : ''}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return pointers.isEmpty ? null : pointers;
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

/// Builder for linear gauge tools
class LinearGaugeBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'linear_gauge',
      name: 'Linear Gauge',
      description: 'Horizontal or vertical bar gauge for numeric values',
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
