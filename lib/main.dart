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
import 'services/alert_coordinator.dart';
import 'services/ais_favorites_service.dart';
import 'services/cpa_alert_service.dart';
import 'widgets/alert_panel.dart';
import 'services/find_home_target_service.dart';
import 'services/dashboard_store_service.dart';
import 'services/chart_tile_cache_service.dart';
import 'services/chart_tile_server_service.dart';
import 'services/chart_download_manager.dart';
import 'services/route_planner_auth_service.dart';
import 'services/weather_routing_service.dart';
import 'models/alert_event.dart' as alert_models;

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

  // Initialize chart tile cache and local proxy server
  final chartTileCacheService = ChartTileCacheService();
  await chartTileCacheService.initialize();
  final chartTileServerService = ChartTileServerService(cacheService: chartTileCacheService);
  await chartTileServerService.start();
  final chartDownloadManager = ChartDownloadManager(cacheService: chartTileCacheService);

  // Route planner auth + weather routing service (surfaces the router
  // API inside the chart plotter)
  final routePlannerAuthService = RoutePlannerAuthService(storageService);
  final weatherRoutingService = WeatherRoutingService(routePlannerAuthService);

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
    chartTileCacheService: chartTileCacheService,
    chartTileServerService: chartTileServerService,
    chartDownloadManager: chartDownloadManager,
    routePlannerAuthService: routePlannerAuthService,
    weatherRoutingService: weatherRoutingService,
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
  final ChartTileCacheService chartTileCacheService;
  final ChartTileServerService chartTileServerService;
  final ChartDownloadManager chartDownloadManager;
  final RoutePlannerAuthService routePlannerAuthService;
  final WeatherRoutingService weatherRoutingService;

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
    required this.chartTileCacheService,
    required this.chartTileServerService,
    required this.chartDownloadManager,
    required this.routePlannerAuthService,
    required this.weatherRoutingService,
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
        ChangeNotifierProvider.value(value: widget.chartTileCacheService),
        ChangeNotifierProvider.value(value: widget.chartTileServerService),
        ChangeNotifierProvider.value(value: widget.chartDownloadManager),
        ChangeNotifierProvider.value(value: widget.routePlannerAuthService),
        ChangeNotifierProvider.value(value: widget.weatherRoutingService),
        Provider<NotificationNavigationService>.value(value: widget.notificationNavigationService),
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
            child: Stack(
              children: [
                child ?? const SizedBox.shrink(),
                // Intercom status indicator overlay (shows when receiving transmission)
                const IntercomStatusIndicator(),
                // Persistent alert panel — renders all active alerts as stacked rows
                const AlertPanel(),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Widget that listens to SignalK notifications and routes them through AlertCoordinator.
/// Replaces legacy snackbar display — alerts now render in the persistent AlertPanel.
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
  AlertCoordinator? _coordinator;

  /// Notification key prefixes owned by dedicated subsystems.
  /// These submit their own alerts — skip to prevent duplicates.
  static const _ownedPrefixes = [
    'navigation.anchor',  // AnchorAlarmService → AlertSubsystem.anchorAlarm
    'weather.nws',        // WeatherAlertsNotifier → AlertSubsystem.nwsWeather
  ];

  @override
  void initState() {
    super.initState();
    try {
      _coordinator = Provider.of<AlertCoordinator>(context, listen: false);
    } catch (_) {}
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
    if (!mounted || _coordinator == null) return;

    // Skip notifications owned by dedicated subsystems
    for (final prefix in _ownedPrefixes) {
      if (notification.key.startsWith(prefix)) return;
    }

    final severity = _mapSeverity(notification.state);

    // "normal" / "nominal" = condition cleared → resolve active alert
    if (severity == alert_models.AlertSeverity.normal ||
        severity == alert_models.AlertSeverity.nominal) {
      _coordinator!.resolveAlert(
        alert_models.AlertSubsystem.signalk,
        alarmId: notification.key,
        internal: true,
      );
      return;
    }

    // Extract headline (strip language prefix like "en-US: ")
    final headline = _extractHeadline(notification.message);

    // SignalK "method" field tells us if sound is requested
    final wantsSound = notification.method.contains('sound');

    _coordinator!.submitAlert(alert_models.AlertEvent(
      subsystem: alert_models.AlertSubsystem.signalk,
      severity: severity,
      title: notification.key,
      body: headline,
      alarmId: notification.key,
      alarmSource: 'signalk',
      wantsSystemNotification: true,
      wantsAudio: wantsSound && severity >= alert_models.AlertSeverity.alarm,
      alarmSound: 'foghorn',
      callbackData: NotificationPayload(
        type: 'signalk',
        notificationKey: notification.key,
      ),
    ));
  }

  static alert_models.AlertSeverity _mapSeverity(String state) {
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

  static String _extractHeadline(String message) {
    final langMatch = RegExp(r'^[a-z]{2}(-[A-Z]{2})?: ').firstMatch(message);
    return langMatch != null ? message.substring(langMatch.end) : message;
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

