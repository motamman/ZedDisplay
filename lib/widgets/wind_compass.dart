import 'dart:math';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'base_compass.dart';
import '../utils/angle_utils.dart';
import '../utils/compass_zone_builder.dart';

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
  final String? cogFormatted;

  // Waypoint navigation
  final double? waypointBearing;   // True bearing to waypoint (degrees)
  final String? waypointBearingFormatted;
  final double? waypointDistance;  // Distance to waypoint (meters)
  final String? waypointDistanceFormatted;

  // Pre-formatted display strings for wind directions
  final String? windDirectionTrueFormatted;
  final String? windDirectionApparentFormatted;
  final String? windAngleApparentFormatted;

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
    this.cogFormatted,
    this.waypointBearing,
    this.waypointBearingFormatted,
    this.waypointDistance,
    this.waypointDistanceFormatted,
    this.windDirectionTrueFormatted,
    this.windDirectionApparentFormatted,
    this.windAngleApparentFormatted,
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
  }

  /// Calculate wind shift from baseline
  // Removed: _normalizeAngle - now using AngleUtils.normalize()
  // Removed: _calculateWindShift and _getShiftType - unused methods

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

    final effectiveTargetAWA = _getOptimalTargetAWA();

    final builder = CompassZoneBuilder();
    builder.addSailingZones(
      windDirection: primaryWindDegrees,
      targetAWA: effectiveTargetAWA,
      targetTolerance: widget.targetTolerance,
    );

    return builder.zones;
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
        value: AngleUtils.normalize(widget.windDirectionTrueDegrees! + widget.targetAWA),
        needleLength: 0.85,
        needleStartWidth: 0,
        needleEndWidth: 4,
        needleColor: Colors.purple,
        knobStyle: const KnobStyle(knobRadius: 0),
      ));
      // Starboard layline
      pointers.add(NeedlePointer(
        value: AngleUtils.normalize(widget.windDirectionTrueDegrees! - widget.targetAWA),
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
    if (widget.windDirectionApparentDegrees != null) {
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
    }

    // True wind direction marker - secondary
    if (widget.windDirectionTrueDegrees != null) {
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
    }

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

  /// Build overlay with AWA display and wind direction arrow
  Widget _buildOverlay(double primaryHeadingDegrees) {
    // Calculate if AWA is in relevant range (polars + 30°)
    bool showAWADisplay = false;
    if (widget.showAWANumbers && (widget.windAngleApparent != null || widget.windDirectionApparentDegrees != null)) {
      double awa;
      if (widget.windAngleApparent != null) {
        awa = widget.windAngleApparent!;
      } else {
        final windDirection = widget.windDirectionApparentDegrees!;
        awa = windDirection - primaryHeadingDegrees;
        while (awa > 180) {
          awa -= 360;
        }
        while (awa < -180) {
          awa += 360;
        }
      }

      final currentTargetAWA = _getOptimalTargetAWA();
      final absAWA = awa.abs();

      // Show AWA display only when within optimal angle + 30° (upwind and reaching)
      showAWADisplay = absAWA <= (currentTargetAWA + 30);
    }

    return Stack(
      children: [
        // AWA Performance Display - only show when relevant (polars + 30°)
        if (showAWADisplay)
          _buildAWAPerformanceDisplay(primaryHeadingDegrees),

        // Wind direction arrow in center
        if (widget.windDirectionTrueDegrees != null)
          _buildWindDirectionArrow(widget.windDirectionTrueDegrees!),
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
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ],
    );
  }

  /// Build wind direction arrow in center of compass
  Widget _buildWindDirectionArrow(double windDirectionDegrees) {
    return Positioned.fill(
      child: Center(
        child: Transform.rotate(
          angle: (windDirectionDegrees - 90) * pi / 180, // Rotate to point at wind direction
          child: SizedBox(
            width: 120,
            height: 120,
            child: CustomPaint(
              painter: _WindDirectionArrowPainter(),
            ),
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

    final portLayline = AngleUtils.normalize(twd + widget.targetAWA);
    final stbdLayline = AngleUtils.normalize(twd - widget.targetAWA);

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
              'WPT: ${widget.waypointBearingFormatted ?? '${waypointBearing.toStringAsFixed(0)}°'}',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (widget.waypointDistanceFormatted != null) ...[
              const SizedBox(width: 8),
              Text(
                widget.waypointDistanceFormatted!,
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
    angle = AngleUtils.normalize(angle);
    start = AngleUtils.normalize(start);
    end = AngleUtils.normalize(end);

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
      AngleUtils.normalize(twd + widget.targetAWA), // Port layline
      AngleUtils.normalize(twd - widget.targetAWA), // Starboard layline
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
      AngleUtils.normalize(twd + optimalAWA), // Port tack optimal VMG
      AngleUtils.normalize(twd - optimalAWA), // Starboard tack optimal VMG
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
                  widget.windDirectionTrueFormatted ?? '${widget.windDirectionTrueDegrees!.toStringAsFixed(0)}°',
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
                  widget.windDirectionApparentFormatted ?? '${widget.windDirectionApparentDegrees!.toStringAsFixed(0)}°',
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
                widget.cogFormatted ?? (widget.cogDegrees != null
                    ? '${widget.cogDegrees!.toStringAsFixed(0)}°'
                    : '--'),
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

    // Calculate apparent wind angle relative to heading
    double awa = windAngle - headingAngle;
    while (awa > 180) {
      awa -= 360;
    }
    while (awa < -180) {
      awa += 360;
    }
    awa = awa.abs();

    // Fade opacity as AWA increases (moving from upwind to downwind)
    // Full opacity at upwind (40°), fade out towards beam reach and beyond
    double opacity;
    if (awa < 60) {
      opacity = 0.5; // Full opacity when close-hauled
    } else if (awa < 120) {
      // Linear fade from 60° to 120° (reaching)
      opacity = 0.5 - ((awa - 60) / 60 * 0.4); // Fade from 0.5 to 0.1
    } else {
      // Very faint when running downwind
      opacity = 0.1;
    }

    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: opacity)
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

/// Custom painter for wind direction arrow with shortened arrowhead
class _WindDirectionArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    // Shadow paint
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // Arrow shaft (vertical line pointing up)
    final shaftStart = Offset(center.dx, size.height * 0.75);
    final shaftEnd = Offset(center.dx, size.height * 0.15);

    // Arrowhead arms - reduced by 1/3
    // Original would be ~20px, now ~13px
    final arrowheadLength = size.height * 0.11; // Shortened from 0.17
    final arrowheadAngle = 25 * pi / 180; // 25 degrees

    final leftArm = Offset(
      shaftEnd.dx - (arrowheadLength * sin(arrowheadAngle)),
      shaftEnd.dy + (arrowheadLength * cos(arrowheadAngle)),
    );
    final rightArm = Offset(
      shaftEnd.dx + (arrowheadLength * sin(arrowheadAngle)),
      shaftEnd.dy + (arrowheadLength * cos(arrowheadAngle)),
    );

    // Draw shadow
    canvas.drawLine(shaftStart, shaftEnd, shadowPaint);
    canvas.drawLine(shaftEnd, leftArm, shadowPaint);
    canvas.drawLine(shaftEnd, rightArm, shadowPaint);

    // Draw arrow
    canvas.drawLine(shaftStart, shaftEnd, paint);
    canvas.drawLine(shaftEnd, leftArm, paint);
    canvas.drawLine(shaftEnd, rightArm, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
