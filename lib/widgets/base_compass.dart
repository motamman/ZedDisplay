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

  /// Build compass labels (N, S, E, W, degrees) as gauge annotations
  List<GaugeAnnotation> _buildCompassLabels() {
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
                      annotations: _buildCompassLabels(),
                    ),
                  ],
                ),
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

    // Bow (front point)
    path.moveTo(center.dx, center.dy - 60 * scale);

    // Port side (left)
    path.lineTo(center.dx - 30 * scale, center.dy + 40 * scale);

    // Stern (back)
    path.lineTo(center.dx - 16 * scale, center.dy + 50 * scale);
    path.lineTo(center.dx + 16 * scale, center.dy + 50 * scale);

    // Starboard side (right)
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
