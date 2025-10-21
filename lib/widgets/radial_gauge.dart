import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import '../models/zone_data.dart';

/// Available radial gauge arc styles
enum RadialGaugeStyle {
  arc,          // 270 degree arc (default)
  full,         // 360 degree full circle
  half,         // 180 degree semicircle
  threequarter, // 270 degrees from bottom
}

/// A customizable radial gauge widget for displaying numeric values
/// Now powered by Syncfusion for professional appearance
class RadialGauge extends StatelessWidget {
  final double value;
  final double minValue;
  final double maxValue;
  final String label;
  final String unit;
  final String? formattedValue; // Pre-formatted value like "12.6 kn"
  final Color primaryColor;
  final Color backgroundColor;
  final int divisions;
  final bool showTickLabels;
  final RadialGaugeStyle gaugeStyle;
  final bool pointerOnly; // Show only pointer, no filled arc
  final bool showValue; // Show/hide the value display
  final List<ZoneDefinition>? zones;
  final bool showZones;

  const RadialGauge({
    super.key,
    required this.value,
    this.minValue = 0,
    this.maxValue = 100,
    this.label = '',
    this.unit = '',
    this.formattedValue,
    this.primaryColor = Colors.blue,
    this.backgroundColor = Colors.grey,
    this.divisions = 10,
    this.showTickLabels = false,
    this.gaugeStyle = RadialGaugeStyle.arc,
    this.pointerOnly = false,
    this.showValue = true,
    this.zones,
    this.showZones = true,
  });

  @override
  Widget build(BuildContext context) {
    // Clamp value to valid range
    final clampedValue = value.clamp(minValue, maxValue);

    // Get start/end angles based on style
    final angles = _getAngles(gaugeStyle);

    return AspectRatio(
      aspectRatio: 1,
      child: SfRadialGauge(
        axes: <RadialAxis>[
          RadialAxis(
            minimum: minValue,
            maximum: maxValue,
            interval: (maxValue - minValue) / divisions,

            // Arc styling
            startAngle: angles.startAngle,
            endAngle: angles.endAngle,

            // Hide axis line (we use ranges for the arc)
            showAxisLine: false,

            // Tick styling
            majorTickStyle: MajorTickStyle(
              length: showTickLabels ? 12 : 8,
              thickness: 2,
              color: Colors.grey.withValues(alpha: 0.6),
            ),
            minorTicksPerInterval: 4,
            minorTickStyle: MinorTickStyle(
              length: 4,
              thickness: 1,
              color: Colors.grey.withValues(alpha: 0.3),
            ),

            // Tick labels
            showLabels: showTickLabels,
            axisLabelStyle: GaugeTextStyle(
              color: Colors.grey.withValues(alpha: 0.8),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
            labelOffset: 15,

            // Ranges for background, value arcs, and zones
            ranges: pointerOnly
                ? <GaugeRange>[
                    // Only background arc when pointer-only mode
                    GaugeRange(
                      startValue: minValue,
                      endValue: maxValue,
                      color: backgroundColor.withValues(alpha: 0.2),
                      startWidth: 15,
                      endWidth: 15,
                    ),
                    // Zone ranges (inside, 1/3 thickness)
                    ..._buildZoneRanges(),
                  ]
                : <GaugeRange>[
                    // Background arc
                    GaugeRange(
                      startValue: minValue,
                      endValue: maxValue,
                      color: backgroundColor.withValues(alpha: 0.2),
                      startWidth: 15,
                      endWidth: 15,
                    ),
                    // Value arc with gradient
                    GaugeRange(
                      startValue: minValue,
                      endValue: clampedValue,
                      gradient: SweepGradient(
                        colors: [
                          primaryColor,
                          primaryColor.withValues(alpha: 0.6),
                        ],
                        stops: const [0.0, 1.0],
                      ),
                      startWidth: 15,
                      endWidth: 15,
                    ),
                    // Zone ranges (inside, 1/3 thickness)
                    ..._buildZoneRanges(),
                  ],

            // Pointer - show for full circle style OR pointer-only mode
            pointers: (gaugeStyle == RadialGaugeStyle.full || pointerOnly)
                ? <GaugePointer>[
                    NeedlePointer(
                      value: clampedValue,
                      needleLength: 0.7,
                      needleStartWidth: 0,
                      needleEndWidth: 8,
                      needleColor: primaryColor,
                      knobStyle: KnobStyle(
                        knobRadius: 0.08,
                        color: primaryColor,
                        borderColor: primaryColor,
                        borderWidth: 0.02,
                      ),
                    ),
                  ]
                : null,

            // Center annotation with value display
            annotations: <GaugeAnnotation>[
              GaugeAnnotation(
                widget: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (label.isNotEmpty)
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    if (label.isNotEmpty && showValue) const SizedBox(height: 4),
                    if (showValue)
                      Text(
                        formattedValue ?? '${value.toStringAsFixed(1)}${unit.isNotEmpty ? " $unit" : ""}',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                angle: 90,
                positionFactor: gaugeStyle == RadialGaugeStyle.half ? 0.3 : 0.0,
              ),
            ],
          ),
        ],
      ),
    );
  }

  ({double startAngle, double endAngle}) _getAngles(RadialGaugeStyle style) {
    switch (style) {
      case RadialGaugeStyle.full:
        return (startAngle: 270, endAngle: 270); // Full circle
      case RadialGaugeStyle.half:
        return (startAngle: 180, endAngle: 0); // Bottom semicircle
      case RadialGaugeStyle.threequarter:
        return (startAngle: 180, endAngle: 90); // 270 degrees from bottom
      case RadialGaugeStyle.arc:
      default:
        return (startAngle: 135, endAngle: 45); // 270 degree arc
    }
  }

  /// Build zone ranges for the gauge (positioned inside data bar, 1/3 thickness)
  List<GaugeRange> _buildZoneRanges() {
    if (!showZones || zones == null || zones!.isEmpty) {
      return [];
    }

    return zones!.map((zone) {
      final lower = zone.lower ?? minValue;
      final upper = zone.upper ?? maxValue;

      return GaugeRange(
        startValue: lower.clamp(minValue, maxValue),
        endValue: upper.clamp(minValue, maxValue),
        color: _getZoneColor(zone.state),
        startWidth: 5, // 1/3 of data bar thickness (15)
        endWidth: 5,
        sizeUnit: GaugeSizeUnit.logicalPixel,
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
}
