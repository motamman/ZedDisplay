/// String utility extensions for ZedDisplay
library;

/// Extension methods for String manipulation
extension StringExtensions on String {
  /// Converts a SignalK path to a human-readable label
  ///
  /// Takes the last segment of a dot-separated path and converts
  /// camelCase to Title Case with spaces.
  ///
  /// Examples:
  /// - "navigation.speedOverGround" -> "Speed Over Ground"
  /// - "environment.depth.belowTransducer" -> "Below Transducer"
  /// - "electrical.batteries.house.voltage" -> "Voltage"
  String toReadableLabel() {
    final parts = split('.');
    if (parts.isEmpty) return this;

    final lastPart = parts.last;
    final result = lastPart.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)}',
    ).trim();

    return result.isEmpty ? lastPart : result;
  }
}
