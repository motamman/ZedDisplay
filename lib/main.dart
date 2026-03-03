import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'services/signalk_service.dart';
import 'services/storage_service.dart';
import 'services/dashboard_service.dart';
import 'services/tool_registry.dart';
import 'services/tool_service.dart';
import 'services/auth_service.dart';
import 'services/setup_service.dart';
import 'services/notification_service.dart';
import 'services/foreground_service.dart';
import 'services/crew_service.dart';
import 'services/messaging_service.dart';
import 'services/file_share_service.dart';
import 'services/file_server_service.dart';
import 'services/intercom_service.dart';
import 'services/scale_service.dart';
import 'models/auth_token.dart';
import 'screens/splash_screen.dart';
import 'screens/setup_management_screen.dart';
import 'widgets/crew/intercom_panel.dart';
import 'widgets/tools/weather_alerts_tool.dart';

// Global app start time
final DateTime appStartTime = DateTime.now();

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Note: Syncfusion license registration is no longer required
  // The license is now handled automatically

  // Initialize storage service
  final storageService = StorageService();
  await storageService.initialize();

  // Initialize notification service
  final notificationService = NotificationService();
  await notificationService.initialize();

  // Initialize foreground service
  final foregroundService = ForegroundTaskService();
  await foregroundService.initialize();

  // Initialize tool service
  final toolService = ToolService(storageService);
  await toolService.initialize();

  // Initialize SignalK service (will connect later)
  final signalKService = SignalKService(storageService: storageService);

  // Initialize crew service
  final crewService = CrewService(signalKService, storageService);
  await crewService.initialize();

  // Initialize messaging service
  final messagingService = MessagingService(signalKService, storageService, crewService);
  await messagingService.initialize();

  // Initialize file server service (for serving shared files over HTTP)
  final fileServerService = FileServerService();

  // Initialize file share service
  final fileShareService = FileShareService(signalKService, storageService, crewService, fileServerService);
  await fileShareService.initialize();

  // Initialize intercom service (wrapped to prevent crash loops on WebRTC init failures)
  final intercomService = IntercomService(signalKService, storageService, crewService);
  try {
    await intercomService.initialize();
  } catch (e) {
    if (kDebugMode) {
      print('⚠️ IntercomService initialization failed: $e');
    }
  }

  // Auto-enable notifications if they were enabled before
  final notificationsEnabled = storageService.getNotificationsEnabled();
  if (notificationsEnabled) {
    // Note: Notification channel will connect when SignalK connects
    await signalKService.setNotificationsEnabled(true);
  }

  // Initialize dashboard service with SignalK and Tool services
  final dashboardService = DashboardService(
    storageService,
    signalKService,
    toolService,
  );
  await dashboardService.initialize();

  // Initialize auth service
  final authService = AuthService(storageService);

  // Initialize setup service
  final setupService = SetupService(
    storageService,
    toolService,
    dashboardService,
  );
  await setupService.initialize();

  // Connect crew service to setup service (for device name in crew profiles)
  crewService.setSetupService(setupService);

  // Register all built-in tool types
  final toolRegistry = ToolRegistry();
  toolRegistry.registerDefaults();

  // Initialize scale service (for menu items)
  await ScaleService.instance.initialize();

  runApp(ZedDisplayApp(
    storageService: storageService,
    signalKService: signalKService,
    dashboardService: dashboardService,
    toolService: toolService,
    authService: authService,
    setupService: setupService,
    notificationService: notificationService,
    foregroundService: foregroundService,
    crewService: crewService,
    messagingService: messagingService,
    fileShareService: fileShareService,
    intercomService: intercomService,
  ));
}

class ZedDisplayApp extends StatefulWidget {
  final StorageService storageService;
  final SignalKService signalKService;
  final DashboardService dashboardService;
  final ToolService toolService;
  final AuthService authService;
  final SetupService setupService;
  final NotificationService notificationService;
  final ForegroundTaskService foregroundService;
  final CrewService crewService;
  final MessagingService messagingService;
  final FileShareService fileShareService;
  final IntercomService intercomService;

