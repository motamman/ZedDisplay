import 'dart:math';
import 'package:flutter/material.dart';

/// A customizable radial gauge widget for displaying numeric values
class RadialGauge extends StatelessWidget {
  final double value;
  final double minValue;
  final double maxValue;
  final String label;
  final String unit;
  final Color primaryColor;
  final Color backgroundColor;
  final int divisions;

  const RadialGauge({
    super.key,
    required this.value,
    this.minValue = 0,
    this.maxValue = 100,
    this.label = '',
    this.unit = '',
    this.primaryColor = Colors.blue,
    this.backgroundColor = Colors.grey,
    this.divisions = 10,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _RadialGaugePainter(
          value: value,
          minValue: minValue,
          maxValue: maxValue,
          label: label,
          unit: unit,
          primaryColor: primaryColor,
          backgroundColor: backgroundColor,
          divisions: divisions,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label.isNotEmpty)
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                value.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (unit.isNotEmpty)
                Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadialGaugePainter extends CustomPainter {
  final double value;
  final double minValue;
  final double maxValue;
  final String label;
  final String unit;
  final Color primaryColor;
  final Color backgroundColor;
  final int divisions;

  _RadialGaugePainter({
    required this.value,
    required this.minValue,
    required this.maxValue,
    required this.label,
    required this.unit,
    required this.primaryColor,
    required this.backgroundColor,
    required this.divisions,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 20;
    const strokeWidth = 15.0;

    // Draw background arc
    final backgroundPaint = Paint()
      ..color = backgroundColor.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    const startAngle = -pi * 0.75; // Start at 135 degrees
    const sweepAngle = pi * 1.5; // 270 degrees total

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      backgroundPaint,
    );

    // Draw value arc
    final normalizedValue = ((value - minValue) / (maxValue - minValue)).clamp(0.0, 1.0);
    final valueSweepAngle = sweepAngle * normalizedValue;

    final valuePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          primaryColor,
          primaryColor.withValues(alpha: 0.6),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      valueSweepAngle,
      false,
      valuePaint,
    );

    // Draw tick marks
    _drawTickMarks(canvas, center, radius, strokeWidth);
  }

  void _drawTickMarks(Canvas canvas, Offset center, double radius, double strokeWidth) {
    final tickPaint = Paint()
      ..color = Colors.grey
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const startAngle = -pi * 0.75;
    const sweepAngle = pi * 1.5;

    for (int i = 0; i <= divisions; i++) {
      final angle = startAngle + (sweepAngle * i / divisions);
      final isMainTick = i % (divisions ~/ 5) == 0;
      final tickLength = isMainTick ? 12.0 : 6.0;

      final startX = center.dx + (radius + strokeWidth / 2 + 5) * cos(angle);
      final startY = center.dy + (radius + strokeWidth / 2 + 5) * sin(angle);
      final endX = center.dx + (radius + strokeWidth / 2 + 5 + tickLength) * cos(angle);
      final endY = center.dy + (radius + strokeWidth / 2 + 5 + tickLength) * sin(angle);

      canvas.drawLine(
        Offset(startX, startY),
        Offset(endX, endY),
        tickPaint..strokeWidth = isMainTick ? 2.5 : 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_RadialGaugePainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.minValue != minValue ||
        oldDelegate.maxValue != maxValue;
  }
}
