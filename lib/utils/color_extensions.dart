/// Color utility extensions for ZedDisplay
library;

import 'package:flutter/material.dart';

/// Extension methods for Color parsing and manipulation
extension ColorParsing on String {
  /// Converts a hex color string to a Color object
  ///
  /// Supports formats:
  /// - "#RRGGBB" (e.g., "#FF5733")
  /// - "RRGGBB" (e.g., "FF5733")
  ///
  /// The alpha channel is always set to FF (fully opaque).
  ///
  /// Returns the provided fallback color if parsing fails.
  ///
  /// Examples:
  /// - "#FF5733".toColor() -> Color(0xFFFF5733)
  /// - "FF5733".toColor() -> Color(0xFFFF5733)
  /// - "invalid".toColor(fallback: Colors.red) -> Colors.red
  Color toColor({Color? fallback}) {
    try {
      final colorString = replaceAll('#', '');
      return Color(int.parse('FF$colorString', radix: 16));
    } catch (e) {
      return fallback ?? Colors.grey;
    }
  }
}
