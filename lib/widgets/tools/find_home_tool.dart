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
import '../../services/alarm_audio_player.dart';
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

  /// Sound asset path from config (default: whistle)
  String get _soundAsset {
    final key = widget.config.style.customProperties?['alertSound'] as String? ?? 'whistle';
    return AlarmAudioPlayer.alarmSounds[key] ?? 'sounds/alarm_whistle.mp3';
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
    try {
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

      // Get an immediate position first so the UI doesn't wait for the stream
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted) {
        setState(() => _devicePosition = lastKnown);
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
          debugPrint('FindHome GPS stream error: $error');
          if (mounted) setState(() => _gpsError = 'GPS error');
        },
      );
    } catch (e) {
      debugPrint('FindHome GPS init error: $e');
      if (mounted) setState(() => _gpsError = 'GPS init failed');
    }
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
    bool isWrongWay,
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

    // Wrong way: heading more than 90° away from target
    final isWrongWay = sogMs >= _sogThreshold && deviation.abs() > 90.0;

    return (
      bearing: bearing,
      deviation: deviation,
      distance: distance,
      cogDeg: AngleUtils.normalize(cogDeg),
      sogMs: sogMs,
      isWrongWay: isWrongWay,
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

    // Wrong way: 3 rapid buzzes regardless of direction
    if (nav.isWrongWay) {
      _vibrateTriple();
      if (_whistleEnabled) _whistleTriple();
      return;
    }

    final absDev = nav.deviation.abs();
    if (absDev < _hapticDeviationThreshold) return;

    if (nav.deviation > 0) {
      // On PORT side of course → turn starboard → 2 buzzes / 2 whistles
      _vibrateDouble();
      if (_whistleEnabled) _whistleDouble();
    } else {
      // On STARBOARD side of course → turn port → 1 buzz / 1 whistle
      _vibrateSingle();
      if (_whistleEnabled) _whistleSingle();
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

  /// Triple rapid vibration: wrong-way signal
  void _vibrateTriple() {
    Vibration.vibrate(
      pattern: [0, 300, 200, 300, 200, 300],
      intensities: [0, 255, 0, 255, 0, 255],
    );
  }

  /// Play one whistle blast
  Future<void> _whistleSingle() async {
    try {
      _whistlePlayer?.dispose();
      _whistlePlayer = AudioPlayer();
      await _whistlePlayer!.play(AssetSource(_soundAsset));
    } catch (e) {
      debugPrint('FindHome whistle error: $e');
    }
  }

  /// Play two whistle blasts
  Future<void> _whistleDouble() async {
    try {
      _whistlePlayer?.dispose();
      _whistlePlayer = AudioPlayer();
      await _whistlePlayer!.play(AssetSource(_soundAsset));
      // Wait for first blast to finish, then play second
      _whistlePlayer!.onPlayerComplete.first.then((_) async {
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted || !_active) return;
        _whistlePlayer?.dispose();
        _whistlePlayer = AudioPlayer();
        await _whistlePlayer!.play(AssetSource(_soundAsset));
      });
    } catch (e) {
      debugPrint('FindHome whistle error: $e');
    }
  }

  /// Play three rapid whistle blasts: wrong-way signal
  Future<void> _whistleTriple() async {
    try {
      var remaining = 3;
      void playNext() async {
        remaining--;
        if (remaining <= 0 || !mounted || !_active) return;
        await Future.delayed(const Duration(milliseconds: 150));
        if (!mounted || !_active) return;
        _whistlePlayer?.dispose();
        _whistlePlayer = AudioPlayer();
        await _whistlePlayer!.play(AssetSource(_soundAsset));
        _whistlePlayer!.onPlayerComplete.first.then((_) => playNext());
      }

      _whistlePlayer?.dispose();
      _whistlePlayer = AudioPlayer();
      await _whistlePlayer!.play(AssetSource(_soundAsset));
      _whistlePlayer!.onPlayerComplete.first.then((_) => playNext());
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
                    isWrongWay: nav.isWrongWay,
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
    final devSide = nav.deviation > 0 ? 'P' : 'S';
    final bool isWrongWay = nav.isWrongWay as bool;

    Color devColor;
    if (isWrongWay) {
      devColor = Colors.red;
    } else if (absDev < 5) {
      devColor = Colors.green;
    } else if (absDev < 15) {
      devColor = Colors.amber;
    } else {
      devColor = Colors.red;
    }

    final devLabel = isWrongWay
        ? 'WRONG WAY'
        : 'DEV ${absDev.toStringAsFixed(0)}° $devSide';
    final etaLabel = isWrongWay
        ? 'ETA --:--'
        : 'ETA ${_formatEta(nav.distance, nav.sogMs)}';

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
                'TO BOAT ${_formatAngle(nav.bearing)}',
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
                devLabel,
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
                etaLabel,
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
  final bool isWrongWay;

  _RunwayPainter({
    required this.deviation,
    required this.maxDeviation,
    required this.distanceMeters,
    required this.metersPerUnit,
    required this.unitSymbol,
    required this.isDark,
    required this.active,
    required this.hapticThreshold,
    required this.isWrongWay,
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

    // Background — red tint when wrong way
    final effectiveBg = isWrongWay
        ? Color.lerp(bgColor, Colors.red.shade900, 0.4)!
        : bgColor;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = effectiveBg,
    );

    // Dim runway elements when wrong way
    final dimFactor = isWrongWay ? 0.5 : 1.0;

    // Runway geometry — apex (anchor) at top, base (vessel) at bottom
    final apexY = 20.0;
    final baseY = h - 20.0;
    final runwayHeight = baseY - apexY;
    final baseHalfWidth = (w / 2) - 20;

    // --- Localizer beam triangle (full ±30° cone) ---
    final beamPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.04 * dimFactor)
          : Colors.black.withValues(alpha: 0.03 * dimFactor);
    final beamPath = Path()
      ..moveTo(centerX, apexY)
      ..lineTo(centerX - baseHalfWidth, baseY)
      ..lineTo(centerX + baseHalfWidth, baseY)
      ..close();
    canvas.drawPath(beamPath, beamPaint);

    // Beam edge lines
    final beamEdgePaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.15 * dimFactor)
          : Colors.black.withValues(alpha: 0.1 * dimFactor)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(centerX, apexY),
        Offset(centerX - baseHalfWidth, baseY), beamEdgePaint);
    canvas.drawLine(Offset(centerX, apexY),
        Offset(centerX + baseHalfWidth, baseY), beamEdgePaint);

    // --- Haptic corridor triangle (±5° on-course zone) ---
    final hapticFrac = hapticThreshold / maxDeviation;
    final hapticBaseHalf = baseHalfWidth * hapticFrac;
    final hapticFillPaint = Paint()
      ..color = Colors.green.withValues(alpha: (isDark ? 0.10 : 0.07) * dimFactor);
    final hapticPath = Path()
      ..moveTo(centerX, apexY)
      ..lineTo(centerX - hapticBaseHalf, baseY)
      ..lineTo(centerX + hapticBaseHalf, baseY)
      ..close();
    canvas.drawPath(hapticPath, hapticFillPaint);

    // Haptic corridor edge lines
    final hapticEdgePaint = Paint()
      ..color = Colors.green.withValues(alpha: 0.35 * dimFactor)
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

    // --- Vessel triangle ---
    // deviation > 0 = on PORT side (bearing is CW from COG) → triangle LEFT
    // deviation < 0 = on STARBOARD side → triangle RIGHT
    final clampedDev = deviation.clamp(-maxDeviation, maxDeviation);
    final vesselX = centerX - (clampedDev / maxDeviation) * baseHalfWidth;
    final vesselY = baseY - 16;

    // --- COG line (dotted, from vessel upward — where you're actually heading) ---
    // Only draw when vessel is within the runway (not clamped at edge)
    final isClamped = deviation.abs() >= maxDeviation;
    if (!isClamped) {
      final cogPaint = Paint()
        ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.4)
        ..strokeWidth = 1.0;
      _drawDashedLine(canvas, Offset(vesselX, vesselY - 12),
          Offset(vesselX, apexY + 20), cogPaint, 5, 4);
    }

    // --- Bearing line (dotted, from vessel to anchor — where you need to go) ---
    final bearingPaint = Paint()
      ..color = devColor.withValues(alpha: active ? 0.7 : 0.4)
      ..strokeWidth = 1.5;
    _drawDashedLine(canvas, Offset(vesselX, vesselY - 12),
        Offset(centerX, apexY + 18), bearingPaint, 6, 4);

    // Vessel chevron — open V-shape rotated by COG deviation
    canvas.save();
    canvas.translate(vesselX, vesselY);
    canvas.rotate(-deviation * math.pi / 180);
    final chevronPaint = Paint()
      ..color = devColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final chevronPath = Path()
      ..moveTo(-8, 6)
      ..lineTo(0, -8)
      ..lineTo(8, 6);
    canvas.drawPath(chevronPath, chevronPaint);
    canvas.restore();

    // --- P / S labels ---
    final labelStyle = TextStyle(
      fontSize: 11,
      color: isDark ? Colors.white38 : Colors.black38,
      fontWeight: FontWeight.bold,
    );
    _drawText(canvas, 'P', Offset(8, baseY - 20), labelStyle);
    _drawText(canvas, 'S', Offset(w - 16, baseY - 20), labelStyle);

    // --- Wrong-way overlay ---
    if (isWrongWay) {
      _drawWrongWayOverlay(canvas, size, deviation);
    }
  }

  void _drawWrongWayOverlay(Canvas canvas, Size size, double deviation) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // "TURN AROUND" title
    final titleStyle = TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w900,
      color: Colors.red.shade300,
      letterSpacing: 2.0,
    );
    final titleTp = TextPainter(
      text: TextSpan(text: 'TURN AROUND', style: titleStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    titleTp.paint(
      canvas,
      Offset(centerX - titleTp.width / 2, centerY - titleTp.height - 4),
    );

    // Direction hint: deviation > 0 means boat is to port → turn starboard
    final turnDir = deviation > 0 ? 'TURN STARBOARD' : 'TURN PORT';
    final arrow = deviation > 0 ? '\u21BB' : '\u21BA'; // ↻ or ↺
    final dirStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: Colors.red.shade200,
      letterSpacing: 1.0,
    );
    final dirTp = TextPainter(
      text: TextSpan(text: '$arrow $turnDir', style: dirStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    dirTp.paint(
      canvas,
      Offset(centerX - dirTp.width / 2, centerY + 4),
    );
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

  void _drawDashedLine(Canvas canvas, Offset from, Offset to, Paint paint,
      double dashLen, double gapLen) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 1) return;
    final ux = dx / dist;
    final uy = dy / dist;
    var drawn = 0.0;
    while (drawn < dist) {
      final segEnd = math.min(drawn + dashLen, dist);
      canvas.drawLine(
        Offset(from.dx + ux * drawn, from.dy + uy * drawn),
        Offset(from.dx + ux * segEnd, from.dy + uy * segEnd),
        paint,
      );
      drawn = segEnd + gapLen;
    }
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
        oldDelegate.metersPerUnit != metersPerUnit ||
        oldDelegate.isWrongWay != isWrongWay;
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
          'alertSound': 'whistle',
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
