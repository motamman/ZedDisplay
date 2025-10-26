import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

/// Available compass display styles
enum CompassStyle {
  classic,  // Full circle with needle (default)
  arc,      // 180° arc showing heading range
  minimal,  // Clean modern with simplified markings
  marine,   // Card rotates, needle points up (traditional marine compass)
}

/// A compass widget for displaying heading/bearing
/// Now powered by Syncfusion for professional appearance
/// Supports up to 4 needles for comparing multiple headings
class CompassGauge extends StatelessWidget {
  final double heading; // Primary heading in degrees (0-360)
  final String label;
  final String? formattedValue;
  final Color primaryColor;
  final bool showTickLabels;
  final CompassStyle compassStyle;
  final bool showValue; // Show/hide the heading value display

  // Additional headings for multi-needle display (up to 3 more)
  final List<double>? additionalHeadings;
  final List<String>? additionalLabels;
  final List<Color>? additionalColors;

  const CompassGauge({
    super.key,
    required this.heading,
    this.label = 'Heading',
    this.formattedValue,
    this.primaryColor = Colors.red,
    this.showTickLabels = false,
    this.compassStyle = CompassStyle.classic,
    this.showValue = true,
    this.additionalHeadings,
    this.additionalLabels,
    this.additionalColors,
  });

  @override
  Widget build(BuildContext context) {
    // Marine style uses a custom rotating card implementation
    if (compassStyle == CompassStyle.marine) {
      return _buildMarineCompass(context);
    }

    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        children: [
          // Gauge with pointer - drawn first
          SfRadialGauge(
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
                  thickness: 2,
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

                // Hide auto-generated labels - we'll use custom annotations instead
                showLabels: false,

                // Outer ring for visual boundary
                ranges: _getRanges(),

                // Heading pointer
                pointers: _getPointers(),

                // Compass labels with counter-rotation to stay horizontal
                annotations: _buildCompassLabels(),
              ),
            ],
          ),

