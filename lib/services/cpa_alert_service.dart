import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/cpa_alert_state.dart';
import '../utils/cpa_utils.dart';
import 'signalk_service.dart';
import 'notification_service.dart';
import 'messaging_service.dart';

/// Background service that continuously monitors AIS vessels for CPA/TCPA
/// and triggers escalating alerts (notifications, crew messages, audio alarms).
class CpaAlertService extends ChangeNotifier {
  final SignalKService _signalKService;
  final NotificationService _notificationService;
  final MessagingService? _messagingService;

  CpaAlertConfig _config = const CpaAlertConfig();
  CpaAlertConfig get config => _config;

  final Map<String, CpaVesselAlert> _vesselAlerts = {};
  Map<String, CpaVesselAlert> get vesselAlerts =>
      Map.unmodifiable(_vesselAlerts);

  bool get hasActiveAlarm =>
      _vesselAlerts.values.any((a) => a.level.isAlarming);

  Timer? _evaluationTimer;
  AudioPlayer? _alarmPlayer;
  Timer? _alarmRepeatTimer;
  bool _alarmSoundPlaying = false;

  static const Duration _evaluationInterval = Duration(seconds: 5);

  // Reuse alarm sounds from anchor alarm service
  static const Map<String, String> alarmSounds = {
    'bell': 'sounds/alarm_bell.mp3',
    'foghorn': 'sounds/alarm_foghorn.mp3',
    'chimes': 'sounds/alarm_chimes.mp3',
  };

  CpaAlertService({
    required SignalKService signalKService,
    required NotificationService notificationService,
    MessagingService? messagingService,
  })  : _signalKService = signalKService,
        _notificationService = notificationService,
        _messagingService = messagingService;

  /// Apply config in memory and start/stop monitoring accordingly.
  void applyConfig(CpaAlertConfig newConfig) {
    final wasEnabled = _config.enabled;
    _config = newConfig;

    if (newConfig.enabled && !wasEnabled) {
      _startMonitoring();
    } else if (!newConfig.enabled && wasEnabled) {
      _stopMonitoring();
    }

    notifyListeners();
  }

  /// User acknowledges / silences the audio alarm.
  void acknowledgeAlarm() {
    _stopAlarmSound();
  }

  void _startMonitoring() {
    _evaluationTimer?.cancel();
    _evaluationTimer =
        Timer.periodic(_evaluationInterval, (_) => _evaluate());
  }

  void _stopMonitoring() {
    _evaluationTimer?.cancel();
    _evaluationTimer = null;
    _stopAlarmSound();
    _vesselAlerts.clear();
    notifyListeners();
  }

  /// Extract a raw numeric SI value from a SignalK data point.
  double? _rawNum(String path) {
    final dp = _signalKService.getValue(path);
    if (dp?.original is num) return (dp!.original as num).toDouble();
    if (dp?.value is num) return (dp!.value as num).toDouble();
    return null;
  }

  // ===== Evaluation Loop =====

  void _evaluate() {
    if (!_config.enabled || !_signalKService.isConnected) return;

    // Get own vessel position
    final posData = _signalKService.getValue('navigation.position')?.value;
    if (posData is! Map) return;
    final ownLat = (posData['latitude'] as num?)?.toDouble();
    final ownLon = (posData['longitude'] as num?)?.toDouble();
    if (ownLat == null || ownLon == null) return;

    final ownCogRad = _rawNum('navigation.courseOverGroundTrue');
    final ownSogMs = _rawNum('navigation.speedOverGround') ?? 0.0;

    final vessels = _signalKService.aisVesselRegistry.vessels;
    final now = DateTime.now();
    bool changed = false;

    // Evaluate each vessel
    for (final entry in vessels.entries) {
      final vessel = entry.value;
      if (!vessel.hasPosition) continue;

      final bearing = CpaUtils.calculateBearing(
          ownLat, ownLon, vessel.latitude!, vessel.longitude!);
      final distance = CpaUtils.calculateDistance(
          ownLat, ownLon, vessel.latitude!, vessel.longitude!);

      final cpaTcpa = CpaUtils.calculateCpaTcpa(
        bearingDeg: bearing,
        distanceM: distance,
        ownCogRad: ownCogRad,
        ownSogMs: ownSogMs,
        targetCogRad: vessel.cogRad,
        targetSogMs: vessel.sogMs,
      );

      if (cpaTcpa == null) continue;

      final newLevel = _determineLevel(
        vessel.vesselId,
        cpaTcpa.cpa,
        cpaTcpa.tcpa,
        now,
      );

      final existing = _vesselAlerts[vessel.vesselId];
      final previousLevel = existing?.level ?? CpaAlertLevel.normal;

      if (newLevel == CpaAlertLevel.normal && existing == null) continue;

      if (newLevel == CpaAlertLevel.normal) {
        _vesselAlerts.remove(vessel.vesselId);
        changed = true;
      } else {
        final alert = CpaVesselAlert(
          vesselId: vessel.vesselId,
          vesselName: vessel.name,
          level: newLevel,
          cpaMeters: cpaTcpa.cpa,
          tcpaSeconds: cpaTcpa.tcpa,
          firstAlerted: existing?.firstAlerted ?? now,
          lastUpdated: now,
          cooldownUntil: existing?.cooldownUntil,
        );
        _vesselAlerts[vessel.vesselId] = alert;
        changed = true;

        // Dispatch alerts on escalation
        if (newLevel.index > previousLevel.index) {
          _triggerAlerts(alert);
        }
      }
    }

    // Prune alerts for vessels no longer in registry
    final staleIds = _vesselAlerts.keys
        .where((id) => !vessels.containsKey(id))
        .toList();
    for (final id in staleIds) {
      _vesselAlerts.remove(id);
      changed = true;
    }

    // Stop alarm sound if no vessels at alarm level
    if (!hasActiveAlarm && _alarmSoundPlaying) {
      _stopAlarmSound();
      changed = true;
    }

    if (changed) notifyListeners();
  }

