import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'weatherflow_forecast.dart'; // Reuse HourlyForecast, SunMoonTimes

/// Weather effect types for animation
enum WeatherEffectType { none, rain, snow, wind, hail, thunder }

/// Circular forecast spinner widget
/// Displays a spinnable dial showing 24 hours of forecast data
/// Center shows detailed conditions for selected time
class ForecastSpinner extends StatefulWidget {
  /// Hourly forecasts (up to 72 hours)
  final List<HourlyForecast> hourlyForecasts;

  /// Sun/Moon times for color calculations
  final SunMoonTimes? sunMoonTimes;

  /// Unit labels
  final String tempUnit;
  final String windUnit;
  final String pressureUnit;

  /// Primary accent color
  final Color primaryColor;

  /// Provider name to display
  final String? providerName;

  /// Callback when selected hour changes
  final void Function(int hourOffset)? onHourChanged;

  /// Whether to show animated weather effects (rain, snow, etc.)
  final bool showWeatherAnimation;

  const ForecastSpinner({
    super.key,
    required this.hourlyForecasts,
    this.sunMoonTimes,
    this.tempUnit = '°F',
    this.windUnit = 'kn',
    this.pressureUnit = 'hPa',
    this.primaryColor = Colors.blue,
    this.providerName,
    this.onHourChanged,
    this.showWeatherAnimation = true,
  });

  @override
  State<ForecastSpinner> createState() => _ForecastSpinnerState();
}

