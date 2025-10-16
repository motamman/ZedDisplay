import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

/// Autopilot-style compass gauge with rotating arc display
/// Matches marine autopilot display with port/starboard color zones
class AutopilotCompass extends StatelessWidget {
  final double heading; // Current heading in degrees (0-360)
  final double targetHeading; // Target/autopilot heading
  final double? crossTrackError; // Optional XTE in meters
  final double? apparentWindAngle; // Optional AWA for wind mode
  final String mode; // Display mode (e.g., 'Mag', 'True', 'Track')
  final bool showTarget; // Whether to show target heading pointer

  const AutopilotCompass({
    super.key,
    required this.heading,
    this.targetHeading = 0,
    this.crossTrackError,
    this.apparentWindAngle,
    this.mode = 'Mag',
    this.showTarget = false,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.8, // Wider aspect ratio for arc display
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // Main compass gauge
              SfRadialGauge(
                axes: <RadialAxis>[
                  RadialAxis(
                    // Start at -120 degrees (240 degree arc visible)
                    startAngle: 150,
                    endAngle: 30,
                    minimum: 0,
                    maximum: 360,
                    interval: 30,

                    // Configure the axis appearance
                    showAxisLine: false,
                    showLastLabel: false,

                    // Tick configuration
                    minorTicksPerInterval: 5,
                    majorTickStyle: const MajorTickStyle(
                      length: 12,
                      thickness: 2,
                      color: Colors.white70,
                    ),
                    minorTickStyle: const MinorTickStyle(
                      length: 6,
                      thickness: 1,
                      color: Colors.white30,
                    ),

                    // Label configuration (shows degrees)
                    axisLabelStyle: const GaugeTextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    labelOffset: 25,

                    // Port (red) and Starboard (green) color zones
                    ranges: <GaugeRange>[
                      // Port side (red) - left half
                      GaugeRange(
                        startValue: _normalizeAngle(heading - 90),
                        endValue: _normalizeAngle(heading),
                        color: Colors.red.withValues(alpha: 0.3),
                        startWidth: 30,
                        endWidth: 30,
                      ),
                      // Starboard side (green) - right half
                      GaugeRange(
                        startValue: _normalizeAngle(heading),
                        endValue: _normalizeAngle(heading + 90),
                        color: Colors.green.withValues(alpha: 0.3),
                        startWidth: 30,
                        endWidth: 30,
                      ),
                    ],

                    // Pointers
                    pointers: <GaugePointer>[
                      // North marker (inverted - gauge rotates, not pointer)
                      NeedlePointer(
                        value: heading,
                        needleLength: 0.7,
                        needleStartWidth: 0,
                        needleEndWidth: 8,
                        needleColor: Colors.white,
                        knobStyle: const KnobStyle(
                          knobRadius: 0,
                        ),
                      ),

                      // Target heading marker (if enabled)
                      if (showTarget)
                        WidgetPointer(
                          value: targetHeading,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.yellow,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                    ],

                    // Center annotation with heading display
                    annotations: <GaugeAnnotation>[
                      GaugeAnnotation(
                        widget: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // "Track" or mode label
                            Text(
                              'Track',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white60,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Large heading display
                            Text(
                              '${heading.toStringAsFixed(0)}°',
                              style: const TextStyle(
                                fontSize: 56,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            // Mode indicator (Mag/True)
                            Text(
                              mode,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        angle: 90,
                        positionFactor: 0.5,
                      ),
                    ],
                  ),
                ],
              ),

              // HDG label (top left)
              Positioned(
                left: 20,
                top: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HDG',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    ),
                    Text(
                      '${heading.toStringAsFixed(0)}°${mode.substring(0, 1)}',
                      style: const TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // XTE display (top right) if available
              if (crossTrackError != null)
                Positioned(
                  right: 20,
                  top: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'XTE',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white60,
                        ),
                      ),
                      Text(
                        '${crossTrackError!.abs().toStringAsFixed(0)}${_getUnit(crossTrackError!)}',
                        style: const TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        crossTrackError! >= 0 ? 'Stbd' : 'Port',
                        style: TextStyle(
                          fontSize: 14,
                          color: crossTrackError! >= 0 ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

              // Cardinal direction markers at the top
              Positioned(
                top: 5,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _getCardinalDirection(heading),
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Normalize angle to 0-360 range
  double _normalizeAngle(double angle) {
    while (angle < 0) angle += 360;
    while (angle >= 360) angle -= 360;
    return angle;
  }

  /// Get cardinal direction from heading
  String _getCardinalDirection(double degrees) {
    const directions = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
                       'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
    final index = ((degrees + 11.25) / 22.5).floor() % 16;
    return directions[index];
  }

  /// Get unit for cross track error display
  String _getUnit(double xte) {
    if (xte.abs() >= 1000) {
      return 'km';
    }
    return 'm';
  }
}
