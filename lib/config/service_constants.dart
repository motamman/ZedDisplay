/// Centralized service-layer constants (network timeouts, retry backoffs,
/// debounce/throttle intervals).
///
/// UI-facing durations (animation curves, snackbar lifetimes) live in
/// [UIConstants] — keep the two separated so service timing can be tuned
/// without re-flowing UI polish, and vice-versa.
library;

class ServiceConstants {
  ServiceConstants._();

  // --------------------------------------------------------------
  // HTTP timeouts
  // --------------------------------------------------------------

  /// Default REST timeout for most SignalK and auxiliary endpoints.
  /// Raised from 3s historically to cope with busy servers.
  static const Duration httpTimeout = Duration(seconds: 10);

  /// Shorter timeout for lightweight endpoints (self-identity, liveness
  /// pings) where a fast failure is preferable to blocking startup.
  static const Duration shortHttpTimeout = Duration(seconds: 5);

  /// Longer timeout for endpoints that are known to be slow on busy
  /// servers (e.g. large REST payloads).
  static const Duration longHttpTimeout = Duration(seconds: 20);

  /// Longest timeout reserved for the heaviest endpoints.
  static const Duration veryLongHttpTimeout = Duration(seconds: 30);

  // --------------------------------------------------------------
  // Debounce / throttle
  // --------------------------------------------------------------

  /// Short debounce — used for rapid user input (e.g. haptic-paced slider).
  static const Duration debounceShort = Duration(milliseconds: 150);

  /// Medium debounce — typical keyboard / gesture debounce window.
  static const Duration debounceMedium = Duration(milliseconds: 300);

  /// Long debounce — used for writes that might coalesce (cache flush, PUT).
  static const Duration debounceLong = Duration(milliseconds: 500);

  // --------------------------------------------------------------
  // UX delays
  // --------------------------------------------------------------

  /// Tiny delay for frame scheduling (100ms).
  static const Duration delayShort = Duration(milliseconds: 100);

  /// Short UX delay (1 second) — e.g. before retrying a transient failure.
  static const Duration delayMedium = Duration(seconds: 1);

  /// Standard delay used for optimistic-update windows (2 seconds).
  static const Duration delayLong = Duration(seconds: 2);

  /// Long UX delay (3 seconds) — e.g. error banner auto-dismiss.
  static const Duration delayVeryLong = Duration(seconds: 3);
}
