import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'dart:math' as math;
import 'dart:async';
import 'base_compass.dart';
import 'route_info_panel.dart';
import '../utils/angle_utils.dart';
import '../utils/compass_zone_builder.dart';

/// Reimagined autopilot control widget with circular center controls
/// +10, -10, +1, -1 buttons are arced around the inner circle edge
class AutopilotWidgetV2 extends StatefulWidget {
  final double currentHeading;
  final double targetHeading;
  final double rudderAngle;
  final String mode;
  final bool engaged;
  final double? apparentWindAngle;
  final double? apparentWindDirection;
  final double? trueWindDirection;
  final double? crossTrackError;
  final bool headingTrue;
  final bool showWindIndicators;
  final Color primaryColor;
  final bool isSailingVessel;
  final double targetAWA;
  final double targetTolerance;
  final LatLon? nextWaypoint;
  final DateTime? eta;
  final double? distanceToWaypoint;
  final Duration? timeToWaypoint;
  final bool onlyShowXTEWhenNear;
  final VoidCallback? onEngageDisengage;
  final Function(String mode)? onModeChange;
  final Function(int degrees)? onAdjustHeading;
  final Function(String direction)? onTack;
  final Function(String direction)? onGybe;
  final VoidCallback? onAdvanceWaypoint;
  final VoidCallback? onDodgeToggle;
  final bool isV2Api;
  final bool dodgeActive;
  final int fadeDelaySeconds;

