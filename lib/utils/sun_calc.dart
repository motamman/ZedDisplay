/// Sun and Moon position and times calculator
/// Based on https://github.com/mourner/suncalc (BSD-2-Clause License)
/// Formulas from "Astronomical Algorithms" 2nd ed. by Jean Meeus
library;

import 'dart:math' as math;

/// Sun times result containing all twilight phases
class SunTimes {
  final DateTime? solarNoon;
  final DateTime? nadir;
  final DateTime? sunrise;
  final DateTime? sunset;
  final DateTime? sunriseEnd;
  final DateTime? sunsetStart;
  final DateTime? dawn; // Civil dawn (-6°)
  final DateTime? dusk; // Civil dusk (-6°)
  final DateTime? nauticalDawn; // -12°
  final DateTime? nauticalDusk; // -12°
  final DateTime? nightEnd; // Astronomical dawn (-18°)
  final DateTime? night; // Astronomical dusk (-18°)
  final DateTime? goldenHourEnd; // Morning golden hour ends (+6°)
  final DateTime? goldenHour; // Evening golden hour starts (+6°)

  /// Polar night - sun never rises (stays below horizon all day)
  /// Occurs at high latitudes in winter
  final bool alwaysNight;

  /// Midnight sun - sun never sets (stays above horizon all day)
  /// Occurs at high latitudes in summer
  final bool alwaysDay;

  const SunTimes({
    this.solarNoon,
    this.nadir,
    this.sunrise,
    this.sunset,
    this.sunriseEnd,
    this.sunsetStart,
    this.dawn,
    this.dusk,
    this.nauticalDawn,
    this.nauticalDusk,
    this.nightEnd,
    this.night,
    this.goldenHourEnd,
    this.goldenHour,
    this.alwaysNight = false,
    this.alwaysDay = false,
  });
}

/// Sun position (azimuth and altitude)
class SunPosition {
  final double azimuth; // radians, measured from south, positive westward
  final double altitude; // radians, above horizon

  const SunPosition({required this.azimuth, required this.altitude});

  /// Altitude in degrees
  double get altitudeDegrees => altitude * 180 / math.pi;

  /// Azimuth in degrees (0-360, measured from north)
  double get azimuthDegrees {
    // Convert from south-based to north-based
    var deg = (azimuth * 180 / math.pi) + 180;
    return deg % 360;
  }
}

/// Calculator for sun position and times
class SunCalc {
  // Constants
  static const double _rad = math.pi / 180;
  static const double _dayMs = 1000 * 60 * 60 * 24;
  static const double _j1970 = 2440588;
  static const double _j2000 = 2451545;
  static const double _e = _rad * 23.4397; // obliquity of Earth

  // Sun times configuration: [angle, riseName, setName]
  // angle: degrees below horizon (negative) or above (positive)
  static const List<List<dynamic>> _times = [
    [-0.833, 'sunrise', 'sunset'],
    [-0.3, 'sunriseEnd', 'sunsetStart'],
    [-6, 'dawn', 'dusk'],
    [-12, 'nauticalDawn', 'nauticalDusk'],
    [-18, 'nightEnd', 'night'],
    [6, 'goldenHourEnd', 'goldenHour'],
  ];

