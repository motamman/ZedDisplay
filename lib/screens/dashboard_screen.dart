import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/signalk_service.dart';
import '../widgets/radial_gauge.dart';
import '../widgets/compass_gauge.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

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

          // Extract common marine data paths
          final speedOverGround = service.getNumericValue('navigation.speedOverGround') ?? 0.0;
          final speedThroughWater = service.getNumericValue('navigation.speedThroughWater') ?? 0.0;
          final heading = service.getNumericValue('navigation.headingTrue') ?? 0.0;
          final windSpeed = service.getNumericValue('environment.wind.speedApparent') ?? 0.0;
          final depth = service.getNumericValue('environment.depth.belowTransducer') ?? 0.0;
          final batteryVoltage = service.getNumericValue('electrical.batteries.house.voltage') ?? 0.0;

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
                              value: speedOverGround * 1.94384, // Convert m/s to knots
                              minValue: 0,
                              maxValue: 15,
                              label: 'SOG',
                              unit: 'kts',
                              primaryColor: Colors.blue,
                            ),
                            RadialGauge(
                              value: speedThroughWater * 1.94384,
                              minValue: 0,
                              maxValue: 15,
                              label: 'STW',
                              unit: 'kts',
                              primaryColor: Colors.teal,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 250,
                          child: CompassGauge(
                            heading: heading * 180 / 3.14159, // Convert radians to degrees
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
                              value: windSpeed * 1.94384, // Convert m/s to knots
                              minValue: 0,
                              maxValue: 40,
                              label: 'Wind',
                              unit: 'kts',
                              primaryColor: Colors.green,
                            ),
                            RadialGauge(
                              value: depth,
                              minValue: 0,
                              maxValue: 50,
                              label: 'Depth',
                              unit: 'm',
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
                            value: batteryVoltage,
                            minValue: 10,
                            maxValue: 15,
                            label: 'Battery',
                            unit: 'V',
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
