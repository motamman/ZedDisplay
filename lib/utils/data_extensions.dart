/// Data utility extensions for ZedDisplay
library;

import '../models/signalk_data.dart';

/// Extension methods for SignalKDataPoint manipulation
extension SignalKDataPointExtensions on SignalKDataPoint? {
  /// Converts the data point value to a boolean
  ///
  /// Handles multiple value types:
  /// - bool: returns as-is
  /// - num: returns true if non-zero
  /// - String: returns true if "true" or "1" (case-insensitive)
  /// - null: returns false
  ///
  /// Examples:
  /// - dataPoint with value true -> true
  /// - dataPoint with value 1 -> true
  /// - dataPoint with value 0 -> false
  /// - dataPoint with value "true" -> true
  /// - dataPoint with value "false" -> false
  /// - null dataPoint -> false
  bool toBool() {
    final value = this?.value;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final str = value.toLowerCase();
      return str == 'true' || str == '1';
    }
    return false;
  }
}