  /// Calculate sun times for a given date and location
  static SunTimes getTimes(DateTime date, double lat, double lng, [double height = 0]) {
    final lw = _rad * -lng;
    final phi = _rad * lat;

    // Height correction for dip angle
    final dh = height > 0 ? -2.076 * math.sqrt(height) / 60 : 0;

    final d = _toDays(date);
    final n = _julianCycle(d, lw);
    final ds = _approxTransit(0, lw, n);

    final M = _solarMeanAnomaly(ds);
    final L = _eclipticLongitude(M);
    final dec = _declination(L, 0);

    final jnoon = _solarTransitJ(ds, M, L);

    // ========== POLAR DETECTION FIRST ==========
    // Calculate sun's altitude at noon and midnight BEFORE the loop
    // This avoids floating point edge cases with cosH near ±1.0
    //
    // At solar noon (H = 0): altitude = asin(sin(phi)*sin(dec) + cos(phi)*cos(dec))
    // At midnight/nadir (H = π): altitude = asin(sin(phi)*sin(dec) - cos(phi)*cos(dec))
    final noonAltitude = math.asin(
      math.sin(phi) * math.sin(dec) + math.cos(phi) * math.cos(dec)
    );
    final midnightAltitude = math.asin(
      math.sin(phi) * math.sin(dec) - math.cos(phi) * math.cos(dec)
    );

    // Sunrise/sunset horizon angle (with height correction)
    final sunriseAngle = (-0.833 + dh) * _rad;

    // Polar night: sun's MAX altitude (at noon) is below sunrise angle - sun never rises
    // Safety check: if noonAltitude is NaN, comparison would be false - treat as NOT polar night
    final alwaysNight = !noonAltitude.isNaN && noonAltitude < sunriseAngle;

    // Polar day (midnight sun): sun's MIN altitude (at midnight) is above sunrise angle - sun never sets
    // Safety check: if midnightAltitude is NaN, comparison would be false - treat as NOT polar day
    final alwaysDay = !midnightAltitude.isNaN && midnightAltitude > sunriseAngle;

    // Handle polar conditions early - return with null times
    if (alwaysNight) {
      return SunTimes(
        solarNoon: _fromJulian(jnoon),
        nadir: _fromJulian(jnoon - 0.5),
        // All rise/set times are null during polar night
        sunrise: null,
        sunset: null,
        sunriseEnd: null,
        sunsetStart: null,
        dawn: null,
        dusk: null,
        nauticalDawn: null,
        nauticalDusk: null,
        nightEnd: null,
        night: null,
        goldenHourEnd: null,
        goldenHour: null,
        alwaysNight: true,
        alwaysDay: false,
      );
    }

    if (alwaysDay) {
      return SunTimes(
        solarNoon: _fromJulian(jnoon),
        nadir: _fromJulian(jnoon - 0.5),
        // All rise/set times are null during midnight sun
        sunrise: null,
        sunset: null,
        sunriseEnd: null,
        sunsetStart: null,
        dawn: null,
        dusk: null,
        nauticalDawn: null,
        nauticalDusk: null,
        nightEnd: null,
        night: null,
        goldenHourEnd: null,
        goldenHour: null,
        alwaysNight: false,
        alwaysDay: true,
      );
    }

    // ========== NORMAL CASE: Calculate rise/set times ==========
    final results = <String, DateTime?>{};

    // Calculate solar noon and nadir
    results['solarNoon'] = _fromJulian(jnoon);
    results['nadir'] = _fromJulian(jnoon - 0.5);

    // Calculate times for each configured angle
    // Note: For angles the sun doesn't reach (e.g., golden hour when sun stays low),
    // the clamped hour angle produces boundary values near noon - this is acceptable
    // since those periods effectively have zero duration
    for (final time in _times) {
      final angle = (time[0] as num).toDouble();
      final riseName = time[1] as String;
      final setName = time[2] as String;

      final h0 = (angle + dh) * _rad;
      final jset = _getSetJ(h0, lw, phi, dec, n, M, L);
      final jrise = jnoon - (jset - jnoon);

      results[riseName] = _fromJulian(jrise);
      results[setName] = _fromJulian(jset);
    }

    return SunTimes(
      solarNoon: results['solarNoon'],
      nadir: results['nadir'],
      sunrise: results['sunrise'],
      sunset: results['sunset'],
      sunriseEnd: results['sunriseEnd'],
      sunsetStart: results['sunsetStart'],
      dawn: results['dawn'],
      dusk: results['dusk'],
      nauticalDawn: results['nauticalDawn'],
      nauticalDusk: results['nauticalDusk'],
      nightEnd: results['nightEnd'],
      night: results['night'],
      goldenHourEnd: results['goldenHourEnd'],
      goldenHour: results['goldenHour'],
      alwaysNight: false,
      alwaysDay: false,
    );
  }

