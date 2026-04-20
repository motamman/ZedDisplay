/// Numeric constants used for navigation math (unit scale factors,
/// compass arithmetic). These exist for code that is legitimately
/// computing in nautical miles / degrees, not as a silent conversion
/// fallback — prefer [MetadataStore] for user-facing unit conversions.
library;

class NavigationConstants {
  NavigationConstants._();

  /// Meters in one nautical mile (SI definition: exactly 1852 m).
  static const double metersPerNauticalMile = 1852.0;

  /// Meters in one statute mile.
  static const double metersPerStatuteMile = 1609.344;

  /// Conversion factor m/s → knots.
  static const double knotsPerMps = 1.94384;

  /// Degrees in a full circle. Used for compass wraparound (`(x + 360) % 360`).
  static const int fullCircleDegrees = 360;

  /// Half-circle in degrees. Used for ±180° normalisation.
  static const int halfCircleDegrees = 180;
}
