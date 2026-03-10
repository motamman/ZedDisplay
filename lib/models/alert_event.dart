/// Severity levels for alerts, ordered from lowest to highest.
enum AlertSeverity implements Comparable<AlertSeverity> {
  nominal,
  normal,
  alert,
  warn,
  alarm,
  emergency;

  @override
  int compareTo(AlertSeverity other) => index.compareTo(other.index);

  bool operator >=(AlertSeverity other) => index >= other.index;
  bool operator >(AlertSeverity other) => index > other.index;
  bool operator <=(AlertSeverity other) => index <= other.index;
  bool operator <(AlertSeverity other) => index < other.index;

  /// Map to the filter level string used by StorageService.
  String get filterLevel => name;
}

/// Alert subsystems that can submit alerts.
enum AlertSubsystem {
  signalk,
  anchorAlarm,
  cpa,
  nwsWeather,
  clockAlarm,
  crewMessage,
  intercom,
}

/// What a subsystem wants delivered. AlertCoordinator enforces filters.
class AlertEvent {
  final AlertSubsystem subsystem;
  final AlertSeverity severity;
  final String title;
  final String body;

  // Channel requests (subsystem says what it WANTS; coordinator filters)
  final bool wantsSystemNotification;
  final bool wantsInAppSnackbar;
  final bool wantsAudio;
  final bool wantsCrewBroadcast;

  // Audio config
  final String? alarmSound; // Key into AlarmAudioPlayer.alarmSounds

  // Notification routing
  final String? alarmId;
  final String? alarmSource; // For tap-to-navigate (e.g., 'anchor_alarm')

  // Crew broadcast (if different from body)
  final String? crewMessage;

  // Subsystem-specific callback data (e.g., CpaVesselAlert for snackbar)
  final dynamic callbackData;

  const AlertEvent({
    required this.subsystem,
    required this.severity,
    required this.title,
    required this.body,
    this.wantsSystemNotification = false,
    this.wantsInAppSnackbar = false,
    this.wantsAudio = false,
    this.wantsCrewBroadcast = false,
    this.alarmSound,
    this.alarmId,
    this.alarmSource,
    this.crewMessage,
    this.callbackData,
  });
}
