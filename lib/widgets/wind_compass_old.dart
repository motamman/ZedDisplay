import 'dart:math';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

/// Display mode for wind compass
enum WindCompassMode {
  targetAWA,    // Performance steering - show target AWA zones
  laylines,     // Navigation - show laylines to waypoint
  vmg,          // VMG optimization - show velocity made good
  combined,     // Show both (future)
}

/// Simple polar data - maps true wind speed to optimal upwind angle
class SimplePolar {
  // Default polar for typical 30-40ft cruiser/racer
  static final Map<double, double> defaultUpwindAngles = {
    0.0: 45.0,    // No wind - wide angle
    5.0: 45.0,    // Light air (0-5 kts) - sail free for speed
    8.0: 42.0,    // Light-medium (5-8 kts) - tighten up
    12.0: 40.0,   // Medium (8-12 kts) - optimal pointing
    16.0: 38.0,   // Medium-heavy (12-16 kts) - can point higher
    20.0: 36.0,   // Heavy (16-20 kts) - flatten sails, point high
    25.0: 38.0,   // Very heavy (20-25 kts) - ease slightly for power
    30.0: 40.0,   // Storm (25+ kts) - sail for control
  };

  /// Get optimal upwind angle for given wind speed (linear interpolation)
  static double getOptimalAngle(double windSpeed, {Map<double, double>? customPolar}) {
    final polar = customPolar ?? defaultUpwindAngles;
    final speeds = polar.keys.toList()..sort();

    // Handle edge cases
    if (windSpeed <= speeds.first) return polar[speeds.first]!;
    if (windSpeed >= speeds.last) return polar[speeds.last]!;

    // Find bracketing values
    double lowerSpeed = speeds.first;
    double upperSpeed = speeds.last;

    for (int i = 0; i < speeds.length - 1; i++) {
      if (windSpeed >= speeds[i] && windSpeed <= speeds[i + 1]) {
        lowerSpeed = speeds[i];
        upperSpeed = speeds[i + 1];
        break;
      }
    }

    // Linear interpolation
    final lowerAngle = polar[lowerSpeed]!;
    final upperAngle = polar[upperSpeed]!;
    final ratio = (windSpeed - lowerSpeed) / (upperSpeed - lowerSpeed);

    return lowerAngle + (upperAngle - lowerAngle) * ratio;
  }
}

/// Wind compass gauge with full circle rotating card (autopilot style)
/// Shows heading (true/magnetic), wind direction (true/apparent), and SOG
class WindCompass extends StatefulWidget {
  // Heading values in radians (for rotation) and degrees (for display)
  final double? headingTrueRadians;
  final double? headingMagneticRadians;
  final double? headingTrueDegrees;
  final double? headingMagneticDegrees;

  // Wind direction values in radians (for rotation) and degrees (for display)
  final double? windDirectionTrueRadians;
  final double? windDirectionApparentRadians;
  final double? windDirectionTrueDegrees;
  final double? windDirectionApparentDegrees;

  // Raw apparent wind angle (relative to boat) - not converted to absolute direction
  final double? windAngleApparent;

  // Wind speed values
  final double? windSpeedTrue;
  final String? windSpeedTrueFormatted;
  final double? windSpeedApparent;
  final String? windSpeedApparentFormatted;

  final double? speedOverGround;
  final String? sogFormatted;
  final double? cogDegrees;

  // Waypoint navigation
  final double? waypointBearing;   // True bearing to waypoint (degrees)
  final double? waypointDistance;  // Distance to waypoint (meters)

  // Target AWA configuration
  final double targetAWA;          // Optimal close-hauled angle from polar data (degrees)
  final double targetTolerance;    // Acceptable deviation from target (degrees)
  final bool showAWANumbers;       // Show numeric AWA display with target comparison
  final bool enableVMG;            // Enable VMG optimization with polar-based target AWA

  const WindCompass({
    super.key,
    this.headingTrueRadians,
    this.headingMagneticRadians,
    this.headingTrueDegrees,
    this.headingMagneticDegrees,
    this.windDirectionTrueRadians,
    this.windDirectionApparentRadians,
    this.windDirectionTrueDegrees,
    this.windDirectionApparentDegrees,
    this.windAngleApparent,
    this.windSpeedTrue,
    this.windSpeedTrueFormatted,
    this.windSpeedApparent,
    this.windSpeedApparentFormatted,
    this.speedOverGround,
    this.sogFormatted,
    this.cogDegrees,
    this.waypointBearing,
    this.waypointDistance,
    this.targetAWA = 40.0,
    this.targetTolerance = 3.0,
    this.showAWANumbers = true,
    this.enableVMG = false,
  });

  @override
  State<WindCompass> createState() => _WindCompassState();
}

class _WindCompassState extends State<WindCompass> {
  bool _useTrueHeading = false; // Default to magnetic
  WindCompassMode _currentMode = WindCompassMode.targetAWA; // Default mode

  // Wind shift tracking
  final List<_WindSample> _windHistory = [];
  static const int _windHistoryDuration = 30; // Track last 30 seconds
  double? _baselineWindDirection; // Average wind direction for comparison

