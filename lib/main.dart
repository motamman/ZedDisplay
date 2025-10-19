import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'services/signalk_service.dart';
import 'services/storage_service.dart';
import 'services/dashboard_service.dart';
import 'services/tool_registry.dart';
import 'services/tool_service.dart';
import 'services/auth_service.dart';
import 'services/setup_service.dart';
import 'models/auth_token.dart';
import 'screens/splash_screen.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Note: Syncfusion license registration is no longer required
  // The license is now handled automatically

  // Initialize storage service
  final storageService = StorageService();
  await storageService.initialize();

  // Initialize tool service
  final toolService = ToolService(storageService);
  await toolService.initialize();

  // Initialize SignalK service (will connect later)
  final signalKService = SignalKService();

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

  // Register all built-in tool types
  final toolRegistry = ToolRegistry();
  toolRegistry.registerDefaults();

  runApp(ZedDisplayApp(
    storageService: storageService,
    signalKService: signalKService,
    dashboardService: dashboardService,
    toolService: toolService,
    authService: authService,
    setupService: setupService,
  ));
}

class ZedDisplayApp extends StatefulWidget {
  final StorageService storageService;
  final SignalKService signalKService;
  final DashboardService dashboardService;
  final ToolService toolService;
  final AuthService authService;
  final SetupService setupService;

  const ZedDisplayApp({
    super.key,
    required this.storageService,
    required this.signalKService,
    required this.dashboardService,
    required this.toolService,
    required this.authService,
    required this.setupService,
  });

  @override
  State<ZedDisplayApp> createState() => _ZedDisplayAppState();
}

class _ZedDisplayAppState extends State<ZedDisplayApp> with WidgetsBindingObserver {
  String? _lastServerUrl;
  bool? _lastUseSecure;
  AuthToken? _lastToken;
  late ThemeMode _themeMode;

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
    super.dispose();
  }

  void _onConnectionChanged() {
    if (widget.signalKService.isConnected) {
      // Enable wakelock when connected to keep screen on and connection alive
      WakelockPlus.enable();
      // debugPrint('Wakelock enabled - keeping connection alive');
    } else {
      // Disable wakelock when disconnected to save battery
      WakelockPlus.disable();
      // debugPrint('Wakelock disabled');
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
          _lastToken = widget.authService.getSavedToken(_lastServerUrl!);
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
      ],
      child: MaterialApp(
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
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}

/// Widget that listens to SignalK notifications and displays them
class SignalKNotificationListener extends StatefulWidget {
  final SignalKService signalKService;
  final Widget child;

  const SignalKNotificationListener({
    super.key,
    required this.signalKService,
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
    debugPrint('📱 NotificationListener: Setting up stream listener');
    _notificationSubscription = widget.signalKService.notificationStream.listen(
      _handleNotification,
      onError: (error) {
        debugPrint('📱 NotificationListener: Stream error: $error');
      },
      onDone: () {
        debugPrint('📱 NotificationListener: Stream closed');
      },
    );
    debugPrint('📱 NotificationListener: Stream listener set up successfully');
  }

  void _handleNotification(SignalKNotification notification) {
    debugPrint('📱 NotificationListener: Received notification: [${notification.state}] ${notification.message}');

    if (!mounted) {
      debugPrint('📱 NotificationListener: Widget not mounted, skipping display');
      return;
    }

    // Check if this notification level should be displayed
    final storageService = Provider.of<StorageService>(context, listen: false);
    final shouldShow = storageService.getNotificationLevelFilter(notification.state.toLowerCase());
    if (!shouldShow) {
      debugPrint('📱 NotificationListener: Level ${notification.state} is filtered out');
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

    // Show the notification as a SnackBar
    debugPrint('📱 NotificationListener: Showing SnackBar with color: $backgroundColor');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    notification.state.toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.message,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
