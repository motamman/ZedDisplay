import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Service to manage foreground task for keeping WebSocket connections alive
class ForegroundTaskService {
  static final ForegroundTaskService _instance = ForegroundTaskService._internal();
  factory ForegroundTaskService() => _instance;
  ForegroundTaskService._internal();

  bool _isRunning = false;

  /// Initialize the foreground task
  Future<void> initialize() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'signalk_foreground_service',
        channelName: 'SignalK Service',
        channelDescription: 'Keeps SignalK connection alive for notifications',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000), // Check every 5 seconds
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Start the foreground service
  Future<bool> start() async {
    if (_isRunning) return true;

    // Check if service is already running
    if (await FlutterForegroundTask.isRunningService) {
      _isRunning = true;
      return true;
    }

    // Start the service
    final serviceStarted = await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'SignalK Connected',
      notificationText: 'Monitoring for alerts',
      notificationIcon: NotificationIcon(
        metaDataName: 'com.zennora.signalk.zeddisplay.NOTIFICATION_ICON',
      ),
      callback: startCallback,
    );

    // Check if it's a success
    if (serviceStarted is ServiceRequestSuccess) {
      _isRunning = true;
      if (kDebugMode) {
        print('✅ Foreground service started');
      }
      return true;
    }

    if (kDebugMode) {
      print('❌ Failed to start foreground service');
    }
    return false;
  }

  /// Stop the foreground service
  Future<bool> stop() async {
    if (!_isRunning) return true;

    final serviceStopped = await FlutterForegroundTask.stopService();
    if (serviceStopped is ServiceRequestSuccess) {
      _isRunning = false;
      if (kDebugMode) {
        print('✅ Foreground service stopped');
      }
      return true;
    }

    return false;
  }

  /// Update the notification
  Future<void> updateNotification({
    required String title,
    required String text,
  }) async {
    if (!_isRunning) return;

    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  bool get isRunning => _isRunning;
}

/// Callback function for the foreground task
@pragma('vm:entry-point')
void startCallback() {
  // This callback is invoked when the service starts
  // Set up the task handler
  FlutterForegroundTask.setTaskHandler(_ForegroundTaskHandler());
}

/// Handler for foreground task events
class _ForegroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Called when the service is started
    if (kDebugMode) {
      print('🔄 Foreground task handler started');
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Called periodically (every 5 seconds based on our config)
    // We don't need to do anything here - just keep the service alive
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // Called when the service is stopped
    if (kDebugMode) {
      print('🔄 Foreground task handler stopped');
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    // Handle notification button presses if we add them in the future
  }

  @override
  void onNotificationPressed() {
    // Handle notification tap
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {
    // Handle notification dismissal
  }
}
