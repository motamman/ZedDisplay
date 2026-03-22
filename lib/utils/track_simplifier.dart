import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Ramer-Douglas-Peucker track simplification.
/// Reduces points while preserving shape within [toleranceMeters].
List<LatLng> simplifyTrack(List<LatLng> points, double toleranceMeters) {
  if (points.length <= 2) return List.from(points);

  // Find the point with the maximum distance from the line (first → last)
  double maxDist = 0;
  int maxIndex = 0;
  final first = points.first;
  final last = points.last;

  for (var i = 1; i < points.length - 1; i++) {
    final dist = _perpendicularDistance(points[i], first, last);
    if (dist > maxDist) {
      maxDist = dist;
      maxIndex = i;
    }
  }

  if (maxDist > toleranceMeters) {
    final left = simplifyTrack(points.sublist(0, maxIndex + 1), toleranceMeters);
    final right = simplifyTrack(points.sublist(maxIndex), toleranceMeters);
    return [...left.sublist(0, left.length - 1), ...right];
  } else {
    return [first, last];
  }
}

/// Perpendicular distance from [point] to the line segment [lineStart]→[lineEnd] in meters.
double _perpendicularDistance(LatLng point, LatLng lineStart, LatLng lineEnd) {
  const distance = Distance();

  final dAB = distance.as(LengthUnit.Meter, lineStart, lineEnd);
  if (dAB < 0.001) return distance.as(LengthUnit.Meter, point, lineStart);

  final dAP = distance.as(LengthUnit.Meter, lineStart, point);
  final dBP = distance.as(LengthUnit.Meter, lineEnd, point);

  // Heron's formula for area, then height = 2*area/base
  final s = (dAB + dAP + dBP) / 2;
  final areaSquared = s * (s - dAB) * (s - dAP) * (s - dBP);
  if (areaSquared <= 0) return 0;
  final area = math.sqrt(areaSquared);
  return 2 * area / dAB;
}
