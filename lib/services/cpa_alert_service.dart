import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/cpa_alert_state.dart';
import '../models/alert_event.dart';
import '../utils/cpa_utils.dart';
import 'signalk_service.dart';
import 'notification_service.dart';
import 'messaging_service.dart';
import 'storage_service.dart';
import 'alert_coordinator.dart';

/// Background service that continuously monitors AIS vessels for CPA/TCPA
/// and triggers escalating alerts (notifications, crew messages, audio alarms).
class CpaAlertService extends ChangeNotifier {
  final SignalKService _signalKService;
  final NotificationService _notificationService;
  final MessagingService? _messagingService;
  final StorageService? _storageService;

  CpaAlertConfig _config = const CpaAlertConfig();
  CpaAlertConfig get config => _config;

  final Map<String, CpaVesselAlert> _vesselAlerts = {};
  Map<String, CpaVesselAlert> get vesselAlerts =>
      Map.unmodifiable(_vesselAlerts);

  /// Manual dismissals — vessel won't re-alert until this time expires.
  final Map<String, DateTime> _dismissedUntil = {};

  bool get hasActiveAlarm =>
      _vesselAlerts.values.any((a) => a.level.isAlarming);

  final AlertCoordinator? _alertCoordinator;

  DateTime? _lastEvaluation;
  static const _evaluationThrottle = Duration(milliseconds: 500);

  /// Coalesced notifyListeners — schedules a single microtask to avoid
  /// calling notifyListeners() during build/layout phases.
  bool _notifyScheduled = false;

  void _safeNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    Future.microtask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  // Reuse alarm sounds from anchor alarm service
  static const Map<String, String> alarmSounds = {
    'bell': 'sounds/alarm_bell.mp3',
    'foghorn': 'sounds/alarm_foghorn.mp3',
    'chimes': 'sounds/alarm_chimes.mp3',
  };

  /// VesselId requested to be highlighted by a notification tap.
  /// The AIS chart reads this in its listener and clears it after use.
  String? _highlightRequestedVesselId;
  String? get highlightRequestedVesselId => _highlightRequestedVesselId;
  void clearHighlightRequest() => _highlightRequestedVesselId = null;
  void requestHighlight(String vesselId) {
    _highlightRequestedVesselId = vesselId;
    _safeNotify();
  }

  /// Callback for in-app snackbar display (set by the owning widget).
  void Function(CpaVesselAlert alert, String message)? onAlertTriggered;

  /// Callback fired when system notification is tapped/dismissed (so snackbar can hide).
  void Function(String vesselId)? onAlertDismissed;

  /// Auto-sunset: alerts older than this are pruned automatically.
  static const Duration _alertSunset = Duration(hours: 48);

  CpaAlertService({
    required SignalKService signalKService,
    required NotificationService notificationService,
    MessagingService? messagingService,
    StorageService? storageService,
    AlertCoordinator? alertCoordinator,
  })  : _signalKService = signalKService,
        _notificationService = notificationService,
        _messagingService = messagingService,
        _storageService = storageService,
        _alertCoordinator = alertCoordinator {
    _notificationService.registerAlarmCallback('ais_polar_chart', _onAlarmTapped);
  }

  /// Apply config in memory and start/stop monitoring accordingly.
  void applyConfig(CpaAlertConfig newConfig) {
    _config = newConfig;

    if (newConfig.enabled) {
      _startMonitoring();
    } else {
      _stopMonitoring();
    }

    _safeNotify();
  }

  /// Callback from notification tap — stops sound and requests vessel highlight.
  void _onAlarmTapped(String? vesselId) {
    _alertCoordinator?.acknowledgeAlarm(AlertSubsystem.cpa);
    if (vesselId != null) {
      _highlightRequestedVesselId = vesselId;
      onAlertDismissed?.call(vesselId);
      _safeNotify();
    }
  }

  /// User acknowledges / silences the audio alarm.
  void acknowledgeAlarm() {
    _alertCoordinator?.acknowledgeAlarm(AlertSubsystem.cpa);
  }

  /// Dismiss a single alert locally (with cooldown so it won't re-trigger immediately).
  void dismissAlert(String vesselId) {
    _vesselAlerts.remove(vesselId);
    _notificationService.cancelAlarmNotification(vesselId);
    _dismissedUntil[vesselId] =
        DateTime.now().add(Duration(seconds: _config.cooldownSeconds));
    if (!hasActiveAlarm) _alertCoordinator?.resolveAlert(AlertSubsystem.cpa);
    _safeNotify();
  }

