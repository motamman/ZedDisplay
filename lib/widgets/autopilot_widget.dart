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
  final double? apparentWindAngle; // Optional AWA for wind mode
  final double? crossTrackError; // Optional XTE for route mode
  final bool headingTrue; // True vs Magnetic heading
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
    this.crossTrackError,
    this.headingTrue = false,
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
      child: Stack(
        children: [
          // Fixed port/starboard arcs at top (drawn first, behind everything)
          Center(
            child: CustomPaint(
              size: const Size(200, 200),
              painter: _PortStarboardArcsPainter(),
            ),
          ),

          // Rotating compass card (marine style)
          Transform.rotate(
            angle: -currentHeading * math.pi / 180, // Rotate card opposite to heading
            child: SfRadialGauge(
              axes: <RadialAxis>[
                RadialAxis(
                  minimum: 0,
                  maximum: 360,
                  interval: 30,
                  startAngle: 270,
                  endAngle: 270,
                  showAxisLine: false,
                  showLastLabel: true,

                  // Tick configuration
                  majorTickStyle: const MajorTickStyle(
                    length: 12,
                    thickness: 2,
                    color: Colors.grey,
                  ),
                  minorTicksPerInterval: 2,
                  minorTickStyle: MinorTickStyle(
                    length: 6,
                    thickness: 1,
                    color: Colors.grey.withValues(alpha: 0.5),
                  ),

                  // Labels that rotate with the card
                  axisLabelStyle: const GaugeTextStyle(
                    color: Colors.grey,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  labelOffset: 20,
                  onLabelCreated: (args) => _customizeLabel(args),

                  // Outer ring only
                  ranges: [
                    GaugeRange(
                      startValue: 0,
                      endValue: 360,
                      color: Colors.grey.withValues(alpha: 0.2),
                      startWidth: 2,
                      endWidth: 2,
                    ),
                  ],

                  // Target heading marker on rotating card
                  pointers: [
                    MarkerPointer(
                      value: targetHeading,
                      markerType: MarkerType.triangle,
                      markerHeight: 20,
                      markerWidth: 20,
                      color: primaryColor,
                      markerOffset: -15,
                    ),
                  ],

                  annotations: const [],
                ),
              ],
            ),
          ),

          // Fixed needle pointing up (current heading direction)
          Center(
            child: CustomPaint(
              size: const Size(200, 200),
              painter: _FixedNeedlePainter(primaryColor),
            ),
          ),

          // Center annotation with target heading value (non-rotating)
          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.only(top: 60.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'TARGET',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w300,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${targetHeading.toStringAsFixed(0)}°',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  Text(
                    mode.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white70,
                    ),
                  ),
                ],
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
      ),
    );
  }

  void _customizeLabel(AxisLabelCreatedArgs args) {
    // Replace degree labels with cardinal directions
    switch (args.text) {
      case '0':
        args.text = 'N';
        args.labelStyle = GaugeTextStyle(
          color: primaryColor,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        );
        break;
      case '90':
        args.text = 'E';
        break;
      case '180':
        args.text = 'S';
        break;
      case '270':
        args.text = 'W';
        break;
      case '30':
      case '60':
      case '120':
      case '150':
      case '210':
      case '240':
      case '300':
      case '330':
        args.text = '';
        break;
      default:
        args.text = '';
    }
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

/// Custom painter for the fixed needle pointing up
class _FixedNeedlePainter extends CustomPainter {
  final Color color;

  _FixedNeedlePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final northNeedleLength = radius * 0.8;
    final southTailLength = radius * 0.75;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    // Draw needle pointing up (North)
    final needlePath = Path();

    // North pointing needle
    needlePath.moveTo(center.dx, center.dy - northNeedleLength);
    needlePath.lineTo(center.dx - 8, center.dy);
    needlePath.lineTo(center.dx, center.dy - 10);
    needlePath.lineTo(center.dx + 8, center.dy);
    needlePath.close();

    // Draw shadow
    canvas.drawPath(needlePath, shadowPaint);

    // Draw needle
    canvas.drawPath(needlePath, paint);

    // South pointing tail
    final hslColor = HSLColor.fromColor(color);
    final darkerColor = hslColor.withLightness((hslColor.lightness - 0.3).clamp(0.0, 1.0)).toColor();

    final tailPaint = Paint()
      ..color = darkerColor
      ..style = PaintingStyle.fill;

    final tailPath = Path();
    tailPath.moveTo(center.dx, center.dy + southTailLength);
    tailPath.lineTo(center.dx - 6, center.dy);
    tailPath.lineTo(center.dx + 6, center.dy);
    tailPath.close();

    canvas.drawPath(tailPath, tailPaint);

    // Draw center knob
    final knobPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 10, knobPaint);

    final knobBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, 10, knobBorderPaint);
  }

  @override
  bool shouldRepaint(_FixedNeedlePainter oldDelegate) {
    return color != oldDelegate.color;
  }
}

/// Custom painter for fixed port/starboard arc indicators at the top
class _PortStarboardArcsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2.65; // Slightly smaller than compass radius

    // Port arc (red, left side - 45° arc from -135° to -45°)
    final portPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi * 0.75, // Start at -135° (top left)
      math.pi * 0.5, // Sweep 90° to top
      false,
      portPaint,
    );

    // Starboard arc (green, right side - 45° arc from -45° to 45°)
    final starboardPaint = Paint()
      ..color = Colors.green.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi * 0.25, // Start at -45° (top right)
      math.pi * 0.5, // Sweep 90° to top
      false,
      starboardPaint,
    );
  }

  @override
  bool shouldRepaint(_PortStarboardArcsPainter oldDelegate) {
    return false; // Static arcs, never need repainting
  }
}
