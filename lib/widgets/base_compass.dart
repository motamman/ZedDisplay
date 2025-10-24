import 'dart:math';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

/// Base compass widget providing a rotating compass card foundation
/// Extracted from WindCompass for reuse across different compass types
class BaseCompass extends StatefulWidget {
  // Heading values in radians (for rotation) and degrees (for display)
  final double? headingTrueRadians;
  final double? headingMagneticRadians;
  final double? headingTrueDegrees;
  final double? headingMagneticDegrees;

  // COG (Course Over Ground) - optional
  final double? cogDegrees;

  // Sailing vessel configuration
  final bool isSailingVessel;
  final double? apparentWindAngle; // AWA in degrees (-180 to +180) for sail trim indicator
  final double targetAWA; // Target AWA for optimal sailing (from polar)
  final double targetTolerance; // Tolerance for target AWA

  // Additional angle indicators
  final List<double>? laylinesAngles; // Layline angles to show with purple arrows
  final List<double>? vmgAngles; // VMG optimal angles to show with cyan arrows

  // Customization builders
  final List<GaugeRange> Function(double primaryHeadingDegrees)? rangesBuilder;
  final List<GaugePointer> Function(double primaryHeadingDegrees)? pointersBuilder;
  final List<CustomPainter> Function(double primaryHeadingRadians, double primaryHeadingDegrees)? customPaintersBuilder;
  final Widget Function(double primaryHeadingDegrees)? overlayBuilder;
  final Widget Function(double primaryHeadingDegrees, String headingMode)? centerDisplayBuilder;

  // Corner displays customization
  final Widget Function(double headingDegrees, bool isActive)? trueHeadingDisplayBuilder;
  final Widget Function(double headingDegrees, bool isActive)? magneticHeadingDisplayBuilder;
  final Widget? bottomLeftDisplay;
  final Widget? bottomRightDisplay;
  final Widget? bottomCenterDisplay;

  // Compass appearance
  final bool showVesselShadow;
  final bool showCenterCircle;
  final bool showCompassLabels;
  final bool allowHeadingModeToggle;

  // Aspect ratio (1.0 = circle, >1.0 = wider)
  final double aspectRatio;

  const BaseCompass({
    super.key,
    this.headingTrueRadians,
    this.headingMagneticRadians,
    this.headingTrueDegrees,
    this.headingMagneticDegrees,
    this.cogDegrees,
    this.isSailingVessel = false,
    this.apparentWindAngle,
    this.targetAWA = 40.0,
    this.targetTolerance = 3.0,
    this.laylinesAngles,
    this.vmgAngles,
    this.rangesBuilder,
    this.pointersBuilder,
    this.customPaintersBuilder,
    this.overlayBuilder,
    this.centerDisplayBuilder,
    this.trueHeadingDisplayBuilder,
    this.magneticHeadingDisplayBuilder,
    this.bottomLeftDisplay,
    this.bottomRightDisplay,
    this.bottomCenterDisplay,
    this.showVesselShadow = true,
    this.showCenterCircle = true,
    this.showCompassLabels = true,
    this.allowHeadingModeToggle = true,
    this.aspectRatio = 1.0,
  });

  @override
  State<BaseCompass> createState() => _BaseCompassState();
}

class _BaseCompassState extends State<BaseCompass> {
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

  /// Build angle indicators (for laylines, VMG, etc.) - simple arrows pointing outward
  List<Widget> _buildAngleIndicators(
    double width,
    double height,
    List<double> angles,
    Color color,
  ) {
    final center = Offset(width / 2, height / 2);
    final radius = min(width, height) / 2 * 0.95;

    final indicators = <Widget>[];

    for (final angle in angles) {
      final angleRad = angle * pi / 180;
      final x = center.dx + radius * sin(angleRad);
      final y = center.dy - radius * cos(angleRad);

      // Simple arrow pointing outward
      indicators.add(
        Positioned(
          left: x - 10,
          top: y - 10,
          child: Transform.rotate(
            angle: angleRad,
            child: Icon(
              Icons.navigation,
              size: 20,
              color: color,
              shadows: const [
                Shadow(color: Colors.white, blurRadius: 2),
                Shadow(color: Colors.black, blurRadius: 4),
              ],
            ),
          ),
        ),
      );
    }

    return indicators;
  }