  @override
  void didUpdateWidget(WindCompass oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update wind history when true wind direction changes
    if (widget.windDirectionTrueDegrees != null &&
        widget.windDirectionTrueDegrees != oldWidget.windDirectionTrueDegrees) {
      _updateWindHistory(widget.windDirectionTrueDegrees!);
    }
  }

  /// Update wind history with new sample
  void _updateWindHistory(double windDirection) {
    final now = DateTime.now();
    _windHistory.add(_WindSample(windDirection, now));

    // Remove old samples
    final cutoff = now.subtract(const Duration(seconds: _windHistoryDuration));
    _windHistory.removeWhere((sample) => sample.timestamp.isBefore(cutoff));

    // Calculate baseline (average) wind direction
    if (_windHistory.length >= 5) {
      _baselineWindDirection = _calculateAverageWindDirection();
    }
  }

  /// Calculate average wind direction handling 0°/360° wraparound
  double _calculateAverageWindDirection() {
    if (_windHistory.isEmpty) return 0;

    // Use vector averaging to handle wraparound
    double sumSin = 0;
    double sumCos = 0;

    for (var sample in _windHistory) {
      final radians = sample.direction * pi / 180;
      sumSin += sin(radians);
      sumCos += cos(radians);
    }

    final avgRadians = atan2(sumSin / _windHistory.length, sumCos / _windHistory.length);
    double avgDegrees = avgRadians * 180 / pi;

    if (avgDegrees < 0) avgDegrees += 360;

    return avgDegrees;
  }

  /// Calculate wind shift from baseline
  /// Returns: positive = clockwise shift, negative = counter-clockwise shift
  double? _calculateWindShift() {
    if (_baselineWindDirection == null || widget.windDirectionTrueDegrees == null) {
      return null;
    }

    double shift = widget.windDirectionTrueDegrees! - _baselineWindDirection!;

    // Normalize to -180 to +180 range
    while (shift > 180) {
      shift -= 360;
    }
    while (shift < -180) {
      shift += 360;
    }

    return shift;
  }

  /// Determine if wind shift is a lift or header
  /// Returns: 'lift', 'header', or null
  String? _getShiftType(double shift) {
    if (shift.abs() < 3) {
      return null; // Shift too small to matter
    }

    // Calculate AWA to determine tack
    // Use raw AWA if available, otherwise calculate from absolute direction
    double? awa;
    if (widget.windAngleApparent != null) {
      // Use raw AWA value (already relative to boat, independent of true/magnetic)
      awa = widget.windAngleApparent!;
    } else if (widget.windDirectionApparentDegrees != null) {
      // Fallback: calculate from absolute direction (old method, has true/magnetic bug)
      final headingDegrees = widget.headingMagneticDegrees ?? widget.headingTrueDegrees;
      if (headingDegrees != null) {
        double tempAwa = widget.windDirectionApparentDegrees! - headingDegrees;
        while (tempAwa > 180) {
          tempAwa -= 360;
        }
        while (tempAwa < -180) {
          tempAwa += 360;
        }
        awa = tempAwa;
      }
    }

    if (awa == null) {
      return null; // No AWA data available
    }

    // Only show lift/header when sailing upwind (AWA < 90°)
    if (awa.abs() > 90) {
      return null;
    }

    final isPortTack = awa < 0;

    // Port tack: clockwise shift (+) = lift, counter-clockwise (-) = header
    // Starboard tack: counter-clockwise (-) = lift, clockwise (+) = header
    if (isPortTack) {
      return shift > 0 ? 'lift' : 'header';
    } else {
      return shift < 0 ? 'lift' : 'header';
    }
  }

  /// Normalize angle to 0-360 range
  double _normalizeAngle(double angle) {
    while (angle < 0) {
      angle += 360;
    }
    while (angle >= 360) {
      angle -= 360;
    }
    return angle;
  }

