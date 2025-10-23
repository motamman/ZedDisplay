import 'dart:math';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

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

  // Wind speed values
  final double? windSpeedTrue;
  final String? windSpeedTrueFormatted;
  final double? windSpeedApparent;
  final String? windSpeedApparentFormatted;

  final double? speedOverGround;
  final String? sogFormatted;
  final double? cogDegrees;

  // Target AWA configuration
  final double targetAWA;          // Optimal close-hauled angle from polar data (degrees)
  final double targetTolerance;    // Acceptable deviation from target (degrees)
  final bool showAWANumbers;       // Show numeric AWA display with target comparison

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
    this.windSpeedTrue,
    this.windSpeedTrueFormatted,
    this.windSpeedApparent,
    this.windSpeedApparentFormatted,
    this.speedOverGround,
    this.sogFormatted,
    this.cogDegrees,
    this.targetAWA = 40.0,
    this.targetTolerance = 3.0,
    this.showAWANumbers = true,
  });

  @override
  State<WindCompass> createState() => _WindCompassState();
}

class _WindCompassState extends State<WindCompass> {
  bool _useTrueHeading = false; // Default to magnetic

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
  /// Uses configurable targetAWA instead of hardcoded angles
  List<GaugeRange> _buildSailingZones(double windDegrees) {
    final zones = <GaugeRange>[];

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
    addRange(windDegrees - 60, windDegrees - widget.targetAWA, Colors.red.withValues(alpha: 0.6));
    // Zone 2: Close reach (60° to 90°) - medium
    addRange(windDegrees - 90, windDegrees - 60, Colors.red.withValues(alpha: 0.4));
    // Zone 3: Beam reach (90° to 110°) - lighter
    addRange(windDegrees - 110, windDegrees - 90, Colors.red.withValues(alpha: 0.25));
    // Zone 4: Broad reach/run (110° to 150°) - lightest
    addRange(windDegrees - 150, windDegrees - 110, Colors.red.withValues(alpha: 0.15));

    // No-go zone (wind ± targetAWA)
    addRange(windDegrees - widget.targetAWA, windDegrees + widget.targetAWA, Colors.white.withValues(alpha: 0.3));

    // STARBOARD SIDE - Gradiated Green Zones (darker = more important)
    // Zone 1: Close-hauled (target to 60°) - darkest
    addRange(windDegrees + widget.targetAWA, windDegrees + 60, Colors.green.withValues(alpha: 0.6));
    // Zone 2: Close reach (60° to 90°) - medium
    addRange(windDegrees + 60, windDegrees + 90, Colors.green.withValues(alpha: 0.4));
    // Zone 3: Beam reach (90° to 110°) - lighter
    addRange(windDegrees + 90, windDegrees + 110, Colors.green.withValues(alpha: 0.25));
    // Zone 4: Broad reach/run (110° to 150°) - lightest
    addRange(windDegrees + 110, windDegrees + 150, Colors.green.withValues(alpha: 0.15));

    // PERFORMANCE ZONES - layer on top with narrower width to show as inner rings
    final target = widget.targetAWA;
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

  /// Build AWA performance display showing current vs target
  Widget _buildAWAPerformanceDisplay(double headingDegrees) {
    // Calculate AWA (Apparent Wind Angle) - relative to boat
    final windDirection = widget.windDirectionApparentDegrees!;
    double awa = windDirection - headingDegrees;

    // Normalize to -180 to +180 range
    while (awa > 180) {
      awa -= 360;
    }
    while (awa < -180) {
      awa += 360;
    }

    // Get absolute AWA for comparison with target
    final absAWA = awa.abs();
    final diff = absAWA - widget.targetAWA;
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

    return Positioned(
      top: 35,
      left: 0,
      right: 0,
      child: Center(
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'AWA: ',
                    style: const TextStyle(
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
                    'TGT: ${widget.targetAWA.toStringAsFixed(0)}°',
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
          ),
        ),
      ),
    );
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
                        noGoAngle: widget.targetAWA,
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
                          knobStyle: KnobStyle(
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
                          knobStyle: KnobStyle(
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
                          knobStyle: KnobStyle(
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

                      // WIND INDICATORS - LAYER 2 (above heading indicators)
                      // Apparent wind - primary
                      if (widget.windDirectionApparentDegrees != null)
                        NeedlePointer(
                          value: widget.windDirectionApparentDegrees!,
                          needleLength: 0.95,
                          needleStartWidth: 5,
                          needleEndWidth: 0,
                          needleColor: Colors.blue,
                          knobStyle: KnobStyle(
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
                          knobStyle: KnobStyle(
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

              // COG label at top center - styled like other labels
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'COG',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
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
                ),
              ),

              // AWA Performance Display - shows current vs target
              if (widget.showAWANumbers && widget.windDirectionApparentDegrees != null)
                _buildAWAPerformanceDisplay(primaryHeadingDegrees),

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
                    decoration: BoxDecoration(
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
                              decoration: BoxDecoration(
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
                              decoration: BoxDecoration(
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
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
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
                        style: TextStyle(
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
                            Text(
                              'TWS',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white60,
                              ),
                            ),
                            Text(
                              widget.windSpeedTrueFormatted ?? widget.windSpeedTrue!.toStringAsFixed(1),
                              style: TextStyle(
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
                          Text(
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
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${widget.windDirectionApparentDegrees!.toStringAsFixed(0)}°',
                        style: TextStyle(
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
                            Text(
                              'AWS',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white60,
                              ),
                            ),
                            Text(
                              widget.windSpeedApparentFormatted ?? widget.windSpeedApparent!.toStringAsFixed(1),
                              style: TextStyle(
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

              // Speed Over Ground (bottom center)
              if (widget.speedOverGround != null)
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'SOG',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white60,
                          ),
                        ),
                        Text(
                          widget.sogFormatted ?? widget.speedOverGround!.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 24,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
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
    return oldDelegate.windAngle != windAngle || oldDelegate.headingAngle != headingAngle;
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
