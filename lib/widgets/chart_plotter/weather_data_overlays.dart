import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/weather_data_service.dart';

const double _msPerKt = 0.514444;

/// Base class for `/wind` and `/currents` JSON tile overlays.
///
/// On every camera change, enumerate the visible XYZ tiles at the
/// rounded zoom, fetch each one via [WeatherDataService.fetchVectorTile]
/// (cache hits are synchronous), concatenate the points, and repaint
/// via the subclass's [buildPainter]. Debounced 200 ms so fling-pan
/// doesn't spam the server before settling.
///
/// The overlay listens to the service's `ChangeNotifier` too — an
/// hour-flip on waypoint scrub invalidates the previous point set and
/// triggers a fetch against the current camera.
abstract class _WeatherVectorTileOverlay extends StatefulWidget {
  const _WeatherVectorTileOverlay({
    super.key,
    required this.service,
    required this.path,
    required this.zoomFloor,
  });

  final WeatherDataService service;
  final String path;
  final int zoomFloor;

  CustomPainter buildPainter(
      MapCamera camera, List<WeatherVectorPoint> points);

  @override
  State<_WeatherVectorTileOverlay> createState() =>
      _WeatherVectorTileOverlayState();
}

class _WeatherVectorTileOverlayState
    extends State<_WeatherVectorTileOverlay> {
  List<WeatherVectorPoint> _points = const [];
  int _seq = 0;
  Timer? _debounce;
  int _lastZoomBucket = -1;
  String _lastHour = '';
  Set<String> _lastTileKeys = const {};

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onServiceChanged);
  }

  @override
  void didUpdateWidget(covariant _WeatherVectorTileOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service)) {
      oldWidget.service.removeListener(_onServiceChanged);
      widget.service.addListener(_onServiceChanged);
      _invalidate();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    // Time or base URL flipped; drop the memoised camera fingerprint
    // so the next build triggers a refetch.
    _invalidate();
  }

  void _invalidate() {
    _lastZoomBucket = -1;
    _lastHour = '';
    _lastTileKeys = const {};
    if (mounted) setState(() {});
  }

  void _scheduleFetch(MapCamera camera) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _doFetch(camera);
    });
  }

  Future<void> _doFetch(MapCamera camera) async {
    if (camera.zoom < widget.zoomFloor) {
      if (_points.isNotEmpty) {
        setState(() => _points = const []);
      }
      _lastZoomBucket = -1;
      _lastHour = '';
      _lastTileKeys = const {};
      return;
    }
    final z = camera.zoom.round();
    final tiles = _tilesForBounds(z, camera.visibleBounds);
    final hour = widget.service.hourParam;
    final tileKeys = tiles.map((t) => '${t.x}_${t.y}').toSet();

    if (z == _lastZoomBucket &&
        hour == _lastHour &&
        _setsEqual(tileKeys, _lastTileKeys)) {
      return;
    }

    final seq = ++_seq;
    final futures = [
      for (final t in tiles)
        widget.service.fetchVectorTile(widget.path, z, t.x, t.y),
    ];
    final results = await Future.wait(futures);
    if (seq != _seq || !mounted) return;

    final merged = <WeatherVectorPoint>[];
    for (final r in results) {
      if (r != null) merged.addAll(r);
    }
    _lastZoomBucket = z;
    _lastHour = hour;
    _lastTileKeys = tileKeys;
    setState(() => _points = merged);
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    // Kick a (debounced) fetch on every camera change.
    _scheduleFetch(camera);
    return IgnorePointer(
      child: MobileLayerTransformer(
        child: CustomPaint(
          painter: widget.buildPainter(camera, _points),
          size: Size.infinite,
        ),
      ),
    );
  }

  /// Visible XYZ tile coordinates at `z`. Uses the standard slippy-map
  /// formulas; the server uses the same scheme so tile coords align.
  static List<_TileXY> _tilesForBounds(int z, LatLngBounds b) {
    final n = 1 << z;
    int tileX(double lon) {
      final v = ((lon + 180.0) / 360.0 * n).floor();
      return v.clamp(0, n - 1);
    }
    int tileY(double lat) {
      final clampedLat = lat.clamp(-85.05112878, 85.05112878);
      final rad = clampedLat * math.pi / 180.0;
      final v = (((1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2) * n)
          .floor();
      return v.clamp(0, n - 1);
    }

    final x0 = tileX(b.west);
    final x1 = tileX(b.east);
    final y0 = tileY(b.north); // north = top → smaller y
    final y1 = tileY(b.south);
    final out = <_TileXY>[];
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        out.add(_TileXY(x, y));
      }
    }
    return out;
  }

  static bool _setsEqual(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final e in a) {
      if (!b.contains(e)) return false;
    }
    return true;
  }
}

class _TileXY {
  const _TileXY(this.x, this.y);
  final int x;
  final int y;
}

// ═════════════════════════ Wind barbs ═════════════════════════════════

/// WMO meteorological wind barbs, one per `/wind/{z}/{x}/{y}.json`
/// sample. Staff points at the wind source (FROM direction); feathers
/// on the left encode speed — pennant = 50 kt, full feather = 10 kt,
/// half = 5 kt.
class WindBarbsTileOverlay extends _WeatherVectorTileOverlay {
  const WindBarbsTileOverlay({super.key, required super.service})
      : super(
          path: '/wind',
          zoomFloor: WeatherDataService.zoomFloorWindBarbs,
        );

  @override
  CustomPainter buildPainter(
      MapCamera camera, List<WeatherVectorPoint> points) {
    return _WindBarbsPainter(camera: camera, barbs: points);
  }
}

