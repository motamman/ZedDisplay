import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import '../models/alert_event.dart';
import 'alarm_audio_player.dart';
import 'notification_service.dart';
import 'messaging_service.dart';
import 'storage_service.dart';

/// Central gateway for all alert delivery.
///
/// Subsystems keep their domain logic (evaluation, thresholds, state tracking)
/// but delegate delivery to the coordinator, which enforces filters centrally.
///
/// Responsibilities:
/// 1. Accept alerts from any subsystem via submitAlert()
/// 2. Dedup/throttle per subsystem+alarmId
/// 3. Track active alerts (what's currently firing)
/// 4. Route to 4 channels: system notification, snackbar, audio, crew broadcast
/// 5. Filter each channel: master toggle, per-severity, overlay, app lifecycle
/// 6. Acknowledge/cancel: stop audio, dismiss notification, clear from active
/// 7. Global audio mute with auto-unmute safety timer
class AlertCoordinator extends ChangeNotifier {
  final StorageService _storageService;
  final NotificationService _notificationService;
  final MessagingService? _messagingService;
  final AlarmAudioPlayer _audioPlayer;

  static const _defaultThrottle = Duration(seconds: 30);
  static const _defaultAutoUnmute = Duration(minutes: 5);

  // --- Snackbar delivery via stream (replaces fragile callback) ---
  final StreamController<AlertEvent> _snackbarController =
      StreamController<AlertEvent>.broadcast();
  Stream<AlertEvent> get snackbarEvents => _snackbarController.stream;

  // --- App lifecycle ---
  bool _appInForeground = true;

  // --- Overlay suppression ---
  final Set<AlertSubsystem> _activeOverlays = {};

  // --- Active alerts (what's currently firing) ---
  final Map<String, AlertEvent> _activeAlerts = {};
  List<AlertEvent> get activeAlerts => List.unmodifiable(_activeAlerts.values.toList());
  int get activeAlertCount => _activeAlerts.length;

  // --- Throttle tracking ---
  final Map<String, DateTime> _lastAlertTime = {};

  // --- Crew broadcast tracking (only send once per alert key until acknowledged) ---
  final Set<String> _crewBroadcastSent = {};

  // --- Audio mute ---
  bool _audioMuted = false;
  Timer? _autoUnmuteTimer;
  bool get audioMuted => _audioMuted;

  // --- Snackbar re-show for active unacknowledged alerts ---
  Timer? _reshowTimer;
  static const _reshowInterval = Duration(seconds: 15);

  AlertCoordinator({
    required StorageService storageService,
    required NotificationService notificationService,
    MessagingService? messagingService,
    AlarmAudioPlayer? audioPlayer,
  })  : _storageService = storageService,
        _notificationService = notificationService,
        _messagingService = messagingService,
        _audioPlayer = audioPlayer ?? AlarmAudioPlayer() {
    // Restore mute state from storage
    _audioMuted = _storageService.getAudioMuted();
    if (_audioMuted) _audioPlayer.mute();
  }

  /// The audio player instance for external queries.
  AlarmAudioPlayer get audioPlayer => _audioPlayer;

  // ===== Submit =====

  /// Submit an alert for coordinated delivery.
  ///
  /// The coordinator enforces throttle, master toggle, per-level filters,
  /// overlay suppression, and per-subsystem crew broadcast preferences.
  void submitAlert(AlertEvent event) {
    final key = event.alertKey;
    final now = DateTime.now();

    // --- Throttle ---
    final throttle = event.throttleDuration ?? _defaultThrottle;
    final lastTime = _lastAlertTime[key];
    if (lastTime != null && now.difference(lastTime) < throttle) {
      // Within throttle window — but still allow audio preemption
      // if the new alert has higher severity than what's playing
      if (event.wantsAudio && !_audioMuted) {
        final currentSeverity = _audioPlayer.activeSeverity;
        if (currentSeverity != null && event.severity > currentSeverity) {
          _playAudio(event);
        }
      }
      return;
    }
    _lastAlertTime[key] = now;

    // --- Gate: master toggle + severity level filter ---
    // One check controls all channels. If the level is filtered out,
    // nothing fires — no audio, no snackbar, no notification, no broadcast.
    final level = event.severity.filterLevel;
    final masterOn = _storageService.getNotificationsEnabled();
    final inAppAllowed = _storageService.getInAppNotificationFilter(level);
    final systemAllowed = _storageService.getSystemNotificationFilter(level);

    if (!masterOn || (!inAppAllowed && !systemAllowed)) return;

    // --- Track as active alert (only if it passed the gate) ---
    _activeAlerts[key] = event;
    _startReshowTimer();
    _safeNotify();

    // System notification
    if (event.wantsSystemNotification && systemAllowed) {
      _notificationService.showAlarmNotification(
        title: event.title,
        body: event.body,
        alarmId: event.alarmId,
        alarmSource: event.alarmSource,
      );
    }

    // In-app snackbar (via stream)
    if (event.wantsInAppSnackbar && inAppAllowed && _appInForeground &&
        !_activeOverlays.contains(event.subsystem)) {
      _snackbarController.add(event);
    }

    // Audio — tied to same gate, plus mute check
    if (event.wantsAudio && !_audioMuted) {
      _playAudio(event);
    }

    // Crew broadcast — only once per alert key until acknowledged
    final messaging = _messagingService;
    if (event.wantsCrewBroadcast && messaging != null &&
        !_crewBroadcastSent.contains(key) &&
        _getCrewBroadcastAllowed(event)) {
      _crewBroadcastSent.add(key);
      final stableId = event.alarmId != null
          ? 'alert-${event.subsystem.name}-${event.alarmId}'
          : 'alert-${event.subsystem.name}';
      messaging.sendAlert(
        event.crewMessage ?? event.body,
        alertId: stableId,
      );
    }
  }

