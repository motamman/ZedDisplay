import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/string_extensions.dart';
import '../../utils/color_extensions.dart';
import '../../utils/data_extensions.dart';
import '../../config/ui_constants.dart';
import 'common/control_tool_layout.dart';

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

    return ControlToolLayout(
      label: label,
      showLabel: style.showLabel == true,
      valueWidget: Text(
        currentValue ? 'ON' : 'OFF',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: currentValue ? activeColor : inactiveColor,
        ),
      ),
      additionalWidgets: const [
        SizedBox(height: 8),
      ],
      controlWidget: Transform.scale(
        scale: UIConstants.switchScale,
        child: Switch(
          value: currentValue,
          activeThumbColor: activeColor,
          activeTrackColor: UIConstants.withMediumOpacity(activeColor),
          inactiveThumbColor: inactiveColor,
          inactiveTrackColor: UIConstants.withLightOpacity(inactiveColor),
          thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
            if (states.contains(WidgetState.selected)) {
              return const Icon(Icons.check, size: 16, color: Colors.white);
            }
            return const Icon(Icons.close, size: 16, color: Colors.white);
          }),
          onChanged: _isSending ? null : (value) => _toggleSwitch(value, dataSource.path),
        ),
      ),
      path: dataSource.path,
      isSending: _isSending,
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
            content: Text('${path.toReadableLabel()} ${newValue ? "enabled" : "disabled"}'),
            duration: UIConstants.snackBarShort,
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to toggle: $e'),
            duration: UIConstants.snackBarNormal,
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
