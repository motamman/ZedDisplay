import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/bundled_dashboard_service.dart';
import '../services/dashboard_store_service.dart';
import '../services/setup_service.dart';
import '../services/signalk_service.dart';
import 'dashboard_manager_screen.dart';

/// Full-screen picker for choosing a dashboard from bundled assets
/// or the SignalK server. Shown on first run, also accessible from
/// Setup Management via "Load Template".
class DashboardPickerScreen extends StatefulWidget {
  /// If true, navigates to DashboardManagerScreen after selection.
  /// Used for the first-run flow.
  final bool isFirstRun;

  const DashboardPickerScreen({super.key, this.isFirstRun = false});

  @override
  State<DashboardPickerScreen> createState() => _DashboardPickerScreenState();
}

class _DashboardPickerScreenState extends State<DashboardPickerScreen> {
  List<BundledDashboardInfo>? _bundledDashboards;
  bool _isLoading = true;
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
      setState(() {
        _bundledDashboards = dashboards;
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchServerDashboards() async {
    final signalK = Provider.of<SignalKService>(context, listen: false);
    if (!signalK.isConnected) return;

    final storeService =
        Provider.of<DashboardStoreService>(context, listen: false);
    await storeService.fetchFromServer();
  }

  Future<void> _loadBundledDashboard(BundledDashboardInfo info) async {
    final confirmed = await _confirmLoad(info.name);
    if (confirmed != true || !mounted) return;

    setState(() => _isApplying = true);

    try {
      final jsonString =
          await BundledDashboardService.loadDashboardJson(info);
      final setupService = Provider.of<SetupService>(context, listen: false);
      final result = await setupService.importAndLoadSetup(jsonString);

      if (!mounted) return;

      if (result.success) {
        setupService.clearNeedsDashboardPicker();
        _onDashboardLoaded(result.setupName ?? info.name);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load dashboard'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  Future<void> _loadServerDashboard(ServerDashboardInfo info) async {
    final confirmed = await _confirmLoad(info.name);
    if (confirmed != true || !mounted) return;

    if (info.zedjson.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dashboard has no content'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isApplying = true);

    try {
      final setupService = Provider.of<SetupService>(context, listen: false);
      final result = await setupService.importAndLoadSetup(info.zedjson);

      if (!mounted) return;

      if (result.success) {
        setupService.clearNeedsDashboardPicker();
        _onDashboardLoaded(result.setupName ?? info.name);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load dashboard'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
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
        content: Text('Load "$name"?\n\nThis will replace your current dashboard.'),
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

  void _onDashboardLoaded(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loaded "$name"'),
        backgroundColor: Colors.green,
      ),
    );

    if (widget.isFirstRun) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const DashboardManagerScreen(),
        ),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final signalK = Provider.of<SignalKService>(context);
    final isConnected = signalK.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a Dashboard'),
        automaticallyImplyLeading: !widget.isFirstRun,
        actions: [
          if (widget.isFirstRun)
            TextButton(
              onPressed: () {
                final setupService =
                    Provider.of<SetupService>(context, listen: false);
                setupService.clearNeedsDashboardPicker();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => const DashboardManagerScreen(),
                  ),
                );
              },
              child: const Text('Skip'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isApplying
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
              : _buildBody(isConnected),
    );
  }

  Widget _buildBody(bool isConnected) {
    final bundled = _bundledDashboards ?? [];
    final storeService = Provider.of<DashboardStoreService>(context);
    final serverDashboards = storeService.serverDashboards;
    final isFetchingServer = storeService.isFetching;

    if (bundled.isEmpty && serverDashboards.isEmpty && !isFetchingServer) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.dashboard_customize, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No dashboards available',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            if (widget.isFirstRun)
              ElevatedButton(
                onPressed: () {
                  final setupService =
                      Provider.of<SetupService>(context, listen: false);
                  setupService.clearNeedsDashboardPicker();
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => const DashboardManagerScreen(),
                    ),
                  );
                },
                child: const Text('Create Blank Dashboard'),
              ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Bundled dashboards section
        if (bundled.isNotEmpty) ...[
          _buildSectionHeader('Bundled Dashboards', Icons.inventory_2),
          const SizedBox(height: 8),
          ...bundled.map(_buildBundledCard),
          const SizedBox(height: 24),
        ],

        // Server dashboards section
        if (isConnected) ...[
          _buildSectionHeader('Server Dashboards', Icons.cloud),
          const SizedBox(height: 8),
          if (isFetchingServer)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (serverDashboards.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No dashboards on server',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ),
            )
          else
            ...serverDashboards.map(_buildServerCard),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
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
      ],
    );
  }

  Widget _buildBundledCard(BundledDashboardInfo info) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.dashboard, color: Colors.blue, size: 32),
        title: Text(info.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (info.description.isNotEmpty)
              Text(info.description, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    info.categoryName,
                    style: TextStyle(fontSize: 10, color: Colors.blue[700]),
                  ),
                ),
                if (info.isDefault) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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

  Widget _buildServerCard(ServerDashboardInfo info) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.cloud_download, color: Colors.teal, size: 32),
        title: Text(info.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (info.description.isNotEmpty)
              Text(info.description, maxLines: 2, overflow: TextOverflow.ellipsis),
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
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _loadServerDashboard(info),
      ),
    );
  }
}
