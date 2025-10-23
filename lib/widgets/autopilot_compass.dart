import 'dart:math';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'base_compass.dart';

/// Autopilot-style compass gauge with rotating card display
/// Built on BaseCompass with autopilot-specific features
class AutopilotCompass extends StatelessWidget {
  final double heading; // Current heading in degrees (0-360)
  final double? headingTrue; // True heading (if different from magnetic)
  final double? headingMagnetic; // Magnetic heading
  final double targetHeading; // Target/autopilot heading
  final double? crossTrackError; // Optional XTE in meters
  final double? apparentWindAngle; // Optional AWA for wind mode
  final String mode; // Display mode (e.g., 'Mag', 'True', 'Track')
  final bool showTarget; // Whether to show target heading pointer

  const AutopilotCompass({
    super.key,
    required this.heading,
    this.headingTrue,
    this.headingMagnetic,
    this.targetHeading = 0,
    this.crossTrackError,
    this.apparentWindAngle,
    this.mode = 'Mag',
    this.showTarget = false,
  });

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

  /// Build autopilot zones (port/starboard)
  List<GaugeRange> _buildAutopilotZones(double primaryHeadingDegrees) {
    final zones = <GaugeRange>[];

    // Helper to add a range, splitting if it crosses 0°
    void addRange(double start, double end, Color color, {double width = 30}) {
      final startNorm = _normalizeAngle(start);
      final endNorm = _normalizeAngle(end);

      if (startNorm < endNorm) {
        zones.add(GaugeRange(
          startValue: startNorm,
          endValue: endNorm,
          color: color,
          startWidth: width,
          endWidth: width,
        ));
      } else {
        // Crosses 0°: split into two ranges
        zones.add(GaugeRange(
          startValue: startNorm,
          endValue: 360,
          color: color,
          startWidth: width,
          endWidth: width,
        ));
        zones.add(GaugeRange(
          startValue: 0,
          endValue: endNorm,
          color: color,
          startWidth: width,
          endWidth: width,
        ));
      }
    }

    // Port side (red) - left 180°
    addRange(primaryHeadingDegrees - 180, primaryHeadingDegrees, Colors.red.withValues(alpha: 0.3));

    // Starboard side (green) - right 180°
    addRange(primaryHeadingDegrees, primaryHeadingDegrees + 180, Colors.green.withValues(alpha: 0.3));

    return zones;
  }

  /// Build autopilot pointers
  List<GaugePointer> _buildAutopilotPointers(double primaryHeadingDegrees) {
    final pointers = <GaugePointer>[];

    // Current heading needle (white, pointing up)
    pointers.add(NeedlePointer(
      value: primaryHeadingDegrees,
      needleLength: 0.7,
      needleStartWidth: 0,
      needleEndWidth: 8,
      needleColor: Colors.white,
      knobStyle: const KnobStyle(knobRadius: 0),
    ));

    // Target heading marker (if enabled)
    if (showTarget) {
      pointers.add(WidgetPointer(
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
      ));
    }

    // Apparent wind angle indicator (if provided)
    if (apparentWindAngle != null) {
      final awaDirection = _normalizeAngle(primaryHeadingDegrees + apparentWindAngle!);
      pointers.add(NeedlePointer(
        value: awaDirection,
        needleLength: 0.85,
        needleStartWidth: 4,
        needleEndWidth: 0,
        needleColor: Colors.blue,
        knobStyle: const KnobStyle(
          knobRadius: 0.02,
          color: Colors.blue,
        ),
      ));
    }

    return pointers;
  }

  /// Build autopilot overlay
  Widget _buildAutopilotOverlay(double primaryHeadingDegrees) {
    return Stack(
      children: [
        // Cardinal direction at top
        Positioned(
          top: 5,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white30, width: 1),
              ),
              child: Text(
                _getCardinalDirection(primaryHeadingDegrees),
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),

        // Target heading info (if shown)
        if (showTarget)
          Positioned(
            top: 35,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.yellow, width: 2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'TARGET',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.white38,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${targetHeading.toStringAsFixed(0)}°',
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.yellow,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // Heading error (difference from target)
                    Builder(
                      builder: (context) {
                        double error = primaryHeadingDegrees - targetHeading;
                        // Normalize to -180 to +180
                        while (error > 180) error -= 360;
                        while (error < -180) error += 360;

                        Color errorColor;
                        if (error.abs() < 3) {
                          errorColor = Colors.green;
                        } else if (error.abs() < 10) {
                          errorColor = Colors.yellow;
                        } else {
                          errorColor = Colors.red;
                        }

                        return Text(
                          '${error > 0 ? '+' : ''}${error.toStringAsFixed(1)}°',
                          style: TextStyle(
                            fontSize: 12,
                            color: errorColor,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

        // XTE display (right side) if available
        if (crossTrackError != null)
          Positioned(
            right: 20,
            top: 0,
            bottom: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: crossTrackError! >= 0 ? Colors.green : Colors.red,
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'XTE',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white60,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      crossTrackError!.abs() >= 1000
                          ? '${(crossTrackError!.abs() / 1000).toStringAsFixed(2)}'
                          : '${crossTrackError!.abs().toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      crossTrackError!.abs() >= 1000 ? 'km' : 'm',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white60,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      crossTrackError! >= 0 ? 'STBD' : 'PORT',
                      style: TextStyle(
                        fontSize: 12,
                        color: crossTrackError! >= 0 ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Convert heading to radians for rotation
    final headingRadians = heading * pi / 180;

    return BaseCompass(
      headingTrueRadians: headingTrue != null ? headingTrue! * pi / 180 : null,
      headingMagneticRadians: headingMagnetic != null ? headingMagnetic! * pi / 180 : headingRadians,
      headingTrueDegrees: headingTrue,
      headingMagneticDegrees: headingMagnetic ?? heading,
      rangesBuilder: _buildAutopilotZones,
      pointersBuilder: _buildAutopilotPointers,
      overlayBuilder: _buildAutopilotOverlay,
      // Hide default heading displays in corners since we show them in overlay
      trueHeadingDisplayBuilder: (_, __) => const SizedBox.shrink(),
      magneticHeadingDisplayBuilder: (_, __) => const SizedBox.shrink(),
      allowHeadingModeToggle: false, // Autopilot typically uses one mode
    );
  }
}
