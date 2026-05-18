import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/weather_route_result.dart';
import '../../utils/antimeridian.dart';

/// Colour palette lifted verbatim from the web UI at
/// `routePlanning/ui/route-planner.html` so the chart and the web planner
/// speak the same visual language. Numeric hexes come from that file's CSS
/// plus the inline OpenLayers styles.
class WeatherRouteColors {
  WeatherRouteColors._();

  static const starboardTack = Color(0xFF2E7D32);
  static const portTack = Color(0xFFD32F2F);
  // Amber `#FFCC44` matches the web UI (`color = '#fc4'` in
  // route-planner.html:1059) and the MOTORING badge foreground in
  // WeatherRoutingItineraryCard._badgeColors, so the chart leg,
  // waypoint ring, chevron and card accent all render in the same
  // colour — mirroring how starboard/port sailing is styled.
  static const motoring = Color(0xFFFFCC44);
  static const arrival = Color(0xFF8888FF);

  static const startFill = Color(0xFF4CAF50);
  static const endFill = Color(0xFFF44336);
  static const waypointFill = Color(0xFFFF9800);
  static const markerStroke = Color(0xFFFFFFFF);

  static const selectionFill = Color(0x2E00E5FF);
  static const selectionStroke = Color(0xFF00E5FF);

  static const windArrow = Color(0xFF1565C0);
}

/// Classifies the leg **departing** a waypoint so each waypoint is
/// coloured by the tack it's about to start, not the tack that just
/// ended at it.
///
/// Matches `route-planner.html:505-510`'s `next_*` convention:
/// waypoint i's "next cog/wind" are the values sampled at waypoint
/// i+1 (the course the vessel is taking to reach i+1, and the wind
/// there). This is how the web UI colours the on-map waypoint ring
/// and the itinerary-card accent. The server rarely populates
/// `outgoing_cog_deg`, so using wp[i]'s own fields would collapse to
/// the arriving leg — producing the "turning from port to starboard
/// is shown as port" glitch.
enum WeatherRouteLegKind { starboardTack, portTack, motoring, arrival }

WeatherRouteLegKind legKindAt(List<WeatherRouteWaypoint> wps, int i) {
  if (i < 0 || i >= wps.length) return WeatherRouteLegKind.motoring;
  if (i == wps.length - 1) return WeatherRouteLegKind.arrival;
  final wp = wps[i];
  final next = wps[i + 1];
  if (next.isMotoring) return WeatherRouteLegKind.motoring;
  // COG for the leg wp→next: prefer wp's own `outgoing_cog_deg` when
  // the server provides it; otherwise use next's `cog_deg` (= the
  // incoming bearing at next, which is the same physical leg).
  // Wind: sampled at `next` per the web UI's `next_wind` semantics,
  // with wp's wind as a safety fallback.
  final cog = wp.outgoingCogDeg ?? next.cogDeg;
  final wind = next.windDirDeg ?? wp.windDirDeg;
  if (cog == null || wind == null) return WeatherRouteLegKind.motoring;
  final rel = ((cog - wind) % 360 + 360) % 360;
  return rel <= 180
      ? WeatherRouteLegKind.starboardTack
      : WeatherRouteLegKind.portTack;
}

Color colorForLegKind(WeatherRouteLegKind k) {
  switch (k) {
    case WeatherRouteLegKind.starboardTack:
      return WeatherRouteColors.starboardTack;
    case WeatherRouteLegKind.portTack:
      return WeatherRouteColors.portTack;
    case WeatherRouteLegKind.motoring:
      return WeatherRouteColors.motoring;
    case WeatherRouteLegKind.arrival:
      return WeatherRouteColors.arrival;
  }
}

/// Paints a computed weather route on top of the chart.
///
/// Visual spec is a port of `routePlanning/ui/route-planner.html`:
/// - 3 px route polyline, per-segment colour chosen by tack / motoring / arrival
/// - 10 px waypoint circles (green Start, red End, orange Intermediate)
///   with 2 px white stroke and 11 px bold white "S" / "E" / "W{n}" label
/// - 16 px inner leg ring, stroke coloured by leg kind
/// - Selection halo: 28 px cyan fill + stroke, plus 22 px inner white ring
/// - Wind arrow and vessel chevron at the selected waypoint
class WeatherRouteOverlayLayer extends StatelessWidget {
  const WeatherRouteOverlayLayer({
    super.key,
    required this.result,
    required this.selectedIndex,
  });

