import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/setup_service.dart';
import '../services/dashboard_service.dart';
import '../services/file_share_service.dart';
import '../services/crew_service.dart';
import '../services/signalk_service.dart';
import '../services/dashboard_store_service.dart';
import '../services/bundled_dashboard_service.dart';
import '../models/dashboard_setup.dart';

/// Screen for managing saved dashboard setups
class SetupManagementScreen extends StatefulWidget {
  const SetupManagementScreen({super.key});

  @override
  State<SetupManagementScreen> createState() => _SetupManagementScreenState();
}

class _SetupManagementScreenState extends State<SetupManagementScreen> {
  List<BundledDashboardInfo>? _bundledDashboards;
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    _loadBundledDashboards();
    _fetchServerDashboards();
  }

  Future<void> _loadBundledDashboards() async {
    final dashboards = await BundledDashboardService.getAvailableDashboards();
    if (mounted) {
      setState(() => _bundledDashboards = dashboards);
    }
  }

  Future<void> _fetchServerDashboards() async {
    final signalK = Provider.of<SignalKService>(context, listen: false);
    if (!signalK.isConnected) return;
    final storeService =
        Provider.of<DashboardStoreService>(context, listen: false);
    await storeService.fetchFromServer();
  }

  @override
  Widget build(BuildContext context) {
    final setupService = Provider.of<SetupService>(context);
    final savedSetups = setupService.getSavedSetups();
    final signalK = Provider.of<SignalKService>(context);
    final isConnected = signalK.isConnected;
    final storeService = Provider.of<DashboardStoreService>(context);
    final serverDashboards = storeService.serverDashboards;
    final bundled = _bundledDashboards ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboards'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            onPressed: _importSetup,
            tooltip: 'Import from File',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: _onAdminMenuSelected,
            itemBuilder: (context) => [
              if (isConnected) ...[
                const PopupMenuItem(
                  value: 'sync_bundled',
                  child: ListTile(
                    leading: Icon(Icons.cloud_upload),
                    title: Text('Sync Bundled to Server'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      body: _isApplying
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading dashboard...'),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // --- My Dashboards ---
                _buildSectionHeader(
                    'My Dashboards', Icons.folder, '${savedSetups.length}'),
                const SizedBox(height: 8),
                if (savedSetups.isEmpty)
                  _buildEmptyHint('No saved dashboards yet')
                else
                  ...savedSetups.map(_buildSetupCard),

                const SizedBox(height: 24),

                // --- Bundled Dashboards ---
                _buildSectionHeader(
                    'Bundled Templates', Icons.inventory_2, '${bundled.length}'),
                const SizedBox(height: 8),
                if (bundled.isEmpty)
                  _buildEmptyHint('No bundled dashboards')
                else
                  ...bundled.map(_buildBundledCard),

                // --- Server Dashboards ---
                if (isConnected) ...[
                  const SizedBox(height: 24),
                  _buildSectionHeader('Server Dashboards', Icons.cloud,
                      '${serverDashboards.length}'),
                  const SizedBox(height: 8),
                  if (storeService.isFetching)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (serverDashboards.isEmpty)
                    _buildEmptyHint('No dashboards on server')
                  else
                    ...serverDashboards.map(_buildServerCard),
                ],

                // Bottom padding for FABs
                const SizedBox(height: 120),
              ],
            ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            onPressed: _createNewDashboard,
            heroTag: 'new_dashboard',
            icon: const Icon(Icons.add),
            label: const Text('New Dashboard'),
          ),
          const SizedBox(height: 16),
          FloatingActionButton.extended(
            onPressed: _saveCurrentSetup,
            heroTag: 'save_current',
            icon: const Icon(Icons.save),
            label: const Text('Save Current As'),
          ),
        ],
      ),
    );
  }

  // --- Section builders ---

  Widget _buildSectionHeader(String title, IconData icon, String count) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(width: 8),
        Text(count, style: TextStyle(fontSize: 14, color: Colors.grey[500])),
      ],
    );
  }

  Widget _buildEmptyHint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Text(text, style: TextStyle(color: Colors.grey[500])),
    );
  }

  // --- Local setup card (existing) ---

  Widget _buildSetupCard(SavedSetup setup) {
    final dashboardService =
        Provider.of<DashboardService>(context, listen: false);
    final isActive = dashboardService.currentLayout?.id == setup.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              Icons.dashboard,
              color: isActive ? Colors.green : Colors.blue,
              size: 32,
            ),
            title: Text(
              setup.name,
              style: TextStyle(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (setup.description.isNotEmpty)
                  Text(setup.description,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${setup.screenCount} screens, ${setup.toolCount} tools',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    if (setup.intendedUse != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          setup.intendedUse!,
                          style:
                              TextStyle(fontSize: 10, color: Colors.blue[700]),
                        ),
                      ),
                    ],
                  ],
                ),
                if (setup.lastUsedAt != null)
                  Text(
                    'Last used: ${_formatDateTime(setup.lastUsedAt!)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
              ],
            ),
            trailing: isActive
                ? const Chip(
                    label: Text('Active', style: TextStyle(fontSize: 11)),
                    backgroundColor: Colors.green,
                    labelStyle: TextStyle(color: Colors.white),
                  )
                : null,
            onTap: isActive ? null : () => _confirmLoadSetup(setup),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isActive)
                  TextButton.icon(
                    onPressed: () => _confirmLoadSetup(setup),
                    icon: const Icon(Icons.swap_horiz, size: 16),
                    label: const Text('Switch'),
                  ),
                TextButton.icon(
                  onPressed: () => _shareSetup(setup),
                  icon: const Icon(Icons.share, size: 16),
                  label: const Text('Share'),
                ),
                TextButton.icon(
                  onPressed: () => _editSetup(setup),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Edit'),
                ),
                if (!isActive)
                  TextButton.icon(
                    onPressed: () => _confirmDeleteSetup(setup),
                    icon:
                        const Icon(Icons.delete, size: 16, color: Colors.red),
                    label: const Text('Delete',
                        style: TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Bundled dashboard card ---

  Widget _buildBundledCard(BundledDashboardInfo info) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading:
            const Icon(Icons.dashboard_customize, color: Colors.teal, size: 32),
        title: Text(info.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (info.description.isNotEmpty)
              Text(info.description,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    info.categoryName,
                    style: TextStyle(fontSize: 10, color: Colors.teal[700]),
                  ),
                ),
                if (info.isDefault) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Recommended',
                      style: TextStyle(fontSize: 10, color: Colors.green[700]),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _loadBundledDashboard(info),
      ),
    );
  }

  // --- Server dashboard card ---

  Widget _buildServerCard(ServerDashboardInfo info) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading:
            const Icon(Icons.cloud_download, color: Colors.indigo, size: 32),
        title: Text(info.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (info.description.isNotEmpty)
              Text(info.description,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(
              children: [
                if (info.screenCount > 0 || info.toolCount > 0)
                  Text(
                    '${info.screenCount} screens, ${info.toolCount} tools',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                if (info.uploadedBy != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    'by ${info.uploadedBy}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: Colors.red[300],
              onPressed: () => _confirmDeleteServerDashboard(info),
              tooltip: 'Delete from server',
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => _loadServerDashboard(info),
      ),
    );
  }

  // --- Actions: load bundled / server dashboard ---

  Future<void> _loadBundledDashboard(BundledDashboardInfo info) async {
    final confirmed = await _confirmLoad(info.name);
    if (confirmed != true || !mounted) return;

    setState(() => _isApplying = true);

    try {
      final jsonString =
          await BundledDashboardService.loadDashboardJson(info);
      final setupService =
          Provider.of<SetupService>(context, listen: false);
      final result = await setupService.importAndLoadSetup(jsonString);

      if (!mounted) return;

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Loaded "${result.setupName ?? info.name}"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  Future<void> _loadServerDashboard(ServerDashboardInfo info) async {
    if (info.zedjson.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dashboard has no content'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await _confirmLoad(info.name);
    if (confirmed != true || !mounted) return;

    setState(() => _isApplying = true);

    try {
      final setupService =
          Provider.of<SetupService>(context, listen: false);
      final result = await setupService.importAndLoadSetup(info.zedjson);

      if (!mounted) return;

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Loaded "${result.setupName ?? info.name}"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  Future<bool?> _confirmLoad(String name) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Load Dashboard'),
        content:
            Text('Load "$name"?\n\nThis will replace your current dashboard.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Load'),
          ),
        ],
      ),
    );
  }

  // --- Admin actions ---

  Future<void> _onAdminMenuSelected(String value) async {
    switch (value) {
      case 'sync_bundled':
        await _syncBundledToServer();
        break;
    }
  }

  Future<void> _syncBundledToServer() async {
    final storeService =
        Provider.of<DashboardStoreService>(context, listen: false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Syncing bundled dashboards...'),
          ],
        ),
      ),
    );

    try {
      final count = await storeService.syncBundledToServer();

      if (!mounted) return;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(count > 0
              ? '$count dashboard(s) pushed to server'
              : 'All bundled dashboards already on server'),
          backgroundColor: count > 0 ? Colors.green : Colors.blue,
        ),
      );
      setState(() {}); // refresh server section
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error syncing: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmDeleteServerDashboard(ServerDashboardInfo db) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Server Dashboard'),
        content: Text('Delete "${db.name}" from the server?'),
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

    if (confirmed == true && mounted) {
      final storeService =
          Provider.of<DashboardStoreService>(context, listen: false);
      final success = await storeService.deleteFromServer(db.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? '"${db.name}" deleted from server'
                : 'Failed to delete from server'),
            backgroundColor: success ? Colors.orange : Colors.red,
          ),
        );
      }
    }
  }

  // --- Existing local setup actions (unchanged) ---

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

  Future<void> _saveCurrentSetup() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Current As'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Setup Name',
                  hintText: 'My Sailing Setup',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'Dashboard configuration for sailing',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
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
              if (nameController.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        final setupService =
            Provider.of<SetupService>(context, listen: false);
        await setupService.saveCurrentAsSetup(
          name: nameController.text.trim(),
          description: descriptionController.text.trim(),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Setup "${nameController.text.trim()}" saved'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {});
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving setup: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _createNewDashboard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Dashboard'),
        content: const Text(
          'This will clear your current dashboard and create a blank one.\n\n'
          'Make sure to save your current dashboard first if you want to keep it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create Blank Dashboard'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final dashboardService =
            Provider.of<DashboardService>(context, listen: false);
        final setupService =
            Provider.of<SetupService>(context, listen: false);

        await dashboardService.createNewDashboard();

        await setupService.saveCurrentAsSetup(
          name: 'New Dashboard',
          description: 'Blank dashboard',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('New blank dashboard created and saved'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error creating new dashboard: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _confirmLoadSetup(SavedSetup setup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch Setup'),
        content: Text(
          'Switch to "${setup.name}"?\n\nThis will replace your current dashboard configuration.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final setupService =
            Provider.of<SetupService>(context, listen: false);
        await setupService.loadSetup(setup.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Switched to "${setup.name}"'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {});
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error loading setup: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _shareSetup(SavedSetup setupRef) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share Dashboard'),
        content: const Text('How would you like to share this dashboard?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, 'crew'),
            icon: const Icon(Icons.people),
            label: const Text('Share with Crew'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, 'external'),
            icon: const Icon(Icons.share),
            label: const Text('Share via...'),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'crew') {
      await _shareWithCrew(setupRef);
    } else {
      await _shareExternal(setupRef);
    }
  }

  Future<void> _shareWithCrew(SavedSetup setupRef) async {
    try {
      final setupService =
          Provider.of<SetupService>(context, listen: false);
      final fileShareService =
          Provider.of<FileShareService>(context, listen: false);
      final crewService =
          Provider.of<CrewService>(context, listen: false);

      if (!crewService.hasProfile) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Create a crew profile first to share with crew'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final dashboardService =
          Provider.of<DashboardService>(context, listen: false);
      final isActive = dashboardService.currentLayout?.id == setupRef.id;

      DashboardSetup setup;
      if (isActive) {
        setup = setupService.exportCurrentSetup(
          name: setupRef.name,
          description: setupRef.description,
        );
      } else {
        await setupService.loadSetup(setupRef.id);
        setup = setupService.exportCurrentSetup(
          name: setupRef.name,
          description: setupRef.description,
        );
      }

      final jsonString = setupService.exportToJson(setup);
      final bytes = Uint8List.fromList(jsonString.codeUnits);
      final filename =
          '${setupRef.name.replaceAll(RegExp(r'[^\w\s-]'), '_')}.zedjson';

      final success = await fileShareService.shareBytes(
        bytes: bytes,
        filename: filename,
        mimeType: 'application/json',
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"${setupRef.name}" shared with crew'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Failed to share with crew. Check SignalK connection.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing with crew: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _shareExternal(SavedSetup setupRef) async {
    try {
      final setupService =
          Provider.of<SetupService>(context, listen: false);

      final dashboardService =
          Provider.of<DashboardService>(context, listen: false);
      final isActive = dashboardService.currentLayout?.id == setupRef.id;

      DashboardSetup setup;
      if (isActive) {
        setup = setupService.exportCurrentSetup(
          name: setupRef.name,
          description: setupRef.description,
        );
      } else {
        await setupService.loadSetup(setupRef.id);
        setup = setupService.exportCurrentSetup(
          name: setupRef.name,
          description: setupRef.description,
        );
      }

      final jsonString = setupService.exportToJson(setup);

      final directory = await getTemporaryDirectory();
      final file = File(
          '${directory.path}/${setupRef.name.replaceAll(' ', '_')}.zedjson');
      await file.writeAsString(jsonString);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Dashboard Setup: ${setupRef.name}',
          text: 'Check out my dashboard setup!',
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Setup exported and ready to share'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing setup: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _importSetup() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Setup'),
        content: const Text('How would you like to import the setup?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, 'paste'),
            icon: const Icon(Icons.content_paste),
            label: const Text('Paste JSON'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, 'browse'),
            icon: const Icon(Icons.folder_open),
            label: const Text('Browse File'),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;

    String? jsonString;

    if (choice == 'browse') {
      try {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['zedjson', 'json'],
          allowMultiple: false,
        );

        if (result != null && result.files.single.path != null) {
          final file = File(result.files.single.path!);
          jsonString = await file.readAsString();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error reading file: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    } else if (choice == 'paste') {
      final controller = TextEditingController();

      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Paste Setup JSON'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Paste the setup JSON below:'),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'JSON',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 10,
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
                if (controller.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Import'),
            ),
          ],
        ),
      );

      if (result == true) {
        jsonString = controller.text.trim();
      }
    }

    if (jsonString != null && jsonString.isNotEmpty && mounted) {
      try {
        final setupService =
            Provider.of<SetupService>(context, listen: false);

        final result = await setupService.importSetup(jsonString);

        if (mounted) {
          String dialogContent = 'The setup has been saved to your list.';
          if (result.hasWarnings) {
            dialogContent += '\n\nNote: ${result.warnings.join("; ")}';
          }
          dialogContent += '\n\nWould you like to switch to it now?';

          final switchNow = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(result.hasWarnings
                  ? 'Setup Imported (with warnings)'
                  : 'Setup Imported'),
              content: Text(dialogContent),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Not Now'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Switch Now'),
                ),
              ],
            ),
          );

          if (switchNow == true && mounted) {
            final savedSetups = setupService.getSavedSetups();
            if (savedSetups.isNotEmpty) {
              final recentSetup = savedSetups.first;
              await setupService.loadSetup(recentSetup.id);

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Switched to "${recentSetup.name}"'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            }
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result.hasWarnings
                    ? 'Setup saved with warnings. You can switch to it anytime.'
                    : 'Setup saved. You can switch to it anytime.'),
                backgroundColor:
                    result.hasWarnings ? Colors.orange : Colors.blue,
              ),
            );
          }

          setState(() {});
        }
      } catch (e) {
        if (mounted) {
          String errorMsg =
              e.toString().replaceAll(RegExp(r'Exception:\s*'), '');
          if (errorMsg.length > 80) {
            errorMsg = '${errorMsg.substring(0, 80)}...';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error importing setup: $errorMsg'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _editSetup(SavedSetup setup) async {
    final nameController = TextEditingController(text: setup.name);
    final descriptionController =
        TextEditingController(text: setup.description);

    const presets = ['Phone', 'Tablet', 'Desktop'];
    final isCustom =
        setup.intendedUse != null && !presets.contains(setup.intendedUse);
    String? selectedIntendedUse = isCustom ? 'Custom' : setup.intendedUse;
    final customIntendedUseController =
        TextEditingController(text: isCustom ? setup.intendedUse : '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Setup'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Setup Name',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                const Text('Intended Use',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                RadioGroup<String?>(
                  groupValue: selectedIntendedUse,
                  onChanged: (value) {
                    setState(() => selectedIntendedUse = value);
                  },
                  child: Column(
                    children: [
                      ...presets.map((preset) => RadioListTile<String?>(
                            title: Text(preset),
                            value: preset,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          )),
                      const RadioListTile<String?>(
                        title: Text('Custom'),
                        value: 'Custom',
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (selectedIntendedUse == 'Custom')
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 16, right: 16, top: 8),
                          child: TextField(
                            controller: customIntendedUseController,
                            decoration: const InputDecoration(
                              labelText: 'Custom name',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            autofocus: true,
                          ),
                        ),
                      const RadioListTile<String?>(
                        title: Text('None'),
                        subtitle: Text('Clear intended use'),
                        value: null,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
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
                if (nameController.text.trim().isEmpty) {
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

    if (result == true && mounted) {
      try {
        final setupService =
            Provider.of<SetupService>(context, listen: false);
        await setupService.renameSetup(
            setup.id, nameController.text.trim());
        await setupService.updateSetupDescription(
            setup.id, descriptionController.text.trim());

        String? finalIntendedUse;
        if (selectedIntendedUse == 'Custom') {
          finalIntendedUse = customIntendedUseController.text.trim();
          if (finalIntendedUse.isEmpty) finalIntendedUse = null;
        } else {
          finalIntendedUse = selectedIntendedUse;
        }
        await setupService.updateSetupIntendedUse(
            setup.id, finalIntendedUse);

        if (!mounted) return;
        final dashboardService =
            Provider.of<DashboardService>(context, listen: false);
        if (dashboardService.currentLayout?.id == setup.id) {
          final currentLayout = dashboardService.currentLayout!;
          final updatedLayout = currentLayout.copyWith(
            intendedUse: finalIntendedUse,
            clearIntendedUse: finalIntendedUse == null,
          );
          await dashboardService.updateLayout(updatedLayout);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Setup updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {});
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating setup: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _confirmDeleteSetup(SavedSetup setup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Setup'),
        content: Text(
          'Are you sure you want to delete "${setup.name}"?\n\nThis action cannot be undone.',
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

    if (confirmed == true && mounted) {
      try {
        final setupService =
            Provider.of<SetupService>(context, listen: false);
        await setupService.deleteSetup(setup.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Setup "${setup.name}" deleted'),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() {});
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting setup: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
