import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';
import '../../models/tool_config.dart';
import '../../models/tool_definition.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/angle_utils.dart';
import '../../utils/cpa_utils.dart';
import '../tool_info_button.dart';

/// Find Home Tool - ILS-style approach display for navigating back to an
/// anchored vessel at night.
///
/// Data sources:
///   - Dinghy position / COG / SOG: device GPS via geolocator
///   - Home target: configurable SignalK path, default navigation.anchor.position
///
/// Haptic feedback: 1 buzz = turn port, 2 buzzes = turn starboard.
class FindHomeTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const FindHomeTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<FindHomeTool> createState() => _FindHomeToolState();
}

class _FindHomeToolState extends State<FindHomeTool> {
  static const _ownerId = 'find_home';
  static const _defaultTargetPath = 'navigation.position';

  /// Full deflection angle in degrees
  static const _maxDeviation = 30.0;

  /// Minimum SOG (m/s) to compute ETA and deviation
  static const _sogThreshold = 0.5;

  /// Deviation threshold for haptic feedback (degrees)
  static const _hapticDeviationThreshold = 5.0;

  /// Feedback interval from config (5-60 seconds, default 10)
  int get _feedbackIntervalSec {
    final val = widget.config.style.customProperties?['feedbackInterval'] as int?;
    return (val ?? 10).clamp(5, 60);
  }

  bool _active = false;
  bool _whistleEnabled = false;
  Timer? _hapticTimer;
  AudioPlayer? _whistlePlayer;

  // Device GPS state
  StreamSubscription<Position>? _positionSub;
  Position? _devicePosition;
  String? _gpsError;

  /// SignalK path for the home target (boat position)
  String get _targetPath {
    if (widget.config.dataSources.isNotEmpty &&
        widget.config.dataSources[0].path.isNotEmpty) {
      return widget.config.dataSources[0].path;
    }
    return _defaultTargetPath;
  }

  @override
  void initState() {
    super.initState();
    // Subscribe to the target position from SignalK
    widget.signalKService
        .subscribeToPaths([_targetPath], ownerId: _ownerId);
    widget.signalKService.addListener(_onSignalKUpdate);
    _initDeviceGps();
  }

  @override
  void dispose() {
    _hapticTimer?.cancel();
    _positionSub?.cancel();
    _whistlePlayer?.dispose();
    widget.signalKService.removeListener(_onSignalKUpdate);
    widget.signalKService
        .unsubscribeFromPaths([_targetPath], ownerId: _ownerId);
    super.dispose();
  }

  void _onSignalKUpdate() {
    if (mounted) setState(() {});
  }

  // --------------- Device GPS ---------------