  /// Build sailing zones that handle 0°/360° wraparound
  /// Uses configurable targetAWA (or dynamic polar-based target if VMG enabled)
  List<GaugeRange> _buildSailingZones(double windDegrees) {
    final zones = <GaugeRange>[];

    // Use dynamic target AWA if VMG mode enabled
    final effectiveTargetAWA = _getOptimalTargetAWA();

    // Helper to add a range, splitting if it crosses 0°
    void addRange(double start, double end, Color color, {double width = 25}) {
      final startNorm = _normalizeAngle(start);
      final endNorm = _normalizeAngle(end);

      if (startNorm < endNorm) {
        // Normal case: doesn't cross 0°
        zones.add(GaugeRange(
          startValue: startNorm,
          endValue: endNorm,
          color: color,
          startWidth: width,
          endWidth: width,
        ));
      } else {
        // Crosses 0°: split into two ranges
        zones.add(GaugeRange(
          startValue: startNorm,
          endValue: 360,
          color: color,
          startWidth: width,
          endWidth: width,
        ));
        zones.add(GaugeRange(
          startValue: 0,
          endValue: endNorm,
          color: color,
          startWidth: width,
          endWidth: width,
        ));
      }
    }

    // GRADIATED ZONES - darker near close-hauled, lighter toward downwind

    // PORT SIDE - Gradiated Red Zones (darker = more important)
    // Zone 1: Close-hauled (target to 60°) - darkest
    addRange(windDegrees - 60, windDegrees - effectiveTargetAWA, Colors.red.withValues(alpha: 0.6));
    // Zone 2: Close reach (60° to 90°) - medium
    addRange(windDegrees - 90, windDegrees - 60, Colors.red.withValues(alpha: 0.4));
    // Zone 3: Beam reach (90° to 110°) - lighter
    addRange(windDegrees - 110, windDegrees - 90, Colors.red.withValues(alpha: 0.25));
    // Zone 4: Broad reach/run (110° to 150°) - lightest
    addRange(windDegrees - 150, windDegrees - 110, Colors.red.withValues(alpha: 0.15));

    // No-go zone (wind ± targetAWA)
    addRange(windDegrees - effectiveTargetAWA, windDegrees + effectiveTargetAWA, Colors.white.withValues(alpha: 0.3));

    // STARBOARD SIDE - Gradiated Green Zones (darker = more important)
    // Zone 1: Close-hauled (target to 60°) - darkest
    addRange(windDegrees + effectiveTargetAWA, windDegrees + 60, Colors.green.withValues(alpha: 0.6));
    // Zone 2: Close reach (60° to 90°) - medium
    addRange(windDegrees + 60, windDegrees + 90, Colors.green.withValues(alpha: 0.4));
    // Zone 3: Beam reach (90° to 110°) - lighter
    addRange(windDegrees + 90, windDegrees + 110, Colors.green.withValues(alpha: 0.25));
    // Zone 4: Broad reach/run (110° to 150°) - lightest
    addRange(windDegrees + 110, windDegrees + 150, Colors.green.withValues(alpha: 0.15));

    // PERFORMANCE ZONES - layer on top with narrower width to show as inner rings
    final target = effectiveTargetAWA;
    final tolerance = widget.targetTolerance;

    // PORT SIDE PERFORMANCE ZONES
    // Optimal green zone: target ± tolerance (e.g., 40° ± 3° = 37-43°)
    addRange(windDegrees - target - tolerance, windDegrees - target + tolerance,
             Colors.green.withValues(alpha: 0.8), width: 15);

    // Acceptable yellow zones: tolerance to 2×tolerance
    addRange(windDegrees - target - (2 * tolerance), windDegrees - target - tolerance,
             Colors.yellow.withValues(alpha: 0.7), width: 15);
    addRange(windDegrees - target + tolerance, windDegrees - target + (2 * tolerance),
             Colors.yellow.withValues(alpha: 0.7), width: 15);

    // STARBOARD SIDE PERFORMANCE ZONES
    // Optimal green zone: target ± tolerance
    addRange(windDegrees + target - tolerance, windDegrees + target + tolerance,
             Colors.green.withValues(alpha: 0.8), width: 15);

    // Acceptable yellow zones: tolerance to 2×tolerance
    addRange(windDegrees + target - (2 * tolerance), windDegrees + target - tolerance,
             Colors.yellow.withValues(alpha: 0.7), width: 15);
    addRange(windDegrees + target + tolerance, windDegrees + target + (2 * tolerance),
             Colors.yellow.withValues(alpha: 0.7), width: 15);

    return zones;
  }

  /// Cycle through display modes
  void _cycleMode() {
    setState(() {
      switch (_currentMode) {
        case WindCompassMode.targetAWA:
          // Switch to VMG if enabled, otherwise laylines, otherwise stay
          if (widget.enableVMG && widget.windSpeedTrue != null) {
            _currentMode = WindCompassMode.vmg;
          } else if (widget.waypointBearing != null) {
            _currentMode = WindCompassMode.laylines;
          }
          break;
        case WindCompassMode.vmg:
          // Switch to laylines if available, otherwise back to target AWA
          if (widget.waypointBearing != null) {
            _currentMode = WindCompassMode.laylines;
          } else {
            _currentMode = WindCompassMode.targetAWA;
          }
          break;
        case WindCompassMode.laylines:
          _currentMode = WindCompassMode.targetAWA;
          break;
        case WindCompassMode.combined:
          _currentMode = WindCompassMode.targetAWA;
          break;
      }
    });
  }

  /// Calculate VMG (Velocity Made Good) toward wind
  /// VMG = SOG × cos(angle between COG and true wind direction)
  double? _calculateVMG() {
    if (widget.speedOverGround == null || widget.cogDegrees == null || widget.windDirectionTrueDegrees == null) {
      return null;
    }

    // Calculate angle between COG and wind direction
    double angleToWind = (widget.cogDegrees! - widget.windDirectionTrueDegrees!).abs();

    // Normalize to 0-180 range
    if (angleToWind > 180) {
      angleToWind = 360 - angleToWind;
    }

    // VMG = SOG × cos(angle)
    final vmg = widget.speedOverGround! * cos(angleToWind * pi / 180);

    return vmg;
  }