  const AutopilotWidgetV2({
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
  State<AutopilotWidgetV2> createState() => _AutopilotWidgetV2State();
}

class _AutopilotWidgetV2State extends State<AutopilotWidgetV2> {
  Timer? _dimTimer;
  double _controlsOpacity = 0.85;

  // Target arrow dragging state
  bool _isDraggingTarget = false;
  double? _dragTargetHeading;
  final List<int> _commandQueue = [];
  bool _isProcessingCommands = false;
  double? _lastAcknowledgedHeading;

  @override
  void didUpdateWidget(AutopilotWidgetV2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Check if target heading changed (command acknowledged)
    if (_isProcessingCommands && _lastAcknowledgedHeading != null) {
      final headingDiff = (widget.targetHeading - _lastAcknowledgedHeading!).abs();
      if (headingDiff < 0.5 || headingDiff > 359.5) {
        // Command was acknowledged, process next in queue
        _processNextCommand();
      }
    }
  }

  @override
  void dispose() {
    _dimTimer?.cancel();
    _commandQueue.clear();
    super.dispose();
  }

  void _onHeadingAdjustmentSent() {
    _dimTimer?.cancel();
    setState(() {
      _controlsOpacity = 0.85;
    });
    _dimTimer = Timer(Duration(seconds: widget.fadeDelaySeconds), () {
      setState(() {
        _controlsOpacity = 0.3;
      });
    });
  }

  void _onScreenTap() {
    _dimTimer?.cancel();
    setState(() {
      _controlsOpacity = 0.85;
    });
  }

  void _onCompassDoubleTap() {
    if (widget.engaged) {
      widget.onEngageDisengage?.call();
      _onHeadingAdjustmentSent();
    }
  }

  // Target arrow dragging methods
  void _onTargetDragStart(Offset localPosition, Size size) {
    if (!widget.engaged) return;

    setState(() {
      _isDraggingTarget = true;
      _dragTargetHeading = widget.targetHeading;
      _controlsOpacity = 0.85;
    });
    _dimTimer?.cancel();
  }

  void _onTargetDragUpdate(Offset localPosition, Size size) {
    if (!_isDraggingTarget) return;

    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;

    // Calculate angle from center (0 = top, clockwise positive)
    var angle = math.atan2(dx, -dy) * 180 / math.pi;
    if (angle < 0) angle += 360;

    setState(() {
      _dragTargetHeading = angle;
    });
  }

  void _onTargetDragEnd() {
    if (!_isDraggingTarget || _dragTargetHeading == null) {
      setState(() {
        _isDraggingTarget = false;
        _dragTargetHeading = null;
      });
      return;
    }

    // Calculate the delta needed
    double delta = _dragTargetHeading! - widget.targetHeading;

    // Normalize to -180 to 180
    while (delta > 180) { delta -= 360; }
    while (delta < -180) { delta += 360; }

    // Build command queue with 10° and 1° increments
    _buildCommandQueue(delta);

    setState(() {
      _isDraggingTarget = false;
      _dragTargetHeading = null;
    });

    // Start processing commands
    _startProcessingCommands();
  }

  void _buildCommandQueue(double totalDelta) {
    _commandQueue.clear();

    int remaining = totalDelta.round();
    final direction = remaining >= 0 ? 1 : -1;
    remaining = remaining.abs();

    // Add 10° increments
    while (remaining >= 10) {
      _commandQueue.add(10 * direction);
      remaining -= 10;
    }

    // Add 1° increments for remainder
    while (remaining >= 1) {
      _commandQueue.add(1 * direction);
      remaining -= 1;
    }
  }

  void _startProcessingCommands() {
    if (_commandQueue.isEmpty) return;

    setState(() {
      _isProcessingCommands = true;
    });

    _processNextCommand();
  }

  void _processNextCommand() {
    if (_commandQueue.isEmpty) {
      setState(() {
        _isProcessingCommands = false;
        _lastAcknowledgedHeading = null;
      });
      _onHeadingAdjustmentSent();
      return;
    }

    final command = _commandQueue.removeAt(0);

    // Calculate expected heading after this command
    _lastAcknowledgedHeading = (widget.targetHeading + command) % 360;

    // Send the command
    widget.onAdjustHeading?.call(command);

    // Set a timeout in case acknowledgment doesn't come
    Future.delayed(const Duration(seconds: 3), () {
      if (_isProcessingCommands && _commandQueue.isNotEmpty) {
        // Timeout - try next command anyway
        _processNextCommand();
      }
    });
  }

  void _cancelCommandQueue() {
    setState(() {
      _commandQueue.clear();
      _isProcessingCommands = false;
      _lastAcknowledgedHeading = null;
    });
  }

  List<GaugeRange> _buildAutopilotZones(double primaryHeadingDegrees) {
    final builder = CompassZoneBuilder();

    if (widget.showWindIndicators && widget.apparentWindAngle != null) {
      final windDirection = AngleUtils.normalize(widget.currentHeading + widget.apparentWindAngle!);
      builder.addSailingZones(
        windDirection: windDirection,
        targetAWA: widget.targetAWA,
        targetTolerance: widget.targetTolerance,
      );
    } else {
      builder.addHeadingZones(currentHeading: widget.currentHeading);
    }

    return builder.zones;
  }

  List<GaugePointer> _buildAutopilotPointers(double primaryHeadingDegrees) {
    final pointers = <GaugePointer>[];

    // Target heading marker on rim (triangle pointing outward)
    // Show drag position when dragging, otherwise actual target
    final displayTargetHeading = _isDraggingTarget && _dragTargetHeading != null
        ? _dragTargetHeading!
        : widget.targetHeading;

    pointers.add(MarkerPointer(
      value: displayTargetHeading,
      markerType: MarkerType.triangle,
      markerHeight: _isDraggingTarget ? 24 : 20,
      markerWidth: _isDraggingTarget ? 20 : 16,
      color: _isDraggingTarget
          ? const Color(0xFFFFD600) // Bright yellow when dragging
          : widget.primaryColor,
      markerOffset: -2,
    ));

    // Show "ghost" marker at original position when dragging
    if (_isDraggingTarget) {
      pointers.add(MarkerPointer(
        value: widget.targetHeading,
        markerType: MarkerType.triangle,
        markerHeight: 16,
        markerWidth: 12,
        color: widget.primaryColor.withValues(alpha: 0.4),
        markerOffset: -2,
      ));
    }

    // Current heading marker
    pointers.add(MarkerPointer(
      value: widget.currentHeading,
      markerType: MarkerType.circle,
      markerHeight: 11,
      markerWidth: 11,
      color: Colors.yellow,
      markerOffset: -5,
    ));

    // Wind indicators
    if (widget.showWindIndicators) {
      if (widget.apparentWindDirection != null) {
        pointers.add(NeedlePointer(
          value: widget.apparentWindDirection!,
          needleLength: 0.95,
          needleStartWidth: 5,
          needleEndWidth: 0,
          needleColor: Colors.blue,
          knobStyle: const KnobStyle(knobRadius: 0.03, color: Colors.blue),
        ));
      }

      if (widget.trueWindDirection != null) {
        pointers.add(NeedlePointer(
          value: widget.trueWindDirection!,
          needleLength: 0.75,
          needleStartWidth: 4,
          needleEndWidth: 0,
          needleColor: Colors.green,
          knobStyle: const KnobStyle(knobRadius: 0.025, color: Colors.green),
        ));
      }
    }

    return pointers;
  }

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

  Widget _buildEmptyHeadingDisplay(double headingDegrees, bool isActive) {
    return const SizedBox.shrink();
  }

  /// Build the center display with controls nested inside
  Widget _buildCenterDisplay(double primaryHeadingDegrees, String headingMode) {
    // Calculate heading error
    double error = widget.currentHeading - widget.targetHeading;
    while (error > 180) { error -= 360; }
    while (error < -180) { error += 360; }

    Color errorColor;
    if (error.abs() < 3) {
      errorColor = Colors.green;
    } else if (error.abs() < 10) {
      errorColor = Colors.yellow;
    } else {
      errorColor = Colors.red;
    }

    return Positioned.fill(
      child: AnimatedOpacity(
        opacity: _controlsOpacity,
        duration: const Duration(milliseconds: 300),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = math.min(constraints.maxWidth, constraints.maxHeight);
            final centerRadius = size * 0.32; // Inner circle radius for controls
            final outerRadius = size * 0.48; // Radius for banana buttons (just inside rim)

            return Stack(
              alignment: Alignment.center,
              children: [
                // Inner circle background for controls
                Container(
                  width: centerRadius * 2,
                  height: centerRadius * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.75),
                    border: Border.all(
                      color: widget.engaged
                          ? const Color(0xFF00E676) // Vibrant green when engaged
                          : Colors.grey.withValues(alpha: 0.5),
                      width: widget.engaged ? 4 : 2,
                    ),
                    boxShadow: widget.engaged ? [
                      BoxShadow(
                        color: const Color(0xFF00E676).withValues(alpha: 0.4),
                        blurRadius: 25,
                        spreadRadius: 8,
                      ),
                    ] : null,
                  ),
                ),

                // Arced heading adjustment buttons (show in Auto/Compass/Standby modes, hidden in Wind/Route)
                if (widget.mode != 'Wind' && widget.mode.toLowerCase() != 'route' && widget.mode.toLowerCase() != 'nav')
                  ..._buildBananaButtons(size, outerRadius, enabled: widget.engaged),

                // Tack/Gybe banana buttons (show in Wind mode only)
                if (widget.mode == 'Wind' && widget.isSailingVessel)
                  ..._buildTackGybeBananas(size, enabled: widget.engaged),

                // Advance waypoint banana button (show in Route/Nav mode)
                if ((widget.mode.toLowerCase() == 'route' || widget.mode.toLowerCase() == 'nav') && !widget.dodgeActive)
                  _buildAdvanceWaypointBanana(size, enabled: widget.engaged),

                // Center content
                SizedBox(
                  width: centerRadius * 1.8,
                  height: centerRadius * 1.8,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Mode indicator (tappable)
                      GestureDetector(
                        onTap: () {
                          _onScreenTap();
                          _showModeMenu(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.mode.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: widget.engaged ? Colors.white : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.arrow_drop_down,
                                size: 20,
                                color: widget.engaged ? Colors.white : Colors.white70,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 4),

                      // Target heading display
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            widget.targetHeading.toStringAsFixed(0),
                            style: TextStyle(
                              fontSize: 42,
                              color: widget.primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '°',
                            style: TextStyle(
                              fontSize: 24,
                              color: widget.primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      // Error indicator
                      Text(
                        '${error > 0 ? '+' : ''}${error.toStringAsFixed(1)}°',
                        style: TextStyle(
                          fontSize: 14,
                          color: errorColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Engage/Disengage button
                      SizedBox(
                        width: 100,
                        height: 36,
                        child: ElevatedButton(
                          onPressed: () {
                            widget.onEngageDisengage?.call();
                            _onHeadingAdjustmentSent();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.engaged
                                ? const Color(0xFFFF1744).withValues(alpha: 0.9) // Vibrant red
                                : const Color(0xFF00E676).withValues(alpha: 0.9), // Vibrant green
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: Text(
                            widget.engaged ? 'STOP' : 'ENGAGE',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      // Dodge button (Route/Nav mode, V2 API only)
                      if (widget.isV2Api &&
                          widget.engaged &&
                          (widget.mode.toLowerCase() == 'route' || widget.mode.toLowerCase() == 'nav')) ...[
                        const SizedBox(height: 6),
                        SizedBox(
                          width: 80,
                          height: 28,
                          child: ElevatedButton(
                            onPressed: () {
                              widget.onDodgeToggle?.call();
                              _onHeadingAdjustmentSent();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.dodgeActive
                                  ? const Color(0xFFFF9100).withValues(alpha: 0.9) // Vibrant orange
                                  : const Color(0xFF00B0FF).withValues(alpha: 0.7), // Vibrant blue
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              widget.dodgeActive ? 'EXIT' : 'DODGE',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Build banana-shaped heading adjustment buttons along the rim
  List<Widget> _buildBananaButtons(double size, double outerRadius, {required bool enabled}) {
    // Button configurations: degrees, startAngle, sweepAngle, isLeft (port side)
    // Angles are in standard math coordinates: 0=right, -90=top, 90=bottom, 180=left
    // Buttons positioned symmetrically around heading centerline (top = -90 degrees)
    final buttons = [
      (-10, -155.0, 30.0, true),   // Far left - port -10
      (-1, -120.0, 22.0, true),    // Near left - port -1
      (1, -82.0, 22.0, false),     // Near right - starboard +1
      (10, -55.0, 30.0, false),    // Far right - starboard +10
    ];

    return buttons.map((config) {
      final degrees = config.$1;
      final startAngle = config.$2;
      final sweepAngle = config.$3;
      final isPort = config.$4;

      final buttonColor = isPort
          ? const Color(0xFFFF1744).withValues(alpha: enabled ? 0.85 : 0.25) // Vibrant red
          : const Color(0xFF00E676).withValues(alpha: enabled ? 0.85 : 0.25); // Vibrant green

      return Positioned.fill(
        child: GestureDetector(
          onTap: enabled ? () {
            widget.onAdjustHeading?.call(degrees);
            _onHeadingAdjustmentSent();
          } : null,
          child: CustomPaint(
            painter: _BananaButtonPainter(
              startAngle: startAngle,
              sweepAngle: sweepAngle,
              color: buttonColor,
              enabled: enabled,
              isPort: isPort,
              isLarge: degrees.abs() == 10,
            ),
          ),
        ),
      );
    }).toList();
  }

  /// Build tack/gybe banana buttons for Wind mode
  /// Positioned based on turn direction:
  /// - Port (left) side: buttons that turn you LEFT (Tack Port, Gybe Starboard)
  /// - Starboard (right) side: buttons that turn you RIGHT (Tack Starboard, Gybe Port)
  List<Widget> _buildTackGybeBananas(double size, {required bool enabled}) {
    final buttons = <Widget>[];

    // PORT SIDE (left) - buttons that turn the boat LEFT
    // Tack to Port (turn left through the wind)
    buttons.add(_buildTackGybeBanana(
      size: size,
      startAngle: 155.0, // Left side, upper
      sweepAngle: 35.0,
      isPort: true,
      isTack: true,
      label: 'TACK\nPORT',
      enabled: enabled,
      onPressed: () {
        widget.onTack?.call('port');
        _onHeadingAdjustmentSent();
      },
    ));

    // Gybe to Starboard (turn left, wind ends on starboard) - V2 API only
    if (widget.isV2Api) {
      buttons.add(_buildTackGybeBanana(
        size: size,
        startAngle: 195.0, // Left side, lower
        sweepAngle: 35.0,
        isPort: true,
        isTack: false,
        label: 'GYBE\nSTBD',
        enabled: enabled,
        onPressed: () {
          widget.onGybe?.call('starboard');
          _onHeadingAdjustmentSent();
        },
      ));
    }

    // STARBOARD SIDE (right) - buttons that turn the boat RIGHT
    // Tack to Starboard (turn right through the wind)
    buttons.add(_buildTackGybeBanana(
      size: size,
      startAngle: -30.0, // Right side, upper
      sweepAngle: 35.0,
      isPort: false,
      isTack: true,
      label: 'TACK\nSTBD',
      enabled: enabled,
      onPressed: () {
        widget.onTack?.call('starboard');
        _onHeadingAdjustmentSent();
      },
    ));

    // Gybe to Port (turn right, wind ends on port) - V2 API only
    if (widget.isV2Api) {
      buttons.add(_buildTackGybeBanana(
        size: size,
        startAngle: 10.0, // Right side, lower
        sweepAngle: 35.0,
        isPort: false,
        isTack: false,
        label: 'GYBE\nPORT',
        enabled: enabled,
        onPressed: () {
          widget.onGybe?.call('port');
          _onHeadingAdjustmentSent();
        },
      ));
    }

    return buttons;
  }

  Widget _buildTackGybeBanana({
    required double size,
    required double startAngle,
    required double sweepAngle,
    required bool isPort,
    required bool isTack,
    required String label,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    // Tack = orange/yellow, Gybe = purple
    final buttonColor = isTack
        ? const Color(0xFFFFAB00).withValues(alpha: enabled ? 0.85 : 0.25) // Vibrant amber for tack
        : const Color(0xFFE040FB).withValues(alpha: enabled ? 0.85 : 0.25); // Vibrant purple for gybe

    return Positioned.fill(
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: CustomPaint(
          painter: _TackGybeBananaPainter(
            startAngle: startAngle,
            sweepAngle: sweepAngle,
            color: buttonColor,
            enabled: enabled,
            isPort: isPort,
            label: label,
          ),
        ),
      ),
    );
  }

  /// Build advance waypoint banana button at the top (heading direction)
  Widget _buildAdvanceWaypointBanana(double size, {required bool enabled}) {
    final buttonColor = const Color(0xFF00B0FF).withValues(alpha: enabled ? 0.85 : 0.25); // Vibrant blue

    return Positioned.fill(
      child: GestureDetector(
        onTap: enabled ? () {
          widget.onAdvanceWaypoint?.call();
          _onHeadingAdjustmentSent();
        } : null,
        child: CustomPaint(
          painter: _AdvanceWaypointBananaPainter(
            color: buttonColor,
            enabled: enabled,
          ),
        ),
      ),
    );
  }

  Widget _buildAutopilotOverlay(double primaryHeadingDegrees) {
    return Stack(
      children: [
        // XTE display
        if (widget.crossTrackError != null && widget.crossTrackError!.abs() < 18520)
          Positioned(
            right: 16,
            bottom: 100,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha:0.8),
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

  Widget _buildHeadingLabel(double headingDegrees, bool isTrue) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha:0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'HDG',
                style: TextStyle(fontSize: 10, color: Colors.white60),
              ),
              const SizedBox(width: 4),
              Container(
                width: 10,
                height: 10,
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
              fontSize: 14,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRudderIndicator() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const Text(
            'RUDDER',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('P', style: TextStyle(fontSize: 9, color: Colors.red)),
              const SizedBox(width: 4),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final normalizedPosition = (widget.rudderAngle + 35) / 70;
                    final leftPosition = (constraints.maxWidth * normalizedPosition) - 4;

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          height: 16,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha:0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        Container(
                          width: 2,
                          height: 24,
                          color: Colors.white.withValues(alpha:0.5),
                        ),
                        Positioned(
                          left: leftPosition.clamp(0.0, constraints.maxWidth - 8),
                          child: Container(
                            width: 8,
                            height: 24,
                            decoration: BoxDecoration(
                              color: widget.rudderAngle < 0 ? Colors.red : Colors.green,
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha:0.3),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Text(
                          '${widget.rudderAngle.toStringAsFixed(0)}°',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 4),
              const Text('S', style: TextStyle(fontSize: 9, color: Colors.green)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final headingRadians = widget.currentHeading * math.pi / 180;

    return GestureDetector(
      onDoubleTap: _onCompassDoubleTap,
      behavior: HitTestBehavior.translucent,
      child: GestureDetector(
        onTap: _onScreenTap,
        behavior: HitTestBehavior.translucent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape = constraints.maxWidth > constraints.maxHeight;
            final compassSize = isLandscape
                ? constraints.maxHeight * 0.95
                : math.min(constraints.maxWidth, constraints.maxHeight) * 0.90;

            return Stack(
              children: [
                // Compass with center controls
                Center(
                  child: SizedBox(
                    width: compassSize,
                    height: compassSize,
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
                    centerDisplayBuilder: _buildCenterDisplay,
                    allowHeadingModeToggle: false,
                    showCenterCircle: false,
                  ),
                ),
              ),

              // Target arrow drag overlay (long press to drag)
              if (widget.engaged && (widget.mode == 'Auto' || widget.mode == 'Compass'))
                Center(
                  child: SizedBox(
                    width: compassSize,
                    height: compassSize,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onLongPressStart: (details) {
                        _onTargetDragStart(details.localPosition, Size(compassSize, compassSize));
                      },
                      onLongPressMoveUpdate: (details) {
                        _onTargetDragUpdate(details.localPosition, Size(compassSize, compassSize));
                      },
                      onLongPressEnd: (details) {
                        _onTargetDragEnd();
                      },
                      onLongPressCancel: () {
                        _onTargetDragEnd();
                      },
                      child: _isDraggingTarget
                          ? CustomPaint(
                              size: Size(compassSize, compassSize),
                              painter: _DragIndicatorPainter(
                                targetHeading: widget.targetHeading,
                                dragHeading: _dragTargetHeading ?? widget.targetHeading,
                                primaryColor: widget.primaryColor,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),

              // Command queue progress indicator
              if (_isProcessingCommands)
                Positioned(
                  top: 50,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF00B0FF),
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF00B0FF),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Moving... ${_commandQueue.length} left',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _cancelCommandQueue,
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Heading label - top right corner
              Positioned(
                right: 12,
                top: 12,
                child: AnimatedOpacity(
                  opacity: _controlsOpacity,
                  duration: const Duration(milliseconds: 300),
                  child: _buildHeadingLabel(widget.currentHeading, widget.headingTrue),
                ),
              ),

              // Route info panel (route/nav mode)
              if ((widget.mode.toLowerCase() == 'route' || widget.mode.toLowerCase() == 'nav') &&
                  widget.nextWaypoint != null &&
                  !widget.dodgeActive)
                Positioned(
                  bottom: 70,
                  left: 16,
                  right: 16,
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

              // Dodge mode indicator
              if (widget.dodgeActive)
                Positioned(
                  top: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha:0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning, color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'DODGE MODE',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Bottom controls area (rudder indicator - show if there's room)
              if (constraints.maxHeight > compassSize + 60)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedOpacity(
                    opacity: _controlsOpacity,
                    duration: const Duration(milliseconds: 300),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 4),
                        _buildRudderIndicator(),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
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
      ..color = Colors.grey.withValues(alpha:0.5)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_NoGoZoneVPainter oldDelegate) {
    return oldDelegate.windDirection != windDirection ||
           oldDelegate.noGoAngle != noGoAngle;
  }
}

/// Custom painter for banana-shaped buttons with arrows
class _BananaButtonPainter extends CustomPainter {
  final double startAngle;
  final double sweepAngle;
  final Color color;
  final bool enabled;
  final bool isPort;
  final bool isLarge;

  _BananaButtonPainter({
    required this.startAngle,
    required this.sweepAngle,
    required this.color,
    required this.enabled,
    required this.isPort,
    required this.isLarge,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Position inside the compass rim (rim is at ~0.85-0.95)
    final outerRadius = math.min(size.width, size.height) / 2 * 0.82;
    final innerRadius = outerRadius * 0.75;
    final midRadius = (outerRadius + innerRadius) / 2;

    final startRad = startAngle * math.pi / 180;
    final sweepRad = sweepAngle * math.pi / 180;

    // Draw banana shape (arc segment)
    final path = Path();

    // Outer arc
    path.addArc(
      Rect.fromCircle(center: center, radius: outerRadius),
      startRad,
      sweepRad,
    );

    // Line to inner arc end
    final innerEndAngle = startRad + sweepRad;
    path.lineTo(
      center.dx + innerRadius * math.cos(innerEndAngle),
      center.dy + innerRadius * math.sin(innerEndAngle),
    );

    // Inner arc (reverse direction)
    path.arcTo(
      Rect.fromCircle(center: center, radius: innerRadius),
      innerEndAngle,
      -sweepRad,
      false,
    );

    path.close();

    // Fill paint
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, fillPaint);

    // Border paint
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: enabled ? 0.6 : 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = enabled ? 2.5 : 1.5;

    canvas.drawPath(path, borderPaint);

    // Center angle of the banana
    final midAngle = startRad + sweepRad / 2;

    // Draw curved arrow following the arc
    final arrowPaint = Paint()
      ..color = Colors.white.withValues(alpha: enabled ? 0.9 : 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // Arrow arc parameters
    final arrowArcRadius = midRadius;
    final arrowArcLength = 0.25; // radians

    // Port turns left (counter-clockwise), Starboard turns right (clockwise)
    final arrowDirection = isPort ? -1.0 : 1.0;
    final arrowStartAngle = midAngle - (arrowArcLength / 2) * arrowDirection;
    final arrowEndAngle = midAngle + (arrowArcLength / 2) * arrowDirection;

    // Draw the curved arrow shaft
    final arrowShaftPath = Path();
    arrowShaftPath.addArc(
      Rect.fromCircle(center: center, radius: arrowArcRadius),
      arrowStartAngle,
      arrowArcLength * arrowDirection,
    );
    canvas.drawPath(arrowShaftPath, arrowPaint);

    // Draw arrowhead at the end
    final arrowHeadPaint = Paint()
      ..color = Colors.white.withValues(alpha: enabled ? 0.9 : 0.35)
      ..style = PaintingStyle.fill;

    final tipAngle = arrowEndAngle;
    final tipX = center.dx + arrowArcRadius * math.cos(tipAngle);
    final tipY = center.dy + arrowArcRadius * math.sin(tipAngle);

    // Arrowhead points in direction of rotation
    final headSize = 8.0;
    // Tangent direction at the tip (perpendicular to radius)
    final tangentAngle = tipAngle + (isPort ? -math.pi / 2 : math.pi / 2);

    final arrowHeadPath = Path();
    arrowHeadPath.moveTo(
      tipX + headSize * math.cos(tangentAngle),
      tipY + headSize * math.sin(tangentAngle),
    );
    arrowHeadPath.lineTo(
      tipX + headSize * 0.6 * math.cos(tangentAngle + 2.3),
      tipY + headSize * 0.6 * math.sin(tangentAngle + 2.3),
    );
    arrowHeadPath.lineTo(
      tipX + headSize * 0.6 * math.cos(tangentAngle - 2.3),
      tipY + headSize * 0.6 * math.sin(tangentAngle - 2.3),
    );
    arrowHeadPath.close();
    canvas.drawPath(arrowHeadPath, arrowHeadPaint);

    // Draw the numeral (1 or 10) centered in the banana
    final textPainter = TextPainter(
      text: TextSpan(
        text: isLarge ? '10' : '1',
        style: TextStyle(
          color: Colors.white.withValues(alpha: enabled ? 1.0 : 0.4),
          fontSize: isLarge ? 16 : 18,
          fontWeight: FontWeight.bold,
          shadows: enabled ? [
            Shadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 2,
              offset: const Offset(1, 1),
            ),
          ] : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // Position text centered in the banana
    final textCenter = Offset(
      center.dx + midRadius * math.cos(midAngle) - textPainter.width / 2,
      center.dy + midRadius * math.sin(midAngle) - textPainter.height / 2,
    );

    textPainter.paint(canvas, textCenter);
  }

  @override
  bool shouldRepaint(_BananaButtonPainter oldDelegate) {
    return oldDelegate.startAngle != startAngle ||
           oldDelegate.sweepAngle != sweepAngle ||
           oldDelegate.color != color ||
           oldDelegate.enabled != enabled;
  }
}

/// Custom painter for tack/gybe banana buttons
class _TackGybeBananaPainter extends CustomPainter {
  final double startAngle;
  final double sweepAngle;
  final Color color;
  final bool enabled;
  final bool isPort;
  final String label;

  _TackGybeBananaPainter({
    required this.startAngle,
    required this.sweepAngle,
    required this.color,
    required this.enabled,
    required this.isPort,
    required this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Position inside the compass rim
    final outerRadius = math.min(size.width, size.height) / 2 * 0.82;
    final innerRadius = outerRadius * 0.72;
    final midRadius = (outerRadius + innerRadius) / 2;

    final startRad = startAngle * math.pi / 180;
    final sweepRad = sweepAngle * math.pi / 180;

    // Draw banana shape
    final path = Path();

    path.addArc(
      Rect.fromCircle(center: center, radius: outerRadius),
      startRad,
      sweepRad,
    );

    final innerEndAngle = startRad + sweepRad;
    path.lineTo(
      center.dx + innerRadius * math.cos(innerEndAngle),
      center.dy + innerRadius * math.sin(innerEndAngle),
    );

    path.arcTo(
      Rect.fromCircle(center: center, radius: innerRadius),
      innerEndAngle,
      -sweepRad,
      false,
    );

    path.close();

    // Fill paint
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, fillPaint);

    // Border paint
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: enabled ? 0.6 : 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = enabled ? 2.5 : 1.5;

    canvas.drawPath(path, borderPaint);

    // Center angle of the banana
    final midAngle = startRad + sweepRad / 2;

    // Draw label text (e.g., "TACK\nPORT" or "GYBE\nSTBD")
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: enabled ? 1.0 : 0.4),
          fontSize: 10,
          fontWeight: FontWeight.bold,
          height: 1.1,
          shadows: enabled ? [
            Shadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 2,
              offset: const Offset(1, 1),
            ),
          ] : null,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.layout();

    // Position text centered in the banana
    final textCenter = Offset(
      center.dx + midRadius * math.cos(midAngle) - textPainter.width / 2,
      center.dy + midRadius * math.sin(midAngle) - textPainter.height / 2,
    );

    textPainter.paint(canvas, textCenter);
  }

  @override
  bool shouldRepaint(_TackGybeBananaPainter oldDelegate) {
    return oldDelegate.startAngle != startAngle ||
           oldDelegate.sweepAngle != sweepAngle ||
           oldDelegate.color != color ||
           oldDelegate.enabled != enabled ||
           oldDelegate.label != label;
  }
}

/// Custom painter for advance waypoint banana button at the top
class _AdvanceWaypointBananaPainter extends CustomPainter {
  final Color color;
  final bool enabled;

  _AdvanceWaypointBananaPainter({
    required this.color,
    required this.enabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Position inside the compass rim, at the top
    final outerRadius = math.min(size.width, size.height) / 2 * 0.82;
    final innerRadius = outerRadius * 0.72;
    final midRadius = (outerRadius + innerRadius) / 2;

    // Position at top center (-90 degrees), spanning about 50 degrees
    const startAngle = -115.0; // degrees
    const sweepAngle = 50.0;   // degrees

    final startRad = startAngle * math.pi / 180;
    final sweepRad = sweepAngle * math.pi / 180;

    // Draw banana shape
    final path = Path();

    path.addArc(
      Rect.fromCircle(center: center, radius: outerRadius),
      startRad,
      sweepRad,
    );

    final innerEndAngle = startRad + sweepRad;
    path.lineTo(
      center.dx + innerRadius * math.cos(innerEndAngle),
      center.dy + innerRadius * math.sin(innerEndAngle),
    );

    path.arcTo(
      Rect.fromCircle(center: center, radius: innerRadius),
      innerEndAngle,
      -sweepRad,
      false,
    );

    path.close();

    // Fill paint
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, fillPaint);

    // Border paint
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: enabled ? 0.6 : 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = enabled ? 2.5 : 1.5;

    canvas.drawPath(path, borderPaint);

    // Center angle of the banana
    final midAngle = startRad + sweepRad / 2;

    // Draw forward arrow icon
    final arrowPaint = Paint()
      ..color = Colors.white.withValues(alpha: enabled ? 0.9 : 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final arrowCenter = Offset(
      center.dx + midRadius * math.cos(midAngle),
      center.dy + midRadius * math.sin(midAngle),
    );

    // Draw >> arrows pointing forward (up)
    final arrowSize = 8.0;

    // First arrow
    final arrow1Path = Path();
    arrow1Path.moveTo(arrowCenter.dx - arrowSize * 0.5, arrowCenter.dy + arrowSize * 0.3);
    arrow1Path.lineTo(arrowCenter.dx, arrowCenter.dy - arrowSize * 0.3);
    arrow1Path.lineTo(arrowCenter.dx + arrowSize * 0.5, arrowCenter.dy + arrowSize * 0.3);
    canvas.drawPath(arrow1Path, arrowPaint);

    // Second arrow (below first)
    final arrow2Path = Path();
    arrow2Path.moveTo(arrowCenter.dx - arrowSize * 0.5, arrowCenter.dy + arrowSize * 0.8);
    arrow2Path.lineTo(arrowCenter.dx, arrowCenter.dy + arrowSize * 0.2);
    arrow2Path.lineTo(arrowCenter.dx + arrowSize * 0.5, arrowCenter.dy + arrowSize * 0.8);
    canvas.drawPath(arrow2Path, arrowPaint);

    // Draw "WPT" text below arrows
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'WPT',
        style: TextStyle(
          color: Colors.white.withValues(alpha: enabled ? 1.0 : 0.4),
          fontSize: 9,
          fontWeight: FontWeight.bold,
          shadows: enabled ? [
            Shadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 2,
              offset: const Offset(1, 1),
            ),
          ] : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final textCenter = Offset(
      arrowCenter.dx - textPainter.width / 2,
      arrowCenter.dy + arrowSize * 1.0,
    );

    textPainter.paint(canvas, textCenter);
  }

  @override
  bool shouldRepaint(_AdvanceWaypointBananaPainter oldDelegate) {
    return oldDelegate.color != color ||
           oldDelegate.enabled != enabled;
  }
}

/// Custom painter for drag indicator showing the arc between original and drag position
class _DragIndicatorPainter extends CustomPainter {
  final double targetHeading;
  final double dragHeading;
  final Color primaryColor;

  _DragIndicatorPainter({
    required this.targetHeading,
    required this.dragHeading,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 * 0.85;

    // Calculate the arc between target and drag position
    double startAngle = (targetHeading - 90) * math.pi / 180; // Convert to radians, adjust for canvas coords
    double endAngle = (dragHeading - 90) * math.pi / 180;

    // Calculate sweep angle (shortest path)
    double sweep = endAngle - startAngle;
    while (sweep > math.pi) { sweep -= 2 * math.pi; }
    while (sweep < -math.pi) { sweep += 2 * math.pi; }

    // Draw the arc showing the change
    final arcPaint = Paint()
      ..color = const Color(0xFFFFD600).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweep,
      false,
      arcPaint,
    );

    // Draw degrees indicator
    double delta = dragHeading - targetHeading;
    while (delta > 180) { delta -= 360; }
    while (delta < -180) { delta += 360; }

    final textPainter = TextPainter(
      text: TextSpan(
        text: '${delta >= 0 ? '+' : ''}${delta.round()}°',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.8),
              blurRadius: 4,
              offset: const Offset(2, 2),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // Position at the drag location
    final midAngle = (dragHeading - 90) * math.pi / 180;
    final textRadius = radius * 0.6;
    final textCenter = Offset(
      center.dx + textRadius * math.cos(midAngle) - textPainter.width / 2,
      center.dy + textRadius * math.sin(midAngle) - textPainter.height / 2,
    );

    textPainter.paint(canvas, textCenter);
  }

  @override
  bool shouldRepaint(_DragIndicatorPainter oldDelegate) {
    return oldDelegate.targetHeading != targetHeading ||
           oldDelegate.dragHeading != dragHeading;
  }
}
