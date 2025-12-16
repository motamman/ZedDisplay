import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';

/// Overlay widget for capturing anchor bearing using device compass
/// Returns the bearing in degrees (0-360) when user confirms
class AnchorCompassOverlay extends StatefulWidget {
  const AnchorCompassOverlay({super.key});

  /// Show the overlay and return the captured bearing (or null if cancelled)
  static Future<double?> show(BuildContext context) {
    return showDialog<double>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (context) => const AnchorCompassOverlay(),
    );
  }

  @override
  State<AnchorCompassOverlay> createState() => _AnchorCompassOverlayState();
}

class _AnchorCompassOverlayState extends State<AnchorCompassOverlay> {
  StreamSubscription<CompassEvent>? _compassSubscription;
  double? _currentHeading;
  bool _hasCompass = true;

  @override
  void initState() {
    super.initState();
    _initCompass();
  }

  void _initCompass() {
    final events = FlutterCompass.events;
    if (events == null) {
      setState(() => _hasCompass = false);
      return;
    }

    _compassSubscription = events.listen((event) {
      if (mounted && event.heading != null) {
        setState(() {
          _currentHeading = event.heading!;
        });
      }
    });
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    super.dispose();
  }

  void _confirm() {
    if (_currentHeading != null) {
      final heading = (_currentHeading! + 360) % 360;
      Navigator.of(context).pop(heading);
    }
  }

  void _cancel() {
    Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Icon(Icons.explore, color: Colors.blue, size: 32),
                  const SizedBox(height: 8),
                  const Text(
                    'Point Phone Toward Anchor',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hold phone flat, point top toward anchor',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _hasCompass
                  ? _buildCompassDisplay()
                  : _buildNoCompassMessage(),
            ),
            if (_hasCompass && _currentHeading != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '${_currentHeading!.toStringAsFixed(0)}°',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _cancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: _currentHeading != null ? _confirm : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Confirm'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompassDisplay() {
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: CustomPaint(
            painter: _CompassPainter(heading: _currentHeading ?? 0),
          ),
        ),
      ),
    );
  }

  Widget _buildNoCompassMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.orange, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Compass Not Available',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your device does not have a compass sensor.',
              style: TextStyle(color: Colors.grey.shade400),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final double heading;

  _CompassPainter({required this.heading});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-heading * math.pi / 180);
    canvas.translate(-center.dx, -center.dy);

    // Outer circle
    final outerPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, outerPaint);

    // Tick marks
    final tickPaint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1;
    final majorTickPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;

    for (int i = 0; i < 360; i += 10) {
      final isMajor = i % 30 == 0;
      final tickLength = isMajor ? 15.0 : 8.0;
      final angle = i * math.pi / 180;

      final outer = Offset(
        center.dx + radius * math.sin(angle),
        center.dy - radius * math.cos(angle),
      );
      final inner = Offset(
        center.dx + (radius - tickLength) * math.sin(angle),
        center.dy - (radius - tickLength) * math.cos(angle),
      );

      canvas.drawLine(inner, outer, isMajor ? majorTickPaint : tickPaint);
    }

    // Cardinal labels
    const textStyle = TextStyle(
      color: Colors.white,
      fontSize: 20,
      fontWeight: FontWeight.bold,
    );
    final labels = ['N', 'E', 'S', 'W'];
    final angles = [0.0, 90.0, 180.0, 270.0];
    final colors = [Colors.red, Colors.white, Colors.white, Colors.white];

    for (int i = 0; i < 4; i++) {
      final angle = angles[i] * math.pi / 180;
      final labelRadius = radius - 30;
      final pos = Offset(
        center.dx + labelRadius * math.sin(angle),
        center.dy - labelRadius * math.cos(angle),
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: textStyle.copyWith(color: colors[i]),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(heading * math.pi / 180);
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );
      canvas.restore();
    }

    canvas.restore();

    // Fixed pointer at top
    final pointerPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    final pointerPath = Path();
    pointerPath.moveTo(center.dx, center.dy - radius + 25);
    pointerPath.lineTo(center.dx - 12, center.dy - radius + 45);
    pointerPath.lineTo(center.dx + 12, center.dy - radius + 45);
    pointerPath.close();
    canvas.drawPath(pointerPath, pointerPaint);

    // Center dot
    final centerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 6, centerPaint);
  }

  @override
  bool shouldRepaint(covariant _CompassPainter oldDelegate) {
    return oldDelegate.heading != heading;
  }
}
