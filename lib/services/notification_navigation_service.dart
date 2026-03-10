import 'package:flutter/widgets.dart';
import '../models/notification_payload.dart';
import 'dashboard_service.dart';

/// Maps notification types/keys to dashboard tool types
/// and provides navigation callbacks for tap-to-navigate.
class NotificationNavigationService {
  final DashboardService _dashboardService;

  NotificationNavigationService(this._dashboardService);

  /// Notification key prefix → candidate tool type IDs (checked in order).
  static const Map<String, List<String>> _keyPrefixMapping = {
    'weather.nws': ['weather_alerts'],
    'navigation.anchor': ['anchor_alarm'],
    'navigation': ['compass', 'wind_compass', 'autopilot', 'position_display'],
    'propulsion': ['radial_gauge', 'linear_gauge'],
    'electrical': ['victron_flow', 'radial_gauge', 'linear_gauge'],
    'environment': ['radial_gauge', 'linear_gauge', 'weatherflow_forecast'],
    'tanks': ['tanks'],
    'steering': ['autopilot', 'autopilot_v2', 'autopilot_simple'],
  };

  /// Non-SignalK notification type → candidate tool type IDs.
  static const Map<String, List<String>> _typeMapping = {
    'crew_message': ['crew_messages'],
    'intercom': ['intercom'],
    'alarm': ['clock_alarm'],
  };

  /// Get navigation info for a notification payload.
  /// Returns (navigate callback, screenName) or null if no matching widget on dashboard.
  (VoidCallback navigate, String screenName)? getNavigation(
      NotificationPayload payload) {
    final candidates = _getCandidateToolTypes(payload);
    if (candidates.isEmpty) return null;

    for (final toolTypeId in candidates) {
      final result = _dashboardService.findScreenWithToolType(toolTypeId);
      if (result != null) {
        final (index, screenName) = result;
        return (
          () => _dashboardService.setActiveScreen(index),
          screenName,
        );
      }
    }
    return null;
  }

  /// Resolve candidate tool type IDs from the payload.
  List<String> _getCandidateToolTypes(NotificationPayload payload) {
    // Direct toolTypeId override takes priority
    if (payload.toolTypeId != null) {
      return [payload.toolTypeId!];
    }

    // Check type-based mapping for non-SignalK types
    if (payload.type != 'signalk') {
      return _typeMapping[payload.type] ?? [];
    }

    // SignalK notifications: match by key prefix
    final key = payload.notificationKey;
    if (key == null) return [];

    for (final entry in _keyPrefixMapping.entries) {
      if (key.startsWith(entry.key)) {
        return entry.value;
      }
    }
    return [];
  }
}
