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

  /// Read a persisted distance value in SI (meters) from a
  /// `customProperties` map.
  ///
  /// Prefers the SI-keyed entry at [siKey]. Falls back to a legacy
  /// display-unit-keyed entry at [legacyNmKey] (interpreted as nautical
  /// miles and converted via [metersPerNauticalMile]). Finally returns
  /// [defaultMeters] when neither key is present.
  ///
  /// This exists to migrate tool configs that historically stored
  /// thresholds in display units (`*Nm`) to SI persistence (`*Meters`)
  /// without losing user-saved values. Callers write only the SI key;
  /// legacy `*Nm` entries get picked up on next read and effectively
  /// converted the moment the user next saves that config through its UI.
  static double readDistanceMeters(
    Map<String, dynamic>? props, {
    required String siKey,
    required String legacyNmKey,
    required double defaultMeters,
  }) {
    if (props == null) return defaultMeters;
    final si = (props[siKey] as num?)?.toDouble();
    if (si != null) return si;
    final nm = (props[legacyNmKey] as num?)?.toDouble();
    if (nm != null) return nm * metersPerNauticalMile;
    return defaultMeters;
  }
}
