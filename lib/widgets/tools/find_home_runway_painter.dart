import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// ILS-style runway CustomPainter for the Find Home tool.
///
/// Draws a perspective runway with deviation indicator, distance markers,
/// sky (sun/moon/stars), and target/vessel icons.
class FindHomeRunwayPainter extends CustomPainter {
  final double deviation;
  final double maxDeviation;
  final double distanceMeters;
  final double metersPerUnit;
  final String unitSymbol;
  final bool isDark;
  final bool active;
  final double hapticThreshold;
  final bool isWrongWay;
  final bool isAisMode;
  final bool isStaleTarget;
  final bool isTrackMode;
  final bool isDodgeMode;
  final bool isRouteMode;
  final double? targetCogDeg;
  final bool isBowPass;
  final double sunAltitudeDeg;
  final double sunAzimuthDeg;
  final double moonAltitudeDeg;
  final double moonAzimuthDeg;
  final double moonPhase;
  final double moonFraction;
  final double vesselCogDeg;
  final double vesselLatitude;

  FindHomeRunwayPainter({
    required this.deviation,
    required this.maxDeviation,
    required this.distanceMeters,
    required this.metersPerUnit,
    required this.unitSymbol,
    required this.isDark,
    required this.active,
    required this.hapticThreshold,
    required this.isWrongWay,
    this.isAisMode = false,
    this.isStaleTarget = false,
    this.isTrackMode = false,
    this.isDodgeMode = false,
    this.isRouteMode = false,
    this.targetCogDeg,
    this.isBowPass = false,
    this.sunAltitudeDeg = -90,
    this.sunAzimuthDeg = 0,
    this.moonAltitudeDeg = -90,
    this.moonAzimuthDeg = 0,
    this.moonPhase = 0,
    this.moonFraction = 0,
    this.vesselCogDeg = 0,
    this.vesselLatitude = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final centerX = w / 2;

    final bgColor =
        isDark ? const Color(0xFF1A1A2E) : const Color(0xFFE8EAF6);
    final centerLineColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : Colors.black.withValues(alpha: 0.4);

    final absDev = deviation.abs();
    Color devColor;
    if (absDev < 5) {
      devColor = Colors.green;
    } else if (absDev < 15) {
      devColor = Colors.amber;
    } else {
      devColor = Colors.red;
    }

    // Background — red tint when wrong way, subtle dodge tint in dodge mode
    Color effectiveBg;
    if (isWrongWay) {
      effectiveBg = Color.lerp(bgColor, Colors.red.shade900, 0.4)!;
    } else if (isDodgeMode) {
      final tintColor = isBowPass ? Colors.orange.shade900 : Colors.cyan.shade900;
      effectiveBg = Color.lerp(bgColor, tintColor, 0.15)!;
    } else {
      effectiveBg = bgColor;
    }
    // Sky above horizon, ground below — horizon at runway top (~40% down)
    final horizonFrac = 0.4;

    // Dynamic sky — warm color rises from horizon as sun climbs
    const nightColor = Color(0xFF0D1B2A);       // deep navy
    const dawnColor = Color(0xFFD4893F);         // golden/orange
    const daySkyTop = Color(0xFF1A4A7A);         // clear blue
    const daySkyHorizon = Color(0xFF5B8FB9);     // lighter blue

    final alt = sunAltitudeDeg;

    // How far up the sky the warm color has risen (0 = horizon only, 1 = fills sky)
    // Starts at horizon during early twilight, rises to top by full day
    final double warmRise;
    final Color warmColor;
    final Color topColor;

    if (alt < -18) {
      // Full night — all dark
      warmRise = 0;
      warmColor = nightColor;
      topColor = nightColor;
    } else if (alt < -6) {
      // Twilight — warm glow appears at horizon, stays low
      final t = (alt + 18) / 12; // 0→1
      warmRise = t * 0.1; // rises to 10% of sky
      warmColor = Color.lerp(nightColor, dawnColor, t)!;
      topColor = nightColor;
    } else if (alt < 0) {
      // Civil twilight — warm band rises, intensifies
      final t = (alt + 6) / 6; // 0→1
      warmRise = 0.1 + t * 0.25; // 10% → 35%
      warmColor = Color.lerp(dawnColor, const Color(0xFFE8A54B), t)!;
      topColor = Color.lerp(nightColor, const Color(0xFF1B3555), t)!;
    } else if (alt < 10) {
      // Low sun — warm color floods upward, transitions to blue
      final t = alt / 10; // 0→1
      warmRise = 0.35 + t * 0.65; // 35% → 100%
      warmColor = Color.lerp(const Color(0xFFE8A54B), daySkyHorizon, t)!;
      topColor = Color.lerp(const Color(0xFF1B3555), daySkyTop, t)!;
    } else {
      // Full day — blue sky
      warmRise = 1.0;
      warmColor = daySkyHorizon;
      topColor = daySkyTop;
    }

    // Build gradient: top color → warm color rising from horizon → ground
    // The warm/top boundary sits at horizonFrac * (1 - warmRise)
    final warmBoundary = horizonFrac * (1.0 - warmRise);

    final groundColor = effectiveBg;
    final groundPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [
          0.0,
          math.max(warmBoundary - 0.02, 0.0),
          math.min(warmBoundary + 0.02, horizonFrac - 0.01),
          horizonFrac,
          1.0,
        ],
        colors: [
          topColor,
          topColor,
          warmColor,
          groundColor,
          groundColor,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), groundPaint);

    // Horizon line
    final horizonY = h * horizonFrac;
    canvas.drawLine(
      Offset(0, horizonY),
      Offset(w, horizonY),
      Paint()
        ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.3)
        ..strokeWidth = 1.0,
    );

