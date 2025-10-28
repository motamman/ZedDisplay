import 'dart:math';

/// Utilities for angle calculations in navigation and compass widgets
///
/// Provides efficient methods for normalizing angles, calculating differences,
/// and performing common navigation calculations. All angle units are in degrees
/// unless specified otherwise.
class AngleUtils {
  /// Normalize angle to 0-360 degree range
  ///
  /// Uses modulo arithmetic for efficiency (faster than while loops).
  ///
  /// Examples:
  /// ```dart
  /// AngleUtils.normalize(370)   // Returns 10
  /// AngleUtils.normalize(-10)   // Returns 350
  /// AngleUtils.normalize(720)   // Returns 0
  /// AngleUtils.normalize(45.5)  // Returns 45.5
  /// ```
  static double normalize(double degrees) {
    degrees %= 360;
    if (degrees < 0) degrees += 360;
    return degrees;
  }

  /// Normalize angle to 0-2π radian range
  ///
  /// Examples:
  /// ```dart
  /// AngleUtils.normalizeRadians(7.0)     // Returns ~0.717 (7 - 2π)
  /// AngleUtils.normalizeRadians(-0.5)    // Returns ~5.783 (-0.5 + 2π)
  /// ```
  static double normalizeRadians(double radians) {
    radians %= (2 * pi);
    if (radians < 0) radians += (2 * pi);
    return radians;
  }

  /// Calculate shortest angular difference between two angles
  ///
  /// Returns a value in the range -180 to +180 degrees, representing
  /// the shortest rotation from angle1 to angle2.
  ///
  /// Positive values indicate clockwise rotation.
  /// Negative values indicate counter-clockwise rotation.
  ///
  /// Examples:
  /// ```dart
  /// AngleUtils.difference(10, 350)   // Returns -20 (not +340)
  /// AngleUtils.difference(350, 10)   // Returns +20 (not -340)
  /// AngleUtils.difference(0, 180)    // Returns 180
  /// AngleUtils.difference(0, 181)    // Returns -179 (shorter to go CCW)
  /// ```
  static double difference(double angle1, double angle2) {
    double diff = angle2 - angle1;
    while (diff > 180) diff -= 360;
    while (diff < -180) diff += 360;
    return diff;
  }

  /// Convert degrees to radians
  ///
  /// Example:
  /// ```dart
  /// AngleUtils.toRadians(180)  // Returns π (3.14159...)
  /// AngleUtils.toRadians(90)   // Returns π/2 (1.5708...)
  /// ```
  static double toRadians(double degrees) => degrees * pi / 180;

  /// Convert radians to degrees
  ///
  /// Example:
  /// ```dart
  /// AngleUtils.toDegrees(pi)       // Returns 180
  /// AngleUtils.toDegrees(pi / 2)   // Returns 90
  /// ```
  static double toDegrees(double radians) => radians * 180 / pi;

  /// Calculate bearing from point A (lat1, lon1) to point B (lat2, lon2)
  ///
  /// Uses the haversine formula to calculate initial bearing.
  /// Returns bearing in degrees (0-360), where:
  /// - 0° = North
  /// - 90° = East
  /// - 180° = South
  /// - 270° = West
  ///
  /// All parameters should be in decimal degrees.
  ///
  /// Example:
  /// ```dart
  /// // Bearing from New York to London
  /// final bearing = AngleUtils.bearing(40.7128, -74.0060, 51.5074, -0.1278);
  /// // Returns approximately 51° (northeast)
  /// ```
  static double bearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = toRadians(lon2 - lon1);
    final lat1Rad = toRadians(lat1);
    final lat2Rad = toRadians(lat2);

    final y = sin(dLon) * cos(lat2Rad);
    final x = cos(lat1Rad) * sin(lat2Rad) -
        sin(lat1Rad) * cos(lat2Rad) * cos(dLon);

    return normalize(toDegrees(atan2(y, x)));
  }

  /// Calculate reciprocal (opposite) bearing
  ///
  /// Returns the bearing 180° opposite to the input.
  ///
  /// Example:
  /// ```dart
  /// AngleUtils.reciprocal(45)   // Returns 225
  /// AngleUtils.reciprocal(270)  // Returns 90
  /// AngleUtils.reciprocal(0)    // Returns 180
  /// ```
  static double reciprocal(double bearing) => normalize(bearing + 180);

  /// Check if an angle is within a sector defined by center ± width
  ///
  /// Correctly handles sectors that cross 0°/360° boundary.
  ///
  /// Example:
  /// ```dart
  /// // Is 10° within 355° ± 20° sector?
  /// AngleUtils.isInSector(10, 355, 20)  // Returns true
  ///
  /// // Is 45° within 90° ± 20° sector?
  /// AngleUtils.isInSector(45, 90, 20)   // Returns false (too far)
  /// ```
  static bool isInSector(double angle, double center, double halfWidth) {
    final diff = difference(center, angle).abs();
    return diff <= halfWidth;
  }

  /// Average a list of angles using vector arithmetic
  ///
  /// Correctly handles angles that cross the 0°/360° boundary.
  /// For example, averaging [359°, 1°] returns 0° (not 180°).
  ///
  /// Returns null if the list is empty.
  ///
  /// Example:
  /// ```dart
  /// AngleUtils.average([10, 20, 30])       // Returns 20
  /// AngleUtils.average([359, 1, 2])        // Returns ~0.67
  /// AngleUtils.average([90, 180, 270, 0])  // Returns ~135
  /// ```
  static double? average(List<double> angles) {
    if (angles.isEmpty) return null;

    // Use vector averaging to handle wraparound
    double sumSin = 0;
    double sumCos = 0;

    for (final angle in angles) {
      final radians = toRadians(angle);
      sumSin += sin(radians);
      sumCos += cos(radians);
    }

    final avgRadians = atan2(sumSin / angles.length, sumCos / angles.length);
    return normalize(toDegrees(avgRadians));
  }

  /// Calculate compass point name for a given bearing
  ///
  /// Returns 16-point compass rose names:
  /// N, NNE, NE, ENE, E, ESE, SE, SSE, S, SSW, SW, WSW, W, WNW, NW, NNW
  ///
  /// Example:
  /// ```dart
  /// AngleUtils.toCompassPoint(0)      // Returns "N"
  /// AngleUtils.toCompassPoint(45)     // Returns "NE"
  /// AngleUtils.toCompassPoint(337.5)  // Returns "NNW"
  /// ```
  static String toCompassPoint(double bearing) {
    const points = [
      'N', 'NNE', 'NE', 'ENE',
      'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW',
      'W', 'WNW', 'NW', 'NNW'
    ];

    final normalized = normalize(bearing);
    final index = ((normalized + 11.25) / 22.5).floor() % 16;
    return points[index];
  }
}
