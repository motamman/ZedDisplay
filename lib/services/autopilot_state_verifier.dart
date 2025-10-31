import 'dart:async';
import '../services/signalk_service.dart';
import '../models/autopilot_errors.dart';

/// Service to verify autopilot state changes via WebSocket deltas
///
/// This service monitors the WebSocket stream for expected state changes
/// and checks for autopilot error notifications. It provides reliable
/// confirmation that commands were successfully executed.
class AutopilotStateVerifier {
  final SignalKService _signalK;
  final Duration timeout;
  final Duration pollInterval;

  AutopilotStateVerifier(
    this._signalK, {
    this.timeout = const Duration(seconds: 5),
    this.pollInterval = const Duration(milliseconds: 500),
  });

  /// Verify that a SignalK path reaches the expected value
  ///
  /// Returns true if value matches within timeout, false otherwise.
  /// Throws [AutopilotException] if autopilot errors are detected.
  ///
  /// This method uses WebSocket data from the SignalK service to verify
  /// state changes in real-time, avoiding REST polling.
  Future<bool> verifyChange({
    required String path,
    required dynamic expectedValue,
    Duration? customTimeout,
  }) async {
    final endTime = DateTime.now().add(customTimeout ?? timeout);

    while (DateTime.now().isBefore(endTime)) {
      // Get current value from WebSocket cache
      final currentValue = _signalK.getPathValue(path);

      if (_valuesMatch(currentValue, expectedValue)) {
        return true;
      }

      // Check for autopilot error notifications
      final errors = _checkAutopilotErrors();
      if (errors.isNotEmpty) {
        throw AutopilotException(
          'Autopilot rejected command: ${errors.first}',
          type: AutopilotErrorType.commandRejected,
          serverMessage: errors.first,
        );
      }

      await Future.delayed(pollInterval);
    }

    return false;
  }

  /// Check if two values match, with appropriate comparison logic
  bool _valuesMatch(dynamic current, dynamic expected) {
    if (current == null) return false;

    // Handle string comparison (case-insensitive for autopilot states)
    if (expected is String) {
      return current.toString().toLowerCase() == expected.toLowerCase();
    }

    // Handle numeric comparison with tolerance (0.5° for headings)
    if (expected is num && current is num) {
      return (current - expected).abs() < 0.5;
    }

    // Handle boolean comparison
    if (expected is bool && current is bool) {
      return current == expected;
    }

    return current == expected;
  }

  /// Check for recent autopilot error notifications
  List<String> _checkAutopilotErrors() {
    // Get recent notifications from SignalK notification stream
    final notifications = _signalK.getRecentNotifications();

    return notifications
        .where((n) =>
            n.key.contains('steering') &&
            n.key.contains('autopilot') &&
            (n.state == 'alarm' || n.state == 'warn' || n.state == 'alert'))
        .map((n) => n.message)
        .toList();
  }
}
