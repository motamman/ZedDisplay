import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/signalk_service.dart';
import '../services/auth_service.dart';
import '../services/dashboard_service.dart';
import 'dashboard_manager_screen.dart';
import 'device_registration_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController(text: '192.168.1.88:3000');
  bool _useSecure = false;
  bool _isConnecting = false;
  String _clientId = '';

  @override
  void initState() {
    super.initState();
    // Generate or load client ID
    final authService = Provider.of<AuthService>(context, listen: false);
    _clientId = authService.generateClientId();
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    try {
      final authService = context.read<AuthService>();
      final signalKService = context.read<SignalKService>();
      final dashboardService = context.read<DashboardService>();

      // Check if we have a saved token
      final savedToken = authService.getSavedToken(_serverController.text);

      if (savedToken != null && savedToken.isValid) {
        // Use saved token
        await signalKService.connect(
          _serverController.text,
          secure: _useSecure,
          authToken: savedToken,
        );

        // After successful connection, subscribe to dashboard paths
        final paths = dashboardService.currentLayout?.getAllRequiredPaths() ?? [];
        if (paths.isNotEmpty) {
          await signalKService.setActiveTemplatePaths(paths);
        }

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const DashboardManagerScreen(),
            ),
          );
        }
      } else {
        // No saved token, start device registration
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => DeviceRegistrationScreen(
                serverUrl: _serverController.text,
                secure: _useSecure,
                clientId: _clientId,
                description: 'ZedDisplay Marine Dashboard',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to SignalK'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.sailing,
                size: 80,
                color: Colors.blue,
              ),
              const SizedBox(height: 32),
              const Text(
                'SignalK Display',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Marine data visualization',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              TextFormField(
                controller: _serverController,
                decoration: const InputDecoration(
                  labelText: 'SignalK Server',
                  hintText: 'demo.signalk.org or localhost:3000',
                  prefixIcon: Icon(Icons.dns),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a server address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Use Secure Connection (HTTPS/WSS)'),
                value: _useSecure,
                onChanged: (value) {
                  setState(() {
                    _useSecure = value;
                  });
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isConnecting ? null : _connect,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isConnecting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Connect',
                        style: TextStyle(fontSize: 18),
                      ),
              ),
              const SizedBox(height: 16),
              const Text(
                'The app will request access to the SignalK server.\nApprove the request in the server Admin UI.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Tip: Use demo.signalk.org to try with sample data',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