          // Center annotation with heading value - drawn last so it's on top, moved down from center
          if (showValue)
            Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.only(top: 55.0), // Move down from center to avoid overlap
                child: Column(
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
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formattedValue ?? '${heading.toStringAsFixed(0)}°',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _getCardinalDirection(heading),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // Multi-needle legend at bottom
          if (additionalHeadings != null && additionalHeadings!.isNotEmpty && additionalLabels != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Primary needle
                      _buildLegendItem(label, primaryColor),
                      // Additional needles
                      for (int i = 0; i < additionalHeadings!.length && i < 3; i++) ...[
                        const SizedBox(width: 8),
                        _buildLegendItem(
                          additionalLabels![i],
                          additionalColors != null && i < additionalColors!.length
                              ? additionalColors![i]
                              : Colors.blue,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.white,
          ),
        ),
      ],
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
      default:
        return 30;
    }
  }

  double _getMajorTickLength() {
    switch (compassStyle) {
      case CompassStyle.minimal:
        return 8;
      default:
        return 12;
    }
  }

  /// Build compass labels (N, S, E, W, degrees) with proper rotation
  /// Labels are counter-rotated by heading so they stay horizontal
  List<GaugeAnnotation> _buildCompassLabels() {
    final labels = <GaugeAnnotation>[];
    const int interval = 30;

    for (int i = 0; i < 360; i += interval) {
      String labelText;
      Color labelColor;
      double fontSize;

      switch (i) {
        case 0:
          labelText = 'N';
          labelColor = primaryColor;
          fontSize = 20;
          break;
        case 90:
          labelText = 'E';
          labelColor = Colors.grey;
          fontSize = 16;
          break;
        case 180:
          labelText = 'S';
          labelColor = Colors.grey;
          fontSize = 16;
          break;
        case 270:
          labelText = 'W';
          labelColor = Colors.grey;
          fontSize = 16;
          break;
        default:
          if (!showTickLabels) continue;
          labelText = '$i°';
          labelColor = Colors.grey.withOpacity(0.6);
          fontSize = 14;
      }

      double labelAngle;
      if (compassStyle == CompassStyle.arc) {
        // Arc compresses 360° into 180° semicircle
        // Gauge value i maps to screen position 180 + (i/2)
        labelAngle = 180 + (i / 2);
      } else {
        // Full circle: add 270° offset to align N to top
        labelAngle = (i + 270) % 360;
      }

      labels.add(
        GaugeAnnotation(
          widget: Text(
            labelText,
            style: TextStyle(
              color: labelColor,
              fontSize: fontSize,
              fontWeight: i == 0 || i % 90 == 0 ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          angle: labelAngle,
          positionFactor: 0.80,
        ),
      );
    }

    return labels;
  }

  List<GaugeRange> _getRanges() {
    if (compassStyle == CompassStyle.minimal) {
      return [];
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
    final pointers = <GaugePointer>[];

    // Add additional needles FIRST (drawn below primary needle)
    if (additionalHeadings != null && additionalHeadings!.isNotEmpty) {
      for (int i = 0; i < additionalHeadings!.length && i < 3; i++) {
        final color = additionalColors != null && i < additionalColors!.length
            ? additionalColors![i]
            : Colors.blue;

        pointers.add(
          NeedlePointer(
            value: additionalHeadings![i],
            needleLength: 0.65, // Slightly shorter than primary
            needleStartWidth: 0,
            needleEndWidth: 8,
            needleColor: color.withOpacity(0.8),
            knobStyle: const KnobStyle(
              knobRadius: 0, // No knob for secondary needles
            ),
          ),
        );
      }
    }

    // Add primary needle LAST (drawn on top)
    if (compassStyle == CompassStyle.minimal) {
      // Triangle marker
      pointers.add(
        MarkerPointer(
          value: heading,
          markerType: MarkerType.triangle,
          markerHeight: 20,
          markerWidth: 20,
          color: primaryColor,
          markerOffset: -10,
        ),
      );
    } else {
      // Classic needle
      pointers.add(
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
      );
    }

    return pointers;
  }

  String _getCardinalDirection(double degrees) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((degrees + 22.5) / 45).floor() % 8;
    return directions[index];
  }

  /// Build marine-style compass where card rotates
  Widget _buildMarineCompass(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        children: [
          // Rotating compass card
          Transform.rotate(
            angle: -heading * 3.14159265359 / 180, // Rotate card opposite to heading
            child: SfRadialGauge(
              axes: <RadialAxis>[
                RadialAxis(
                  minimum: 0,
                  maximum: 360,
                  interval: 30,
                  startAngle: 270,
                  endAngle: 270,
                  showAxisLine: false,
                  showLastLabel: true,

                  // Tick configuration
                  majorTickStyle: const MajorTickStyle(
                    length: 12,
                    thickness: 2,
                    color: Colors.grey,
                  ),
                  minorTicksPerInterval: 2,
                  minorTickStyle: MinorTickStyle(
                    length: 6,
                    thickness: 1,
                    color: Colors.grey.withValues(alpha: 0.5),
                  ),

                  // Hide built-in labels - we'll use custom annotations that stay horizontal
                  showLabels: false,

                  // Outer ring
                  ranges: [
                    GaugeRange(
                      startValue: 0,
                      endValue: 360,
                      color: Colors.grey.withValues(alpha: 0.2),
                      startWidth: 2,
                      endWidth: 2,
                    ),
                  ],

                  // No pointer on the rotating card
                  pointers: const [],

                  // Custom annotations that counter-rotate to stay horizontal
                  annotations: _buildMarineCompassLabels(),
                ),
              ],
            ),
          ),

          // Fixed needles pointing up (North) - drawn before value so they're underneath
          // Additional needles first (below primary)
          if (additionalHeadings != null && additionalHeadings!.isNotEmpty)
            for (int i = 0; i < additionalHeadings!.length && i < 3; i++)
              Transform.rotate(
                angle: (additionalHeadings![i] - heading) * 3.14159265359 / 180, // Rotate relative to primary heading
                child: Center(
                  child: CustomPaint(
                    size: const Size(200, 200),
                    painter: _MarineNeedlePainter(
                      additionalColors != null && i < additionalColors!.length
                          ? additionalColors![i]
                          : Colors.blue,
                      isSecondary: true,
                    ),
                  ),
                ),
              ),

          // Primary needle last (on top)
          Center(
            child: CustomPaint(
              size: const Size(200, 200),
              painter: _MarineNeedlePainter(primaryColor),
            ),
          ),

          // Center annotation with heading value (non-rotating) - drawn last so it's on top
          if (showValue)
            Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.only(top: 60.0), // Move down to avoid needle
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formattedValue ?? '${heading.toStringAsFixed(0)}°',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _getCardinalDirection(heading),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // Multi-needle legend at bottom
          if (additionalHeadings != null && additionalHeadings!.isNotEmpty && additionalLabels != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Primary needle
                      _buildLegendItem(label, primaryColor),
                      // Additional needles
                      for (int i = 0; i < additionalHeadings!.length && i < 3; i++) ...[
                        const SizedBox(width: 8),
                        _buildLegendItem(
                          additionalLabels![i],
                          additionalColors != null && i < additionalColors!.length
                              ? additionalColors![i]
                              : Colors.blue,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Build marine compass labels that counter-rotate to stay horizontal
  List<GaugeAnnotation> _buildMarineCompassLabels() {
    final labels = <GaugeAnnotation>[];
    const int interval = 30;

    for (int i = 0; i < 360; i += interval) {
      String labelText;
      Color labelColor;
      double fontSize;

      switch (i) {
        case 0:
          labelText = 'N';
          labelColor = primaryColor;
          fontSize = 22;
          break;
        case 90:
          labelText = 'E';
          labelColor = Colors.grey;
          fontSize = 18;
          break;
        case 180:
          labelText = 'S';
          labelColor = Colors.grey;
          fontSize = 18;
          break;
        case 270:
          labelText = 'W';
          labelColor = Colors.grey;
          fontSize = 18;
          break;
        default:
          if (!showTickLabels) continue;
          labelText = '$i°';
          labelColor = Colors.grey.withOpacity(0.7);
          fontSize = 16;
      }

      labels.add(
        GaugeAnnotation(
          widget: Transform.rotate(
            angle: heading * 3.14159 / 180, // Counter-rotate by heading to keep label horizontal
            child: Text(
              labelText,
              style: TextStyle(
                color: labelColor,
                fontSize: fontSize,
                fontWeight: i % 90 == 0 ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
          angle: i.toDouble(),
          positionFactor: 0.80,
        ),
      );
    }

    return labels;
  }
}

/// Custom painter for the fixed marine compass needle
class _MarineNeedlePainter extends CustomPainter {
  final Color color;
  final bool isSecondary;

  _MarineNeedlePainter(this.color, {this.isSecondary = false});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final northNeedleLength = radius * (isSecondary ? 0.7 : 0.8); // Shorter for secondary
    final southTailLength = radius * (isSecondary ? 0.65 : 0.75); // Shorter for secondary
    final needleWidth = isSecondary ? 6.0 : 8.0; // Narrower for secondary

    final paint = Paint()
      ..color = isSecondary ? color.withOpacity(0.8) : color
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    // Draw needle pointing up (North)
    final needlePath = Path();

    // North pointing needle
    needlePath.moveTo(center.dx, center.dy - northNeedleLength);
    needlePath.lineTo(center.dx - needleWidth, center.dy);
    needlePath.lineTo(center.dx, center.dy - 10);
    needlePath.lineTo(center.dx + needleWidth, center.dy);
    needlePath.close();

    // Draw shadow
    if (!isSecondary) {
      canvas.drawPath(needlePath, shadowPaint);
    }

    // Draw needle
    canvas.drawPath(needlePath, paint);

    // South pointing tail (darker shade for better visibility)
    final hslColor = HSLColor.fromColor(color);
    final darkerColor = hslColor.withLightness((hslColor.lightness - 0.3).clamp(0.0, 1.0)).toColor();

    final tailPaint = Paint()
      ..color = isSecondary ? darkerColor.withOpacity(0.8) : darkerColor
      ..style = PaintingStyle.fill;

    final tailPath = Path();
    tailPath.moveTo(center.dx, center.dy + southTailLength);
    tailPath.lineTo(center.dx - (needleWidth * 0.75), center.dy);
    tailPath.lineTo(center.dx + (needleWidth * 0.75), center.dy);
    tailPath.close();

    canvas.drawPath(tailPath, tailPaint);

    // Draw center knob (only for primary needle)
    if (!isSecondary) {
      final knobPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawCircle(center, 10, knobPaint);

      final knobBorderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(center, 10, knobBorderPaint);
    }
  }

  @override
  bool shouldRepaint(_MarineNeedlePainter oldDelegate) {
    return color != oldDelegate.color || isSecondary != oldDelegate.isSecondary;
  }
}