  /// Build AWA icon indicators using actual Flutter Icons
  List<Widget> _buildAWAIconIndicators(
    double width,
    double height,
    double awa,
    double targetAWA,
    double targetTolerance,
  ) {
    final center = Offset(width / 2, height / 2);
    final radius = min(width, height) / 2 * 0.95;

    // Determine performance color
    final absAWA = awa.abs();
    final diff = absAWA - targetAWA;
    Color performanceColor;
    if (diff.abs() <= targetTolerance) {
      performanceColor = Colors.green.shade600;
    } else if (diff.abs() <= targetTolerance * 2) {
      performanceColor = Colors.yellow.shade700;
    } else {
      performanceColor = Colors.red.shade600;
    }

    final indicators = <Widget>[];

    // Determine if optimal, too high, or too low
    final isOptimal = diff.abs() <= targetTolerance;
    final isTooHigh = absAWA > targetAWA;

    // Create simple arrow icon at port and starboard AWA positions
    for (final angle in [awa, -awa]) {
      final angleRad = angle * pi / 180;
      final x = center.dx + radius * sin(angleRad);
      final y = center.dy - radius * cos(angleRad);

      // Arrow direction based on performance:
      // - Optimal: point straight out (radial)
      // - Too high: point counter-clockwise along rim (toward wind)
      // - Too low: point clockwise along rim (away from wind)
      final double rotationAngle;
      if (isOptimal) {
        rotationAngle = angleRad; // Point outward
      } else {
        final steerDirection = isTooHigh ? -pi / 2 : pi / 2;
        rotationAngle = angleRad + steerDirection; // Point along rim
      }

      indicators.add(
        Positioned(
          left: x - 10, // Center icon
          top: y - 10,
          child: Transform.rotate(
            angle: rotationAngle,
            child: Icon(
              Icons.navigation,
              size: 20,
              color: performanceColor,
              shadows: const [
                Shadow(color: Colors.white, blurRadius: 2),
                Shadow(color: Colors.black, blurRadius: 4),
              ],
            ),
          ),
        ),
      );
    }

    return indicators;
  }

