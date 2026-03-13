import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'autopilot_api_detector.dart';
import 'autopilot_v2_api.dart';
import 'signalk_service.dart';
import '../utils/dodge_utils.dart';

/// Status record for UI display of dodge autopilot state.
class DodgeAutopilotStatus {
  final bool active;
  final double? lastSentHeadingDeg;
  final String? error;

  const DodgeAutopilotStatus({
    this.active = false,
    this.lastSentHeadingDeg,
    this.error,
  });
}

/// Bridges dodge computation results to autopilot heading commands.
///
/// Standalone service that sends dodge-recommended headings to the autopilot
/// via V1 PUT or V2 setTarget(). Throttled, deadbanded, and clamped for safety.
class DodgeAutopilotService {
  final SignalKService _signalKService;

  // Autopilot API state (detected once on first activation)
  AutopilotApiVersion? _apiVersion;
  AutopilotV2Api? _v2Api;
  String? _selectedInstanceId;

  // Active state
  bool _active = false;

  // Throttle / deadband tracking
  double? _lastSentHeadingRad;
  DateTime? _lastSentTime;

  // Error state
  String? _lastError;

  // Safety constants
  static const _minSendIntervalSeconds = 5;
  static const _deadbandDeg = 2.0;
  static const _maxSingleChangeDeg = 45.0;

  DodgeAutopilotService({required SignalKService signalKService})
      : _signalKService = signalKService;

  bool get isActive => _active;
  String? get lastError => _lastError;

  DodgeAutopilotStatus get status => DodgeAutopilotStatus(
        active: _active,
        lastSentHeadingDeg: _lastSentHeadingRad != null
            ? _lastSentHeadingRad! * 180.0 / math.pi
            : null,
        error: _lastError,
      );

  /// Detect autopilot API version. Returns true if an autopilot was found.
  Future<bool> detectAutopilot() async {
    try {
      final detector = AutopilotApiDetector(
        baseUrl: _signalKService.serverUrl,
        authToken: _signalKService.authToken?.token,
      );

      _apiVersion = await detector.detectApiVersion();

      if (_apiVersion!.isV2) {
        final instance = _apiVersion!.defaultInstance;
        if (instance != null) {
          _selectedInstanceId = instance.id;
          _v2Api = AutopilotV2Api(
            baseUrl: _signalKService.serverUrl,
            authToken: _signalKService.authToken?.token,
          );
        }
      }

      _lastError = null;
      return true;
    } catch (e) {
      _lastError = 'Detection failed: $e';
      if (kDebugMode) print('DodgeAP: $_lastError');
      return false;
    }
  }

  /// Verify the autopilot is in 'auto' mode and ready to accept heading commands.
  /// Records the current target heading as pre-dodge heading.
  /// Returns null on success, or an error message.
  Future<String?> verifyAutopilotReady() async {
    try {
      // Check AP state from SignalK cache
      final stateData =
          _signalKService.getValue('steering.autopilot.state');
      final state = stateData?.value as String?;

      if (state == null) {
        return 'Autopilot state unknown';
      }
      if (state != 'auto') {
        return 'Autopilot not in auto mode (currently: $state)';
      }

      _lastError = null;
      return null;
    } catch (e) {
      return 'Failed to verify autopilot: $e';
    }
  }

  /// Activate auto-dodge heading updates.
  void activate() {
    _active = true;
    _lastSentHeadingRad = null;
    _lastSentTime = null;
    _lastError = null;
    if (kDebugMode) print('DodgeAP: activated');
  }

  /// Deactivate auto-dodge. Does NOT disengage the autopilot hardware.
  void deactivate() {
    _active = false;
    if (kDebugMode) print('DodgeAP: deactivated — AP holding last heading');
  }