  /// Dismiss all alerts and cancel all CPA notifications.
  void dismissAllAlerts() {
    final now = DateTime.now();
    for (final id in _vesselAlerts.keys.toList()) {
      _notificationService.cancelAlarmNotification(id);
      _dismissedUntil[id] = now.add(Duration(seconds: _config.cooldownSeconds));
    }
    _vesselAlerts.clear();
    _alertCoordinator?.resolveAlert(AlertSubsystem.cpa);
    _safeNotify();
  }

  void _startMonitoring() {
    _signalKService.aisVesselRegistry.addListener(_onAISUpdate);
    _evaluate();
  }

  void _stopMonitoring() {
    _signalKService.aisVesselRegistry.removeListener(_onAISUpdate);
    _alertCoordinator?.resolveAlert(AlertSubsystem.cpa);
    for (final id in _vesselAlerts.keys.toList()) {
      _notificationService.cancelAlarmNotification(id);
    }
    _vesselAlerts.clear();
    _safeNotify();
  }

  void _onAISUpdate() {
    if (!_config.enabled) return;
    final now = DateTime.now();
    if (_lastEvaluation != null &&
        now.difference(_lastEvaluation!) < _evaluationThrottle) {
      return;
    }
    _lastEvaluation = now;
    _evaluate();
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

      // Skip vessels beyond max range (garbage AIS data)
      if (distance > _config.maxRangeMeters) continue;

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
        _notificationService.cancelAlarmNotification(vessel.vesselId);
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
      _notificationService.cancelAlarmNotification(id);
      changed = true;
    }

    // Sunset alerts older than 48 hours
    final sunsetIds = _vesselAlerts.entries
        .where((e) => now.difference(e.value.firstAlerted) > _alertSunset)
        .map((e) => e.key)
        .toList();
    for (final id in sunsetIds) {
      _vesselAlerts.remove(id);
      _notificationService.cancelAlarmNotification(id);
      changed = true;
    }

    // Resolve alert if no vessels at alarm level
    if (!hasActiveAlarm && (_alertCoordinator?.audioPlayer.activeSource == 'cpa')) {
      _alertCoordinator?.resolveAlert(AlertSubsystem.cpa);
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

    // Check manual dismissal cooldown
    final dismissedUntil = _dismissedUntil[vesselId];
    if (dismissedUntil != null) {
      if (now.isBefore(dismissedUntil)) return CpaAlertLevel.normal;
      _dismissedUntil.remove(vesselId); // expired
    }

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
    final message = '$name - CPA $cpaDisplay in $tcpaDisplay';

    if (_alertCoordinator != null) {
      _alertCoordinator.submitAlert(AlertEvent(
        subsystem: AlertSubsystem.cpa,
        severity: alert.level.isAlarming ? AlertSeverity.alarm : AlertSeverity.warn,
        title: title,
        body: message,
        wantsSystemNotification: true,
        wantsInAppSnackbar: true,
        wantsAudio: alert.level.isAlarming,
        wantsCrewBroadcast: _config.sendCrewAlert && alert.level.isAlarming,
        alarmSound: _config.alarmSound,
        alarmId: alert.vesselId,
        alarmSource: 'ais_polar_chart',
        callbackData: alert,
      ));
      // Also fire widget callback for highlight/focus if registered
      onAlertTriggered?.call(alert, message);
    } else {
      // Fallback without coordinator
      final filterLevel = alert.level.isAlarming ? 'alarm' : 'warn';
      final showSystem = _storageService?.getSystemNotificationFilter(filterLevel) ?? true;
      final showInApp = _storageService?.getInAppNotificationFilter(filterLevel) ?? true;
      if (showSystem) {
        await _notificationService.showAlarmNotification(
          title: title,
          body: message,
          alarmId: alert.vesselId,
          alarmSource: 'ais_polar_chart',
        );
      }
      if (_config.sendCrewAlert && alert.level.isAlarming && showSystem) {
        _messagingService?.sendAlert(message, alertId: 'alert-cpa-${alert.vesselId}');
      }
      if (showInApp) {
        onAlertTriggered?.call(alert, message);
      }
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

  @override
  void dispose() {
    _signalKService.aisVesselRegistry.removeListener(_onAISUpdate);
    _notificationService.unregisterAlarmCallback('ais_polar_chart');
    super.dispose();
  }
}
