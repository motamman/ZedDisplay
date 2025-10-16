import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

/// Available compass display styles
enum CompassStyle {
  classic,  // Full circle with needle (default)
  arc,      // 180° arc showing heading range
  minimal,  // Clean modern with simplified markings
  rose,     // Traditional compass rose style
}

/// A compass widget for displaying heading/bearing
/// Now powered by Syncfusion for professional appearance
class CompassGauge extends StatelessWidget {
  final double heading; // In degrees (0-360)
  final String label;
  final String? formattedValue;
  final Color primaryColor;
  final bool showTickLabels;
  final CompassStyle compassStyle;

  const CompassGauge({
    super.key,
    required this.heading,
    this.label = 'Heading',
    this.formattedValue,
    this.primaryColor = Colors.red,
    this.showTickLabels = false,
    this.compassStyle = CompassStyle.classic,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: SfRadialGauge(
        axes: <RadialAxis>[
          RadialAxis(
            minimum: 0,
            maximum: 360,
            interval: _getInterval(),

            // Angles based on style
            startAngle: _getStartAngle(),
            endAngle: _getEndAngle(),

            // Hide axis line
            showAxisLine: false,
            showLastLabel: compassStyle != CompassStyle.arc,

            // Tick configuration
            majorTickStyle: MajorTickStyle(
              length: _getMajorTickLength(),
              thickness: compassStyle == CompassStyle.rose ? 3 : 2,
              color: compassStyle == CompassStyle.minimal
                  ? Colors.grey.withValues(alpha: 0.3)
                  : Colors.grey,
            ),
            minorTicksPerInterval: compassStyle == CompassStyle.minimal ? 0 : 2,
            minorTickStyle: MinorTickStyle(
              length: 6,
              thickness: 1,
              color: Colors.grey.withValues(alpha: 0.5),
            ),

            // Custom labels for cardinal directions
            axisLabelStyle: GaugeTextStyle(
              color: Colors.grey,
              fontSize: compassStyle == CompassStyle.rose ? 18 : 16,
              fontWeight: compassStyle == CompassStyle.rose
                  ? FontWeight.w900
                  : FontWeight.bold,
            ),
            labelOffset: compassStyle == CompassStyle.rose ? 25 : 20,
            onLabelCreated: (args) => _customizeLabel(args),

            // Outer ring for visual boundary
            ranges: _getRanges(),

            // Heading pointer
            pointers: _getPointers(),

            // Center annotation with heading value
            annotations: <GaugeAnnotation>[
              GaugeAnnotation(
                widget: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (compassStyle != CompassStyle.minimal)
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    if (compassStyle != CompassStyle.minimal) const SizedBox(height: 4),
                    Text(
                      formattedValue ?? '${heading.toStringAsFixed(0)}°',
                      style: TextStyle(
                        fontSize: compassStyle == CompassStyle.rose ? 36 : 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _getCardinalDirection(heading),
                      style: TextStyle(
                        fontSize: compassStyle == CompassStyle.rose ? 20 : 18,
                        fontWeight: FontWeight.w500,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
                angle: 90,
                positionFactor: compassStyle == CompassStyle.arc ? 0.3 : 0.1,
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _getStartAngle() {
    switch (compassStyle) {
      case CompassStyle.arc:
        return 180; // Bottom half
      default:
        return 270; // Top (north)
    }
  }

  double _getEndAngle() {
    switch (compassStyle) {
      case CompassStyle.arc:
        return 0; // 180 degree arc
      default:
        return 270; // Full circle
    }
  }

  double _getInterval() {
    switch (compassStyle) {
      case CompassStyle.minimal:
        return 90; // Only cardinal directions
      case CompassStyle.rose:
        return 22.5; // 16 divisions
      default:
        return 30;
    }
  }

  double _getMajorTickLength() {
    switch (compassStyle) {
      case CompassStyle.rose:
        return 15;
      case CompassStyle.minimal:
        return 8;
      default:
        return 12;
    }
  }

  void _customizeLabel(AxisLabelCreatedArgs args) {
    // Replace degree labels with cardinal directions
    switch (args.text) {
      case '0':
        args.text = 'N';
        args.labelStyle = GaugeTextStyle(
          color: primaryColor,
          fontSize: compassStyle == CompassStyle.rose ? 22 : 20,
          fontWeight: FontWeight.bold,
        );
        break;
      case '90':
        args.text = 'E';
        break;
      case '180':
        args.text = 'S';
        break;
      case '270':
        args.text = 'W';
        break;
      case '45':
        args.text = compassStyle == CompassStyle.rose ? 'NE' : '';
        break;
      case '135':
        args.text = compassStyle == CompassStyle.rose ? 'SE' : '';
        break;
      case '225':
        args.text = compassStyle == CompassStyle.rose ? 'SW' : '';
        break;
      case '315':
        args.text = compassStyle == CompassStyle.rose ? 'NW' : '';
        break;
      case '22.5':
      case '67.5':
      case '112.5':
      case '157.5':
      case '202.5':
      case '247.5':
      case '292.5':
      case '337.5':
        // Intercardinal directions for rose style
        args.text = compassStyle == CompassStyle.rose ? '•' : '';
        args.labelStyle = const GaugeTextStyle(fontSize: 8);
        break;
      default:
        if (showTickLabels) {
          args.text = '${args.text}°';
        } else {
          args.text = ''; // Hide non-cardinal labels
        }
    }
  }

  List<GaugeRange> _getRanges() {
    if (compassStyle == CompassStyle.minimal) {
      return [];
    }

    if (compassStyle == CompassStyle.rose) {
      // Add quadrant shading for rose style
      return [
        GaugeRange(
          startValue: 0,
          endValue: 360,
          color: Colors.grey.withValues(alpha: 0.1),
          startWidth: 2,
          endWidth: 2,
        ),
      ];
    }

    return [
      GaugeRange(
        startValue: 0,
        endValue: 360,
        color: Colors.grey.withValues(alpha: 0.2),
        startWidth: 2,
        endWidth: 2,
      ),
    ];
  }

  List<GaugePointer> _getPointers() {
    if (compassStyle == CompassStyle.rose) {
      // Traditional compass needle style (larger needle)
      return [
        NeedlePointer(
          value: heading,
          needleLength: 0.75,
          needleStartWidth: 8,
          needleEndWidth: 2,
          needleColor: primaryColor,
          knobStyle: KnobStyle(
            knobRadius: 0.1,
            color: primaryColor,
            borderColor: Colors.white,
            borderWidth: 0.03,
          ),
        ),
      ];
    }

    if (compassStyle == CompassStyle.minimal) {
      // Triangle marker
      return [
        MarkerPointer(
          value: heading,
          markerType: MarkerType.triangle,
          markerHeight: 20,
          markerWidth: 20,
          color: primaryColor,
          markerOffset: -10,
        ),
      ];
    }

    // Classic needle
    return [
      NeedlePointer(
        value: heading,
        needleLength: 0.7,
        needleStartWidth: 0,
        needleEndWidth: 10,
        needleColor: primaryColor,
        knobStyle: KnobStyle(
          knobRadius: 0.08,
          color: primaryColor,
          borderColor: primaryColor,
          borderWidth: 0.02,
        ),
      ),
    ];
  }

  String _getCardinalDirection(double degrees) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((degrees + 22.5) / 45).floor() % 8;
    return directions[index];
  }
}
