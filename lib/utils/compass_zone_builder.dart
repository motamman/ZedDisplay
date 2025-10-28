import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'angle_utils.dart';

/// Builder for compass gauge zones with automatic 0°/360° wraparound handling
///
/// Simplifies creation of colored zones for compass widgets (wind compass,
/// autopilot, etc.) by automatically splitting zones that cross the 0°/360°
/// boundary into two separate ranges.
///
/// Example:
/// ```dart
/// final builder = CompassZoneBuilder();
/// builder.addZone(350, 10, Colors.red);  // Automatically splits into 350-360 and 0-10
/// final zones = builder.zones;
/// ```
class CompassZoneBuilder {
  final List<GaugeRange> _zones = [];

  /// Get all created zones
  List<GaugeRange> get zones => _zones;

  /// Add a zone range with automatic 0°/360° wraparound handling
  ///
  /// If the zone crosses the 0°/360° boundary (e.g., 350° to 10°),
  /// it's automatically split into two ranges:
  /// - 350° to 360°
  /// - 0° to 10°
  ///
  /// Parameters:
  /// - [startDegrees]: Start angle in degrees (0-360)
  /// - [endDegrees]: End angle in degrees (0-360)
  /// - [color]: Fill color for the zone
  /// - [width]: Width/thickness of the zone ring (default: 25)
  ///
  /// Example:
  /// ```dart
  /// builder.addZone(10, 50, Colors.red);        // Simple zone
  /// builder.addZone(350, 10, Colors.blue);      // Wraps around 0°
  /// builder.addZone(45, 45, Colors.green, width: 15);  // Point zone
  /// ```
  void addZone(double startDegrees, double endDegrees, Color color, {double width = 25}) {
    final startNorm = AngleUtils.normalize(startDegrees);
    final endNorm = AngleUtils.normalize(endDegrees);

    if (startNorm < endNorm) {
      // Normal range: doesn't cross 0°
      _zones.add(_createRange(startNorm, endNorm, color, width));
    } else {
      // Crosses 0°: split into two ranges
      _zones.add(_createRange(startNorm, 360, color, width));
      _zones.add(_createRange(0, endNorm, color, width));
    }
  }

  /// Add a symmetrical zone centered on a specific angle
  ///
  /// Creates a zone that extends equally in both directions from the center.
  ///
  /// Parameters:
  /// - [centerDegrees]: Center angle of the zone
  /// - [halfWidthDegrees]: How far the zone extends on each side
  /// - [color]: Fill color
  /// - [thickness]: Width/thickness of the zone ring (default: 25)
  ///
  /// Example:
  /// ```dart
  /// // Create a 10° zone centered at 90° (extends from 85° to 95°)
  /// builder.addSymmetrical(90, 5, Colors.green);
  /// ```
  void addSymmetrical(
    double centerDegrees,
    double halfWidthDegrees,
    Color color, {
    double thickness = 25,
  }) {
    addZone(
      centerDegrees - halfWidthDegrees,
      centerDegrees + halfWidthDegrees,
      color,
      width: thickness,
    );
  }

  /// Add multiple gradiated zones with decreasing opacity
  ///
  /// Useful for creating visual depth by layering zones with different
  /// transparencies (e.g., port/starboard sailing zones).
  ///
  /// Parameters:
  /// - [centerDegrees]: Center reference angle for the zones
  /// - [zones]: List of zone definitions with offsets and opacities
  /// - [baseColor]: Base color to apply opacity to
  ///
  /// Example:
  /// ```dart
  /// builder.addGradiatedZones(windDirection, [
  ///   GradiatedZone(startOffset: -60, endOffset: -40, opacity: 0.6),
  ///   GradiatedZone(startOffset: -90, endOffset: -60, opacity: 0.4),
  ///   GradiatedZone(startOffset: -110, endOffset: -90, opacity: 0.25),
  /// ], Colors.red);
  /// ```
  void addGradiatedZones(
    double centerDegrees,
    List<GradiatedZone> zones,
    Color baseColor,
  ) {
    for (final zone in zones) {
      addZone(
        centerDegrees + zone.startOffset,
        centerDegrees + zone.endOffset,
        baseColor.withValues(alpha: zone.opacity),
        width: zone.width,
      );
    }
  }

