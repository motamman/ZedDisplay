import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'signalk_service.dart';
import 'notification_navigation_service.dart';
import '../models/crew_message.dart';
import '../models/crew_member.dart';
import '../models/notification_payload.dart';
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

  /// Navigation service for tap-to-navigate
  NotificationNavigationService? _navService;

  /// Pending payload for cold start handling
  String? _pendingPayload;

  /// Set the navigation service for tap-to-navigate
  void setNavigationService(NotificationNavigationService navService) {
    _navService = navService;
  }

  /// Set the navigator key for notification-based navigation
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;

    // Process pending cold-start payload after navigator is ready
    if (_pendingPayload != null) {
      final pending = _pendingPayload;
      _pendingPayload = null;
      Future.delayed(const Duration(milliseconds: 500), () {
        _processPayload(pending!);
      });
    }
  }

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_initialized) return;

    // Android initialization settings - use monochrome drawable for status bar
    const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');

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
      settings: initSettings,
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

    // Check for cold start notification (app launched by tapping a notification)
    _checkColdStartNotification();
  }

  /// Check if the app was launched by tapping a notification
  Future<void> _checkColdStartNotification() async {
    try {
      final launchDetails = await _notifications.getNotificationAppLaunchDetails();
      if (launchDetails != null &&
          launchDetails.didNotificationLaunchApp &&
          launchDetails.notificationResponse != null) {
        final payload = launchDetails.notificationResponse!.payload;
        if (payload != null) {
          // Store as pending — will be processed when navigator key is set
          _pendingPayload = payload;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error checking cold start notification: $e');
      }
    }
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    if (kDebugMode) {
      print('Notification tapped: ${response.payload}');
    }

    final payload = response.payload;
    if (payload == null) return;

    if (_navigatorKey?.currentState == null) {
      // Navigator not ready — store for later
      _pendingPayload = payload;
      return;
    }

    _processPayload(payload);
  }

  /// Process a notification payload string (handles both structured and legacy formats)
  void _processPayload(String payload) {
    // Try structured payload first
    final structured = NotificationPayload.decode(payload);
    if (structured != null) {
      _handleStructuredPayload(structured);
      return;
    }

    // Fall through to legacy string-based handlers
    _handleLegacyPayload(payload);
  }

  /// Handle a structured NotificationPayload
  void _handleStructuredPayload(NotificationPayload payload) {
    // Try navigation service first
    if (_navService != null) {
      final nav = _navService!.getNavigation(payload);
      if (nav != null) {
        final (navigate, _) = nav;

        // For NWS alerts, also expand the alert detail
        if (payload.type == 'weather_nws' && payload.context?['alertId'] != null) {
          WeatherAlertsNotifier.instance.requestExpandAlert(payload.context!['alertId']!);
        }

        navigate();
        return;
      }
    }

    // Fall back to legacy screen-push navigation for specific types
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) return;

    switch (payload.type) {
      case 'weather_nws':
        final alertId = payload.context?['alertId'];
        if (alertId != null) {
          WeatherAlertsNotifier.instance.requestExpandAlert(alertId);
        }
        break;

      case 'crew_message':
        final subType = payload.context?['subType'];
        if (subType == 'direct') {
          final fromId = payload.context?['fromId'];
          final fromName = payload.context?['fromName'];
          if (fromId != null && fromName != null) {
            final sender = CrewMember(id: fromId, name: fromName, deviceId: '');
            navigator.push(MaterialPageRoute(builder: (_) => DirectChatScreen(crewMember: sender)));
          }
        } else {
          navigator.push(MaterialPageRoute(builder: (_) => const ChatScreen()));
        }
        break;

      case 'intercom':
        final channelId = payload.context?['channelId'];
        if (channelId != null) {
          navigator.push(MaterialPageRoute(builder: (_) => IntercomScreen(initialChannelId: channelId)));
        } else {
          navigator.push(MaterialPageRoute(builder: (_) => const IntercomScreen()));
        }
        break;

      case 'signalk':
        // Navigation service already tried above; no legacy fallback needed
        break;
    }
  }

  /// Handle legacy string-based payloads (backward compatibility)
  void _handleLegacyPayload(String payload) {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) return;

    // Handle intercom notifications
    if (payload.startsWith('intercom:')) {
      final parts = payload.split(':');
      if (parts.length >= 2) {
        navigator.push(MaterialPageRoute(builder: (_) => IntercomScreen(initialChannelId: parts[1])));
      } else {
        navigator.push(MaterialPageRoute(builder: (_) => const IntercomScreen()));
      }
      return;
    }

    // Handle crew message notifications
    if (payload.startsWith('crew_message:')) {
      final parts = payload.split(':');
      if (parts.length >= 2 && parts[1] == 'broadcast') {
        navigator.push(MaterialPageRoute(builder: (_) => const ChatScreen()));
      } else if (parts.length >= 4 && parts[1] == 'direct') {
        final fromId = parts[2];
        final fromName = parts.sublist(3).join(':');
        final sender = CrewMember(id: fromId, name: fromName, deviceId: '');
        navigator.push(MaterialPageRoute(builder: (_) => DirectChatScreen(crewMember: sender)));
      } else {
        navigator.push(MaterialPageRoute(builder: (_) => const ChatScreen()));
      }
      return;
    }

    // Handle NWS weather alert notifications
    if (payload.startsWith('weather.nws.')) {
      final alertId = payload.replaceFirst('weather.nws.', '');
      WeatherAlertsNotifier.instance.requestExpandAlert(alertId);
      // Also try to navigate to the weather_alerts screen
      if (_navService != null) {
        final nav = _navService!.getNavigation(
          NotificationPayload(type: 'weather_nws', context: {'alertId': alertId}),
        );
        if (nav != null) {
          nav.$1();
        }
      }
      return;
    }

    // Handle alarm notifications
    if (payload.startsWith('alarm:')) {
      if (_navService != null) {
        final nav = _navService!.getNavigation(const NotificationPayload(type: 'alarm'));
        if (nav != null) {
          nav.$1();
        }
      }
      return;
    }

    // Handle other notification types — try navigation service with SignalK key
    if (_navService != null) {
      final nav = _navService!.getNavigation(
        NotificationPayload(type: 'signalk', notificationKey: payload),
      );
      if (nav != null) {
        nav.$1();
        return;
      }
    }

    // Final fallback for crew-related
    if (payload.contains('crew')) {
      navigator.push(MaterialPageRoute(builder: (_) => const CrewScreen()));
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

      // Use stable ID per key so the OS replaces (not stacks) same-key notifications
      final notificationId = notification.key.hashCode.abs() % 100000 + 1; // +1 to avoid 0 (group summary)

      // Extract headline from message (remove language prefix like "en-US: ")
      String headline = notification.message;
      final langMatch = RegExp(r'^[a-z]{2}(-[A-Z]{2})?: ').firstMatch(headline);
      if (langMatch != null) {
        headline = headline.substring(langMatch.end);
      }

      // Build structured payload for tap-to-navigate
      final isNws = notification.key.startsWith('weather.nws.');
      final structuredPayload = NotificationPayload(
        type: isNws ? 'weather_nws' : 'signalk',
        notificationKey: notification.key,
        context: isNws
            ? {'alertId': notification.key.replaceFirst('weather.nws.', '')}
            : null,
      );

      await _notifications.show(
        id: notificationId,
        title: '[$title] $headline',
        body: notification.key,
        notificationDetails: details,
        payload: structuredPayload.encode(),
      );
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
      id: _groupSummaryId,
      title: 'ZedDisplay',
      body: '$_activeNotificationCount active alert${_activeNotificationCount > 1 ? 's' : ''}',
      notificationDetails: details,
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
    await _notifications.cancel(id: id);
    if (_activeNotificationCount > 0) {
      _activeNotificationCount--;
      if (_activeNotificationCount == 0) {
        await _notifications.cancel(id: _groupSummaryId);
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

      // Build structured payload
      final structuredPayload = NotificationPayload(
        type: 'crew_message',
        context: message.isBroadcast
            ? {'subType': 'broadcast'}
            : {
                'subType': 'direct',
                'fromId': message.fromId,
                'fromName': message.fromName,
              },
      );

      await _notifications.show(
        id: _notificationIdCounter,
        title: title,
        body: body,
        notificationDetails: details,
        payload: structuredPayload.encode(),
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
      id: _groupSummaryId + 1000, // Different ID from SignalK summary
      title: 'Crew Messages',
      body: '$_activeNotificationCount message${_activeNotificationCount > 1 ? 's' : ''}',
      notificationDetails: details,
    );
  }

  /// Show a notification for clock alarms with action buttons
  Future<void> showAlarmNotification({
    required String title,
    required String body,
    String? alarmId,
  }) async {
    if (!_initialized) return;

    try {
      final androidDetails = AndroidNotificationDetails(
        'clock_alarms',
        'Clock Alarms',
        channelDescription: 'Alarm notifications from clock widget',
        importance: Importance.max,
        priority: Priority.max,
        color: const Color(0xFFF57C00), // orange.shade700
        playSound: true,
        enableVibration: true,
        ticker: title,
        fullScreenIntent: true, // Show as full screen on lock screen
        category: AndroidNotificationCategory.alarm,
        ongoing: true, // Keep notification until dismissed
        autoCancel: false,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            'snooze_$alarmId',
            'Snooze 9m',
            showsUserInterface: true,
          ),
          AndroidNotificationAction(
            'dismiss_local_$alarmId',
            'Dismiss Here',
            showsUserInterface: true,
          ),
          AndroidNotificationAction(
            'dismiss_all_$alarmId',
            'Dismiss All',
            showsUserInterface: true,
          ),
        ],
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Use stable ID per alarm type so OS replaces (not stacks) on state changes
      final stableAlarmId = (alarmId ?? 'unknown').hashCode.abs() % 100000 + 1;

      // Store the notification ID for this alarm so we can cancel it later
      _alarmNotificationIds[alarmId ?? 'unknown'] = stableAlarmId;

      // Build structured payload
      final structuredPayload = NotificationPayload(
        type: 'alarm',
        context: alarmId != null ? {'alarmId': alarmId} : null,
      );

      await _notifications.show(
        id: stableAlarmId,
        title: title,
        body: body,
        notificationDetails: details,
        payload: structuredPayload.encode(),
      );

      if (kDebugMode) {
        print('Showed alarm notification: $title (id: $_notificationIdCounter)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error showing alarm notification: $e');
      }
    }
  }

  // Track notification IDs for alarms so we can cancel them
  final Map<String, int> _alarmNotificationIds = {};

  /// Cancel an alarm notification
  Future<void> cancelAlarmNotification(String alarmId) async {
    final notificationId = _alarmNotificationIds[alarmId];
    if (notificationId != null) {
      await _notifications.cancel(id: notificationId);
      _alarmNotificationIds.remove(alarmId);
      if (kDebugMode) {
        print('Cancelled alarm notification: $alarmId');
      }
    }
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

      // Build structured payload
      final structuredPayload = NotificationPayload(
        type: 'intercom',
        context: {'channelId': channelId, 'channelName': channelName},
      );

      await _notifications.show(
        id: _notificationIdCounter,
        title: isEmergency ? '🚨 EMERGENCY: $channelName' : '📻 $channelName',
        body: '$transmitterName is transmitting',
        notificationDetails: details,
        payload: structuredPayload.encode(),
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
