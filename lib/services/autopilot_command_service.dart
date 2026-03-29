import 'package:flutter/foundation.dart';
import 'autopilot_api_detector.dart';
import 'autopilot_v2_api.dart';
import 'signalk_service.dart';
import '../models/autopilot_errors.dart';

/// Shared autopilot command service — owns API detection and provides
/// all command methods with V1/V2 dispatch.
///
/// Used by FindHome route mode and any widget that needs AP control
/// without duplicating the V1/V2 dispatch logic. Each method throws
/// [AutopilotException] on failure; UI feedback is the caller's
/// responsibility.
class AutopilotCommandService {
  final SignalKService _signalKService;

  AutopilotApiVersion? _apiVersion;
  AutopilotV2Api? _v2Api;
  String? _selectedInstanceId;

  AutopilotCommandService({required SignalKService signalKService})
      : _signalKService = signalKService;

  bool get isDetected => _apiVersion != null;
  bool get isV2 => _apiVersion?.isV2 ?? false;
  String get apiVersionString => _apiVersion?.version ?? 'unknown';
  String? get selectedInstanceId => _selectedInstanceId;

  /// Detect autopilot API version. Returns true if an autopilot was found.
  Future<bool> detect() async {
    try {
      final detector = AutopilotApiDetector(
        baseUrl: _signalKService.httpBaseUrl,
        authToken: _signalKService.authToken?.token,
      );

      _apiVersion = await detector.detectApiVersion();

      if (_apiVersion!.isV2) {
        final instance = _apiVersion!.defaultInstance;
        if (instance != null) {
          _selectedInstanceId = instance.id;
          _v2Api = AutopilotV2Api(
            baseUrl: _signalKService.httpBaseUrl,
            authToken: _signalKService.authToken?.token,
          );
          _v2Api!.useKeystrokeStrategy = instance.id == 'raySTNGConv';
        }
      }

      if (kDebugMode) print('AutopilotCommandService: detected ${_apiVersion!.version}');
      return true;
    } catch (e) {
      if (kDebugMode) print('AutopilotCommandService: detection failed: $e');
      return false;
    }
  }

  /// Engage autopilot (V1: PUT state=auto, V2: engage())
  Future<void> engage() async {
    if (_useV2) {
      await _v2Api!.engage(_selectedInstanceId!);
    } else {
      await _signalKService.sendPutRequest(
        'steering.autopilot.state',
        'auto',
      );
    }
  }

  /// Disengage autopilot (V1: PUT state=standby, V2: disengage())
  Future<void> disengage() async {
    if (_useV2) {
      await _v2Api!.disengage(_selectedInstanceId!);
    } else {
      await _signalKService.sendPutRequest(
        'steering.autopilot.state',
        'standby',
      );
    }
  }

  /// Set autopilot mode (auto, wind, route, standby)
  Future<void> setMode(String mode) async {
    if (_useV2) {
      await _v2Api!.setMode(_selectedInstanceId!, mode.toLowerCase());
    } else {
      await _signalKService.sendPutRequest(
        'steering.autopilot.state',
        mode.toLowerCase(),
      );
    }
  }

  /// Adjust heading by [degrees] (±1, ±10, etc.)
  Future<void> adjustHeading(int degrees) async {
    if (_useV2) {
      await _v2Api!.adjustTarget(_selectedInstanceId!, degrees);
    } else {
      await _signalKService.sendPutRequest(
        'steering.autopilot.actions.adjustHeading',
        degrees,
      );
    }
  }

  /// Set absolute target heading in degrees
  Future<void> setTarget(double headingDeg, {double? currentHeadingDeg}) async {
    if (_useV2) {
      await _v2Api!.setTarget(_selectedInstanceId!, headingDeg,
          currentHeadingDeg: currentHeadingDeg);
    } else {
      await _signalKService.sendPutRequest(
        'steering.autopilot.target.headingMagnetic',
        headingDeg,
      );
    }
  }

  /// Advance to next waypoint on route
  Future<void> advanceWaypoint() async {
    if (_useV2) {
      await _v2Api!.courseNextPoint(_selectedInstanceId!);
    } else {
      await _signalKService.sendPutRequest(
        'steering.autopilot.actions.advanceWaypoint',
        1,
      );
    }
  }

  /// Tack to [direction] ('port' or 'starboard')
  Future<void> tack(String direction) async {
    if (_useV2) {
      await _v2Api!.tack(_selectedInstanceId!, direction);
    } else {
      await _signalKService.sendPutRequest(
        'steering.autopilot.actions.tack',
        direction,
      );
    }
  }

  /// Gybe to [direction] ('port' or 'starboard') — V2 only
  Future<void> gybe(String direction) async {
    if (!isV2) {
      throw AutopilotException(
        'Gybe not available in V1 API',
        type: AutopilotErrorType.v2NotAvailable,
      );
    }
    await _v2Api!.gybe(_selectedInstanceId!, direction);
  }

  /// Activate dodge mode — V2 only
  Future<void> activateDodge() async {
    if (!isV2) {
      throw AutopilotException(
        'Dodge mode not available in V1 API',
        type: AutopilotErrorType.v2NotAvailable,
      );
    }
    await _v2Api!.activateDodge(_selectedInstanceId!);
  }

  /// Deactivate dodge mode — V2 only
  Future<void> deactivateDodge() async {
    if (!isV2) {
      throw AutopilotException(
        'Dodge mode not available in V1 API',
        type: AutopilotErrorType.v2NotAvailable,
      );
    }
    await _v2Api!.deactivateDodge(_selectedInstanceId!);
  }

  bool get _useV2 =>
      _apiVersion?.isV2 == true &&
      _v2Api != null &&
      _selectedInstanceId != null;

  void dispose() {
    _v2Api?.dispose();
    _v2Api = null;
  }
}