  final WeatherRouteResult result;
  final int? selectedIndex;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: WeatherRoutePainter(
          camera: camera,
          result: result,
          selectedIndex: selectedIndex,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class WeatherRoutePainter extends CustomPainter {
  WeatherRoutePainter({
    required this.camera,
    required this.result,
    required this.selectedIndex,
  });

  final MapCamera camera;
  final WeatherRouteResult result;
  final int? selectedIndex;

  /// Screen radius (px) of the circular waypoint markers. Also used for
  /// chart tap hit-testing by the V3 tool.
  static const double waypointRadius = 10;
  static const double innerRingRadius = 16;
  static const double selectionOuterRadius = 28;
  static const double selectionInnerRadius = 22;

  @override
  void paint(Canvas canvas, Size size) {
    final rawCoords = result.coords;
    if (rawCoords.length < 2) return;
    final wps = result.waypoints;
    final origin = camera.pixelOrigin;
    Offset project(List<double> lonLat) =>
        camera.projectAtZoom(LatLng(lonLat[1], lonLat[0])) - origin;

    // flutter_map renders the world in repeating copies across ±180°,
    // but `projectAtZoom` maps a lon to its one canonical pixel. Make
    // the route's longitudes path-continuous and shift the whole thing
    // to the world copy nearest the camera so it (a) never streaks
    // across the map at the date line and (b) stays fully visible when
    // the user pans across ±180 (recomputed every paint). All
    // downstream decoration derives from `points`, so the polyline,
    // rings, chevrons, markers and selection halo stay aligned.
    final coords =
        unwrapLonForCamera(rawCoords, camera.center.longitude);
    final points = coords.map(project).toList(growable: false);
    // Snap-original points unwrapped into the same world copy as their
    // route anchor (used by the selection halo, S/E pins and bridge).
    final startOrigU =
        unwrapLonNear(result.summary.startOriginal, coords.first[0]);
    final endOrigU =
        unwrapLonNear(result.summary.endOriginal, coords.last[0]);

    // Precompute a leg kind per segment. Segment i goes from point[i] to
    // point[i+1]; each segment is coloured by the tack of the leg
    // departing point[i], matching route-planner.html's per-segment
    // style function. The final waypoint's ring gets the arrival colour
    // via `kindAt` below — the segment itself keeps its tack colour.
    final legKinds = List<WeatherRouteLegKind>.generate(
      points.length - 1,
      (i) => (i >= wps.length - 1)
          ? WeatherRouteLegKind.motoring
          : legKindAt(wps, i),
      growable: false,
    );

    // Per-waypoint kind — forward-looking, matching route-planner.html's
    // `next_*` style convention. Arrival kind on the last waypoint.
    WeatherRouteLegKind kindAt(int i) {
      if (i == points.length - 1) return WeatherRouteLegKind.arrival;
      if (i < legKinds.length) return legKinds[i];
      return WeatherRouteLegKind.motoring;
    }

    // 1) Route polyline — per-segment colour chosen by the departing
    //    waypoint's leg kind.
    final linePaint = Paint()
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // `coords` is already path-continuous (see `unwrapLonForCamera`), so
    // consecutive points never jump ±180 — a plain segment draw is
    // both streak-free and renders in the visible world copy.
    for (var i = 0; i < points.length - 1; i++) {
      linePaint.color = colorForLegKind(legKinds[i]);
      canvas.drawLine(points[i], points[i + 1], linePaint);
    }

    // 2) Selection halo — under the waypoint decoration so the ring,
    //    chevron, and wind arrow sit on top. Virtual sentinels (-1 /
    //    waypoints.length) get a halo at the snap-aware pin position
    //    so the user sees feedback when their click landed on the
    //    relocated start/end marker; real-waypoint indices get the
    //    halo at the waypoint anchor as before.
    final sel = selectedIndex;
    Offset? haloCentre;
    if (sel != null && points.isNotEmpty) {
      if (sel == -1) {
        haloCentre = _snapAwarePinPosition(
          isStart: true,
          original: startOrigU,
          anchorPx: points.first,
          origin: origin,
        );
      } else if (sel == wps.length) {
        haloCentre = _snapAwarePinPosition(
          isStart: false,
          original: endOrigU,
          anchorPx: points.last,
          origin: origin,
        );
      } else if (sel >= 0 && sel < points.length) {
        haloCentre = points[sel];
      }
    }
    if (haloCentre != null) {
      canvas.drawCircle(
        haloCentre,
        selectionOuterRadius,
        Paint()..color = WeatherRouteColors.selectionFill,
      );
      canvas.drawCircle(
        haloCentre,
        selectionOuterRadius,
        Paint()
          ..color = WeatherRouteColors.selectionStroke
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke,
      );
      canvas.drawCircle(
        haloCentre,
        selectionInnerRadius,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }

    // 3) Waypoint decoration — for every waypoint, ring + vessel chevron
    //    + wind arrow (matches route-planner.html). Start and End also
    //    get a filled circle with an S / E label; intermediates do not.
    final ringPaint = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < points.length; i++) {
      final isStart = i == 0;
      final isEnd = i == points.length - 1;
      final kind = kindAt(i);
      final colour = colorForLegKind(kind);

      // Outer ring — stroke widens when selected.
      ringPaint.color = colour;
      ringPaint.strokeWidth = (selectedIndex == i) ? 5 : 2;
      canvas.drawCircle(points[i], innerRingRadius, ringPaint);

      // Vessel chevron and wind arrow at every waypoint, provided we
      // have matching waypoint metadata (LineString geometry can be
      // simplified to fewer points than waypoints in edge cases).
      if (i < wps.length) {
        // Chevron points along the OUTGOING leg (where the vessel is
        // about to go), not the incoming leg. Server's `cog_deg` at
        // wps[i+1] is the haversine bearing from wps[i] → wps[i+1],
        // which IS the outgoing direction from wps[i]. For the last
        // waypoint (no outgoing leg) fall back to its own cog so the
        // arrival marker still points sensibly.
        final outgoingCog = (i + 1 < wps.length)
            ? wps[i + 1].cogDeg
            : wps[i].cogDeg;
        _paintVesselChevron(canvas, points[i], outgoingCog, kind);
        _paintWindArrow(canvas, points[i], wps[i]);
      }

      // Only Start / End get the filled circle + label; intermediates
      // are ring-only so the chevron and wind arrow read cleanly. Pin
      // position is snap-aware: when the router moved the route's
      // actual start / end away from the user's clicked point to find
      // a navigable cell, the pin sits at the user's intent
      // (`*_original`) and the dashed-bridge pass below joins it to
      // the route's actual endpoint at `points[i]`.
      if (isStart || isEnd) {
        final fill = isStart
            ? WeatherRouteColors.startFill
            : WeatherRouteColors.endFill;
        final pinPx = _snapAwarePinPosition(
          isStart: isStart,
          original: isStart ? startOrigU : endOrigU,
          anchorPx: points[i],
          origin: origin,
        );
        canvas.drawCircle(pinPx, waypointRadius, Paint()..color = fill);
        canvas.drawCircle(
          pinPx,
          waypointRadius,
          Paint()
            ..color = WeatherRouteColors.markerStroke
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
        _paintLabel(canvas, pinPx, isStart ? 'S' : 'E');
      }
    }

    // Dashed maroon bridge from each `*_original` to its anchor
    // when the router had to snap. Painted after the per-waypoint
    // loop so the dashed segment sits over the ring / chevron
    // without those decorations occluding the bridge endpoints.
    _paintSnapBridge(
      canvas: canvas,
      origin: origin,
      original: startOrigU,
      anchorPx: points.first,
      snapDistanceM: result.summary.startSnapDistanceM,
    );
    _paintSnapBridge(
      canvas: canvas,
      origin: origin,
      original: endOrigU,
      anchorPx: points.last,
      snapDistanceM: result.summary.endSnapDistanceM,
    );
  }

  /// Project the (already camera-copy-unwrapped) snap-original
  /// `[lon, lat]` to screen pixels when the router moved the route's
  /// start / end. Falls back to the anchor pixel (no snap → pin at the
  /// actual endpoint).
  Offset _snapAwarePinPosition({
    required bool isStart,
    required List<double>? original,
    required Offset anchorPx,
    required Offset origin,
  }) {
    final snapDist = isStart
        ? result.summary.startSnapDistanceM
        : result.summary.endSnapDistanceM;
    if (original == null || snapDist == null || snapDist <= 0) {
      return anchorPx;
    }
    return camera.projectAtZoom(LatLng(original[1], original[0])) - origin;
  }

  /// Maroon (`#7F0000`) dashed line connecting the user's clicked
  /// start / end (`*_original`) to the route's actual endpoint
  /// (`*_anchor`, == `points.first` / `points.last`). Visible only
  /// when the snap distance is non-zero — a snap of exactly zero
  /// means the click hit a navigable cell directly.
  void _paintSnapBridge({
    required Canvas canvas,
    required Offset origin,
    required List<double>? original,
    required Offset anchorPx,
    required double? snapDistanceM,
  }) {
    if (original == null) return;
    if (snapDistanceM == null || snapDistanceM <= 0) return;
    final originPx =
        camera.projectAtZoom(LatLng(original[1], original[0])) - origin;
    _paintDashedLine(canvas, originPx, anchorPx, const Color(0xFF7F0000));
  }


  /// Stroke a dashed line between two screen-space offsets. Dash
  /// length 6 px, gap 4 px. Flutter has no native dashed-stroke
  /// primitive; this walks the segment and emits short individual
  /// `drawLine` calls so the dashes render correctly even at
  /// odd lengths and zoom levels.
  static void _paintDashedLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Color color,
  ) {
    const dashLen = 6.0;
    const gapLen = 4.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 0.5) return;
    final ux = dx / dist;
    final uy = dy / dist;
    final stepCount = (dist / (dashLen + gapLen)).floor();
    for (var i = 0; i < stepCount; i++) {
      final t0 = i * (dashLen + gapLen);
      final t1 = t0 + dashLen;
      canvas.drawLine(
        Offset(a.dx + ux * t0, a.dy + uy * t0),
        Offset(a.dx + ux * t1, a.dy + uy * t1),
        paint,
      );
    }
    // Trailing partial dash so the bridge always reaches the
    // anchor visually instead of stopping short at the last full
    // dash boundary.
    final lastStart = stepCount * (dashLen + gapLen);
    if (lastStart < dist) {
      final endT = math.min(lastStart + dashLen, dist);
      canvas.drawLine(
        Offset(a.dx + ux * lastStart, a.dy + uy * lastStart),
        Offset(a.dx + ux * endT, a.dy + uy * endT),
        paint,
      );
    }
  }

  void _paintLabel(Canvas canvas, Offset centre, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    tp.layout();
    tp.paint(
      canvas,
      Offset(centre.dx - tp.width / 2, centre.dy - tp.height / 2),
    );
  }

  void _paintWindArrow(
      Canvas canvas, Offset centre, WeatherRouteWaypoint wp) {
    final dirFromDeg = wp.windDirDeg;
    if (dirFromDeg == null) return;
    // Web UI offsets the arrow 22 px upwind so it "points toward where the
    // wind is going" from just upwind of the waypoint. Upwind direction on
    // screen = wind_from direction. Going direction = wind_from + 180°.
    final upwindRad = _deg2screenRad(dirFromDeg);
    final offset = Offset(
      centre.dx + 22 * math.sin(upwindRad),
      centre.dy - 22 * math.cos(upwindRad),
    );
    final goingRad = _deg2screenRad(dirFromDeg + 180);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.rotate(goingRad);
    final path = ui.Path()
      ..moveTo(0, -14) // arrow tip
      ..lineTo(-7, 0)
      ..lineTo(0, -3)
      ..lineTo(7, 0)
      ..close()
      ..addRect(const Rect.fromLTWH(-2, -3, 4, 17)); // shaft
    canvas.drawPath(path, Paint()..color = WeatherRouteColors.windArrow);
    canvas.restore();
  }

  void _paintVesselChevron(
    Canvas canvas,
    Offset centre,
    double? cogDeg,
    WeatherRouteLegKind kind,
  ) {
    if (cogDeg == null) return;
    final rot = _deg2screenRad(cogDeg);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(rot);
    final path = ui.Path()
      ..moveTo(0, -16)
      ..lineTo(-8, 0)
      ..lineTo(0, -4)
      ..lineTo(8, 0)
      ..close()
      ..addRect(const Rect.fromLTWH(-3, -4, 6, 18));
    canvas.drawPath(path, Paint()..color = colorForLegKind(kind));
    canvas.restore();
  }

  /// Converts a compass bearing in degrees (0°=N, 90°=E) into a canvas
  /// rotation in radians where 0 rad points to screen-top (i.e. toward the
  /// camera's +y = -screen y). This matches the same formula used by
  /// `_RoutePainter` at chart_plotter_v3_tool.dart:3851 — `atan2(dx, -dy)`
  /// evaluated for a vector whose angle from north is `deg`.
  static double _deg2screenRad(double deg) => deg * math.pi / 180.0;

  @override
  bool shouldRepaint(covariant WeatherRoutePainter old) =>
      old.camera != camera ||
      old.result != result ||
      old.selectedIndex != selectedIndex;
}

/// Paints a translucent white halo around each intermediate via
/// pin when the user has the routing service set to
/// `approximate` precision. The halo's geographic radius matches
/// the server's `arrival_radius_m` parameter — so the user can
/// see, before pressing Compute, how loose the arrival proximity
/// is around each waypoint. The radius is in meters and scales
/// with zoom (closer-in zooms paint a larger pixel ring; farther-
/// out zooms paint a tighter one).
///
/// Halos are drawn ONLY for intermediate vias because the server
/// treats start and end as exact regardless of precision — the
/// `arrival_radius_m` field is ignored for those.
class WeatherRouteApproxHaloLayer extends StatelessWidget {
  const WeatherRouteApproxHaloLayer({
    super.key,
    required this.vias,
    required this.radiusM,
  });