  /// Add standard sailing zones for upwind sailing
  ///
  /// Creates the standard red (port) and green (starboard) zones with
  /// gradiated opacity, plus a white no-go zone.
  ///
  /// This is a convenience method that creates the typical sailing compass
  /// zone pattern used in wind compasses and autopilot widgets.
  ///
  /// Parameters:
  /// - [windDirection]: True or apparent wind direction in degrees
  /// - [targetAWA]: Target apparent wind angle (e.g., 40°)
  /// - [targetTolerance]: Tolerance for performance zones (e.g., 3°)
  ///
  /// Example:
  /// ```dart
  /// builder.addSailingZones(
  ///   windDirection: 45,
  ///   targetAWA: 40,
  ///   targetTolerance: 3,
  /// );
  /// ```
  void addSailingZones({
    required double windDirection,
    required double targetAWA,
    required double targetTolerance,
  }) {
    // PORT SIDE - Gradiated Red Zones (darker = closer to optimal)
    addGradiatedZones(windDirection, [
      GradiatedZone(startOffset: -60, endOffset: -targetAWA, opacity: 0.6),
      GradiatedZone(startOffset: -90, endOffset: -60, opacity: 0.4),
      GradiatedZone(startOffset: -110, endOffset: -90, opacity: 0.25),
      GradiatedZone(startOffset: -150, endOffset: -110, opacity: 0.15),
    ], Colors.red);

    // No-go zone (wind ± targetAWA)
    addZone(
      windDirection - targetAWA,
      windDirection + targetAWA,
      Colors.white.withValues(alpha: 0.3),
    );

    // STARBOARD SIDE - Gradiated Green Zones (darker = closer to optimal)
    addGradiatedZones(windDirection, [
      GradiatedZone(startOffset: targetAWA, endOffset: 60, opacity: 0.6),
      GradiatedZone(startOffset: 60, endOffset: 90, opacity: 0.4),
      GradiatedZone(startOffset: 90, endOffset: 110, opacity: 0.25),
      GradiatedZone(startOffset: 110, endOffset: 150, opacity: 0.15),
    ], Colors.green);

    // PERFORMANCE ZONES - Narrow bands showing optimal target AWA
    // PORT SIDE
    addGradiatedZones(windDirection, [
      GradiatedZone(
        startOffset: -targetAWA - targetTolerance,
        endOffset: -targetAWA + targetTolerance,
        opacity: 0.8,
        width: 15,
      ),
      GradiatedZone(
        startOffset: -targetAWA - (2 * targetTolerance),
        endOffset: -targetAWA - targetTolerance,
        opacity: 0.7,
        width: 15,
      ),
      GradiatedZone(
        startOffset: -targetAWA + targetTolerance,
        endOffset: -targetAWA + (2 * targetTolerance),
        opacity: 0.7,
        width: 15,
      ),
    ], Colors.green);

    // STARBOARD SIDE
    addGradiatedZones(windDirection, [
      GradiatedZone(
        startOffset: targetAWA - targetTolerance,
        endOffset: targetAWA + targetTolerance,
        opacity: 0.8,
        width: 15,
      ),
      GradiatedZone(
        startOffset: targetAWA - (2 * targetTolerance),
        endOffset: targetAWA - targetTolerance,
        opacity: 0.7,
        width: 15,
      ),
      GradiatedZone(
        startOffset: targetAWA + targetTolerance,
        endOffset: targetAWA + (2 * targetTolerance),
        opacity: 0.7,
        width: 15,
      ),
    ], Colors.yellow);
  }

  /// Add simple port/starboard zones for autopilot heading mode
  ///
  /// Creates basic red (port) and green (starboard) zones split at
  /// the current heading, used when not in wind mode.
  ///
  /// Parameters:
  /// - [currentHeading]: Current vessel heading in degrees
  /// - [opacity]: Transparency of the zones (default: 0.3)
  ///
  /// Example:
  /// ```dart
  /// builder.addHeadingZones(currentHeading: 90);
  /// ```
  void addHeadingZones({
    required double currentHeading,
    double opacity = 0.3,
  }) {
    // Port (red) - behind the boat
    addZone(
      currentHeading - 180,
      currentHeading,
      Colors.red.withValues(alpha: opacity),
    );

    // Starboard (green) - ahead of the boat
    addZone(
      currentHeading,
      currentHeading + 180,
      Colors.green.withValues(alpha: opacity),
    );
  }

  /// Clear all zones
  void clear() => _zones.clear();

  /// Get total number of zones
  int get count => _zones.length;

  /// Helper to create a GaugeRange
  GaugeRange _createRange(double start, double end, Color color, double width) {
    return GaugeRange(
      startValue: start,
      endValue: end,
      color: color,
      startWidth: width,
      endWidth: width,
    );
  }
}

/// Definition for a gradiated zone with offset and opacity
///
/// Used with [CompassZoneBuilder.addGradiatedZones] to create
/// multiple zones with varying transparency.
class GradiatedZone {
  /// Start angle offset from center (can be negative)
  final double startOffset;

  /// End angle offset from center (can be negative)
  final double endOffset;

  /// Opacity/transparency of this zone (0.0 = transparent, 1.0 = opaque)
  final double opacity;

  /// Width/thickness of the zone ring (default: 25)
  final double width;

  const GradiatedZone({
    required this.startOffset,
    required this.endOffset,
    required this.opacity,
    this.width = 25,
  });
}
