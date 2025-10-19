import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'signalk_service.dart';

/// Service to handle system-level notifications
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _notificationIdCounter = 0; // Sequential ID for unique notifications

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_initialized) return;

    // Android initialization settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization settings
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Request permissions for Android 13+
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidImplementation = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidImplementation?.requestNotificationsPermission();
      if (kDebugMode) {
        print('📱 Android notification permission: ${granted == true ? "GRANTED" : "DENIED"}');
      }
    }

    // Request permissions for iOS
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _notifications
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }

    _initialized = true;

    if (kDebugMode) {
      print('📱 Notification service initialized');
    }
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    if (kDebugMode) {
      print('Notification tapped: ${response.payload}');
    }
    // TODO: Navigate to specific screen based on notification type
  }

  /// Show a system notification for a SignalK notification
  Future<void> showNotification(SignalKNotification notification) async {
    if (kDebugMode) {
      print('📱 showNotification called: [${notification.state}] ${notification.message}');
    }

    if (!_initialized) {
      if (kDebugMode) {
        print('❌ NotificationService not initialized');
      }
      return;
    }

    try {
      final (title, priority, importance, color) = _getNotificationSettings(notification.state);

      // Create notification details
      final androidDetails = AndroidNotificationDetails(
        'signalk_${notification.state.toLowerCase()}',
        'SignalK ${notification.state} Notifications',
        channelDescription: 'SignalK ${notification.state} level notifications',
        importance: importance,
        priority: priority,
        color: color,
        playSound: notification.state.toLowerCase() == 'emergency' || notification.state.toLowerCase() == 'alarm',
        enableVibration: notification.state.toLowerCase() == 'emergency' || notification.state.toLowerCase() == 'alarm',
        ticker: notification.message,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Use sequential ID to avoid replacing notifications
      _notificationIdCounter++;
      if (_notificationIdCounter > 2147483647) {
        _notificationIdCounter = 1; // Reset if overflow
      }

      await _notifications.show(
        _notificationIdCounter,
        title,
        notification.message,
        details,
        payload: notification.key,
      );

      if (kDebugMode) {
        print('📱 ✅ System notification shown: ID=$_notificationIdCounter [$title] ${notification.message}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error showing system notification: $e');
      }
    }
  }

  /// Get notification settings based on severity level
  (String title, Priority priority, Importance importance, Color color) _getNotificationSettings(String state) {
    switch (state.toLowerCase()) {
      case 'emergency':
        return ('EMERGENCY', Priority.max, Importance.max, const Color(0xFFB71C1C)); // red.shade900
      case 'alarm':
        return ('ALARM', Priority.high, Importance.high, const Color(0xFFC62828)); // red.shade700
      case 'warn':
        return ('WARNING', Priority.high, Importance.high, const Color(0xFFF57C00)); // orange.shade700
      case 'alert':
        return ('ALERT', Priority.defaultPriority, Importance.defaultImportance, const Color(0xFFFFB300)); // amber.shade700
      case 'normal':
        return ('Notification', Priority.defaultPriority, Importance.defaultImportance, const Color(0xFF1976D2)); // blue.shade700
      case 'nominal':
        return ('All Systems Normal', Priority.low, Importance.low, const Color(0xFF388E3C)); // green.shade700
      default:
        return ('Notification', Priority.defaultPriority, Importance.defaultImportance, const Color(0xFF757575)); // grey
    }
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }

  /// Cancel a specific notification
  Future<void> cancel(int id) async {
    await _notifications.cancel(id);
  }
}
