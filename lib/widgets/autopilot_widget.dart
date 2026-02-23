import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'dart:math' as math;
import 'dart:async';
import 'base_compass.dart';
import 'route_info_panel.dart';
import '../utils/angle_utils.dart';
import '../utils/compass_zone_builder.dart';

/// Full-featured autopilot control widget with compass display
/// Built on BaseCompass for consistent styling with wind compass
class AutopilotWidget extends StatefulWidget {
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

  // Route navigation data
  final LatLon? nextWaypoint;
  final DateTime? eta;
  final double? distanceToWaypoint;
  final Duration? timeToWaypoint;
  final bool onlyShowXTEWhenNear;

  // Callbacks
  final VoidCallback? onEngageDisengage;
  final Function(String mode)? onModeChange;
  final Function(int degrees)? onAdjustHeading;
  final Function(String direction)? onTack;
  final Function(String direction)? onGybe;
  final VoidCallback? onAdvanceWaypoint;
  final VoidCallback? onDodgeToggle;

  // API version and V2 features
  final bool isV2Api; // Whether using V2 API (enables V2-only features)
  final bool dodgeActive; // Whether dodge mode is currently active

  // Fade configuration
  final int fadeDelaySeconds; // Seconds before controls fade after activity

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
    this.nextWaypoint,
    this.eta,
    this.distanceToWaypoint,
    this.timeToWaypoint,
    this.onlyShowXTEWhenNear = true,
    this.onEngageDisengage,
    this.onModeChange,
    this.onAdjustHeading,
    this.onTack,
    this.onGybe,
    this.onAdvanceWaypoint,
    this.onDodgeToggle,
    this.isV2Api = false,
    this.dodgeActive = false,
    this.fadeDelaySeconds = 5,
  });

  @override
  State<AutopilotWidget> createState() => _AutopilotWidgetState();
}

class _AutopilotWidgetState extends State<AutopilotWidget> {
  Timer? _dimTimer;
  double _controlsOpacity = 0.7;

  @override
  void dispose() {
    _dimTimer?.cancel();
    super.dispose();
  }

  void _onHeadingAdjustmentSent() {
    // Cancel any existing timer
    _dimTimer?.cancel();

    // Reset opacity to normal (70%)
    setState(() {
      _controlsOpacity = 0.7;
    });

    // Start configurable timer to dim controls
    _dimTimer = Timer(Duration(seconds: widget.fadeDelaySeconds), () {
      setState(() {
        _controlsOpacity = 0.2;
      });
    });
  }

  void _onScreenTap() {
    // Cancel any existing timer
    _dimTimer?.cancel();

    // Restore normal opacity (70%)
    setState(() {
      _controlsOpacity = 0.7;
    });
  }

  void _onCompassDoubleTap() {
    // Double-tap on compass triggers disengage
    if (widget.engaged) {
      widget.onEngageDisengage?.call();
      _onHeadingAdjustmentSent();
    }
  }

  // Removed: _normalizeAngle - now using AngleUtils.normalize()

  /// Build autopilot zones - SAME STYLE AS WIND COMPASS
  List<GaugeRange> _buildAutopilotZones(double primaryHeadingDegrees) {
    final builder = CompassZoneBuilder();

    if (widget.showWindIndicators && widget.apparentWindAngle != null) {
      // WIND MODE - USE EXACT SAME ZONES AS WIND COMPASS
      final windDirection = AngleUtils.normalize(widget.currentHeading + widget.apparentWindAngle!);

      builder.addSailingZones(
        windDirection: windDirection,
        targetAWA: widget.targetAWA,
        targetTolerance: widget.targetTolerance,
      );
    } else {
      // HEADING MODE - Simple port/starboard zones
      builder.addHeadingZones(currentHeading: widget.currentHeading);
    }

    return builder.zones;
  }

