import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'signalk_service.dart';
import '../models/crew_message.dart';
import '../models/crew_member.dart';
import '../screens/crew/chat_screen.dart';
import '../screens/crew/crew_screen.dart';
import '../screens/crew/direct_chat_screen.dart';
import '../screens/crew/intercom_screen.dart';
import '../widgets/tools/weather_alerts_tool.dart';

/// Service to handle system-level notifications
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _notificationIdCounter = 0; // Sequential ID for unique notifications
  static const int _groupSummaryId = 0; // Fixed ID for group summary
  int _activeNotificationCount = 0; // Track active notifications for summary

  /// Navigator key for navigating from notifications
  GlobalKey<NavigatorState>? _navigatorKey;

  /// Set the navigator key for notification-based navigation
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_initialized) return;

    // Android initialization settings - use monochrome drawable for status bar
    const androidSettings = AndroidInitializationSettings('@drawable/ic_launcher_foreground');

    // iOS initialization settings
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // Linux initialization settings
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open notification',
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      linux: linuxSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Request permissions for Android 13+
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidImplementation = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidImplementation?.requestNotificationsPermission();
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
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    if (kDebugMode) {
      print('Notification tapped: ${response.payload}');
    }

    final payload = response.payload;
    if (payload == null || _navigatorKey?.currentState == null) return;

    final navigator = _navigatorKey!.currentState!;

    // Handle intercom notifications
    // Payload format: intercom:{channelId}:{channelName}
    if (payload.startsWith('intercom:')) {
      final parts = payload.split(':');
      if (parts.length >= 2) {
        final channelId = parts[1];
        navigator.push(
          MaterialPageRoute(
            builder: (_) => IntercomScreen(initialChannelId: channelId),
          ),
        );
      } else {
        navigator.push(
          MaterialPageRoute(builder: (_) => const IntercomScreen()),
        );
      }
      return;
    }

    // Handle crew message notifications
    // Payload format: crew_message:broadcast or crew_message:direct:{fromId}:{fromName}
    if (payload.startsWith('crew_message:')) {
      final parts = payload.split(':');

      if (parts.length >= 2 && parts[1] == 'broadcast') {
        // Open broadcast chat screen
        navigator.push(
          MaterialPageRoute(builder: (_) => const ChatScreen()),
        );
      } else if (parts.length >= 4 && parts[1] == 'direct') {
        // Open direct chat with the sender
        final fromId = parts[2];
        final fromName = parts.sublist(3).join(':'); // Handle names with colons

        // Create a minimal CrewMember for navigation
        final sender = CrewMember(
          id: fromId,
          name: fromName,
          deviceId: '', // Not needed for navigation
        );

        navigator.push(
          MaterialPageRoute(builder: (_) => DirectChatScreen(crewMember: sender)),
        );
      } else {
        // Fallback to broadcast chat
        navigator.push(
          MaterialPageRoute(builder: (_) => const ChatScreen()),
        );
      }
      return;
    }

    // Handle NWS weather alert notifications
    // Payload format: weather.nws.{alertId}
    if (payload.startsWith('weather.nws.')) {
      final alertId = payload.replaceFirst('weather.nws.', '');
      WeatherAlertsNotifier.instance.requestExpandAlert(alertId);
      return;
    }

    // Handle other notification types (SignalK alerts, etc.)
    // For now, open the crew screen for crew-related or general notifications
    if (payload.contains('crew')) {
      navigator.push(
        MaterialPageRoute(builder: (_) => const CrewScreen()),
      );
    }
  }

  /// Show a system notification for a SignalK notification
  Future<void> showNotification(SignalKNotification notification) async {
    if (!_initialized) {
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
        groupKey: 'com.zennora.zed_display.SIGNALK_NOTIFICATIONS',
        setAsGroupSummary: false,
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

      // Extract headline from message (remove language prefix like "en-US: ")
      String headline = notification.message;
      final langMatch = RegExp(r'^[a-z]{2}(-[A-Z]{2})?: ').firstMatch(headline);
      if (langMatch != null) {
        headline = headline.substring(langMatch.end);
      }

      await _notifications.show(
        _notificationIdCounter,
        '[$title] $headline',
        notification.key,
        details,
        payload: notification.key,
      );

      // Update group summary
      _activeNotificationCount++;
      await _updateGroupSummary();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error showing system notification: $e');
      }
    }
  }

  /// Update or create the group summary notification
  Future<void> _updateGroupSummary() async {
    if (!_initialized || _activeNotificationCount == 0) return;

    const androidDetails = AndroidNotificationDetails(
      'signalk_summary',
      'SignalK Notifications',
      channelDescription: 'Summary of SignalK notifications',
      importance: Importance.low,
      priority: Priority.low,
      groupKey: 'com.zennora.zed_display.SIGNALK_NOTIFICATIONS',
      setAsGroupSummary: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: true,
      presentSound: false,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      _groupSummaryId,
      'ZedDisplay',
      '$_activeNotificationCount active alert${_activeNotificationCount > 1 ? 's' : ''}',
      details,
    );
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
    _activeNotificationCount = 0;
  }

  /// Cancel a specific notification
  Future<void> cancel(int id) async {
    await _notifications.cancel(id);
    if (_activeNotificationCount > 0) {
      _activeNotificationCount--;
      if (_activeNotificationCount == 0) {
        await _notifications.cancel(_groupSummaryId);
      } else {
        await _updateGroupSummary();
      }
    }
  }

  /// Show a notification for a crew message
  Future<void> showCrewMessageNotification(CrewMessage message) async {
    if (!_initialized) return;

    try {
      final (title, body, priority, importance, color, playSound) =
          _getCrewMessageSettings(message);

      final androidDetails = AndroidNotificationDetails(
        'crew_messages',
        'Crew Messages',
        channelDescription: 'Messages from crew members',
        importance: importance,
        priority: priority,
        color: color,
        playSound: playSound,
        enableVibration: playSound,
        ticker: body,
        groupKey: 'com.zennora.zed_display.CREW_MESSAGES',
        setAsGroupSummary: false,
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

      _notificationIdCounter++;
      if (_notificationIdCounter > 2147483647) {
        _notificationIdCounter = 1;
      }

      // Build payload based on message type
      // Format: crew_message:broadcast or crew_message:direct:{fromId}:{fromName}
      final payload = message.isBroadcast
          ? 'crew_message:broadcast'
          : 'crew_message:direct:${message.fromId}:${message.fromName}';

      await _notifications.show(
        _notificationIdCounter,
        title,
        body,
        details,
        payload: payload,
      );

      _activeNotificationCount++;
      await _updateCrewMessageSummary();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error showing crew message notification: $e');
      }
    }
  }

  /// Get notification settings based on message type
  (String title, String body, Priority priority, Importance importance, Color color, bool playSound)
      _getCrewMessageSettings(CrewMessage message) {
    switch (message.type) {
      case MessageType.alert:
        return (
          '🚨 ALERT from ${message.fromName}',
          message.content,
          Priority.max,
          Importance.max,
          const Color(0xFFB71C1C), // red.shade900
          true,
        );
      case MessageType.status:
        return (
          message.fromName,
          message.content,
          Priority.defaultPriority,
          Importance.defaultImportance,
          const Color(0xFF1976D2), // blue.shade700
          false,
        );
      case MessageType.text:
      default:
        return (
          message.fromName,
          message.content,
          Priority.high,
          Importance.high,
          const Color(0xFF388E3C), // green.shade700
          true,
        );
    }
  }

  /// Update crew message group summary
  Future<void> _updateCrewMessageSummary() async {
    if (!_initialized || _activeNotificationCount == 0) return;

    const androidDetails = AndroidNotificationDetails(
      'crew_messages_summary',
      'Crew Messages',
      channelDescription: 'Summary of crew messages',
      importance: Importance.low,
      priority: Priority.low,
      groupKey: 'com.zennora.zed_display.CREW_MESSAGES',
      setAsGroupSummary: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: true,
      presentSound: false,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      _groupSummaryId + 1000, // Different ID from SignalK summary
      'Crew Messages',
      '$_activeNotificationCount message${_activeNotificationCount > 1 ? 's' : ''}',
      details,
    );
  }

  /// Show a notification for intercom activity
  Future<void> showIntercomNotification({
    required String channelId,
    required String channelName,
    required String transmitterName,
    bool isEmergency = false,
  }) async {
    if (!_initialized) return;

    try {
      final androidDetails = AndroidNotificationDetails(
        isEmergency ? 'intercom_emergency' : 'intercom_activity',
        isEmergency ? 'Emergency Intercom' : 'Intercom Activity',
        channelDescription: isEmergency
            ? 'Emergency intercom transmissions'
            : 'Voice intercom activity notifications',
        importance: isEmergency ? Importance.max : Importance.high,
        priority: isEmergency ? Priority.max : Priority.high,
        color: isEmergency ? const Color(0xFFB71C1C) : const Color(0xFF1976D2),
        playSound: true,
        enableVibration: true,
        ticker: '$transmitterName on $channelName',
        groupKey: 'com.zennora.zed_display.INTERCOM',
        setAsGroupSummary: false,
        // Use a short timeout so it auto-dismisses when transmission ends
        timeoutAfter: 30000, // 30 seconds
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

      _notificationIdCounter++;
      if (_notificationIdCounter > 2147483647) {
        _notificationIdCounter = 1;
      }

      // Payload for navigation: intercom:{channelId}
      final payload = 'intercom:$channelId';

      await _notifications.show(
        _notificationIdCounter,
        isEmergency ? '🚨 EMERGENCY: $channelName' : '📻 $channelName',
        '$transmitterName is transmitting',
        details,
        payload: payload,
      );

      if (kDebugMode) {
        print('Showed intercom notification: $transmitterName on $channelName');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error showing intercom notification: $e');
      }
    }
  }
}