class _ForecastSpinnerState extends State<ForecastSpinner>
    with SingleTickerProviderStateMixin {
  // Rotation state - use ValueNotifier to avoid setState on every pan update
  final ValueNotifier<double> _rotationNotifier = ValueNotifier<double>(0.0);
  double _previousAngle = 0.0; // For tracking delta

  // Track last hour offset to minimize center content rebuilds
  int _lastSelectedHourOffset = 0;

  // Animation controller for momentum and snap
  late AnimationController _controller;
  Animation<double>? _snapAnimation;

  // Cached segment colors (calculated once when sunMoonTimes changes)
  List<Color>? _cachedSegmentColors;

  // Cached DateTime.now() for consistent time across a frame
  DateTime _cachedNow = DateTime.now();

  // Convenience getter for rotation angle
  double get _rotationAngle => _rotationNotifier.value;
  set _rotationAngle(double value) => _rotationNotifier.value = value;

  // Selected time offset in minutes (derived from rotation)
  int get _selectedMinuteOffset {
    // Each 10 minutes = 2.5 degrees = pi/72 radians
    // Negative rotation (counter-clockwise) = forward in time
    final minutes = (-_rotationAngle / (math.pi / 72) * 10).round();
    final maxMinutes = (widget.hourlyForecasts.length - 1) * 60;
    return minutes.clamp(0, maxMinutes);
  }

  // Selected hour index for forecast lookup
  int get _selectedHourOffset {
    if (widget.hourlyForecasts.isEmpty) return 0;
    return (_selectedMinuteOffset ~/ 60).clamp(0, widget.hourlyForecasts.length - 1);
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    // Initialize cached segment colors
    _updateSegmentColors();
    // Defer listener registration to avoid issues during placement preview
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.addListener(_onAnimationTick);
      }
    });
  }

  @override
  void didUpdateWidget(ForecastSpinner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recalculate segment colors if sun/moon times changed
    if (widget.sunMoonTimes != oldWidget.sunMoonTimes) {
      _updateSegmentColors();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onAnimationTick);
    _controller.dispose();
    _rotationNotifier.dispose();
    super.dispose();
  }

  /// Pre-compute all segment colors based on sun/moon times
  /// This is called once when sunMoonTimes changes, not on every paint
  void _updateSegmentColors() {
    _cachedNow = DateTime.now();

    // Compute colors dynamically based on forecast length (1-10 days)
    // Each segment = 1 hour, clamp to reasonable range
    final segmentCount = widget.hourlyForecasts.length.clamp(24, 240);
    const minutesPerSegment = 60;

    _cachedSegmentColors = List<Color>.generate(segmentCount, (i) {
      final segmentTime = _cachedNow.add(Duration(minutes: i * minutesPerSegment));
      return _computeSegmentColor(segmentTime, widget.sunMoonTimes);
    });
  }

  /// Compute the color for a segment based on time of day and sun data
  Color _computeSegmentColor(DateTime time, SunMoonTimes? times) {
    if (times != null) {
      final todayStart = DateTime(_cachedNow.year, _cachedNow.month, _cachedNow.day);
      final dayIndex = time.difference(todayStart).inDays;
      final dayTimes = times.getDay(dayIndex);

      if (dayTimes != null) {
        final sunrise = dayTimes.sunrise;
        final sunset = dayTimes.sunset;
        final dawn = dayTimes.dawn;
        final dusk = dayTimes.dusk;
        final goldenHour = dayTimes.goldenHour;
        final goldenHourEnd = dayTimes.goldenHourEnd;
        final nauticalDawn = dayTimes.nauticalDawn;
        final nauticalDusk = dayTimes.nauticalDusk;

        if (sunrise != null && sunset != null) {
          final timeMinutes = time.hour * 60 + time.minute;
          final sunriseLocal = sunrise.toLocal();
          final sunsetLocal = sunset.toLocal();
          final sunriseMin = sunriseLocal.hour * 60 + sunriseLocal.minute;
          final sunsetMin = sunsetLocal.hour * 60 + sunsetLocal.minute;
          final dawnLocal = dawn?.toLocal();
          final duskLocal = dusk?.toLocal();
          final nauticalDawnLocal = nauticalDawn?.toLocal();
          final nauticalDuskLocal = nauticalDusk?.toLocal();
          final goldenHourLocal = goldenHour?.toLocal();
          final goldenHourEndLocal = goldenHourEnd?.toLocal();
          final dawnMin = dawnLocal != null ? dawnLocal.hour * 60 + dawnLocal.minute : sunriseMin - 30;
          final duskMin = duskLocal != null ? duskLocal.hour * 60 + duskLocal.minute : sunsetMin + 30;
          final nauticalDawnMin = nauticalDawnLocal != null ? nauticalDawnLocal.hour * 60 + nauticalDawnLocal.minute : dawnMin - 30;
          final nauticalDuskMin = nauticalDuskLocal != null ? nauticalDuskLocal.hour * 60 + nauticalDuskLocal.minute : duskMin + 30;
          final goldenHourEndMin = goldenHourEndLocal != null ? goldenHourEndLocal.hour * 60 + goldenHourEndLocal.minute : sunriseMin + 60;
          final goldenHourMin = goldenHourLocal != null ? goldenHourLocal.hour * 60 + goldenHourLocal.minute : sunsetMin - 60;

          if (timeMinutes < nauticalDawnMin) return Colors.indigo.shade900;
          if (timeMinutes >= nauticalDawnMin && timeMinutes < dawnMin) return Colors.indigo.shade700;
          if (timeMinutes >= dawnMin && timeMinutes < sunriseMin) return Colors.indigo.shade400;
          if (timeMinutes >= sunriseMin && timeMinutes < goldenHourEndMin) return Colors.orange.shade300;
          if (timeMinutes >= goldenHourEndMin && timeMinutes < goldenHourMin) return Colors.amber.shade200;
          if (timeMinutes >= goldenHourMin && timeMinutes < sunsetMin) return Colors.orange.shade300;
          if (timeMinutes >= sunsetMin && timeMinutes < duskMin) return Colors.deepOrange.shade400;
          if (timeMinutes >= duskMin && timeMinutes < nauticalDuskMin) return Colors.indigo.shade700;
          if (timeMinutes >= nauticalDuskMin) return Colors.indigo.shade900;
        }
      }
    }

    // Fallback: use simplified hour-based colors
    final hour = time.hour;
    if (hour >= 5 && hour < 6) return Colors.indigo.shade700;
    if (hour >= 6 && hour < 7) return Colors.indigo.shade400;
    if (hour >= 7 && hour < 8) return Colors.orange.shade300;
    if (hour >= 8 && hour < 16) return Colors.amber.shade200;
    if (hour >= 16 && hour < 17) return Colors.orange.shade400;
    if (hour >= 17 && hour < 18) return Colors.deepOrange.shade400;
    if (hour >= 18 && hour < 19) return Colors.indigo.shade700;
    return Colors.indigo.shade900;
  }

  void _onAnimationTick() {
    if (!mounted) return;
    // Use snap animation value if available, otherwise controller value (for momentum)
    final newAngle = _snapAnimation?.value ?? _controller.value;
    // Guard against infinity/NaN
    if (newAngle.isFinite) {
      _rotationAngle = newAngle; // Updates ValueNotifier, triggers repaint
      // Only rebuild center content when hour offset changes
      _checkHourOffsetChanged();
    }
  }

  /// Check if hour offset changed and rebuild center content if needed
  void _checkHourOffsetChanged() {
    final newOffset = _selectedHourOffset;
    if (newOffset != _lastSelectedHourOffset) {
      _lastSelectedHourOffset = newOffset;
      if (mounted) setState(() {}); // Rebuild center content only
    }
  }

  void _onPanStart(DragStartDetails details) {
    _controller.stop();
    _snapAnimation = null; // Clear any active snap animation
    _previousAngle = _getAngleFromPosition(details.localPosition);
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    final currentAngle = _getAngleFromPosition(details.localPosition);
    var delta = currentAngle - _previousAngle;

    // Handle wrap-around at +/- pi
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;

    // Update rotation directly via ValueNotifier (no setState!)
    var newRotation = _rotationAngle + delta;
    _previousAngle = currentAngle;

    // Clamp rotation to valid forecast range
    if (widget.hourlyForecasts.isNotEmpty) {
      final maxHours = widget.hourlyForecasts.length - 1;
      final maxRotation = 0.0; // Can't go before "now"
      final minRotation = -maxHours * (math.pi / 12);
      newRotation = newRotation.clamp(minRotation, maxRotation);
    }

    _rotationAngle = newRotation; // Updates ValueNotifier
    // Only rebuild center content when hour changes
    _checkHourOffsetChanged();
  }

  void _onPanEnd(DragEndDetails details) {
    // Guard against non-finite rotation angle
    if (!_rotationAngle.isFinite) {
      _rotationAngle = 0.0;
    }

    // Snap directly to nearest hour (no momentum)
    _snapToNearestHour();
  }

  void _snapToNearestHour() {
    if (widget.hourlyForecasts.isEmpty) return;

    // Guard against non-finite rotation
    if (!_rotationAngle.isFinite) {
      _rotationAngle = 0.0;
      return;
    }

    // Snap to nearest 10 minutes (6 steps per hour)
    final tenMinuteStep = math.pi / 72; // 2.5 degrees per 10 minutes
    final maxHours = widget.hourlyForecasts.length - 1;
    final maxAngle = maxHours * math.pi / 12;
    final targetAngle = ((_rotationAngle / tenMinuteStep).round() * tenMinuteStep)
        .clamp(-maxAngle, 0.0);

    _snapAnimation = Tween<double>(
      begin: _rotationAngle,
      end: targetAngle,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.duration = const Duration(milliseconds: 200);
    _controller.forward(from: 0).then((_) {
      if (!mounted) return;
      _controller.stop();
      setState(() {
        _rotationAngle = targetAngle;
        _snapAnimation = null;
      });
      widget.onHourChanged?.call(_selectedHourOffset);
    });
  }

  // Store current size for gesture calculations
  Size _currentSize = const Size(300, 300);

  double _getAngleFromPosition(Offset position) {
    // Calculate from widget center using actual size
    final centerX = _currentSize.width / 2;
    final centerY = _currentSize.height / 2;
    return math.atan2(position.dy - centerY, position.dx - centerX);
  }

  void _returnToNow() {
    _controller.stop();
    final targetAngle = 0.0;

    _controller.animateTo(
      targetAngle,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        _currentSize = Size(size, size);

        // Scale factor for UI elements based on reference size of 300px
        final scale = (size / 300).clamp(0.5, 1.5);

        // RepaintBoundary isolates repaints to just this widget tree
        return RepaintBoundary(
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
            alignment: Alignment.center,
            children: [
              // Gesture detector for the entire area (rim spinning)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: _onPanStart,
                  onPanUpdate: (details) => _onPanUpdate(details, Size(size, size)),
                  onPanEnd: _onPanEnd,
                  // Use ValueListenableBuilder to only repaint the rim on rotation
                  // without rebuilding the entire widget tree
                  child: ValueListenableBuilder<double>(
                    valueListenable: _rotationNotifier,
                    builder: (context, rotationAngle, child) {
                      return CustomPaint(
                        size: Size(size, size),
                        painter: _ForecastRimPainter(
                          times: widget.sunMoonTimes,
                          rotationAngle: rotationAngle,
                          isDark: isDark,
                          selectedHourOffset: _selectedHourOffset,
                          cachedSegmentColors: _cachedSegmentColors,
                          cachedNow: _cachedNow,
                          maxForecastHours: widget.hourlyForecasts.length,
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Selection indicator at top - prominent pointer close to rim
              Positioned(
                top: 0,
                child: IgnorePointer(
                  child: Container(
                    width: 20 * scale,
                    height: 30 * scale,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(10 * scale),
                        bottomRight: Radius.circular(10 * scale),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 4 * scale,
                          offset: Offset(0, 2 * scale),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.arrow_drop_down,
                      color: Colors.white,
                      size: 20 * scale,
                    ),
                  ),
                ),
              ),

              // Center content (doesn't block rim gestures)
              IgnorePointer(
                ignoring: true,
                child: _buildCenterContent(size, isDark),
              ),

              // Return to Now button (separate, on top, interactive)
              if (_selectedHourOffset > 0)
                Positioned(
                  bottom: size * 0.22,
                  child: TextButton.icon(
                    onPressed: _returnToNow,
                    icon: Icon(Icons.gps_fixed, size: 14 * scale),
                    label: Text('Now', style: TextStyle(fontSize: 11 * scale)),
                    style: TextButton.styleFrom(
                      foregroundColor: widget.primaryColor,
                      backgroundColor: isDark ? Colors.black54 : Colors.white70,
                      padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 4 * scale),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),

              // Provider name in top left
              if (widget.providerName != null && widget.providerName!.isNotEmpty)
                Positioned(
                  top: 4 * scale,
                  left: 4 * scale,
                  child: IgnorePointer(
                    child: Text(
                      widget.providerName!,
                      style: TextStyle(
                        fontSize: 10 * scale,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          ),
        );
      },
    );
  }

  Widget _buildCenterContent(double size, bool isDark) {
    // Calculate centerSize to match the inner edge of the rim
    final scale = (size / 300).clamp(0.5, 1.5);
    final outerMargin = 27.0 * scale;
    final outerRadius = size / 2 - outerMargin;
    final innerRadius = outerRadius * 0.72;
    final centerSize = innerRadius * 2; // Diameter matches rim's inner edge
    final forecast = _selectedHourOffset < widget.hourlyForecasts.length
        ? widget.hourlyForecasts[_selectedHourOffset]
        : null;

    // Get background color based on time of day (use precise minute offset)
    final selectedTime = DateTime.now().add(Duration(minutes: _selectedMinuteOffset));
    final bgColor = _getTimeOfDayColor(selectedTime);

    return Container(
      width: centerSize,
      height: centerSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            bgColor.withValues(alpha: 0.6),
            bgColor.withValues(alpha: 0.3),
          ],
        ),
        border: Border.all(
          color: isDark ? Colors.white24 : Colors.black12,
          width: 2,
        ),
      ),
      child: forecast == null
          ? const Center(child: Text('No data'))
          : _buildForecastContent(forecast, selectedTime, isDark, centerSize),
    );
  }

  Widget _buildForecastContent(HourlyForecast forecast, DateTime time, bool isDark, double centerSize) {
    // Scale factor based on reference size of 200px for center content
    final scale = (centerSize / 200).clamp(0.6, 1.2);
    final weatherEffect = _getWeatherEffect(forecast);

    return Stack(
      alignment: Alignment.center,
      children: [
        // Weather icon as background - fills the middle area
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.all(centerSize * 0.15),
            child: Opacity(
              opacity: 0.40,
              child: SvgPicture.asset(
                forecast.weatherIconAsset,
                fit: BoxFit.contain,
                placeholderBuilder: (context) => Icon(
                  forecast.fallbackIcon,
                  size: centerSize * 0.5,
                  color: _getWeatherIconColor(forecast.icon),
                ),
              ),
            ),
          ),
        ),
        // Animated weather effect overlay
        if (widget.showWeatherAnimation && weatherEffect != WeatherEffectType.none)
          Positioned.fill(
            child: _WeatherEffectOverlay(
              effectType: weatherEffect,
              size: centerSize,
            ),
          ),
        // Data content on top
        Padding(
          padding: EdgeInsets.all(8 * scale),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Time label
              Text(
                _formatSelectedTime(time),
                style: TextStyle(
                  fontSize: 14 * scale,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              SizedBox(height: 2 * scale),

              // Conditions text only (icon is now in background)
              // Use longDescription if available, otherwise conditions
              Text(
                forecast.longDescription ?? forecast.conditions ?? '',
                style: TextStyle(
                  fontSize: 11 * scale,
                  color: isDark ? Colors.white60 : Colors.black45,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 4 * scale),

          // Temperature (large)
          Text(
            forecast.temperature != null
                ? '${forecast.temperature!.toStringAsFixed(0)}${widget.tempUnit}'
                : '--',
            style: TextStyle(
              fontSize: 28 * scale,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          SizedBox(height: 4 * scale),

          // Wind speed and direction
          if (forecast.windSpeed != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (forecast.windDirection != null)
                  Transform.rotate(
                    angle: (forecast.windDirection! + 180) * math.pi / 180,
                    child: Icon(
                      Icons.navigation,
                      size: 18 * scale,
                      color: Colors.teal.shade300,
                    ),
                  ),
                SizedBox(width: 3 * scale),
                Text(
                  '${forecast.windSpeed!.toStringAsFixed(0)} ${widget.windUnit}',
                  style: TextStyle(
                    fontSize: 16 * scale,
                    color: Colors.teal.shade300,
                  ),
                ),
                if (forecast.windDirection != null) ...[
                  SizedBox(width: 3 * scale),
                  Text(
                    _getWindDirectionLabel(forecast.windDirection!),
                    style: TextStyle(
                      fontSize: 13 * scale,
                      color: Colors.teal.shade300,
                    ),
                  ),
                ],
              ],
            ),
          SizedBox(height: 2 * scale),

          // Humidity and Rain probability row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (forecast.humidity != null) ...[
                Icon(Icons.water_drop, size: 16 * scale, color: Colors.cyan.shade300),
                Text(
                  ' ${forecast.humidity!.toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 14 * scale, color: Colors.cyan.shade300),
                ),
              ],
              if (forecast.humidity != null && forecast.precipProbability != null)
                SizedBox(width: 10 * scale),
              if (forecast.precipProbability != null) ...[
                Icon(Icons.umbrella, size: 16 * scale, color: Colors.blue.shade300),
                Text(
                  ' ${forecast.precipProbability!.toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 14 * scale, color: Colors.blue.shade300),
                ),
              ],
            ],
          ),
          SizedBox(height: 2 * scale),

          // Pressure
          if (forecast.pressure != null)
            Text(
              '${forecast.pressure!.toStringAsFixed(0)} ${widget.pressureUnit}',
              style: TextStyle(
                fontSize: 13 * scale,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),

              SizedBox(height: 16 * scale), // Space for button area
            ],
          ),
        ),
      ],
    );
  }

  String _formatSelectedTime(DateTime time) {
    final now = DateTime.now();
    final isToday = time.day == now.day && time.month == now.month && time.year == now.year;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow = time.day == tomorrow.day && time.month == tomorrow.month && time.year == tomorrow.year;

    // Format time in AM/PM with actual minutes
    final hour = time.hour;
    final minute = time.minute;
    final minuteStr = minute.toString().padLeft(2, '0');
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final ampm = hour < 12 ? 'AM' : 'PM';
    final hourStr = '$displayHour:$minuteStr $ampm';

    if (isToday) {
      return hourStr;
    } else if (isTomorrow) {
      return 'Tomorrow $hourStr';
    } else {
      final dayName = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][time.weekday - 1];
      return '$dayName $hourStr';
    }
  }

  Color _getTimeOfDayColor(DateTime time) {
    // Use actual sun times if available - matches _computeSegmentColor logic
    final times = widget.sunMoonTimes;
    if (times != null && times.days.isNotEmpty) {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final dayIndex = time.difference(todayStart).inDays;
      final dayTimes = times.getDay(dayIndex);

      if (dayTimes != null) {
        final sunrise = dayTimes.sunrise;
        final sunset = dayTimes.sunset;
        final dawn = dayTimes.dawn;
        final dusk = dayTimes.dusk;
        final goldenHour = dayTimes.goldenHour;
        final goldenHourEnd = dayTimes.goldenHourEnd;
        final nauticalDawn = dayTimes.nauticalDawn;
        final nauticalDusk = dayTimes.nauticalDusk;

        if (sunrise != null && sunset != null) {
          final timeMinutes = time.hour * 60 + time.minute;
          final sunriseLocal = sunrise.toLocal();
          final sunsetLocal = sunset.toLocal();
          final sunriseMin = sunriseLocal.hour * 60 + sunriseLocal.minute;
          final sunsetMin = sunsetLocal.hour * 60 + sunsetLocal.minute;
          final dawnLocal = dawn?.toLocal();
          final duskLocal = dusk?.toLocal();
          final nauticalDawnLocal = nauticalDawn?.toLocal();
          final nauticalDuskLocal = nauticalDusk?.toLocal();
          final goldenHourLocal = goldenHour?.toLocal();
          final goldenHourEndLocal = goldenHourEnd?.toLocal();
          final dawnMin = dawnLocal != null ? dawnLocal.hour * 60 + dawnLocal.minute : sunriseMin - 30;
          final duskMin = duskLocal != null ? duskLocal.hour * 60 + duskLocal.minute : sunsetMin + 30;
          final nauticalDawnMin = nauticalDawnLocal != null ? nauticalDawnLocal.hour * 60 + nauticalDawnLocal.minute : dawnMin - 30;
          final nauticalDuskMin = nauticalDuskLocal != null ? nauticalDuskLocal.hour * 60 + nauticalDuskLocal.minute : duskMin + 30;
          final goldenHourEndMin = goldenHourEndLocal != null ? goldenHourEndLocal.hour * 60 + goldenHourEndLocal.minute : sunriseMin + 60;
          final goldenHourMin = goldenHourLocal != null ? goldenHourLocal.hour * 60 + goldenHourLocal.minute : sunsetMin - 60;

          if (timeMinutes < nauticalDawnMin) return Colors.indigo.shade900;
          if (timeMinutes >= nauticalDawnMin && timeMinutes < dawnMin) return Colors.indigo.shade700;
          if (timeMinutes >= dawnMin && timeMinutes < sunriseMin) return Colors.indigo.shade400;
          if (timeMinutes >= sunriseMin && timeMinutes < goldenHourEndMin) return Colors.orange.shade300;
          if (timeMinutes >= goldenHourEndMin && timeMinutes < goldenHourMin) return Colors.amber.shade200;
          if (timeMinutes >= goldenHourMin && timeMinutes < sunsetMin) return Colors.orange.shade300;
          if (timeMinutes >= sunsetMin && timeMinutes < duskMin) return Colors.deepOrange.shade400;
          if (timeMinutes >= duskMin && timeMinutes < nauticalDuskMin) return Colors.indigo.shade700;
          if (timeMinutes >= nauticalDuskMin) return Colors.indigo.shade900;
        }
      }
    }

    // Fallback: simplified hour-based colors - matches _computeSegmentColor fallback
    final hour = time.hour;
    if (hour >= 5 && hour < 6) return Colors.indigo.shade700;
    if (hour >= 6 && hour < 7) return Colors.indigo.shade400;
    if (hour >= 7 && hour < 8) return Colors.orange.shade300;
    if (hour >= 8 && hour < 16) return Colors.amber.shade200;
    if (hour >= 16 && hour < 17) return Colors.orange.shade400;
    if (hour >= 17 && hour < 18) return Colors.deepOrange.shade400;
    if (hour >= 18 && hour < 19) return Colors.indigo.shade700;
    return Colors.indigo.shade900;
  }

  String _getWindDirectionLabel(double degrees) {
    const directions = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
                        'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
    final index = ((degrees + 11.25) % 360 / 22.5).floor();
    return directions[index];
  }

  Color _getWeatherIconColor(String? iconCode) {
    final code = iconCode?.toLowerCase() ?? '';
    if (code.contains('clear')) return Colors.amber;
    if (code.contains('partly-cloudy')) return Colors.blueGrey;
    if (code.contains('cloudy')) return Colors.grey;
    if (code.contains('rainy') || code.contains('rain')) return Colors.blue;
    if (code.contains('thunder')) return Colors.deepPurple;
    if (code.contains('snow')) return Colors.lightBlue.shade100;
    if (code.contains('sleet')) return Colors.cyan;
    if (code.contains('foggy')) return Colors.blueGrey;
    if (code.contains('windy')) return Colors.teal;
    return Colors.grey;
  }

  /// Detect weather effect type from forecast
  WeatherEffectType _getWeatherEffect(HourlyForecast forecast) {
    final conditions = forecast.conditions?.toLowerCase() ?? '';
    final icon = forecast.icon?.toLowerCase() ?? '';
    final combined = '$conditions $icon';

    // Check for thunder first (highest priority)
    if (combined.contains('thunder') || combined.contains('lightning')) {
      return WeatherEffectType.thunder;
    }

    // Check for hail/sleet
    if (combined.contains('hail') || combined.contains('sleet') || combined.contains('ice')) {
      return WeatherEffectType.hail;
    }

    // Check for snow
    if (combined.contains('snow') || combined.contains('flurr')) {
      return WeatherEffectType.snow;
    }

    // Check for rain
    if (combined.contains('rain') || combined.contains('drizzle') || combined.contains('shower')) {
      return WeatherEffectType.rain;
    }

    // Check for wind (high wind speed or wind in conditions)
    final windSpeed = forecast.windSpeed ?? 0;
    if (combined.contains('wind') || windSpeed > 25) {
      return WeatherEffectType.wind;
    }

    return WeatherEffectType.none;
  }
}

/// Custom painter for the spinnable rim
class _ForecastRimPainter extends CustomPainter {
  final SunMoonTimes? times;
  final double rotationAngle;
  final bool isDark;
  final int selectedHourOffset;
  final List<Color>? cachedSegmentColors;
  final DateTime cachedNow;
  final int maxForecastHours;

  _ForecastRimPainter({
    required this.times,
    required this.rotationAngle,
    required this.isDark,
    required this.selectedHourOffset,
    this.cachedSegmentColors,
    required this.cachedNow,
    required this.maxForecastHours,
  });

  @override
  void paint(Canvas canvas, Size size) {
    try {
      _paintInternal(canvas, size);
    } catch (e) {
      // Silently fail to prevent crash loops
      debugPrint('ForecastRimPainter error: $e');
    }
  }

  void _paintInternal(Canvas canvas, Size size) {
    // Guard against invalid size or rotation
    if (size.isEmpty || !rotationAngle.isFinite) {
      return;
    }

    final center = Offset(size.width / 2, size.height / 2);

    // Scale factor based on reference size of 300px
    final scale = (size.width / 300).clamp(0.5, 1.5);

    // Dynamic sizing based on widget size
    final outerMargin = 27.0 * scale; // Match sunrise/sunset icon width
    final outerRadius = size.width / 2 - outerMargin;
    final innerRadius = outerRadius * 0.72; // Proportional inner radius
    final rimWidth = outerRadius - innerRadius;

    // Additional size guards
    if (outerRadius <= 0 || innerRadius <= 0 || rimWidth <= 0) {
      return;
    }

    // Save canvas state and apply rotation
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotationAngle);
    canvas.translate(-center.dx, -center.dy);

    // Draw segments for 72 hours (one segment per hour = 72 segments)
    // Reduced from 144 segments for better performance
    const segmentCount = 72;
    const minutesPerSegment = 60;
    const radiansPerSegment = (2 * math.pi) / 24; // 24 segments per 24 hours (one per hour)

    final arcRect = Rect.fromCircle(center: center, radius: (outerRadius + innerRadius) / 2);
    final segmentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rimWidth
      ..strokeCap = StrokeCap.butt;

    for (int i = 0; i < segmentCount; i++) {
      // Each segment represents 1 hour, positioned by hours from now
      final startAngle = -math.pi / 2 + (i * math.pi / 12);
      const sweepAngle = radiansPerSegment + 0.01; // Slight overlap

      // Use cached color if available, otherwise fallback to simple calculation
      segmentPaint.color = cachedSegmentColors != null && i < cachedSegmentColors!.length
          ? cachedSegmentColors![i]
          : _getFallbackColor(i * minutesPerSegment);

      canvas.drawArc(
        arcRect,
        startAngle,
        sweepAngle,
        false,
        segmentPaint,
      );
    }

    // Unused but kept for compatibility
    final baseHourOffset = 0;

    // Draw hour tick marks
    final tickPaint = Paint()
      ..color = isDark ? Colors.white54 : Colors.black38
      ..strokeWidth = 2 * scale;

    for (int i = 0; i < 24; i++) {
      final angle = -math.pi / 2 + (i * math.pi / 12);
      final outerPoint = Offset(
        center.dx + outerRadius * math.cos(angle),
        center.dy + outerRadius * math.sin(angle),
      );
      final innerPoint = Offset(
        center.dx + (outerRadius - 8 * scale) * math.cos(angle),
        center.dy + (outerRadius - 8 * scale) * math.sin(angle),
      );
      canvas.drawLine(innerPoint, outerPoint, tickPaint);
    }

    // Draw hour labels for key hours (every 6 hours) - show actual times
    final textStyle = TextStyle(
      fontSize: 9 * scale,
      color: isDark ? Colors.white70 : Colors.black54,
      fontWeight: FontWeight.w500,
    );

    for (int i = 0; i < 24; i += 6) {
      final angle = -math.pi / 2 + (i * math.pi / 12);
      final labelRadius = innerRadius - 12 * scale;
      final labelCenter = Offset(
        center.dx + labelRadius * math.cos(angle),
        center.dy + labelRadius * math.sin(angle),
      );

      // Label text - show actual time using cachedNow
      String labelText;
      if (i == 0) {
        // Show current time for "Now"
        final hour = cachedNow.hour;
        final minute = cachedNow.minute;
        final ampm = hour < 12 ? 'AM' : 'PM';
        final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        labelText = '$displayHour:${minute.toString().padLeft(2, '0')} $ampm';
      } else {
        // Show future time
        final futureTime = cachedNow.add(Duration(hours: i));
        final hour = futureTime.hour;
        final ampm = hour < 12 ? 'AM' : 'PM';
        final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        labelText = '$displayHour $ampm';
      }

      final textSpan = TextSpan(text: labelText, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // Counter-rotate text to keep it readable
      canvas.save();
      canvas.translate(labelCenter.dx, labelCenter.dy);
      canvas.rotate(-rotationAngle); // Counter-rotate
      canvas.translate(-textPainter.width / 2, -textPainter.height / 2);
      textPainter.paint(canvas, Offset.zero);
      canvas.restore();
    }

    // Draw sun/moon icons on the rim (pass base offset and scale for correct positioning)
    _drawSunMoonIcons(canvas, center, outerRadius, innerRadius, cachedNow, baseHourOffset, scale);

    canvas.restore();

    // Draw outer border (doesn't rotate)
    final borderPaint = Paint()
      ..color = isDark ? Colors.white24 : Colors.black12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * scale;
    canvas.drawCircle(center, outerRadius, borderPaint);
  }

  void _drawSunMoonIcons(Canvas canvas, Offset center, double outerRadius, double innerRadius, DateTime now, int baseHourOffset, double scale) {
    if (times == null) return;

    final iconRadius = (outerRadius + innerRadius) / 2;
    final iconSize = 27.0 * scale;  // Reduced by 25% from 36

    // Helper to get angle for a specific time
    // Icons are positioned at absolute hours from now, rotating with the rim
    // Only show icons within the currently visible ~24 hour window
    double? getAngleForTime(DateTime? eventTime) {
      if (eventTime == null) return null;

      // Guard against non-finite rotation values
      if (!rotationAngle.isFinite) return null;

      final hoursFromNow = eventTime.difference(now).inMinutes / 60.0;
      if (!hoursFromNow.isFinite) return null;

      // Calculate the current view window based on rotation
      // rotationAngle is negative when spinning forward in time (counter-clockwise)
      // Each hour = pi/12 radians, so current center hour = -rotationAngle / (pi/12)
      final centerHour = -rotationAngle / (math.pi / 12);

      // Show icons within ~12 hours before and after the center (24-hour visible window)
      final minVisibleHour = centerHour - 12;
      final maxVisibleHour = centerHour + 12;

      // Only show if within visible window AND within forecast range
      if (hoursFromNow < minVisibleHour || hoursFromNow > maxVisibleHour) return null;
      if (hoursFromNow < -2 || hoursFromNow > maxForecastHours) return null;

      // Each hour = 15 degrees = pi/12 radians, starting from top (-pi/2)
      return -math.pi / 2 + (hoursFromNow * math.pi / 12);
    }

    // Format time as AM/PM with minutes (convert to local timezone)
    String formatTime(DateTime time) {
      final local = time.toLocal();
      final hour = local.hour;
      final minute = local.minute;
      final minuteStr = minute.toString().padLeft(2, '0');
      if (hour == 0) return '12:$minuteStr AM';
      if (hour < 12) return '$hour:$minuteStr AM';
      if (hour == 12) return '12:$minuteStr PM';
      return '${hour - 12}:$minuteStr PM';
    }

    // Helper to draw sun icon (simple circle with rays)
    void drawSunIcon(Offset iconCenter, double angle, DateTime eventTime, bool isRise) {
      canvas.save();
      canvas.translate(iconCenter.dx, iconCenter.dy);
      canvas.rotate(-rotationAngle); // Counter-rotate to keep upright

      final sunRadius = iconSize / 2 - 2 * scale;

      // Draw sun glow
      final glowPaint = Paint()
        ..color = (isRise ? Colors.orange.shade300 : Colors.deepOrange.shade400).withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset.zero, sunRadius + 4 * scale, glowPaint);

      // Draw sun body
      final sunPaint = Paint()
        ..color = isRise ? Colors.orange.shade400 : Colors.deepOrange.shade500
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset.zero, sunRadius, sunPaint);

      // Draw rays
      final rayPaint = Paint()
        ..color = isRise ? Colors.orange.shade300 : Colors.deepOrange.shade400
        ..strokeWidth = 2 * scale
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < 8; i++) {
        final rayAngle = i * math.pi / 4;
        final start = Offset(
          (sunRadius + 2 * scale) * math.cos(rayAngle),
          (sunRadius + 2 * scale) * math.sin(rayAngle),
        );
        final end = Offset(
          (sunRadius + 5 * scale) * math.cos(rayAngle),
          (sunRadius + 5 * scale) * math.sin(rayAngle),
        );
        canvas.drawLine(start, end, rayPaint);
      }

      // Draw arrow indicator (scaled)
      final arrowPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 3 * scale
        ..style = PaintingStyle.stroke;
      if (isRise) {
        // Up arrow for sunrise
        canvas.drawLine(Offset(0, 5 * scale), Offset(0, -7 * scale), arrowPaint);
        canvas.drawLine(Offset(-5 * scale, 0), Offset(0, -7 * scale), arrowPaint);
        canvas.drawLine(Offset(5 * scale, 0), Offset(0, -7 * scale), arrowPaint);
      } else {
        // Down arrow for sunset
        canvas.drawLine(Offset(0, -5 * scale), Offset(0, 7 * scale), arrowPaint);
        canvas.drawLine(Offset(-5 * scale, 0), Offset(0, 7 * scale), arrowPaint);
        canvas.drawLine(Offset(5 * scale, 0), Offset(0, 7 * scale), arrowPaint);
      }

      canvas.restore();

      // Draw time label outside the rim
      final labelRadius = outerRadius + 14 * scale;
      final labelCenter = Offset(
        center.dx + labelRadius * math.cos(angle),
        center.dy + labelRadius * math.sin(angle),
      );

      final timeText = formatTime(eventTime);
      final textSpan = TextSpan(
        text: timeText,
        style: TextStyle(
          fontSize: 10 * scale,
          fontWeight: FontWeight.w600,
          color: isRise ? Colors.orange.shade400 : Colors.deepOrange.shade500,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      canvas.save();
      canvas.translate(labelCenter.dx, labelCenter.dy);
      canvas.rotate(-rotationAngle); // Counter-rotate to keep readable
      canvas.translate(-textPainter.width / 2, -textPainter.height / 2);
      textPainter.paint(canvas, Offset.zero);
      canvas.restore();
    }

    // Helper to draw moon icon with phase
    void drawMoonIcon(Offset iconCenter, double angle, DateTime eventTime, bool isRise) {
      canvas.save();
      canvas.translate(iconCenter.dx, iconCenter.dy);
      canvas.rotate(-rotationAngle); // Counter-rotate to keep upright

      final moonRadius = iconSize / 2 - 1 * scale;
      // Guard against NaN/Infinity from SignalK
      var phase = times!.moonPhase ?? 0.5;
      var fraction = times!.moonFraction ?? 0.5;
      if (!phase.isFinite) phase = 0.5;
      if (!fraction.isFinite) fraction = 0.5;
      fraction = fraction.clamp(0.0, 1.0);

      // Draw moon background (dark side)
      final darkPaint = Paint()
        ..color = Colors.grey.shade800
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset.zero, moonRadius, darkPaint);

      // Draw illuminated side
      final lightPaint = Paint()
        ..color = Colors.grey.shade200
        ..style = PaintingStyle.fill;

      if (fraction > 0.01 && fraction < 0.99) {
        final bool isWaxing = phase < 0.5;
        final termWidth = moonRadius * (2.0 * fraction - 1.0);
        final isGibbous = fraction > 0.5;

        // Guard against invalid ellipse radii
        final ellipseX = termWidth.abs().clamp(0.1, moonRadius - 0.1);
        if (!ellipseX.isFinite || !moonRadius.isFinite) {
          // Fallback to simple half moon
          canvas.drawArc(
            Rect.fromCircle(center: Offset.zero, radius: moonRadius),
            isWaxing ? -math.pi / 2 : math.pi / 2,
            math.pi,
            true,
            lightPaint,
          );
        } else {
          final path = Path();
          if (isWaxing) {
            path.moveTo(0, -moonRadius);
            path.arcToPoint(
              Offset(0, moonRadius),
              radius: Radius.circular(moonRadius),
              clockwise: true,
            );
            path.arcToPoint(
              Offset(0, -moonRadius),
              radius: Radius.elliptical(ellipseX, moonRadius),
              clockwise: isGibbous,
            );
          } else {
            path.moveTo(0, -moonRadius);
            path.arcToPoint(
              Offset(0, moonRadius),
              radius: Radius.circular(moonRadius),
              clockwise: false,
            );
            path.arcToPoint(
              Offset(0, -moonRadius),
              radius: Radius.elliptical(ellipseX, moonRadius),
              clockwise: !isGibbous,
            );
          }
          path.close();
          canvas.drawPath(path, lightPaint);
        }
      } else if (fraction >= 0.99) {
        // Full moon
        canvas.drawCircle(Offset.zero, moonRadius, lightPaint);
      }

      // Draw arrow indicator (scaled)
      final arrowPaint = Paint()
        ..color = isRise ? Colors.cyan.shade300 : Colors.blueGrey.shade400
        ..strokeWidth = 3 * scale
        ..style = PaintingStyle.stroke;
      if (isRise) {
        canvas.drawLine(Offset(0, 5 * scale), Offset(0, -7 * scale), arrowPaint);
        canvas.drawLine(Offset(-5 * scale, 0), Offset(0, -7 * scale), arrowPaint);
        canvas.drawLine(Offset(5 * scale, 0), Offset(0, -7 * scale), arrowPaint);
      } else {
        canvas.drawLine(Offset(0, -5 * scale), Offset(0, 7 * scale), arrowPaint);
        canvas.drawLine(Offset(-5 * scale, 0), Offset(0, 7 * scale), arrowPaint);
        canvas.drawLine(Offset(5 * scale, 0), Offset(0, 7 * scale), arrowPaint);
      }

      canvas.restore();

      // Draw time label outside the rim
      final labelRadius = outerRadius + 14 * scale;
      final labelCenter = Offset(
        center.dx + labelRadius * math.cos(angle),
        center.dy + labelRadius * math.sin(angle),
      );

      final timeText = formatTime(eventTime);
      final textSpan = TextSpan(
        text: timeText,
        style: TextStyle(
          fontSize: 10 * scale,
          fontWeight: FontWeight.w600,
          color: isRise ? Colors.cyan.shade300 : Colors.blueGrey.shade400,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      canvas.save();
      canvas.translate(labelCenter.dx, labelCenter.dy);
      canvas.rotate(-rotationAngle); // Counter-rotate to keep readable
      canvas.translate(-textPainter.width / 2, -textPainter.height / 2);
      textPainter.paint(canvas, Offset.zero);
      canvas.restore();
    }

    // Secondary icon size and radius (smaller, outside the rim)
    final secondaryIconSize = iconSize * 0.5;
    final secondaryIconRadius = outerRadius + 8 * scale;

    // Helper to draw twilight icon (sun with horizon line) - small, outside rim
    void drawTwilightIcon(Offset iconCenter, double angle, DateTime eventTime, bool isDawn, bool isNautical) {
      canvas.save();
      canvas.translate(iconCenter.dx, iconCenter.dy);
      canvas.rotate(-rotationAngle);

      final tinyRadius = secondaryIconSize / 3;
      final color = isNautical
          ? (isDawn ? Colors.indigo.shade300 : Colors.indigo.shade400)
          : (isDawn ? Colors.purple.shade300 : Colors.deepPurple.shade300);

      // Draw horizon line
      final horizonPaint = Paint()
        ..color = color
        ..strokeWidth = 1.5 * scale
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(-tinyRadius - 2 * scale, 0), Offset(tinyRadius + 2 * scale, 0), horizonPaint);

      // Draw half sun (above or below horizon)
      final sunPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      final rect = Rect.fromCircle(center: Offset.zero, radius: tinyRadius);
      if (isDawn) {
        canvas.drawArc(rect, 0, math.pi, true, sunPaint);
      } else {
        canvas.drawArc(rect, -math.pi, math.pi, true, sunPaint);
      }

      // Draw tiny stars for nautical twilight
      if (isNautical) {
        final starPaint = Paint()
          ..color = Colors.white70
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(-tinyRadius - 1 * scale, -tinyRadius), 1.5 * scale, starPaint);
        canvas.drawCircle(Offset(tinyRadius + 1 * scale, -tinyRadius + 1 * scale), 1 * scale, starPaint);
      }

      canvas.restore();
    }

    // Helper to draw golden hour icon (half sun with warm glow) - small, outside rim
    void drawGoldenHourIcon(Offset iconCenter, double angle, DateTime eventTime, bool isMorning) {
      canvas.save();
      canvas.translate(iconCenter.dx, iconCenter.dy);
      canvas.rotate(-rotationAngle);

      final tinyRadius = secondaryIconSize / 2.5;

      // Draw warm golden glow
      final glowPaint = Paint()
        ..color = Colors.orange.shade300.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(0, isMorning ? 2 * scale : -2 * scale), tinyRadius + 3 * scale, glowPaint);

      // Draw horizon line (thicker, golden)
      final horizonPaint = Paint()
        ..color = Colors.orange.shade400
        ..strokeWidth = 2 * scale
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(-tinyRadius - 4 * scale, 0), Offset(tinyRadius + 4 * scale, 0), horizonPaint);

      // Draw half sun (above horizon for morning/end, below for evening/start)
      final sunPaint = Paint()
        ..color = Colors.orange.shade500
        ..style = PaintingStyle.fill;

      final rect = Rect.fromCircle(center: Offset.zero, radius: tinyRadius);
      if (isMorning) {
        // Morning golden hour END - sun rising above horizon
        canvas.drawArc(rect, math.pi, math.pi, true, sunPaint);
      } else {
        // Evening golden hour START - sun setting toward horizon
        canvas.drawArc(rect, 0, math.pi, true, sunPaint);
      }

      // Draw rays only on the visible half (3 rays)
      final rayPaint = Paint()
        ..color = Colors.amber.shade400
        ..strokeWidth = 1.5 * scale
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < 3; i++) {
        final rayAngle = (isMorning ? -math.pi / 2 : math.pi / 2) + (i - 1) * math.pi / 6;
        final start = Offset(
          (tinyRadius + 1 * scale) * math.cos(rayAngle),
          (tinyRadius + 1 * scale) * math.sin(rayAngle),
        );
        final end = Offset(
          (tinyRadius + 4 * scale) * math.cos(rayAngle),
          (tinyRadius + 4 * scale) * math.sin(rayAngle),
        );
        canvas.drawLine(start, end, rayPaint);
      }

      canvas.restore();
    }

    // Helper to draw solar noon icon (sun at peak) - small, outside rim
    void drawSolarNoonIcon(Offset iconCenter, double angle, DateTime eventTime) {
      canvas.save();
      canvas.translate(iconCenter.dx, iconCenter.dy);
      canvas.rotate(-rotationAngle);

      final tinyRadius = secondaryIconSize / 3;

      // Draw bright glow
      final glowPaint = Paint()
        ..color = Colors.yellow.shade100.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset.zero, tinyRadius + 3 * scale, glowPaint);

      // Draw sun
      final sunPaint = Paint()
        ..color = Colors.yellow.shade600
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset.zero, tinyRadius, sunPaint);

      // Draw rays
      final rayPaint = Paint()
        ..color = Colors.yellow.shade400
        ..strokeWidth = 1 * scale
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < 8; i++) {
        final rayAngle = i * math.pi / 4;
        final start = Offset(
          (tinyRadius + 1 * scale) * math.cos(rayAngle),
          (tinyRadius + 1 * scale) * math.sin(rayAngle),
        );
        final end = Offset(
          (tinyRadius + 3 * scale) * math.cos(rayAngle),
          (tinyRadius + 3 * scale) * math.sin(rayAngle),
        );
        canvas.drawLine(start, end, rayPaint);
      }

      canvas.restore();
    }

    // Draw sun/moon icons for all available days
    for (int dayIndex = 0; dayIndex < times!.days.length; dayIndex++) {
      final dayTimes = times!.days[dayIndex];

      // Nautical Dawn - secondary, outside rim
      if (dayTimes.nauticalDawn != null) {
        final angle = getAngleForTime(dayTimes.nauticalDawn);
        if (angle != null) {
          final pos = Offset(center.dx + secondaryIconRadius * math.cos(angle),
                             center.dy + secondaryIconRadius * math.sin(angle));
          drawTwilightIcon(pos, angle, dayTimes.nauticalDawn!, true, true);
        }
      }

      // Dawn (civil twilight) - secondary, outside rim
      if (dayTimes.dawn != null) {
        final angle = getAngleForTime(dayTimes.dawn);
        if (angle != null) {
          final pos = Offset(center.dx + secondaryIconRadius * math.cos(angle),
                             center.dy + secondaryIconRadius * math.sin(angle));
          drawTwilightIcon(pos, angle, dayTimes.dawn!, true, false);
        }
      }

      // Sunrise - primary, on rim
      if (dayTimes.sunrise != null) {
        final angle = getAngleForTime(dayTimes.sunrise);
        if (angle != null) {
          final pos = Offset(center.dx + iconRadius * math.cos(angle),
                             center.dy + iconRadius * math.sin(angle));
          drawSunIcon(pos, angle, dayTimes.sunrise!, true);
        }
      }

      // Golden Hour End (morning) - secondary, outside rim
      if (dayTimes.goldenHourEnd != null) {
        final angle = getAngleForTime(dayTimes.goldenHourEnd);
        if (angle != null) {
          final pos = Offset(center.dx + secondaryIconRadius * math.cos(angle),
                             center.dy + secondaryIconRadius * math.sin(angle));
          drawGoldenHourIcon(pos, angle, dayTimes.goldenHourEnd!, true);
        }
      }

      // Solar Noon - secondary, outside rim
      if (dayTimes.solarNoon != null) {
        final angle = getAngleForTime(dayTimes.solarNoon);
        if (angle != null) {
          final pos = Offset(center.dx + secondaryIconRadius * math.cos(angle),
                             center.dy + secondaryIconRadius * math.sin(angle));
          drawSolarNoonIcon(pos, angle, dayTimes.solarNoon!);
        }
      }

      // Golden Hour (evening) - secondary, outside rim
      if (dayTimes.goldenHour != null) {
        final angle = getAngleForTime(dayTimes.goldenHour);
        if (angle != null) {
          final pos = Offset(center.dx + secondaryIconRadius * math.cos(angle),
                             center.dy + secondaryIconRadius * math.sin(angle));
          drawGoldenHourIcon(pos, angle, dayTimes.goldenHour!, false);
        }
      }

      // Sunset - primary, on rim
      if (dayTimes.sunset != null) {
        final angle = getAngleForTime(dayTimes.sunset);
        if (angle != null) {
          final pos = Offset(center.dx + iconRadius * math.cos(angle),
                             center.dy + iconRadius * math.sin(angle));
          drawSunIcon(pos, angle, dayTimes.sunset!, false);
        }
      }

      // Dusk (civil twilight) - secondary, outside rim
      if (dayTimes.dusk != null) {
        final angle = getAngleForTime(dayTimes.dusk);
        if (angle != null) {
          final pos = Offset(center.dx + secondaryIconRadius * math.cos(angle),
                             center.dy + secondaryIconRadius * math.sin(angle));
          drawTwilightIcon(pos, angle, dayTimes.dusk!, false, false);
        }
      }

      // Nautical Dusk - secondary, outside rim
      if (dayTimes.nauticalDusk != null) {
        final angle = getAngleForTime(dayTimes.nauticalDusk);
        if (angle != null) {
          final pos = Offset(center.dx + secondaryIconRadius * math.cos(angle),
                             center.dy + secondaryIconRadius * math.sin(angle));
          drawTwilightIcon(pos, angle, dayTimes.nauticalDusk!, false, true);
        }
      }

      // Moonrise - primary, on rim
      if (dayTimes.moonrise != null) {
        final angle = getAngleForTime(dayTimes.moonrise);
        if (angle != null) {
          final pos = Offset(center.dx + iconRadius * math.cos(angle),
                             center.dy + iconRadius * math.sin(angle));
          drawMoonIcon(pos, angle, dayTimes.moonrise!, true);
        }
      }

      // Moonset - primary, on rim
      if (dayTimes.moonset != null) {
        final angle = getAngleForTime(dayTimes.moonset);
        if (angle != null) {
          final pos = Offset(center.dx + iconRadius * math.cos(angle),
                             center.dy + iconRadius * math.sin(angle));
          drawMoonIcon(pos, angle, dayTimes.moonset!, false);
        }
      }
    }
  }

  /// Simple fallback color based on hour - used only when cached colors unavailable
  Color _getFallbackColor(int minutesFromNow) {
    // Calculate the hour of day for this segment
    final segmentTime = cachedNow.add(Duration(minutes: minutesFromNow));
    final hour = segmentTime.hour;
    if (hour >= 5 && hour < 6) return Colors.indigo.shade700;      // Nautical dawn
    if (hour >= 6 && hour < 7) return Colors.indigo.shade400;      // Civil dawn
    if (hour >= 7 && hour < 8) return Colors.orange.shade300;      // Golden hour morning
    if (hour >= 8 && hour < 16) return Colors.amber.shade200;      // Daylight
    if (hour >= 16 && hour < 17) return Colors.orange.shade400;    // Golden hour evening
    if (hour >= 17 && hour < 18) return Colors.deepOrange.shade400; // Civil dusk
    if (hour >= 18 && hour < 19) return Colors.indigo.shade700;    // Nautical dusk
    return Colors.indigo.shade900;                                  // Night
  }

  @override
  bool shouldRepaint(covariant _ForecastRimPainter oldDelegate) {
    // Only repaint if rotation, theme, or cached data changed
    // cachedSegmentColors identity check is fast (same list = no change)
    return oldDelegate.rotationAngle != rotationAngle ||
           oldDelegate.isDark != isDark ||
           !identical(oldDelegate.cachedSegmentColors, cachedSegmentColors);
  }
}

