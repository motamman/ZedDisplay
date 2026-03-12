import 'dart:math' as math;

/// Result of a dodge intercept calculation.
class DodgeResult {
  /// Heading to steer (radians, navigational: 0=N, CW)
  final double courseToSteerRad;

  /// Time to reach the apex point (seconds)
  final double timeToApexSeconds;

  /// Apex point in local Cartesian (meters from own vessel, X=East, Y=North)
  final double apexX, apexY;

  /// Target position at apex time (meters from own vessel)
  final double targetAtApexX, targetAtApexY;

  /// Whether the intercept is geometrically feasible
  final bool isFeasible;

  /// Whether a bow pass meets safety criteria (t > 60s, course change < 90°)
  final bool bowPassSafe;

  const DodgeResult({
    required this.courseToSteerRad,
    required this.timeToApexSeconds,
    required this.apexX,
    required this.apexY,
    required this.targetAtApexX,
    required this.targetAtApexY,
    required this.isFeasible,
    required this.bowPassSafe,
  });
}

/// Pure static utility for dodge intercept calculations.
/// All inputs/outputs in SI units (radians, m/s, meters) unless noted.
///
/// Coordinate frame: local Cartesian, X=East, Y=North (matches CpaUtils).
class DodgeUtils {
  DodgeUtils._();

  /// Minimum own SOG to attempt dodge (m/s) — ~0.5 knot
  static const _minOwnSog = 0.25;

  /// Maximum time horizon (seconds) — 30 minutes
  static const _maxTimeHorizon = 1800.0;

  /// Calculate the dodge course to pass behind (or ahead of) a moving target
  /// at a safe distance.
  ///
  /// [bearingDeg]: bearing from own vessel to target (degrees 0-360).
  /// [distanceM]: range to target (meters).
  /// [ownSogMs]: own speed over ground (m/s).
  /// [targetCogRad]: target COG (radians, navigational).
  /// [targetSogMs]: target SOG (m/s).
  /// [safeDistanceM]: offset distance astern/ahead of target (default 300m).
  /// [bowPass]: false = pass astern (default), true = pass ahead.
  ///
  /// Returns null if infeasible (own vessel too slow, no positive root, etc.).
  static DodgeResult? calculateDodge({
    required double bearingDeg,
    required double distanceM,
    required double ownSogMs,
    required double targetCogRad,
    required double targetSogMs,
    required double safeDistanceM,
    required bool bowPass,
  }) {
    // Own vessel too slow
    if (ownSogMs < _minOwnSog) return null;

    // Target velocity in Cartesian (X=East, Y=North)
    final vtx = targetSogMs * math.sin(targetCogRad);
    final vty = targetSogMs * math.cos(targetCogRad);

    // Target position relative to own vessel
    final bearingRad = bearingDeg * math.pi / 180;
    final tx = distanceM * math.sin(bearingRad);
    final ty = distanceM * math.cos(bearingRad);

    // Offset point: astern = behind target along its COG
    // Astern offset is opposite to target's heading direction
    final sign = bowPass ? 1.0 : -1.0;
    final offsetX = sign * safeDistanceM * math.sin(targetCogRad);
    final offsetY = sign * safeDistanceM * math.cos(targetCogRad);

    // Handle near-stationary target: aim for the offset point directly
    if (targetSogMs < 0.1) {
      final dx = tx + offsetX;
      final dy = ty + offsetY;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < 1.0) return null;

      final courseRad = math.atan2(dx, dy); // navigational atan2(E, N)
      final t = dist / ownSogMs;

      return DodgeResult(
        courseToSteerRad: _normalizeRad(courseRad),
        timeToApexSeconds: t,
        apexX: dx,
        apexY: dy,
        targetAtApexX: tx,
        targetAtApexY: ty,
        isFeasible: true,
        bowPassSafe: true, // stationary target, always safe
      );
    }

    // Vector from own vessel to the moving offset point at time t:
    // P(t) = D + Vt * t, where D = target_pos + offset, Vt = target velocity
    // We need |P(t)| = ownSog * t
    //
    // Quadratic: (|Vt|² - ownSog²) * t² + 2*(D · Vt) * t + |D|² = 0
    final dx = tx + offsetX;
    final dy = ty + offsetY;

    final vtSq = vtx * vtx + vty * vty;
    final ownSogSq = ownSogMs * ownSogMs;

    final a = vtSq - ownSogSq;
    final b = 2.0 * (dx * vtx + dy * vty);
    final c = dx * dx + dy * dy;

    double? t = _solveSmallestPositive(a, b, c);

    // No positive root → infeasible
    if (t == null) return null;

    // Cap at max time horizon
    if (t > _maxTimeHorizon) return null;

    // Apex point: where the offset point will be at time t
    final apexX = dx + vtx * t;
    final apexY = dy + vty * t;

    // Target position at apex time
    final tatX = tx + vtx * t;
    final tatY = ty + vty * t;

    // Course to steer: direction from own vessel to apex
    final courseRad = math.atan2(apexX, apexY); // navigational atan2(E, N)

    // Bow pass safety check: t > 60s and course change < 90°
    final ownCogRad = math.atan2(
      ownSogMs * math.sin(bearingRad),
      ownSogMs * math.cos(bearingRad),
    );
    final courseChange = _angleDiffRad(courseRad, ownCogRad).abs();
    final bowSafe = t > 60.0 && courseChange < math.pi / 2;

    return DodgeResult(
      courseToSteerRad: _normalizeRad(courseRad),
      timeToApexSeconds: t,
      apexX: apexX,
      apexY: apexY,
      targetAtApexX: tatX,
      targetAtApexY: tatY,
      isFeasible: true,
      bowPassSafe: bowSafe,
    );
  }

  /// Solve a*t² + b*t + c = 0, return smallest positive root or null.
  static double? _solveSmallestPositive(double a, double b, double c) {
    if (a.abs() < 1e-9) {
      // Linear: b*t + c = 0
      if (b.abs() < 1e-9) return null;
      final t = -c / b;
      return t > 0 ? t : null;
    }

    final discriminant = b * b - 4 * a * c;
    if (discriminant < 0) return null;

    final sqrtD = math.sqrt(discriminant);
    final t1 = (-b + sqrtD) / (2 * a);
    final t2 = (-b - sqrtD) / (2 * a);

    double? best;
    if (t1 > 0.1) best = t1;
    if (t2 > 0.1 && (best == null || t2 < best)) best = t2;
    return best;
  }

  /// Normalize radians to [0, 2π).
  static double _normalizeRad(double rad) {
    rad %= (2 * math.pi);
    if (rad < 0) rad += 2 * math.pi;
    return rad;
  }

  /// Shortest angular difference in radians, range [-π, π].
  static double _angleDiffRad(double a, double b) {
    var diff = a - b;
    while (diff > math.pi) {
      diff -= 2 * math.pi;
    }
    while (diff < -math.pi) {
      diff += 2 * math.pi;
    }
    return diff;
  }
}
