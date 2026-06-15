import 'package:flutter/widgets.dart';
import '../models/notification_payload.dart';
import 'dashboard_service.dart';

/// Maps notification types/keys to dashboard tool types
/// and provides navigation callbacks for tap-to-navigate.
class NotificationNavigationService {
  final DashboardService _dashboardService;

  NotificationNavigationService(this._dashboardService);

  /// Non-SignalK notification type → tool type. These are app-internal
  /// notification types with no SignalK path to match on, so they map to their
  /// one obvious home widget. (SignalK notifications are NOT listed here — they
  /// route by path; see getNavigation.)
  static const Map<String, List<String>> _typeMapping = {
    'crew_message': ['crew_messages'],
    'intercom': ['intercom'],
    'alarm': ['clock_alarm'],
  };

  /// Get navigation info for a notification payload.
  /// Returns (navigate callback, screenName), or null when nothing relevant is
  /// placed — in which case VIEW is hidden rather than navigating somewhere
  /// unrelated.
  (VoidCallback navigate, String screenName)? getNavigation(
      NotificationPayload payload) {
    // 1. Explicit tool-type override on the payload wins.
    if (payload.toolTypeId != null) return _navByType(payload.toolTypeId!);

    // 2. Non-SignalK app notifications (crew/intercom/alarm) → their widget.
    if (payload.type != 'signalk') {
      for (final toolTypeId in _typeMapping[payload.type] ?? const <String>[]) {
        final nav = _navByType(toolTypeId);
        if (nav != null) return nav;
      }
      return null;
    }

    // 3. SignalK notifications route by PATH: go to the widget the user bound
    //    to the alerting path. No category table — the path is the binding.
    final key = payload.notificationKey;
    if (key == null) return null;
    final byPath = _dashboardService.findScreenWithToolPath(key);
    if (byPath != null) {
      return (() => _dashboardService.setActiveScreen(byPath.$1), byPath.$2);
    }
    return null;
  }

  /// Resolve a screen containing [toolTypeId] into a navigate callback.
  (VoidCallback navigate, String screenName)? _navByType(String toolTypeId) {
    final result = _dashboardService.findScreenWithToolType(toolTypeId);
    if (result == null) return null;
    return (() => _dashboardService.setActiveScreen(result.$1), result.$2);
  }
}
