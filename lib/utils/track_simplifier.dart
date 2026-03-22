import 'package:latlong2/latlong.dart';

/// Course-delta track simplification for marine route creation.
///
/// Preserves waypoints at turns while removing redundant straight-line points.
/// Unlike Ramer-Douglas-Peucker, this never cuts corners through dangerous waters.
///
/// [headingThresholdDeg] — cumulative heading change (degrees) that triggers a new waypoint.
/// Lower = more waypoints (tighter turns preserved), higher = fewer waypoints.
///
/// [maxLegMeters] — maximum distance between waypoints. Prevents long straight
/// legs with no intermediate waypoints. Default 2 NM (3704m).
List<LatLng> simplifyTrack(
  List<LatLng> points,
  double headingThresholdDeg, {
  double maxLegMeters = 3704.0,
}) {
  if (points.length <= 2) return List.from(points);

  const dist = Distance();
  final result = <LatLng>[points.first];

  var lastKeptIndex = 0;
  var prevBearing = dist.bearing(points[0], points[1]);

  for (var i = 1; i < points.length - 1; i++) {
    final bearing = dist.bearing(points[i], points[i + 1]);

    // Heading change between consecutive segments
    var delta = (bearing - prevBearing).abs();
    if (delta > 180) delta = 360 - delta;

    // Distance from last kept waypoint
    final legDist = dist.as(LengthUnit.Meter, points[lastKeptIndex], points[i]);

    if (delta >= headingThresholdDeg || legDist >= maxLegMeters) {
      result.add(points[i]);
      lastKeptIndex = i;
    }

    prevBearing = bearing;
  }

  // Always keep the last point
  result.add(points.last);
  return result;
}

/// Calculate total distance of a track in meters.
double trackDistanceMeters(List<LatLng> points) {
  const dist = Distance();
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += dist.as(LengthUnit.Meter, points[i - 1], points[i]);
  }
  return total;
}

/// Convert meters to nautical miles.
double metersToNM(double meters) => meters / 1852.0;