  /// Get optimal target AWA based on current wind speed (if VMG mode enabled)
  double _getOptimalTargetAWA() {
    if (!widget.enableVMG || widget.windSpeedTrue == null) {
      return widget.targetAWA;
    }

    return SimplePolar.getOptimalAngle(widget.windSpeedTrue!);
  }

  /// Build AWA performance display showing current vs target (tappable to change modes)
  Widget _buildAWAPerformanceDisplay(double headingDegrees) {
    // Calculate AWA (Apparent Wind Angle) - relative to boat
    // Use raw AWA if available, otherwise calculate from absolute direction
    double awa;
    if (widget.windAngleApparent != null) {
      // Use raw AWA value (already relative to boat, independent of true/magnetic)
      awa = widget.windAngleApparent!;
    } else {
      // Fallback: calculate from absolute direction (old method, has true/magnetic bug)
      final windDirection = widget.windDirectionApparentDegrees!;
      awa = windDirection - headingDegrees;
    }

    // Normalize to -180 to +180 range
    while (awa > 180) {
      awa -= 360;
    }
    while (awa < -180) {
      awa += 360;
    }

    // Get optimal target AWA (dynamic if VMG mode enabled)
    final currentTargetAWA = _getOptimalTargetAWA();

    // Get absolute AWA for comparison with target
    final absAWA = awa.abs();
    final diff = absAWA - currentTargetAWA;
    final absDiff = diff.abs();

    // Determine status color and text
    Color statusColor;
    String statusText;

    if (absDiff <= widget.targetTolerance) {
      statusColor = Colors.green;
      statusText = 'OPTIMAL';
    } else if (absDiff <= widget.targetTolerance * 2) {
      statusColor = Colors.yellow;
      statusText = diff > 0 ? 'HIGH' : 'LOW';
    } else {
      statusColor = Colors.red;
      statusText = diff > 0 ? 'TOO HIGH' : 'TOO LOW';
    }

    // Build content based on mode
    Widget content;
    String modeLabel;

    if (_currentMode == WindCompassMode.targetAWA) {
      modeLabel = 'AWA MODE';
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'AWA: ',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
              Text(
                '${absAWA.toStringAsFixed(0)}°',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(${awa > 0 ? "STBD" : "PORT"})',
                style: TextStyle(
                  fontSize: 10,
                  color: awa > 0 ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'TGT: ${currentTargetAWA.toStringAsFixed(0)}°',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white60,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${diff > 0 ? '+' : ''}${diff.toStringAsFixed(1)}° $statusText',
                style: TextStyle(
                  fontSize: 11,
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      );
    } else if (_currentMode == WindCompassMode.vmg) {
      // VMG mode
      modeLabel = 'VMG MODE';
      content = _buildVMGDisplay(headingDegrees);
    } else {
      // Laylines mode
      modeLabel = 'LAYLINES';
      content = _buildLaylinesDisplay(headingDegrees);
    }

    return Positioned(
      top: 35,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: _cycleMode,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColor, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  modeLabel,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white38,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                content,
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build VMG display showing velocity made good performance
  Widget _buildVMGDisplay(double headingDegrees) {
    final vmg = _calculateVMG();
    final currentTargetAWA = _getOptimalTargetAWA();
    final tws = widget.windSpeedTrue;

    if (vmg == null || tws == null) {
      return const Text(
        'NO VMG DATA',
        style: TextStyle(
          fontSize: 12,
          color: Colors.white60,
        ),
      );
    }

    // Calculate AWA for status
    // Use raw AWA if available, otherwise calculate from absolute direction
    double? awa;
    if (widget.windAngleApparent != null) {
      // Use raw AWA value (already relative to boat, independent of true/magnetic)
      awa = widget.windAngleApparent!;
    } else if (widget.windDirectionApparentDegrees != null) {
      // Fallback: calculate from absolute direction (old method, has true/magnetic bug)
      double tempAwa = widget.windDirectionApparentDegrees! - headingDegrees;
      while (tempAwa > 180) {
        tempAwa -= 360;
      }
      while (tempAwa < -180) {
        tempAwa += 360;
      }
      awa = tempAwa;
    }

    // Determine performance color
    Color vmgColor = Colors.green;
    if (vmg < 0) {
      vmgColor = Colors.red; // Going downwind
    } else if (vmg < (widget.speedOverGround ?? 0) * 0.5) {
      vmgColor = Colors.yellow; // Poor VMG
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // VMG value
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'VMG: ',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
            Text(
              vmg.abs().toStringAsFixed(2),
              style: TextStyle(
                fontSize: 20,
                color: vmgColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              widget.sogFormatted != null ? widget.sogFormatted!.replaceAll(RegExp(r'[\d.]+'), '') : 'kts',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white60,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Wind speed and optimal angle
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'TWS: ${tws.toStringAsFixed(1)} →',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white60,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'OPT: ${currentTargetAWA.toStringAsFixed(0)}°',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        // Current AWA if available
        if (awa != null) ...[
          const SizedBox(height: 2),
          Text(
            'AWA: ${awa.abs().toStringAsFixed(0)}° (${awa > 0 ? "STBD" : "PORT"})',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ],
    );
  }

  /// Build wind shift indicator showing lift/header
  Widget _buildWindShiftIndicator() {
    final shift = _calculateWindShift();
    if (shift == null || shift.abs() < 3) {
      return const SizedBox.shrink(); // No significant shift
    }

    final shiftType = _getShiftType(shift);
    if (shiftType == null) {
      return const SizedBox.shrink(); // Not sailing upwind or shift too small
    }

    final isLift = shiftType == 'lift';
    final shiftColor = isLift ? Colors.green : Colors.red;
    final shiftIcon = isLift ? Icons.arrow_upward : Icons.arrow_downward;
    final shiftLabel = isLift ? 'LIFT' : 'HEADER';

    // Position inside compass rim on the right side
    // Using a fixed offset that works well for typical compass sizes
    return Positioned(
      right: 80,
      top: 0,
      bottom: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            border: Border.all(color: shiftColor, width: 2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                shiftIcon,
                color: shiftColor,
                size: 24,
              ),
              const SizedBox(height: 2),
              Text(
                shiftLabel,
                style: TextStyle(
                  fontSize: 10,
                  color: shiftColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${shift.abs().toStringAsFixed(0)}°',
                style: TextStyle(
                  fontSize: 14,
                  color: shiftColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build laylines display showing navigation to waypoint
  Widget _buildLaylinesDisplay(double headingDegrees) {
    if (widget.waypointBearing == null) {
      return const Text(
        'NO WAYPOINT',
        style: TextStyle(
          fontSize: 12,
          color: Colors.white60,
        ),
      );
    }

    // For navigation calculations, use COG (actual track) with true heading fallback
    // This keeps calculations in true coordinate system and accounts for current/leeway
    final navigationCourse = widget.cogDegrees ?? widget.headingTrueDegrees ?? widget.headingMagneticDegrees ?? headingDegrees;

    // Calculate True Wind Direction (TWD)
    // TWD = Heading + TWA (true wind angle relative to boat)
    final twd = widget.windDirectionTrueDegrees ?? navigationCourse;

    // Calculate laylines: TWD ± optimal angle
    final portLayline = _normalizeAngle(twd + widget.targetAWA);
    final stbdLayline = _normalizeAngle(twd - widget.targetAWA);

    final waypointBearing = widget.waypointBearing!;

    // Determine if waypoint is fetchable on each tack
    final canFetchPort = _isAngleBetween(waypointBearing, portLayline, twd);
    final canFetchStbd = _isAngleBetween(waypointBearing, twd, stbdLayline);

    // Calculate tack angles using actual navigation course (COG preferred)
    final portTackAngle = _angleDifference(navigationCourse, portLayline);
    final stbdTackAngle = _angleDifference(navigationCourse, stbdLayline);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'WPT: ${waypointBearing.toStringAsFixed(0)}°',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (widget.waypointDistance != null) ...[
              const SizedBox(width: 8),
              Text(
                '${(widget.waypointDistance! / 1852).toStringAsFixed(1)}nm',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white60,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Port tack
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: canFetchPort ? Colors.green.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'PORT ${portTackAngle.abs().toStringAsFixed(0)}°',
                style: TextStyle(
                  fontSize: 10,
                  color: canFetchPort ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Starboard tack
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: canFetchStbd ? Colors.green.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'STBD ${stbdTackAngle.abs().toStringAsFixed(0)}°',
                style: TextStyle(
                  fontSize: 10,
                  color: canFetchStbd ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Check if angle is between two other angles (handles wraparound)
  bool _isAngleBetween(double angle, double start, double end) {
    angle = _normalizeAngle(angle);
    start = _normalizeAngle(start);
    end = _normalizeAngle(end);

    if (start <= end) {
      return angle >= start && angle <= end;
    } else {
      return angle >= start || angle <= end;
    }
  }

  /// Calculate signed difference between two angles
  double _angleDifference(double from, double to) {
    double diff = to - from;
    while (diff > 180) {
      diff -= 360;
    }
    while (diff < -180) {
      diff += 360;
    }
    return diff;
  }

  /// Build compass labels (N, S, E, W, degrees) as gauge annotations
  /// Labels are positioned at their angle on the rotating gauge
  List<GaugeAnnotation> _buildCompassLabels() {
    final labels = <GaugeAnnotation>[];

    for (int i = 0; i < 360; i += 30) {
      String label;
      Color labelColor;
      double fontSize;

      switch (i) {
        case 0:
          label = 'N';
          labelColor = Colors.white;
          fontSize = 24;
          break;
        case 90:
          label = 'E';
          labelColor = Colors.white70;
          fontSize = 20;
          break;
        case 180:
          label = 'S';
          labelColor = Colors.white70;
          fontSize = 20;
          break;
        case 270:
          label = 'W';
          labelColor = Colors.white70;
          fontSize = 20;
          break;
        default:
          label = i.toString();
          labelColor = Colors.white60;
          fontSize = 16;
      }

      labels.add(
        GaugeAnnotation(
          widget: Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: fontSize,
              fontWeight: i == 0 || i % 90 == 0 ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          angle: i.toDouble(),
          positionFactor: 0.85,
        ),
      );
    }

    return labels;
  }

  @override
  Widget build(BuildContext context) {
    // Use radians for rotation based on user selection
    final primaryHeadingRadians = _useTrueHeading
        ? (widget.headingTrueRadians ?? widget.headingMagneticRadians ?? 0.0)
        : (widget.headingMagneticRadians ?? widget.headingTrueRadians ?? 0.0);

    // Use degrees for display based on user selection
    final primaryHeadingDegrees = _useTrueHeading
        ? (widget.headingTrueDegrees ?? widget.headingMagneticDegrees ?? 0.0)
        : (widget.headingMagneticDegrees ?? widget.headingTrueDegrees ?? 0.0);

    // Use apparent wind for primary wind direction (for no-go zones)
    final primaryWindDegrees = widget.windDirectionApparentDegrees ?? widget.windDirectionTrueDegrees;

    final headingMode = _useTrueHeading ? 'True' : 'Mag';

    return AspectRatio(
      aspectRatio: 1.0,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // Vessel shadow - LOWEST LAYER - FIXED pointing up (not rotating with compass)
              Positioned.fill(
                child: CustomPaint(
                  painter: VesselShadowPainter(),
                ),
              ),

              // No-go zone - LAYER 2 - rotates with compass, below wind/heading pointers
              if (primaryWindDegrees != null)
                Positioned.fill(
                  child: Transform.rotate(
                    angle: -primaryHeadingRadians - (3.14159265359 / 2),
                    child: CustomPaint(
                      painter: NoGoZoneVPainter(
                        windAngle: primaryWindDegrees,
                        headingAngle: primaryHeadingDegrees,
                        noGoAngle: _getOptimalTargetAWA(), // Use dynamic target AWA
                      ),
                    ),
                  ),
                ),

              // Main compass gauge (full circle) - LAYER 3 - wrapped in Transform.rotate
              Transform.rotate(
                angle: -primaryHeadingRadians - (3.14159265359 / 2),  // Rotation minus 90° to compensate
                child: SfRadialGauge(
                  axes: <RadialAxis>[
                    RadialAxis(
                      // Full circle
                      startAngle: 0,
                      endAngle: 360,
                    minimum: 0,
                    maximum: 360,
                    interval: 30,

                    // Configure the axis appearance
                    showAxisLine: false,
                    showLastLabel: false,
                    showLabels: false, // Hide auto-generated labels, we'll add our own

                    // Tick configuration
                    minorTicksPerInterval: 2,
                    majorTickStyle: const MajorTickStyle(
                      length: 15,
                      thickness: 2,
                      color: Colors.white70,
                    ),
                    minorTickStyle: const MinorTickStyle(
                      length: 8,
                      thickness: 1,
                      color: Colors.white30,
                    ),

                    // Sailing zones: red (port tack), no-go, green (starboard tack)
                    ranges: <GaugeRange>[
                      if (primaryWindDegrees != null)
                        ..._buildSailingZones(primaryWindDegrees),
                    ],

                    // Pointers for wind, heading, and COG (drawn in order: first = bottom, last = top)
                    pointers: <GaugePointer>[
                      // HEADING INDICATORS - LAYER 1 (above no-go zone, below wind)
                      // Yellow for true heading
                      if (!_useTrueHeading && widget.headingTrueDegrees != null)
                        NeedlePointer(
                          value: widget.headingTrueDegrees!,
                          needleLength: 0.92,  // Slightly shorter so rounded end fits
                          needleStartWidth: 0,
                          needleEndWidth: 10,  // Twice as wide as dominant wind (5 * 2)
                          needleColor: Colors.yellow,
                          knobStyle: const KnobStyle(
                            knobRadius: 0,
                          ),
                        ),
                      // Rounded end for yellow heading indicator - always visible at edge
                      if (widget.headingTrueDegrees != null)
                        MarkerPointer(
                          value: widget.headingTrueDegrees!,
                          markerType: MarkerType.circle,
                          markerHeight: 16,
                          markerWidth: 16,
                          color: Colors.yellow,
                          markerOffset: -5, // Position at outer edge of compass
                        ),

                      // Orange for magnetic heading
                      if (_useTrueHeading && widget.headingMagneticDegrees != null)
                        NeedlePointer(
                          value: widget.headingMagneticDegrees!,
                          needleLength: 0.92,  // Slightly shorter so rounded end fits
                          needleStartWidth: 0,
                          needleEndWidth: 10,  // Twice as wide as dominant wind (5 * 2)
                          needleColor: Colors.orange,
                          knobStyle: const KnobStyle(
                            knobRadius: 0,
                          ),
                        ),
                      // Rounded end for orange heading indicator - always visible at edge
                      if (widget.headingMagneticDegrees != null)
                        MarkerPointer(
                          value: widget.headingMagneticDegrees!,
                          markerType: MarkerType.circle,
                          markerHeight: 16,
                          markerWidth: 16,
                          color: Colors.orange,
                          markerOffset: -5, // Position at outer edge of compass
                        ),

                      // COG (Course Over Ground)
                      if (widget.cogDegrees != null)
                        NeedlePointer(
                          value: widget.cogDegrees!,
                          needleLength: 0.60,  // Slightly shorter so rounded end fits
                          needleStartWidth: 0,
                          needleEndWidth: 6,
                          needleColor: Colors.white,
                          knobStyle: const KnobStyle(
                            knobRadius: 0,
                          ),
                        ),
                      // Rounded end for COG indicator
                      if (widget.cogDegrees != null)
                        MarkerPointer(
                          value: widget.cogDegrees!,
                          markerType: MarkerType.circle,
                          markerHeight: 10,
                          markerWidth: 10,
                          color: Colors.white,
                          markerOffset: -5, // Position at outer edge of compass
                        ),

                      // LAYLINES - show when in laylines mode
                      if (_currentMode == WindCompassMode.laylines && widget.waypointBearing != null && widget.windDirectionTrueDegrees != null) ...[
                        // Port layline
                        NeedlePointer(
                          value: _normalizeAngle(widget.windDirectionTrueDegrees! + widget.targetAWA),
                          needleLength: 0.85,
                          needleStartWidth: 0,
                          needleEndWidth: 4,
                          needleColor: Colors.purple,
                          knobStyle: const KnobStyle(
                            knobRadius: 0,
                          ),
                        ),
                        // Starboard layline
                        NeedlePointer(
                          value: _normalizeAngle(widget.windDirectionTrueDegrees! - widget.targetAWA),
                          needleLength: 0.85,
                          needleStartWidth: 0,
                          needleEndWidth: 4,
                          needleColor: Colors.purple,
                          knobStyle: const KnobStyle(
                            knobRadius: 0,
                          ),
                        ),
                        // Waypoint bearing indicator
                        NeedlePointer(
                          value: widget.waypointBearing!,
                          needleLength: 0.90,
                          needleStartWidth: 0,
                          needleEndWidth: 6,
                          needleColor: Colors.yellow,
                          knobStyle: const KnobStyle(
                            knobRadius: 0,
                          ),
                        ),
                      ],

                      // WIND INDICATORS - LAYER 2 (above heading indicators)
                      // Apparent wind - primary
                      if (widget.windDirectionApparentDegrees != null)
                        NeedlePointer(
                          value: widget.windDirectionApparentDegrees!,
                          needleLength: 0.95,
                          needleStartWidth: 5,
                          needleEndWidth: 0,
                          needleColor: Colors.blue,
                          knobStyle: const KnobStyle(
                            knobRadius: 0.03,
                            color: Colors.blue,
                          ),
                        ),

                      // True wind direction marker - secondary
                      if (widget.windDirectionTrueDegrees != null)
                        NeedlePointer(
                          value: widget.windDirectionTrueDegrees!,
                          needleLength: 0.75,
                          needleStartWidth: 4,
                          needleEndWidth: 0,
                          needleColor: Colors.green,
                          knobStyle: const KnobStyle(
                            knobRadius: 0.025,
                            color: Colors.green,
                          ),
                        ),
                    ],

                    // Annotations - compass labels
                    annotations: _buildCompassLabels(),
                  ),
                ],
                ),
              ),

              // AWA Performance Display - shows current vs target
              if (widget.showAWANumbers && widget.windDirectionApparentDegrees != null)
                _buildAWAPerformanceDisplay(primaryHeadingDegrees),

              // Wind shift indicator (lift/header)
              _buildWindShiftIndicator(),

              // Center display with heading (use degrees) - moved down
              Positioned.fill(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 90), // Push content down more
                      // Large heading display
                      Text(
                        '${primaryHeadingDegrees.toStringAsFixed(0)}°',
                        style: const TextStyle(
                          fontSize: 56,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      // Mode indicator (Mag/True)
                      Text(
                        headingMode,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // White circle in the center - HIGHEST LAYER - above everything
              Positioned.fill(
                child: Center(
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),

              // HDG True (top left) - tap to switch to true heading
              if (widget.headingTrueDegrees != null)
                Positioned(
                  left: 16,
                  top: 40,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _useTrueHeading = true;
                      });
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                color: Colors.yellow,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'HDG',
                              style: TextStyle(
                                fontSize: 12,
                                color: _useTrueHeading ? Colors.white : Colors.white60,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${widget.headingTrueDegrees!.toStringAsFixed(0)}°T',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.white,
                            fontWeight: _useTrueHeading ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // HDG Magnetic (top right) - tap to switch to magnetic heading
              if (widget.headingMagneticDegrees != null)
                Positioned(
                  right: 16,
                  top: 40,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _useTrueHeading = false;
                      });
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'HDG',
                              style: TextStyle(
                                fontSize: 12,
                                color: !_useTrueHeading ? Colors.white : Colors.white60,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                color: Colors.orange,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${widget.headingMagneticDegrees!.toStringAsFixed(0)}°M',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.white,
                            fontWeight: !_useTrueHeading ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // True Wind Direction (bottom left)
              if (widget.windDirectionTrueDegrees != null)
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'TWD',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${widget.windDirectionTrueDegrees!.toStringAsFixed(0)}°',
                        style: const TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      // True Wind Speed
                      if (widget.windSpeedTrue != null || widget.windSpeedTrueFormatted != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TWS',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white60,
                              ),
                            ),
                            Text(
                              widget.windSpeedTrueFormatted ?? widget.windSpeedTrue!.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

              // Apparent Wind Direction (bottom right)
              if (widget.windDirectionApparentDegrees != null)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'AWD',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${widget.windDirectionApparentDegrees!.toStringAsFixed(0)}°',
                        style: const TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      // Apparent Wind Speed
                      if (widget.windSpeedApparent != null || widget.windSpeedApparentFormatted != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'AWS',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white60,
                              ),
                            ),
                            Text(
                              widget.windSpeedApparentFormatted ?? widget.windSpeedApparent!.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

              // Speed Over Ground and COG (bottom center) - always shown
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // SOG
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'SOG',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white60,
                            ),
                          ),
                          Text(
                            widget.speedOverGround != null
                                ? (widget.sogFormatted ?? widget.speedOverGround!.toStringAsFixed(1))
                                : '--',
                            style: const TextStyle(
                              fontSize: 24,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      // Spacing between SOG and COG
                      const SizedBox(width: 24),

                      // COG
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'COG',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white60,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            widget.cogDegrees != null
                                ? '${widget.cogDegrees!.toStringAsFixed(0)}°'
                                : '--',
                            style: const TextStyle(
                              fontSize: 20,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Custom painter for the V-shaped no-go zone indicator
class NoGoZoneVPainter extends CustomPainter {
  final double windAngle;
  final double headingAngle;
  final double noGoAngle; // Target AWA angle from wind direction

  NoGoZoneVPainter({
    required this.windAngle,
    required this.headingAngle,
    this.noGoAngle = 40.0, // Default to 40° if not specified
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 * 0.85; // 85% of radius to stay within compass

    // windAngle is in compass coordinates (0-360°)
    // The SfRadialGauge has startAngle: 0, endAngle: 360
    // In gauge's natural coordinate system: 0° is at 3 o'clock (right)
    // The gauge value maps directly to this angle system
    // Since we're inside the gauge as an annotation, we use the same system

    // Convert gauge value to canvas radians (value in degrees -> radians)
    // In gauge's natural coords: value 0 = 0° = 3 o'clock position
    final windRad = windAngle * pi / 180;
    final noGoRad = noGoAngle * pi / 180;

    // Calculate the V-shape edges centered on wind direction
    final leftAngle = windRad - noGoRad;  // -45° from wind direction

    // Create path for V-shape
    final path = Path();
    path.moveTo(center.dx, center.dy); // Start at center

    // Left edge of V
    path.lineTo(
      center.dx + radius * cos(leftAngle),
      center.dy + radius * sin(leftAngle),
    );

    // Arc along the perimeter from left to right edge
    path.arcTo(
      Rect.fromCircle(center: center, radius: radius),
      leftAngle,
      2 * noGoRad,  // Sweep angle: from -45° to +45° (total 90°)
      false,
    );

    // Right edge back to center
    path.lineTo(center.dx, center.dy);

    // Close the path
    path.close();

    // Draw the V-shape with 50% opacity grey
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(NoGoZoneVPainter oldDelegate) {
    return oldDelegate.windAngle != windAngle ||
           oldDelegate.headingAngle != headingAngle ||
           oldDelegate.noGoAngle != noGoAngle;  // Must repaint when target AWA changes
  }
}

/// Custom painter for vessel shadow
class VesselShadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = size.width / 200; // Increased scale (was 400, now 200 = 2x larger)

    // Create boat shape pointing up (will be rotated by heading)
    final path = Path();

    // Bow (front point) - made much longer
    path.moveTo(center.dx, center.dy - 60 * scale);

    // Port side (left) - made wider
    path.lineTo(center.dx - 30 * scale, center.dy + 40 * scale);

    // Stern (back) - made wider
    path.lineTo(center.dx - 16 * scale, center.dy + 50 * scale);
    path.lineTo(center.dx + 16 * scale, center.dy + 50 * scale);

    // Starboard side (right) - made wider
    path.lineTo(center.dx + 30 * scale, center.dy + 40 * scale);

    // Back to bow
    path.close();

    // Draw vessel shadow with semi-transparent black
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);

    // Optional: Add a subtle outline
    final outlinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    canvas.drawPath(path, outlinePaint);
  }

  @override
  bool shouldRepaint(VesselShadowPainter oldDelegate) => false;
}

/// Wind sample for tracking historical wind direction
class _WindSample {
  final double direction;
  final DateTime timestamp;

  _WindSample(this.direction, this.timestamp);
}
