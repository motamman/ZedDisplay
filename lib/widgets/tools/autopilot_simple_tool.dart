import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../models/autopilot_errors.dart';
import '../../services/signalk_service.dart';
import '../../services/autopilot_state_verifier.dart';
import '../../services/tool_registry.dart';
import '../../utils/color_extensions.dart';
import '../../config/ui_constants.dart';

/// Simple Autopilot control tool - text-based display with controls
/// No compass visualization - just heading, target, mode, and buttons
///
/// **IMPORTANT**: Currently supports V1 API only (plugin-based via PUT requests)
/// V2 API support (REST-based with instance discovery) is planned for future release.
class AutopilotSimpleTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const AutopilotSimpleTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<AutopilotSimpleTool> createState() => _AutopilotSimpleToolState();
}

class _AutopilotSimpleToolState extends State<AutopilotSimpleTool> with AutomaticKeepAliveClientMixin {
  // Autopilot state from SignalK
  double _currentHeading = 0;
  double _targetHeading = 0;
  String _mode = 'Standby';
  bool _engaged = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.signalKService.addListener(_onSignalKUpdate);
    _subscribeToAutopilotPaths();

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _onSignalKUpdate();
      }
    });
  }

  @override
  void dispose() {
    widget.signalKService.removeListener(_onSignalKUpdate);
    super.dispose();
  }

  void _subscribeToAutopilotPaths() {
    final configuredPaths = widget.config.dataSources.map((ds) => ds.path).toList();
    final additionalPaths = [
      'navigation.headingTrue',
    ];
    final allPaths = {...configuredPaths, ...additionalPaths}.toList();
    widget.signalKService.subscribeToAutopilotPaths(allPaths);
  }

  void _onSignalKUpdate() {
    if (!mounted) return;

    final dataSources = widget.config.dataSources;
    if (dataSources.isEmpty) return;

    setState(() {
      // 0: Autopilot state/mode
      if (dataSources.isNotEmpty) {
        final stateData = widget.signalKService.getValue(
          dataSources[0].path,
          source: dataSources[0].source,
        );
        if (stateData?.value != null) {
          final rawMode = stateData!.value.toString();
          _mode = rawMode.isNotEmpty
              ? rawMode[0].toUpperCase() + rawMode.substring(1).toLowerCase()
              : 'Standby';
        }
      }

      // Derive engaged state from mode
      _engaged = _mode.toLowerCase() != 'standby';

      // 3: Target heading
      if (dataSources.length > 3) {
        final targetData = widget.signalKService.getValue(
          dataSources[3].path,
          source: dataSources[3].source,
        );
        if (targetData?.value != null) {
          _targetHeading = _radiansToDegrees(targetData!.value as num);
        }
      }

      // 4: Current heading
      if (dataSources.length > 4) {
        final headingData = widget.signalKService.getValue(
          dataSources[4].path,
          source: dataSources[4].source,
        );
        if (headingData?.value != null) {
          _currentHeading = _radiansToDegrees(headingData!.value as num);
        }
      }
    });
  }

  double _radiansToDegrees(num radians) {
    return (radians * 180 / 3.14159265359) % 360;
  }

  Future<void> _sendV1Command(String path, dynamic value) async {
    if (kDebugMode) {
      print('Sending autopilot command: $path = $value');
    }

    try {
      // Send command via PUT request
      await widget.signalKService.sendPutRequest(path, value);

      // Show pending feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sending command...'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }

      // Verify state change via WebSocket
      final verifier = AutopilotStateVerifier(widget.signalKService);
      final verified = await verifier.verifyChange(
        path: path,
        expectedValue: value,
      );

      if (kDebugMode) {
        print('Autopilot command ${verified ? "verified" : "timed out"}');
      }

      // Show final result
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(verified
                ? 'Command successful'
                : 'Command sent but not confirmed - may still be processing'),
            backgroundColor: verified ? Colors.green : Colors.orange,
            duration: UIConstants.snackBarShort,
          ),
        );
      }
    } on AutopilotException catch (e) {
      if (kDebugMode) {
        print('Autopilot error: ${e.message}');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.getUserFriendlyMessage()),
            backgroundColor: Colors.red,
            duration: UIConstants.snackBarLong,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Autopilot command failed: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Command failed: $e'),
            backgroundColor: Colors.red,
            duration: UIConstants.snackBarLong,
          ),
        );
      }
    }
  }

  void _handleEngageDisengage() async {
    if (_engaged) {
      await _sendV1Command('steering.autopilot.state', 'standby');
    } else {
      await _sendV1Command('steering.autopilot.state', 'auto');
    }
  }

  void _handleModeChange(String mode) async {
    await _sendV1Command('steering.autopilot.state', mode.toLowerCase());
  }

  void _handleAdjustHeading(int degrees) {
    _sendV1Command('steering.autopilot.actions.adjustHeading', degrees);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.config.dataSources.length < 5) {
      return const Center(
        child: Text(
          'Autopilot requires at least 5 data sources',
          textAlign: TextAlign.center,
        ),
      );
    }

    final primaryColor = widget.config.style.primaryColor?.toColor(
      fallback: Colors.red
    ) ?? Colors.red;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Status row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatusCard('Mode', _mode, primaryColor),
              _buildStatusCard('Status', _engaged ? 'Engaged' : 'Standby',
                _engaged ? Colors.green : Colors.grey),
            ],
          ),

          const SizedBox(height: 16),

          // Heading row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildHeadingCard('Current', _currentHeading, Colors.blue),
              _buildHeadingCard('Target', _targetHeading, primaryColor),
            ],
          ),

          const SizedBox(height: 24),

          // Engage/Disengage button
          ElevatedButton.icon(
            onPressed: _handleEngageDisengage,
            icon: Icon(_engaged ? Icons.power_off : Icons.power),
            label: Text(_engaged ? 'DISENGAGE' : 'ENGAGE'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _engaged ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),

          const SizedBox(height: 16),

          // Heading adjustment buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildAdjustButton('-10°', -10, primaryColor),
              _buildAdjustButton('-1°', -1, primaryColor),
              _buildAdjustButton('+1°', 1, primaryColor),
              _buildAdjustButton('+10°', 10, primaryColor),
            ],
          ),

          const SizedBox(height: 16),

          // Mode buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _buildModeButton('Auto', primaryColor),
              _buildModeButton('Wind', primaryColor),
              _buildModeButton('Route', primaryColor),
              _buildModeButton('Standby', Colors.grey),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(String label, String value, Color color) {
    return Expanded(
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeadingCard(String label, double heading, Color color) {
    return Expanded(
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${heading.toStringAsFixed(0)}°',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdjustButton(String label, int degrees, Color color) {
    return ElevatedButton(
      onPressed: _engaged ? () => _handleAdjustHeading(degrees) : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Text(label),
    );
  }

  Widget _buildModeButton(String mode, Color color) {
    final isCurrentMode = _mode.toLowerCase() == mode.toLowerCase();

    return ElevatedButton(
      onPressed: () => _handleModeChange(mode),
      style: ElevatedButton.styleFrom(
        backgroundColor: isCurrentMode ? color : Colors.grey[300],
        foregroundColor: isCurrentMode ? Colors.white : Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      child: Text(mode),
    );
  }
}

/// Builder for simple autopilot tools
class AutopilotSimpleToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'autopilot_simple',
      name: 'Autopilot (Simple)',
      description: 'Simple text-based autopilot control without compass visualization',
      category: ToolCategory.compass,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: true,
        minPaths: 5,
        maxPaths: 10,
        styleOptions: const [
          'primaryColor',
        ],
      ),
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: [
        DataSource(path: 'steering.autopilot.state', label: 'Autopilot State'),
        DataSource(path: 'steering.autopilot.mode', label: 'Autopilot Mode'),
        DataSource(path: 'steering.autopilot.engaged', label: 'Autopilot Engaged'),
        DataSource(path: 'steering.autopilot.target.headingMagnetic', label: 'Target Heading'),
        DataSource(path: 'navigation.headingMagnetic', label: 'Current Heading'),
      ],
      style: StyleConfig(
        primaryColor: '#FF0000',
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return AutopilotSimpleTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
