/// Shared utility for NWS alert active-status checks.
///
/// Used by both `NWSAlert.isActive` (widget) and `_NotificationManager`
/// (service) to avoid circular imports.
class NWSAlertUtils {
  NWSAlertUtils._();

  /// Returns `true` when the alert should still be considered active.
  ///
  /// An alert is inactive when:
  /// - [expires] is in the past, or
  /// - [ends] is in the past, or
  /// - [urgency] equals `'past'` (case-insensitive).
  ///
  /// If all parameters are null the alert is assumed active (safe default).
  static bool isAlertActive({
    DateTime? expires,
    DateTime? ends,
    String? urgency,
  }) {
    final now = DateTime.now();
    if (expires != null && now.isAfter(expires)) return false;
    if (ends != null && now.isAfter(ends)) return false;
    if (urgency != null && urgency.toLowerCase() == 'past') return false;
    return true;
  }
}
