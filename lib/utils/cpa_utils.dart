import 'dart:math' as math;

/// Pure static utility for CPA/TCPA calculations.
/// All inputs/outputs in SI units unless noted.
class CpaUtils {
  CpaUtils._();

  /// Bearing from point 1 to point 2.
  /// Inputs: lat/lon in degrees. Returns: degrees 0-360.
  static double calculateBearing(
      double lat1, double lon1, double lat2, double lon2) {
    final lat1Rad = lat1 * math.pi / 180;
    final lat2Rad = lat2 * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;

    final y = math.sin(dLon) * math.cos(lat2Rad);
    final x = math.cos(lat1Rad) * math.sin(lat2Rad) -
        math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(dLon);

    final bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360;
  }

  /// Great-circle distance between two points.
  /// Inputs: lat/lon in degrees. Returns: meters.
  static double calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0; // Earth radius in meters
    final lat1Rad = lat1 * math.pi / 180;
    final lat2Rad = lat2 * math.pi / 180;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return R * c;
  }

  /// CPA/TCPA via velocity vector dot-product method.
  /// [bearingDeg]: bearing from own vessel to target in degrees.
  /// [distanceM]: distance from own vessel to target in meters.
  /// [ownCogRad]/[ownSogMs]: own vessel COG (radians) and SOG (m/s).
  /// [targetCogRad]/[targetSogMs]: target vessel COG and SOG.
  /// Returns (cpa: meters, tcpa: seconds) or null if insufficient data.
  static ({double cpa, double tcpa})? calculateCpaTcpa({
    required double bearingDeg,
    required double distanceM,
    required double? ownCogRad,
    required double ownSogMs,
    required double? targetCogRad,
    required double? targetSogMs,
  }) {
    // Own vessel velocity components (m/s)
    double ownVx = 0.0;
    double ownVy = 0.0;
    if (ownSogMs > 0.01) {
      if (ownCogRad == null) return null; // Moving but no direction
      ownVx = ownSogMs * math.sin(ownCogRad);
      ownVy = ownSogMs * math.cos(ownCogRad);
    }

    // Target vessel velocity components (m/s)
    double targetVx = 0.0;
    double targetVy = 0.0;
    final tSog = targetSogMs ?? 0.0;
    if (tSog > 0.01 && targetCogRad != null) {
      targetVx = tSog * math.sin(targetCogRad);
      targetVy = tSog * math.cos(targetCogRad);
    }

    // Relative velocity (target relative to own)
    final relVx = targetVx - ownVx;
    final relVy = targetVy - ownVy;
    final relSpeedSq = relVx * relVx + relVy * relVy;

    if (relSpeedSq < 0.0001) {
      // Vessels moving parallel, CPA is current distance
      return (cpa: distanceM, tcpa: double.infinity);
    }

    // Current relative position (target relative to own) in meters
    final bearingRad = bearingDeg * math.pi / 180;
    final relX = distanceM * math.sin(bearingRad);
    final relY = distanceM * math.cos(bearingRad);

    // Time to CPA (dot product method)
    final tcpa = -(relX * relVx + relY * relVy) / relSpeedSq;

    if (tcpa < 0) {
      // CPA is in the past, vessels diverging
      return (cpa: distanceM, tcpa: 0);
    }

    // Position at CPA
    final cpaX = relX + relVx * tcpa;
    final cpaY = relY + relVy * tcpa;
    final cpa = math.sqrt(cpaX * cpaX + cpaY * cpaY);

    return (cpa: cpa, tcpa: tcpa);
  }
}
