import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'dart:math' as math;
import 'base_compass.dart';

/// Full-featured autopilot control widget with compass display
/// Built on BaseCompass for consistent styling with wind compass
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

  // Vessel configuration
  final bool isSailingVessel; // Whether vessel is sailing type (shows wind mode & tack)

  // Polar configuration (for wind mode zones)
  final double targetAWA; // Optimal close-hauled angle (degrees)
  final double targetTolerance; // Acceptable deviation from target (degrees)

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
    this.isSailingVessel = true,
    this.targetAWA = 40.0,
    this.targetTolerance = 3.0,
    this.onEngageDisengage,
    this.onModeChange,
    this.onAdjustHeading,
    this.onTack,
  });

  /// Normalize angle to 0-360 range
  double _normalizeAngle(double angle) {
    while (angle < 0) angle += 360;
    while (angle >= 360) angle -= 360;
    return angle;
  }

  /// Build autopilot zones - SAME STYLE AS WIND COMPASS
  List<GaugeRange> _buildAutopilotZones(double primaryHeadingDegrees) {
    final zones = <GaugeRange>[];

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

    if (showWindIndicators && apparentWindAngle != null) {
      // WIND MODE - USE EXACT SAME ZONES AS WIND COMPASS
      final windDirection = _normalizeAngle(currentHeading + apparentWindAngle!);
      final effectiveTargetAWA = targetAWA; // Use configured target AWA
      final tolerance = targetTolerance; // Use configured tolerance

      // PORT SIDE - Gradiated Red Zones (darker = more important)
      addRange(windDirection - 60, windDirection - effectiveTargetAWA, Colors.red.withValues(alpha: 0.6));
      addRange(windDirection - 90, windDirection - 60, Colors.red.withValues(alpha: 0.4));
      addRange(windDirection - 110, windDirection - 90, Colors.red.withValues(alpha: 0.25));
      addRange(windDirection - 150, windDirection - 110, Colors.red.withValues(alpha: 0.15));

      // No-go zone (wind ± targetAWA)
      addRange(windDirection - effectiveTargetAWA, windDirection + effectiveTargetAWA, Colors.white.withValues(alpha: 0.3));

      // STARBOARD SIDE - Gradiated Green Zones (darker = more important)
      addRange(windDirection + effectiveTargetAWA, windDirection + 60, Colors.green.withValues(alpha: 0.6));
      addRange(windDirection + 60, windDirection + 90, Colors.green.withValues(alpha: 0.4));
      addRange(windDirection + 90, windDirection + 110, Colors.green.withValues(alpha: 0.25));
      addRange(windDirection + 110, windDirection + 150, Colors.green.withValues(alpha: 0.15));

      // PERFORMANCE ZONES - layer on top with narrower width to show as inner rings
      // PORT SIDE PERFORMANCE ZONES
      addRange(windDirection - effectiveTargetAWA - tolerance, windDirection - effectiveTargetAWA + tolerance,
               Colors.green.withValues(alpha: 0.8), width: 15);
      addRange(windDirection - effectiveTargetAWA - (2 * tolerance), windDirection - effectiveTargetAWA - tolerance,
               Colors.yellow.withValues(alpha: 0.7), width: 15);
      addRange(windDirection - effectiveTargetAWA + tolerance, windDirection - effectiveTargetAWA + (2 * tolerance),
               Colors.yellow.withValues(alpha: 0.7), width: 15);

      // STARBOARD SIDE PERFORMANCE ZONES
      addRange(windDirection + effectiveTargetAWA - tolerance, windDirection + effectiveTargetAWA + tolerance,
               Colors.green.withValues(alpha: 0.8), width: 15);
      addRange(windDirection + effectiveTargetAWA - (2 * tolerance), windDirection + effectiveTargetAWA - tolerance,
               Colors.yellow.withValues(alpha: 0.7), width: 15);
      addRange(windDirection + effectiveTargetAWA + tolerance, windDirection + effectiveTargetAWA + (2 * tolerance),
               Colors.yellow.withValues(alpha: 0.7), width: 15);

    } else {
      // HEADING MODE - Simple port/starboard zones
      addRange(currentHeading - 180, currentHeading, Colors.red.withValues(alpha: 0.3));
      addRange(currentHeading, currentHeading + 180, Colors.green.withValues(alpha: 0.3));
    }

    return zones;
  }

  /// Build autopilot pointers (target, current heading, wind)
  List<GaugePointer> _buildAutopilotPointers(double primaryHeadingDegrees) {
    final pointers = <GaugePointer>[];

    // Determine which heading is primary (being used for compass rotation)
    final usingTrueHeading = headingTrue;

    // Target heading marker (needle with rounded end) - drawn first (below)
    pointers.add(NeedlePointer(
      value: targetHeading,
      needleLength: 0.92,
      needleStartWidth: 0,
      needleEndWidth: 10,
      needleColor: primaryColor,
      knobStyle: const KnobStyle(knobRadius: 0),
    ));

    // Rounded end for target heading indicator
    pointers.add(MarkerPointer(
      value: targetHeading,
      markerType: MarkerType.circle,
      markerHeight: 16,
      markerWidth: 16,
      color: primaryColor,
      markerOffset: -5,
    ));

    // Current heading indicator - only show dot (no needle) since vessel shadow shows direction
    // Rounded end for current heading indicator
    pointers.add(MarkerPointer(
      value: currentHeading,
      markerType: MarkerType.circle,
      markerHeight: 11,
      markerWidth: 11,
      color: Colors.yellow,
      markerOffset: -5,
    ));

    // WIND INDICATORS - only show in wind mode
    if (showWindIndicators) {
      // Apparent wind direction - primary (blue)
      if (apparentWindDirection != null) {
        pointers.add(NeedlePointer(
          value: apparentWindDirection!,
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

      // True wind direction - secondary (green)
      if (trueWindDirection != null) {
        pointers.add(NeedlePointer(
          value: trueWindDirection!,
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
    }

    return pointers;
  }

  /// Build custom painters (no-go zone for wind mode)
  /// Note: Sail trim indicator is now handled by BaseCompass automatically
  List<CustomPainter> _buildCustomPainters(double primaryHeadingRadians, double primaryHeadingDegrees) {
    final painters = <CustomPainter>[];

    if (showWindIndicators && apparentWindAngle != null) {
      painters.add(_NoGoZoneVPainter(
        windDirection: _normalizeAngle(currentHeading + apparentWindAngle!),
        noGoAngle: targetAWA,
      ));
    }

    return painters;
  }

  /// Build autopilot overlay (minimal - just shows mode/target info)
  /// Build heading display for top row (with orange dot)
  Widget _buildHeadingLabel(double headingDegrees, bool isTrue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'HDG',
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
                color: Colors.orange,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
        Text(
          '${headingDegrees.toStringAsFixed(0)}°${isTrue ? 'T' : 'M'}',
          style: const TextStyle(
            fontSize: 16,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// Empty builder to hide heading labels inside compass
  Widget _buildEmptyHeadingDisplay(double headingDegrees, bool isActive) {
    return const SizedBox.shrink();
  }

  /// Build target info box
  Widget _buildTargetInfoBox() {
    // Calculate heading error
    double error = currentHeading - targetHeading;
    while (error > 180) error -= 360;
    while (error < -180) error += 360;

    Color errorColor;
    if (error.abs() < 3) {
      errorColor = Colors.green;
    } else if (error.abs() < 10) {
      errorColor = Colors.yellow;
    } else {
      errorColor = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: primaryColor, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            mode.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white60,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'TGT: ',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white60,
                ),
              ),
              Text(
                '${targetHeading.toStringAsFixed(0)}°',
                style: TextStyle(
                  fontSize: 16,
                  color: primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${error > 0 ? '+' : ''}${error.toStringAsFixed(1)}°',
                style: TextStyle(
                  fontSize: 12,
                  color: errorColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAutopilotOverlay(double primaryHeadingDegrees) {
    return Stack(
      children: [
        // XTE display (right side below heading display) if available and reasonable
        // Only show XTE if < 10nm (~18520m) to filter out bad data
        if (crossTrackError != null && crossTrackError!.abs() < 18520)
          Positioned(
            right: 16,
            bottom: 100,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: crossTrackError! >= 0 ? Colors.green : Colors.red,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'XTE',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white60,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    crossTrackError!.abs() >= 1000
                        ? '${(crossTrackError!.abs() / 1000).toStringAsFixed(2)}'
                        : '${crossTrackError!.abs().toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${crossTrackError!.abs() >= 1000 ? 'km' : 'm'} ${crossTrackError! >= 0 ? 'STBD' : 'PORT'}',
                    style: TextStyle(
                      fontSize: 10,
                      color: crossTrackError! >= 0 ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    // Convert heading to radians for rotation
    final headingRadians = currentHeading * math.pi / 180;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          // Compass with overlaid controls (85% size, centered)
          Center(
            child: FractionallySizedBox(
              widthFactor: 0.85,
              heightFactor: 0.85,
              child: BaseCompass(
                headingTrueRadians: headingTrue ? headingRadians : null,
                headingMagneticRadians: !headingTrue ? headingRadians : null,
                headingTrueDegrees: headingTrue ? currentHeading : null,
                headingMagneticDegrees: !headingTrue ? currentHeading : null,
                isSailingVessel: isSailingVessel,
                apparentWindAngle: apparentWindAngle,
                targetAWA: targetAWA,
                targetTolerance: targetTolerance,
                rangesBuilder: _buildAutopilotZones,
                pointersBuilder: _buildAutopilotPointers,
                customPaintersBuilder: _buildCustomPainters,
                overlayBuilder: _buildAutopilotOverlay,
                magneticHeadingDisplayBuilder: _buildEmptyHeadingDisplay,
                trueHeadingDisplayBuilder: _buildEmptyHeadingDisplay,
                allowHeadingModeToggle: false, // Autopilot uses one mode
              ),
            ),
          ),

          // Target box - top left corner
          Positioned(
            left: 16,
            top: 16,
            child: _buildTargetInfoBox(),
          ),

          // Heading label - top right corner
          Positioned(
            right: 16,
            top: 16,
            child: _buildHeadingLabel(currentHeading, headingTrue),
          ),

          // Tack Port button - left side, aligned with compass midline (only for sailing vessels in Auto/Wind mode)
          if (isSailingVessel && engaged && (mode == 'Auto' || mode == 'Wind'))
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 75,
                  child: ElevatedButton(
                    onPressed: () => onTack?.call('port'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withValues(alpha: 0.6),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text('TACK\nPORT',
                      style: TextStyle(fontSize: 9),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),

          // Tack Starboard button - right side, aligned with compass midline (only for sailing vessels in Auto/Wind mode)
          if (isSailingVessel && engaged && (mode == 'Auto' || mode == 'Wind'))
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 75,
                  child: ElevatedButton(
                    onPressed: () => onTack?.call('starboard'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.withValues(alpha: 0.6),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text('TACK\nSTBD',
                      style: TextStyle(fontSize: 9),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),

          // Controls overlay - bottom third of compass
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.7),
                    Colors.black.withValues(alpha: 0.9),
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),

                  // Mode selector and engage/disengage
                  _buildModeControls(context),

                  const SizedBox(height: 10),

                  // Heading adjustment buttons (for all vessels in Auto/Compass/Wind mode)
                  if (engaged && (mode == 'Auto' || mode == 'Compass' || mode == 'Wind'))
                    _buildHeadingControls(),

                  const SizedBox(height: 10),

                  // Rudder indicator
                  _buildRudderIndicator(),

                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
                    final normalizedPosition = (rudderAngle + 35) / 70;
                    final leftPosition = (constraints.maxWidth * normalizedPosition) - 4;

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        Container(
                          width: 2,
                          height: 30,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
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
            icon: const Icon(Icons.navigation, size: 18),
            label: Text('Mode: $mode', style: const TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              backgroundColor: Colors.black.withValues(alpha: 0.3),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: onEngageDisengage,
            style: ElevatedButton.styleFrom(
              backgroundColor: (engaged ? Colors.red : Colors.green).withValues(alpha: 0.7),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            child: Text(
              engaged ? 'DISENGAGE' : 'ENGAGE',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
            // Wind mode only for sailing vessels
            if (isSailingVessel)
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildAdjustButton('-10°', -10),
            _buildAdjustButton('-1°', -1),
            _buildAdjustButton('+1°', 1),
            _buildAdjustButton('+10°', 10),
          ],
        ),
        const SizedBox(height: 12),
        _HeadingAdjustmentSlider(
          onAdjustHeading: onAdjustHeading,
        ),
      ],
    );
  }

  Widget _buildAdjustButton(String label, int degrees) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: ElevatedButton(
          onPressed: () => onAdjustHeading?.call(degrees),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 10),
            backgroundColor: Colors.blue.withValues(alpha: 0.6),
          ),
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }

}

/// Stateful slider widget for fine-grained heading adjustments
class _HeadingAdjustmentSlider extends StatefulWidget {
  final Function(int degrees)? onAdjustHeading;

  const _HeadingAdjustmentSlider({
    this.onAdjustHeading,
  });

  @override
  State<_HeadingAdjustmentSlider> createState() => _HeadingAdjustmentSliderState();
}

class _HeadingAdjustmentSliderState extends State<_HeadingAdjustmentSlider> {
  double _sliderValue = 0.0;
  bool _isDragging = false;

  Future<void> _showConfirmationDialog(int degrees) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Heading Adjustment'),
        content: Text(
          'Adjust heading by ${degrees > 0 ? '+' : ''}$degrees°?',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
            ),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      widget.onAdjustHeading?.call(degrees);
    }

    // Reset slider to 0 regardless of choice
    setState(() {
      _sliderValue = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Change Course',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${_sliderValue.round() > 0 ? '+' : ''}${_sliderValue.round()}°',
                style: TextStyle(
                  fontSize: 14,
                  color: _sliderValue.round() == 0
                      ? Colors.white70
                      : (_sliderValue > 0 ? Colors.green : Colors.red),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.grey.withValues(alpha: 0.3),
              inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
              thumbColor: _sliderValue.round() == 0
                  ? Colors.white
                  : (_sliderValue > 0 ? Colors.green : Colors.red),
              overlayColor: (_sliderValue > 0 ? Colors.green : Colors.red).withValues(alpha: 0.2),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: _sliderValue,
              min: -180,
              max: 180,
              divisions: 360,
              onChanged: (value) {
                setState(() {
                  _sliderValue = value;
                  _isDragging = true;
                });
              },
              onChangeEnd: (value) {
                if (value.round() != 0) {
                  _showConfirmationDialog(value.round());
                }
                setState(() {
                  _isDragging = false;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for no-go zone V-shape
class _NoGoZoneVPainter extends CustomPainter {
  final double windDirection;
  final double noGoAngle;

  _NoGoZoneVPainter({
    required this.windDirection,
    required this.noGoAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 * 0.95;

    final windRad = windDirection * math.pi / 180;
    final noGoRad = noGoAngle * math.pi / 180;

    final leftAngle = windRad - noGoRad;

    final path = Path();
    path.moveTo(center.dx, center.dy);

    path.lineTo(
      center.dx + radius * math.cos(leftAngle),
      center.dy + radius * math.sin(leftAngle),
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
  bool shouldRepaint(_NoGoZoneVPainter oldDelegate) {
    return oldDelegate.windDirection != windDirection ||
           oldDelegate.noGoAngle != noGoAngle;
  }
}