  const ZedDisplayApp({
    super.key,
    required this.storageService,
    required this.signalKService,
    required this.dashboardService,
    required this.toolService,
    required this.authService,
    required this.setupService,
    required this.notificationService,
    required this.foregroundService,
    required this.crewService,
    required this.messagingService,
    required this.fileShareService,
    required this.intercomService,
  });

  @override
  State<ZedDisplayApp> createState() => _ZedDisplayAppState();
}

class _ZedDisplayAppState extends State<ZedDisplayApp> with WidgetsBindingObserver {
  String? _lastServerUrl;
  bool? _lastUseSecure;
  AuthToken? _lastToken;
  late ThemeMode _themeMode;
  static const platform = MethodChannel('com.zennora.zed_display/intent');
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize theme mode from storage (defaults to dark)
    final themeModeStr = widget.storageService.getThemeMode();
    _themeMode = _parseThemeMode(themeModeStr);

    // Listen to connection changes to manage wakelock
    widget.signalKService.addListener(_onConnectionChanged);

    // Listen to storage changes for theme updates
    widget.storageService.addListener(_onStorageChanged);

    // Set navigator key for notification-based navigation
    widget.notificationService.setNavigatorKey(_navigatorKey);

    // Check for shared file (Android only)
    if (!kIsWeb && Platform.isAndroid) {
      _checkForSharedFile();
    }
  }

  Future<void> _checkForSharedFile() async {
    try {
      final String? fileContent = await platform.invokeMethod('getSharedFileContent');
      if (fileContent != null && mounted) {
        await _loadSharedFile(fileContent);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error checking for shared file: $e');
      }
    }
  }

  Future<void> _loadSharedFile(String content) async {
    try {
      // Validate JSON first
      jsonDecode(content); // Will throw if invalid

      // Load the setup (expects JSON string)
      final result = await widget.setupService.importSetup(content);

      // Show success feedback (with warnings if any)
      if (mounted) {
        final message = result.hasWarnings
            ? 'Dashboard imported with warnings: ${result.warnings.join("; ")}'
            : 'Dashboard imported successfully';
        _showImportSnackBar(message, result.hasWarnings ? Colors.orange : Colors.green);
      }

      // Schedule navigation after SplashScreen completes (2500ms + buffer)
      Future.delayed(const Duration(milliseconds: 3000), () {
        if (mounted && _navigatorKey.currentState != null) {
          _navigatorKey.currentState!.push(
            MaterialPageRoute(
              builder: (context) => const SetupManagementScreen(),
            ),
          );
        }
      });

      if (kDebugMode) {
        print('Successfully loaded shared dashboard file');
      }
    } catch (e) {
      // Always show error to user (not just in debug mode)
      if (mounted) {
        _showImportSnackBar('Failed to import dashboard: ${_formatImportError(e)}', Colors.red);
      }
      if (kDebugMode) {
        print('Error loading shared file: $e');
      }
    }
  }

  /// Show a snackbar for import results
  void _showImportSnackBar(String message, Color backgroundColor) {
    // Schedule after frame to ensure MaterialApp is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scaffoldMessengerKey.currentState != null) {
        _scaffoldMessengerKey.currentState!.showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: backgroundColor,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    });
  }

  /// Format error messages for display (remove nested Exception: prefixes)
  String _formatImportError(dynamic error) {
    String msg = error.toString();
    // Remove nested "Exception:" prefixes for cleaner display
    msg = msg.replaceAll(RegExp(r'Exception:\s*'), '');
    // Truncate if too long
    if (msg.length > 100) {
      msg = '${msg.substring(0, 100)}...';
    }
    return msg;
  }

  ThemeMode _parseThemeMode(String mode) {
    switch (mode.toLowerCase()) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark; // Default to dark
    }
  }

  void _onStorageChanged() {
    final themeModeStr = widget.storageService.getThemeMode();
    final newThemeMode = _parseThemeMode(themeModeStr);
    if (newThemeMode != _themeMode) {
      setState(() {
        _themeMode = newThemeMode;
      });
    }
  }

  @override
  void dispose() {
    widget.signalKService.removeListener(_onConnectionChanged);
    widget.storageService.removeListener(_onStorageChanged);
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    widget.foregroundService.stop();
    super.dispose();
  }

  void _onConnectionChanged() {
    if (widget.signalKService.isConnected) {
      // Enable wakelock when connected to keep screen on and connection alive
      WakelockPlus.enable();

      // Start foreground service if notifications are enabled
      final notificationsEnabled = widget.storageService.getNotificationsEnabled();
      if (notificationsEnabled) {
        widget.foregroundService.start();
      }
    } else {
      // Disable wakelock when disconnected to save battery
      WakelockPlus.disable();

      // Stop foreground service when disconnected
      widget.foregroundService.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // Save connection state when app goes to background
        if (widget.signalKService.isConnected) {
          _lastServerUrl = widget.signalKService.serverUrl;
          _lastUseSecure = widget.signalKService.useSecureConnection;
          // Find connection by URL to get connectionId for token lookup
          final connection = widget.storageService.findConnectionByUrl(_lastServerUrl!);
          _lastToken = connection != null
              ? widget.authService.getSavedToken(connection.id)
              : null;
        }
        break;

      case AppLifecycleState.resumed:
        // Reconnect when app returns to foreground
        if (_lastServerUrl != null && _lastToken != null && !widget.signalKService.isConnected) {
          _reconnect();
        }
        break;

      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _reconnect() async {
    try {
      await widget.signalKService.connect(
        _lastServerUrl!,
        secure: _lastUseSecure ?? false,
        authToken: _lastToken,
      );

      // Re-setup dashboard subscriptions
      if (widget.dashboardService.currentLayout != null) {
        await widget.dashboardService.updateLayout(widget.dashboardService.currentLayout!);
      }
    } catch (e) {
      // Silent fail - user will see disconnected state in UI
      debugPrint('Auto-reconnect failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.storageService),
        ChangeNotifierProvider.value(value: widget.signalKService),
        ChangeNotifierProvider.value(value: widget.dashboardService),
        ChangeNotifierProvider.value(value: widget.toolService),
        ChangeNotifierProvider.value(value: widget.authService),
        ChangeNotifierProvider.value(value: widget.setupService),
        ChangeNotifierProvider.value(value: widget.crewService),
        ChangeNotifierProvider.value(value: widget.messagingService),
        ChangeNotifierProvider.value(value: widget.fileShareService),
        ChangeNotifierProvider.value(value: widget.intercomService),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        scaffoldMessengerKey: _scaffoldMessengerKey,
        title: 'Zed Display',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: _themeMode,
        home: const SplashScreen(),
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          return SignalKNotificationListener(
            signalKService: widget.signalKService,
            storageService: widget.storageService,
            notificationService: widget.notificationService,
            child: Stack(
              children: [
                child ?? const SizedBox.shrink(),
                // Intercom status indicator overlay (shows when receiving transmission)
                const IntercomStatusIndicator(),
                // Global reconnection overlay
                StreamBuilder<SignalKConnectionState>(
                  stream: widget.signalKService.connectionStateStream,
                  builder: (context, snapshot) {
                    final state = snapshot.data ?? widget.signalKService.connectionState;
                    if (state == SignalKConnectionState.reconnecting) {
                      return _ReconnectingOverlay(
                        attempt: widget.signalKService.reconnectAttempt,
                        maxAttempts: widget.signalKService.maxReconnectAttempts,
                      );
                    }
                    if (state == SignalKConnectionState.disconnected &&
                        widget.signalKService.wasConnected) {
                      return _DisconnectedOverlay(
                        onRetry: () => widget.signalKService.reconnect(),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Widget that listens to SignalK notifications and displays them
class SignalKNotificationListener extends StatefulWidget {
  final SignalKService signalKService;
  final StorageService storageService;
  final NotificationService notificationService;
  final Widget child;

  const SignalKNotificationListener({
    super.key,
    required this.signalKService,
    required this.storageService,
    required this.notificationService,
    required this.child,
  });

  @override
  State<SignalKNotificationListener> createState() => _SignalKNotificationListenerState();
}

class _SignalKNotificationListenerState extends State<SignalKNotificationListener> {
  StreamSubscription<SignalKNotification>? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    _setupNotificationListener();
  }

  void _setupNotificationListener() {
    _notificationSubscription = widget.signalKService.notificationStream.listen(
      _handleNotification,
      onError: (error) {
        if (kDebugMode) {
          print('Notification stream error: $error');
        }
      },
    );
  }

  void _handleNotification(SignalKNotification notification) {
    if (!mounted) return;

    // Check both in-app and system notification filters
    final showInApp = widget.storageService.getInAppNotificationFilter(notification.state.toLowerCase());
    final showSystem = widget.storageService.getSystemNotificationFilter(notification.state.toLowerCase());

    if (!showInApp && !showSystem) {
      return; // Filtered out
    }

    // Show system notification if enabled for this level
    if (showSystem) {
      widget.notificationService.showNotification(notification);
    }

    // Show in-app notification if enabled for this level
    if (!showInApp) {
      return;
    }

    // Determine color based on notification state
    Color backgroundColor;
    IconData icon;

    switch (notification.state.toLowerCase()) {
      case 'emergency':
        backgroundColor = Colors.red.shade900;
        icon = Icons.emergency;
        break;
      case 'alarm':
        backgroundColor = Colors.red.shade700;
        icon = Icons.alarm;
        break;
      case 'warn':
        backgroundColor = Colors.orange.shade700;
        icon = Icons.warning;
        break;
      case 'alert':
        backgroundColor = Colors.amber.shade700;
        icon = Icons.info;
        break;
      case 'normal':
        backgroundColor = Colors.blue.shade700;
        icon = Icons.notifications;
        break;
      case 'nominal':
        backgroundColor = Colors.green.shade700;
        icon = Icons.check_circle;
        break;
      default:
        backgroundColor = Colors.grey.shade700;
        icon = Icons.notifications_none;
        break;
    }

    // Extract headline from message (remove language prefix like "en-US: ")
    String headline = notification.message;
    final langMatch = RegExp(r'^[a-z]{2}(-[A-Z]{2})?: ').firstMatch(headline);
    if (langMatch != null) {
      headline = headline.substring(langMatch.end);
    }

    // Check if this is an NWS weather alert
    final isNwsAlert = notification.key.startsWith('weather.nws.');
    // Extract alert ID from key like "weather.nws.winterWeatherAdvisory"
    final alertId = isNwsAlert ? notification.key.replaceFirst('weather.nws.', '') : null;

    // Show the notification as a SnackBar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: GestureDetector(
          onTap: isNwsAlert && alertId != null
              ? () {
                  WeatherAlertsNotifier.instance.requestExpandAlert(alertId);
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                }
              : null,
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '[${notification.state.toUpperCase()}] $headline',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.key,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        if (isNwsAlert)
                          const Text(
                            'TAP FOR DETAILS',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white54,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        backgroundColor: backgroundColor,
        duration: notification.state.toLowerCase() == 'emergency' ||
                notification.state.toLowerCase() == 'alarm'
            ? const Duration(seconds: 10)
            : const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'DISMISS',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Overlay shown when attempting to reconnect to SignalK server
class _ReconnectingOverlay extends StatelessWidget {
  final int attempt;
  final int maxAttempts;

  const _ReconnectingOverlay({
    required this.attempt,
    required this.maxAttempts,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Reconnecting...', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 8),
                Text('Attempt $attempt of $maxAttempts'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Overlay shown when connection to SignalK server is lost
class _DisconnectedOverlay extends StatelessWidget {
  final VoidCallback onRetry;

  const _DisconnectedOverlay({
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text('Connection Lost', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