  /// Calculate sun position for a given date/time and location
  static SunPosition getPosition(DateTime date, double lat, double lng) {
    final lw = _rad * -lng;
    final phi = _rad * lat;
    final d = _toDays(date);

    final c = _sunCoords(d);
    final H = _siderealTime(d, lw) - c['ra']!;

    return SunPosition(
      azimuth: _azimuth(H, phi, c['dec']!),
      altitude: _altitude(H, phi, c['dec']!),
    );
  }

  // Date/time conversions
  static double _toJulian(DateTime date) {
    return date.millisecondsSinceEpoch / _dayMs - 0.5 + _j1970;
  }

  static DateTime? _fromJulian(double j) {
    if (j.isNaN || j.isInfinite) return null;
    final ms = (j + 0.5 - _j1970) * _dayMs;
    return DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true);
  }

  static double _toDays(DateTime date) {
    return _toJulian(date) - _j2000;
  }

  // General calculations for position
  static double _rightAscension(double l, double b) {
    return math.atan2(math.sin(l) * math.cos(_e) - math.tan(b) * math.sin(_e), math.cos(l));
  }

  static double _declination(double l, double b) {
    return math.asin(math.sin(b) * math.cos(_e) + math.cos(b) * math.sin(_e) * math.sin(l));
  }

  static double _azimuth(double H, double phi, double dec) {
    return math.atan2(math.sin(H), math.cos(H) * math.sin(phi) - math.tan(dec) * math.cos(phi));
  }

  static double _altitude(double H, double phi, double dec) {
    return math.asin(math.sin(phi) * math.sin(dec) + math.cos(phi) * math.cos(dec) * math.cos(H));
  }

  static double _siderealTime(double d, double lw) {
    return _rad * (280.16 + 360.9856235 * d) - lw;
  }

  // Sun calculations
  static double _solarMeanAnomaly(double d) {
    return _rad * (357.5291 + 0.98560028 * d);
  }

  static double _eclipticLongitude(double M) {
    final C = _rad * (1.9148 * math.sin(M) + 0.02 * math.sin(2 * M) + 0.0003 * math.sin(3 * M));
    final P = _rad * 102.9372; // perihelion of Earth
    return M + C + P + math.pi;
  }

  static Map<String, double> _sunCoords(double d) {
    final M = _solarMeanAnomaly(d);
    final L = _eclipticLongitude(M);
    return {
      'dec': _declination(L, 0),
      'ra': _rightAscension(L, 0),
    };
  }

  // Calculations for sun times
  static const double _j0 = 0.0009;

  static double _julianCycle(double d, double lw) {
    return (d - _j0 - lw / (2 * math.pi)).round().toDouble();
  }

  // ignore: non_constant_identifier_names
  static double _approxTransit(double Ht, double lw, double n) {
    return _j0 + (Ht + lw) / (2 * math.pi) + n;
  }

  static double _solarTransitJ(double ds, double M, double L) {
    return _j2000 + ds + 0.0053 * math.sin(M) - 0.0069 * math.sin(2 * L);
  }

  /// Calculate hour angle for sun position
  /// Clamps cosH to [-1, 1] for numerical stability
  /// Note: Polar conditions (sunrise/sunset) are now detected BEFORE this is called
  /// using noon/midnight altitude comparison in getTimes()
  static double _hourAngle(double h, double phi, double d) {
    final cosH = (math.sin(h) - math.sin(phi) * math.sin(d)) / (math.cos(phi) * math.cos(d));
    // Clamp for numerical stability - polar conditions are handled upfront in getTimes()
    return math.acos(cosH.clamp(-1.0, 1.0));
  }

  /// Get set time Julian date
  /// Note: Polar conditions are now detected upfront in getTimes() using altitude comparison
  static double _getSetJ(double h, double lw, double phi, double dec, double n, double M, double L) {
    final w = _hourAngle(h, phi, dec);
    final a = _approxTransit(w, lw, n);
    return _solarTransitJ(a, M, L);
  }
}