  /// Build compass labels (N, S, E, W, degrees) as gauge annotations
  List<GaugeAnnotation> _buildCompassLabels(double headingDegrees) {
    if (!widget.showCompassLabels) return [];

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
          widget: Transform.rotate(
            angle: (headingDegrees * pi / 180) + (pi / 2), // Counter-rotate by heading + 90° to align with vessel bow
            child: Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontSize: fontSize,
                fontWeight: i == 0 || i % 90 == 0 ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
          angle: i.toDouble(),
          positionFactor: 0.85,
        ),
      );
    }

    return labels;
  }

  /// Build default center display with heading
  Widget _buildDefaultCenterDisplay(double primaryHeadingDegrees, String headingMode) {
    return Positioned.fill(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 90), // Push content down
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
    );
  }

  /// Build default true heading display (top left)
  Widget _buildDefaultTrueHeadingDisplay(double headingDegrees, bool isActive) {
    return Column(
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
                color: isActive ? Colors.white : Colors.white60,
              ),
            ),
          ],
        ),
        Text(
          '${headingDegrees.toStringAsFixed(0)}°T',
          style: TextStyle(
            fontSize: 20,
            color: Colors.white,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  /// Build default magnetic heading display (top right)
  Widget _buildDefaultMagneticHeadingDisplay(double headingDegrees, bool isActive) {
    return Column(
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
                color: isActive ? Colors.white : Colors.white60,
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
          '${headingDegrees.toStringAsFixed(0)}°M',
          style: TextStyle(
            fontSize: 20,
            color: Colors.white,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
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

    final headingMode = _useTrueHeading ? 'True' : 'Mag';

    // Get custom painters if provided
    final customPainters = widget.customPaintersBuilder?.call(primaryHeadingRadians, primaryHeadingDegrees) ?? [];

    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // Vessel shadow - LOWEST LAYER - FIXED pointing up (not rotating with compass)
              if (widget.showVesselShadow)
                Positioned.fill(
                  child: CustomPaint(
                    painter: VesselShadowPainter(),
                  ),
                ),

              // Custom painters - LAYER 2 - can include no-go zones, etc.
              ...customPainters.map((painter) => Positioned.fill(
                child: Transform.rotate(
                  angle: -primaryHeadingRadians - (pi / 2),
                  child: CustomPaint(painter: painter),
                ),
              )),

              // Sail trim indicator - LAYER 2.5 - for sailing vessels with wind data
              // FIXED like vessel shadow - not rotating with compass
              if (widget.isSailingVessel && widget.apparentWindAngle != null)
                Positioned.fill(
                  child: CustomPaint(
                    painter: SailTrimIndicatorPainter(
                      apparentWindAngle: widget.apparentWindAngle!,
                      targetAWA: widget.targetAWA,
                      targetTolerance: widget.targetTolerance,
                    ),
                  ),
                ),

              // Main compass gauge (full circle) - LAYER 3 - wrapped in Transform.rotate
              Transform.rotate(
                angle: -primaryHeadingRadians - (pi / 2),  // Rotation minus 90° to compensate
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

                      // Custom ranges (zones)
                      ranges: widget.rangesBuilder?.call(primaryHeadingDegrees) ?? [],

                      // Custom pointers
                      pointers: widget.pointersBuilder?.call(primaryHeadingDegrees) ?? [],

                      // Compass labels
                      annotations: _buildCompassLabels(primaryHeadingDegrees),
                    ),
                  ],
                ),
              ),

              // AWA indicators using actual Icons - LAYER 3.5 - FIXED on rim (ABOVE compass)
              if (widget.apparentWindAngle != null)
                ..._buildAWAIconIndicators(
                  constraints.maxWidth,
                  constraints.maxHeight,
                  widget.apparentWindAngle!,
                  widget.targetAWA,
                  widget.targetTolerance,
                ),

              // Layline indicators - LAYER 3.6 - purple arrows
              if (widget.laylinesAngles != null)
                ..._buildAngleIndicators(
                  constraints.maxWidth,
                  constraints.maxHeight,
                  widget.laylinesAngles!,
                  Colors.purple.shade400,
                ),

              // VMG indicators - LAYER 3.7 - cyan arrows
              if (widget.vmgAngles != null)
                ..._buildAngleIndicators(
                  constraints.maxWidth,
                  constraints.maxHeight,
                  widget.vmgAngles!,
                  Colors.cyan.shade400,
                ),

              // Custom overlay (AWA displays, XTE, etc.) - LAYER 4
              if (widget.overlayBuilder != null)
                widget.overlayBuilder!(primaryHeadingDegrees),

              // Center display with heading - LAYER 5
              widget.centerDisplayBuilder?.call(primaryHeadingDegrees, headingMode) ??
                  _buildDefaultCenterDisplay(primaryHeadingDegrees, headingMode),

              // White circle in the center - HIGHEST LAYER - above everything
              if (widget.showCenterCircle)
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
                    onTap: widget.allowHeadingModeToggle
                        ? () {
                            setState(() {
                              _useTrueHeading = true;
                            });
                          }
                        : null,
                    child: widget.trueHeadingDisplayBuilder?.call(
                          widget.headingTrueDegrees!,
                          _useTrueHeading,
                        ) ??
                        _buildDefaultTrueHeadingDisplay(
                          widget.headingTrueDegrees!,
                          _useTrueHeading,
                        ),
                  ),
                ),

              // HDG Magnetic (top right) - tap to switch to magnetic heading
              if (widget.headingMagneticDegrees != null)
                Positioned(
                  right: 16,
                  top: 40,
                  child: GestureDetector(
                    onTap: widget.allowHeadingModeToggle
                        ? () {
                            setState(() {
                              _useTrueHeading = false;
                            });
                          }
                        : null,
                    child: widget.magneticHeadingDisplayBuilder?.call(
                          widget.headingMagneticDegrees!,
                          !_useTrueHeading,
                        ) ??
                        _buildDefaultMagneticHeadingDisplay(
                          widget.headingMagneticDegrees!,
                          !_useTrueHeading,
                        ),
                  ),
                ),

              // Bottom left display
              if (widget.bottomLeftDisplay != null)
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: widget.bottomLeftDisplay!,
                ),

              // Bottom right display
              if (widget.bottomRightDisplay != null)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: widget.bottomRightDisplay!,
                ),

              // Bottom center display (SOG/COG)
              if (widget.bottomCenterDisplay != null)
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Center(child: widget.bottomCenterDisplay!),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Custom painter for vessel shadow
class VesselShadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = size.width / 200; // Scale based on size

    // Create boat shape pointing up
    final path = Path();

    // Bow (front point) - extended forward
    path.moveTo(center.dx, center.dy - 70 * scale);

    // Port side (left) - curve inward toward stern (start curve further forward)
    path.lineTo(center.dx - 30 * scale, center.dy + 5 * scale);
    path.quadraticBezierTo(
      center.dx - 28 * scale, center.dy + 30 * scale, // Control point
      center.dx - 18 * scale, center.dy + 48 * scale, // End point (curves inward)
    );

    // Port side of stern - to rudder notch
    path.lineTo(center.dx - 4 * scale, center.dy + 50 * scale);

    // Rudder notch
    path.lineTo(center.dx - 4 * scale, center.dy + 54 * scale); // Down into notch
    path.lineTo(center.dx + 4 * scale, center.dy + 54 * scale); // Across notch
    path.lineTo(center.dx + 4 * scale, center.dy + 50 * scale); // Back up

    // Starboard side of stern
    path.lineTo(center.dx + 18 * scale, center.dy + 48 * scale);

    // Starboard side (right) - curve inward toward stern (start curve further forward)
    path.quadraticBezierTo(
      center.dx + 28 * scale, center.dy + 30 * scale, // Control point
      center.dx + 30 * scale, center.dy + 5 * scale, // End point (curves inward)
    );

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

