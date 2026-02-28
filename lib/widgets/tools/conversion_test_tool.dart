import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';

/// Simple test tool to display conversion data from SignalK
/// Uses STANDARD SignalK WebSocket: ws://[server]/signalk/v1/stream
class ConversionTestTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const ConversionTestTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<ConversionTestTool> createState() => _ConversionTestToolState();
}

class _ConversionTestToolState extends State<ConversionTestTool> {
  @override
  void initState() {
    super.initState();

    // Subscribe to paths using STANDARD SignalK WebSocket ONLY
    // Path: ws://[server]/signalk/v1/stream
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final paths = widget.config.dataSources.map((ds) => ds.path).toList();
      if (paths.isNotEmpty) {
        widget.signalKService.subscribeToAutopilotPaths(paths);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.signalKService.isConnected) {
      return const Center(
        child: Text(
          'Not connected',
          style: TextStyle(fontSize: 12),
        ),
      );
    }

    if (widget.config.dataSources.isEmpty) {
      return const Center(
        child: Text(
          'No paths configured',
          style: TextStyle(fontSize: 12),
        ),
      );
    }

    return ListView.builder(
      itemCount: widget.config.dataSources.length,
      itemBuilder: (context, index) {
        final path = widget.config.dataSources[index].path;
        final dataPoint = widget.signalKService.getValue(path);

        // Use MetadataStore as single source of truth for conversions
        final metadata = widget.signalKService.metadataStore.get(path);
        final targetUnit = metadata?.targetUnit;
        final formula = metadata?.formula;
        final symbol = metadata?.symbol;

        // Get raw SI value from data point
        final rawValue = dataPoint?.original is num
            ? (dataPoint!.original as num).toDouble()
            : (dataPoint?.value is num ? (dataPoint!.value as num).toDouble() : null);

        // Get converted value using MetadataStore (applies server's formula)
        final convertedValue = rawValue != null ? metadata?.convert(rawValue) : null;

        final hasMetadata = metadata != null;

        return Card(
          margin: const EdgeInsets.all(4.0),
          color: hasMetadata ? null : Colors.red.withOpacity(0.1),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      hasMetadata ? Icons.check_circle : Icons.error,
                      size: 14,
                      color: hasMetadata ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        path,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (hasMetadata) ...[
                  _buildRow('Unit', symbol ?? targetUnit ?? '---'),
                  _buildRow('Raw (SI)', rawValue?.toStringAsFixed(4) ?? '---'),
                  _buildRow('Converted', convertedValue?.toStringAsFixed(2) ?? '---'),
                  _buildRow('Formula', formula ?? '---'),
                ] else ...[
                  _buildRow('Status', 'NO metadata from server'),
                  _buildRow('Raw value', dataPoint?.value?.toString() ?? '---'),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.0),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Builder for conversion test tool
class ConversionTestToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'conversion_test',
      name: 'Conversion Test',
      description: 'Test tool to display conversion data from standard SignalK stream',
      category: ToolCategory.system,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: true,
        minPaths: 1,
        maxPaths: 20,
        styleOptions: const [],
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return ConversionTestTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
