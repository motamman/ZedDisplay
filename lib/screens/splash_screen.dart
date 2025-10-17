import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/signalk_service.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../services/dashboard_service.dart';
import 'connection_screen.dart';
import 'dashboard_manager_screen.dart';

/// Splash screen shown on app launch while auto-connecting
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _tryAutoConnect();
    _navigateAfterDelay();
  }

  Future<void> _tryAutoConnect() async {
    setState(() {
      _isConnecting = true;
    });

    final storageService = Provider.of<StorageService>(context, listen: false);
    final signalKService = Provider.of<SignalKService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final dashboardService = Provider.of<DashboardService>(context, listen: false);

    final lastServerUrl = storageService.getLastServerUrl();

    if (lastServerUrl != null) {
      final savedToken = authService.getSavedToken(lastServerUrl);

      if (savedToken != null && savedToken.isValid) {
        try {
          await signalKService.connect(
            lastServerUrl,
            secure: storageService.getLastUseSecure(),
            authToken: savedToken,
          );

          // Set up dashboard subscriptions
          if (dashboardService.currentLayout != null) {
            await dashboardService.updateLayout(dashboardService.currentLayout!);
          }
        } catch (e) {
          debugPrint('Auto-connect failed: $e');
        }
      }
    }

    setState(() {
      _isConnecting = false;
    });
  }

  void _navigateAfterDelay() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _navigateToNextScreen();
      }
    });
  }

  void _navigateToNextScreen() {
    if (!mounted) return;

    final signalKService = Provider.of<SignalKService>(context, listen: false);

    // Navigate to appropriate screen
    if (signalKService.isConnected) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const DashboardManagerScreen(),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const ConnectionScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Static logo
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/icon.png',
                  width: 120,
                  height: 120,
                ),
                const SizedBox(height: 24),
                const Text(
                  'ZedDisplay',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Marine Dashboard',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),

          // Connection status overlay
          if (_isConnecting)
            Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Connecting...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
