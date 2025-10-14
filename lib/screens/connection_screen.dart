import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/signalk_service.dart';
import 'dashboard_manager_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController(text: '192.168.1.88:3000');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _useSecure = false;
  bool _isConnecting = false;
  bool _requiresAuth = false;

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
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
      final service = context.read<SignalKService>();
      await service.connect(
        _serverController.text,
        secure: _useSecure,
        username: _requiresAuth ? _usernameController.text : null,
        password: _requiresAuth ? _passwordController.text : null,
      );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const DashboardManagerScreen(),
          ),
        );
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
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Requires Authentication'),
                value: _requiresAuth,
                onChanged: (value) {
                  setState(() {
                    _requiresAuth = value;
                  });
                },
              ),
              if (_requiresAuth) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (_requiresAuth && (value == null || value.isEmpty)) {
                      return 'Please enter username';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (_requiresAuth && (value == null || value.isEmpty)) {
                      return 'Please enter password';
                    }
                    return null;
                  },
                ),
              ],
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
