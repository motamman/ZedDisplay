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
      debugPrint('Wakelock enabled - keeping connection alive');
    } else {
      // Disable wakelock when disconnected to save battery
      WakelockPlus.disable();
      debugPrint('Wakelock disabled');
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
      ),
    );
  }
}
