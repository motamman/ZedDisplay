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
class AlertCoordinator extends ChangeNotifier {
  final StorageService _storageService;
  final NotificationService _notificationService;
  final MessagingService? _messagingService;
  final AlarmAudioPlayer _audioPlayer;

  /// In-app snackbar callback (set by main.dart).
  void Function(AlertEvent event)? onShowSnackbar;

  /// Whether the app is in the foreground. Snackbars are skipped while backgrounded
  /// to prevent addPostFrameCallback accumulation that causes jank on resume.
  bool _appInForeground = true;

  /// Overlay state — tracks which subsystems have an active overlay.
  /// When a subsystem has an overlay visible, snackbars are suppressed for it.
  final Set<AlertSubsystem> _activeOverlays = {};

  AlertCoordinator({
    required StorageService storageService,
    required NotificationService notificationService,
    MessagingService? messagingService,
    AlarmAudioPlayer? audioPlayer,
  })  : _storageService = storageService,
        _notificationService = notificationService,
        _messagingService = messagingService,
        _audioPlayer = audioPlayer ?? AlarmAudioPlayer();

  /// The audio player instance for external queries.
  AlarmAudioPlayer get audioPlayer => _audioPlayer;

  /// Submit an alert for coordinated delivery.
  ///
  /// The coordinator enforces master toggle, per-level filters, and
  /// per-subsystem crew broadcast preferences.
  void submitAlert(AlertEvent event) {
    final level = event.severity.filterLevel;
    final masterOn = _storageService.getNotificationsEnabled();

    // --- System notification ---
    if (event.wantsSystemNotification && masterOn &&
        _storageService.getSystemNotificationFilter(level)) {
      _notificationService.showAlarmNotification(
        title: event.title,
        body: event.body,
        alarmId: event.alarmId,
        alarmSource: event.alarmSource,
      );
    }

    // --- In-app snackbar ---
    // Suppressed when master is OFF, when subsystem has an overlay visible,
    // or when the app is backgrounded (prevents callback accumulation).
    if (event.wantsInAppSnackbar && masterOn && _appInForeground &&
        _storageService.getInAppNotificationFilter(level) &&
        !_activeOverlays.contains(event.subsystem)) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        onShowSnackbar?.call(event);
      });
    }

    // --- Audio ---
    // Audio always fires regardless of master toggle (safety-critical)
    if (event.wantsAudio) {
      final assetPath = AlarmAudioPlayer.alarmSounds[event.alarmSound] ??
          AlarmAudioPlayer.alarmSounds['foghorn'] ?? 'sounds/alarm_foghorn.mp3';
      _audioPlayer.play(
        assetPath: assetPath,
        severity: event.severity,
        source: event.subsystem.name,
      );
    }

    // --- Crew broadcast ---
    if (event.wantsCrewBroadcast && _messagingService != null) {
      final shouldSend = _getCrewBroadcastAllowed(event);
      if (shouldSend) {
        // Use stable alert ID so repeated alerts overwrite the same server
        // resource instead of accumulating (e.g. alert-cpa-<vesselId>).
        final stableId = event.alarmId != null
            ? 'alert-${event.subsystem.name}-${event.alarmId}'
            : 'alert-${event.subsystem.name}';
        _messagingService.sendAlert(
          event.crewMessage ?? event.body,
          alertId: stableId,
        );
      }
    }
  }

  /// Determine if crew broadcast is allowed for this event.
  bool _getCrewBroadcastAllowed(AlertEvent event) {
    switch (event.subsystem) {
      case AlertSubsystem.crewMessage:
        // Crew messages use their own dedicated toggles
        final isAlert = event.severity >= AlertSeverity.warn;
        return isAlert
            ? _storageService.getCrewAlertNotificationsEnabled()
            : _storageService.getCrewNotificationsEnabled();
      default:
        // Other subsystems: allow crew broadcast by default
        // (per-subsystem prefs can be added to StorageService later)
        return true;
    }
  }

  /// Track app lifecycle — call from didChangeAppLifecycleState.
  void setAppInForeground(bool foreground) {
    _appInForeground = foreground;
  }

  /// Register/unregister overlay state for a subsystem.
  /// When an overlay is active, snackbars are suppressed for that subsystem.
  void setOverlayActive(AlertSubsystem subsystem, bool active) {
    if (active) {
      _activeOverlays.add(subsystem);
    } else {
      _activeOverlays.remove(subsystem);
    }
  }

  /// Acknowledge an alarm: stops audio + cancels system notification.
  void acknowledgeAlarm(AlertSubsystem subsystem, {String? alarmId}) {
    _audioPlayer.stop(source: subsystem.name);
    if (alarmId != null) {
      _notificationService.cancelAlarmNotification(alarmId);
    }
  }

  /// Cancel a specific alert (removes notification from tray).
  void cancelAlert(AlertSubsystem subsystem, {String? alarmId}) {
    if (alarmId != null) {
      _notificationService.cancelAlarmNotification(alarmId);
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}
