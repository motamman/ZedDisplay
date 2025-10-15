import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Comprehensive windsteer gauge widget mirroring Kip implementation
class WindsteerGauge extends StatelessWidget {
  // Required
  final double heading;

  // Wind data
  final double? apparentWindAngle;
  final double? apparentWindSpeed;
  final double? trueWindAngle;
  final double? trueWindSpeed;

  // Navigation
  final double? courseOverGround;
  final double? waypointBearing;

  // Current/Drift
  final double? driftSet;        // Current direction
  final double? driftFlow;       // Current speed

  // Historical wind (for wind sectors)
  final double? trueWindMinHistoric;
  final double? trueWindMidHistoric;
  final double? trueWindMaxHistoric;

  // Configuration
  final double laylineAngle;
  final bool showLaylines;
  final bool showTrueWind;
  final bool showCOG;
  final bool showAWS;
  final bool showTWS;
  final bool showDrift;
  final bool showWaypoint;
  final bool showWindSectors;

  // Formatted values
  final String? awsFormatted;
  final String? twsFormatted;
  final String? driftFormatted;

  // Colors
  final Color primaryColor;
  final Color secondaryColor;

  const WindsteerGauge({
    super.key,
    required this.heading,
    this.apparentWindAngle,
    this.apparentWindSpeed,
    this.trueWindAngle,
    this.trueWindSpeed,
    this.courseOverGround,
    this.waypointBearing,
    this.driftSet,
    this.driftFlow,
    this.trueWindMinHistoric,
    this.trueWindMidHistoric,
    this.trueWindMaxHistoric,
    this.laylineAngle = 45.0,
    this.showLaylines = true,
    this.showTrueWind = true,
    this.showCOG = false,
    this.showAWS = true,
    this.showTWS = true,
    this.showDrift = false,
    this.showWaypoint = false,
    this.showWindSectors = false,
    this.awsFormatted,
    this.twsFormatted,
    this.driftFormatted,
    this.primaryColor = Colors.blue,
    this.secondaryColor = Colors.green,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 2,
      child: CustomPaint(
        painter: _WindsteerPainter(
          heading: heading,
          apparentWindAngle: apparentWindAngle,
          trueWindAngle: trueWindAngle,
          courseOverGround: courseOverGround,
          waypointBearing: waypointBearing,
          driftSet: driftSet,
          trueWindMinHistoric: trueWindMinHistoric,
          trueWindMidHistoric: trueWindMidHistoric,
          trueWindMaxHistoric: trueWindMaxHistoric,
          laylineAngle: laylineAngle,
          showLaylines: showLaylines && apparentWindAngle != null,
          showTrueWind: showTrueWind && trueWindAngle != null,
          showCOG: showCOG && courseOverGround != null,
          showDrift: showDrift && driftSet != null,
          showWaypoint: showWaypoint && waypointBearing != null,
          showWindSectors: showWindSectors &&
              trueWindMinHistoric != null &&
              trueWindMidHistoric != null &&
              trueWindMaxHistoric != null,
          primaryColor: primaryColor,
          secondaryColor: secondaryColor,
          isDark: isDark,
        ),
        child: Stack(
          children: [
            // Heading display at top center
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${heading.round()}°',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),

            // AWS display top left
            if (showAWS && apparentWindSpeed != null)
              Positioned(
                top: 16,
                left: 16,
                child: _WindSpeedDisplay(
                  label: 'AWS',
                  speed: apparentWindSpeed!,
                  formatted: awsFormatted,
                  color: primaryColor,
                ),
              ),

            // TWS display top right
            if (showTWS && trueWindSpeed != null)
              Positioned(
                top: 16,
                right: 16,
                child: _WindSpeedDisplay(
                  label: 'TWS',
                  speed: trueWindSpeed!,
                  formatted: twsFormatted,
                  color: secondaryColor,
                ),
              ),

            // Drift flow display in center
            if (showDrift && driftFlow != null)
              Positioned.fill(
                child: Center(
                  child: Text(
                    driftFormatted ?? driftFlow!.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WindSpeedDisplay extends StatelessWidget {
  final String label;
  final double speed;
  final String? formatted;
  final Color color;

  const _WindSpeedDisplay({
    required this.label,
    required this.speed,
    this.formatted,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            formatted ?? speed.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _WindsteerPainter extends CustomPainter {
  final double heading;
  final double? apparentWindAngle;
  final double? trueWindAngle;
  final double? courseOverGround;
  final double? waypointBearing;
  final double? driftSet;
  final double? trueWindMinHistoric;
  final double? trueWindMidHistoric;
  final double? trueWindMaxHistoric;
  final double laylineAngle;
  final bool showLaylines;
  final bool showTrueWind;
  final bool showCOG;
  final bool showDrift;
  final bool showWaypoint;
  final bool showWindSectors;
  final Color primaryColor;
  final Color secondaryColor;
  final bool isDark;

  _WindsteerPainter({
    required this.heading,
    this.apparentWindAngle,
    this.trueWindAngle,
    this.courseOverGround,
    this.waypointBearing,
    this.driftSet,
    this.trueWindMinHistoric,
    this.trueWindMidHistoric,
    this.trueWindMaxHistoric,
    required this.laylineAngle,
    required this.showLaylines,
    required this.showTrueWind,
    required this.showCOG,
    required this.showDrift,
    required this.showWaypoint,
    required this.showWindSectors,
    required this.primaryColor,
    required this.secondaryColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 80;

    // Draw compass background
    _drawCompassBackground(canvas, center, radius);

    // Save canvas state for rotation
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-heading * math.pi / 180); // Rotate compass based on heading

    // Draw compass markings
    _drawCompassMarkings(canvas, radius);

    // Draw wind sectors (if enabled)
    if (showWindSectors && trueWindMinHistoric != null &&
        trueWindMidHistoric != null && trueWindMaxHistoric != null) {
      _drawWindSectors(canvas, radius);
    }

    // Draw laylines (if enabled and AWA is available)
    if (showLaylines && apparentWindAngle != null) {
      _drawLaylines(canvas, radius, apparentWindAngle!, laylineAngle);
    }

    // Restore canvas for fixed indicators
    canvas.restore();

    // Draw wind indicators (fixed relative to boat)
    if (apparentWindAngle != null) {
      _drawWindIndicator(canvas, center, radius * 0.7, apparentWindAngle!, primaryColor, 'A', large: true);
    }

    if (showTrueWind && trueWindAngle != null) {
      _drawWindIndicator(canvas, center, radius * 0.55, trueWindAngle!, secondaryColor, 'T', large: false);
    }

    // Draw COG indicator
    if (showCOG && courseOverGround != null) {
      _drawCOGIndicator(canvas, center, radius * 0.8, courseOverGround! - heading);
    }

    // Draw waypoint bearing indicator
    if (showWaypoint && waypointBearing != null) {
      _drawWaypointIndicator(canvas, center, radius * 0.85, waypointBearing! - heading);
    }

    // Draw drift/set indicator
    if (showDrift && driftSet != null) {
      _drawDriftIndicator(canvas, center, radius * 0.6, driftSet! - heading);
    }

    // Draw boat icon in center
    _drawBoatIcon(canvas, center);
  }

  void _drawCompassBackground(Canvas canvas, Offset center, double radius) {
    // Outer ring
    final outerPaint = Paint()
      ..color = isDark ? Colors.grey[800]! : Colors.grey[300]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20;

    canvas.drawCircle(center, radius, outerPaint);

    // Inner background
    final bgPaint = Paint()
      ..color = isDark ? Colors.grey[900]! : Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius - 10, bgPaint);

    // Port/starboard markers
    final portPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round;

    final stbdPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round;

    // Port arc (left side, 270-330 degrees)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 5),
      150 * math.pi / 180,
      60 * math.pi / 180,
      false,
      portPaint,
    );

    // Starboard arc (right side, 30-90 degrees)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 5),
      -30 * math.pi / 180,
      60 * math.pi / 180,
      false,
      stbdPaint,
    );
  }

  void _drawCompassMarkings(Canvas canvas, double radius) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    final tickPaint = Paint()
      ..color = isDark ? Colors.white70 : Colors.black87
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final majorTickPaint = Paint()
      ..color = isDark ? Colors.white : Colors.black
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    // Draw compass markings
    for (int i = 0; i < 360; i += 10) {
      final angle = i * math.pi / 180;
      final isMajor = i % 30 == 0;
      final paint = isMajor ? majorTickPaint : tickPaint;
      final tickLength = isMajor ? 15.0 : 8.0;

      final startX = (radius - tickLength) * math.sin(angle);
      final startY = -(radius - tickLength) * math.cos(angle);
      final endX = radius * math.sin(angle);
      final endY = -radius * math.cos(angle);

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);

      // Draw degree text for major marks
      if (i % 30 == 0) {
        final textRadius = radius - 35;
        final textX = textRadius * math.sin(angle);
        final textY = -textRadius * math.cos(angle);

        String label;
        if (i == 0) label = 'N';
        else if (i == 90) label = 'E';
        else if (i == 180) label = 'S';
        else if (i == 270) label = 'W';
        else label = i.toString();

        textPainter.text = TextSpan(
          text: label,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: isMajor && (i % 90 == 0) ? 20 : 16,
            fontWeight: (i % 90 == 0) ? FontWeight.bold : FontWeight.normal,
          ),
        );
        textPainter.layout();

        // Rotate text to be upright
        canvas.save();
        canvas.translate(textX, textY);
        canvas.rotate(heading * math.pi / 180); // Counter-rotate text
        textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
        canvas.restore();
      }
    }
  }

  void _drawWindSectors(Canvas canvas, double radius) {
    // Draw wind sector showing historical wind range
    // Port sector (left side)
    final portSectorPaint = Paint()
      ..color = primaryColor.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    final minAngle = (trueWindMinHistoric! - laylineAngle) * math.pi / 180;
    final midAngle = (trueWindMidHistoric!) * math.pi / 180;
    final maxAngle = (trueWindMaxHistoric! + laylineAngle) * math.pi / 180;

    // Create sector path for port side
    final portPath = Path();
    portPath.moveTo(0, 0); // Center
    portPath.lineTo(radius * math.sin(minAngle), -radius * math.cos(minAngle));
    portPath.arcTo(
      Rect.fromCircle(center: Offset.zero, radius: radius),
      -math.pi / 2 + minAngle,
      midAngle - minAngle,
      false,
    );
    portPath.close();
    canvas.drawPath(portPath, portSectorPaint);

    // Starboard sector (right side)
    final stbdSectorPaint = Paint()
      ..color = primaryColor.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    final stbdPath = Path();
    stbdPath.moveTo(0, 0);
    stbdPath.lineTo(radius * math.sin(midAngle), -radius * math.cos(midAngle));
    stbdPath.arcTo(
      Rect.fromCircle(center: Offset.zero, radius: radius),
      -math.pi / 2 + midAngle,
      maxAngle - midAngle,
      false,
    );
    stbdPath.close();
    canvas.drawPath(stbdPath, stbdSectorPaint);
  }

  void _drawLaylines(Canvas canvas, double radius, double awaAngle, double laylineAngle) {
    final laylinePaint = Paint()
      ..color = primaryColor.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Laylines are offset from AWA by the layline angle
    final portLaylineAngle = (awaAngle - laylineAngle) * math.pi / 180;
    final stbdLaylineAngle = (awaAngle + laylineAngle) * math.pi / 180;

    // Draw port layline
    final portX = radius * math.sin(portLaylineAngle);
    final portY = -radius * math.cos(portLaylineAngle);
    canvas.drawLine(Offset.zero, Offset(portX, portY), laylinePaint);

    // Draw starboard layline
    final stbdX = radius * math.sin(stbdLaylineAngle);
    final stbdY = -radius * math.cos(stbdLaylineAngle);
    canvas.drawLine(Offset.zero, Offset(stbdX, stbdY), laylinePaint);
  }

  void _drawWindIndicator(Canvas canvas, Offset center, double length, double angle, Color color, String label, {required bool large}) {
    final radians = angle * math.pi / 180;
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(radians);

    // Draw arrow
    final arrowPath = Path();
    final width = large ? 20.0 : 15.0;
    final headSize = large ? 30.0 : 20.0;

    arrowPath.moveTo(0, -length);
    arrowPath.lineTo(-width, -length + headSize);
    arrowPath.lineTo(-width * 0.4, -length + headSize);
    arrowPath.lineTo(-width * 0.4, -headSize);
    arrowPath.lineTo(width * 0.4, -headSize);
    arrowPath.lineTo(width * 0.4, -length + headSize);
    arrowPath.lineTo(width, -length + headSize);
    arrowPath.close();

    canvas.drawPath(arrowPath, arrowPaint);

    // Draw label
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: large ? 24 : 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(-textPainter.width / 2, -headSize / 2 - textPainter.height / 2));

    canvas.restore();
  }

  void _drawCOGIndicator(Canvas canvas, Offset center, double length, double relativeAngle) {
    final radians = relativeAngle * math.pi / 180;
    final cogPaint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(radians);

    // Draw diamond indicator
    final path = Path();
    path.moveTo(0, -length);
    path.lineTo(8, -length + 12);
    path.lineTo(0, -length + 20);
    path.lineTo(-8, -length + 12);
    path.close();

    canvas.drawPath(path, cogPaint);
    canvas.restore();
  }

  void _drawWaypointIndicator(Canvas canvas, Offset center, double length, double relativeAngle) {
    final radians = relativeAngle * math.pi / 180;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(radians);

    // Draw waypoint marker (circle with line)
    final waypointPaint = Paint()
      ..color = Colors.purple
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Draw line to waypoint
    canvas.drawLine(Offset(0, 0), Offset(0, -length), waypointPaint);

    // Draw circle at waypoint position
    final circlePaint = Paint()
      ..color = Colors.purple
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(0, -length), 8, circlePaint);

    // Draw border
    canvas.drawCircle(Offset(0, -length), 8, waypointPaint);

    canvas.restore();
  }

  void _drawDriftIndicator(Canvas canvas, Offset center, double length, double relativeAngle) {
    final radians = relativeAngle * math.pi / 180;
    final driftPaint = Paint()
      ..color = Colors.cyan
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(radians);

    // Draw drift arrow (gradient arrow showing current)
    final arrowPath = Path();
    arrowPath.moveTo(0, 0);
    arrowPath.lineTo(-10, -length + 20);
    arrowPath.lineTo(-5, -length + 20);
    arrowPath.lineTo(-5, -length);
    arrowPath.lineTo(5, -length);
    arrowPath.lineTo(5, -length + 20);
    arrowPath.lineTo(10, -length + 20);
    arrowPath.close();

    canvas.drawPath(arrowPath, driftPaint);
    canvas.restore();
  }

  void _drawBoatIcon(Canvas canvas, Offset center) {
    final boatPaint = Paint()
      ..color = isDark ? Colors.white : Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Simple boat outline
    final boatPath = Path();
    boatPath.moveTo(center.dx, center.dy - 25); // Bow
    boatPath.quadraticBezierTo(
      center.dx - 15, center.dy,
      center.dx - 10, center.dy + 20,
    ); // Port side
    boatPath.quadraticBezierTo(
      center.dx, center.dy + 25,
      center.dx + 10, center.dy + 20,
    ); // Stern
    boatPath.quadraticBezierTo(
      center.dx + 15, center.dy,
      center.dx, center.dy - 25,
    ); // Starboard side

    canvas.drawPath(boatPath, boatPaint);

    // Center line
    canvas.drawLine(
      Offset(center.dx, center.dy - 25),
      Offset(center.dx, center.dy + 20),
      boatPaint,
    );
  }

  @override
  bool shouldRepaint(_WindsteerPainter oldDelegate) {
    return heading != oldDelegate.heading ||
        apparentWindAngle != oldDelegate.apparentWindAngle ||
        trueWindAngle != oldDelegate.trueWindAngle ||
        courseOverGround != oldDelegate.courseOverGround ||
        waypointBearing != oldDelegate.waypointBearing ||
        driftSet != oldDelegate.driftSet ||
        trueWindMinHistoric != oldDelegate.trueWindMinHistoric ||
        trueWindMidHistoric != oldDelegate.trueWindMidHistoric ||
        trueWindMaxHistoric != oldDelegate.trueWindMaxHistoric ||
        laylineAngle != oldDelegate.laylineAngle ||
        showLaylines != oldDelegate.showLaylines ||
        showTrueWind != oldDelegate.showTrueWind ||
        showCOG != oldDelegate.showCOG ||
        showDrift != oldDelegate.showDrift ||
        showWaypoint != oldDelegate.showWaypoint ||
        showWindSectors != oldDelegate.showWindSectors;
  }
}
