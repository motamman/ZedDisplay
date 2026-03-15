import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/sun_calc.dart';
import '../weatherflow_forecast.dart';
import '../sun_moon_arc.dart';
import '../tool_info_button.dart';

/// Dashboard tool that computes and displays sun/moon arc from boat position
class SunMoonArcTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const SunMoonArcTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<SunMoonArcTool> createState() => _SunMoonArcToolState();
}

class _SunMoonArcToolState extends State<SunMoonArcTool> {
  static const _positionPath = 'navigation.position';
  static const _ownerId = 'sun_moon_arc';

  Timer? _refreshTimer;
  SunMoonTimes? _times;
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    // Subscribe to position path
    widget.signalKService.subscribeToPaths([_positionPath], ownerId: _ownerId);
    // Refresh every minute to keep arc current
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _computeTimes();
    });
    // Initial computation after a short delay for data to arrive
    Future.delayed(const Duration(milliseconds: 500), _computeTimes);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    widget.signalKService.unsubscribeFromPaths([_positionPath], ownerId: _ownerId);
    super.dispose();
  }

  void _computeTimes() {
    final posData = widget.signalKService.getValue(_positionPath);
    if (posData?.value == null) {
      // No position data yet
      if (_times != null) return; // Keep stale data
      return;
    }

    double? lat;
    double? lng;

    final value = posData!.value;
    if (value is Map) {
      lat = (value['latitude'] as num?)?.toDouble();
      lng = (value['longitude'] as num?)?.toDouble();
    }

    if (lat == null || lng == null) return;

    // Only recompute if position changed significantly or first time
    if (_lat != null && _lng != null) {
      final latDiff = (lat - _lat!).abs();
      final lngDiff = (lng - _lng!).abs();
      if (latDiff < 0.01 && lngDiff < 0.01 && _times != null) {
        // Position hasn't moved much, just trigger repaint for time progression
        if (mounted) setState(() {});
        return;
      }
    }

    _lat = lat;
    _lng = lng;

    final now = DateTime.now().toUtc();
    // Use LOCAL date for yesterday/today/tomorrow so that todayIndex aligns
    // with getTimesForDate() which indexes by local date. When UTC day != local
    // day (e.g. 9 PM EDT = next day UTC), using UTC dates causes a one-day
    // offset in the lookup.
    final localNow = DateTime.now();
    final localToday = DateTime(localNow.year, localNow.month, localNow.day, 12);
    final yesterday = localToday.subtract(const Duration(days: 1)).toUtc();
    final today = localToday.toUtc();
    final tomorrow = localToday.add(const Duration(days: 1)).toUtc();

    // Compute sun times for yesterday, today, and tomorrow
    // The arc spans ±12 hours from now, so when UTC day != local day,
    // we need yesterday's data for the left side of the arc.
    final yesterdaySun = SunCalc.getTimes(yesterday, lat, lng);
    final yesterdayMoon = MoonCalc.getTimes(yesterday, lat, lng);
    final yesterdayMoonIllum = MoonCalc.getIllumination(yesterday);

    final todaySun = SunCalc.getTimes(today, lat, lng);
    final todayMoon = MoonCalc.getTimes(today, lat, lng);
    final todayMoonIllum = MoonCalc.getIllumination(today);

    final tomorrowSun = SunCalc.getTimes(tomorrow, lat, lng);
    final tomorrowMoon = MoonCalc.getTimes(tomorrow, lat, lng);
    final tomorrowMoonIllum = MoonCalc.getIllumination(tomorrow);

    final currentMoonIllum = MoonCalc.getIllumination(now);

    final times = SunMoonTimes(
      days: [
        DaySunTimes(
          sunrise: yesterdaySun.sunrise,
          sunset: yesterdaySun.sunset,
          dawn: yesterdaySun.dawn,
          dusk: yesterdaySun.dusk,
          nauticalDawn: yesterdaySun.nauticalDawn,
          nauticalDusk: yesterdaySun.nauticalDusk,
          solarNoon: yesterdaySun.solarNoon,
          goldenHour: yesterdaySun.goldenHour,
          goldenHourEnd: yesterdaySun.goldenHourEnd,
          night: yesterdaySun.night,
          nightEnd: yesterdaySun.nightEnd,
          moonrise: yesterdayMoon.rise,
          moonset: yesterdayMoon.set,
          alwaysDay: yesterdaySun.alwaysDay,
          alwaysNight: yesterdaySun.alwaysNight,
          moonAlwaysUp: yesterdayMoon.alwaysUp,
          moonAlwaysDown: yesterdayMoon.alwaysDown,
          moonPhase: yesterdayMoonIllum.phase,
          moonFraction: yesterdayMoonIllum.fraction,
        ),
        DaySunTimes(
          sunrise: todaySun.sunrise,
          sunset: todaySun.sunset,
          dawn: todaySun.dawn,
          dusk: todaySun.dusk,
          nauticalDawn: todaySun.nauticalDawn,
          nauticalDusk: todaySun.nauticalDusk,
          solarNoon: todaySun.solarNoon,
          goldenHour: todaySun.goldenHour,
          goldenHourEnd: todaySun.goldenHourEnd,
          night: todaySun.night,
          nightEnd: todaySun.nightEnd,
          moonrise: todayMoon.rise,
          moonset: todayMoon.set,
          alwaysDay: todaySun.alwaysDay,
          alwaysNight: todaySun.alwaysNight,
          moonAlwaysUp: todayMoon.alwaysUp,
          moonAlwaysDown: todayMoon.alwaysDown,
          moonPhase: todayMoonIllum.phase,
          moonFraction: todayMoonIllum.fraction,
        ),
        DaySunTimes(
          sunrise: tomorrowSun.sunrise,
          sunset: tomorrowSun.sunset,
          dawn: tomorrowSun.dawn,
          dusk: tomorrowSun.dusk,
          nauticalDawn: tomorrowSun.nauticalDawn,
          nauticalDusk: tomorrowSun.nauticalDusk,
          solarNoon: tomorrowSun.solarNoon,
          goldenHour: tomorrowSun.goldenHour,
          goldenHourEnd: tomorrowSun.goldenHourEnd,
          night: tomorrowSun.night,
          nightEnd: tomorrowSun.nightEnd,
          moonrise: tomorrowMoon.rise,
          moonset: tomorrowMoon.set,
          alwaysDay: tomorrowSun.alwaysDay,
          alwaysNight: tomorrowSun.alwaysNight,
          moonAlwaysUp: tomorrowMoon.alwaysUp,
          moonAlwaysDown: tomorrowMoon.alwaysDown,
          moonPhase: tomorrowMoonIllum.phase,
          moonFraction: tomorrowMoonIllum.fraction,
        ),
      ],
      todayIndex: 1,
      moonPhase: currentMoonIllum.phase,
      moonFraction: currentMoonIllum.fraction,
      moonAngle: currentMoonIllum.angle,
      latitude: lat,
      longitude: lng,
    );

    if (mounted) {
      setState(() {
        _times = times;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.config.style;
    final props = style.customProperties ?? {};

    // Parse config from customProperties
    final arcStyleName = props['arcStyle'] as String? ?? 'half';
    final use24Hour = props['use24HourFormat'] as bool? ?? false;
    final showInteriorTime = props['showInteriorTime'] as bool? ?? false;
    final showMoonMarkers = props['showMoonMarkers'] as bool? ?? true;
    final showSecondaryIcons = props['showSecondaryIcons'] as bool? ?? true;

    final arcStyle = ArcStyle.values.firstWhere(
      (s) => s.name == arcStyleName,
      orElse: () => ArcStyle.half,
    );

    if (_times == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wb_sunny_outlined, size: 32, color: Colors.amber.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            Text(
              'Waiting for position...',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final arcConfig = SunMoonArcConfig(
          arcStyle: arcStyle,
          use24HourFormat: use24Hour,
          showInteriorTime: showInteriorTime,
          showMoonMarkers: showMoonMarkers,
          showSecondaryIcons: showSecondaryIcons,
          height: constraints.maxHeight,
          strokeWidth: 2.5,
        );

        return Stack(
          children: [
            SunMoonArcWidget(
              times: _times!,
              config: arcConfig,
            ),
            // Moon phase label at bottom center
            if (_times!.moonPhase != null)
              Positioned(
                bottom: 4,
                left: 0,
                right: 0,
                child: Text(
                  MoonCalc.getIllumination(DateTime.now().toUtc()).phaseName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.5),
                  ),
                ),
              ),
            // Tool info button
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: ToolInfoButton(
                  toolId: 'sun_moon_arc',
                  signalKService: widget.signalKService,
                  iconSize: 14,
                  iconColor: Colors.white70,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Builder for the Sun/Moon Arc dashboard tool
class SunMoonArcToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'sun_moon_arc',
      name: 'Sun/Moon Arc',
      description: 'Sun and moon arc showing sunrise, sunset, moonrise, moonset, '
          'twilight phases, and moon phase. Computes locally from boat position.',
      category: ToolCategory.weather,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
        styleOptions: ['arcStyle', 'use24HourFormat', 'showInteriorTime', 'showMoonMarkers', 'showSecondaryIcons'],
        allowsDataSources: false,
        allowsUnitSelection: false,
        allowsVisibilityToggles: false,
        allowsTTL: false,
      ),
      defaultWidth: 4,
      defaultHeight: 2,
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      dataSources: const [],
      style: StyleConfig(
        customProperties: {
          'arcStyle': 'half',
          'use24HourFormat': false,
          'showInteriorTime': false,
          'showMoonMarkers': true,
          'showSecondaryIcons': true,
        },
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return SunMoonArcTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
