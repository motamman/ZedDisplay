import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../services/signalk_service.dart';
import '../services/storage_service.dart';
import '../services/auth_service.dart';
import '../services/dashboard_service.dart';
import '../services/foreground_service.dart';
import '../models/server_connection.dart';
import 'connection_screen.dart';
import 'device_registration_screen.dart';
import 'setup_management_screen.dart';

/// Settings screen with connection management
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _showConnections = false;
  bool _notificationsEnabled = false;

  // In-app notification level filters
  bool _showInAppEmergency = true;
  bool _showInAppAlarm = false;
  bool _showInAppWarn = false;
  bool _showInAppAlert = false;
  bool _showInAppNormal = false;
  bool _showInAppNominal = false;

  // System notification level filters (only emergency and alarm available)
  bool _showSystemEmergency = true;
  bool _showSystemAlarm = false;

  @override
  void initState() {
    super.initState();
    _loadNotificationsPreference();
  }

  Future<void> _loadNotificationsPreference() async {
    final storageService = Provider.of<StorageService>(context, listen: false);
    final signalKService = Provider.of<SignalKService>(context, listen: false);

    setState(() {
      _notificationsEnabled = storageService.getNotificationsEnabled();

      // Load in-app notification filters
      _showInAppEmergency = storageService.getInAppNotificationFilter('emergency');
      _showInAppAlarm = storageService.getInAppNotificationFilter('alarm');
      _showInAppWarn = storageService.getInAppNotificationFilter('warn');
      _showInAppAlert = storageService.getInAppNotificationFilter('alert');
      _showInAppNormal = storageService.getInAppNotificationFilter('normal');
      _showInAppNominal = storageService.getInAppNotificationFilter('nominal');

      // Load system notification filters (only emergency and alarm)
      _showSystemEmergency = storageService.getSystemNotificationFilter('emergency');
      _showSystemAlarm = storageService.getSystemNotificationFilter('alarm');
    });

    // Sync with SignalKService
    await signalKService.setNotificationsEnabled(_notificationsEnabled);
  }

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

          // Saved Connections Section (Collapsible)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dns, color: Colors.blue),
                  title: Text(
                    signalKService.isConnected ? 'Saved Connections' : 'Select Connection',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    '${storageService.getAllConnections().length} connection(s)',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      _showConnections ? Icons.expand_less : Icons.expand_more,
                    ),
                    onPressed: () {
                      setState(() {
                        _showConnections = !_showConnections;
                      });
                    },
                  ),
                  onTap: () {
                    setState(() {
                      _showConnections = !_showConnections;
                    });
                  },
                ),
                if (_showConnections) ...[
                  const Divider(height: 1),
                  _buildSavedConnectionsList(storageService, signalKService.isConnected),
                ],
              ],
            ),
          ),

          const Divider(height: 32),

          // Dashboard Setups Section
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: const Icon(Icons.dashboard_customize, color: Colors.blue),
              title: const Text(
                'Dashboard Setups',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text(
                'Save, load, and share dashboard configurations',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const SetupManagementScreen(),
                  ),
                );
              },
            ),
          ),

          const Divider(height: 32),

          // Notifications Section
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_active, color: Colors.orange),
                  title: const Text(
                    'SignalK Notifications',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: const Text(
                    'Receive and display alerts from the SignalK server',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _notificationsEnabled,
                  onChanged: (value) async {
                    setState(() {
                      _notificationsEnabled = value;
                    });

                    // Save preference
                    await storageService.saveNotificationsEnabled(value);

                    // Update SignalK subscription
                    await signalKService.setNotificationsEnabled(value);

                    // Start/stop foreground service
                    final foregroundService = ForegroundTaskService();
                    if (value && signalKService.isConnected) {
                      await foregroundService.start();
                    } else {
                      await foregroundService.stop();
                    }

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            value
                                ? 'Notifications enabled'
                                : 'Notifications disabled',
                          ),
                          backgroundColor: value ? Colors.green : Colors.orange,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
                if (_notificationsEnabled) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Notification Types',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        // Header row
                        Row(
                          children: [
                            const Expanded(flex: 2, child: SizedBox()),
                            Expanded(
                              child: Text(
                                'In-App',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'System',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                        // Emergency
                        _buildNotificationRow(
                          Icons.emergency,
                          Colors.red,
                          'Emergency',
                          _showInAppEmergency,
                          _showSystemEmergency,
                          (inApp, system) async {
                            setState(() {
                              _showInAppEmergency = inApp;
                              if (system != null) _showSystemEmergency = system;
                            });
                            await storageService.saveInAppNotificationFilter('emergency', inApp);
                            if (system != null) {
                              await storageService.saveSystemNotificationFilter('emergency', system);
                            }
                          },
                        ),
                        // Alarm
                        _buildNotificationRow(
                          Icons.alarm,
                          Colors.red.shade700,
                          'Alarm',
                          _showInAppAlarm,
                          _showSystemAlarm,
                          (inApp, system) async {
                            setState(() {
                              _showInAppAlarm = inApp;
                              if (system != null) _showSystemAlarm = system;
                            });
                            await storageService.saveInAppNotificationFilter('alarm', inApp);
                            if (system != null) {
                              await storageService.saveSystemNotificationFilter('alarm', system);
                            }
                          },
                        ),
                        // Warn (in-app only)
                        _buildNotificationRow(
                          Icons.warning,
                          Colors.orange,
                          'Warn',
                          _showInAppWarn,
                          null, // No system notification
                          (inApp, system) async {
                            setState(() {
                              _showInAppWarn = inApp;
                            });
                            await storageService.saveInAppNotificationFilter('warn', inApp);
                          },
                        ),
                        // Alert (in-app only)
                        _buildNotificationRow(
                          Icons.info,
                          Colors.amber,
                          'Alert',
                          _showInAppAlert,
                          null, // No system notification
                          (inApp, system) async {
                            setState(() {
                              _showInAppAlert = inApp;
                            });
                            await storageService.saveInAppNotificationFilter('alert', inApp);
                          },
                        ),
                        // Normal (in-app only)
                        _buildNotificationRow(
                          Icons.notifications,
                          Colors.blue,
                          'Normal',
                          _showInAppNormal,
                          null, // No system notification
                          (inApp, system) async {
                            setState(() {
                              _showInAppNormal = inApp;
                            });
                            await storageService.saveInAppNotificationFilter('normal', inApp);
                          },
                        ),
                        // Nominal (in-app only)
                        _buildNotificationRow(
                          Icons.check_circle,
                          Colors.green,
                          'Nominal',
                          _showInAppNominal,
                          null, // No system notification
                          (inApp, system) async {
                            setState(() {
                              _showInAppNominal = inApp;
                            });
                            await storageService.saveInAppNotificationFilter('nominal', inApp);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ],
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
      return const Card(
        margin: EdgeInsets.symmetric(horizontal: 16),
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            children: [
              Icon(Icons.cloud_off, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                'Not Connected',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
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
            const Row(
              children: [
                Icon(Icons.cloud_done, color: Colors.green),
                SizedBox(width: 8),
                Text(
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
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Icon(Icons.dns, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'No saved connections',
              style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a connection to get started',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _showAddConnectionDialog(storageService),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Connection'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: connections.map((connection) {
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Icon(
            connection.useSecure ? Icons.lock : Icons.dns,
            color: connection.useSecure ? Colors.green : Colors.blue,
            size: 20,
          ),
          title: Text(
            connection.name,
            style: const TextStyle(fontSize: 14),
          ),
          subtitle: Text(
            connection.serverUrl,
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.play_arrow, size: 20),
                onPressed: () => _connectToSaved(connection),
                tooltip: 'Connect',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              if (isConnected) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: () => _showEditConnectionDialog(
                    storageService,
                    connection,
                  ),
                  tooltip: 'Edit',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete, size: 18),
                  onPressed: () => _confirmDeleteConnection(
                    storageService,
                    connection,
                  ),
                  tooltip: 'Delete',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ],
          ),
          // Make the entire tile tappable to connect when not connected
          onTap: !isConnected ? () => _connectToSaved(connection) : null,
        );
      }).toList(),
    );
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

  /// Build a notification level row with in-app and system checkboxes
  Widget _buildNotificationRow(
    IconData icon,
    Color iconColor,
    String label,
    bool inAppValue,
    bool? systemValue, // null means no system checkbox
    Function(bool inApp, bool? system) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Expanded(
            child: Checkbox(
              value: inAppValue,
              onChanged: (value) {
                onChanged(value ?? false, systemValue);
              },
            ),
          ),
          Expanded(
            child: systemValue != null
                ? Checkbox(
                    value: systemValue,
                    onChanged: (value) {
                      onChanged(inAppValue, value ?? false);
                    },
                  )
                : const SizedBox(), // Empty space for consistency
          ),
        ],
      ),
    );
  }

}
