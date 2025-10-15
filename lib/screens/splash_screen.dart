import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import '../services/signalk_service.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../services/dashboard_service.dart';
import 'connection_screen.dart';
import 'dashboard_manager_screen.dart';

/// Splash screen that plays a video once on app launch
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
    _tryAutoConnect();
  }

  Future<void> _initializeVideo() async {
    try {
      _controller = VideoPlayerController.asset('assets/splash.mp4');
      await _controller!.initialize();
      setState(() {
        _isInitialized = true;
      });

      // Play the video once
      _controller!.play();

      // Listen for video completion
      _controller!.addListener(_checkVideoCompleted);
    } catch (e) {
      debugPrint('Error loading splash video: $e');
      setState(() {
        _hasError = true;
      });
      // If video fails, navigate after a short delay
      _navigateAfterDelay();
    }
  }

  void _checkVideoCompleted() {
    if (_controller != null && !_controller!.value.isPlaying) {
      // Video has finished playing
      _controller!.removeListener(_checkVideoCompleted);
      _navigateToNextScreen();
    }
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
  void dispose() {
    _controller?.removeListener(_checkVideoCompleted);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Video player or fallback
          if (_isInitialized && _controller != null)
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            )
          else if (_hasError)
            // Fallback UI if video fails to load
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.sailing,
                    size: 120,
                    color: Colors.blue[300],
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
            )
          else
            // Loading indicator while video initializes
            const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
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
