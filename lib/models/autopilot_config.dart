/// Configuration options for autopilot tools
///
/// Controls optional features like route calculations which can impact
/// server performance.
class AutopilotConfig {
  /// Enable route navigation calculations
  ///
  /// When enabled, subscribes to route calculation paths like:
  /// - navigation.course.calcValues.bearingMagnetic/True
  /// - navigation.courseGreatCircle.nextPoint.position
  /// - navigation.course.calcValues.distance/timeToGo/ETA
  ///
  /// **WARNING**: Route calculations can be CPU-intensive on some SignalK servers.
  /// Only enable if your server handles these calculations efficiently.
  final bool enableRouteCalculations;

  /// Only show cross-track error when vessel is near waypoint (< 10nm)
  ///
  /// Reduces clutter when far from destination.
  final bool onlyShowXTEWhenNear;

  /// Countdown duration for tack/gybe/advance waypoint confirmations
  final int confirmationCountdownSeconds;

  /// Use true heading instead of magnetic heading
  final bool useTrueHeading;

  /// Invert rudder indicator direction
  final bool invertRudderIndicator;

  const AutopilotConfig({
    this.enableRouteCalculations = false, // Default OFF for performance
    this.onlyShowXTEWhenNear = true,
    this.confirmationCountdownSeconds = 5,
    this.useTrueHeading = false,
    this.invertRudderIndicator = false,
  });

  AutopilotConfig copyWith({
    bool? enableRouteCalculations,
    bool? onlyShowXTEWhenNear,
    int? confirmationCountdownSeconds,
    bool? useTrueHeading,
    bool? invertRudderIndicator,
  }) {
    return AutopilotConfig(
      enableRouteCalculations: enableRouteCalculations ?? this.enableRouteCalculations,
      onlyShowXTEWhenNear: onlyShowXTEWhenNear ?? this.onlyShowXTEWhenNear,
      confirmationCountdownSeconds: confirmationCountdownSeconds ?? this.confirmationCountdownSeconds,
      useTrueHeading: useTrueHeading ?? this.useTrueHeading,
      invertRudderIndicator: invertRudderIndicator ?? this.invertRudderIndicator,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enableRouteCalculations': enableRouteCalculations,
      'onlyShowXTEWhenNear': onlyShowXTEWhenNear,
      'confirmationCountdownSeconds': confirmationCountdownSeconds,
      'useTrueHeading': useTrueHeading,
      'invertRudderIndicator': invertRudderIndicator,
    };
  }

  factory AutopilotConfig.fromJson(Map<String, dynamic> json) {
    return AutopilotConfig(
      enableRouteCalculations: json['enableRouteCalculations'] as bool? ?? false,
      onlyShowXTEWhenNear: json['onlyShowXTEWhenNear'] as bool? ?? true,
      confirmationCountdownSeconds: json['confirmationCountdownSeconds'] as int? ?? 5,
      useTrueHeading: json['useTrueHeading'] as bool? ?? false,
      invertRudderIndicator: json['invertRudderIndicator'] as bool? ?? false,
    );
  }
}
