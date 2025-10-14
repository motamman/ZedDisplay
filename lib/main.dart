import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/signalk_service.dart';
import 'services/storage_service.dart';
import 'services/tool_registry.dart';
import 'services/template_service.dart';
import 'screens/connection_screen.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize storage service
  final storageService = StorageService();
  await storageService.initialize();

  // Initialize template service
  final templateService = TemplateService(storageService);
  await templateService.initialize();

  // Register all built-in tool types
  final toolRegistry = ToolRegistry();
  toolRegistry.registerDefaults();

  runApp(ZedDisplayApp(
    storageService: storageService,
    templateService: templateService,
  ));
}

class ZedDisplayApp extends StatelessWidget {
  final StorageService storageService;
  final TemplateService templateService;

  const ZedDisplayApp({
    super.key,
    required this.storageService,
    required this.templateService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: storageService),
        ChangeNotifierProvider.value(value: templateService),
        ChangeNotifierProvider(create: (_) => SignalKService()),
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