/// Animated weather effect overlay for the center circle
class _WeatherEffectOverlay extends StatefulWidget {
  final WeatherEffectType effectType;
  final double size;

  const _WeatherEffectOverlay({
    required this.effectType,
    required this.size,
  });

  @override
  State<_WeatherEffectOverlay> createState() => _WeatherEffectOverlayState();
}

class _WeatherEffectOverlayState extends State<_WeatherEffectOverlay>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  final List<_WeatherParticle> _particles = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _controller.addListener(_updateParticles);
    _initParticles();
  }

  @override
  void didUpdateWidget(_WeatherEffectOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effectType != widget.effectType) {
      _initParticles();
    }
  }

  void _initParticles() {
    _particles.clear();
    if (widget.effectType == WeatherEffectType.none) return;

    final count = widget.effectType == WeatherEffectType.wind ? 6 : 12;
    for (int i = 0; i < count; i++) {
      _particles.add(_WeatherParticle(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        speed: 0.3 + _random.nextDouble() * 0.4,
        size: 0.8 + _random.nextDouble() * 0.4,
        delay: _random.nextDouble(),
      ));
    }
  }

  void _updateParticles() {
    if (!mounted) return;
    setState(() {
      for (final p in _particles) {
        final progress = (_controller.value + p.delay) % 1.0;
        if (widget.effectType == WeatherEffectType.wind) {
          // Horizontal movement for wind
          p.currentX = (p.x + progress * p.speed * 2) % 1.0;
          p.currentY = p.y + math.sin(progress * math.pi * 4) * 0.05;
        } else {
          // Vertical falling for rain/snow/hail
          p.currentX = p.x + math.sin(progress * math.pi * 2) * 0.03;
          p.currentY = (progress * p.speed + p.y) % 1.0;
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_updateParticles);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.effectType == WeatherEffectType.none) {
      return const SizedBox.shrink();
    }

    return ClipOval(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          children: _particles.map((p) {
            final iconSize = 14.0 * p.size;
            return Positioned(
              left: p.currentX * widget.size - iconSize / 2,
              top: p.currentY * widget.size - iconSize / 2,
              child: Opacity(
                opacity: 0.6,
                child: _buildParticleIcon(iconSize),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildParticleIcon(double size) {
    switch (widget.effectType) {
      case WeatherEffectType.rain:
        return Icon(
          PhosphorIcons.drop(),
          size: size,
          color: Colors.blue.shade300,
        );
      case WeatherEffectType.snow:
        return Icon(
          PhosphorIcons.snowflake(),
          size: size,
          color: Colors.white70,
        );
      case WeatherEffectType.wind:
        return Icon(
          PhosphorIcons.wind(),
          size: size,
          color: Colors.teal.shade300,
        );
      case WeatherEffectType.hail:
        return Icon(
          PhosphorIcons.cloudSnow(),
          size: size,
          color: Colors.cyan.shade200,
        );
      case WeatherEffectType.thunder:
        return Icon(
          PhosphorIcons.lightning(),
          size: size,
          color: Colors.yellow.shade300,
        );
      case WeatherEffectType.none:
        return const SizedBox.shrink();
    }
  }
}

/// Single weather particle for animation
class _WeatherParticle {
  double x;
  double y;
  double speed;
  double size;
  double delay;
  double currentX = 0;
  double currentY = 0;

  _WeatherParticle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.delay,
  }) {
    currentX = x;
    currentY = y;
  }
}
