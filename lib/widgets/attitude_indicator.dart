import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Attitude/Heel Indicator widget showing roll and pitch
/// Displays an artificial horizon with boat silhouette and digital values
class AttitudeIndicator extends StatelessWidget {
  /// Roll angle in degrees (positive = starboard heel)
  final double? rollDegrees;

  /// Pitch angle in degrees (positive = bow up)
  final double? pitchDegrees;

  /// Whether to show digital values
  final bool showDigitalValues;

  /// Whether to show the horizon grid
  final bool showGrid;

  /// Primary color for the indicator
  final Color primaryColor;

  /// Maximum displayable pitch angle (degrees)
  final double maxPitch;

  /// Maximum displayable roll angle (degrees)
  final double maxRoll;

  const AttitudeIndicator({
    super.key,
    this.rollDegrees,
    this.pitchDegrees,
    this.showDigitalValues = true,
    this.showGrid = true,
    this.primaryColor = Colors.orange,
    this.maxPitch = 30.0,
    this.maxRoll = 45.0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Title
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.explore,
                  color: primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Attitude',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Horizon indicator
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Use the smallest dimension to maintain circular shape
                  final size = math.min(constraints.maxWidth, constraints.maxHeight);
                  return Center(
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: ClipOval(
                        child: CustomPaint(
                          painter: _AttitudePainter(
                            rollDegrees: rollDegrees ?? 0,
                            pitchDegrees: pitchDegrees ?? 0,
                            maxPitch: maxPitch,
                            showGrid: showGrid,
                            isDark: isDark,
                            primaryColor: primaryColor,
                          ),
                          child: Container(),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // Digital values
            if (showDigitalValues) _buildDigitalValues(context, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildDigitalValues(BuildContext context, bool isDark) {
    final roll = rollDegrees;
    final pitch = pitchDegrees;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Roll (Heel)
        _buildValueBox(
          context,
          'HEEL',
          roll != null ? '${roll.abs().toStringAsFixed(1)}°' : '--',
          roll != null ? (roll >= 0 ? 'STBD' : 'PORT') : '',
          roll != null ? (roll >= 0 ? Colors.green : Colors.red) : Colors.grey,
          isDark,
        ),

        // Pitch
        _buildValueBox(
          context,
          'PITCH',
          pitch != null ? '${pitch.abs().toStringAsFixed(1)}°' : '--',
          pitch != null ? (pitch >= 0 ? 'BOW UP' : 'BOW DN') : '',
          pitch != null ? (pitch >= 0 ? Colors.blue : Colors.orange) : Colors.grey,
          isDark,
        ),
      ],
    );
  }

  Widget _buildValueBox(
    BuildContext context,
    String label,
    String value,
    String suffix,
    Color suffixColor,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white60 : Colors.black45,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          if (suffix.isNotEmpty)
            Text(
              suffix,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: suffixColor,
              ),
            ),
        ],
      ),
    );
  }
}

/// Custom painter for the attitude indicator
class _AttitudePainter extends CustomPainter {
  final double rollDegrees;
  final double pitchDegrees;
  final double maxPitch;
  final bool showGrid;
  final bool isDark;
  final Color primaryColor;

  _AttitudePainter({
    required this.rollDegrees,
    required this.pitchDegrees,
    required this.maxPitch,
    required this.showGrid,
    required this.isDark,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    // Clip to circle
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));

    // Calculate pitch offset (pixels per degree)
    final pitchPixelsPerDegree = radius / maxPitch;
    final pitchOffset = pitchDegrees * pitchPixelsPerDegree;

