import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'signalk_service.dart';
import 'autopilot_command_service.dart';

/// Event emitted when the vessel enters a waypoint arrival zone.
class RouteArrivalEvent {
  /// Current waypoint index (0-based).
  final int pointIndex;

  /// Total waypoints in the route.
  final int pointTotal;

  /// True if this is the last waypoint on the route.
  bool get isLastWaypoint =>
      pointTotal > 0 && pointIndex >= 0 && pointIndex >= pointTotal - 1;

  /// The notification key that triggered this event.
  final String trigger;

  RouteArrivalEvent({
    required this.pointIndex,
    required this.pointTotal,
    required this.trigger,
  });
}

/// Monitors SignalK notifications for waypoint arrival and provides
/// auto-advance capability.
///
/// Shared between FindHome route mode and the autopilot tool.
/// The widget is responsible for showing a countdown UI and calling
/// [advance] or [endRoute] based on user action.
///
/// Usage:
/// ```dart
/// final monitor = RouteArrivalMonitor(signalKService: skService);
/// monitor.arrivalStream.listen((event) {
///   if (event.isLastWaypoint) { /* show end-route dialog */ }
///   else { /* show advance countdown */ }
/// });
/// ```
class RouteArrivalMonitor {
  final SignalKService _signalKService;
  AutopilotCommandService? _apService;

  StreamSubscription<SignalKNotification>? _notificationSub;
  final _arrivalController = StreamController<RouteArrivalEvent>.broadcast();

  /// Whether to listen for arrival notifications.
  bool _active = false;

  RouteArrivalMonitor({required SignalKService signalKService})
      : _signalKService = signalKService;

  /// Stream of arrival events. Widgets subscribe to show countdown UI.
  Stream<RouteArrivalEvent> get arrivalStream => _arrivalController.stream;

  /// Set the autopilot command service (for advance calls).
  set apService(AutopilotCommandService? service) => _apService = service;

  /// Start monitoring arrival notifications.
  void start() {
    if (_active) return;
    _active = true;
    _notificationSub = _signalKService.notificationStream.listen(_onNotification);
    if (kDebugMode) print('RouteArrivalMonitor: started');
  }

  /// Stop monitoring.
  void stop() {
    _active = false;
    _notificationSub?.cancel();
    _notificationSub = null;
    if (kDebugMode) print('RouteArrivalMonitor: stopped');
  }

  void _onNotification(SignalKNotification n) {
    if (!_active) return;
    // Match arrival circle or perpendicular passed notifications
    if (n.key.contains('arrivalCircleEntered') ||
        n.key.contains('perpendicularPassed')) {
      // Only fire on active alerts, not clears (state 'normal')
      if (n.state == 'normal') return;
      _fetchRouteStateAndEmit(n.key);
    }
  }

  Future<void> _fetchRouteStateAndEmit(String trigger) async {
    try {
      final baseUrl = _signalKService.httpBaseUrl;
      final token = _signalKService.authToken?.token;
      final headers = <String, String>{
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final response = await http.get(
        Uri.parse('$baseUrl/signalk/v2/api/vessels/self/navigation/course'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        if (kDebugMode) print('RouteArrivalMonitor: course API returned ${response.statusCode}');
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final activeRoute = data['activeRoute'] as Map<String, dynamic>?;
      if (activeRoute == null) return;

      final pointIndex = activeRoute['pointIndex'] as int? ?? 0;
      final pointTotal = activeRoute['pointTotal'] as int? ?? 0;

      _arrivalController.add(RouteArrivalEvent(
        pointIndex: pointIndex,
        pointTotal: pointTotal,
        trigger: trigger,
      ));
    } catch (e) {
      if (kDebugMode) print('RouteArrivalMonitor: error fetching route state: $e');
    }
  }

  /// Advance to the next waypoint. Throws on failure.
  Future<void> advance() async {
    if (_apService == null) {
      throw StateError('No AutopilotCommandService set');
    }
    await _apService!.advanceWaypoint();
  }

  void dispose() {
    stop();
    _arrivalController.close();
  }
}
