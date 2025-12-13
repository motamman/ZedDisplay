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

class _CheckboxToolState extends State<CheckboxTool> with AutomaticKeepAliveClientMixin {
  bool _isSending = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

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
        scale: UIConstants.checkboxScale,
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
      path: dataSource.path,
      isSending: _isSending,
    );
  }

  Future<void> _toggleCheckbox(bool newValue, String path) async {
    setState(() {
      _isSending = true;
    });

    try {
      // Note: source is NOT passed to PUT - source identifies the sender, not target
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