    // Save canvas and apply roll rotation
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-rollDegrees * math.pi / 180);

    // Draw sky (blue)
    final skyPaint = Paint()
      ..color = Colors.blue.shade300
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTWH(
        -radius * 2,
        -radius * 2 + pitchOffset,
        radius * 4,
        radius * 2,
      ),
      skyPaint,
    );

    // Draw ground (brown)
    final groundPaint = Paint()
      ..color = Colors.brown.shade400
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTWH(
        -radius * 2,
        pitchOffset,
        radius * 4,
        radius * 2,
      ),
      groundPaint,
    );

    // Draw horizon line
    final horizonPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(-radius * 2, pitchOffset),
      Offset(radius * 2, pitchOffset),
      horizonPaint,
    );

    // Draw pitch ladder
    if (showGrid) {
      _drawPitchLadder(canvas, radius, pitchOffset, pitchPixelsPerDegree);
    }

    canvas.restore();

    // Draw fixed aircraft symbol (does not rotate)
    _drawAircraftSymbol(canvas, center, radius);

    // Draw roll indicator arc
    _drawRollIndicator(canvas, center, radius);

    // Draw bezel
    final bezelPaint = Paint()
      ..color = isDark ? Colors.grey.shade800 : Colors.grey.shade400
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius - 2, bezelPaint);
  }

  void _drawPitchLadder(Canvas canvas, double radius, double pitchOffset, double pixelsPerDegree) {
    final ladderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    // Draw pitch lines every 10 degrees
    for (int i = -30; i <= 30; i += 10) {
      if (i == 0) continue; // Skip horizon (already drawn)

      final y = pitchOffset - (i * pixelsPerDegree);
      final lineWidth = radius * 0.4;

      // Draw main line
      canvas.drawLine(
        Offset(-lineWidth, y),
        Offset(lineWidth, y),
        ladderPaint,
      );

      // Draw pitch value
      textPainter.text = TextSpan(
        text: '${i.abs()}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(-lineWidth - textPainter.width - 4, y - textPainter.height / 2),
      );
      textPainter.paint(
        canvas,
        Offset(lineWidth + 4, y - textPainter.height / 2),
      );
    }

    // Draw minor pitch lines every 5 degrees
    for (int i = -25; i <= 25; i += 10) {
      final y = pitchOffset - (i * pixelsPerDegree);
      final lineWidth = radius * 0.2;

      canvas.drawLine(
        Offset(-lineWidth, y),
        Offset(lineWidth, y),
        ladderPaint..strokeWidth = 1,
      );
    }
  }

  void _drawAircraftSymbol(Canvas canvas, Offset center, double radius) {
    final symbolPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw aircraft wings
    final wingWidth = radius * 0.6;
    final wingY = center.dy;

    // Left wing
    canvas.drawLine(
      Offset(center.dx - wingWidth, wingY),
      Offset(center.dx - radius * 0.15, wingY),
      symbolPaint,
    );

    // Right wing
    canvas.drawLine(
      Offset(center.dx + radius * 0.15, wingY),
      Offset(center.dx + wingWidth, wingY),
      symbolPaint,
    );

    // Center dot
    final centerPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 6, centerPaint);

    // Wing tips (down ticks)
    canvas.drawLine(
      Offset(center.dx - wingWidth, wingY),
      Offset(center.dx - wingWidth, wingY + radius * 0.1),
      symbolPaint,
    );
    canvas.drawLine(
      Offset(center.dx + wingWidth, wingY),
      Offset(center.dx + wingWidth, wingY + radius * 0.1),
      symbolPaint,
    );
  }

  void _drawRollIndicator(Canvas canvas, Offset center, double radius) {
    final rollRadius = radius * 0.85;

    // Draw roll scale arc at top
    final scalePaint = Paint()
      ..color = isDark ? Colors.white70 : Colors.black87
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Draw tick marks at standard angles
    final rollAngles = [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60];

    for (final angle in rollAngles) {
      final radians = (angle - 90) * math.pi / 180; // -90 to start from top
      final isMajor = angle % 30 == 0;
      final tickLength = isMajor ? radius * 0.1 : radius * 0.05;

      final outerX = center.dx + rollRadius * math.cos(radians);
      final outerY = center.dy + rollRadius * math.sin(radians);
      final innerX = center.dx + (rollRadius - tickLength) * math.cos(radians);
      final innerY = center.dy + (rollRadius - tickLength) * math.sin(radians);

      canvas.drawLine(
        Offset(innerX, innerY),
        Offset(outerX, outerY),
        scalePaint..strokeWidth = isMajor ? 2 : 1,
      );
    }

    // Draw roll pointer (triangle at current roll)
    final pointerAngle = (-rollDegrees - 90) * math.pi / 180;
    final pointerRadius = rollRadius - radius * 0.12;

    final pointerPath = Path();
    final tipX = center.dx + pointerRadius * math.cos(pointerAngle);
    final tipY = center.dy + pointerRadius * math.sin(pointerAngle);

    // Triangle pointer
    final pointerSize = radius * 0.08;
    final leftAngle = pointerAngle - math.pi / 2;
    final rightAngle = pointerAngle + math.pi / 2;

    pointerPath.moveTo(tipX, tipY);
    pointerPath.lineTo(
      tipX + pointerSize * math.cos(pointerAngle) + pointerSize * 0.5 * math.cos(leftAngle),
      tipY + pointerSize * math.sin(pointerAngle) + pointerSize * 0.5 * math.sin(leftAngle),
    );
    pointerPath.lineTo(
      tipX + pointerSize * math.cos(pointerAngle) + pointerSize * 0.5 * math.cos(rightAngle),
      tipY + pointerSize * math.sin(pointerAngle) + pointerSize * 0.5 * math.sin(rightAngle),
    );
    pointerPath.close();

    final pointerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawPath(pointerPath, pointerPaint);

    // Draw fixed triangle at top (zero reference)
    final refPath = Path();
    final refY = center.dy - rollRadius + radius * 0.02;

    refPath.moveTo(center.dx, refY);
    refPath.lineTo(center.dx - radius * 0.05, refY - radius * 0.08);
    refPath.lineTo(center.dx + radius * 0.05, refY - radius * 0.08);
    refPath.close();

    final refPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(refPath, refPaint);
  }

  @override
  bool shouldRepaint(_AttitudePainter oldDelegate) {
    return rollDegrees != oldDelegate.rollDegrees ||
        pitchDegrees != oldDelegate.pitchDegrees ||
        showGrid != oldDelegate.showGrid ||
        isDark != oldDelegate.isDark;
  }
}