/// Moon position result
class MoonPosition {
  final double azimuth; // radians, measured from south
  final double altitude; // radians, above horizon
  final double distance; // km to moon
  final double parallacticAngle; // radians

  const MoonPosition({
    required this.azimuth,
    required this.altitude,
    required this.distance,
    required this.parallacticAngle,
  });

  /// Altitude in degrees
  double get altitudeDegrees => altitude * 180 / math.pi;

  /// Azimuth in degrees (0-360, measured from north)
  double get azimuthDegrees {
    var deg = (azimuth * 180 / math.pi) + 180;
    return deg % 360;
  }
}

/// Moon illumination result
class MoonIllumination {
  final double fraction; // 0-1, illuminated fraction
  final double phase; // 0-1 (0=new, 0.25=first quarter, 0.5=full, 0.75=last quarter)
  final double angle; // radians, midpoint angle of illuminated limb

  const MoonIllumination({
    required this.fraction,
    required this.phase,
    required this.angle,
  });

  /// Phase name
  String get phaseName {
    if (phase < 0.0625) return 'New Moon';
    if (phase < 0.1875) return 'Waxing Crescent';
    if (phase < 0.3125) return 'First Quarter';
    if (phase < 0.4375) return 'Waxing Gibbous';
    if (phase < 0.5625) return 'Full Moon';
    if (phase < 0.6875) return 'Waning Gibbous';
    if (phase < 0.8125) return 'Last Quarter';
    if (phase < 0.9375) return 'Waning Crescent';
    return 'New Moon';
  }
}

/// Moon rise/set times result
class MoonTimes {
  final DateTime? rise;
  final DateTime? set;
  final bool alwaysUp;
  final bool alwaysDown;

  const MoonTimes({
    this.rise,
    this.set,
    this.alwaysUp = false,
    this.alwaysDown = false,
  });
}

/// Calculator for moon position and times
class MoonCalc {
  static const double _rad = math.pi / 180;
  static const double _dayMs = 1000 * 60 * 60 * 24;
  static const double _j1970 = 2440588;
  static const double _j2000 = 2451545;
  static const double _e = _rad * 23.4397;

  // Moon calculations based on http://aa.quae.nl/en/reken/hemelpositie.html
  static Map<String, double> _moonCoords(double d) {
    final L = _rad * (218.316 + 13.176396 * d); // ecliptic longitude
    final M = _rad * (134.963 + 13.064993 * d); // mean anomaly
    final F = _rad * (93.272 + 13.229350 * d); // mean distance

    final l = L + _rad * 6.289 * math.sin(M); // longitude
    final b = _rad * 5.128 * math.sin(F); // latitude
    final dt = 385001 - 20905 * math.cos(M); // distance to moon in km

    return {
      'ra': _rightAscension(l, b),
      'dec': _declination(l, b),
      'dist': dt,
    };
  }

  static double _rightAscension(double l, double b) {
    return math.atan2(math.sin(l) * math.cos(_e) - math.tan(b) * math.sin(_e), math.cos(l));
  }

  static double _declination(double l, double b) {
    return math.asin(math.sin(b) * math.cos(_e) + math.cos(b) * math.sin(_e) * math.sin(l));
  }

  static double _siderealTime(double d, double lw) {
    return _rad * (280.16 + 360.9856235 * d) - lw;
  }

  static double _azimuth(double H, double phi, double dec) {
    return math.atan2(math.sin(H), math.cos(H) * math.sin(phi) - math.tan(dec) * math.cos(phi));
  }

  static double _altitude(double H, double phi, double dec) {
    return math.asin(math.sin(phi) * math.sin(dec) + math.cos(phi) * math.cos(dec) * math.cos(H));
  }

  static double _toJulian(DateTime date) {
    return date.millisecondsSinceEpoch / _dayMs - 0.5 + _j1970;
  }

  static double _toDays(DateTime date) {
    return _toJulian(date) - _j2000;
  }

