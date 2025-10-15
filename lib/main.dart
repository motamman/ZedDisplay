import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/signalk_service.dart';
import 'services/storage_service.dart';
import 'services/dashboard_service.dart';
import 'services/tool_registry.dart';
import 'services/template_service.dart';
import 'services/auth_service.dart';
import 'screens/connection_screen.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize storage service
  final storageService = StorageService();
  await storageService.initialize();

  // Initialize SignalK service (will connect later)
  final signalKService = SignalKService();

  // Initialize dashboard service with SignalK service
  final dashboardService = DashboardService(storageService, signalKService);
  await dashboardService.initialize();

  // Initialize template service
  final templateService = TemplateService(storageService);
  await templateService.initialize();

  // Initialize auth service
  final authService = AuthService(storageService);

  // Register all built-in tool types
  final toolRegistry = ToolRegistry();
  toolRegistry.registerDefaults();

  runApp(ZedDisplayApp(
    storageService: storageService,
    signalKService: signalKService,
    dashboardService: dashboardService,
    templateService: templateService,
    authService: authService,
  ));
}

class ZedDisplayApp extends StatelessWidget {
  final StorageService storageService;
  final SignalKService signalKService;
  final DashboardService dashboardService;
  final TemplateService templateService;
  final AuthService authService;

  const ZedDisplayApp({
    super.key,
    required this.storageService,
    required this.signalKService,
    required this.dashboardService,
    required this.templateService,
    required this.authService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: storageService),
        ChangeNotifierProvider.value(value: signalKService),
        ChangeNotifierProvider.value(value: dashboardService),
        ChangeNotifierProvider.value(value: templateService),
        ChangeNotifierProvider.value(value: authService),
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
        themeMode: ThemeMode.system,
        home: const ConnectionScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