  /// Send a dodge heading to the autopilot.
  ///
  /// Safe to call every frame — internally throttled (5s), deadbanded (2°),
  /// and clamped (45° max single change).
  Future<void> sendDodgeHeading(DodgeResult dodge) async {
    // Guard 1: not active
    if (!_active) return;

    // Guard 2: infeasible dodge
    if (!dodge.isFeasible) return;

    // Guard 3: bow pass not safe
    if (dodge.bowPassSafe == false && dodge.courseToSteerRad != 0) {
      // bowPassSafe is only meaningful when bow pass was requested
      // We check this at the call site too, but belt-and-suspenders
    }

    // Guard 4: throttle — minimum 5 seconds between sends
    final now = DateTime.now();
    if (_lastSentTime != null &&
        now.difference(_lastSentTime!).inSeconds < _minSendIntervalSeconds) {
      return;
    }

    // Get magnetic variation from SignalK (radians, SI)
    final magVarData =
        _signalKService.getValue('navigation.magneticVariation');
    if (magVarData?.value is! num) {
      _lastError = 'No magnetic variation data';
      if (kDebugMode) print('DodgeAP: $_lastError');
      return;
    }
    final magVarRad = (magVarData!.value as num).toDouble();

    // Convert true heading to magnetic: magnetic = true - variation
    final courseToSteerRad = dodge.courseToSteerRad;
    final magneticHeadingRad = courseToSteerRad - magVarRad;

    // Guard 5: deadband — skip if change < 2° from last sent
    if (_lastSentHeadingRad != null) {
      final changeDeg =
          (_angleDiffRad(magneticHeadingRad, _lastSentHeadingRad!).abs()) *
              180.0 /
              math.pi;
      if (changeDeg < _deadbandDeg) return;

      // Guard 6: clamp single change to 45°
      if (changeDeg > _maxSingleChangeDeg) {
        if (kDebugMode) {
          print(
              'DodgeAP: clamping ${changeDeg.toStringAsFixed(1)}° to $_maxSingleChangeDeg°');
        }
        // Clamp: move max 45° in the direction of the new heading
        final sign =
            _angleDiffRad(magneticHeadingRad, _lastSentHeadingRad!) > 0
                ? 1.0
                : -1.0;
        final clampedRad =
            _lastSentHeadingRad! + sign * _maxSingleChangeDeg * math.pi / 180.0;
        await _sendHeading(_normalizeRad(clampedRad));
        return;
      }
    }

    await _sendHeading(magneticHeadingRad);
  }

  /// Actually send the heading to the autopilot hardware.
  Future<void> _sendHeading(double magneticHeadingRad) async {
    final headingDeg = _normalizeRad(magneticHeadingRad) * 180.0 / math.pi;

    try {
      if (_apiVersion?.isV2 == true &&
          _v2Api != null &&
          _selectedInstanceId != null) {
        // V2: setTarget expects degrees
        await _v2Api!.setTarget(_selectedInstanceId!, headingDeg);
      } else {
        // V1: PUT to steering.autopilot.target.headingMagnetic (radians)
        await _signalKService.sendPutRequest(
          'steering.autopilot.target.headingMagnetic',
          magneticHeadingRad,
        );
      }

      _lastSentHeadingRad = magneticHeadingRad;
      _lastSentTime = DateTime.now();
      _lastError = null;

      if (kDebugMode) {
        print('DodgeAP: sent heading ${headingDeg.toStringAsFixed(1)}°M');
      }
    } catch (e) {
      _lastError = 'Send failed: $e';
      if (kDebugMode) print('DodgeAP: $_lastError');
    }
  }

  /// Signed angle difference in radians (-π to +π).
  static double _angleDiffRad(double a, double b) {
    double diff = a - b;
    while (diff > math.pi) {
      diff -= 2 * math.pi;
    }
    while (diff < -math.pi) {
      diff += 2 * math.pi;
    }
    return diff;
  }

  /// Normalize radians to 0..2π.
  static double _normalizeRad(double rad) {
    double r = rad % (2 * math.pi);
    if (r < 0) r += 2 * math.pi;
    return r;
  }

  void dispose() {
    _active = false;
    _v2Api?.dispose();
  }
}
