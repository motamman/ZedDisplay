/// Antimeridian (±180° / international date line) helpers for
/// flutter_map custom-painter overlays.
///
/// flutter_map repeats the world across ±180 but `projectAtZoom` only
/// ever yields the one canonical pixel for a longitude, so a custom
/// painter whose geometry crosses the date line either streaks a
/// straight Mercator line across the whole map or shows on only one
/// side when the viewport is panned across the seam. Unwrapping
/// longitudes — making them path-continuous, then shifting the whole
/// thing to the world copy nearest the camera — fixes both.
///
/// Single source of truth shared by `WeatherRoutePainter` (the weather
/// route) and `_RoutePainter` (the SignalK editable route) so the two
/// can't drift. Logic mirrors `routePlanning/ui/route-planner.html`
/// and the backend's `_split_antimeridian`.
library;

/// Make a polyline's longitudes path-continuous (no ±360 jump between
/// consecutive points), then shift the whole thing to the world copy
/// nearest [cameraLon]. Meant to be recomputed every paint, so the
/// route follows the camera across the seam. Returns fresh
/// `[lon, lat]` lists; `lat` is untouched. An empty input is returned
/// unchanged.
List<List<double>> unwrapLonForCamera(
    List<List<double>> coords, double cameraLon) {
  if (coords.isEmpty) return coords;
  final out = <List<double>>[
    [coords[0][0], coords[0][1]]
  ];
  for (var i = 1; i < coords.length; i++) {
    var d = coords[i][0] - coords[i - 1][0];
    d -= 360.0 * (d / 360.0).roundToDouble(); // shortest signed step
    out.add([out[i - 1][0] + d, coords[i][1]]);
  }
  final shift = 360.0 * ((cameraLon - out[0][0]) / 360.0).roundToDouble();
  if (shift != 0.0) {
    for (final p in out) {
      p[0] += shift;
    }
  }
  return out;
}

/// Bring a lone `[lon, lat]` (e.g. a snap-original endpoint) into the
/// same world copy as its already-unwrapped route anchor so the pin /
/// dashed bridge land beside the route, not a world copy away.
/// `null` → `null`.
List<double>? unwrapLonNear(List<double>? p, double anchorLon) {
  if (p == null) return null;
  var d = p[0] - anchorLon;
  d -= 360.0 * (d / 360.0).roundToDouble();
  return [anchorLon + d, p[1]];
}
