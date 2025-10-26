import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'dart:math' as math;

/// Full-featured autopilot control widget with compass display
/// Based on marine compass style with rotating card
class AutopilotWidget extends StatelessWidget {
  final double currentHeading; // Current heading in degrees (0-360)
  final double targetHeading; // Target autopilot heading
  final double rudderAngle; // Rudder angle (-35 to +35 degrees)
  final String mode; // Current autopilot mode
  final bool engaged; // Autopilot engaged/disengaged
  final double? apparentWindAngle; // Optional AWA for wind mode (relative angle)
  final double? apparentWindDirection; // Optional apparent wind direction (absolute, 0-360)
  final double? trueWindDirection; // Optional true wind direction (absolute, 0-360)
  final double? crossTrackError; // Optional XTE for route mode
  final bool headingTrue; // True vs Magnetic heading
  final bool showWindIndicators; // Whether to show wind needles
  final Color primaryColor;

  // Callbacks
  final VoidCallback? onEngageDisengage;
  final Function(String mode)? onModeChange;
  final Function(int degrees)? onAdjustHeading;
  final Function(String direction)? onTack;

  const AutopilotWidget({
    super.key,
    required this.currentHeading,
    required this.targetHeading,
    required this.rudderAngle,
    this.mode = 'Standby',
    this.engaged = false,
    this.apparentWindAngle,
    this.apparentWindDirection,
    this.trueWindDirection,
    this.crossTrackError,
    this.headingTrue = false,
    this.showWindIndicators = false,
    this.primaryColor = Colors.red,
    this.onEngageDisengage,
    this.onModeChange,
    this.onAdjustHeading,
    this.onTack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Compass display
          Expanded(
            flex: 3,
            child: _buildCompassDisplay(),
          ),

          const SizedBox(height: 16),

          // Rudder indicator
          _buildRudderIndicator(),

          const SizedBox(height: 16),

          // Mode selector and engage/disengage
          _buildModeControls(context),

          const SizedBox(height: 12),

          // Heading adjustment buttons
          if (engaged && (mode == 'Auto' || mode == 'Compass'))
            _buildHeadingControls(),

          const SizedBox(height: 12),

          // Tack buttons
          if (engaged && (mode == 'Auto' || mode == 'Wind'))
            _buildTackButtons(),
        ],
      ),
    );
  }

  Widget _buildCompassDisplay() {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            children: [
              // Vessel shadow in center - FIXED pointing up
              Center(
                child: CustomPaint(
                  size: size,
                  painter: _VesselShadowPainter(),
                ),
              ),

              // No-go zone V-shape - only in wind mode
              if (showWindIndicators && apparentWindAngle != null)
                Transform.rotate(
                  angle: -currentHeading * math.pi / 180 - (math.pi / 2),
                  child: CustomPaint(
                    size: size,
                    painter: _NoGoZoneVPainter(
                      windDirection: _normalizeAngle(currentHeading + apparentWindAngle!),
                    ),
                  ),
                ),

              // Rotating compass card (marine style)
              Transform.rotate(
                angle: -currentHeading * math.pi / 180 - (math.pi / 2), // Rotate card opposite to heading, compensate for 90° offset
                child: SfRadialGauge(
              axes: <RadialAxis>[
                RadialAxis(
                  minimum: 0,
                  maximum: 360,
                  interval: 30,
                  startAngle: 0,
                  endAngle: 360,
                  showAxisLine: false,
                  showLastLabel: false,

                  // Tick configuration - match wind compass style
                  majorTickStyle: const MajorTickStyle(
                    length: 15,
                    thickness: 2,
                    color: Colors.white70,
                  ),
                  minorTicksPerInterval: 2,
                  minorTickStyle: const MinorTickStyle(
                    length: 8,
                    thickness: 1,
                    color: Colors.white30,
                  ),

                  // Hide auto-generated labels - we'll add counter-rotating ones
                  showLabels: false,

                  // Zones: wind-based in wind mode, heading-based otherwise
                  ranges: showWindIndicators && apparentWindAngle != null
                      ? _buildWindSailingZones()
                      : _buildHeadingZones(),

                  // Target heading marker on rotating card
                  pointers: [
                    // Target heading marker (needle with rounded end) - drawn first (below)
                    NeedlePointer(
                      value: targetHeading,
                      needleLength: 0.92,
                      needleStartWidth: 0,
                      needleEndWidth: 10,
                      needleColor: primaryColor,
                      knobStyle: const KnobStyle(
                        knobRadius: 0,
                      ),
                    ),
                    // Rounded end for target heading indicator
                    MarkerPointer(
                      value: targetHeading,
                      markerType: MarkerType.circle,
                      markerHeight: 16,
                      markerWidth: 16,
                      color: primaryColor,
                      markerOffset: -5,
                    ),

                    // Current heading indicator - drawn second (on top), 1/3 smaller
                    NeedlePointer(
                      value: currentHeading,
                      needleLength: 0.92,
                      needleStartWidth: 0,
                      needleEndWidth: 7, // 1/3 smaller (was 10)
                      needleColor: Colors.yellow,
                      knobStyle: const KnobStyle(
                        knobRadius: 0,
                      ),
                    ),
                    // Rounded end for current heading indicator
                    MarkerPointer(
                      value: currentHeading,
                      markerType: MarkerType.circle,
                      markerHeight: 11, // 1/3 smaller (was 16)
                      markerWidth: 11,
                      color: Colors.yellow,
                      markerOffset: -5,
                    ),

                    // WIND INDICATORS - only show in wind mode
                    // Apparent wind direction - primary (blue)
                    if (showWindIndicators && apparentWindDirection != null)
                      NeedlePointer(
                        value: apparentWindDirection!,
                        needleLength: 0.95,
                        needleStartWidth: 5,
                        needleEndWidth: 0,
                        needleColor: Colors.blue,
                        knobStyle: const KnobStyle(
                          knobRadius: 0.03,
                          color: Colors.blue,
                        ),
                      ),

                    // True wind direction - secondary (green/cyan)
                    if (showWindIndicators && trueWindDirection != null)
                      NeedlePointer(
                        value: trueWindDirection!,
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

                  // Counter-rotating compass labels
                  annotations: _buildCompassLabels(),
                ),
              ],
            ),
          ),

              // Center annotation with target heading value (non-rotating)
              // Positioned below the white center dot, inside vessel shape
              Positioned(
            top: size.height / 2 + 20, // Start just below the center dot (10px dot radius + 10px spacing)
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${targetHeading.toStringAsFixed(0)}°',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  mode.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'TARGET',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w300,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          // White circle in the center - above everything
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

          // HDG label (top left)
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'HDG',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  Text(
                    '${currentHeading.toStringAsFixed(0)}°${headingTrue ? 'T' : 'M'}',
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // AWA display (top right) if available
          if (apparentWindAngle != null)
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'AWA',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    Text(
                      '${apparentWindAngle!.abs().toStringAsFixed(0)}° ${apparentWindAngle! >= 0 ? 'S' : 'P'}',
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.cyan,
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

  /// Build counter-rotating compass labels (N, S, E, W, and degree numbers)
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
          labelColor = Colors.white54;
          fontSize = 16;
      }

      labels.add(
        GaugeAnnotation(
          widget: Transform.rotate(
            angle: currentHeading * math.pi / 180,  // Counter-rotate to keep upright
            child: Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontSize: fontSize,
                fontWeight: fontSize > 20 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          angle: i.toDouble(),
          positionFactor: 0.82,
        ),
      );
    }

    return labels;
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

  /// Build port/starboard zones based on heading (for non-wind modes)
  /// Red on port (left), green on starboard (right), each extending 135° from heading
  List<GaugeRange> _buildHeadingZones() {
    final zones = <GaugeRange>[];

    // Helper to add a range, splitting if it crosses 0°
    void addRange(double start, double end, Color color) {
      final startNorm = _normalizeAngle(start);
      final endNorm = _normalizeAngle(end);

      if (startNorm < endNorm) {
        // Normal case: doesn't cross 0°
        zones.add(GaugeRange(
          startValue: startNorm,
          endValue: endNorm,
          color: color,
          startWidth: 25,
          endWidth: 25,
        ));
      } else {
        // Crosses 0°: split into two ranges
        zones.add(GaugeRange(
          startValue: startNorm,
          endValue: 360,
          color: color,
          startWidth: 25,
          endWidth: 25,
        ));
        zones.add(GaugeRange(
          startValue: 0,
          endValue: endNorm,
          color: color,
          startWidth: 25,
          endWidth: 25,
        ));
      }
    }

    // Port (left/red): from heading - 135° to heading
    addRange(currentHeading - 135, currentHeading, Colors.red.withValues(alpha: 0.5));

    // Starboard (right/green): from heading to heading + 135°
    addRange(currentHeading, currentHeading + 135, Colors.green.withValues(alpha: 0.5));

    return zones;
  }

  /// Build sailing zones (red/white/green) based on apparent wind angle (for wind mode)
  List<GaugeRange> _buildWindSailingZones() {
    if (apparentWindAngle == null) return [];

    final zones = <GaugeRange>[];
    // Convert apparent wind angle (relative, -180 to +180) to absolute wind direction
    final windDirection = _normalizeAngle(currentHeading + apparentWindAngle!);

    // Helper to add a range, splitting if it crosses 0°
    void addRange(double start, double end, Color color) {
      final startNorm = _normalizeAngle(start);
      final endNorm = _normalizeAngle(end);

      if (startNorm < endNorm) {
        // Normal case: doesn't cross 0°
        zones.add(GaugeRange(
          startValue: startNorm,
          endValue: endNorm,
          color: color,
          startWidth: 25,
          endWidth: 25,
        ));
      } else {
        // Crosses 0°: split into two ranges
        zones.add(GaugeRange(
          startValue: startNorm,
          endValue: 360,
          color: color,
          startWidth: 25,
          endWidth: 25,
        ));
        zones.add(GaugeRange(
          startValue: 0,
          endValue: endNorm,
          color: color,
          startWidth: 25,
          endWidth: 25,
        ));
      }
    }

    // Red zone - port tack (wind - 135° to wind - 45°, extended to 90° wide)
    addRange(windDirection - 135, windDirection - 45, Colors.red.withValues(alpha: 0.5));

    // No-go zone (wind - 45° to wind + 45°)
    addRange(windDirection - 45, windDirection + 45, Colors.white.withValues(alpha: 0.3));

    // Green zone - starboard tack (wind + 45° to wind + 135°, extended to 90° wide)
    addRange(windDirection + 45, windDirection + 135, Colors.green.withValues(alpha: 0.5));

    return zones;
  }

  Widget _buildRudderIndicator() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const Text(
            'RUDDER',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Port', style: TextStyle(fontSize: 10, color: Colors.red)),
              const SizedBox(width: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Calculate rudder position within the available width
                    // rudderAngle ranges from -35 to +35 degrees
                    final normalizedPosition = (rudderAngle + 35) / 70; // 0.0 to 1.0
                    final leftPosition = (constraints.maxWidth * normalizedPosition) - 4; // -4 for half width of indicator

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Background bar
                        Container(
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        // Center line
                        Container(
                          width: 2,
                          height: 30,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        // Rudder position indicator
                        Positioned(
                          left: leftPosition.clamp(0.0, constraints.maxWidth - 8),
                          child: Container(
                            width: 8,
                            height: 30,
                            decoration: BoxDecoration(
                              color: rudderAngle < 0 ? Colors.red : Colors.green,
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Angle text
                        Text(
                          '${rudderAngle.toStringAsFixed(0)}°',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              const Text('Stbd', style: TextStyle(fontSize: 10, color: Colors.green)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeControls(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showModeMenu(context),
            icon: const Icon(Icons.navigation),
            label: Text('Mode: $mode'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: onEngageDisengage,
            style: ElevatedButton.styleFrom(
              backgroundColor: engaged ? Colors.red : Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(
              engaged ? 'DISENGAGE' : 'ENGAGE',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  void _showModeMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Select Mode',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildModeOption(context, 'Auto', 'Compass heading mode'),
            _buildModeOption(context, 'Wind', 'Wind angle mode'),
            _buildModeOption(context, 'Route', 'Route following mode'),
            _buildModeOption(context, 'Standby', 'Autopilot standby'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeOption(BuildContext context, String modeOption, String description) {
    final isSelected = mode == modeOption;
    return ListTile(
      leading: Icon(
        isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
        color: isSelected ? primaryColor : Colors.grey,
      ),
      title: Text(modeOption),
      subtitle: Text(description, style: const TextStyle(fontSize: 12)),
      onTap: () {
        onModeChange?.call(modeOption);
        Navigator.pop(context);
      },
    );
  }

  Widget _buildHeadingControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildAdjustButton('-10°', -10),
        _buildAdjustButton('-1°', -1),
        _buildAdjustButton('+1°', 1),
        _buildAdjustButton('+10°', 10),
      ],
    );
  }

  Widget _buildAdjustButton(String label, int degrees) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ElevatedButton(
          onPressed: () => onAdjustHeading?.call(degrees),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          child: Text(label),
        ),
      ),
    );
  }

  Widget _buildTackButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () => onTack?.call('port'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.withValues(alpha: 0.8),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text('TACK PORT'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: () => onTack?.call('starboard'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.withValues(alpha: 0.8),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text('TACK STBD'),
          ),
        ),
      ],
    );
  }
}

/// Custom painter for no-go zone V-shape
class _NoGoZoneVPainter extends CustomPainter {
  final double windDirection; // Wind direction in degrees (0-360)
  final double noGoAngle; // Half-angle of no-go zone (default 45°)

  _NoGoZoneVPainter({
    required this.windDirection,
    this.noGoAngle = 45.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 * 0.85; // 85% of radius to stay within compass

    // Convert to radians
    final windRad = windDirection * math.pi / 180;
    final noGoRad = noGoAngle * math.pi / 180;

    // Calculate the V-shape edges centered on wind direction
    final leftAngle = windRad - noGoRad;  // -45° from wind direction

    // Create path for V-shape
    final path = Path();
    path.moveTo(center.dx, center.dy); // Start at center

    // Left edge of V
    path.lineTo(
      center.dx + radius * math.cos(leftAngle),
      center.dy + radius * math.sin(leftAngle),
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
  bool shouldRepaint(_NoGoZoneVPainter oldDelegate) {
    return oldDelegate.windDirection != windDirection;
  }
}

/// Custom painter for vessel shadow in the center
class _VesselShadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = math.min(size.width, size.height) / 200; // Scale based on smaller dimension to fit inside compass rim

    // Create boat shape pointing up
    final path = Path();

    // Bow (front point) - larger vessel
    path.moveTo(center.dx, center.dy - 60 * scale);

    // Port side (left) - wider
    path.lineTo(center.dx - 30 * scale, center.dy + 40 * scale);

    // Stern (back) - wider
    path.lineTo(center.dx - 16 * scale, center.dy + 50 * scale);
    path.lineTo(center.dx + 16 * scale, center.dy + 50 * scale);

    // Starboard side (right) - wider
    path.lineTo(center.dx + 30 * scale, center.dy + 40 * scale);

    // Back to bow
    path.close();

    // Draw vessel shadow with semi-transparent black
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);

    // Add a subtle outline
    final outlinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    canvas.drawPath(path, outlinePaint);
  }

  @override
  bool shouldRepaint(_VesselShadowPainter oldDelegate) => false;
}
