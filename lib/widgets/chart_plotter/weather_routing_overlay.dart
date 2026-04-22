import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/weather_route_result.dart';

/// Colour palette lifted verbatim from the web UI at
/// `routePlanning/ui/route-planner.html` so the chart and the web planner
/// speak the same visual language. Numeric hexes come from that file's CSS
/// plus the inline OpenLayers styles.
class WeatherRouteColors {
  WeatherRouteColors._();

  static const starboardTack = Color(0xFF2E7D32);
  static const portTack = Color(0xFFD32F2F);
  static const motoring = Color(0xFF000000);
  static const arrival = Color(0xFF8888FF);

  static const startFill = Color(0xFF4CAF50);
  static const endFill = Color(0xFFF44336);
  static const waypointFill = Color(0xFFFF9800);
  static const markerStroke = Color(0xFFFFFFFF);

  static const selectionFill = Color(0x2E00E5FF);
  static const selectionStroke = Color(0xFF00E5FF);

  static const windArrow = Color(0xFF1565C0);
}

/// Classifies a waypoint's incoming leg so the painter (and itinerary
/// card) can colour it. Mirrors the logic at route-planner.html:505-510.
enum WeatherRouteLegKind { starboardTack, portTack, motoring, arrival }

WeatherRouteLegKind legKindAt(List<WeatherRouteWaypoint> wps, int i) {
  if (i < 0 || i >= wps.length) return WeatherRouteLegKind.motoring;
  if (i == wps.length - 1) return WeatherRouteLegKind.arrival;
  final wp = wps[i];
  if (wp.isMotoring) return WeatherRouteLegKind.motoring;
  final cog = wp.cogDeg;
  final wind = wp.windDirDeg;
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
    final coords = result.coords;
    if (coords.length < 2) return;
    final wps = result.waypoints;
    final origin = camera.pixelOrigin;
    Offset project(List<double> lonLat) =>
        camera.projectAtZoom(LatLng(lonLat[1], lonLat[0])) - origin;

    final points = coords.map(project).toList(growable: false);

    // Precompute a leg kind per segment. Segment i goes from point[i] to
    // point[i+1]; we colour it using the leg kind of the starting waypoint
    // (or the arrival colour for the final segment).
    final legKinds = List<WeatherRouteLegKind>.generate(
      points.length - 1,
      (i) {
        if (i == points.length - 2) return WeatherRouteLegKind.arrival;
        // Waypoints list length can differ from coords length if the
        // server simplified the geometry; fall through to motoring when
        // we don't have a matching waypoint.
        if (i >= wps.length) return WeatherRouteLegKind.motoring;
        return legKindAt(wps, i);
      },
      growable: false,
    );

    // 1) Route polyline — draw each segment with its own colour.
    final linePaint = Paint()
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < points.length - 1; i++) {
      linePaint.color = colorForLegKind(legKinds[i]);
      canvas.drawLine(points[i], points[i + 1], linePaint);
    }

    // 2) Inner leg rings — one per waypoint, coloured by the leg that
    //    *arrives* at it. The start point has no arriving leg, so we
    //    colour it by the departing leg instead.
    final ringPaint = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < points.length; i++) {
      final kind = i == 0
          ? (legKinds.isNotEmpty ? legKinds.first : WeatherRouteLegKind.motoring)
          : legKinds[math.min(i - 1, legKinds.length - 1)];
      ringPaint.color = colorForLegKind(kind);
      ringPaint.strokeWidth = (selectedIndex == i) ? 5 : 2;
      canvas.drawCircle(points[i], innerRingRadius, ringPaint);
    }

    // 3) Selection halo — 28 px cyan fill + stroke, 22 px white inner ring.
    final sel = selectedIndex;
    if (sel != null && sel >= 0 && sel < points.length) {
      final centre = points[sel];
      canvas.drawCircle(
        centre,
        selectionOuterRadius,
        Paint()..color = WeatherRouteColors.selectionFill,
      );
      canvas.drawCircle(
        centre,
        selectionOuterRadius,
        Paint()
          ..color = WeatherRouteColors.selectionStroke
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke,
      );
      canvas.drawCircle(
        centre,
        selectionInnerRadius,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );

      // Wind arrow at the selected waypoint, if we have wind data.
      if (sel < wps.length) {
        _paintWindArrow(canvas, centre, wps[sel]);
        _paintVesselChevron(canvas, centre, wps[sel], legKindAt(wps, sel));
      }
    }

    // 4) Waypoint circles + labels — drawn last so they sit on top.
    for (var i = 0; i < points.length; i++) {
      final isStart = i == 0;
      final isEnd = i == points.length - 1;
      final fill = isStart
          ? WeatherRouteColors.startFill
          : isEnd
              ? WeatherRouteColors.endFill
              : WeatherRouteColors.waypointFill;
      canvas.drawCircle(
        points[i],
        waypointRadius,
        Paint()..color = fill,
      );
      canvas.drawCircle(
        points[i],
        waypointRadius,
        Paint()
          ..color = WeatherRouteColors.markerStroke
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
      final label = isStart ? 'S' : (isEnd ? 'E' : 'W$i');
      _paintLabel(canvas, points[i], label);
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
    WeatherRouteWaypoint wp,
    WeatherRouteLegKind kind,
  ) {
    final cogDeg = wp.outgoingCogDeg ?? wp.cogDeg;
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

/// Hit-tests a tap against the waypoint markers of a weather route.
/// Returns the index of the nearest waypoint within [radius] pixels, or
/// null if the tap doesn't land on any marker.
///
/// The caller converts the tap LatLng to a screen Offset using the same
/// `MapCamera.projectAtZoom(…) - pixelOrigin` transform the painter uses.
int? hitTestWeatherRouteWaypoint({
  required WeatherRouteResult result,
  required MapCamera camera,
  required LatLng tap,
  double radius = WeatherRoutePainter.waypointRadius + 2,
}) {
  if (result.coords.isEmpty) return null;
  final origin = camera.pixelOrigin;
  final tapPx = camera.projectAtZoom(tap) - origin;
  int? best;
  double bestDist = radius;
  for (var i = 0; i < result.coords.length; i++) {
    final c = result.coords[i];
    final p =
        camera.projectAtZoom(LatLng(c[1], c[0])) - origin;
    final d = (p - tapPx).distance;
    if (d < bestDist) {
      bestDist = d;
      best = i;
    }
  }
  return best;
}