/// Custom painter for sail trim indicator
/// Shows a curved line on opposite side of vessel representing point of sail
class SailTrimIndicatorPainter extends CustomPainter {
  final double apparentWindAngle; // AWA in degrees (-180 to +180)
  final double targetAWA; // Target AWA from polar configuration
  final double targetTolerance; // Tolerance from polar configuration

  SailTrimIndicatorPainter({
    required this.apparentWindAngle,
    this.targetAWA = 40.0,
    this.targetTolerance = 3.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = size.width / 200;

    // Get absolute AWA
    final absAWA = apparentWindAngle.abs();

    // Determine side (opposite of wind)
    // If wind from starboard (+), sail on port (-)
    // If wind from port (-), sail on starboard (+)
    final sailSide = apparentWindAngle > 0 ? -1.0 : 1.0;

    // Check if in no-go zone (luffing) - below target minus 2x tolerance
    final isLuffing = absAWA < (targetAWA - 2 * targetTolerance);

    // Calculate sail position and color based on point of sail
    // Color matches the compass rim zones - POLAR ZONES FIRST
    double sailDistance;
    Color sailColor;

    if (isLuffing) {
      // In no-go zone - grey/white like the no-go zone on compass
      sailDistance = 25 * scale;
      sailColor = Colors.grey.withValues(alpha: 0.8);
    } else if (absAWA >= (targetAWA - targetTolerance) && absAWA <= (targetAWA + targetTolerance)) {
      // Optimal performance zone - green (target ± tolerance)
      sailDistance = 25 * scale;
      sailColor = Colors.green.withValues(alpha: 0.8);
    } else if ((absAWA >= (targetAWA - 2 * targetTolerance) && absAWA < (targetAWA - targetTolerance)) ||
               (absAWA > (targetAWA + targetTolerance) && absAWA <= (targetAWA + 2 * targetTolerance))) {
      // Acceptable performance zone - yellow (on both sides of green)
      sailDistance = 28 * scale;
      sailColor = Colors.yellow.withValues(alpha: 0.7);
    } else if (absAWA < 60) {
      // Close hauled zone - match gradiated zone colors (port tack green, starboard tack red)
      sailDistance = 28 * scale;
      sailColor = (apparentWindAngle < 0 ? Colors.green : Colors.red).withValues(alpha: 0.6);
    } else if (absAWA < 90) {
      // Close to beam reach - sail easing out
      sailDistance = 35 * scale;
      sailColor = (apparentWindAngle < 0 ? Colors.green : Colors.red).withValues(alpha: 0.4);
    } else if (absAWA < 110) {
      // Beam reach
      sailDistance = 45 * scale;
      sailColor = (apparentWindAngle < 0 ? Colors.green : Colors.red).withValues(alpha: 0.25);
    } else if (absAWA < 150) {
      // Broad reach
      sailDistance = 50 * scale;
      sailColor = (apparentWindAngle < 0 ? Colors.green : Colors.red).withValues(alpha: 0.15);
    } else {
      // Dead downwind (150-180°) - grey zone, no performance data
      sailDistance = 55 * scale;
      sailColor = Colors.grey.withValues(alpha: 0.5);
    }

    // Draw curved sail line on the side opposite to wind
    final path = Path();

    // Mast position - MUST match vessel shadow exactly
    // Vessel: bow at -70*scale, stern at +50*scale, total length 120*scale
    // Typical sailboat mast is ~30% back from bow
    // -70 + (120 * 0.30) = -34
    final mastTopY = center.dy - 34 * scale; // Mast at 30% back from bow
    path.moveTo(center.dx, mastTopY); // Start at mast top on centerline

    if (isLuffing) {
      // LUFFING MODE - create smooth wavy sail edge to show fluttering
      final totalHeight = 80 * scale;
      final numWaves = 3; // Number of complete wave cycles
      final waveAmplitude = 5 * scale; // Wave size

      // Generate smooth curve points
      final steps = 20; // More steps = smoother curve
      Offset? prevPoint;

      for (int i = 0; i <= steps; i++) {
        final t = i / steps;
        final y = mastTopY + (totalHeight * t);

        // Base distance varies along sail length (billows out in middle)
        double baseDistance;
        if (t < 0.5) {
          baseDistance = sailDistance * (0.3 + t * 1.4);
        } else {
          baseDistance = sailDistance * (1.0 - (t - 0.5) * 1.6);
        }

        // Add smooth wave
        final wave = waveAmplitude * sin(t * numWaves * 2 * pi);
        final x = center.dx + (sailSide * (baseDistance + wave));

        final currentPoint = Offset(x, y);

        if (i == 0) {
          path.lineTo(x, y);
        } else if (prevPoint != null) {
          // Use smooth quadratic curves with control point at midpoint
          final midY = (prevPoint.dy + currentPoint.dy) / 2;
          final midX = (prevPoint.dx + currentPoint.dx) / 2;
          path.quadraticBezierTo(midX, midY, currentPoint.dx, currentPoint.dy);
        }

        prevPoint = currentPoint;
      }
    } else {
      // NORMAL MODE - single bold arc from mast top to boom end (the leech)
      // This creates a triangular sail with the luff (mast), foot (boom), and curved leech

      // mastTopY already defined above (-34*scale from center)
      // Boom end should be near stern but not at rudder
      // Stern deck ends at +48*scale, rudder extends to +50*scale
      final boomEndY = center.dy + 35 * scale; // Boom near stern

      // Calculate boom angle based on AWA (opposite side from wind)
      // Close hauled (40°): boom at ~10° from centerline
      // Beam reach (90°): boom at ~50° from centerline
      // Broad reach (120°): boom at ~70° from centerline
      // Running (150-180°): boom at ~85-90° from centerline (nearly perpendicular)
      double boomAngle;
      if (absAWA < 60) {
        // Close hauled - tight to the boat
        boomAngle = 10 + (absAWA - 40) * 0.5; // 10° at 40° AWA, up to 20° at 60° AWA
      } else if (absAWA < 90) {
        // Reaching - easing out
        boomAngle = 20 + (absAWA - 60) * 1.0; // 20° to 50°
      } else if (absAWA < 150) {
        // Broad reach - letting out more
        boomAngle = 50 + (absAWA - 90) * 0.583; // 50° to 85°
      } else {
        // Running - nearly perpendicular
        boomAngle = 85 + (absAWA - 150) * 0.167; // 85° to 90°
      }

      // Calculate boom end position using the angle
      final boomLength = 69 * scale; // Distance from mast top to boom end
      final boomAngleRad = (boomAngle * sailSide) * pi / 180; // Convert to radians, apply side

      final boomEndPoint = Offset(
        center.dx + (sin(boomAngleRad) * boomLength),
        boomEndY,
      );

      // Draw single smooth arc from mast top to boom end
      // Control points create the sail's draft (belly)
      // Max draft should be about 1/3 to 1/2 back from mast
      // Make the sail belly out from the boom line
      final sailBelly = sailDistance * 0.3; // How much the sail billows out

      final controlPoint1 = Offset(
        center.dx + (sin(boomAngleRad) * boomLength * 0.3) + (sailSide * sailBelly * 0.5),
        mastTopY + (boomEndY - mastTopY) * 0.25,
      );
      final controlPoint2 = Offset(
        center.dx + (sin(boomAngleRad) * boomLength * 0.7) + (sailSide * sailBelly),
        mastTopY + (boomEndY - mastTopY) * 0.7,
      );

      path.cubicTo(
        controlPoint1.dx, controlPoint1.dy,
        controlPoint2.dx, controlPoint2.dy,
        boomEndPoint.dx, boomEndPoint.dy,
      );
    }

    // Draw the sail curve
    final paint = Paint()
      ..color = sailColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5 // Same thickness for all sails
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, paint);

    // Draw the boom (straight line from mast top to boom end) - only in normal mode
    if (!isLuffing) {
      // Recalculate boom position using the same angle logic
      final boomEndY = center.dy + 35 * scale;
      final absAWA = apparentWindAngle.abs();

      double boomAngle;
      if (absAWA < 60) {
        boomAngle = 10 + (absAWA - 40) * 0.5;
      } else if (absAWA < 90) {
        boomAngle = 20 + (absAWA - 60) * 1.0;
      } else if (absAWA < 150) {
        boomAngle = 50 + (absAWA - 90) * 0.583;
      } else {
        boomAngle = 85 + (absAWA - 150) * 0.167;
      }

      final boomLength = 69 * scale;
      final boomAngleRad = (boomAngle * sailSide) * pi / 180;
      final boomEndPoint = Offset(
        center.dx + (sin(boomAngleRad) * boomLength),
        boomEndY,
      );

      final boomPaint = Paint()
        ..color = sailColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round;

      // Draw boom as straight line from mast top to boom end (outer corner of sail)
      canvas.drawLine(
        Offset(center.dx, mastTopY),  // Start at mast top
        boomEndPoint,                  // End at boom end (clew)
        boomPaint,
      );
    }

    // Draw semi-transparent fill to show sail area - only between boom and sail curve
    final fillPaint = Paint()
      ..color = sailColor.withValues(alpha: 0.2) // Same transparency for all sails
      ..style = PaintingStyle.fill;

    if (!isLuffing) {
      // Create filled sail shape: curved sail edge from mast top to boom end,
      // then straight boom line back to mast top
      final fillPath = Path();
      fillPath.moveTo(center.dx, mastTopY); // Start at mast top

      // Add the curved sail edge using the same angle-based calculation
      final boomEndY = center.dy + 35 * scale;
      final absAWA = apparentWindAngle.abs();

      double boomAngle;
      if (absAWA < 60) {
        boomAngle = 10 + (absAWA - 40) * 0.5;
      } else if (absAWA < 90) {
        boomAngle = 20 + (absAWA - 60) * 1.0;
      } else if (absAWA < 150) {
        boomAngle = 50 + (absAWA - 90) * 0.583;
      } else {
        boomAngle = 85 + (absAWA - 150) * 0.167;
      }

      final boomLength = 69 * scale;
      final boomAngleRad = (boomAngle * sailSide) * pi / 180;
      final boomEndPoint = Offset(
        center.dx + (sin(boomAngleRad) * boomLength),
        boomEndY,
      );

      final sailBelly = sailDistance * 0.3;
      final controlPoint1 = Offset(
        center.dx + (sin(boomAngleRad) * boomLength * 0.3) + (sailSide * sailBelly * 0.5),
        mastTopY + (boomEndY - mastTopY) * 0.25,
      );
      final controlPoint2 = Offset(
        center.dx + (sin(boomAngleRad) * boomLength * 0.7) + (sailSide * sailBelly),
        mastTopY + (boomEndY - mastTopY) * 0.7,
      );

      fillPath.cubicTo(
        controlPoint1.dx, controlPoint1.dy,
        controlPoint2.dx, controlPoint2.dy,
        boomEndPoint.dx, boomEndPoint.dy,
      );

      // Close back to mast top (this creates the straight boom line)
      fillPath.close();

      canvas.drawPath(fillPath, fillPaint);
    } else {
      // Luffing mode - fill the luffing shape
      final fillPath = Path.from(path);
      final totalHeight = 80 * scale;
      fillPath.lineTo(center.dx, mastTopY + totalHeight);
      fillPath.close();
      canvas.drawPath(fillPath, fillPaint);
    }
  }

  @override
  bool shouldRepaint(SailTrimIndicatorPainter oldDelegate) {
    return oldDelegate.apparentWindAngle != apparentWindAngle ||
           oldDelegate.targetAWA != targetAWA ||
           oldDelegate.targetTolerance != targetTolerance;
  }
}

