import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/signalk_service.dart';
import 'screens/connection_screen.dart';

void main() {
  runApp(const ZedDisplayApp());
}

class ZedDisplayApp extends StatelessWidget {
  const ZedDisplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SignalKService(),
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
