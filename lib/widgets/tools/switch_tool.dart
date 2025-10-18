import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';

/// Config-driven switch tool for toggling boolean SignalK paths
class SwitchTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const SwitchTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<SwitchTool> createState() => _SwitchToolState();
}

class _SwitchToolState extends State<SwitchTool> {
  bool _isSending = false;

  @override
  Widget build(BuildContext context) {
    // Get data from first data source
    if (widget.config.dataSources.isEmpty) {
      return const Center(child: Text('No data source configured'));
    }

    final dataSource = widget.config.dataSources.first;
    final dataPoint = widget.signalKService.getValue(dataSource.path, source: dataSource.source);

    // Get boolean value - handle different formats
    bool currentValue = false;
    if (dataPoint?.value is bool) {
      currentValue = dataPoint!.value as bool;
    } else if (dataPoint?.value is num) {
      // Handle numeric 0/1 as boolean
      currentValue = (dataPoint!.value as num) != 0;
    } else if (dataPoint?.value is String) {
      // Handle string "true"/"false"
      final stringValue = (dataPoint!.value as String).toLowerCase();
      currentValue = stringValue == 'true' || stringValue == '1';
    }

    // Get style configuration
    final style = widget.config.style;

    // Get label from data source or style
    final label = dataSource.label ?? _getDefaultLabel(dataSource.path);

    // Parse colors from hex string
    Color activeColor = Colors.green;
    Color inactiveColor = Colors.grey;

    if (style.primaryColor != null) {
      try {
        final colorString = style.primaryColor!.replaceAll('#', '');
        activeColor = Color(int.parse('FF$colorString', radix: 16));
      } catch (e) {
        // Keep default color if parsing fails
      }
    }

    if (style.secondaryColor != null) {
      try {
        final colorString = style.secondaryColor!.replaceAll('#', '');
        inactiveColor = Color(int.parse('FF$colorString', radix: 16));
      } catch (e) {
        // Keep default color if parsing fails
      }
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (style.showLabel == true) ...[
              Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],

            // State label
            Text(
              currentValue ? 'ON' : 'OFF',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: currentValue ? activeColor : inactiveColor,
              ),
            ),

            const SizedBox(height: 16),

            // Material Switch with enhanced styling
            Transform.scale(
              scale: 1.8,
              child: Switch(
                value: currentValue,
                activeColor: activeColor,
                activeTrackColor: activeColor.withValues(alpha: 0.5),
                inactiveThumbColor: inactiveColor,
                inactiveTrackColor: inactiveColor.withValues(alpha: 0.3),
                thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Icon(Icons.check, size: 16, color: Colors.white);
                  }
                  return Icon(Icons.close, size: 16, color: Colors.white);
                }),
                onChanged: _isSending ? null : (value) => _toggleSwitch(value, dataSource.path),
              ),
            ),

            // Path info
            const SizedBox(height: 8),
            Text(
              dataSource.path,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            // Sending indicator
            if (_isSending) ...[
              const SizedBox(height: 8),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggleSwitch(bool newValue, String path) async {
    setState(() {
      _isSending = true;
    });

    try {
      await widget.signalKService.sendPutRequest(path, newValue);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_getDefaultLabel(path)} ${newValue ? "enabled" : "disabled"}'),
            duration: const Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to toggle: $e'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  /// Extract a readable label from the path
  String _getDefaultLabel(String path) {
    final parts = path.split('.');
    if (parts.isEmpty) return path;

    // Get the last part and make it readable
    final lastPart = parts.last;

    // Convert camelCase to Title Case
    final result = lastPart.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)}',
    ).trim();

    return result.isEmpty ? lastPart : result;
  }
}

/// Builder for switch tools
class SwitchToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'switch',
      name: 'Switch',
      description: 'Toggle switch for boolean SignalK paths with PUT support',
      category: ToolCategory.control,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 1,
        maxPaths: 1,
        styleOptions: const [
          'primaryColor',    // Active color
          'secondaryColor',  // Inactive color
          'showLabel',
        ],
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return SwitchTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