  void _playAudio(AlertEvent event) {
    final assetPath = AlarmAudioPlayer.alarmSounds[event.alarmSound] ??
        AlarmAudioPlayer.alarmSounds['foghorn'] ?? 'sounds/alarm_foghorn.mp3';
    _audioPlayer.play(
      assetPath: assetPath,
      severity: event.severity,
      source: event.subsystem.name,
    );
  }

  // ===== Crew broadcast filtering =====

  bool _getCrewBroadcastAllowed(AlertEvent event) {
    if (event.subsystem == AlertSubsystem.crewMessage) {
      // Crew messages use their own dedicated toggles
      final isAlert = event.severity >= AlertSeverity.warn;
      return isAlert
          ? _storageService.getCrewAlertNotificationsEnabled()
          : _storageService.getCrewNotificationsEnabled();
    }
    return _storageService.getCrewBroadcastEnabled(event.subsystem.name);
  }

  // ===== Acknowledge / Resolve =====

  /// Acknowledge an alarm: "I see it, stop the noise."
  /// Alert stays active — snackbar will re-show. Only resolveAlert clears it.
  void acknowledgeAlarm(AlertSubsystem subsystem, {String? alarmId}) {
    _audioPlayer.stop(source: subsystem.name);
    if (alarmId != null) {
      _notificationService.cancelAlarmNotification(alarmId);
    }
  }

  /// Resolve an alert: condition is over (e.g., vessel moved away).
  /// Removes from active alerts and stops everything.
  void resolveAlert(AlertSubsystem subsystem, {String? alarmId}) {
    _audioPlayer.stop(source: subsystem.name);
    if (alarmId != null) {
      _notificationService.cancelAlarmNotification(alarmId);
    }
    final key = '${subsystem.name}:${alarmId ?? 'default'}';
    _activeAlerts.remove(key);
    _crewBroadcastSent.remove(key);
    _activeOverlays.remove(subsystem);
    _stopReshowIfEmpty();
    _safeNotify();
  }

  /// Clear all active alerts for a subsystem (e.g., on disconnect).
  void clearSubsystem(AlertSubsystem subsystem) {
    _audioPlayer.stop(source: subsystem.name);
    _activeAlerts.removeWhere((key, _) => key.startsWith('${subsystem.name}:'));
    _crewBroadcastSent.removeWhere((key) => key.startsWith('${subsystem.name}:'));
    _activeOverlays.remove(subsystem);
    _stopReshowIfEmpty();
    _safeNotify();
  }

  // ===== Audio mute =====

  /// Mute all audio. Stops current playback, suppresses future audio.
  /// Auto-unmutes after [autoUnmute] duration (default 5 min) for safety.
  void muteAudio({Duration autoUnmute = _defaultAutoUnmute}) {
    _audioMuted = true;
    _audioPlayer.mute();
    _storageService.saveAudioMuted(true);
    _safeNotify();

    _autoUnmuteTimer?.cancel();
    _autoUnmuteTimer = Timer(autoUnmute, () {
      unmuteAudio();
    });
  }

  /// Unmute audio. Next alert with wantsAudio will play.
  void unmuteAudio() {
    _autoUnmuteTimer?.cancel();
    _autoUnmuteTimer = null;
    _audioMuted = false;
    _audioPlayer.unmute();
    _storageService.saveAudioMuted(false);
    _safeNotify();
  }

  // ===== App lifecycle =====

  void setAppInForeground(bool foreground) {
    _appInForeground = foreground;
  }

  // ===== Overlay suppression =====

  void setOverlayActive(AlertSubsystem subsystem, bool active) {
    if (active) {
      _activeOverlays.add(subsystem);
    } else {
      _activeOverlays.remove(subsystem);
    }
  }

  // ===== Snackbar re-show =====

  void _startReshowTimer() {
    if (_reshowTimer != null) return; // already running
    _reshowTimer = Timer.periodic(_reshowInterval, (_) {
      if (_activeAlerts.isEmpty) {
        _stopReshowIfEmpty();
        return;
      }
      // Re-emit active alerts that still pass the filter
      if (_appInForeground && _storageService.getNotificationsEnabled()) {
        for (final event in _activeAlerts.values) {
          final lvl = event.severity.filterLevel;
          if (event.wantsInAppSnackbar &&
              _storageService.getInAppNotificationFilter(lvl) &&
              !_activeOverlays.contains(event.subsystem)) {
            _snackbarController.add(event);
          }
        }
      }
    });
  }

  void _stopReshowIfEmpty() {
    if (_activeAlerts.isEmpty) {
      _reshowTimer?.cancel();
      _reshowTimer = null;
    }
  }

  // ===== Safe notify =====

  /// Notify listeners safely — defers if called during build phase.
  /// Notify listeners after the current frame to avoid build-phase conflicts.
  void _safeNotify() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  // ===== Cleanup =====

  @override
  void dispose() {
    _autoUnmuteTimer?.cancel();
    _reshowTimer?.cancel();
    _snackbarController.close();
    _audioPlayer.dispose();
    super.dispose();
  }
}
