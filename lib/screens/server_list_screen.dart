import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/storage_service.dart';
import '../services/signalk_service.dart';
import '../services/auth_service.dart';
import '../services/dashboard_service.dart';
import '../services/setup_service.dart';
import '../models/server_connection.dart';
import 'connection_screen.dart';
import 'dashboard_manager_screen.dart';
import 'device_registration_screen.dart';

/// Screen showing list of saved SignalK server connections
class ServerListScreen extends StatefulWidget {
  const ServerListScreen({super.key});

  @override
  State<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends State<ServerListScreen> {
  bool _isConnecting = false;
  String? _connectingToId;

  Future<void> _connectToServer(ServerConnection connection) async {
    setState(() {
      _isConnecting = true;
      _connectingToId = connection.id;
    });

    try {
      final authService = context.read<AuthService>();
      final signalKService = context.read<SignalKService>();
      final dashboardService = context.read<DashboardService>();
      final storageService = context.read<StorageService>();

      // Check if we have a saved token for this connection
      final savedToken = authService.getSavedToken(connection.id);

      if (savedToken != null && savedToken.isValid) {
        // Use saved token
        await signalKService.connect(
          connection.serverUrl,
          secure: connection.useSecure,
          authToken: savedToken,
        );

        // Update last connected time
        await storageService.updateConnectionLastConnected(connection.id);

        // Save this as the last successful connection
        await storageService.saveLastConnection(
          connection.serverUrl,
          connection.useSecure,
        );

        // Set up dashboard subscriptions
        if (dashboardService.currentLayout != null) {
          await dashboardService.updateLayout(dashboardService.currentLayout!);
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
          // Generate device description with setup name or device model
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
          _connectingToId = null;
        });
      }
    }
  }

  Future<void> _deleteConnection(ServerConnection connection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Server'),
        content: Text(
          'Are you sure you want to delete "${connection.name}"?\n\n'
          'This will also remove saved authentication credentials for this connection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final storageService = context.read<StorageService>();
      await storageService.deleteConnection(connection.id);
      setState(() {}); // Refresh the list
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Server'),
        automaticallyImplyLeading: false,
      ),
      body: Consumer<StorageService>(
        builder: (context, storageService, child) {
          final connections = storageService.getAllConnections();

          if (connections.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No saved servers',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const ConnectionScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add Server'),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: connections.length,
                  itemBuilder: (context, index) {
                    final connection = connections[index];
                    final isConnecting = _isConnecting && _connectingToId == connection.id;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Icon(
                          connection.useSecure ? Icons.lock : Icons.lock_open,
                          color: connection.useSecure ? Colors.green : Colors.orange,
                        ),
                        title: Text(
                          connection.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              connection.serverUrl,
                              style: const TextStyle(fontSize: 14),
                            ),
                            if (connection.lastConnectedAt != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Last connected: ${_formatDate(connection.lastConnectedAt!)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: isConnecting
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.delete, size: 20),
                                    onPressed: () => _deleteConnection(connection),
                                    color: Colors.red[300],
                                  ),
                                ],
                              ),
                        onTap: isConnecting ? null : () => _connectToServer(connection),
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: _isConnecting
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const ConnectionScreen(),
                            ),
                          );
                        },
                  icon: const Icon(Icons.add),
                  label: const Text('Add New Server'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()}y ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()}mo ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
