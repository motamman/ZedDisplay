# Sun/Moon Arc Widget — Integration Guide

## Overview

The `SunMoonArcWidget` displays a configurable arc showing the 24-hour progression of sun and moon through the sky. It shows sunrise/sunset, moonrise/moonset, twilight phases, golden hours, and moon phase — all computed locally from latitude/longitude using the `SunCalc`/`MoonCalc` ephemeris library.

## Key Files

| File | Purpose |
|------|---------|
| `lib/utils/sun_calc.dart` | `SunCalc` + `MoonCalc` ephemeris (pure Dart math) |
| `lib/utils/date_time_formatter.dart` | Time/date formatting utility |
| `lib/widgets/sun_moon_arc.dart` | `SunMoonArcWidget`, `ArcStyle`, `SunMoonArcConfig` |
| `lib/widgets/weatherflow_forecast.dart` | `SunMoonTimes`, `DaySunTimes` models |
| `lib/widgets/tools/sun_moon_arc_tool.dart` | Dashboard tool wrapper |
| `lib/screens/tool_config/configurators/sun_moon_arc_configurator.dart` | Config UI |

## Tool Registration

The tool is registered as `'sun_moon_arc'` in `ToolRegistry`. It subscribes to `navigation.position` and computes everything locally. No server-side sun/moon plugin needed. Excluded from both data source and style config sections in `tool_config_screen.dart` (see `.claude/CREATE_WIDGET_GUIDE.md` for the exclusion pattern).

## Embedding in Another Widget

### Step 1: Build `SunMoonTimes`

You need lat/lon and then compute the data:

```dart
import 'package:zeddisplay/utils/sun_calc.dart';
import 'package:zeddisplay/widgets/weatherflow_forecast.dart';

// Given lat/lon (e.g., from SignalK navigation.position)
final lat = 37.7749;
final lng = -122.4194;

final now = DateTime.now().toUtc();
final today = DateTime.utc(now.year, now.month, now.day, 12);
final tomorrow = today.add(const Duration(days: 1));

// Compute sun times
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
    // ... tomorrow similarly
  ],
  todayIndex: 0,
  moonPhase: currentMoonIllum.phase,
  moonFraction: currentMoonIllum.fraction,
  moonAngle: currentMoonIllum.angle,
  latitude: lat,
  longitude: lng,
);
```

### Step 2: Render the Widget

```dart
import 'package:zeddisplay/widgets/sun_moon_arc.dart';

SunMoonArcWidget(
  times: times,
  config: const SunMoonArcConfig(
    arcStyle: ArcStyle.half,        // half, threeQuarter, wide, full
    use24HourFormat: false,
    showInteriorTime: false,        // clock inside the arc
    showMoonMarkers: true,          // moonrise/moonset icons
    showSecondaryIcons: true,       // twilight/golden hour icons
    height: 70.0,                   // widget height
    strokeWidth: 2.0,
  ),
)
```

### Step 3: Keep It Updated

The widget is stateless — it renders whatever `SunMoonTimes` you give it. To keep the "now" marker moving, rebuild the parent at least once per minute (e.g., with a `Timer.periodic`).

For the standalone tool (`SunMoonArcTool`), this is already handled internally.

## `SunMoonArcConfig` Options

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `arcStyle` | `ArcStyle` | `half` | Arc shape: `half` (180°), `threeQuarter` (270°), `wide` (320°), `full` (355°) |
| `use24HourFormat` | `bool` | `false` | 24h time labels |
| `showTimeLabels` | `bool` | `true` | Time labels at arc edges |
| `showSunMarkers` | `bool` | `true` | Sunrise/sunset/noon icons |
| `showMoonMarkers` | `bool` | `true` | Moonrise/moonset/transit icons |
| `showTwilightSegments` | `bool` | `true` | Colored arc segments for twilight phases |
| `showCenterIndicator` | `bool` | `true` | "NOW" label at arc center |
| `showSecondaryIcons` | `bool` | `true` | Dawn, dusk, golden hour icons |
| `showInteriorTime` | `bool` | `false` | Large time display inside arc |
| `strokeWidth` | `double` | `2.0` | Arc line thickness |
| `height` | `double` | `70.0` | Widget height |
| `labelColor` | `Color?` | `null` | Override label color (auto from theme) |

## `SunMoonTimes` Model

The model supports:
- **`todayIndex`**: Which index in `days` represents today (usually 0)
- **`latitude`/`longitude`**: Enables on-demand computation via `getTimesForDate()`
- **`utcOffsetSeconds`**: Location timezone for correct label display
- **`getTimesForDate(date)`**: Returns cached data or computes on-demand using SunCalc/MoonCalc
- **`toLocationTime(utc)`**: Converts UTC to location time
- **`toUtcFromLocation(local)`**: Inverse conversion
- **`isSouthernHemisphere`**: Flips moon phase rendering

## `DaySunTimes` Fields

All `DateTime?` in UTC: `sunrise`, `sunset`, `dawn`, `dusk`, `nauticalDawn`, `nauticalDusk`, `solarNoon`, `goldenHour`, `goldenHourEnd`, `night`, `nightEnd`, `moonrise`, `moonset`.

Per-day: `moonPhase` (double 0-1), `moonFraction` (double 0-1), `alwaysNight`, `alwaysDay`, `moonAlwaysUp`, `moonAlwaysDown` (bools for polar conditions).

## Ephemeris Library (`sun_calc.dart`)

### `SunCalc`
- `SunCalc.getTimes(date, lat, lng)` → `SunTimes` (all twilight phases + polar detection)
- `SunCalc.getPosition(date, lat, lng)` → `SunPosition` (azimuth, altitude)

### `MoonCalc`
- `MoonCalc.getTimes(date, lat, lng)` → `MoonTimes` (rise, set, alwaysUp/Down)
- `MoonCalc.getIllumination(date)` → `MoonIllumination` (fraction, phase, angle, phaseName)
- `MoonCalc.getPosition(date, lat, lng)` → `MoonPosition` (azimuth, altitude, distance)

All methods are static, pure Dart math, zero external dependencies.
