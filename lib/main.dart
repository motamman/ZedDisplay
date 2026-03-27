import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
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
import 'services/notification_navigation_service.dart';
import 'services/foreground_service.dart';
import 'services/crew_service.dart';
import 'services/messaging_service.dart';
import 'services/file_share_service.dart';
import 'services/file_server_service.dart';
import 'services/intercom_service.dart';
import 'services/scale_service.dart';
import 'services/diagnostic_service.dart';
import 'models/auth_token.dart';
import 'models/notification_payload.dart';
import 'screens/splash_screen.dart';
import 'screens/setup_management_screen.dart';
import 'widgets/crew/intercom_panel.dart';
import 'services/anchor_alarm_service.dart';
import 'services/alert_coordinator.dart';
import 'services/ais_favorites_service.dart';
import 'services/cpa_alert_service.dart';
import 'models/cpa_alert_state.dart';
import 'services/find_home_target_service.dart';
import 'services/dashboard_store_service.dart';
import 'models/alert_event.dart' as alert_models;
import 'widgets/tools/weather_alerts_tool.dart';

// Global app start time
final DateTime appStartTime = DateTime.now();

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Catch unhandled async errors (e.g., SocketException from dead WebSocket
  // when Android kills the connection while backgrounded)
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (error is SocketException) {
      // Expected when resuming from background — WebSocket reconnect handles recovery
      if (kDebugMode) {
        print('Caught background SocketException: ${error.message}');
      }
      return true; // Handled, don't crash
    }
    return false; // Let other errors propagate
  };

  // Note: Syncfusion license registration is no longer required
  // The license is now handled automatically

  // Initialize storage service
  final storageService = StorageService();
  await storageService.initialize();

  // Initialize notification service
  final notificationService = NotificationService();
  await notificationService.initialize();
  notificationService.setMasterEnabled(storageService.getNotificationsEnabled());

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

  // Initialize diagnostic service for memory leak investigation
  final deviceId = storageService.getSetting('crew_device_id') ?? 'unknown';
  final diagnosticService = await DiagnosticService.initialize(
    signalKService: signalKService,
    deviceId: deviceId,
  );
  signalKService.setDiagnosticService(diagnosticService);
  if (storageService.getDiagnosticsEnabled()) {
    await diagnosticService.start();
  }

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

  // Wire diagnostic service to report active tool types per snapshot
  diagnosticService.getActiveToolTypes = () {
    final layout = dashboardService.currentLayout;
    if (layout == null) return [];
    final toolIds = layout.getAllToolIds();
    return toolIds
        .map((id) => toolService.getTool(id)?.toolTypeId)
        .whereType<String>()
        .toList();
  };

  // Initialize auth service
  final authService = AuthService(storageService);

  // Initialize setup service
  final setupService = SetupService(
    storageService,
    toolService,
    dashboardService,
  );
  await setupService.initialize();

  // Wire notification tap-to-navigate service
  final notificationNavigationService = NotificationNavigationService(dashboardService);
  notificationService.setNavigationService(notificationNavigationService);

  // Initialize alert coordinator (central gateway for all alert delivery)
  final alertCoordinator = AlertCoordinator(
    storageService: storageService,
    notificationService: notificationService,
    messagingService: messagingService,
  );

  // Wire NWS notification filter: only show alerts when weather_alerts widget is on dashboard
  signalKService.setWeatherAlertsChecker(() {
    final layout = dashboardService.currentLayout;
    if (layout == null) return false;
    final dashToolIds = layout.getAllToolIds().toSet();
    final waTools = toolService.getToolsByToolType('weather_alerts');
    return waTools.any((t) => dashToolIds.contains(t.id));
  });

  // Connect crew service to setup service (for device name in crew profiles)
  crewService.setSetupService(setupService);

  // Register all built-in tool types
  final toolRegistry = ToolRegistry();
  toolRegistry.registerDefaults();

  // Initialize Find Home target service (AIS → Find Home bridge)
  final findHomeTargetService = FindHomeTargetService();

  // Initialize dashboard store service (server-side dashboard CRUD)
  final dashboardStoreService = DashboardStoreService(signalKService);

  // Initialize AIS favorites service
  final aisFavoritesService = AISFavoritesService();
  aisFavoritesService.loadFromStorage(storageService);
  aisFavoritesService.startMonitoring(signalKService, alertCoordinator);

  // Initialize CPA alert service (global singleton — survives widget rebuilds)
  final cpaAlertService = CpaAlertService(
    signalKService: signalKService,
    notificationService: notificationService,
    messagingService: messagingService,
    storageService: storageService,
    alertCoordinator: alertCoordinator,
  );

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
    notificationNavigationService: notificationNavigationService,
    foregroundService: foregroundService,
    crewService: crewService,
    messagingService: messagingService,
    fileShareService: fileShareService,
    intercomService: intercomService,
    alertCoordinator: alertCoordinator,
    aisFavoritesService: aisFavoritesService,
    cpaAlertService: cpaAlertService,
    findHomeTargetService: findHomeTargetService,
    dashboardStoreService: dashboardStoreService,
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
  final NotificationNavigationService notificationNavigationService;
  final ForegroundTaskService foregroundService;
  final CrewService crewService;
  final MessagingService messagingService;
  final FileShareService fileShareService;
  final IntercomService intercomService;
  final AlertCoordinator alertCoordinator;
  final AISFavoritesService aisFavoritesService;
  final CpaAlertService cpaAlertService;
  final FindHomeTargetService findHomeTargetService;
  final DashboardStoreService dashboardStoreService;

  const ZedDisplayApp({
    super.key,
    required this.storageService,
    required this.signalKService,
    required this.dashboardService,
    required this.toolService,
    required this.authService,
    required this.setupService,
    required this.notificationService,
    required this.notificationNavigationService,
    required this.foregroundService,
    required this.crewService,
    required this.messagingService,
    required this.fileShareService,
    required this.intercomService,
    required this.alertCoordinator,
    required this.aisFavoritesService,
    required this.cpaAlertService,
    required this.findHomeTargetService,
    required this.dashboardStoreService,
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

  bool _wakelockEnabled = false;
  bool _wasConnectedForServices = false;
  void _onConnectionChanged() {
    final isConnected = widget.signalKService.isConnected;
    if (isConnected == _wasConnectedForServices) return;
    _wasConnectedForServices = isConnected;

    if (isConnected) {
      if (!_wakelockEnabled) {
        _wakelockEnabled = true;
        WakelockPlus.enable();
      }

      final notificationsEnabled = widget.storageService.getNotificationsEnabled();
      if (notificationsEnabled) {
        widget.foregroundService.start();
      }
    } else {
      if (_wakelockEnabled) {
        _wakelockEnabled = false;
        WakelockPlus.disable();
      }

      widget.foregroundService.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // Tell coordinator we're backgrounded — suppresses snackbar callback
        // accumulation that causes jank on resume
        widget.alertCoordinator.setAppInForeground(false);
        // Flush diagnostic log on background
        DiagnosticService.instance?.stop();
        // Save connection state when app goes to background
        // (don't disconnect — reconnect is too heavy; PlatformDispatcher.onError
        // catches any SocketException if Android kills the socket)
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
        // Resume snackbar delivery
        widget.alertCoordinator.setAppInForeground(true);
        // Restart diagnostic logging on foreground return
        if (widget.storageService.getDiagnosticsEnabled()) {
          DiagnosticService.instance?.start();
        }
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
        ChangeNotifierProvider.value(value: widget.alertCoordinator),
        ChangeNotifierProvider.value(value: widget.aisFavoritesService),
        ChangeNotifierProvider.value(value: widget.cpaAlertService),
        ChangeNotifierProvider.value(value: widget.findHomeTargetService),
        ChangeNotifierProvider.value(value: widget.dashboardStoreService),
      ],
      child: MaterialApp(
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          },
        ),
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
            dashboardService: widget.dashboardService,
            notificationNavigationService: widget.notificationNavigationService,
            child: Stack(
              children: [
                child ?? const SizedBox.shrink(),
                // Intercom status indicator overlay (shows when receiving transmission)
                const IntercomStatusIndicator(),
                // Connection state is shown in the dashboard app bar title area
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
  final DashboardService dashboardService;
  final NotificationNavigationService notificationNavigationService;
  final Widget child;

  const SignalKNotificationListener({
    super.key,
    required this.signalKService,
    required this.storageService,
    required this.notificationService,
    required this.dashboardService,
    required this.notificationNavigationService,
    required this.child,
  });

  @override
  State<SignalKNotificationListener> createState() => _SignalKNotificationListenerState();
}

class _SignalKNotificationListenerState extends State<SignalKNotificationListener> {
  StreamSubscription<SignalKNotification>? _notificationSubscription;
  StreamSubscription<alert_models.AlertEvent>? _snackbarSubscription;

  // Track current snackbar severity — don't let lower severity replace higher
  alert_models.AlertSeverity? _currentSnackbarSeverity;
  Timer? _snackbarSeverityTimer;

  @override
  void initState() {
    super.initState();
    _setupNotificationListener();
    _setupSnackbarListener();
  }

  void _setupSnackbarListener() {
    try {
      final coordinator = Provider.of<AlertCoordinator>(context, listen: false);
      _snackbarSubscription = coordinator.snackbarEvents.listen(showAlertEventSnackbar);
    } catch (_) {
      // Coordinator not available yet — will be set up in didChangeDependencies
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // If stream wasn't available in initState (Provider not ready), subscribe now
    if (_snackbarSubscription == null) {
      _setupSnackbarListener();
    }
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

    if (!showInApp && !showSystem) return;

    // Show system notification if enabled for this level
    if (showSystem) {
      widget.notificationService.showNotification(notification);
    }

    // Show in-app snackbar if enabled for this level
    if (showInApp) {
      _showSignalKSnackbar(notification);
    }
  }

  alert_models.AlertSeverity _mapNotificationSeverity(String state) {
    switch (state.toLowerCase()) {
      case 'emergency': return alert_models.AlertSeverity.emergency;
      case 'alarm': return alert_models.AlertSeverity.alarm;
      case 'warn': return alert_models.AlertSeverity.warn;
      case 'alert': return alert_models.AlertSeverity.alert;
      case 'normal': return alert_models.AlertSeverity.normal;
      case 'nominal': return alert_models.AlertSeverity.nominal;
      default: return alert_models.AlertSeverity.normal;
    }
  }

  /// Show a snackbar for an AlertEvent from the coordinator.
  void showAlertEventSnackbar(alert_models.AlertEvent event) {
    if (!mounted) return;

    // Don't let a lower-severity snackbar replace a higher-severity one
    if (_currentSnackbarSeverity != null &&
        event.severity < _currentSnackbarSeverity!) {
      return;
    }

    // Track current severity, clear after snackbar duration
    _currentSnackbarSeverity = event.severity;
    _snackbarSeverityTimer?.cancel();
    final duration = event.severity >= alert_models.AlertSeverity.alarm
        ? const Duration(seconds: 10)
        : const Duration(seconds: 5);
    _snackbarSeverityTimer = Timer(duration, () {
      _currentSnackbarSeverity = null;
    });

    // If the callbackData is a SignalKNotification, use the full snackbar
    if (event.callbackData is SignalKNotification) {
      _showSignalKSnackbar(event.callbackData as SignalKNotification);
      return;
    }

    // AIS Favorites: snackbar with VIEW and DISMISS
    if (event.subsystem == alert_models.AlertSubsystem.aisFavorites &&
        event.callbackData is String) {
      final vesselId = event.callbackData as String;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.favorite, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${event.title} ${event.body}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                ),
              ),
              TextButton(
                onPressed: () {
                  final favService = Provider.of<AISFavoritesService>(context, listen: false);
                  favService.requestHighlight(vesselId);
                  // Resolve so it doesn't come back
                  try {
                    final coordinator = Provider.of<AlertCoordinator>(context, listen: false);
                    coordinator.resolveAlert(event.subsystem, alarmId: event.alarmId);
                  } catch (_) {}
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
                child: const Text('VIEW', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: () {
                  try {
                    final coordinator = Provider.of<AlertCoordinator>(context, listen: false);
                    coordinator.resolveAlert(event.subsystem, alarmId: event.alarmId);
                  } catch (_) {}
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
                child: const Text('DISMISS', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
          backgroundColor: Colors.blue.shade700,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Generic snackbar for other alert types
    final colors = _severityColors(event.severity);
    final isAlarm = event.severity >= alert_models.AlertSeverity.alarm;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(colors.$2, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${event.title} ${event.body}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
              ),
            ),
            // VIEW: navigate to vessel on AIS chart (CPA alerts only)
            if (event.subsystem == alert_models.AlertSubsystem.cpa &&
                event.callbackData is CpaVesselAlert)
              TextButton(
                onPressed: () {
                  try {
                    final cpaService = Provider.of<CpaAlertService>(context, listen: false);
                    cpaService.requestHighlight((event.callbackData as CpaVesselAlert).vesselId);
                  } catch (_) {}
                  // Don't dismiss, ack, or hide — just navigate
                },
                child: const Text('VIEW', style: TextStyle(color: Colors.white70)),
              ),
            if (isAlarm) ...[
              // ACK: stop the noise, alert stays active and re-shows
              TextButton(
                onPressed: () {
                  try {
                    final coordinator = Provider.of<AlertCoordinator>(context, listen: false);
                    coordinator.acknowledgeAlarm(event.subsystem, alarmId: event.alarmId);
                  } catch (_) {}
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
                child: const Text('ACK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              // CANCEL: dismiss this alert entirely, stop tracking it
              TextButton(
                onPressed: () {
                  try {
                    final coordinator = Provider.of<AlertCoordinator>(context, listen: false);
                    coordinator.resolveAlert(event.subsystem, alarmId: event.alarmId);
                  } catch (_) {}
                  _currentSnackbarSeverity = null;
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
                child: const Text('CANCEL', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ],
        ),
        backgroundColor: colors.$1,
        duration: isAlarm
            ? const Duration(seconds: 10) : const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        action: isAlarm ? null : SnackBarAction(
          label: 'DISMISS',
          textColor: Colors.white,
          onPressed: () {
            try {
              final coordinator = Provider.of<AlertCoordinator>(context, listen: false);
              coordinator.resolveAlert(event.subsystem, alarmId: event.alarmId);
            } catch (_) {}
            _currentSnackbarSeverity = null;
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  (Color, IconData) _severityColors(alert_models.AlertSeverity severity) {
    switch (severity) {
      case alert_models.AlertSeverity.emergency: return (Colors.red.shade900, Icons.emergency);
      case alert_models.AlertSeverity.alarm: return (Colors.red.shade700, Icons.alarm);
      case alert_models.AlertSeverity.warn: return (Colors.orange.shade700, Icons.warning);
      case alert_models.AlertSeverity.alert: return (Colors.amber.shade700, Icons.info);
      case alert_models.AlertSeverity.normal: return (Colors.blue.shade700, Icons.notifications);
      case alert_models.AlertSeverity.nominal: return (Colors.green.shade700, Icons.check_circle);
    }
  }

  void _showSignalKSnackbar(SignalKNotification notification) {
    final colors = _severityColors(_mapNotificationSeverity(notification.state));

    // Extract headline from message (remove language prefix like "en-US: ")
    String headline = notification.message;
    final langMatch = RegExp(r'^[a-z]{2}(-[A-Z]{2})?: ').firstMatch(headline);
    if (langMatch != null) {
      headline = headline.substring(langMatch.end);
    }

    // Check if this is an NWS weather alert
    final isNwsAlert = notification.key.startsWith('weather.nws.');
    final alertId = isNwsAlert ? notification.key.replaceFirst('weather.nws.', '') : null;

    // Build payload and check for tap-to-navigate target
    final payload = NotificationPayload(
      type: isNwsAlert ? 'weather_nws' : 'signalk',
      notificationKey: notification.key,
      context: isNwsAlert && alertId != null ? {'alertId': alertId} : null,
    );
    final navResult = widget.notificationNavigationService.getNavigation(payload);
    final hasNavTarget = navResult != null;
    final String? targetScreenName = navResult?.$2;

    // Build tap handler
    VoidCallback? onTap;
    if (hasNavTarget) {
      onTap = () {
        navResult.$1();
        if (isNwsAlert && alertId != null) {
          WeatherAlertsNotifier.instance.requestExpandAlert(alertId);
        }
        if (notification.key.startsWith('navigation.anchor')) {
          AnchorAlarmService.instance?.acknowledgeAlarm();
        }
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      };
    } else if (isNwsAlert && alertId != null) {
      onTap = () {
        WeatherAlertsNotifier.instance.requestExpandAlert(alertId);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      };
    }

    String? hintText;
    if (hasNavTarget) {
      hintText = 'TAP: $targetScreenName';
    } else if (isNwsAlert) {
      hintText = 'TAP FOR DETAILS';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: GestureDetector(
          onTap: onTap,
          behavior: onTap != null ? HitTestBehavior.opaque : HitTestBehavior.deferToChild,
          child: Row(
            children: [
              Icon(colors.$2, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '[${notification.state.toUpperCase()}] $headline',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(notification.key, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                        ),
                        if (hintText != null)
                          Text(hintText, style: const TextStyle(fontSize: 10, color: Colors.white54, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        backgroundColor: colors.$1,
        duration: notification.state.toLowerCase() == 'emergency' || notification.state.toLowerCase() == 'alarm'
            ? const Duration(seconds: 10) : const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'DISMISS',
          textColor: Colors.white,
          onPressed: () {
            if (notification.key.startsWith('navigation.anchor')) {
              AnchorAlarmService.instance?.acknowledgeAlarm();
            }
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    _snackbarSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

