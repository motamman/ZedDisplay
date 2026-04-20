import 'package:flutter/material.dart';

/// Semantic color palette for ZedDisplay.
///
/// Centralises the hex codes that recur across the codebase for things like
/// modal backgrounds, alarm and warning states, and autopilot engagement.
/// Widgets should reach for these names instead of literal `Color(0xFF...)`
/// so we can retheme (or dark/light switch) in one place later.
class AppColors {
  AppColors._();

  // Surfaces

  /// Standard dark card / bottom sheet / dialog background.
  static const Color cardBackgroundDark = Color(0xFF1E1E2E);

  // Alert severity

  /// Alarm (highest severity visual): bright red used for active alarms.
  static const Color alarmRed = Color(0xFFFF1744);

  /// Emergency / persistent-alarm state: dark red (Material `red.shade900`).
  static const Color alarmDarkRed = Color(0xFFB71C1C);

  /// Warning / caution: orange, used for tank fuel warnings and similar.
  static const Color warningOrange = Color(0xFFFF5722);

  /// Warning / attention: yellow, used for autopilot dodge / standby states.
  static const Color warningYellow = Color(0xFFFFD600);

  // Success & info

  /// Success / engaged: green, used for autopilot engagement indicator.
  static const Color successGreen = Color(0xFF00E676);

  /// Informational / notification: blue (Material `blue.shade700`).
  static const Color infoBlue = Color(0xFF1976D2);
}
