/// Error types for autopilot operations
enum AutopilotErrorType {
  networkError,           // Connection lost
  authenticationError,    // Invalid token
  commandRejected,        // Autopilot safety interlock
  invalidModeTransition,  // Cannot switch from X to Y
  timeout,                // Command timeout
  serverError,            // 5xx response
  notConfigured,          // Widget not set up
  v2NotAvailable,         // V2 API requested but not available
  instanceNotFound,       // V2 instance doesn't exist
}

/// Custom exception for autopilot operations
class AutopilotException implements Exception {
  final String message;
  final AutopilotErrorType type;
  final int? statusCode;
  final String? serverMessage;
  final bool retryable;

  AutopilotException(
    this.message, {
    required this.type,
    this.statusCode,
    this.serverMessage,
    bool? retryable,
  }) : retryable = retryable ?? _isRetryable(type);

  static bool _isRetryable(AutopilotErrorType type) {
    return type == AutopilotErrorType.networkError ||
           type == AutopilotErrorType.timeout ||
           type == AutopilotErrorType.serverError;
  }

  /// Get user-friendly error message
  String getUserFriendlyMessage() {
    switch (type) {
      case AutopilotErrorType.networkError:
        return 'Network connection lost. Check your connection and try again.';

      case AutopilotErrorType.authenticationError:
        return 'Authentication failed. Please log in again.';

      case AutopilotErrorType.commandRejected:
        return serverMessage ??
               'Autopilot rejected the command. Check safety interlocks.';

      case AutopilotErrorType.invalidModeTransition:
        return 'Invalid mode change. Check current autopilot state.';

      case AutopilotErrorType.timeout:
        return 'Command timed out. Autopilot may not be responding.';

      case AutopilotErrorType.serverError:
        return 'Server error (${statusCode ?? "unknown"}). Try again later.';

      case AutopilotErrorType.notConfigured:
        return 'Autopilot not configured. Open settings to configure.';

      case AutopilotErrorType.v2NotAvailable:
        return 'V2 API not available. Your SignalK server may need an update.';

      case AutopilotErrorType.instanceNotFound:
        return 'Autopilot instance not found. Reconfigure the widget.';
    }
  }

  @override
  String toString() => 'AutopilotException: $message (type: $type)';
}
