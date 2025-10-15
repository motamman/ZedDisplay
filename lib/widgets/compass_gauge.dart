import 'dart:math';
import 'package:flutter/material.dart';

/// A compass widget for displaying heading/bearing
class CompassGauge extends StatelessWidget {
  final double heading; // In degrees (0-360)
  final String label;
  final String? formattedValue;
  final Color primaryColor;

  const CompassGauge({
    super.key,
    required this.heading,
    this.label = 'Heading',
    this.formattedValue,
    this.primaryColor = Colors.red,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _CompassPainter(
          heading: heading,
          primaryColor: primaryColor,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                formattedValue ?? '${heading.toStringAsFixed(0)}°',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _getCardinalDirection(heading),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getCardinalDirection(double degrees) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((degrees + 22.5) / 45).floor() % 8;
    return directions[index];
  }
}

class _CompassPainter extends CustomPainter {
  final double heading;
  final Color primaryColor;

  _CompassPainter({
    required this.heading,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 30;

    // Draw outer circle
    final circlePaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius, circlePaint);

    // Draw cardinal directions
    _drawCardinalMarks(canvas, center, radius);

    // Draw heading indicator (rotating arrow pointing to current heading)
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate((heading - 90) * pi / 180); // Rotate to heading

    final arrowPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    // Draw arrow pointing to heading
    final arrowPath = Path()
      ..moveTo(radius - 40, 0) // Tip of arrow
      ..lineTo(radius - 60, -8)
      ..lineTo(radius - 60, 8)
      ..close();

    canvas.drawPath(arrowPath, arrowPaint);
    canvas.restore();

    // Draw north indicator (fixed at top)
    _drawNorthIndicator(canvas, center, radius);
  }

  void _drawCardinalMarks(Canvas canvas, Offset center, double radius) {
    const directions = ['N', 'E', 'S', 'W'];
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    for (int i = 0; i < 4; i++) {
      final angle = i * pi / 2 - pi / 2; // Start at top (North)
      final x = center.dx + radius * 0.85 * cos(angle);
      final y = center.dy + radius * 0.85 * sin(angle);

      textPainter.text = TextSpan(
        text: directions[i],
        style: TextStyle(
          color: directions[i] == 'N' ? Colors.red : Colors.grey,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      );

      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, y - textPainter.height / 2),
      );

      // Draw tick marks
      final tickPaint = Paint()
        ..color = Colors.grey
        ..strokeWidth = directions[i] == 'N' ? 3 : 2
        ..strokeCap = StrokeCap.round;

      final startX = center.dx + (radius - 15) * cos(angle);
      final startY = center.dy + (radius - 15) * sin(angle);
      final endX = center.dx + (radius - 5) * cos(angle);
      final endY = center.dy + (radius - 5) * sin(angle);

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), tickPaint);
    }

    // Draw minor tick marks (every 30 degrees)
    final minorTickPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.5)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 12; i++) {
      if (i % 3 != 0) {
        // Skip cardinal directions
        final angle = i * pi / 6 - pi / 2;
        final startX = center.dx + (radius - 10) * cos(angle);
        final startY = center.dy + (radius - 10) * sin(angle);
        final endX = center.dx + (radius - 5) * cos(angle);
        final endY = center.dy + (radius - 5) * sin(angle);

        canvas.drawLine(
          Offset(startX, startY),
          Offset(endX, endY),
          minorTickPaint,
        );
      }
    }
  }

  void _drawNorthIndicator(Canvas canvas, Offset center, double radius) {
    // Draw a fixed triangle at the top to indicate north
    final northPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final northPath = Path()
      ..moveTo(center.dx, center.dy - radius + 5)
      ..lineTo(center.dx - 8, center.dy - radius + 20)
      ..lineTo(center.dx + 8, center.dy - radius + 20)
      ..close();

    canvas.drawPath(northPath, northPaint);
  }

  @override
  bool shouldRepaint(_CompassPainter oldDelegate) {
    return oldDelegate.heading != heading;
  }
}
