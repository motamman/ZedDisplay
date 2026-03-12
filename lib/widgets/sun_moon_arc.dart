/// Sun/Moon Arc Widget
/// Configurable arc display for sun/moon times with multiple arc styles
/// Arc angles: 90°, 180°, 270°, 320°, 355°
library;

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'weatherflow_forecast.dart';
import '../utils/date_time_formatter.dart';

/// Available arc styles
enum ArcStyle {
  /// 180° arc - half circle (default)
  half(180),
  /// 270° arc - three-quarter circle
  threeQuarter(270),
  /// 320° arc - almost full
  wide(320),
  /// 355° arc - near-full circle
  full(355);

  final double degrees;
  const ArcStyle(this.degrees);

  double get radians => degrees * math.pi / 180;
}

/// Configuration for the Sun/Moon Arc Widget
class SunMoonArcConfig {
  /// Arc style (angle)
  final ArcStyle arcStyle;

  /// Use 24-hour time format
  final bool use24HourFormat;

  /// Show time labels at arc edges
  final bool showTimeLabels;

  /// Show sunrise/sunset markers
  final bool showSunMarkers;

  /// Show moonrise/moonset markers
  final bool showMoonMarkers;

  /// Show twilight segments (dawn/dusk colors)
  final bool showTwilightSegments;

  /// Show center indicator ("now" or "noon")
  final bool showCenterIndicator;

  /// Show secondary icons (dawn, dusk, golden hours, solar noon)
  final bool showSecondaryIcons;

  /// Show time in interior of arc (inside the curve)
  final bool showInteriorTime;

  /// Arc stroke width
  final double strokeWidth;

  /// Height of the widget
  final double height;

  /// Label color (for time labels)
  final Color? labelColor;

  const SunMoonArcConfig({
    this.arcStyle = ArcStyle.half,
    this.use24HourFormat = false,
    this.showTimeLabels = true,
    this.showSunMarkers = true,
    this.showMoonMarkers = true,
    this.showTwilightSegments = true,
    this.showCenterIndicator = true,
    this.showSecondaryIcons = true,
    this.showInteriorTime = false,
    this.strokeWidth = 2.0,
    this.height = 70.0,
    this.labelColor,
  });

  SunMoonArcConfig copyWith({
    ArcStyle? arcStyle,
    bool? use24HourFormat,
    bool? showTimeLabels,
    bool? showSunMarkers,
    bool? showMoonMarkers,
    bool? showTwilightSegments,
    bool? showCenterIndicator,
    bool? showSecondaryIcons,
    bool? showInteriorTime,
    double? strokeWidth,
    double? height,
    Color? labelColor,
  }) {
    return SunMoonArcConfig(
      arcStyle: arcStyle ?? this.arcStyle,
      use24HourFormat: use24HourFormat ?? this.use24HourFormat,
      showTimeLabels: showTimeLabels ?? this.showTimeLabels,
      showSunMarkers: showSunMarkers ?? this.showSunMarkers,
      showMoonMarkers: showMoonMarkers ?? this.showMoonMarkers,
      showTwilightSegments: showTwilightSegments ?? this.showTwilightSegments,
      showCenterIndicator: showCenterIndicator ?? this.showCenterIndicator,
      showSecondaryIcons: showSecondaryIcons ?? this.showSecondaryIcons,
      showInteriorTime: showInteriorTime ?? this.showInteriorTime,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      height: height ?? this.height,
      labelColor: labelColor ?? this.labelColor,
    );
  }
}

/// Sun/Moon Arc Widget showing day progression with configurable arc angle
class SunMoonArcWidget extends StatelessWidget {
  /// Sun/Moon times data
  final SunMoonTimes times;

  /// Configuration for the arc display
  final SunMoonArcConfig config;

  /// Selected day index (null = today, 0+ = future day)
  final int? selectedDayIndex;

  /// Optional center hour (0-23) - centers the arc on this hour
  /// The arc always shows 24 hours, this controls which hour is at the center
  /// If null, centers on current time (today) or noon (future days)
  final int? centerHour;

  /// Whether to use dark theme colors
  final bool? isDark;