  final List<LatLng> vias;
  final double radiusM;

  @override
  Widget build(BuildContext context) {
    if (vias.isEmpty || radiusM <= 0) return const SizedBox.shrink();
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _ApproxHaloPainter(
          camera: camera,
          vias: vias,
          radiusM: radiusM,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _ApproxHaloPainter extends CustomPainter {
  _ApproxHaloPainter({
    required this.camera,
    required List<LatLng> vias,
    required this.radiusM,
  }) : vias = List<LatLng>.unmodifiable(vias);

  final MapCamera camera;
  /// Snapshot taken at construction. Defensive against an upstream
  /// caller that caches and mutates the source list in place — the
  /// `identical` short-circuit in shouldRepaint would otherwise
  /// hide content changes. The wrap is a single allocation per
  /// rebuild and the painter rebuilds on every camera change anyway,
  /// so cost is negligible.
  final List<LatLng> vias;
  final double radiusM;

  /// Geodesic distance helper — produces a true offset point given a
  /// LatLng + bearing + distance, so the halo's pixel radius tracks
  /// the WebMercator projection (and any latitude-dependent stretch)
  /// rather than a hardcoded meters-per-degree-latitude constant.
  /// Bearing 0° is north — irrelevant which compass heading we pick
  /// since we measure pixel distance back to the centre, but north
  /// avoids the cosine term that would otherwise distort the ring
  /// near the poles.
  static const Distance _geo = Distance();

  @override
  void paint(Canvas canvas, Size size) {
    final origin = camera.pixelOrigin;
    final fillPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final via in vias) {
      final centre = camera.projectAtZoom(via) - origin;
      // `Distance.offset` returns the geodesic point `radiusM`
      // meters away on the given bearing. Project both points and
      // measure their pixel separation — the result is whatever the
      // current map projection makes [radiusM] resolve to in pixels.
      final north = _geo.offset(via, radiusM, 0);
      final northPx = camera.projectAtZoom(north) - origin;
      final pxRadius = (centre - northPx).distance;
      if (pxRadius < 0.5) continue;
      canvas.drawCircle(centre, pxRadius, fillPaint);
      canvas.drawCircle(centre, pxRadius, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ApproxHaloPainter old) =>
      old.camera != camera ||
      old.radiusM != radiusM ||
      !_listEquals(old.vias, vias);

  /// Length + element comparison. No `identical` short-circuit so a
  /// mutated-in-place list never hides a content change — paranoid
  /// given the unmodifiable snapshot in the constructor, but cheap.
  static bool _listEquals(List<LatLng> a, List<LatLng> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Hit-tests a tap against the waypoint markers of a weather route.
/// Returns the index of the nearest waypoint within [radius] pixels, or
/// null if the tap doesn't land on any marker.
///
/// Both the tap and each waypoint are projected through the SAME
/// camera-copy longitude unwrap `WeatherRoutePainter.paint` uses
/// (`unwrapLonNear` toward the camera centre), so a route crossing
/// ±180° — drawn in the camera's world copy — stays hit-testable
/// instead of the canonical projection looking a world-width away.
int? hitTestWeatherRouteWaypoint({
  required WeatherRouteResult result,
  required MapCamera camera,
  required LatLng tap,
  double radius = WeatherRoutePainter.innerRingRadius + 2,
}) {
  if (result.coords.isEmpty) return null;
  final origin = camera.pixelOrigin;
  final camLon = camera.center.longitude;
  Offset scrUnwrapped(double lon, double lat) {
    final u = unwrapLonNear([lon, lat], camLon)!;
    return camera.projectAtZoom(LatLng(u[1], u[0])) - origin;
  }

  final tapPx = scrUnwrapped(tap.longitude, tap.latitude);
  int? best;
  double bestDist = radius;
  for (var i = 0; i < result.coords.length; i++) {
    final c = result.coords[i];
    final p = scrUnwrapped(c[0], c[1]);
    final d = (p - tapPx).distance;
    if (d < bestDist) {
      bestDist = d;
      best = i;
    }
  }
  return best;
}