    // --- Sun/Moon in sky — positioned by azimuth relative to vessel heading ---
    final skyHeight = horizonY;
    // Field of view: ±90° from heading maps to full sky width
    const skyFov = 90.0;

    // Sun
    if (sunAltitudeDeg > 0) {
      // Relative bearing: how far left/right of heading is the sun
      var sunRelBearing = (sunAzimuthDeg - vesselCogDeg) % 360;
      if (sunRelBearing > 180) sunRelBearing -= 360; // -180 to +180
      if (sunRelBearing.abs() <= skyFov) {
        final sunX = w / 2 + (sunRelBearing / skyFov) * (w / 2);
        final sunY = horizonY - (sunAltitudeDeg.clamp(0, 90) / 90) * (skyHeight - 20);
        final sunCenter = Offset(sunX, sunY);
        const sunRadius = 14.0;
        // Glow
        canvas.drawCircle(
          sunCenter,
          sunRadius + 6,
          Paint()..color = Colors.amber.withValues(alpha: 0.25),
        );
        // Disc
        canvas.drawCircle(
          sunCenter,
          sunRadius,
          Paint()..color = Colors.amber,
        );
      }
    }
    // Moon
    if (moonAltitudeDeg > 0) {
      var moonRelBearing = (moonAzimuthDeg - vesselCogDeg) % 360;
      if (moonRelBearing > 180) moonRelBearing -= 360;
      if (moonRelBearing.abs() <= skyFov) {
        final moonX = w / 2 + (moonRelBearing / skyFov) * (w / 2);
        final moonY = horizonY - (moonAltitudeDeg.clamp(0, 90) / 90) * (skyHeight - 20);
        final moonSize = 36.0;
        canvas.save();
        canvas.translate(moonX - moonSize / 2, moonY - moonSize / 2);
        _paintMoonPhase(canvas, Size(moonSize, moonSize));
        canvas.restore();
      }
    }

