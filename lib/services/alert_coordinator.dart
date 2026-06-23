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
  /// Active alerts visible to the UI.
  ///
  /// Invariant: anything that can make noise is always shown. An audible
  /// (`wantsAudio`) alert is safety-critical and is included whenever it is
  /// active and not within its acknowledge window — it CANNOT be hidden by
  /// overlay ownership or the per-severity in-app filter. This is the same
  /// "audible-live" set the audio projection plays (see [_isAudibleLive] /
  /// [_reconcileAudio]), so a sounding alarm always has a reachable control and
  /// audio can never diverge from the panel.
  ///
  /// Non-audible (informational) alerts may still be hidden by overlay
  /// suppression or a severity level the user turned off — there is no
  /// dead-zone risk because they make no sound.
  List<AlertEvent> get activeAlerts {
    final now = DateTime.now();
    return List.unmodifiable(
      _activeAlerts.entries
          .where((e) {
            final ackUntil = _acknowledgedUntil[e.key];
            return ackUntil == null || now.isAfter(ackUntil);
          })
          .where((e) {
            // Audible alerts always show — bypass overlay + severity filter.
            if (e.value.wantsAudio) return true;
            if (_activeOverlays.contains(e.value.subsystem)) return false;
            return _storageService
                .getInAppNotificationFilter(e.value.severity.filterLevel);
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
    // Restore mute state from storage. Audio is a projection of the active
    // alert set (see _reconcileAudio); mute is enforced there, not on the
    // player, which is now a dumb sink.
    _audioMuted = _storageService.getAudioMuted();
    // Re-render the panel when notification settings change (e.g. the user
    // toggles an in-app level filter), so activeAlerts re-filters live instead
    // of only on the next alert event.
    _storageService.addListener(_onStorageChanged);
  }

  void _onStorageChanged() => _safeNotify();

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
      // Within throttle window — still refresh the active alert so the panel
      // reflects the latest state, then reconcile audio (the projection plays
      // the highest-severity audible-live alert).
      _activeAlerts[key] = event;
      _reconcileAudio();
      _safeNotify();
      return;
    }
    _lastAlertTime[key] = now;

    // --- Always track as active alert ---
    // AlertPanel renders _activeAlerts via the activeAlerts getter. A fresh
    // submission clears any prior acknowledge window for this key, so an
    // escalation or re-fire un-snoozes it.
    _activeAlerts[key] = event;
    _acknowledgedUntil.remove(key);
    _safeNotify();

    // --- Audio is a pure projection of the active set: reconcile, never poke ---
    _reconcileAudio();

    // --- Gate: master toggle + severity level filter ---
    // Controls system notifications and crew broadcast only.
    // Does NOT gate _activeAlerts (panel) or audio.
    final level = event.severity.filterLevel;
    final masterOn = _storageService.getNotificationsEnabled();
    final inAppAllowed = _storageService.getInAppNotificationFilter(level);
    final systemAllowed = _storageService.getSystemNotificationFilter(level);

    // Audible (safety-critical) alerts bypass the per-severity system filter so
    // the OS notification stays consistent with the always-shown panel row: no
    // OS alarm sound without a corresponding panel row, and vice versa.
    final systemOk = systemAllowed || event.wantsAudio;

    if (!masterOn || (!inAppAllowed && !systemOk)) return;

    // System notification
    if (event.wantsSystemNotification && systemOk) {
      _notificationService.showAlarmNotification(
        title: event.title,
        body: event.body,
        alarmId: event.alarmId,
        alarmSource: event.alarmSource,
      );
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

  /// Whether [event] (stored under [key]) is currently eligible to sound:
  /// active, audio-requested, and not inside its acknowledge window. This is
  /// the single predicate shared by the audio projection and the
  /// [activeAlerts] getter, so the two can never diverge.
  bool _isAudibleLive(String key, AlertEvent event, DateTime now) {
    if (!event.wantsAudio) return false;
    final ackUntil = _acknowledgedUntil[key];
    if (ackUntil != null && now.isBefore(ackUntil)) return false;
    return true;
  }

  /// Audio is a pure projection of the active alert set. Computes the desired
  /// audio target — the single highest-severity audible-live alert, or none
  /// when muted / nothing audible — and hands it to the sink with one
  /// synchronous, idempotent [AlarmAudioPlayer.setTarget] call. Nothing
  /// imperative crosses the boundary, so calling this in a burst just rewrites
  /// the same target (the sink owns exactly one player). Acknowledging or
  /// resolving the loudest alarm makes the target move to the next still-active
  /// one — no stomping, no silent-but-active alarms, no pile-up.
  void _reconcileAudio() {
    if (_audioMuted) {
      _audioPlayer.setTarget(null);
      return;
    }
    final now = DateTime.now();
    String? targetKey;
    AlertEvent? target;
    for (final entry in _activeAlerts.entries) {
      if (!_isAudibleLive(entry.key, entry.value, now)) continue;
      if (target == null || entry.value.severity > target.severity) {
        target = entry.value;
        targetKey = entry.key;
      }
    }
    if (target == null || targetKey == null) {
      _audioPlayer.setTarget(null);
      return;
    }
    final assetPath = AlarmAudioPlayer.alarmSounds[target.alarmSound] ??
        AlarmAudioPlayer.alarmSounds['foghorn'] ??
        'sounds/alarm_foghorn.mp3';
    _audioPlayer.setTarget(targetKey, assetPath);
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
    if (alarmId != null) {
      _notificationService.cancelAlarmNotification(alarmId);
    }
    _acknowledgedUntil[key] = DateTime.now().add(_ackReshowInterval);
    _startAckExpiryTimer();
    // Audio is a projection: the now-acked alert is no longer audible-live, so
    // reconcile silences it (or switches to the next still-active alarm).
    _reconcileAudio();
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
    if (alarmId != null) {
      _notificationService.cancelAlarmNotification(alarmId);
    }
    _activeAlerts.remove(key);
    _acknowledgedUntil.remove(key);
    _crewBroadcastSent.remove(key);
    _activeOverlays.remove(subsystem);

    // Removed from the active set → reconcile silences it (or moves to the next
    // still-active alarm).
    _reconcileAudio();
    _safeNotify();

    if (!internal) {
      _resolveCallbacks[subsystem]?.call(alarmId);
    }
  }

  /// Acknowledge every active alert (silence audio + clear system
  /// notifications, leave the rows up). Snapshot first — acknowledgeAlarm
  /// mutates coordinator state.
  void acknowledgeAll() {
    // Use the filtered `activeAlerts` (the same set shown in the panel) so we
    // never act on alerts the user can't currently see. Snapshot first.
    for (final event in activeAlerts.toList()) {
      acknowledgeAlarm(event.subsystem, alarmId: event.alarmId);
    }
  }

  /// Dismiss (resolve) EVERY active alert — including ones currently hidden
  /// from the panel by an in-app severity filter, an acknowledge window, or an
  /// active overlay. Iterates the raw store (not the filtered `activeAlerts`
  /// getter) so "DISMISS ALL" truly clears everything and can't leave stuck,
  /// invisible alerts behind. Snapshot first — resolveAlert mutates the map.
  void dismissAll() {
    for (final event in _activeAlerts.values.toList()) {
      resolveAlert(event.subsystem, alarmId: event.alarmId);
    }
  }

  /// Clear all active alerts for a subsystem (e.g., on disconnect).
  void clearSubsystem(AlertSubsystem subsystem, {bool internal = false}) {
    final clearedKeys = _activeAlerts.keys
        .where((key) => key.startsWith('${subsystem.name}:'))
        .toList();
    _activeAlerts.removeWhere((key, _) => key.startsWith('${subsystem.name}:'));
    _crewBroadcastSent.removeWhere((key) => key.startsWith('${subsystem.name}:'));
    _activeOverlays.remove(subsystem);

    _reconcileAudio();
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
    _storageService.saveAudioMuted(true);
    _reconcileAudio(); // muted → reconcile stops playback
    _safeNotify();

    _autoUnmuteTimer?.cancel();
    _autoUnmuteTimer = Timer(autoUnmute, () {
      unmuteAudio();
    });
  }

  /// Unmute audio. Reconcile resumes the highest-severity audible-live alarm.
  void unmuteAudio() {
    _autoUnmuteTimer?.cancel();
    _autoUnmuteTimer = null;
    _audioMuted = false;
    _storageService.saveAudioMuted(false);
    _reconcileAudio(); // unmuted → reconcile resumes if still active
    _safeNotify();
  }


  // ===== Overlay suppression =====

  void setOverlayActive(AlertSubsystem subsystem, bool active) {
    final changed = active
        ? _activeOverlays.add(subsystem)
        : _activeOverlays.remove(subsystem);
    if (changed) _safeNotify();
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
        // Ack windows expired → those alerts are audible-live again; reconcile
        // resumes audio for any still-active alarm.
        _reconcileAudio();
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
    _storageService.removeListener(_onStorageChanged);
    _autoUnmuteTimer?.cancel();
    _ackExpiryTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}