  /// Build autopilot pointers (target, current heading, wind)
  List<GaugePointer> _buildAutopilotPointers(double primaryHeadingDegrees) {
    final pointers = <GaugePointer>[];

    // Determine which heading is primary (being used for compass rotation)
    // final usingTrueHeading = widget.headingTrue; // Unused for now

    // Target heading marker (needle with rounded end) - drawn first (below)
    pointers.add(NeedlePointer(
      value: widget.targetHeading,
      needleLength: 0.92,
      needleStartWidth: 0,
      needleEndWidth: 10,
      needleColor: widget.primaryColor,
      knobStyle: const KnobStyle(knobRadius: 0),
    ));

    // Rounded end for target heading indicator
    pointers.add(MarkerPointer(
      value: widget.targetHeading,
      markerType: MarkerType.circle,
      markerHeight: 16,
      markerWidth: 16,
      color: widget.primaryColor,
      markerOffset: -5,
    ));

    // Current heading indicator - only show dot (no needle) since vessel shadow shows direction
    // Rounded end for current heading indicator
    pointers.add(MarkerPointer(
      value: widget.currentHeading,
      markerType: MarkerType.circle,
      markerHeight: 11,
      markerWidth: 11,
      color: Colors.yellow,
      markerOffset: -5,
    ));

    // WIND INDICATORS - only show in wind mode
    if (widget.showWindIndicators) {
      // Apparent wind direction - primary (blue)
      if (widget.apparentWindDirection != null) {
        pointers.add(NeedlePointer(
          value: widget.apparentWindDirection!,
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
      if (widget.trueWindDirection != null) {
        pointers.add(NeedlePointer(
          value: widget.trueWindDirection!,
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

    if (widget.showWindIndicators && widget.apparentWindAngle != null) {
      painters.add(_NoGoZoneVPainter(
        windDirection: AngleUtils.normalize(widget.currentHeading + widget.apparentWindAngle!),
        noGoAngle: widget.targetAWA,
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
    double error = widget.currentHeading - widget.targetHeading;
    while (error > 180) {
      error -= 360;
    }
    while (error < -180) {
      error += 360;
    }

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
        border: Border.all(color: widget.primaryColor, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.mode.toUpperCase(),
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
                '${widget.targetHeading.toStringAsFixed(0)}°',
                style: TextStyle(
                  fontSize: 16,
                  color: widget.primaryColor,
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
        if (widget.crossTrackError != null && widget.crossTrackError!.abs() < 18520)
          Positioned(
            right: 16,
            bottom: 100,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: widget.crossTrackError! >= 0 ? Colors.green : Colors.red,
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
                    widget.crossTrackError!.abs() >= 1000
                        ? (widget.crossTrackError!.abs() / 1000).toStringAsFixed(2)
                        : widget.crossTrackError!.abs().toStringAsFixed(0),
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${widget.crossTrackError!.abs() >= 1000 ? 'km' : 'm'} ${widget.crossTrackError! >= 0 ? 'STBD' : 'PORT'}',
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.crossTrackError! >= 0 ? Colors.green : Colors.red,
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


  /// Build the compass area with overlays (target box, heading label, tack buttons, route info)
  Widget _buildCompassArea(double headingRadians) {
    return Stack(
      children: [
        // Compass with overlaid controls (85% size, centered)
        Center(
          child: FractionallySizedBox(
            widthFactor: 0.85,
            heightFactor: 0.85,
            child: BaseCompass(
              headingTrueRadians: widget.headingTrue ? headingRadians : null,
              headingMagneticRadians: !widget.headingTrue ? headingRadians : null,
              headingTrueDegrees: widget.headingTrue ? widget.currentHeading : null,
              headingMagneticDegrees: !widget.headingTrue ? widget.currentHeading : null,
              isSailingVessel: widget.isSailingVessel,
              apparentWindAngle: widget.apparentWindAngle,
              targetAWA: widget.targetAWA,
              targetTolerance: widget.targetTolerance,
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
          child: _buildHeadingLabel(widget.currentHeading, widget.headingTrue),
        ),

        // Tack Port button - left side, aligned with compass midline (only for sailing vessels in Auto/Wind mode)
        if (widget.isSailingVessel && widget.engaged && (widget.mode == 'Auto' || widget.mode == 'Wind'))
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: AnimatedOpacity(
              opacity: _controlsOpacity,
              duration: const Duration(milliseconds: 300),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 75,
                  child: ElevatedButton(
                    onPressed: () {
                      widget.onTack?.call('port');
                      _onHeadingAdjustmentSent();
                    },
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
          ),

        // Tack Starboard button - right side, aligned with compass midline (only for sailing vessels in Auto/Wind mode)
        if (widget.isSailingVessel && widget.engaged && (widget.mode == 'Auto' || widget.mode == 'Wind'))
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: AnimatedOpacity(
              opacity: _controlsOpacity,
              duration: const Duration(milliseconds: 300),
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 75,
                  child: ElevatedButton(
                    onPressed: () {
                      widget.onTack?.call('starboard');
                      _onHeadingAdjustmentSent();
                    },
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
          ),

        // Route info panel - middle area (only in route/nav mode with route data, hidden during dodge)
        if ((widget.mode.toLowerCase() == 'route' || widget.mode.toLowerCase() == 'nav') &&
            widget.nextWaypoint != null &&
            !widget.dodgeActive)
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: AnimatedOpacity(
              opacity: _controlsOpacity,
              duration: const Duration(milliseconds: 300),
              child: RouteInfoPanel(
                nextWaypoint: widget.nextWaypoint,
                eta: widget.eta,
                distanceToWaypoint: widget.distanceToWaypoint,
                timeToWaypoint: widget.timeToWaypoint,
                crossTrackError: widget.crossTrackError,
                onlyShowXTEWhenNear: widget.onlyShowXTEWhenNear,
              ),
            ),
          ),

        // Dodge mode indicator (top center when active)
        if (widget.dodgeActive)
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'DODGE MODE ACTIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Build the controls panel (mode, heading adj, gybe, dodge, advance WP, rudder)
  Widget _buildControlsPanel({bool isWideLayout = false}) {
    return AnimatedOpacity(
      opacity: _controlsOpacity,
      duration: const Duration(milliseconds: 300),
      child: Container(
        decoration: isWideLayout
            ? BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              )
            : BoxDecoration(
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
        padding: isWideLayout ? const EdgeInsets.all(12) : EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: isWideLayout ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            const SizedBox(height: 12),

            // Mode selector and engage/disengage
            _buildModeControls(context),

            const SizedBox(height: 10),

            // Heading adjustment buttons (for all vessels in Auto/Compass/Wind mode)
            if (widget.engaged && (widget.mode == 'Auto' || widget.mode == 'Compass' || widget.mode == 'Wind'))
              _buildHeadingControls(),

            // Gybe buttons (V2 only, sailing vessels, wind mode for downwind sailing)
            if (widget.isV2Api && widget.isSailingVessel && widget.engaged && widget.mode == 'Wind')
              _buildGybeControls(),

            // Dodge mode toggle (V2 only, route/nav mode)
            if (widget.isV2Api && widget.engaged && (widget.mode.toLowerCase() == 'route' || widget.mode.toLowerCase() == 'nav'))
              _buildDodgeModeToggle(),

            // Advance waypoint button (only in route/nav mode, hidden during dodge)
            if (widget.engaged &&
                (widget.mode.toLowerCase() == 'route' || widget.mode.toLowerCase() == 'nav') &&
                !widget.dodgeActive)
              _buildAdvanceWaypointButton(),

            const SizedBox(height: 10),

            // Rudder indicator
            _buildRudderIndicator(),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Convert heading to radians for rotation
    final headingRadians = widget.currentHeading * math.pi / 180;

    // Wrap entire widget with double-tap handler to capture gestures even over buttons
    return GestureDetector(
      onDoubleTap: _onCompassDoubleTap,
      behavior: HitTestBehavior.translucent,
      child: GestureDetector(
        onTap: _onScreenTap,
        behavior: HitTestBehavior.translucent,
        child: Container(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 600;

              final compassWidget = _buildCompassArea(headingRadians);
              final controlsWidget = _buildControlsPanel(isWideLayout: isWide);

              if (isWide) {
                // Side-by-side: compass left (max 50%), controls right
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Compass area - max 50% width
                    SizedBox(
                      width: constraints.maxWidth * 0.5 - 8,
                      child: compassWidget,
                    ),
                    const SizedBox(width: 16),
                    // Controls - remaining space, centered vertically
                    Expanded(
                      child: Center(child: controlsWidget),
                    ),
                  ],
                );
              } else {
                // Stacked: compass top, controls below
                return Stack(
                  children: [
                    // Compass fills available space
                    Positioned.fill(child: compassWidget),
                    // Controls overlay at bottom
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: controlsWidget,
                    ),
                  ],
                );
              }
            },
          ),
        ),
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
                    final normalizedPosition = (widget.rudderAngle + 35) / 70;
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
                              color: widget.rudderAngle < 0 ? Colors.red : Colors.green,
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
                          '${widget.rudderAngle.toStringAsFixed(0)}°',
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
            onPressed: () {
              _onScreenTap(); // Reset timer when opening menu
              _showModeMenu(context);
            },
            icon: const Icon(Icons.navigation, size: 18),
            label: Text('Mode: ${widget.mode}', style: const TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              backgroundColor: Colors.black.withValues(alpha: 0.3),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              widget.onEngageDisengage?.call();
              _onHeadingAdjustmentSent();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: (widget.engaged ? Colors.red : Colors.green).withValues(alpha: 0.7),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            child: Text(
              widget.engaged ? 'DISENGAGE' : 'ENGAGE',
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
            if (widget.isSailingVessel)
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
    final isSelected = widget.mode == modeOption;
    return ListTile(
      leading: Icon(
        isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
        color: isSelected ? widget.primaryColor : Colors.grey,
      ),
      title: Text(modeOption),
      subtitle: Text(description, style: const TextStyle(fontSize: 12)),
      onTap: () {
        widget.onModeChange?.call(modeOption);
        _onHeadingAdjustmentSent();
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
      ],
    );
  }

  Widget _buildAdjustButton(String label, int degrees) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: ElevatedButton(
          onPressed: () {
            widget.onAdjustHeading?.call(degrees);
            _onHeadingAdjustmentSent();
          },
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 10),
            backgroundColor: Colors.blue.withValues(alpha: 0.6),
          ),
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }

  Widget _buildAdvanceWaypointButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ElevatedButton.icon(
        onPressed: widget.onAdvanceWaypoint,
        icon: const Icon(Icons.skip_next),
        label: const Text('ADVANCE WAYPOINT'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue.withValues(alpha: 0.6),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildGybeControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => widget.onGybe?.call('port'),
              icon: const Icon(Icons.directions_boat, size: 16),
              label: const Text('GYBE PORT'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.withValues(alpha: 0.6),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => widget.onGybe?.call('starboard'),
              icon: const Icon(Icons.directions_boat, size: 16),
              label: const Text('GYBE STBD'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.withValues(alpha: 0.6),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDodgeModeToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ElevatedButton.icon(
        onPressed: widget.onDodgeToggle,
        icon: Icon(widget.dodgeActive ? Icons.cancel : Icons.edit_road),
        label: Text(widget.dodgeActive ? 'DEACTIVATE DODGE' : 'ACTIVATE DODGE'),
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.dodgeActive
              ? Colors.orange.withValues(alpha: 0.8)
              : Colors.blue.withValues(alpha: 0.6),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
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
