import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/string_extensions.dart';
import '../../utils/color_extensions.dart';
import '../../utils/data_extensions.dart';

/// Config-driven checkbox tool for toggling boolean SignalK paths
class CheckboxTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const CheckboxTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<CheckboxTool> createState() => _CheckboxToolState();
}

class _CheckboxToolState extends State<CheckboxTool> {
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
    final currentValue = dataPoint.toBool();

    // Get style configuration
    final style = widget.config.style;

    // Get label from data source or style
    final label = dataSource.label ?? dataSource.path.toReadableLabel();

    // Parse colors from hex string
    final activeColor = style.primaryColor?.toColor(
      fallback: Colors.green
    ) ?? Colors.green;

    final inactiveColor = style.secondaryColor?.toColor(
      fallback: Colors.grey
    ) ?? Colors.grey;

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

            // Checkbox with enhanced styling
            Transform.scale(
              scale: 2.0,
              child: Checkbox(
                value: currentValue,
                activeColor: activeColor,
                checkColor: Colors.white,
                side: BorderSide(
                  color: currentValue ? activeColor : inactiveColor,
                  width: 2,
                ),
                onChanged: _isSending ? null : (value) => _toggleCheckbox(value ?? false, dataSource.path),
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

  Future<void> _toggleCheckbox(bool newValue, String path) async {
    setState(() {
      _isSending = true;
    });

    try {
      await widget.signalKService.sendPutRequest(path, newValue);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${path.toReadableLabel()} ${newValue ? "enabled" : "disabled"}'),
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
}

/// Builder for checkbox tools
class CheckboxToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'checkbox',
      name: 'Checkbox',
      description: 'Checkbox for boolean SignalK paths with PUT support',
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
    return CheckboxTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