  /// Determine alert level with hysteresis and cooldown.
  CpaAlertLevel _determineLevel(
    String vesselId,
    double cpaMeters,
    double tcpaSeconds,
    DateTime now,
  ) {
    final existing = _vesselAlerts[vesselId];

    // Check cooldown
    if (existing?.cooldownUntil != null &&
        now.isBefore(existing!.cooldownUntil!)) {
      return CpaAlertLevel.normal;
    }

    final approaching = tcpaSeconds > 0 && tcpaSeconds < _config.tcpaThresholdSeconds;
    final hysteresisThreshold = _config.warnThresholdMeters * 1.2;

    // De-escalation: vessel diverging or moved outside hysteresis band
    if (existing != null && existing.level != CpaAlertLevel.normal) {
      if (!approaching || cpaMeters > hysteresisThreshold) {
        // Set cooldown when de-escalating from alarm
        if (existing.level.isAlarming) {
          _vesselAlerts[vesselId] = existing.copyWith(
            level: CpaAlertLevel.normal,
            lastUpdated: now,
            cooldownUntil: now.add(Duration(seconds: _config.cooldownSeconds)),
          );
          return CpaAlertLevel.normal;
        }
        return CpaAlertLevel.normal;
      }
    }

    if (!approaching) return CpaAlertLevel.normal;

    // Escalation
    if (cpaMeters < _config.alarmThresholdMeters) {
      return CpaAlertLevel.alarm;
    } else if (cpaMeters < _config.warnThresholdMeters) {
      return CpaAlertLevel.warning;
    }

    return CpaAlertLevel.normal;
  }

  // ===== Alert Dispatch =====

  Future<void> _triggerAlerts(CpaVesselAlert alert) async {
    final name = alert.vesselName ?? _extractMMSI(alert.vesselId);
    final cpaDisplay = _formatCpa(alert.cpaMeters);
    final tcpaDisplay = _formatTcpa(alert.tcpaSeconds);

    final title = alert.level.isAlarming ? 'CPA ALARM' : 'CPA Warning';
    final message = '$title: $name - CPA $cpaDisplay in $tcpaDisplay';

    // 1. Audio (alarm level only)
    if (alert.level.isAlarming) await _playAlarmSound();

    // 2. System notification
    await _notificationService.showAlarmNotification(
      title: title,
      body: message,
    );

    // 3. Crew broadcast (if configured)
    if (_config.sendCrewAlert) {
      _messagingService?.sendAlert(message);
    }
  }

  String _extractMMSI(String vesselId) {
    final match = RegExp(r'(\d{9})').firstMatch(vesselId);
    return match?.group(1) ?? vesselId;
  }

  String _formatCpa(double meters) {
    final metadata =
        _signalKService.metadataStore.getByCategory('distance');
    if (metadata != null) {
      return metadata.format(meters);
    }
    // Fallback: show in nautical miles
    final nm = meters / 1852.0;
    return '${nm.toStringAsFixed(2)} nm';
  }

  String _formatTcpa(double tcpaSeconds) {
    if (tcpaSeconds < 60) {
      return '${tcpaSeconds.toStringAsFixed(0)}s';
    } else if (tcpaSeconds < 3600) {
      final minutes = tcpaSeconds / 60;
      return '${minutes.toStringAsFixed(1)}m';
    } else {
      final hours = tcpaSeconds / 3600;
      return '${hours.toStringAsFixed(1)}h';
    }
  }

  // ===== Audio =====

  Future<void> _playAlarmSound() async {
    if (_alarmSoundPlaying) return;

    final assetPath =
        alarmSounds[_config.alarmSound] ?? alarmSounds['foghorn']!;

    try {
      _alarmPlayer?.dispose();
      _alarmPlayer = AudioPlayer();
      await _alarmPlayer!.setVolume(1.0);
      await _alarmPlayer!.play(AssetSource(assetPath));
      _alarmSoundPlaying = true;

      // Repeat every 5 seconds while alarm is active
      _alarmRepeatTimer?.cancel();
      _alarmRepeatTimer =
          Timer.periodic(const Duration(seconds: 5), (_) async {
        if (hasActiveAlarm) {
          _alarmPlayer?.dispose();
          _alarmPlayer = AudioPlayer();
          await _alarmPlayer!.play(AssetSource(assetPath));
        } else {
          _alarmRepeatTimer?.cancel();
          _alarmSoundPlaying = false;
        }
      });
    } catch (e) {
      if (kDebugMode) {
        print('CpaAlertService: error playing alarm sound: $e');
      }
    }
  }

  Future<void> _stopAlarmSound() async {
    _alarmRepeatTimer?.cancel();
    _alarmPlayer?.stop();
    _alarmPlayer?.dispose();
    _alarmPlayer = null;
    _alarmSoundPlaying = false;
  }

  @override
  void dispose() {
    _evaluationTimer?.cancel();
    _alarmRepeatTimer?.cancel();
    _alarmPlayer?.dispose();
    super.dispose();
  }
}