  Future<void> _initDeviceGps() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _gpsError = 'Location services disabled');
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _gpsError = 'Location permission denied');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() => _gpsError = 'Location permanently denied');
      }
      return;
    }

    final LocationSettings settings;
    if (Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        forceLocationManager: false,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );
    }

    _positionSub =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) {
        if (mounted) setState(() => _devicePosition = position);
      },
      onError: (error) {
        debugPrint('FindHome GPS error: $error');
        if (mounted) setState(() => _gpsError = 'GPS error');
      },
    );
  }

  // --------------- Data helpers ---------------

  /// Get home target position from SignalK
  (double?, double?) _getTargetPosition() {
    final data = widget.signalKService.getValue(_targetPath);
    if (data?.value is Map) {
      final m = data!.value as Map;
      final lat = m['latitude'];
      final lon = m['longitude'];
      if (lat is num && lon is num) {
        return (lat.toDouble(), lon.toDouble());
      }
    }
    return (null, null);
  }

  // --------------- Unit helpers ---------------

  ({double metersPerUnit, String symbol}) _getDistanceUnit() {
    final meta = widget.signalKService.metadataStore
        .get('navigation.anchor.currentRadius');
    if (meta != null) {
      final oneInDisplay = meta.convert(1.0);
      if (oneInDisplay != null && oneInDisplay > 0) {
        return (
          metersPerUnit: 1.0 / oneInDisplay,
          symbol: meta.symbol ?? 'm',
        );
      }
    }
    return (metersPerUnit: 1852.0, symbol: 'nm');
  }

  // --------------- Computed nav data ---------------

  ({
    double bearing,
    double deviation,
    double distance,
    double cogDeg,
    double sogMs,
  })? _computeNav() {
    final pos = _devicePosition;
    if (pos == null) return null;

    final (homeLat, homeLon) = _getTargetPosition();
    if (homeLat == null || homeLon == null) return null;

    final lat = pos.latitude;
    final lon = pos.longitude;

    final bearing = AngleUtils.bearing(lat, lon, homeLat, homeLon);
    final distance = CpaUtils.calculateDistance(lat, lon, homeLat, homeLon);

    // COG and SOG from device GPS
    final sogMs = pos.speed >= 0 ? pos.speed : 0.0;
    final cogDeg = pos.heading >= 0 ? pos.heading : bearing;

    // Only compute deviation when actually moving
    final deviation = sogMs >= _sogThreshold
        ? AngleUtils.difference(cogDeg, bearing)
        : 0.0;

    return (
      bearing: bearing,
      deviation: deviation,
      distance: distance,
      cogDeg: AngleUtils.normalize(cogDeg),
      sogMs: sogMs,
    );
  }

  // --------------- Feedback engine ---------------

  void _toggleActive() {
    setState(() {
      _active = !_active;
    });
    if (_active) {
      _startFeedback();
    } else {
      _stopFeedback();
    }
  }

  void _toggleWhistle() {
    setState(() {
      _whistleEnabled = !_whistleEnabled;
    });
  }

  void _startFeedback() {
    _hapticTimer?.cancel();
    _hapticTimer = Timer.periodic(
      Duration(seconds: _feedbackIntervalSec),
      (_) => _fireFeedback(),
    );
  }

  void _stopFeedback() {
    _hapticTimer?.cancel();
    _hapticTimer = null;
  }

  void _fireFeedback() {
    if (!_active || !mounted) return;
    final nav = _computeNav();
    if (nav == null) return;

    final absDev = nav.deviation.abs();
    if (absDev < _hapticDeviationThreshold) return;

    if (nav.deviation > 0) {
      // On starboard side of course → turn port → 1 buzz / 1 whistle
      _vibrateSingle();
      if (_whistleEnabled) _whistleSingle();
    } else {
      // On port side of course → turn starboard → 2 buzzes / 2 whistles
      _vibrateDouble();
      if (_whistleEnabled) _whistleDouble();
    }
  }

  /// Single long vibration: 500ms at max intensity
  void _vibrateSingle() {
    Vibration.vibrate(
      pattern: [0, 500],
      intensities: [0, 255],
    );
  }

  /// Double long vibration: 500ms, pause 300ms, 500ms
  void _vibrateDouble() {
    Vibration.vibrate(
      pattern: [0, 500, 300, 500],
      intensities: [0, 255, 0, 255],
    );
  }

  /// Play one whistle blast
  Future<void> _whistleSingle() async {
    try {
      _whistlePlayer?.dispose();
      _whistlePlayer = AudioPlayer();
      await _whistlePlayer!.play(AssetSource('sounds/alarm_whistle.mp3'));
    } catch (e) {
      debugPrint('FindHome whistle error: $e');
    }
  }

  /// Play two whistle blasts
  Future<void> _whistleDouble() async {
    try {
      _whistlePlayer?.dispose();
      _whistlePlayer = AudioPlayer();
      await _whistlePlayer!.play(AssetSource('sounds/alarm_whistle.mp3'));
      // Wait for first blast to finish, then play second
      _whistlePlayer!.onPlayerComplete.first.then((_) async {
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted || !_active) return;
        _whistlePlayer?.dispose();
        _whistlePlayer = AudioPlayer();
        await _whistlePlayer!.play(AssetSource('sounds/alarm_whistle.mp3'));
      });
    } catch (e) {
      debugPrint('FindHome whistle error: $e');
    }
  }

  // --------------- Formatting ---------------

  String _formatDistance(double meters) {
    final unit = _getDistanceUnit();
    final display = meters / unit.metersPerUnit;
    return '${display.toStringAsFixed(display < 10 ? 2 : 1)} ${unit.symbol}';
  }

  String _formatAngle(double degrees) {
    return '${degrees.toStringAsFixed(0)}°';
  }

  String _formatSpeed(double sogMs) {
    final meta =
        widget.signalKService.metadataStore.get('navigation.speedOverGround');
    if (meta != null) {
      return meta.format(sogMs, decimals: 1);
    }
    final kn = sogMs * 1.9438444924;
    return '${kn.toStringAsFixed(1)} kn';
  }

  String _formatEta(double distanceM, double sogMs) {
    if (sogMs < _sogThreshold) return '--:--';
    final seconds = distanceM / sogMs;
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    if (mins >= 60) {
      final hrs = mins ~/ 60;
      final remMins = mins % 60;
      return '$hrs:${remMins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  // --------------- Build ---------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Check for target position from SignalK
    final (homeLat, _) = _getTargetPosition();
    if (homeLat == null) {
      return _buildNoTarget(isDark);
    }

    // Check for device GPS errors
    if (_gpsError != null) {
      return _buildGpsError(isDark);
    }

    // Check for device GPS fix
    final nav = _computeNav();
    if (nav == null) {
      return _buildAcquiringGps(isDark);
    }

    final unit = _getDistanceUnit();

    return Stack(
      children: [
        Column(
          children: [
            _buildHeader(nav, isDark),
            Expanded(
              child: ClipRect(
                child: CustomPaint(
                  painter: _RunwayPainter(
                    deviation: nav.deviation,
                    maxDeviation: _maxDeviation,
                    distanceMeters: nav.distance,
                    metersPerUnit: unit.metersPerUnit,
                    unitSymbol: unit.symbol,
                    isDark: isDark,
                    active: _active,
                    hapticThreshold: _hapticDeviationThreshold,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
            _buildFooter(nav, isDark),
          ],
        ),
        _buildInfoButton(),
      ],
    );
  }

  Widget _buildInfoButton() {
    return Positioned(
      top: 8,
      right: 8,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: ToolInfoButton(
          toolId: 'find_home',
          signalKService: widget.signalKService,
          iconSize: 20,
          iconColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildNoTarget(bool isDark) {
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.anchor, size: 32, color: Colors.grey),
              const SizedBox(height: 8),
              const Text(
                'No home position',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Text(
                'Drop anchor to set target',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
        _buildInfoButton(),
      ],
    );
  }

  Widget _buildGpsError(bool isDark) {
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_disabled,
                  size: 32, color: Colors.orange),
              const SizedBox(height: 8),
              Text(
                _gpsError ?? 'GPS unavailable',
                style: const TextStyle(color: Colors.orange),
              ),
              const SizedBox(height: 4),
              const Text(
                'Enable location services',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
        _buildInfoButton(),
      ],
    );
  }

  Widget _buildAcquiringGps(bool isDark) {
    return Stack(
      children: [
        const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_searching, size: 32, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                'Acquiring device GPS...',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        _buildInfoButton(),
      ],
    );
  }

  Widget _buildHeader(dynamic nav, bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final labelColor = isDark ? Colors.white60 : Colors.black54;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 40, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'FIND HOME',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: labelColor,
              letterSpacing: 1.2,
            ),
          ),
          Text(
            _formatDistance(nav.distance),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(dynamic nav, bool isDark) {
    final labelColor = isDark ? Colors.white60 : Colors.black54;
    final absDev = nav.deviation.abs() as double;
    final devSide = nav.deviation > 0 ? 'S' : 'P';

    Color devColor;
    if (absDev < 5) {
      devColor = Colors.green;
    } else if (absDev < 15) {
      devColor = Colors.amber;
    } else {
      devColor = Colors.red;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'COG ${_formatAngle(nav.cogDeg)}',
                style: TextStyle(
                    fontSize: 12, fontFamily: 'monospace', color: labelColor),
              ),
              Text(
                'BRG ${_formatAngle(nav.bearing)}',
                style: TextStyle(
                    fontSize: 12, fontFamily: 'monospace', color: labelColor),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'DEV ${absDev.toStringAsFixed(0)}° $devSide',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  color: devColor,
                ),
              ),
              Text(
                _formatSpeed(nav.sogMs),
                style: TextStyle(
                    fontSize: 12, fontFamily: 'monospace', color: labelColor),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ETA ${_formatEta(nav.distance, nav.sogMs)}',
                style: TextStyle(
                    fontSize: 12, fontFamily: 'monospace', color: labelColor),
              ),
              Row(
                children: [
                  // Whistle toggle
                  GestureDetector(
                    onTap: _toggleWhistle,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _whistleEnabled
                            ? Colors.orange.withValues(alpha: 0.3)
                            : Colors.grey.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              _whistleEnabled ? Colors.orange : Colors.grey,
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        _whistleEnabled
                            ? Icons.volume_up
                            : Icons.volume_off,
                        size: 14,
                        color:
                            _whistleEnabled ? Colors.orange : Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Vibration/active toggle
                  GestureDetector(
                    onTap: _toggleActive,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _active
                            ? Colors.green.withValues(alpha: 0.3)
                            : Colors.grey.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _active ? Colors.green : Colors.grey,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _active ? 'ACTIVE' : 'OFF',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _active ? Colors.green : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --------------- Runway CustomPainter ---------------

class _RunwayPainter extends CustomPainter {
  final double deviation;
  final double maxDeviation;
  final double distanceMeters;
  final double metersPerUnit;
  final String unitSymbol;
  final bool isDark;
  final bool active;
  final double hapticThreshold;

  _RunwayPainter({
    required this.deviation,
    required this.maxDeviation,
    required this.distanceMeters,
    required this.metersPerUnit,
    required this.unitSymbol,
    required this.isDark,
    required this.active,
    required this.hapticThreshold,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final centerX = w / 2;

    final bgColor =
        isDark ? const Color(0xFF1A1A2E) : const Color(0xFFE8EAF6);
    final centerLineColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : Colors.black.withValues(alpha: 0.4);

    final absDev = deviation.abs();
    Color devColor;
    if (absDev < 5) {
      devColor = Colors.green;
    } else if (absDev < 15) {
      devColor = Colors.amber;
    } else {
      devColor = Colors.red;
    }

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = bgColor,
    );

    // Runway geometry — apex (anchor) at top, base (vessel) at bottom
    final apexY = 20.0;
    final baseY = h - 20.0;
    final runwayHeight = baseY - apexY;
    final baseHalfWidth = (w / 2) - 20;

    // --- Localizer beam triangle (full ±30° cone) ---
    final beamPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.04)
          : Colors.black.withValues(alpha: 0.03);
    final beamPath = Path()
      ..moveTo(centerX, apexY)
      ..lineTo(centerX - baseHalfWidth, baseY)
      ..lineTo(centerX + baseHalfWidth, baseY)
      ..close();
    canvas.drawPath(beamPath, beamPaint);

    // Beam edge lines
    final beamEdgePaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.15)
          : Colors.black.withValues(alpha: 0.1)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(centerX, apexY),
        Offset(centerX - baseHalfWidth, baseY), beamEdgePaint);
    canvas.drawLine(Offset(centerX, apexY),
        Offset(centerX + baseHalfWidth, baseY), beamEdgePaint);

    // --- Haptic corridor triangle (±5° on-course zone) ---
    final hapticFrac = hapticThreshold / maxDeviation;
    final hapticBaseHalf = baseHalfWidth * hapticFrac;
    final hapticFillPaint = Paint()
      ..color = Colors.green.withValues(alpha: isDark ? 0.10 : 0.07);
    final hapticPath = Path()
      ..moveTo(centerX, apexY)
      ..lineTo(centerX - hapticBaseHalf, baseY)
      ..lineTo(centerX + hapticBaseHalf, baseY)
      ..close();
    canvas.drawPath(hapticPath, hapticFillPaint);

    // Haptic corridor edge lines
    final hapticEdgePaint = Paint()
      ..color = Colors.green.withValues(alpha: 0.35)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(centerX, apexY),
        Offset(centerX - hapticBaseHalf, baseY), hapticEdgePaint);
    canvas.drawLine(Offset(centerX, apexY),
        Offset(centerX + hapticBaseHalf, baseY), hapticEdgePaint);

    // --- Center line (dashed) ---
    final centerPaint = Paint()
      ..color = centerLineColor
      ..strokeWidth = 1.5;
    const dashLen = 8.0;
    const gapLen = 6.0;
    var y = apexY;
    while (y < baseY) {
      canvas.drawLine(
        Offset(centerX, y),
        Offset(centerX, math.min(y + dashLen, baseY)),
        centerPaint,
      );
      y += dashLen + gapLen;
    }

    // --- Distance countdown markers along centerline ---
    final distInUnits = distanceMeters / metersPerUnit;
    _drawDistanceMarkers(
        canvas, centerX, apexY, baseY, runwayHeight, distInUnits);

    // --- Anchor icon at apex ---
    _drawAnchorIcon(canvas, Offset(centerX, apexY + 10));

    // --- Vessel triangle offset by deviation ---
    final clampedDev = deviation.clamp(-maxDeviation, maxDeviation);
    final vesselX = centerX + (clampedDev / maxDeviation) * baseHalfWidth;
    final vesselY = baseY - 16;

    // Approach line from vessel to anchor
    final approachPaint = Paint()
      ..color = devColor.withValues(alpha: active ? 0.5 : 0.25)
      ..strokeWidth = 2.0;
    canvas.drawLine(
      Offset(vesselX, vesselY),
      Offset(centerX, apexY + 18),
      approachPaint,
    );

    // Vessel triangle
    final vesselPaint = Paint()..color = devColor;
    final vPath = Path()
      ..moveTo(vesselX, vesselY - 10)
      ..lineTo(vesselX - 8, vesselY + 6)
      ..lineTo(vesselX + 8, vesselY + 6)
      ..close();
    canvas.drawPath(vPath, vesselPaint);

    // --- P / S labels ---
    final labelStyle = TextStyle(
      fontSize: 11,
      color: isDark ? Colors.white38 : Colors.black38,
      fontWeight: FontWeight.bold,
    );
    _drawText(canvas, 'P', Offset(8, baseY - 20), labelStyle);
    _drawText(canvas, 'S', Offset(w - 16, baseY - 20), labelStyle);
  }

  /// Draw 3-4 evenly spaced distance markers ON the centerline.
  /// Labels show distance from the destination (0 at apex/anchor).
  /// Positioned at nice round fractions of total distance.
  void _drawDistanceMarkers(
    Canvas canvas,
    double centerX,
    double apexY,
    double baseY,
    double runwayHeight,
    double distInUnits,
  ) {
    if (distInUnits < 0.001) return;

    // Pick 3 evenly-spaced marker positions at 25%, 50%, 75% of distance
    final fractions = [0.25, 0.50, 0.75];

    final markerColor = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : Colors.black.withValues(alpha: 0.4);
    final markerStyle = TextStyle(
      fontSize: 10,
      color: markerColor,
      fontFamily: 'monospace',
      fontWeight: FontWeight.w500,
    );

    for (final frac in fractions) {
      // Distance from destination at this marker
      final distFromDest = distInUnits * frac;
      // Y position: frac=0 is at apex (destination), frac=1 is at base (vessel)
      final markerY = apexY + frac * runwayHeight;

      // Skip if too close to anchor icon or vessel triangle
      if (markerY < apexY + 30 || markerY > baseY - 34) continue;

      // Format the distance label
      final label = _formatSmartDistance(distFromDest);

      // Draw label centered on the centerline
      final tp = TextPainter(
        text: TextSpan(text: label, style: markerStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      // Background pill behind text for readability
      final pillRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX, markerY),
          width: tp.width + 10,
          height: tp.height + 4,
        ),
        const Radius.circular(4),
      );
      canvas.drawRRect(
        pillRect,
        Paint()..color = (isDark ? Colors.black : Colors.white).withValues(alpha: 0.6),
      );

      tp.paint(
        canvas,
        Offset(centerX - tp.width / 2, markerY - tp.height / 2),
      );
    }
  }

  /// Format distance with minimal clutter. No unit symbol on every marker —
  /// just the number. Unit is already shown in the header.
  String _formatSmartDistance(double value) {
    if (value >= 10) return value.toStringAsFixed(0);
    if (value >= 1) return value.toStringAsFixed(1);
    if (value >= 0.1) return value.toStringAsFixed(2);
    return value.toStringAsFixed(3);
  }

  void _drawAnchorIcon(Canvas canvas, Offset center) {
    final paint = Paint()
      ..color = isDark ? Colors.white70 : Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final x = center.dx;
    final y = center.dy;

    canvas.drawLine(Offset(x, y - 6), Offset(x, y + 6), paint);
    canvas.drawLine(Offset(x - 5, y - 3), Offset(x + 5, y - 3), paint);
    canvas.drawCircle(Offset(x, y - 7), 2, paint);
    final flukePath = Path()
      ..moveTo(x - 6, y + 2)
      ..quadraticBezierTo(x - 6, y + 7, x, y + 6)
      ..quadraticBezierTo(x + 6, y + 7, x + 6, y + 2);
    canvas.drawPath(flukePath, paint);
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_RunwayPainter oldDelegate) {
    return oldDelegate.deviation != deviation ||
        oldDelegate.distanceMeters != distanceMeters ||
        oldDelegate.isDark != isDark ||
        oldDelegate.active != active ||
        oldDelegate.metersPerUnit != metersPerUnit;
  }
}

// --------------- Builder ---------------

class FindHomeToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'find_home',
      name: 'Find Home',
      description:
          'ILS-style approach display for navigating back to your anchored vessel',
      category: ToolCategory.navigation,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 1,
        styleOptions: const [],
      ),
      defaultWidth: 2,
      defaultHeight: 3,
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: [
        DataSource(path: 'navigation.position', label: 'Home Target'),
      ],
      style: StyleConfig(
        customProperties: {
          'feedbackInterval': 10, // seconds (5-60)
        },
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return FindHomeTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
