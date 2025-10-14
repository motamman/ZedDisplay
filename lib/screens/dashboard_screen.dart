import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/signalk_service.dart';
import '../widgets/radial_gauge.dart';
import '../widgets/compass_gauge.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

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
              // TODO: Navigate to settings
            },
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
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('Back to Connection'),
                  ),
                ],
              ),
            );
          }

          // Extract common marine data paths (already converted by units-preference plugin)
          final speedOverGround = service.getConvertedValue('navigation.speedOverGround') ?? 0.0;
          final speedThroughWater = service.getConvertedValue('navigation.speedThroughWater') ?? 0.0;
          final heading = service.getConvertedValue('navigation.headingTrue') ?? 0.0;
          final windSpeed = service.getConvertedValue('environment.wind.speedApparent') ?? 0.0;
          final depth = service.getConvertedValue('environment.depth.belowTransducer') ?? 0.0;
          final batteryVoltage = service.getConvertedValue('electrical.batteries.house.voltage') ?? 0.0;

          // Get unit symbols from server configuration
          final speedUnit = service.getUnitSymbol('navigation.speedOverGround') ?? 'kts';
          final depthUnit = service.getUnitSymbol('environment.depth.belowTransducer') ?? 'm';
          final voltageUnit = service.getUnitSymbol('electrical.batteries.house.voltage') ?? 'V';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
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
    );
  }
}
