import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/string_extensions.dart';
import '../../utils/color_extensions.dart';
import '../../utils/data_extensions.dart';
import '../../config/ui_constants.dart';

/// Config-driven switch tool for toggling boolean SignalK paths
/// Supports multiple switches in a single tool
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

class _SwitchToolState extends State<SwitchTool> with AutomaticKeepAliveClientMixin {
  final Set<String> _sendingPaths = {};

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.config.dataSources.isEmpty) {
      return const Center(child: Text('No data source configured'));
    }

    final style = widget.config.style;
    final dataSources = widget.config.dataSources;

    // Parse colors from hex string
    final activeColor = style.primaryColor?.toColor(
      fallback: Colors.green
    ) ?? Colors.green;

    final inactiveColor = style.secondaryColor?.toColor(
      fallback: Colors.grey
    ) ?? Colors.grey;

    // Single switch - use original layout
    if (dataSources.length == 1) {
      return _buildSingleSwitch(dataSources.first, style, activeColor, inactiveColor);
    }

    // Multiple switches - use grid layout
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Determine grid columns based on available width
          final crossAxisCount = constraints.maxWidth > 400 ? 3 : (constraints.maxWidth > 200 ? 2 : 1);

          // Adjust aspect ratio based on what's shown
          final showLabel = style.showLabel == true;
          final showValue = style.showValue == true;
          double aspectRatio;
          if (showLabel && showValue) {
            aspectRatio = 1.0;  // Taller for both
          } else if (showLabel || showValue) {
            aspectRatio = 1.3;  // Medium
          } else {
            aspectRatio = 1.8;  // Wider/shorter for icon only
          }

          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: aspectRatio,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: dataSources.length,
            itemBuilder: (context, index) {
              return _buildSwitchCard(
                dataSources[index],
                style,
                activeColor,
                inactiveColor,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSingleSwitch(
    DataSource dataSource,
    StyleConfig style,
    Color activeColor,
    Color inactiveColor,
  ) {
    final dataPoint = widget.signalKService.getValue(dataSource.path, source: dataSource.source);
    final currentValue = dataPoint.toBool();
    final label = dataSource.label ?? dataSource.path.toReadableLabel();
    final isSending = _sendingPaths.contains(dataSource.path);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (style.showLabel == true) ...[
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
          ],
          if (style.showValue == true) ...[
            Text(
              currentValue ? 'ON' : 'OFF',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: currentValue ? activeColor : inactiveColor,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Transform.scale(
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
              onChanged: isSending ? null : (value) => _toggleSwitch(value, dataSource.path),
            ),
          ),
          if (isSending)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSwitchCard(
    DataSource dataSource,
    StyleConfig style,
    Color activeColor,
    Color inactiveColor,
  ) {
    final dataPoint = widget.signalKService.getValue(dataSource.path, source: dataSource.source);
    final currentValue = dataPoint.toBool();
    final label = dataSource.label ?? dataSource.path.toReadableLabel();
    final isSending = _sendingPaths.contains(dataSource.path);

    return Card(
      elevation: 2,
      child: InkWell(
        onTap: isSending ? null : () => _toggleSwitch(!currentValue, dataSource.path),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: currentValue ? activeColor : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon indicator
              Icon(
                currentValue ? Icons.toggle_on : Icons.toggle_off,
                size: 32,
                color: currentValue ? activeColor : inactiveColor,
              ),
              const SizedBox(height: 4),
              // Label
              if (style.showLabel == true)
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              // ON/OFF text
              if (style.showValue == true)
                Text(
                  currentValue ? 'ON' : 'OFF',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: currentValue ? activeColor : inactiveColor,
                  ),
                ),
              // Loading indicator
              if (isSending)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleSwitch(bool newValue, String path) async {
    setState(() {
      _sendingPaths.add(path);
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
          _sendingPaths.remove(path);
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
      description: 'Toggle switches for boolean SignalK paths with PUT support',
      category: ToolCategory.controls,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: true,
        minPaths: 1,
        maxPaths: 8,
        styleOptions: const [
          'primaryColor',    // Active color
          'secondaryColor',  // Inactive color
          'showLabel',
          'showValue',       // Show ON/OFF text
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
