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

  // --- Overlay suppression ---
  final Set<AlertSubsystem> _activeOverlays = {};

  // --- Active alerts (what's currently firing) ---
  final Map<String, AlertEvent> _activeAlerts = {};
  /// Active alerts visible to the UI — excludes temporarily acknowledged ones.
  List<AlertEvent> get activeAlerts {
    final now = DateTime.now();
    return List.unmodifiable(
      _activeAlerts.entries
          .where((e) {
            final ackUntil = _acknowledgedUntil[e.key];
            return ackUntil == null || now.isAfter(ackUntil);
          })
          .map((e) => e.value)
          .toList(),
    );
  }

  int get activeAlertCount => activeAlerts.length;

  // --- Throttle tracking ---
  final Map<String, DateTime> _lastAlertTime = {};

  // --- Crew broadcast tracking (only send once per alert key until acknowledged) ---
  final Set<String> _crewBroadcastSent = {};

  // --- Acknowledged alerts: hidden from panel until expiry, then re-shown ---
  final Map<String, DateTime> _acknowledgedUntil = {};
  Timer? _ackExpiryTimer;
  static const _ackReshowInterval = Duration(seconds: 15);

  // --- Resolve callbacks (subsystems register to hear when their alerts are resolved) ---
  final Map<AlertSubsystem, void Function(String? alarmId)> _resolveCallbacks = {};

  // --- Audio mute ---
  bool _audioMuted = false;
  Timer? _autoUnmuteTimer;
  bool get audioMuted => _audioMuted;



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
    // AlertPanel widget listens to notifyListeners and renders _activeAlerts directly.
    _activeAlerts[key] = event;
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
  /// Row disappears from panel temporarily, re-shows after [_ackReshowInterval]
  /// if the alert is still active. Only resolveAlert clears it permanently.
  void acknowledgeAlarm(AlertSubsystem subsystem, {String? alarmId}) {
    final key = '${subsystem.name}:${alarmId ?? 'default'}';
    _audioPlayer.stop(source: subsystem.name);
    if (alarmId != null) {
      _notificationService.cancelAlarmNotification(alarmId);
    }
    _acknowledgedUntil[key] = DateTime.now().add(_ackReshowInterval);
    _startAckExpiryTimer();
    _safeNotify();
  }

  /// Resolve an alert: condition is over (e.g., vessel moved away) or user dismissed.
  ///
  /// When [internal] is false (default — user action or external trigger),
  /// the subsystem's registered callback fires so it can do its own cleanup
  /// (e.g., CPA sets dismissal cooldown). When [internal] is true (subsystem
  /// initiated the resolve itself), the callback is skipped to prevent loops.
  void resolveAlert(AlertSubsystem subsystem, {String? alarmId, bool internal = false}) {
    final key = '${subsystem.name}:${alarmId ?? 'default'}';
    _audioPlayer.stop(source: subsystem.name);
    if (alarmId != null) {
      _notificationService.cancelAlarmNotification(alarmId);
    }
    _activeAlerts.remove(key);
    _acknowledgedUntil.remove(key);
    _crewBroadcastSent.remove(key);
    _activeOverlays.remove(subsystem);

    _safeNotify();

    if (!internal) {
      _resolveCallbacks[subsystem]?.call(alarmId);
    }
  }

  /// Clear all active alerts for a subsystem (e.g., on disconnect).
  void clearSubsystem(AlertSubsystem subsystem, {bool internal = false}) {
    _audioPlayer.stop(source: subsystem.name);
    final clearedKeys = _activeAlerts.keys
        .where((key) => key.startsWith('${subsystem.name}:'))
        .toList();
    _activeAlerts.removeWhere((key, _) => key.startsWith('${subsystem.name}:'));
    _crewBroadcastSent.removeWhere((key) => key.startsWith('${subsystem.name}:'));
    _activeOverlays.remove(subsystem);

    _safeNotify();

    if (!internal) {
      for (final key in clearedKeys) {
        final alarmId = key.contains(':') ? key.split(':').skip(1).join(':') : null;
        _resolveCallbacks[subsystem]?.call(alarmId == 'default' ? null : alarmId);
      }
    }
  }

  // ===== Resolve callbacks =====

  /// Register a callback that fires when an alert for this subsystem is resolved
  /// externally (user dismiss, timeout, etc.). Not called on internal resolves.
  void registerResolveCallback(AlertSubsystem subsystem, void Function(String? alarmId) callback) {
    _resolveCallbacks[subsystem] = callback;
  }

  void unregisterResolveCallback(AlertSubsystem subsystem) {
    _resolveCallbacks.remove(subsystem);
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


  // ===== Overlay suppression =====

  void setOverlayActive(AlertSubsystem subsystem, bool active) {
    if (active) {
      _activeOverlays.add(subsystem);
    } else {
      _activeOverlays.remove(subsystem);
    }
  }

  // ===== ACK expiry timer =====

  /// Periodically checks if any acknowledged alerts have expired and should re-show.
  void _startAckExpiryTimer() {
    if (_ackExpiryTimer != null) return;
    _ackExpiryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_acknowledgedUntil.isEmpty) {
        _ackExpiryTimer?.cancel();
        _ackExpiryTimer = null;
        return;
      }
      final now = DateTime.now();
      final expired = _acknowledgedUntil.entries
          .where((e) => now.isAfter(e.value))
          .map((e) => e.key)
          .toList();
      if (expired.isNotEmpty) {
        for (final key in expired) {
          _acknowledgedUntil.remove(key);
        }
        _safeNotify(); // Panel rebuilds, expired ACKs re-appear
      }
    });
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
    _ackExpiryTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}
