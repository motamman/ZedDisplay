import 'dart:math';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'base_compass.dart';

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

/// Wind compass gauge with full circle rotating card
/// Built on BaseCompass with wind-specific features
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
  final bool isSailingVessel;      // Whether vessel is sailing type (shows sail trim indicator)

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
    this.isSailingVessel = true,
  });

  @override
  State<WindCompass> createState() => _WindCompassState();
}

class _WindCompassState extends State<WindCompass> {
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
    final cutoff = now.subtract(Duration(seconds: _windHistoryDuration));
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
  String? _getShiftType(double shift) {
    if (shift.abs() < 3) {
      return null; // Shift too small to matter
    }

    // Calculate AWA to determine tack
    double? awa;
    if (widget.windAngleApparent != null) {
      awa = widget.windAngleApparent!;
    } else if (widget.windDirectionApparentDegrees != null) {
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
      return null;
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

  /// Get optimal target AWA based on current wind speed (if VMG mode enabled)
  double _getOptimalTargetAWA() {
    if (!widget.enableVMG || widget.windSpeedTrue == null) {
      return widget.targetAWA;
    }

    return SimplePolar.getOptimalAngle(widget.windSpeedTrue!);
  }

  /// Build sailing zones that handle 0°/360° wraparound
  List<GaugeRange> _buildSailingZones(double primaryHeadingDegrees) {
    final primaryWindDegrees = widget.windDirectionApparentDegrees ?? widget.windDirectionTrueDegrees;
    if (primaryWindDegrees == null) return [];

    final zones = <GaugeRange>[];
    final effectiveTargetAWA = _getOptimalTargetAWA();

    // Helper to add a range, splitting if it crosses 0°
    void addRange(double start, double end, Color color, {double width = 25}) {
      final startNorm = _normalizeAngle(start);
      final endNorm = _normalizeAngle(end);

      if (startNorm < endNorm) {
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

    // PORT SIDE - Gradiated Red Zones
    addRange(primaryWindDegrees - 60, primaryWindDegrees - effectiveTargetAWA, Colors.red.withValues(alpha: 0.6));
    addRange(primaryWindDegrees - 90, primaryWindDegrees - 60, Colors.red.withValues(alpha: 0.4));
    addRange(primaryWindDegrees - 110, primaryWindDegrees - 90, Colors.red.withValues(alpha: 0.25));
    addRange(primaryWindDegrees - 150, primaryWindDegrees - 110, Colors.red.withValues(alpha: 0.15));

    // No-go zone
    addRange(primaryWindDegrees - effectiveTargetAWA, primaryWindDegrees + effectiveTargetAWA, Colors.white.withValues(alpha: 0.3));

    // STARBOARD SIDE - Gradiated Green Zones
    addRange(primaryWindDegrees + effectiveTargetAWA, primaryWindDegrees + 60, Colors.green.withValues(alpha: 0.6));
    addRange(primaryWindDegrees + 60, primaryWindDegrees + 90, Colors.green.withValues(alpha: 0.4));
    addRange(primaryWindDegrees + 90, primaryWindDegrees + 110, Colors.green.withValues(alpha: 0.25));
    addRange(primaryWindDegrees + 110, primaryWindDegrees + 150, Colors.green.withValues(alpha: 0.15));

    // PERFORMANCE ZONES
    final target = effectiveTargetAWA;
    final tolerance = widget.targetTolerance;

    // PORT SIDE PERFORMANCE ZONES
    addRange(primaryWindDegrees - target - tolerance, primaryWindDegrees - target + tolerance,
             Colors.green.withValues(alpha: 0.8), width: 15);
    addRange(primaryWindDegrees - target - (2 * tolerance), primaryWindDegrees - target - tolerance,
             Colors.yellow.withValues(alpha: 0.7), width: 15);
    addRange(primaryWindDegrees - target + tolerance, primaryWindDegrees - target + (2 * tolerance),
             Colors.yellow.withValues(alpha: 0.7), width: 15);

    // STARBOARD SIDE PERFORMANCE ZONES
    addRange(primaryWindDegrees + target - tolerance, primaryWindDegrees + target + tolerance,
             Colors.green.withValues(alpha: 0.8), width: 15);
    addRange(primaryWindDegrees + target - (2 * tolerance), primaryWindDegrees + target - tolerance,
             Colors.yellow.withValues(alpha: 0.7), width: 15);
    addRange(primaryWindDegrees + target + tolerance, primaryWindDegrees + target + (2 * tolerance),
             Colors.yellow.withValues(alpha: 0.7), width: 15);

    return zones;
  }

  /// Build wind pointers
  List<GaugePointer> _buildWindPointers(double primaryHeadingDegrees) {
    final pointers = <GaugePointer>[];

    // Determine which heading is primary (being used for compass rotation)
    final isPrimaryTrue = widget.headingTrueDegrees != null &&
                          (widget.headingTrueDegrees! - primaryHeadingDegrees).abs() < 0.5;
    final isPrimaryMagnetic = widget.headingMagneticDegrees != null &&
                              (widget.headingMagneticDegrees! - primaryHeadingDegrees).abs() < 0.5;

    // HEADING INDICATORS
    // True heading - only show needle if NOT primary (vessel shadow shows primary)
    if (widget.headingTrueDegrees != null) {
      // Only show needle for non-primary heading
      if (!isPrimaryTrue) {
        pointers.add(NeedlePointer(
          value: widget.headingTrueDegrees!,
          needleLength: 0.92,
          needleStartWidth: 0,
          needleEndWidth: 10,
          needleColor: Colors.yellow,
          knobStyle: const KnobStyle(knobRadius: 0),
        ));
      }

      // Always show dot
      pointers.add(MarkerPointer(
        value: widget.headingTrueDegrees!,
        markerType: MarkerType.circle,
        markerHeight: 16,
        markerWidth: 16,
        color: Colors.yellow,
        markerOffset: -5,
      ));
    }

    // Magnetic heading - only show needle if NOT primary (vessel shadow shows primary)
    if (widget.headingMagneticDegrees != null) {
      // Only show needle for non-primary heading
      if (!isPrimaryMagnetic) {
        pointers.add(NeedlePointer(
          value: widget.headingMagneticDegrees!,
          needleLength: 0.92,
          needleStartWidth: 0,
          needleEndWidth: 10,
          needleColor: Colors.orange,
          knobStyle: const KnobStyle(knobRadius: 0),
        ));
      }

      // Always show dot
      pointers.add(MarkerPointer(
        value: widget.headingMagneticDegrees!,
        markerType: MarkerType.circle,
        markerHeight: 16,
        markerWidth: 16,
        color: Colors.orange,
        markerOffset: -5,
      ));
    }

    // COG (Course Over Ground)
    if (widget.cogDegrees != null) {
      pointers.add(NeedlePointer(
        value: widget.cogDegrees!,
        needleLength: 0.60,
        needleStartWidth: 0,
        needleEndWidth: 6,
        needleColor: Colors.white,
        knobStyle: const KnobStyle(knobRadius: 0),
      ));
      pointers.add(MarkerPointer(
        value: widget.cogDegrees!,
        markerType: MarkerType.circle,
        markerHeight: 10,
        markerWidth: 10,
        color: Colors.white,
        markerOffset: -5,
      ));
    }

    // LAYLINES - show when in laylines mode
    if (_currentMode == WindCompassMode.laylines && widget.waypointBearing != null && widget.windDirectionTrueDegrees != null) {
      // Port layline
      pointers.add(NeedlePointer(
        value: _normalizeAngle(widget.windDirectionTrueDegrees! + widget.targetAWA),
        needleLength: 0.85,
        needleStartWidth: 0,
        needleEndWidth: 4,
        needleColor: Colors.purple,
        knobStyle: const KnobStyle(knobRadius: 0),
      ));
      // Starboard layline
      pointers.add(NeedlePointer(
        value: _normalizeAngle(widget.windDirectionTrueDegrees! - widget.targetAWA),
        needleLength: 0.85,
        needleStartWidth: 0,
        needleEndWidth: 4,
        needleColor: Colors.purple,
        knobStyle: const KnobStyle(knobRadius: 0),
      ));
      // Waypoint bearing indicator
      pointers.add(NeedlePointer(
        value: widget.waypointBearing!,
        needleLength: 0.90,
        needleStartWidth: 0,
        needleEndWidth: 6,
        needleColor: Colors.yellow,
        knobStyle: const KnobStyle(knobRadius: 0),
      ));
    }

    // WIND INDICATORS
    // Apparent wind - primary
    if (widget.windDirectionApparentDegrees != null)
      pointers.add(NeedlePointer(
        value: widget.windDirectionApparentDegrees!,
        needleLength: 0.95,
        needleStartWidth: 5,
        needleEndWidth: 0,
        needleColor: Colors.blue,
        knobStyle: const KnobStyle(
          knobRadius: 0.03,
          color: Colors.blue,
        ),
      ));

    // True wind direction marker - secondary
    if (widget.windDirectionTrueDegrees != null)
      pointers.add(NeedlePointer(
        value: widget.windDirectionTrueDegrees!,
        needleLength: 0.75,
        needleStartWidth: 4,
        needleEndWidth: 0,
        needleColor: Colors.green,
        knobStyle: const KnobStyle(
          knobRadius: 0.025,
          color: Colors.green,
        ),
      ));

    return pointers;
  }

  /// Build custom painters (no-go zone and AWA indicators)
  List<CustomPainter> _buildCustomPainters(double primaryHeadingRadians, double primaryHeadingDegrees) {
    final painters = <CustomPainter>[];

    final primaryWindDegrees = widget.windDirectionApparentDegrees ?? widget.windDirectionTrueDegrees;
    if (primaryWindDegrees != null) {
      painters.add(NoGoZoneVPainter(
        windAngle: primaryWindDegrees,
        headingAngle: primaryHeadingDegrees,
        noGoAngle: _getOptimalTargetAWA(),
      ));
    }

    return painters;
  }

  /// Build overlay with AWA display and wind shift indicator
  Widget _buildOverlay(double primaryHeadingDegrees) {
    // Check if wind shift indicator should be shown
    final shift = _calculateWindShift();
    final shouldShowShift = shift != null && shift.abs() >= 3;
    final shiftType = shouldShowShift ? _getShiftType(shift!) : null;
    final showShiftIndicator = shiftType != null;

    return Stack(
      children: [
        // AWA Performance Display - always show if enabled
        if (widget.showAWANumbers)
          _buildAWAPerformanceDisplay(primaryHeadingDegrees),

        // Wind shift indicator - only add to Stack when actually visible
        if (showShiftIndicator)
          _buildWindShiftIndicatorWidget(shift!, shiftType!),
      ],
    );
  }

  /// Cycle through display modes
  void _cycleMode() {
    setState(() {
      switch (_currentMode) {
        case WindCompassMode.targetAWA:
          if (widget.enableVMG && widget.windSpeedTrue != null) {
            _currentMode = WindCompassMode.vmg;
          } else if (widget.waypointBearing != null) {
            _currentMode = WindCompassMode.laylines;
          }
          break;
        case WindCompassMode.vmg:
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
  double? _calculateVMG() {
    if (widget.speedOverGround == null || widget.cogDegrees == null || widget.windDirectionTrueDegrees == null) {
      return null;
    }

    double angleToWind = (widget.cogDegrees! - widget.windDirectionTrueDegrees!).abs();

    if (angleToWind > 180) {
      angleToWind = 360 - angleToWind;
    }

    return widget.speedOverGround! * cos(angleToWind * pi / 180);
  }

  /// Build AWA performance display
  Widget _buildAWAPerformanceDisplay(double headingDegrees) {
    // Check if we have wind data
    if (widget.windAngleApparent == null && widget.windDirectionApparentDegrees == null) {
      // No wind data - show placeholder
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
                border: Border.all(color: Colors.grey, width: 2),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'AWA MODE',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.white38,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'NO WIND DATA',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    double awa;
    if (widget.windAngleApparent != null) {
      awa = widget.windAngleApparent!;
    } else {
      final windDirection = widget.windDirectionApparentDegrees!;
      awa = windDirection - headingDegrees;
    }

    while (awa > 180) {
      awa -= 360;
    }
    while (awa < -180) {
      awa += 360;
    }

    final currentTargetAWA = _getOptimalTargetAWA();
    final absAWA = awa.abs();
    final diff = absAWA - currentTargetAWA;
    final absDiff = diff.abs();

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
      modeLabel = 'VMG MODE';
      content = _buildVMGDisplay(headingDegrees);
    } else {
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

  /// Build VMG display
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

    double? awa;
    if (widget.windAngleApparent != null) {
      awa = widget.windAngleApparent!;
    } else if (widget.windDirectionApparentDegrees != null) {
      double tempAwa = widget.windDirectionApparentDegrees! - headingDegrees;
      while (tempAwa > 180) {
        tempAwa -= 360;
      }
      while (tempAwa < -180) {
        tempAwa += 360;
      }
      awa = tempAwa;
    }

    Color vmgColor = Colors.green;
    if (vmg < 0) {
      vmgColor = Colors.red;
    } else if (vmg < (widget.speedOverGround ?? 0) * 0.5) {
      vmgColor = Colors.yellow;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
        if (awa != null) ...[
          const SizedBox(height: 2),
          Text(
            'AWA: ${awa.abs().toStringAsFixed(0)}° (${awa > 0 ? "STBD" : "PORT"})',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ],
      ],
    );
  }

  /// Build wind shift indicator widget (when visible)
  Widget _buildWindShiftIndicatorWidget(double shift, String shiftType) {
    final isLift = shiftType == 'lift';
    final shiftColor = isLift ? Colors.green : Colors.red;
    final shiftIcon = isLift ? Icons.arrow_upward : Icons.arrow_downward;
    final shiftLabel = isLift ? 'LIFT' : 'HEADER';

    return Positioned(
      right: 80,
      top: 0,
      bottom: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
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

  /// Build laylines display
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
    final navigationCourse = widget.cogDegrees ?? widget.headingTrueDegrees ?? widget.headingMagneticDegrees ?? headingDegrees;

    final twd = widget.windDirectionTrueDegrees ?? navigationCourse;

    final portLayline = _normalizeAngle(twd + widget.targetAWA);
    final stbdLayline = _normalizeAngle(twd - widget.targetAWA);

    final waypointBearing = widget.waypointBearing!;

    final canFetchPort = _isAngleBetween(waypointBearing, portLayline, twd);
    final canFetchStbd = _isAngleBetween(waypointBearing, twd, stbdLayline);

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

  /// Get layline angles (only in laylines mode)
  List<double>? _getLaylinesAngles() {
    if (_currentMode != WindCompassMode.laylines || widget.windDirectionTrueDegrees == null) {
      return null;
    }
    final twd = widget.windDirectionTrueDegrees!;
    return [
      _normalizeAngle(twd + widget.targetAWA), // Port layline
      _normalizeAngle(twd - widget.targetAWA), // Starboard layline
    ];
  }

  /// Get VMG optimal angles (only in VMG mode)
  List<double>? _getVMGAngles() {
    if (_currentMode != WindCompassMode.vmg || widget.windDirectionTrueDegrees == null) {
      return null;
    }
    final twd = widget.windDirectionTrueDegrees!;
    final optimalAWA = _getOptimalTargetAWA();
    return [
      _normalizeAngle(twd + optimalAWA), // Port tack optimal VMG
      _normalizeAngle(twd - optimalAWA), // Starboard tack optimal VMG
    ];
  }

  @override
  Widget build(BuildContext context) {
    return BaseCompass(
      headingTrueRadians: widget.headingTrueRadians,
      headingMagneticRadians: widget.headingMagneticRadians,
      headingTrueDegrees: widget.headingTrueDegrees,
      headingMagneticDegrees: widget.headingMagneticDegrees,
      cogDegrees: widget.cogDegrees,
      isSailingVessel: widget.isSailingVessel,
      apparentWindAngle: widget.windAngleApparent,
      targetAWA: widget.targetAWA,
      targetTolerance: widget.targetTolerance,
      laylinesAngles: _getLaylinesAngles(),
      vmgAngles: _getVMGAngles(),
      rangesBuilder: _buildSailingZones,
      pointersBuilder: _buildWindPointers,
      customPaintersBuilder: _buildCustomPainters,
      overlayBuilder: _buildOverlay,
      bottomLeftDisplay: widget.windDirectionTrueDegrees != null
          ? Column(
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
            )
          : null,
      bottomRightDisplay: widget.windDirectionApparentDegrees != null
          ? Column(
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
            )
          : null,
      bottomCenterDisplay: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
          const SizedBox(width: 24),
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
    );
  }
}

/// Custom painter for the V-shaped no-go zone indicator
class NoGoZoneVPainter extends CustomPainter {
  final double windAngle;
  final double headingAngle;
  final double noGoAngle;

  NoGoZoneVPainter({
    required this.windAngle,
    required this.headingAngle,
    this.noGoAngle = 40.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 * 0.95;

    final windRad = windAngle * pi / 180;
    final noGoRad = noGoAngle * pi / 180;

    final leftAngle = windRad - noGoRad;

    final path = Path();
    path.moveTo(center.dx, center.dy);

    path.lineTo(
      center.dx + radius * cos(leftAngle),
      center.dy + radius * sin(leftAngle),
    );

    path.arcTo(
      Rect.fromCircle(center: center, radius: radius),
      leftAngle,
      2 * noGoRad,
      false,
    );

    path.lineTo(center.dx, center.dy);
    path.close();

    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(NoGoZoneVPainter oldDelegate) {
    return oldDelegate.windAngle != windAngle ||
           oldDelegate.headingAngle != headingAngle ||
           oldDelegate.noGoAngle != noGoAngle;
  }
}

/// Wind sample for tracking historical wind direction
class _WindSample {
  final double direction;
  final DateTime timestamp;

  _WindSample(this.direction, this.timestamp);
}
