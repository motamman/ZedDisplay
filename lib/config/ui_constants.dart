/// UI constants for ZedDisplay
library;

import 'package:flutter/material.dart';

/// Centralized UI constants to avoid magic numbers throughout the codebase
class UIConstants {
  // Prevent instantiation
  UIConstants._();

  // Opacity levels
  /// Subtle opacity for text and secondary elements
  static const double subtleOpacity = 0.7;

  /// Medium opacity for disabled or inactive elements
  static const double mediumOpacity = 0.5;

  /// Light opacity for backgrounds and overlays
  static const double lightOpacity = 0.3;

  /// Very light opacity for subtle backgrounds
  static const double veryLightOpacity = 0.2;

  // Polling intervals
  /// Fast polling interval for active controls (5 seconds)
  static const Duration fastPolling = Duration(seconds: 5);

  /// Slow polling interval for background updates (30 seconds)
  static const Duration slowPolling = Duration(seconds: 30);

  /// Fast polling duration for active user interactions
  static const Duration fastPollingDuration = Duration(seconds: 30);

  // Timeouts
  /// Duration after which data is considered stale (30 seconds)
  static const Duration dataStaleTimeout = Duration(seconds: 30);

  /// Window for optimistic updates before reverting (3 seconds)
  static const Duration optimisticUpdateWindow = Duration(seconds: 3);

  // UI spacing
  /// Standard card elevation
  static const double cardElevation = 2.0;

  /// Standard card padding
  static const EdgeInsets cardPadding = EdgeInsets.all(16.0);

  /// Small spacing between elements
  static const double smallSpacing = 8.0;

  /// Medium spacing between elements
  static const double mediumSpacing = 16.0;

  /// Large spacing between elements
  static const double largeSpacing = 24.0;

  // Font sizes
  /// Small font size for secondary text (10pt)
  static const double fontSizeSmall = 10.0;

  /// Regular font size for body text (12pt)
  static const double fontSizeRegular = 12.0;

  /// Medium font size for labels (18pt)
  static const double fontSizeMedium = 18.0;

  /// Large font size for values (24pt)
  static const double fontSizeLarge = 24.0;

  /// Extra large font size for main displays (32pt)
  static const double fontSizeXLarge = 32.0;

  /// Huge font size for primary values (48pt)
  static const double fontSizeHuge = 48.0;

  // Icon sizes
  /// Small icon size (16pt)
  static const double iconSizeSmall = 16.0;

  /// Regular icon size (24pt)
  static const double iconSizeRegular = 24.0;

  /// Large icon size (32pt)
  static const double iconSizeLarge = 32.0;

  // Animation durations
  /// Quick animation (100ms)
  static const Duration animationQuick = Duration(milliseconds: 100);

  /// Normal animation (200ms)
  static const Duration animationNormal = Duration(milliseconds: 200);

  /// Slow animation (300ms)
  static const Duration animationSlow = Duration(milliseconds: 300);

  // SnackBar durations
  /// Short SnackBar duration (1 second)
  static const Duration snackBarShort = Duration(seconds: 1);

  /// Normal SnackBar duration (2 seconds)
  static const Duration snackBarNormal = Duration(seconds: 2);

  /// Long SnackBar duration (3 seconds)
  static const Duration snackBarLong = Duration(seconds: 3);

  // Control tool constants
  /// Progress indicator stroke width
  static const double progressStrokeWidth = 2.0;

  /// Progress indicator size
  static const double progressSize = 16.0;

  /// Slider active track height
  static const double sliderActiveTrackHeight = 6.0;

  /// Slider inactive track height
  static const double sliderInactiveTrackHeight = 6.0;

  /// Slider thumb radius
  static const double sliderThumbRadius = 12.0;

  /// Slider overlay radius
  static const double sliderOverlayRadius = 24.0;

  // Switch/Checkbox scales
  /// Switch scale factor
  static const double switchScale = 1.8;

  /// Checkbox scale factor
  static const double checkboxScale = 2.0;

  // Decimal places defaults
  /// Default decimal places for numeric values
  static const int defaultDecimalPlaces = 1;

  /// Default decimal places for high precision
  static const int highPrecisionDecimalPlaces = 2;

  // Helper methods
  /// Creates a color with the specified opacity level
  static Color withOpacity(Color color, double opacity) {
    return color.withValues(alpha: opacity);
  }

  /// Creates a subtle opacity color
  static Color withSubtleOpacity(Color color) {
    return color.withValues(alpha: subtleOpacity);
  }

  /// Creates a medium opacity color
  static Color withMediumOpacity(Color color) {
    return color.withValues(alpha: mediumOpacity);
  }

  /// Creates a light opacity color
  static Color withLightOpacity(Color color) {
    return color.withValues(alpha: lightOpacity);
  }
}