  /// Get moon position for a given date/time and location
  static MoonPosition getPosition(DateTime date, double lat, double lng) {
    final lw = _rad * -lng;
    final phi = _rad * lat;
    final d = _toDays(date);

    final c = _moonCoords(d);
    final H = _siderealTime(d, lw) - c['ra']!;
    var h = _altitude(H, phi, c['dec']!);

    // Altitude correction for refraction
    h = h + _rad * 0.017 / math.tan(h + _rad * 10.26 / (h + _rad * 5.10));

    final pa = math.atan2(math.sin(H), math.tan(phi) * math.cos(c['dec']!) - math.sin(c['dec']!) * math.cos(H));

    return MoonPosition(
      azimuth: _azimuth(H, phi, c['dec']!),
      altitude: h,
      distance: c['dist']!,
      parallacticAngle: pa,
    );
  }

  /// Get moon illumination for a given date
  static MoonIllumination getIllumination(DateTime date) {
    final d = _toDays(date);
    final s = SunCalc._sunCoords(d);
    final m = _moonCoords(d);

    const sdist = 149598000.0; // distance from Earth to Sun in km

    final phi = math.acos(
      math.sin(s['dec']!) * math.sin(m['dec']!) +
      math.cos(s['dec']!) * math.cos(m['dec']!) * math.cos(s['ra']! - m['ra']!)
    );

    final inc = math.atan2(sdist * math.sin(phi), m['dist']! - sdist * math.cos(phi));
    final angle = math.atan2(
      math.cos(s['dec']!) * math.sin(s['ra']! - m['ra']!),
      math.sin(s['dec']!) * math.cos(m['dec']!) -
      math.cos(s['dec']!) * math.sin(m['dec']!) * math.cos(s['ra']! - m['ra']!)
    );

    return MoonIllumination(
      fraction: (1 + math.cos(inc)) / 2,
      phase: 0.5 + 0.5 * inc * (angle < 0 ? -1 : 1) / math.pi,
      angle: angle,
    );
  }

  /// Get moon rise and set times for a given date and location
  static MoonTimes getTimes(DateTime date, double lat, double lng) {
    // Start at midnight
    final t = DateTime.utc(date.year, date.month, date.day);

    const hc = 0.133 * _rad; // Moon apparent radius
    var h0 = getPosition(t, lat, lng).altitude - hc;

    DateTime? rise;
    DateTime? set;

    // Go through 24 hours in 2-hour steps
    for (var i = 1; i <= 24; i += 2) {
      final h1 = getPosition(t.add(Duration(hours: i)), lat, lng).altitude - hc;
      final h2 = getPosition(t.add(Duration(hours: i + 1)), lat, lng).altitude - hc;

      final a = (h0 + h2) / 2 - h1;
      final b = (h2 - h0) / 2;
      final xe = -b / (2 * a);
      final ye = (a * xe + b) * xe + h1;
      final d = b * b - 4 * a * h1;
      var roots = 0;
      double x1 = 0, x2 = 0;

      if (d >= 0) {
        final dx = math.sqrt(d) / (a.abs() * 2);
        x1 = xe - dx;
        x2 = xe + dx;
        if (x1.abs() <= 1) roots++;
        if (x2.abs() <= 1) roots++;
        if (x1 < -1) x1 = x2;
      }

      if (roots == 1) {
        if (h0 < 0) {
          rise = _hoursLater(t, i + x1);
        } else {
          set = _hoursLater(t, i + x1);
        }
      } else if (roots == 2) {
        rise = _hoursLater(t, i + (ye < 0 ? x2 : x1));
        set = _hoursLater(t, i + (ye < 0 ? x1 : x2));
      }

      if (rise != null && set != null) break;

      h0 = h2;
    }

    return MoonTimes(
      rise: rise,
      set: set,
      alwaysUp: rise == null && set == null && h0 > 0,
      alwaysDown: rise == null && set == null && h0 <= 0,
    );
  }

  static DateTime _hoursLater(DateTime date, double h) {
    return date.add(Duration(milliseconds: (h * 60 * 60 * 1000).round()));
  }
}