class _WindBarbsPainter extends CustomPainter {
  _WindBarbsPainter({required this.camera, required this.barbs});

  final MapCamera camera;
  final List<WeatherVectorPoint> barbs;

  /// Matches `_windColor` in `routePlanning/ui/route-planner.html` —
  /// same six-stop ramp, capped at `#C62828` for the gale+ bucket.
  /// (The server heatmap LUT has an extra 50-kt stop but the web UI
  /// doesn't and we keep parity with the planner.)
  static Color _colorFor(double kts) {
    if (kts < 5) return const Color(0xFF90CAF9);
    if (kts < 10) return const Color(0xFF4FC3F7);
    if (kts < 15) return const Color(0xFF00897B);
    if (kts < 20) return const Color(0xFF43A047);
    if (kts < 25) return const Color(0xFFF9A825);
    if (kts < 30) return const Color(0xFFE64A19);
    return const Color(0xFFC62828);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (barbs.isEmpty) return;
    final origin = camera.pixelOrigin;
    for (final b in barbs) {
      final pt = camera.projectAtZoom(LatLng(b.lat, b.lon)) - origin;
      _paintBarb(canvas, pt, b);
    }
  }

  void _paintBarb(Canvas canvas, Offset anchor, WeatherVectorPoint b) {
    final kts = b.speedMs / _msPerKt;
    final colour = _colorFor(kts);
    final paint = Paint()
      ..color = colour
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = colour;

    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    canvas.rotate(b.dirDeg * math.pi / 180);

    if (kts < 2.5) {
      canvas.drawCircle(
        const Offset(0, -4),
        4,
        Paint()
          ..color = colour
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
      canvas.restore();
      return;
    }

    var remain = (kts / 5).round() * 5;
    const staffTop = -34.0;
    const featherLen = 10.0;
    const featherStep = 4.0;
    const halfLen = 5.0;

    canvas.drawLine(Offset.zero, const Offset(0, staffTop), paint);

    var y = staffTop;
    while (remain >= 50) {
      final p = ui.Path()
        ..moveTo(0, y)
        ..lineTo(0, y + featherStep)
        ..lineTo(-featherLen, y + featherStep / 2)
        ..close();
      canvas.drawPath(p, fill);
      y += featherStep + 1;
      remain -= 50;
    }
    while (remain >= 10) {
      canvas.drawLine(Offset(0, y), Offset(-featherLen, y + 3), paint);
      y += featherStep;
      remain -= 10;
    }
    if (remain >= 5) {
      if (y == staffTop) y += featherStep;
      canvas.drawLine(Offset(0, y), Offset(-halfLen, y + 1.5), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WindBarbsPainter old) =>
      old.camera != camera || !identical(old.barbs, barbs);
}

// ═════════════════════════ Current arrows ═════════════════════════════

class CurrentArrowsTileOverlay extends _WeatherVectorTileOverlay {
  const CurrentArrowsTileOverlay({super.key, required super.service})
      : super(
          path: '/currents',
          zoomFloor: WeatherDataService.zoomFloorCurrents,
        );

  @override
  CustomPainter buildPainter(
      MapCamera camera, List<WeatherVectorPoint> points) {
    return _CurrentsPainter(camera: camera, currents: points);
  }
}

class _CurrentsPainter extends CustomPainter {
  _CurrentsPainter({required this.camera, required this.currents});

  final MapCamera camera;
  final List<WeatherVectorPoint> currents;

  /// Matches `_currentColor` in `routePlanning/ui/route-planner.html`:
  /// four-bucket green → olive → orange → red ramp. Deliberately
  /// different from the server's current-heatmap LUT — the web UI
  /// uses this tighter palette for arrow glyphs and we follow it.
  static Color _colorFor(double kts) {
    if (kts < 0.5) return const Color(0xD900C88C);
    if (kts < 1.0) return const Color(0xD9B4B400);
    if (kts < 1.5) return const Color(0xD9DC8C00);
    return const Color(0xE6DC2828);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (currents.isEmpty) return;
    final origin = camera.pixelOrigin;
    for (final c in currents) {
      final pt = camera.projectAtZoom(LatLng(c.lat, c.lon)) - origin;
      _paintArrow(canvas, pt, c);
    }
  }

  void _paintArrow(Canvas canvas, Offset anchor, WeatherVectorPoint c) {
    final kts = c.speedMs / _msPerKt;
    final colour = _colorFor(kts);
    final fill = Paint()..color = colour;

    if (kts < 0.05) {
      final p = Paint()..color = colour;
      final rect1 =
          Rect.fromLTWH(anchor.dx - 4, anchor.dy - 4, 2.5, 10);
      final rect2 =
          Rect.fromLTWH(anchor.dx + 1.5, anchor.dy - 4, 2.5, 10);
      canvas.drawRect(rect1, p);
      canvas.drawRect(rect2, p);
      return;
    }

    final scale = (kts * 0.7 + 0.27).clamp(0.4, 0.8);
    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    canvas.rotate(c.dirDeg * math.pi / 180);
    canvas.scale(scale);

    final path = ui.Path()
      ..moveTo(0, -16)
      ..lineTo(-7, -2)
      ..lineTo(0, -6)
      ..lineTo(7, -2)
      ..close()
      ..addRect(const Rect.fromLTWH(-2, -4, 4, 20));
    canvas.drawPath(path, fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CurrentsPainter old) =>
      old.camera != camera || !identical(old.currents, currents);
}