    // Polaris — visible at night, northern hemisphere only
    // Altitude ≈ vessel latitude, azimuth ≈ true north (0°)
    if (sunAltitudeDeg < -6 && vesselLatitude > 5) {
      final polarisAlt = vesselLatitude.clamp(0.0, 90.0);
      var polarisRelBearing = (0.0 - vesselCogDeg) % 360;
      if (polarisRelBearing > 180) polarisRelBearing -= 360;
      if (polarisRelBearing.abs() <= skyFov) {
        final px = w / 2 + (polarisRelBearing / skyFov) * (w / 2);
        final py = horizonY - (polarisAlt / 90) * (skyHeight - 20);
        // Star with 4-point rays and glow
        final starCenter = Offset(px, py);
        // Outer glow
        canvas.drawCircle(starCenter, 8, Paint()
          ..color = Colors.white.withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
        // Core
        canvas.drawCircle(starCenter, 3, Paint()
          ..color = Colors.white.withValues(alpha: 0.9));
        // Rays
        final rayPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.7)
          ..strokeWidth = 1.0
          ..strokeCap = StrokeCap.round;
        const rayLen = 10.0;
        canvas.drawLine(Offset(px - rayLen, py), Offset(px + rayLen, py), rayPaint);
        canvas.drawLine(Offset(px, py - rayLen), Offset(px, py + rayLen), rayPaint);
        // Diagonal rays (shorter)
        const diagLen = 6.0;
        canvas.drawLine(Offset(px - diagLen, py - diagLen), Offset(px + diagLen, py + diagLen), rayPaint);
        canvas.drawLine(Offset(px + diagLen, py - diagLen), Offset(px - diagLen, py + diagLen), rayPaint);
      }
    }

    // Off-screen sun glow — orange corner glow when sun is above horizon but outside FOV
    if (sunAltitudeDeg > 0) {
      var sunRel = (sunAzimuthDeg - vesselCogDeg) % 360;
      if (sunRel > 180) sunRel -= 360;
      if (sunRel.abs() > skyFov) {
        final cornerX = sunRel > 0 ? w : 0.0;
        final glowRadius = w * 0.3;
        canvas.drawCircle(
          Offset(cornerX, 0),
          glowRadius,
          Paint()
            ..shader = ui.Gradient.radial(
              Offset(cornerX, 0),
              glowRadius,
              [Colors.orange.withValues(alpha: 0.4), Colors.orange.withValues(alpha: 0.0)],
            ),
        );
      }
    }

    // Off-screen moon glow — white corner glow at night, brightness ∝ moonFraction
    if (sunAltitudeDeg <= 0 && moonAltitudeDeg > 0) {
      var moonRel = (moonAzimuthDeg - vesselCogDeg) % 360;
      if (moonRel > 180) moonRel -= 360;
      if (moonRel.abs() > skyFov) {
        final cornerX = moonRel > 0 ? w : 0.0;
        final glowRadius = w * 0.3;
        final alpha = (moonFraction * 0.5).clamp(0.0, 0.5);
        canvas.drawCircle(
          Offset(cornerX, 0),
          glowRadius,
          Paint()
            ..shader = ui.Gradient.radial(
              Offset(cornerX, 0),
              glowRadius,
              [Colors.white.withValues(alpha: alpha), Colors.white.withValues(alpha: 0.0)],
            ),
        );
      }
    }

    // Dim runway elements when wrong way
    final dimFactor = isWrongWay ? 0.5 : 1.0;

    // Runway geometry — trapezoid: narrow at top (far), wide at bottom (near)
    final apexY = 20.0 + (h - 40) * 0.4;
    final baseY = h - 20.0;
    final runwayHeight = baseY - apexY;
    final baseHalfWidth = (w / 2) - 20;
    final topHalfWidth = baseHalfWidth * 0.15; // Squared-off far end

