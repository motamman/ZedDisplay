import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/signalk_service.dart';
import '../services/tool_registry.dart';
import '../models/tool_instance.dart';
import '../widgets/radial_gauge.dart';
import '../widgets/compass_gauge.dart';
import 'tool_config_screen.dart';
import 'template_library_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final List<ToolInstance> _customTools = [];

  Future<void> _addTool() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ToolConfigScreen(screenId: 'main'),
      ),
    );

    if (result is ToolInstance) {
      setState(() {
        _customTools.add(result);
      });
    }
  }

  Future<void> _browseTemplates() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const TemplateLibraryScreen(),
      ),
    );

    if (result is ToolInstance) {
      setState(() {
        _customTools.add(result);
      });
    }
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Create Custom Tool'),
              subtitle: const Text('Configure a tool from scratch'),
              onTap: () {
                Navigator.pop(context);
                _addTool();
              },
            ),
            ListTile(
              leading: const Icon(Icons.collections_bookmark),
              title: const Text('Browse Templates'),
              subtitle: const Text('Use pre-configured tool templates'),
              onTap: () {
                Navigator.pop(context);
                _browseTemplates();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _removeTool(String toolId) {
    setState(() {
      _customTools.removeWhere((tool) => tool.id == toolId);
    });
  }

  // Note: This is a test screen, not used in production
  // The real dashboard is DashboardManagerScreen
  Future<void> _saveAsTemplate(ToolInstance toolInstance) async {
    // This feature is not implemented in the new architecture
    // Tools are managed directly in the ToolService
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Feature not available in this test screen'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // Test method for vessel ID
  void _testGetVesselId(BuildContext context, SignalKService service) async {
    final vesselId = await service.getVesselSelfId();
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Vessel ID'),
          content: Text(vesselId ?? 'No vessel ID found'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  // Test method for available paths
  void _testGetPaths(BuildContext context, SignalKService service) async {
    final tree = await service.getAvailablePaths();
    if (tree != null) {
      final paths = service.extractPathsFromTree(tree);
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Available Paths (${paths.length})'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: paths.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    dense: true,
                    title: Text(
                      paths[index],
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to fetch paths')),
      );
    }
  }

  // Test method for sources
  void _testGetSources(BuildContext context, SignalKService service) async {
    const testPath = 'navigation.speedOverGround';
    final sources = await service.getSourcesForPath(testPath);
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sources for SOG'),
          content: sources != null
              ? Text(sources.keys.join('\n'))
              : const Text('No sources found or path has no \$source'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marine Dashboard'),
        actions: [
          Consumer<SignalKService>(
            builder: (context, service, child) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Center(
                  child: Row(
                    children: [
                      Icon(
                        service.isConnected ? Icons.cloud_done : Icons.cloud_off,
                        color: service.isConnected ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        service.isConnected ? 'Connected' : 'Disconnected',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Consumer<SignalKService>(
        builder: (context, service, child) {
          if (!service.isConnected) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'Not connected to SignalK server',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.settings),
                    label: const Text('Connection Settings'),
                  ),
                ],
              ),
            );
          }

          // Extract common marine data paths (already converted by units-preference plugin)
          final speedOverGround = service.getConvertedValue('navigation.speedOverGround') ?? 0.0;
          final speedThroughWater = service.getConvertedValue('navigation.speedThroughWater') ?? 0.0;
          final heading = service.getConvertedValue('navigation.headingMagnetic') ?? 0.0;
          final windSpeed = service.getConvertedValue('environment.wind.speedApparent') ?? 0.0;
          final depth = service.getConvertedValue('environment.depth.belowTransducer') ?? 0.0;
          final batteryVoltage = service.getConvertedValue('electrical.batteries.512.voltage') ?? 0.0;

          // Get unit symbols from server configuration
          final speedUnit = service.getUnitSymbol('navigation.speedOverGround') ?? 'kts';
          final depthUnit = service.getUnitSymbol('environment.depth.belowTransducer') ?? 'm';
          final voltageUnit = service.getUnitSymbol('electrical.batteries.512.voltage') ?? 'V';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Custom Tools Section
                if (_customTools.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Custom Tools',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${_customTools.length} tools',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                            ),
                            itemCount: _customTools.length,
                            itemBuilder: (context, index) {
                              final tool = _customTools[index];
                              final registry = ToolRegistry();

                              return Stack(
                                children: [
                                  registry.buildTool(
                                    tool.toolTypeId,
                                    tool.config,
                                    service,
                                  ),
                                  // Save as Template button
                                  Positioned(
                                    top: 4,
                                    left: 4,
                                    child: IconButton(
                                      icon: const Icon(Icons.bookmark_add, size: 16),
                                      onPressed: () => _saveAsTemplate(tool),
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.blue.withValues(alpha: 0.7),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.all(4),
                                        minimumSize: const Size(24, 24),
                                      ),
                                      tooltip: 'Save as Template',
                                    ),
                                  ),
                                  // Delete button
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: IconButton(
                                      icon: const Icon(Icons.close, size: 16),
                                      onPressed: () => _removeTool(tool.id),
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.red.withValues(alpha: 0.7),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.all(4),
                                        minimumSize: const Size(24, 24),
                                      ),
                                      tooltip: 'Remove',
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Navigation Section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Navigation',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          children: [
                            RadialGauge(
                              value: speedOverGround, // Already converted
                              minValue: 0,
                              maxValue: 15,
                              label: 'SOG',
                              unit: speedUnit,
                              primaryColor: Colors.blue,
                            ),
                            RadialGauge(
                              value: speedThroughWater, // Already converted
                              minValue: 0,
                              maxValue: 15,
                              label: 'STW',
                              unit: speedUnit,
                              primaryColor: Colors.teal,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 250,
                          child: CompassGauge(
                            heading: heading, // Already converted to degrees
                            label: 'Heading',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Environment Section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Environment',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          children: [
                            RadialGauge(
                              value: windSpeed, // Already converted
                              minValue: 0,
                              maxValue: 40,
                              label: 'Wind',
                              unit: speedUnit,
                              primaryColor: Colors.green,
                            ),
                            RadialGauge(
                              value: depth, // Already converted
                              minValue: 0,
                              maxValue: 50,
                              label: 'Depth',
                              unit: depthUnit,
                              primaryColor: Colors.purple,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Electrical Section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Electrical',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 200,
                          child: RadialGauge(
                            value: batteryVoltage, // Already converted
                            minValue: 10,
                            maxValue: 15,
                            label: 'Battery',
                            unit: voltageUnit,
                            primaryColor: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Debug Info (you can remove this later)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Debug Info',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Data points received: ${service.latestData.length}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (service.latestData.isNotEmpty)
                          Text(
                            'Sample paths: ${service.latestData.keys.take(5).join(", ")}',
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () => _testGetVesselId(context, service),
                              icon: const Icon(Icons.directions_boat, size: 16),
                              label: const Text('Get Vessel ID', style: TextStyle(fontSize: 12)),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => _testGetPaths(context, service),
                              icon: const Icon(Icons.list, size: 16),
                              label: const Text('Get All Paths', style: TextStyle(fontSize: 12)),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => _testGetSources(context, service),
                              icon: const Icon(Icons.sensors, size: 16),
                              label: const Text('Get Sources', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddMenu,
        icon: const Icon(Icons.add),
        label: const Text('Add Tool'),
      ),
    );
  }
}
