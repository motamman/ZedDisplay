import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

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
  });

  @override
  Widget build(BuildContext context) {
    // Clamp value to valid range
    final clampedValue = value.clamp(minValue, maxValue);

    return AspectRatio(
      aspectRatio: 1,
      child: SfRadialGauge(
        axes: <RadialAxis>[
          RadialAxis(
            minimum: minValue,
            maximum: maxValue,
            interval: (maxValue - minValue) / divisions,

            // Arc styling (270 degrees)
            startAngle: 135,
            endAngle: 45,

            // Hide axis line (we use ranges for the arc)
            showAxisLine: false,

            // Tick styling
            majorTickStyle: MajorTickStyle(
              length: showTickLabels ? 12 : 8,
              thickness: 2,
              color: Colors.grey.withOpacity(0.6),
            ),
            minorTicksPerInterval: 4,
            minorTickStyle: MinorTickStyle(
              length: 4,
              thickness: 1,
              color: Colors.grey.withOpacity(0.3),
            ),

            // Tick labels
            showLabels: showTickLabels,
            axisLabelStyle: GaugeTextStyle(
              color: Colors.grey.withOpacity(0.8),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
            labelOffset: 15,

            // Ranges for background and value arcs
            ranges: <GaugeRange>[
              // Background arc
              GaugeRange(
                startValue: minValue,
                endValue: maxValue,
                color: backgroundColor.withOpacity(0.2),
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
                    primaryColor.withOpacity(0.6),
                  ],
                  stops: const [0.0, 1.0],
                ),
                startWidth: 15,
                endWidth: 15,
              ),
            ],

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
                    if (label.isNotEmpty) const SizedBox(height: 4),
                    Text(
                      formattedValue ?? value.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // Only show unit if not using formatted value (which includes unit)
                    if (unit.isNotEmpty && formattedValue == null)
                      Text(
                        unit,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                  ],
                ),
                angle: 90,
                positionFactor: 0.0,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
