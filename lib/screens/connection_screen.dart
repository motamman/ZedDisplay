import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../services/signalk_service.dart';
import '../services/auth_service.dart';
import '../services/dashboard_service.dart';
import '../services/storage_service.dart';
import '../services/setup_service.dart';
import '../models/server_connection.dart';
import '../models/auth_token.dart';
import '../utils/conversion_utils.dart';
import 'dashboard_manager_screen.dart';
import 'device_registration_screen.dart';
import 'user_login_screen.dart';
import 'settings_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _serverController = TextEditingController(text: '192.168.1.88:3000');
  bool _useSecure = false;
  bool _isConnecting = false;
  String _clientId = '';
  bool _autoConnecting = false;

  @override
  void initState() {
    super.initState();
    // Generate or load client ID
    final authService = Provider.of<AuthService>(context, listen: false);
    _clientId = authService.generateClientId();

    // Try auto-connect if we have saved connection
    _tryAutoConnect();
  }

  Future<void> _tryAutoConnect() async {
    final storageService = Provider.of<StorageService>(context, listen: false);
    final lastServerUrl = storageService.getLastServerUrl();

    if (lastServerUrl != null) {
      setState(() {
        _autoConnecting = true;
        _serverController.text = lastServerUrl;
        _useSecure = storageService.getLastUseSecure();
      });

      // Wait a moment for UI to settle
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        await _connect(silent: true);
      }

      if (mounted) {
        setState(() {
          _autoConnecting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _connect({bool silent = false}) async {
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
      final storageService = context.read<StorageService>();

      // First, find or create the connection in storage
      final existingConnection = storageService.findConnectionByUrl(_serverController.text);
      ServerConnection connection;

      if (existingConnection != null) {
        // Update existing connection
        connection = existingConnection.copyWith(
          name: _nameController.text.trim().isEmpty
              ? existingConnection.name
              : _nameController.text.trim(),
          useSecure: _useSecure,
        );
      } else {
        // Create new connection
        connection = ServerConnection(
          id: const Uuid().v4(),
          name: _nameController.text.trim().isEmpty
              ? _serverController.text
              : _nameController.text.trim(),
          serverUrl: _serverController.text,
          useSecure: _useSecure,
          createdAt: DateTime.now(),
        );
      }

      await storageService.saveConnection(connection);

      // Check if we have a saved token for this connection (keyed by connection.id)
      final savedToken = authService.getSavedToken(connection.id);

      if (savedToken != null && savedToken.isValid) {
        // Use saved token
        await signalKService.connect(
          _serverController.text,
          secure: _useSecure,
          authToken: savedToken,
        );

        // Update last connected time
        await storageService.updateConnectionLastConnected(connection.id);

        // Save this as the last successful connection
        await storageService.saveLastConnection(
          _serverController.text,
          _useSecure,
        );

        // If user auth, load user preferences
        if (savedToken.authType == AuthType.user) {
          await signalKService.fetchUserUnitPreferences();
          ConversionUtils.loadUserPreferences(signalKService);
        }

        // Trigger dashboard subscription update (happens automatically in DashboardService)
        // Force an update to ensure subscriptions are set up
        await dashboardService.updateLayout(dashboardService.currentLayout!);

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const DashboardManagerScreen(),
            ),
          );
        }
      } else {
        // No saved token, offer choice of auth methods
        if (mounted) {
          await _showAuthMethodDialog(connection, authService);
        }
      }
    } catch (e) {
      if (mounted && !silent) {
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

  Future<void> _showAuthMethodDialog(ServerConnection connection, AuthService authService) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Authentication'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('How would you like to authenticate?'),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.person, color: Colors.blue),
              title: const Text('User Login'),
              subtitle: const Text('Personal unit preferences'),
              onTap: () => Navigator.pop(context, 'user'),
            ),
            ListTile(
              leading: const Icon(Icons.devices, color: Colors.green),
              title: const Text('Device Auth'),
              subtitle: const Text('Server-wide settings'),
              onTap: () => Navigator.pop(context, 'device'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (result == 'user' && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => UserLoginScreen(
            serverUrl: connection.serverUrl,
            secure: connection.useSecure,
            connectionId: connection.id,
          ),
        ),
      );
    } else if (result == 'device' && mounted) {
      final setupService = Provider.of<SetupService>(context, listen: false);
      final setupName = await setupService.getActiveSetupName();
      final description = await AuthService.generateDeviceDescription(setupName: setupName);

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DeviceRegistrationScreen(
              serverUrl: connection.serverUrl,
              secure: connection.useSecure,
              clientId: authService.generateClientId(),
              description: description,
              connectionId: connection.id,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to SignalK'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
              Image.asset(
                'assets/icon.png',
                width: 120,
                height: 120,
              ),
              const SizedBox(height: 24),
              const Text(
                'ZedDisplay +SignalK',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'SignalK data visualization',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Connection Name (optional)',
                  hintText: 'My Boat',
                  prefixIcon: Icon(Icons.label),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
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
              if (_autoConnecting)
                const Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Auto-connecting to saved server...',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: _isConnecting ? null : () => _connect(),
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
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isConnecting
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const SettingsScreen(
                                    showConnections: true,
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.list),
                      label: const Text('Other Connections'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ],
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
        ),
      ),
    );
  }
}
