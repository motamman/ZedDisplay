import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

/// Wind compass gauge with full circle rotating card (autopilot style)
/// Shows heading (true/magnetic), wind direction (true/apparent), and SOG
class WindCompass extends StatefulWidget {
  // Heading values in radians (for rotation) and degrees (for display)
  final double? headingTrueRadians;
  final double? headingMagneticRadians;
  final double? headingTrueDegrees;
  final double? headingMagneticDegrees;

  // Wind direction values in radians (for rotation) and degrees (for display)
  final double? windDirectionTrueRadians;
  final double? windDirectionApparentRadians;
  final double? windDirectionTrueDegrees;
  final double? windDirectionApparentDegrees;

  final double? speedOverGround;
  final String? sogFormatted;
  final double? cogDegrees;

  const WindCompass({
    super.key,
    this.headingTrueRadians,
    this.headingMagneticRadians,
    this.headingTrueDegrees,
    this.headingMagneticDegrees,
    this.windDirectionTrueRadians,
    this.windDirectionApparentRadians,
    this.windDirectionTrueDegrees,
    this.windDirectionApparentDegrees,
    this.speedOverGround,
    this.sogFormatted,
    this.cogDegrees,
  });

  @override
  State<WindCompass> createState() => _WindCompassState();
}

class _WindCompassState extends State<WindCompass> {
  bool _useTrueHeading = false; // Default to magnetic

  /// Normalize angle to 0-360 range
  double _normalizeAngle(double angle) {
    while (angle < 0) {
      angle += 360;
    }
    while (angle >= 360) {
      angle -= 360;
    }
    return angle;
  }

  /// Build compass labels (N, S, E, W, degrees) as gauge annotations
  /// Labels counter-rotate to stay upright while compass card rotates
  List<GaugeAnnotation> _buildCompassLabels() {
    final labels = <GaugeAnnotation>[];

    // Get the current heading in DEGREES for counter-rotation (doesn't need to use selected heading)
    final headingDegrees = widget.headingMagneticDegrees ?? widget.headingTrueDegrees ?? 0.0;

    for (int i = 0; i < 360; i += 30) {
      String label;
      Color labelColor;
      double fontSize;

      switch (i) {
        case 0:
          label = 'N';
          labelColor = Colors.white;
          fontSize = 24;
          break;
        case 90:
          label = 'E';
          labelColor = Colors.white70;
          fontSize = 20;
          break;
        case 180:
          label = 'S';
          labelColor = Colors.white70;
          fontSize = 20;
          break;
        case 270:
          label = 'W';
          labelColor = Colors.white70;
          fontSize = 20;
          break;
        default:
          label = i.toString();
          labelColor = Colors.white60;
          fontSize = 16;
      }

      labels.add(
        GaugeAnnotation(
          widget: Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: fontSize,
              fontWeight: i == 0 || i % 90 == 0 ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          angle: i.toDouble(),
          positionFactor: 0.85,
        ),
      );
    }

    return labels;
  }

