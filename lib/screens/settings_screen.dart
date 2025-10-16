import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../services/signalk_service.dart';
import '../services/storage_service.dart';
import '../services/auth_service.dart';
import '../services/dashboard_service.dart';
import '../models/server_connection.dart';
import 'connection_screen.dart';
import 'device_registration_screen.dart';
import 'autopilot_compass_demo.dart';

/// Settings screen with connection management
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final signalKService = Provider.of<SignalKService>(context);
    final storageService = Provider.of<StorageService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // Current Connection Section (only show when connected)
          if (signalKService.isConnected) ...[
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Current Connection',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _buildCurrentConnectionCard(signalKService, storageService),
            const Divider(height: 32),
          ],

          // Saved Connections Section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              signalKService.isConnected ? 'Saved Connections' : 'Select Connection',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _buildSavedConnectionsList(storageService, signalKService.isConnected),

          const Divider(height: 32),

          // Demos Section
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Demos',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: ListTile(
              leading: const Icon(Icons.explore, color: Colors.blue),
              title: const Text('Autopilot Compass'),
              subtitle: const Text('Test the new Syncfusion-based compass widget'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const AutopilotCompassDemo(),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 80),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddConnectionDialog(storageService),
        icon: const Icon(Icons.add),
        label: const Text('Add Connection'),
      ),
    );
  }

  Widget _buildCurrentConnectionCard(
    SignalKService signalKService,
    StorageService storageService,
  ) {
    if (!signalKService.isConnected) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
              const SizedBox(height: 8),
              const Text(
                'Not Connected',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'No active connection to a SignalK server',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_done, color: Colors.green),
                const SizedBox(width: 8),
                const Text(
                  'Connected',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow('Server', signalKService.serverUrl),
            _buildInfoRow(
              'Protocol',
              signalKService.useSecureConnection ? 'HTTPS/WSS' : 'HTTP/WS',
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _disconnect(signalKService, storageService),
                icon: const Icon(Icons.logout),
                label: const Text('Disconnect'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedConnectionsList(StorageService storageService, bool isConnected) {
    final connections = storageService.getAllConnections();

    if (connections.isEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            children: [
              Icon(Icons.dns, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No saved connections',
                style: TextStyle(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Add a connection to get started',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _showAddConnectionDialog(storageService),
                icon: const Icon(Icons.add),
                label: const Text('Add Connection'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: connections.map((connection) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: Icon(
              Icons.dns,
              color: connection.useSecure ? Colors.green : Colors.blue,
            ),
            title: Text(connection.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(connection.serverUrl),
                if (connection.lastConnectedAt != null)
                  Text(
                    'Last connected: ${_formatDateTime(connection.lastConnectedAt!)}',
                    style: const TextStyle(fontSize: 10),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.play_arrow),
                  onPressed: () => _connectToSaved(connection),
                  tooltip: 'Connect',
                ),
                if (isConnected) ...[
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _showEditConnectionDialog(
                      storageService,
                      connection,
                    ),
                    tooltip: 'Edit',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _confirmDeleteConnection(
                      storageService,
                      connection,
                    ),
                    tooltip: 'Delete',
                  ),
                ],
              ],
            ),
            // Make the entire tile tappable to connect when not connected
            onTap: !isConnected ? () => _connectToSaved(connection) : null,
          ),
        );
      }).toList(),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  Future<void> _disconnect(
    SignalKService signalKService,
    StorageService storageService,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect'),
        content: const Text(
          'Are you sure you want to disconnect from the SignalK server?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      signalKService.disconnect();

      // Clear last connection
      await storageService.clearLastConnection();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Disconnected from server'),
            backgroundColor: Colors.orange,
          ),
        );

        // Navigate back to connection screen
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const ConnectionScreen()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _connectToSaved(ServerConnection connection) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final signalKService = Provider.of<SignalKService>(context, listen: false);
    final storageService = Provider.of<StorageService>(context, listen: false);
    final dashboardService = Provider.of<DashboardService>(context, listen: false);

    // Check if we have a saved token
    final savedToken = authService.getSavedToken(connection.serverUrl);

    try {
      if (savedToken != null && savedToken.isValid) {
        // Connect to the saved connection (disconnect is handled internally)
        await signalKService.connect(
          connection.serverUrl,
          secure: connection.useSecure,
          authToken: savedToken,
        );

        // Update last connected time
        await storageService.updateConnectionLastConnected(connection.id);

        // Save as last connection
        await storageService.saveLastConnection(
          connection.serverUrl,
          connection.useSecure,
        );

        // Trigger dashboard subscription update to ensure subscriptions are set up
        if (dashboardService.currentLayout != null) {
          await dashboardService.updateLayout(dashboardService.currentLayout!);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connected to ${connection.name}'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop();
        }
      } else {
        // No saved token, start device registration
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => DeviceRegistrationScreen(
                serverUrl: connection.serverUrl,
                secure: connection.useSecure,
                clientId: authService.generateClientId(),
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
    }
  }

  Future<void> _showAddConnectionDialog(StorageService storageService) async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    bool useSecure = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Connection'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Connection Name',
                    hintText: 'My Boat',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: '192.168.1.88:3000',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Use Secure Connection (HTTPS/WSS)'),
                  value: useSecure,
                  onChanged: (value) {
                    setState(() {
                      useSecure = value;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty ||
                    urlController.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final connection = ServerConnection(
        id: const Uuid().v4(),
        name: nameController.text.trim(),
        serverUrl: urlController.text.trim(),
        useSecure: useSecure,
        createdAt: DateTime.now(),
      );

      await storageService.saveConnection(connection);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection "${connection.name}" added'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {});
      }
    }
  }

  Future<void> _showEditConnectionDialog(
    StorageService storageService,
    ServerConnection connection,
  ) async {
    final nameController = TextEditingController(text: connection.name);
    final urlController = TextEditingController(text: connection.serverUrl);
    bool useSecure = connection.useSecure;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Connection'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Connection Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Use Secure Connection (HTTPS/WSS)'),
                  value: useSecure,
                  onChanged: (value) {
                    setState(() {
                      useSecure = value;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty ||
                    urlController.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final updatedConnection = connection.copyWith(
        name: nameController.text.trim(),
        serverUrl: urlController.text.trim(),
        useSecure: useSecure,
      );

      await storageService.saveConnection(updatedConnection);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection "${updatedConnection.name}" updated'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {});
      }
    }
  }

  Future<void> _confirmDeleteConnection(
    StorageService storageService,
    ServerConnection connection,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Connection'),
        content: Text(
          'Are you sure you want to delete "${connection.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await storageService.deleteConnection(connection.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection "${connection.name}" deleted'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() {});
      }
    }
  }
}