    // --- Rolling road runway surface ---
    final runwayPaint = Paint()
      ..color = isDark
          ? const Color(0xFF1A3A5C).withValues(alpha: 0.7 * dimFactor)
          : const Color(0xFFB0C4DE).withValues(alpha: 0.4 * dimFactor);
    final runwayPath = Path()
      ..moveTo(centerX - topHalfWidth, apexY)
      ..lineTo(centerX + topHalfWidth, apexY)
      ..lineTo(centerX + baseHalfWidth, baseY)
      ..lineTo(centerX - baseHalfWidth, baseY)
      ..close();
    canvas.drawPath(runwayPath, runwayPaint);

    // --- Perspective lines fanning from top to bottom ---
    const perspectiveLineCount = 10;
    final perspLinePaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.15 * dimFactor)
      ..strokeWidth = 0.5;
    for (var i = 0; i <= perspectiveLineCount; i++) {
      final frac = i / perspectiveLineCount;
      final topX = centerX - topHalfWidth + (2 * topHalfWidth * frac);
      final baseX = centerX - baseHalfWidth + (2 * baseHalfWidth * frac);
      canvas.drawLine(Offset(topX, apexY), Offset(baseX, baseY), perspLinePaint);
    }

    // --- Port (red) and starboard (green) edge lines ---
    final portEdgePaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.8 * dimFactor)
      ..strokeWidth = 1.5;
    final stbdEdgePaint = Paint()
      ..color = Colors.green.withValues(alpha: 0.8 * dimFactor)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(centerX - topHalfWidth, apexY),
        Offset(centerX - baseHalfWidth, baseY), portEdgePaint);
    canvas.drawLine(Offset(centerX + topHalfWidth, apexY),
        Offset(centerX + baseHalfWidth, baseY), stbdEdgePaint);

    // --- Haptic corridor (±5° on-course zone) ---
    final hapticFrac = hapticThreshold / maxDeviation;
    final hapticBaseHalf = baseHalfWidth * hapticFrac;
    final hapticTopHalf = topHalfWidth * hapticFrac;
    final hapticFillPaint = Paint()
      ..color = Colors.green.withValues(alpha: (isDark ? 0.08 : 0.05) * dimFactor);
    final hapticPath = Path()
      ..moveTo(centerX - hapticTopHalf, apexY)
      ..lineTo(centerX + hapticTopHalf, apexY)
      ..lineTo(centerX + hapticBaseHalf, baseY)
      ..lineTo(centerX - hapticBaseHalf, baseY)
      ..close();
    canvas.drawPath(hapticPath, hapticFillPaint);

    // Haptic corridor edge lines
    final hapticEdgePaint = Paint()
      ..color = Colors.green.withValues(alpha: 0.25 * dimFactor)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(centerX - hapticTopHalf, apexY),
        Offset(centerX - hapticBaseHalf, baseY), hapticEdgePaint);
    canvas.drawLine(Offset(centerX + hapticTopHalf, apexY),
        Offset(centerX + hapticBaseHalf, baseY), hapticEdgePaint);

    // --- Center line (dashed) ---
    final centerPaint = Paint()
      ..color = centerLineColor
      ..strokeWidth = 2.0;
    const dashLen = 8.0;
    const gapLen = 6.0;
    var y = apexY;
    while (y < baseY) {
      canvas.drawLine(
        Offset(centerX, y),
        Offset(centerX, math.min(y + dashLen, baseY)),
        centerPaint,
      );
      y += dashLen + gapLen;
    }

    // --- Distance countdown markers along centerline ---
    final distInUnits = distanceMeters / metersPerUnit;
    _drawDistanceMarkers(
        canvas, centerX, apexY, baseY, runwayHeight, distInUnits);

    // --- Target icon at apex ---
    if (isDodgeMode && targetCogDeg != null) {
      // In dodge mode: draw target vessel chevron rotated to its COG
      _drawTargetVesselAtApex(canvas, Offset(centerX, apexY + 10), targetCogDeg!);
    } else if (isRouteMode) {
      _drawWaypointIcon(canvas, Offset(centerX, apexY + 10));
    } else if (isAisMode) {
      _drawVesselIcon(canvas, Offset(centerX, apexY - 8));
    } else if (isTrackMode) {
      _drawBoatIcon(canvas, Offset(centerX, apexY + 10));
    } else {
      _drawAnchorIcon(canvas, Offset(centerX, apexY + 10));
    }

    // --- Label over apex icon ---
    if (isDodgeMode) {
      final dodgeColor = isBowPass ? Colors.orange : Colors.cyan;
      final label = isBowPass ? 'BOW' : 'STERN';
      final labelStyle = TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w900,
        color: dodgeColor,
        letterSpacing: 0.5,
      );
      final labelTp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      labelTp.paint(canvas, Offset(centerX - labelTp.width / 2, apexY - 4));
    } else if (isRouteMode) {
      const wptStyle = TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w900,
        color: Colors.green,
        letterSpacing: 0.5,
      );
      final wptTp = TextPainter(
        text: const TextSpan(text: 'WPT', style: wptStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      wptTp.paint(canvas, Offset(centerX - wptTp.width / 2, apexY - 4));
    } else if (isAisMode) {
      final aisColor = isStaleTarget ? Colors.orange : Colors.cyan;
      final aisStyle = TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w900,
        color: aisColor,
        letterSpacing: 0.5,
      );
      final aisTp = TextPainter(
        text: TextSpan(text: isStaleTarget ? 'AIS ?' : 'AIS', style: aisStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      aisTp.paint(canvas, Offset(centerX - aisTp.width / 2, apexY - 32));
    }

    // --- Vessel triangle ---
    // deviation > 0 = on PORT side (bearing is CW from COG) → triangle LEFT
    // deviation < 0 = on STARBOARD side → triangle RIGHT
    final clampedDev = deviation.clamp(-maxDeviation, maxDeviation);
    final vesselX = centerX - (clampedDev / maxDeviation) * baseHalfWidth;
    final vesselY = baseY - 16;

    // --- COG line (dotted, from vessel upward — where you're actually heading) ---
    // Only draw when vessel is within the runway (not clamped at edge)
    final isClamped = deviation.abs() >= maxDeviation;
    if (!isClamped) {
      final cogPaint = Paint()
        ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.4)
        ..strokeWidth = 1.0;
      _drawDashedLine(canvas, Offset(vesselX, vesselY - 12),
          Offset(vesselX, apexY + 20), cogPaint, 5, 4);
    }

    // --- Bearing line (dotted, from vessel to apex — where you need to go) ---
    final bearingLineColor = isDodgeMode
        ? (isBowPass ? Colors.orange : Colors.cyan).withValues(alpha: active ? 0.7 : 0.4)
        : devColor.withValues(alpha: active ? 0.7 : 0.4);
    final bearingPaint = Paint()
      ..color = bearingLineColor
      ..strokeWidth = 1.5;
    _drawDashedLine(canvas, Offset(vesselX, vesselY - 12),
        Offset(centerX, apexY + 18), bearingPaint, 6, 4);

    // --- Target COG track line through apex (dodge mode only) ---
    if (isDodgeMode && targetCogDeg != null) {
      final cogTrackColor = (isBowPass ? Colors.orange : Colors.cyan)
          .withValues(alpha: 0.3);
      final cogTrackPaint = Paint()
        ..color = cogTrackColor
        ..strokeWidth = 1.0;
      // Draw a line extending upward from apex in target's COG direction
      // Since runway is heading-up, we just draw a vertical-ish line from apex
      _drawDashedLine(
        canvas,
        Offset(centerX, apexY + 20),
        Offset(centerX, apexY - 10),
        cogTrackPaint,
        4,
        3,
      );
    }

    // Vessel chevron — open V-shape rotated by COG deviation
    canvas.save();
    canvas.translate(vesselX, vesselY);
    canvas.rotate(-deviation * math.pi / 180);
    final chevronPaint = Paint()
      ..color = devColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final chevronPath = Path()
      ..moveTo(-8, 6)
      ..lineTo(0, -8)
      ..lineTo(8, 6);
    canvas.drawPath(chevronPath, chevronPaint);
    canvas.restore();

    // --- P / S labels ---
    final labelStyle = TextStyle(
      fontSize: 11,
      color: isDark ? Colors.white38 : Colors.black38,
      fontWeight: FontWeight.bold,
    );
    _drawText(canvas, 'P', Offset(8, baseY - 20), labelStyle);
    _drawText(canvas, 'S', Offset(w - 16, baseY - 20), labelStyle);

    // --- Wrong-way overlay ---
    if (isWrongWay) {
      _drawWrongWayOverlay(canvas, size, deviation);
    }
  }

  void _drawWrongWayOverlay(Canvas canvas, Size size, double deviation) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // "TURN AROUND" title
    final titleStyle = TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w900,
      color: Colors.red.shade300,
      letterSpacing: 2.0,
    );
    final titleTp = TextPainter(
      text: TextSpan(text: 'TURN AROUND', style: titleStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    titleTp.paint(
      canvas,
      Offset(centerX - titleTp.width / 2, centerY - titleTp.height - 4),
    );

    // Direction hint: deviation > 0 means boat is to port → turn starboard
    final turnDir = deviation > 0 ? 'TURN STARBOARD' : 'TURN PORT';
    final arrow = deviation > 0 ? '\u21BB' : '\u21BA'; // ↻ or ↺
    final dirStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: Colors.red.shade200,
      letterSpacing: 1.0,
    );
    final dirTp = TextPainter(
      text: TextSpan(text: '$arrow $turnDir', style: dirStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    dirTp.paint(
      canvas,
      Offset(centerX - dirTp.width / 2, centerY + 4),
    );
  }

  /// Draw 3-4 evenly spaced distance markers ON the centerline.
  /// Labels show distance from the destination (0 at apex/anchor).
  /// Positioned at nice round fractions of total distance.
  void _drawDistanceMarkers(
    Canvas canvas,
    double centerX,
    double apexY,
    double baseY,
    double runwayHeight,
    double distInUnits,
  ) {
    if (distInUnits < 0.001) return;

    // Pick 3 evenly-spaced marker positions at 25%, 50%, 75% of distance
    final fractions = [0.25, 0.50, 0.75];

    final markerColor = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : Colors.black.withValues(alpha: 0.4);
    final markerStyle = TextStyle(
      fontSize: 10,
      color: markerColor,
      fontFamily: 'monospace',
      fontWeight: FontWeight.w500,
    );

    for (final frac in fractions) {
      // Distance from destination at this marker
      final distFromDest = distInUnits * frac;
      // Y position: frac=0 is at apex (destination), frac=1 is at base (vessel)
      final markerY = apexY + frac * runwayHeight;

      // Skip if too close to anchor icon or vessel triangle
      if (markerY < apexY + 30 || markerY > baseY - 34) continue;

      // Format the distance label
      final label = _formatSmartDistance(distFromDest);

      // Draw label centered on the centerline
      final tp = TextPainter(
        text: TextSpan(text: label, style: markerStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      // Background pill behind text for readability
      final pillRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX, markerY),
          width: tp.width + 10,
          height: tp.height + 4,
        ),
        const Radius.circular(4),
      );
      canvas.drawRRect(
        pillRect,
        Paint()..color = (isDark ? Colors.black : Colors.white).withValues(alpha: 0.6),
      );

      tp.paint(
        canvas,
        Offset(centerX - tp.width / 2, markerY - tp.height / 2),
      );
    }
  }

  /// Format distance with minimal clutter. No unit symbol on every marker —
  /// just the number. Unit is already shown in the header.
  String _formatSmartDistance(double value) {
    if (value >= 10) return value.toStringAsFixed(0);
    if (value >= 1) return value.toStringAsFixed(1);
    if (value >= 0.1) return value.toStringAsFixed(2);
    return value.toStringAsFixed(3);
  }

  /// Draw a waypoint flag icon for route mode apex.
  void _drawWaypointIcon(Canvas canvas, Offset center) {
    const color = Colors.green;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    final x = center.dx;
    final y = center.dy;

    // Pole
    canvas.drawLine(Offset(x, y - 8), Offset(x, y + 8), paint);
    // Flag triangle
    final flag = Path()
      ..moveTo(x, y - 8)
      ..lineTo(x + 8, y - 4)
      ..lineTo(x, y)
      ..close();
    canvas.drawPath(flag, fillPaint);
    canvas.drawPath(flag, paint);
    // Base dot
    canvas.drawCircle(Offset(x, y + 8), 2, fillPaint);
  }

  void _drawAnchorIcon(Canvas canvas, Offset center) {
    final Color anchorColor;
    if (isAisMode && isStaleTarget) {
      anchorColor = Colors.orange;
    } else if (isAisMode) {
      anchorColor = Colors.cyan;
    } else {
      anchorColor = isDark ? Colors.white70 : Colors.black54;
    }
    final paint = Paint()
      ..color = anchorColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final x = center.dx;
    final y = center.dy;

    canvas.drawLine(Offset(x, y - 6), Offset(x, y + 6), paint);
    canvas.drawLine(Offset(x - 5, y - 3), Offset(x + 5, y - 3), paint);
    canvas.drawCircle(Offset(x, y - 7), 2, paint);
    final flukePath = Path()
      ..moveTo(x - 6, y + 2)
      ..quadraticBezierTo(x - 6, y + 7, x, y + 6)
      ..quadraticBezierTo(x + 6, y + 7, x + 6, y + 2);
    canvas.drawPath(flukePath, paint);
  }

  /// Draw a simple boat icon pointing up (bow at top).
  void _drawBoatIcon(Canvas canvas, Offset center) {
    final Color boatColor;
    if (isAisMode && isStaleTarget) {
      boatColor = Colors.orange;
    } else if (isAisMode) {
      boatColor = Colors.cyan;
    } else {
      boatColor = isDark ? Colors.white70 : Colors.black54;
    }
    final paint = Paint()
      ..color = boatColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final x = center.dx;
    final y = center.dy;

    // Hull outline — pointed bow at top, flat stern at bottom
    final hull = Path()
      ..moveTo(x, y - 8)          // bow
      ..lineTo(x - 6, y + 2)      // port chine
      ..lineTo(x - 5, y + 6)      // port stern
      ..lineTo(x + 5, y + 6)      // starboard stern
      ..lineTo(x + 6, y + 2)      // starboard chine
      ..close();
    canvas.drawPath(hull, paint);

    // Keel line (centerline from bow down)
    canvas.drawLine(Offset(x, y - 8), Offset(x, y + 6), paint);
  }

  /// Draw a vessel icon using Material Icons.directions_boat for AIS mode.
  void _drawVesselIcon(Canvas canvas, Offset center) {
    final Color color = isStaleTarget ? Colors.orange : Colors.cyan;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.directions_boat.codePoint),
        style: TextStyle(
          fontSize: 20,
          fontFamily: Icons.directions_boat.fontFamily,
          package: Icons.directions_boat.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  /// Draw target vessel chevron at apex, rotated to target COG.
  void _drawTargetVesselAtApex(Canvas canvas, Offset center, double cogDeg) {
    final color = isBowPass ? Colors.orange : Colors.cyan;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.save();
    canvas.translate(center.dx, center.dy);

    // Vessel hull
    final hull = Path()
      ..moveTo(0, -8)       // bow
      ..lineTo(-6, 2)       // port
      ..lineTo(-5, 6)       // port stern
      ..lineTo(5, 6)        // starboard stern
      ..lineTo(6, 2)        // starboard
      ..close();
    canvas.drawPath(hull, paint);

    // Fill with translucent color
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawPath(hull, fillPaint);

    canvas.restore();
  }

  void _drawDashedLine(Canvas canvas, Offset from, Offset to, Paint paint,
      double dashLen, double gapLen) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 1) return;
    final ux = dx / dist;
    final uy = dy / dist;
    var drawn = 0.0;
    while (drawn < dist) {
      final segEnd = math.min(drawn + dashLen, dist);
      canvas.drawLine(
        Offset(from.dx + ux * drawn, from.dy + uy * drawn),
        Offset(from.dx + ux * segEnd, from.dy + uy * segEnd),
        paint,
      );
      drawn = segEnd + gapLen;
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  /// Paint moon phase disc — same algorithm as SunMoonArc's _MoonPhasePainter.
  void _paintMoonPhase(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1;

    // Dark side
    canvas.drawCircle(center, radius, Paint()
      ..color = Colors.grey.shade800
      ..style = PaintingStyle.fill);

    if (moonFraction < 0.01) return;
    if (moonFraction > 0.99) {
      canvas.drawCircle(center, radius, Paint()
        ..color = Colors.grey.shade200
        ..style = PaintingStyle.fill);
      return;
    }

    final lightPaint = Paint()
      ..color = Colors.grey.shade200
      ..style = PaintingStyle.fill;
    final isWaxing = moonPhase < 0.5;
    final termWidth = radius * (2.0 * moonFraction - 1.0);
    final isGibbous = moonFraction > 0.5;
    final path = Path();

    if (isWaxing) {
      path.moveTo(center.dx, center.dy - radius);
      path.arcToPoint(Offset(center.dx, center.dy + radius),
          radius: Radius.circular(radius), clockwise: true);
      path.arcToPoint(Offset(center.dx, center.dy - radius),
          radius: Radius.elliptical(termWidth.abs().clamp(0.1, radius), radius),
          clockwise: isGibbous);
    } else {
      path.moveTo(center.dx, center.dy - radius);
      path.arcToPoint(Offset(center.dx, center.dy + radius),
          radius: Radius.circular(radius), clockwise: false);
      path.arcToPoint(Offset(center.dx, center.dy - radius),
          radius: Radius.elliptical(termWidth.abs().clamp(0.1, radius), radius),
          clockwise: !isGibbous);
    }
    path.close();
    canvas.drawPath(path, lightPaint);

    // Outline
    canvas.drawCircle(center, radius, Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5);
  }

  @override
  bool shouldRepaint(FindHomeRunwayPainter oldDelegate) {
    return oldDelegate.deviation != deviation ||
        oldDelegate.distanceMeters != distanceMeters ||
        oldDelegate.isDark != isDark ||
        oldDelegate.active != active ||
        oldDelegate.metersPerUnit != metersPerUnit ||
        oldDelegate.isWrongWay != isWrongWay ||
        oldDelegate.isAisMode != isAisMode ||
        oldDelegate.isStaleTarget != isStaleTarget ||
        oldDelegate.isTrackMode != isTrackMode ||
        oldDelegate.isDodgeMode != isDodgeMode ||
        oldDelegate.isRouteMode != isRouteMode ||
        oldDelegate.targetCogDeg != targetCogDeg ||
        oldDelegate.isBowPass != isBowPass ||
        oldDelegate.sunAltitudeDeg != sunAltitudeDeg ||
        oldDelegate.sunAzimuthDeg != sunAzimuthDeg ||
        oldDelegate.moonAltitudeDeg != moonAltitudeDeg ||
        oldDelegate.moonAzimuthDeg != moonAzimuthDeg ||
        oldDelegate.moonPhase != moonPhase ||
        oldDelegate.moonFraction != moonFraction ||
        oldDelegate.vesselCogDeg != vesselCogDeg ||
        oldDelegate.vesselLatitude != vesselLatitude;
  }
}