  @override
  Widget build(BuildContext context) {
    // Use radians for rotation based on user selection
    final primaryHeadingRadians = _useTrueHeading
        ? (widget.headingTrueRadians ?? widget.headingMagneticRadians ?? 0.0)
        : (widget.headingMagneticRadians ?? widget.headingTrueRadians ?? 0.0);

    // Use degrees for display based on user selection
    final primaryHeadingDegrees = _useTrueHeading
        ? (widget.headingTrueDegrees ?? widget.headingMagneticDegrees ?? 0.0)
        : (widget.headingMagneticDegrees ?? widget.headingTrueDegrees ?? 0.0);

    // Use apparent wind for primary wind direction (for no-go zones)
    final primaryWindDegrees = widget.windDirectionApparentDegrees ?? widget.windDirectionTrueDegrees;

    final headingMode = _useTrueHeading ? 'True' : 'Mag';

    return AspectRatio(
      aspectRatio: 1.0,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // Main compass gauge (full circle) - wrapped in Transform.rotate
              Transform.rotate(
                angle: -primaryHeadingRadians - (3.14159265359 / 2),  // Rotation minus 90° to compensate
                child: SfRadialGauge(
                  axes: <RadialAxis>[
                    RadialAxis(
                      // Full circle
                      startAngle: 0,
                      endAngle: 360,
                    minimum: 0,
                    maximum: 360,
                    interval: 30,

                    // Configure the axis appearance
                    showAxisLine: false,
                    showLastLabel: false,
                    showLabels: false, // Hide auto-generated labels, we'll add our own

                    // Tick configuration
                    minorTicksPerInterval: 2,
                    majorTickStyle: const MajorTickStyle(
                      length: 15,
                      thickness: 2,
                      color: Colors.white70,
                    ),
                    minorTickStyle: const MinorTickStyle(
                      length: 8,
                      thickness: 1,
                      color: Colors.white30,
                    ),

                    // Sailing zones: red (port tack), no-go, green (starboard tack)
                    ranges: <GaugeRange>[
                      // Red zone - 45° to the LEFT of no-go zone
                      if (primaryWindDegrees != null)
                        GaugeRange(
                          startValue: _normalizeAngle(primaryWindDegrees! - 90),
                          endValue: _normalizeAngle(primaryWindDegrees! - 45),
                          color: Colors.red.withValues(alpha: 0.5),
                          startWidth: 25,
                          endWidth: 25,
                        ),
                      // No-go zone (white/gray) - ±45° from wind direction
                      if (primaryWindDegrees != null)
                        GaugeRange(
                          startValue: _normalizeAngle(primaryWindDegrees! - 45),
                          endValue: _normalizeAngle(primaryWindDegrees! + 45),
                          color: Colors.white.withValues(alpha: 0.3),
                          startWidth: 25,
                          endWidth: 25,
                        ),
                      // Green zone - 45° to the RIGHT of no-go zone
                      if (primaryWindDegrees != null)
                        GaugeRange(
                          startValue: _normalizeAngle(primaryWindDegrees! + 45),
                          endValue: _normalizeAngle(primaryWindDegrees! + 90),
                          color: Colors.green.withValues(alpha: 0.5),
                          startWidth: 25,
                          endWidth: 25,
                        ),
                    ],

                    // Pointers for wind, heading, and COG (drawn in order, later ones appear on top)
                    pointers: <GaugePointer>[
                      // Non-selected heading indicator FIRST (so other arrows can be seen over it)
                      // Yellow for true heading when mag is selected
                      if (!_useTrueHeading && widget.headingTrueDegrees != null)
                        NeedlePointer(
                          value: widget.headingTrueDegrees!,
                          needleLength: 0.92,  // Slightly shorter so rounded end fits
                          needleStartWidth: 0,
                          needleEndWidth: 10,  // Twice as wide as dominant wind (5 * 2)
                          needleColor: Colors.yellow,
                          knobStyle: KnobStyle(
                            knobRadius: 0,
                          ),
                        ),
                      // Rounded end for yellow heading indicator - always visible at edge
                      if (widget.headingTrueDegrees != null)
                        MarkerPointer(
                          value: widget.headingTrueDegrees!,
                          markerType: MarkerType.circle,
                          markerHeight: 16,
                          markerWidth: 16,
                          color: Colors.yellow,
                          markerOffset: -5, // Position at outer edge of compass
                        ),

                      // Orange for magnetic heading when true is selected
                      if (_useTrueHeading && widget.headingMagneticDegrees != null)
                        NeedlePointer(
                          value: widget.headingMagneticDegrees!,
                          needleLength: 0.92,  // Slightly shorter so rounded end fits
                          needleStartWidth: 0,
                          needleEndWidth: 10,  // Twice as wide as dominant wind (5 * 2)
                          needleColor: Colors.orange,
                          knobStyle: KnobStyle(
                            knobRadius: 0,
                          ),
                        ),
                      // Rounded end for orange heading indicator - always visible at edge
                      if (widget.headingMagneticDegrees != null)
                        MarkerPointer(
                          value: widget.headingMagneticDegrees!,
                          markerType: MarkerType.circle,
                          markerHeight: 16,
                          markerWidth: 16,
                          color: Colors.orange,
                          markerOffset: -5, // Position at outer edge of compass
                        ),

                      // COG (Course Over Ground) - white needle, always visible
                      if (widget.cogDegrees != null)
                        NeedlePointer(
                          value: widget.cogDegrees!,
                          needleLength: 0.65,
                          needleStartWidth: 3,
                          needleEndWidth: 0,
                          needleColor: Colors.white,
                          knobStyle: KnobStyle(
                            knobRadius: 0.02,
                            color: Colors.white,
                          ),
                        ),

                      // Apparent wind direction marker - primary
                      if (widget.windDirectionApparentDegrees != null)
                        NeedlePointer(
                          value: widget.windDirectionApparentDegrees!,
                          needleLength: 0.95,
                          needleStartWidth: 5,
                          needleEndWidth: 0,
                          needleColor: Colors.blue,
                          knobStyle: KnobStyle(
                            knobRadius: 0.03,
                            color: Colors.blue,
                          ),
                        ),

                      // True wind direction marker - secondary
                      if (widget.windDirectionTrueDegrees != null)
                        NeedlePointer(
                          value: widget.windDirectionTrueDegrees!,
                          needleLength: 0.75,
                          needleStartWidth: 4,
                          needleEndWidth: 0,
                          needleColor: Colors.green,
                          knobStyle: KnobStyle(
                            knobRadius: 0.025,
                            color: Colors.green,
                          ),
                        ),
                    ],

                    // Fixed compass labels as annotations
                    annotations: _buildCompassLabels(),
                  ),
                ],
                ),
              ),

              // COG label at top center - styled like other labels
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'COG',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        widget.cogDegrees != null
                            ? '${widget.cogDegrees!.toStringAsFixed(0)}°'
                            : '--',
                        style: const TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Center display with heading (use degrees) - moved down
              Positioned.fill(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 90), // Push content down more
                      // Large heading display
                      Text(
                        '${primaryHeadingDegrees.toStringAsFixed(0)}°',
                        style: const TextStyle(
                          fontSize: 56,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      // Mode indicator (Mag/True)
                      Text(
                        headingMode,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // White circle in the center - above everything
              Positioned.fill(
                child: Center(
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),

              // HDG True (top left) - tap to switch to true heading
              if (widget.headingTrueDegrees != null)
                Positioned(
                  left: 16,
                  top: 40,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _useTrueHeading = true;
                      });
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.yellow,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'HDG',
                              style: TextStyle(
                                fontSize: 12,
                                color: _useTrueHeading ? Colors.white : Colors.white60,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${widget.headingTrueDegrees!.toStringAsFixed(0)}°T',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.white,
                            fontWeight: _useTrueHeading ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // HDG Magnetic (top right) - tap to switch to magnetic heading
              if (widget.headingMagneticDegrees != null)
                Positioned(
                  right: 16,
                  top: 40,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _useTrueHeading = false;
                      });
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'HDG',
                              style: TextStyle(
                                fontSize: 12,
                                color: !_useTrueHeading ? Colors.white : Colors.white60,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${widget.headingMagneticDegrees!.toStringAsFixed(0)}°M',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.white,
                            fontWeight: !_useTrueHeading ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // True Wind Direction (bottom left)
              if (widget.windDirectionTrueDegrees != null)
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'TWD',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${widget.windDirectionTrueDegrees!.toStringAsFixed(0)}°',
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

              // Apparent Wind Direction (bottom right)
              if (widget.windDirectionApparentDegrees != null)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'AWD',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${widget.windDirectionApparentDegrees!.toStringAsFixed(0)}°',
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

              // Speed Over Ground (bottom center)
              if (widget.speedOverGround != null)
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'SOG',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white60,
                          ),
                        ),
                        Text(
                          widget.sogFormatted ?? widget.speedOverGround!.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 24,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