  const SunMoonArcWidget({
    super.key,
    required this.times,
    this.config = const SunMoonArcConfig(),
    this.selectedDayIndex,
    this.centerHour,
    this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveIsDark = isDark ?? Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now().toUtc();

    // Calculate the center time for the arc
    DateTime arcCenter;
    bool showNoonIndicator = false;

    if (centerHour != null) {
      // Center on specific hour - convert location hour to UTC
      final dayOffset = selectedDayIndex ?? 0;
      final utcOffsetHours = (times.utcOffsetSeconds ?? 0) / 3600;

      // Get the date for the selected day (on-demand, no day limit)
      final targetDate = now.add(Duration(days: dayOffset));
      final day = times.getTimesForDate(targetDate);
      final baseDate = day?.sunrise ?? day?.sunset ?? targetDate;

      // Convert location hour to UTC: subtract the offset
      // e.g., 6 AM PST (offset=-8) -> 6 - (-8) = 14:00 UTC
      final utcHour = centerHour! - utcOffsetHours.round();
      arcCenter = DateTime.utc(baseDate.year, baseDate.month, baseDate.day, utcHour, 0);

      // Only show "now" if same hour AND same day (dayOffset == 0)
      final locationNow = times.toLocationTime(now);
      final isCurrentHourToday = (dayOffset == 0) && (centerHour == locationNow.hour);
      showNoonIndicator = !isCurrentHourToday;
    } else if (selectedDayIndex != null && selectedDayIndex! > 0) {
      // Future day selected - center on noon (on-demand, no day limit)
      final targetDate = now.add(Duration(days: selectedDayIndex!));
      final selectedDay = times.getTimesForDate(targetDate);
      arcCenter = selectedDay?.solarNoon ??
          DateTime.utc(now.year, now.month, now.day + selectedDayIndex!, 12, 0);
      showNoonIndicator = true;
    } else {
      // Today or no selection - center on current time
      arcCenter = now;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Reserve top padding for icons that extend above the arc
        final iconOverflow = constraints.maxHeight * 0.15;
        final arcHeight = constraints.maxHeight - iconOverflow;
        final effectiveConfig = config.copyWith(height: arcHeight);

        return Padding(
          padding: EdgeInsets.only(top: iconOverflow),
          child: ClipRect(
            clipBehavior: Clip.none,
            child: CustomPaint(
              size: Size(constraints.maxWidth, arcHeight),
              painter: _SunMoonArcPainter(
                times: times,
                now: arcCenter,
                isDark: effectiveIsDark,
                config: effectiveConfig,
                isSelectedDay: showNoonIndicator,
              ),
              child: _buildIconsOverlay(
                BoxConstraints(
                  maxWidth: constraints.maxWidth,
                  maxHeight: arcHeight,
                ),
                arcCenter,
                showNoonIndicator,
                effectiveIsDark,
                centerHour,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIconsOverlay(
    BoxConstraints constraints,
    DateTime now,
    bool isSelectedDay,
    bool isDark,
    int? centerHourValue,
  ) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final arcAngle = config.arcStyle.radians;

    // Scale factor for icons: 1.0 at default height (70), grows proportionally
    final scale = (height / 70.0).clamp(0.5, 3.0);

    // Arc spans 24 hours centered on 'now'
    final arcStart = now.subtract(const Duration(hours: 12));
    final arcEnd = now.add(const Duration(hours: 12));
    const arcDuration = 1440; // 24 hours in minutes

    final children = <Widget>[];

    // Helper to calculate position on arc
    (double x, double y)? getArcPosition(DateTime time, {double size = 16}) {
      final minutesFromStart = time.difference(arcStart).inMinutes;
      final progress = minutesFromStart / arcDuration;
      if (progress < 0 || progress > 1) return null;

      // Calculate position based on arc style
      final pos = _calculateArcPosition(
        progress: progress,
        width: width,
        height: height,
        arcAngle: arcAngle,
      );

      return (pos.dx - size / 2, pos.dy - size / 2);
    }

    // Get days that fall within arc range (typically 1-2 days)
    // Must iterate through LOCATION days, then convert back to UTC for getTimesForDate
    final arcDays = <DaySunTimes>[];
    final locationArcStart = times.toLocationTime(arcStart);
    final locationArcEnd = times.toLocationTime(arcEnd);
    final startLocationDay = DateTime.utc(locationArcStart.year, locationArcStart.month, locationArcStart.day);
    final endLocationDay = DateTime.utc(locationArcEnd.year, locationArcEnd.month, locationArcEnd.day);

    var currentLocationDay = startLocationDay;
    while (!currentLocationDay.isAfter(endLocationDay)) {
      // Convert noon on this location day back to UTC for getTimesForDate
      final noonUtc = times.toUtcFromLocation(
        DateTime.utc(currentLocationDay.year, currentLocationDay.month, currentLocationDay.day, 12),
      );
      final dayData = times.getTimesForDate(noonUtc);
      if (dayData != null) {
        arcDays.add(dayData);
      }
      currentLocationDay = currentLocationDay.add(const Duration(days: 1));
    }

    // Add sunrise/sunset/solar noon and moon markers for days within arc range
    for (final day in arcDays) {
      // Sunrise marker
      if (config.showSunMarkers &&
          day.sunrise != null &&
          day.sunrise!.isAfter(arcStart) &&
          day.sunrise!.isBefore(arcEnd)) {
        final sunrisePos = getArcPosition(day.sunrise!, size: 20 * scale);
        if (sunrisePos != null) {
          children.add(
            Positioned(
              left: sunrisePos.$1,
              top: sunrisePos.$2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_upward,
                    color: Colors.amber.shade600,
                    size: 10 * scale,
                  ),
                  Icon(Icons.wb_sunny, color: Colors.amber, size: 16 * scale),
                ],
              ),
            ),
          );
        }
      }

      // Sunset marker
      if (config.showSunMarkers &&
          day.sunset != null &&
          day.sunset!.isAfter(arcStart) &&
          day.sunset!.isBefore(arcEnd)) {
        final sunsetPos = getArcPosition(day.sunset!, size: 20 * scale);
        if (sunsetPos != null) {
          children.add(
            Positioned(
              left: sunsetPos.$1,
              top: sunsetPos.$2 - 10 * scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.wb_sunny, color: Colors.deepOrange, size: 16 * scale),
                  Icon(
                    Icons.arrow_downward,
                    color: Colors.deepOrange.shade600,
                    size: 10 * scale,
                  ),
                ],
              ),
            ),
          );
        }
      }

      // Solar noon marker (sun at max height)
      if (config.showSunMarkers &&
          day.solarNoon != null &&
          day.solarNoon!.isAfter(arcStart) &&
          day.solarNoon!.isBefore(arcEnd)) {
        final noonPos = getArcPosition(day.solarNoon!, size: 24 * scale);
        if (noonPos != null) {
          children.add(
            Positioned(
              left: noonPos.$1,
              top: noonPos.$2 - 8 * scale,
              child: Icon(Icons.wb_sunny, color: Colors.amber, size: 24 * scale),
            ),
          );
        }
      }

      // Moonrise marker
      if (config.showMoonMarkers &&
          day.moonrise != null &&
          day.moonrise!.isAfter(arcStart) &&
          day.moonrise!.isBefore(arcEnd)) {
        final moonrisePos = getArcPosition(day.moonrise!, size: 20 * scale);
        if (moonrisePos != null) {
          children.add(
            Positioned(
              left: moonrisePos.$1,
              top: moonrisePos.$2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_upward,
                    color: Colors.blueGrey.shade300,
                    size: 8 * scale,
                  ),
                  _buildMoonIcon(day.moonPhase, day.moonFraction, size: 14 * scale),
                ],
              ),
            ),
          );
        }
      }

      // Moonset marker
      if (config.showMoonMarkers &&
          day.moonset != null &&
          day.moonset!.isAfter(arcStart) &&
          day.moonset!.isBefore(arcEnd)) {
        final moonsetPos = getArcPosition(day.moonset!, size: 20 * scale);
        if (moonsetPos != null) {
          children.add(
            Positioned(
              left: moonsetPos.$1,
              top: moonsetPos.$2 - 8 * scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMoonIcon(day.moonPhase, day.moonFraction, size: 14 * scale),
                  Icon(
                    Icons.arrow_downward,
                    color: Colors.blueGrey.shade400,
                    size: 8 * scale,
                  ),
                ],
              ),
            ),
          );
        }
      }

      // Moon max height (lunar transit)
      if (config.showMoonMarkers && day.moonrise != null && day.moonset != null) {
        DateTime lunarTransit;
        if (day.moonset!.isAfter(day.moonrise!)) {
          final midpoint = day.moonrise!.add(
            Duration(minutes: day.moonset!.difference(day.moonrise!).inMinutes ~/ 2),
          );
          lunarTransit = midpoint;
        } else {
          lunarTransit = day.moonrise!.add(const Duration(hours: 6));
        }

        if (lunarTransit.isAfter(arcStart) && lunarTransit.isBefore(arcEnd)) {
          final transitPos = getArcPosition(lunarTransit, size: 20 * scale);
          if (transitPos != null) {
            children.add(
              Positioned(
                left: transitPos.$1,
                top: transitPos.$2 - 6 * scale,
                child: _buildMoonIcon(day.moonPhase, day.moonFraction, size: 20 * scale),
              ),
            );
          }
        }
      }

      // Secondary twilight icons (dawn, dusk, golden hours)
      if (config.showSecondaryIcons) {
        final twilightSize = 14 * scale;

        // Nautical Dawn
        if (day.nauticalDawn != null &&
            day.nauticalDawn!.isAfter(arcStart) &&
            day.nauticalDawn!.isBefore(arcEnd)) {
          final pos = getArcPosition(day.nauticalDawn!, size: twilightSize);
          if (pos != null) {
            children.add(
              Positioned(
                left: pos.$1 - 1 * scale,
                top: pos.$2 - 6 * scale,
                child: _TwilightIcon(
                  isDawn: true,
                  isNautical: true,
                  size: twilightSize,
                ),
              ),
            );
          }
        }

        // Civil Dawn
        if (day.dawn != null &&
            day.dawn!.isAfter(arcStart) &&
            day.dawn!.isBefore(arcEnd)) {
          final pos = getArcPosition(day.dawn!, size: twilightSize);
          if (pos != null) {
            children.add(
              Positioned(
                left: pos.$1 - 1 * scale,
                top: pos.$2 - 6 * scale,
                child: _TwilightIcon(
                  isDawn: true,
                  isNautical: false,
                  size: twilightSize,
                ),
              ),
            );
          }
        }

        // Golden Hour End (morning)
        if (day.goldenHourEnd != null &&
            day.goldenHourEnd!.isAfter(arcStart) &&
            day.goldenHourEnd!.isBefore(arcEnd)) {
          final pos = getArcPosition(day.goldenHourEnd!, size: twilightSize);
          if (pos != null) {
            children.add(
              Positioned(
                left: pos.$1,
                top: pos.$2 - 5 * scale,
                child: Icon(
                  Icons.wb_twilight,
                  color: Colors.orange.shade300,
                  size: 12 * scale,
                ),
              ),
            );
          }
        }

        // Golden Hour (evening start)
        if (day.goldenHour != null &&
            day.goldenHour!.isAfter(arcStart) &&
            day.goldenHour!.isBefore(arcEnd)) {
          final pos = getArcPosition(day.goldenHour!, size: twilightSize);
          if (pos != null) {
            children.add(
              Positioned(
                left: pos.$1,
                top: pos.$2 - 5 * scale,
                child: Icon(
                  Icons.wb_twilight,
                  color: Colors.orange.shade400,
                  size: 12 * scale,
                ),
              ),
            );
          }
        }

        // Civil Dusk
        if (day.dusk != null &&
            day.dusk!.isAfter(arcStart) &&
            day.dusk!.isBefore(arcEnd)) {
          final pos = getArcPosition(day.dusk!, size: twilightSize);
          if (pos != null) {
            children.add(
              Positioned(
                left: pos.$1 - 1 * scale,
                top: pos.$2 - 6 * scale,
                child: _TwilightIcon(
                  isDawn: false,
                  isNautical: false,
                  size: twilightSize,
                ),
              ),
            );
          }
        }

        // Nautical Dusk
        if (day.nauticalDusk != null &&
            day.nauticalDusk!.isAfter(arcStart) &&
            day.nauticalDusk!.isBefore(arcEnd)) {
          final pos = getArcPosition(day.nauticalDusk!, size: twilightSize);
          if (pos != null) {
            children.add(
              Positioned(
                left: pos.$1 - 1 * scale,
                top: pos.$2 - 6 * scale,
                child: _TwilightIcon(
                  isDawn: false,
                  isNautical: true,
                  size: twilightSize,
                ),
              ),
            );
          }
        }
      }
    }

    // Center indicator is now drawn as a red hash mark by the painter (no overlay needed)

    // Interior time display (current time inside the arc)
    if (config.showInteriorTime) {
      final centerX = width / 2;
      // Use location time instead of device time
      final locationTime = times.toLocationTime(now);
      final timeStr = DateTimeFormatter.formatTime(locationTime, use24Hour: config.use24HourFormat);
      final dateStr = DateTimeFormatter.formatDateShort(locationTime);
      // Proportional font size based on widget height (gentle scaling)
      final fontSize = (height * 0.15).clamp(12.0, 24.0);
      final dateFontSize = fontSize * 0.55;
      final textWidth = fontSize * 6; // Approximate width for time text
      // Position in lower half of arc to avoid stepping on markers
      final topPosition = height * 0.5 - fontSize / 2;

      children.add(
        Positioned(
          left: centerX - textWidth / 2,
          top: topPosition,
          child: SizedBox(
            width: textWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    color: config.labelColor ?? (isDark ? Colors.white70 : Colors.black54),
                  ),
                ),
                Text(
                  dateStr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: dateFontSize,
                    color: config.labelColor?.withValues(alpha: 0.7) ??
                        (isDark ? Colors.white54 : Colors.black45),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Stack(clipBehavior: Clip.none, children: children);
  }


  /// Calculate position on the arc for a given progress (0-1)
  /// Uses true circular arc geometry, centered horizontally and vertically
  Offset _calculateArcPosition({
    required double progress,
    required double width,
    required double height,
    required double arcAngle,
  }) {
    final centerX = width / 2;
    final centerY = height / 2;

    // For 180° (half), use parabolic approximation to match forecast widget
    // Use BOTH enum check AND angle check for robustness
    final isHalfArc = config.arcStyle == ArcStyle.half && arcAngle > 3.0; // ~172°
    if (isHalfArc) {
      final arcHeight = (height - 10) * 0.8;
      final baseY = (height + arcHeight) / 2;
      final x = width * (0.05 + progress * 0.9);
      final normalizedX = (progress - 0.5) * 2;
      final y = baseY - (1 - normalizedX * normalizedX) * arcHeight;
      return Offset(x, y);
    }

    // For all other arc styles (90°, 270°, 320°, 355°), use true circular arc geometry
    final maxDim = math.min(width, height) * 0.85;
    final radius = maxDim / 2;

    // Arc angles: progress 0 = left side, progress 1 = right side
    // Top of arc is at angle = π/2 (90°, pointing up from center)
    final startAngle = math.pi / 2 + arcAngle / 2;
    final currentAngle = startAngle - progress * arcAngle;

    final x = centerX + radius * math.cos(currentAngle);
    final y = centerY - radius * math.sin(currentAngle);

    return Offset(x, y);
  }

  Widget _buildMoonIcon(double? phase, double? fraction, {double size = 16}) {
    return CustomPaint(
      size: Size(size, size),
      painter: _MoonPhasePainter(
        phase: phase ?? 0.5,
        fraction: fraction ?? 0.5,
        isSouthernHemisphere: times.isSouthernHemisphere,
      ),
    );
  }
}

/// Custom painter for the sun/moon arc
class _SunMoonArcPainter extends CustomPainter {
  final SunMoonTimes times;
  final DateTime now;
  final bool isDark;
  final SunMoonArcConfig config;
  final bool isSelectedDay;

  _SunMoonArcPainter({
    required this.times,
    required this.now,
    required this.isDark,
    required this.config,
    this.isSelectedDay = false,
  });

  String _formatTime(DateTime time, {bool includeMinutes = true}) {
    return DateTimeFormatter.formatTime(
      time,
      use24Hour: config.use24HourFormat,
      includeMinutes: includeMinutes,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final arcStart = now.subtract(const Duration(hours: 12));
    final arcEnd = now.add(const Duration(hours: 12));
    const arcDuration = 1440.0;
    final arcAngle = config.arcStyle.radians;

    // Scale factor for painter elements
    final scale = (size.height / 70.0).clamp(0.5, 3.0);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = config.strokeWidth * scale;

    if (config.showTwilightSegments) {
      final segments = <_ArcSegment>[];

      void addSegment(DateTime? start, DateTime? end, Color color) {
        if (start == null || end == null) return;
        if (end.isBefore(arcStart) || start.isAfter(arcEnd)) return;
        segments.add(_ArcSegment(start, end, color));
      }

      // Get days that fall within arc range (typically 1-2 days)
      // Must iterate through LOCATION days, then convert back to UTC for getTimesForDate
      final arcDays = <DaySunTimes>[];
      final locationArcStart = times.toLocationTime(arcStart);
      final locationArcEnd = times.toLocationTime(arcEnd);
      final startLocationDay = DateTime.utc(locationArcStart.year, locationArcStart.month, locationArcStart.day);
      final endLocationDay = DateTime.utc(locationArcEnd.year, locationArcEnd.month, locationArcEnd.day);

      var currentLocationDay = startLocationDay;
      while (!currentLocationDay.isAfter(endLocationDay)) {
        // Convert noon on this location day back to UTC for getTimesForDate
        final noonUtc = times.toUtcFromLocation(
          DateTime.utc(currentLocationDay.year, currentLocationDay.month, currentLocationDay.day, 12),
        );
        final dayData = times.getTimesForDate(noonUtc);
        if (dayData != null) {
          arcDays.add(dayData);
        }
        currentLocationDay = currentLocationDay.add(const Duration(days: 1));
      }

      // Add segments for each day in arc range
      for (final day in arcDays) {
        // Night before dawn
        if (day.nauticalDawn != null) {
          final nightStart = day.nauticalDawn!.subtract(const Duration(hours: 6));
          addSegment(nightStart, day.nauticalDawn, Colors.indigo.shade900.withValues(alpha: 0.5));
        }
        addSegment(day.nauticalDawn, day.dawn, Colors.indigo.shade700);
        addSegment(day.dawn, day.sunrise, Colors.indigo.shade400);
        addSegment(day.sunrise, day.goldenHourEnd, Colors.orange.shade300);
        addSegment(day.goldenHourEnd, day.solarNoon, Colors.amber.shade200);
        addSegment(day.solarNoon, day.goldenHour, Colors.amber.shade200);
        addSegment(day.goldenHour, day.sunset, Colors.orange.shade400);
        addSegment(day.sunset, day.dusk, Colors.deepOrange.shade400);
        addSegment(day.dusk, day.nauticalDusk, Colors.indigo.shade400);
        if (day.nauticalDusk != null) {
          final nightEnd = day.nauticalDusk!.add(const Duration(hours: 6));
          addSegment(day.nauticalDusk, nightEnd, Colors.indigo.shade900.withValues(alpha: 0.5));
        }
      }

      // Calculate chord center (bottom baseline) for wedge gradients
      final leftPoint = _getArcPosition(0.0, size, arcAngle);
      final rightPoint = _getArcPosition(1.0, size, arcAngle);
      final chordCenter = Offset(
        (leftPoint.dx + rightPoint.dx) / 2,
        (leftPoint.dy + rightPoint.dy) / 2,
      );

      // Calculate gradient radius (distance from chord center to arc top)
      final arcTop = _getArcPosition(0.5, size, arcAngle);
      final gradientRadius = (chordCenter - arcTop).distance;

      // Draw gradient wedges BEFORE arc strokes (so arc is on top)
      for (final segment in segments) {
        final startProgress = segment.start.difference(arcStart).inMinutes / arcDuration;
        final endProgress = segment.end.difference(arcStart).inMinutes / arcDuration;

        if (startProgress >= 1 || endProgress <= 0) continue;

        final clampedStart = startProgress.clamp(0.0, 1.0);
        final clampedEnd = endProgress.clamp(0.0, 1.0);

        // Build wedge path from chord center to arc segment
        final wedgePath = Path();
        wedgePath.moveTo(chordCenter.dx, chordCenter.dy);

        const steps = 20;
        for (int i = 0; i <= steps; i++) {
          final t = clampedStart + (clampedEnd - clampedStart) * (i / steps);
          final pos = _getArcPosition(t, size, arcAngle);
          wedgePath.lineTo(pos.dx, pos.dy);
        }
        wedgePath.close();

        // Gradient paint: transparent at center → segment color at arc
        final wedgePaint = Paint()
          ..style = PaintingStyle.fill
          ..shader = ui.Gradient.radial(
            chordCenter,
            gradientRadius,
            [Colors.transparent, segment.color.withValues(alpha: 0.25)],
            [0.0, 1.0],
          );

        canvas.drawPath(wedgePath, wedgePaint);
      }

      // Draw arc segments
      for (final segment in segments) {
        final startProgress = segment.start.difference(arcStart).inMinutes / arcDuration;
        final endProgress = segment.end.difference(arcStart).inMinutes / arcDuration;

        if (startProgress >= 1 || endProgress <= 0) continue;

        final clampedStart = startProgress.clamp(0.0, 1.0);
        final clampedEnd = endProgress.clamp(0.0, 1.0);

        paint.color = segment.color;
        _drawArcSegment(canvas, size, clampedStart, clampedEnd, paint, arcAngle);
      }
    } else {
      // Simple arc without twilight segments
      paint.color = isDark ? Colors.white24 : Colors.black26;
      _drawArcSegment(canvas, size, 0.0, 1.0, paint, arcAngle);
    }

    // Draw baseline (chord) connecting arc endpoints
    final leftPoint = _getArcPosition(0.0, size, arcAngle);
    final rightPoint = _getArcPosition(1.0, size, arcAngle);
    canvas.drawLine(
      leftPoint,
      rightPoint,
      Paint()
        ..color = isDark ? Colors.white24 : Colors.black12
        ..strokeWidth = 1 * scale,
    );

    // Draw time labels
    if (config.showTimeLabels) {
      _drawTimeLabels(canvas, size, arcStart, arcAngle);
    }

    // Draw red hash mark at center (progress 0.5 = "now")
    if (config.showCenterIndicator && !isSelectedDay) {
      final arcPos = _getArcPosition(0.5, size, arcAngle);
      final hashLength = 8 * scale;
      final hashPaint = Paint()
        ..color = Colors.red
        ..strokeWidth = 2 * scale
        ..strokeCap = StrokeCap.round;
      // Draw perpendicular to arc at center point
      // For half arc, hash is vertical; for others, radial from center
      if (config.arcStyle == ArcStyle.half) {
        canvas.drawLine(
          Offset(arcPos.dx, arcPos.dy - hashLength),
          Offset(arcPos.dx, arcPos.dy + hashLength),
          hashPaint,
        );
      } else {
        // Radial hash: from center of circle through arc point
        final cx = size.width / 2;
        final cy = size.height / 2;
        final dx = arcPos.dx - cx;
        final dy = arcPos.dy - cy;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist > 0) {
          final nx = dx / dist;
          final ny = dy / dist;
          canvas.drawLine(
            Offset(arcPos.dx - nx * hashLength, arcPos.dy - ny * hashLength),
            Offset(arcPos.dx + nx * hashLength, arcPos.dy + ny * hashLength),
            hashPaint,
          );
        }
      }
    }
  }

  void _drawArcSegment(
    Canvas canvas,
    Size size,
    double startProgress,
    double endProgress,
    Paint paint,
    double arcAngle,
  ) {
    final path = Path();
    const steps = 30;

    for (int i = 0; i <= steps; i++) {
      final t = startProgress + (endProgress - startProgress) * (i / steps);
      final pos = _getArcPosition(t, size, arcAngle);

      if (i == 0) {
        path.moveTo(pos.dx, pos.dy);
      } else {
        path.lineTo(pos.dx, pos.dy);
      }
    }

    canvas.drawPath(path, paint);
  }

  Offset _getArcPosition(double progress, Size size, double arcAngle) {
    final width = size.width;
    final height = size.height;
    final centerX = width / 2;
    final centerY = height / 2;

    // For 180° (half), use parabolic approximation to match forecast widget
    // Use BOTH enum check AND angle check for robustness
    final isHalfArc = config.arcStyle == ArcStyle.half && arcAngle > 3.0; // ~172°
    if (isHalfArc) {
      final arcHeight = (height - 10) * 0.8;
      final baseY = (height + arcHeight) / 2;
      final x = width * (0.05 + progress * 0.9);
      final normalizedX = (progress - 0.5) * 2;
      final y = baseY - (1 - normalizedX * normalizedX) * arcHeight;
      return Offset(x, y);
    }

    // For all other arc styles (90°, 270°, 320°, 355°), use true circular arc geometry
    final maxDim = math.min(width, height) * 0.85;
    final radius = maxDim / 2;

    // Arc angles: progress 0 = left side, progress 1 = right side
    // Top of arc is at angle = π/2 (90°, pointing up from center)
    final startAngle = math.pi / 2 + arcAngle / 2;
    final currentAngle = startAngle - progress * arcAngle;

    final x = centerX + radius * math.cos(currentAngle);
    final y = centerY - radius * math.sin(currentAngle);

    return Offset(x, y);
  }

  void _drawTimeLabels(Canvas canvas, Size size, DateTime arcStart, double arcAngle) {
    // Use configured label color or default based on theme
    final neutralColor = config.labelColor ?? (isDark ? Colors.white54 : Colors.black45);
    final scale = (size.height / 70.0).clamp(0.5, 3.0);
    final fontScale = math.sqrt(scale).clamp(0.7, 2.0);
    final labelFontSize = 8 * fontScale;

    // Get endpoint positions for label placement
    final leftPoint = _getArcPosition(0.0, size, arcAngle);
    final rightPoint = _getArcPosition(1.0, size, arcAngle);
    final chordY = math.max(leftPoint.dy, rightPoint.dy);

    void drawLabel(double progress, String text, Color color, {bool isEndpoint = false}) {
      if (progress < 0 || progress > 1) return;
      final pos = _getArcPosition(progress, size, arcAngle);

      // Position label:
      // - Endpoint labels (start/end times): below the chord
      // - Other labels (sunrise/sunset): below their arc position
      double labelY;
      if (isEndpoint) {
        labelY = chordY + 2 * scale;
      } else {
        labelY = pos.dy + 12 * scale;
      }

      final textSpan = TextSpan(
        text: text,
        style: TextStyle(fontSize: labelFontSize, color: color, fontWeight: FontWeight.w500),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(pos.dx - textPainter.width / 2, labelY));
    }

    // Edge time labels (at chord endpoints)
    final startTime = times.toLocationTime(arcStart);
    final endTime = times.toLocationTime(arcStart.add(const Duration(hours: 24)));
    drawLabel(0.0, _formatTime(startTime, includeMinutes: false), neutralColor, isEndpoint: true);
    drawLabel(1.0, _formatTime(endTime, includeMinutes: false), neutralColor, isEndpoint: true);

    // Sunrise/sunset time labels (on the arc)
    if (times.sunrise != null) {
      final progress = times.sunrise!.difference(arcStart).inMinutes / 1440.0;
      if (progress >= 0 && progress <= 1) {
        final local = times.toLocationTime(times.sunrise!);
        drawLabel(progress, _formatTime(local), Colors.amber, isEndpoint: false);
      }
    }

    if (times.sunset != null) {
      final progress = times.sunset!.difference(arcStart).inMinutes / 1440.0;
      if (progress >= 0 && progress <= 1) {
        final local = times.toLocationTime(times.sunset!);
        drawLabel(progress, _formatTime(local), Colors.deepOrange, isEndpoint: false);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SunMoonArcPainter oldDelegate) {
    return oldDelegate.now.minute != now.minute ||
        oldDelegate.isDark != isDark ||
        oldDelegate.config.arcStyle != config.arcStyle ||
        oldDelegate.config.use24HourFormat != config.use24HourFormat ||
        oldDelegate.config.showTimeLabels != config.showTimeLabels ||
        oldDelegate.config.showTwilightSegments != config.showTwilightSegments ||
        oldDelegate.config.strokeWidth != config.strokeWidth ||
        oldDelegate.config.labelColor != config.labelColor;
  }
}

/// Custom painter for moon phase
class _MoonPhasePainter extends CustomPainter {
  final double phase;
  final double fraction;
  final bool isSouthernHemisphere;

  _MoonPhasePainter({
    required this.phase,
    required this.fraction,
    this.isSouthernHemisphere = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1;

    // Dark side
    final darkPaint = Paint()
      ..color = Colors.grey.shade800
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, darkPaint);

    // Illuminated side
    final lightPaint = Paint()
      ..color = Colors.grey.shade200
      ..style = PaintingStyle.fill;

    if (fraction < 0.01) return;
    if (fraction > 0.99) {
      canvas.drawCircle(center, radius, lightPaint);
      return;
    }

    bool isWaxing = phase < 0.5;
    if (isSouthernHemisphere) isWaxing = !isWaxing;

    final termWidth = radius * (2.0 * fraction - 1.0);
    final isGibbous = fraction > 0.5;

    final path = Path();

    if (isWaxing) {
      path.moveTo(center.dx, center.dy - radius);
      path.arcToPoint(
        Offset(center.dx, center.dy + radius),
        radius: Radius.circular(radius),
        clockwise: true,
      );
      path.arcToPoint(
        Offset(center.dx, center.dy - radius),
        radius: Radius.elliptical(termWidth.abs().clamp(0.1, radius), radius),
        clockwise: isGibbous,
      );
    } else {
      path.moveTo(center.dx, center.dy - radius);
      path.arcToPoint(
        Offset(center.dx, center.dy + radius),
        radius: Radius.circular(radius),
        clockwise: false,
      );
      path.arcToPoint(
        Offset(center.dx, center.dy - radius),
        radius: Radius.elliptical(termWidth.abs().clamp(0.1, radius), radius),
        clockwise: !isGibbous,
      );
    }

    path.close();
    canvas.drawPath(path, lightPaint);

    // Outline
    final outlinePaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawCircle(center, radius, outlinePaint);
  }

  @override
  bool shouldRepaint(covariant _MoonPhasePainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.fraction != fraction ||
        oldDelegate.isSouthernHemisphere != isSouthernHemisphere;
  }
}

class _ArcSegment {
  final DateTime start;
  final DateTime end;
  final Color color;

  _ArcSegment(this.start, this.end, this.color);
}

/// Twilight icon widget - half sun with horizon line
/// Matches the style used in ForecastSpinner
class _TwilightIcon extends StatelessWidget {
  final bool isDawn;
  final bool isNautical;
  final double size;

  const _TwilightIcon({
    required this.isDawn,
    required this.isNautical,
    this.size = 14,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _TwilightIconPainter(
        isDawn: isDawn,
        isNautical: isNautical,
      ),
    );
  }
}

class _TwilightIconPainter extends CustomPainter {
  final bool isDawn;
  final bool isNautical;

  _TwilightIconPainter({
    required this.isDawn,
    required this.isNautical,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final sunRadius = size.width / 4;

    // Color based on type
    final color = isNautical
        ? (isDawn ? Colors.indigo.shade300 : Colors.indigo.shade400)
        : (isDawn ? Colors.purple.shade300 : Colors.deepPurple.shade300);

    // Draw horizon line
    final horizonPaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(center.dx - sunRadius - 2, center.dy),
      Offset(center.dx + sunRadius + 2, center.dy),
      horizonPaint,
    );

    // Draw half sun (above horizon for dawn, below for dusk)
    final sunPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final rect = Rect.fromCircle(center: center, radius: sunRadius);
    if (isDawn) {
      // Dawn: sun rising (half circle above horizon)
      canvas.drawArc(rect, math.pi, math.pi, true, sunPaint);
    } else {
      // Dusk: sun setting (half circle below horizon)
      canvas.drawArc(rect, 0, math.pi, true, sunPaint);
    }

    // Draw tiny stars for nautical twilight
    if (isNautical) {
      final starPaint = Paint()
        ..color = Colors.white70
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(center.dx - sunRadius - 1, center.dy - sunRadius),
        1.5,
        starPaint,
      );
      canvas.drawCircle(
        Offset(center.dx + sunRadius + 1, center.dy - sunRadius + 1),
        1.0,
        starPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TwilightIconPainter oldDelegate) {
    return oldDelegate.isDawn != isDawn || oldDelegate.isNautical != isNautical;
  }
}
