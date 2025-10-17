import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../autopilot_widget.dart';

/// Autopilot control tool - subscribes to SignalK paths and displays autopilot controls
/// Supports both V1 (plugin-based) and V2 (REST API-based) autopilot systems
///
/// Expected data sources (in order):
/// 0: steering.autopilot.state (REQUIRED)
/// 1: steering.autopilot.mode (REQUIRED)
/// 2: steering.autopilot.engaged (optional - V2 only)
/// 3: steering.autopilot.target.headingMagnetic (REQUIRED)
/// 4: navigation.headingMagnetic (REQUIRED)
/// 5: steering.rudderAngle (REQUIRED)
/// 6: environment.wind.angleApparent (optional)
/// 7: navigation.course.calcValues.crossTrackError (optional)
class AutopilotTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const AutopilotTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<AutopilotTool> createState() => _AutopilotToolState();
}

class _AutopilotToolState extends State<AutopilotTool> {
  // Autopilot state from SignalK
  double _currentHeading = 0;
  double _currentHeadingTrue = 0;
  double _targetHeading = 0;
  double _rudderAngle = 0;
  String _mode = 'Standby';
  bool _engaged = false;
  double? _apparentWindAngle;
  double? _trueWindAngle;
  double? _crossTrackError;

  @override
  void initState() {
    super.initState();
    // Subscribe to SignalK data updates
    widget.signalKService.addListener(_onSignalKUpdate);
    _subscribeToAutopilotPaths();
  }

  @override
  void dispose() {
    widget.signalKService.removeListener(_onSignalKUpdate);
    super.dispose();
  }

  /// Subscribe to autopilot SignalK paths from config
  void _subscribeToAutopilotPaths() {
    // Get paths from tool config data sources
    final configuredPaths = widget.config.dataSources.map((ds) => ds.path).toList();

    // Always include these additional optional paths for enhanced functionality
    final additionalPaths = [
      'steering.autopilot.target.windAngleApparent',
      'navigation.headingTrue',
      'environment.wind.angleTrueWater',
      'navigation.course.calcValues.bearingMagnetic',
      'navigation.course.calcValues.bearingTrue',
      'navigation.courseGreatCircle.nextPoint.position',
      'navigation.course.calcValues.distance',
      'navigation.course.calcValues.timeToGo',
      'navigation.course.calcValues.estimatedTimeOfArrival',
    ];

    // Combine configured paths with additional paths (removing duplicates)
    final allPaths = {...configuredPaths, ...additionalPaths}.toList();

    widget.signalKService.subscribeToPaths(allPaths);
  }

  /// Update local state from SignalK data
  void _onSignalKUpdate() {
    if (!mounted) return;

    final dataSources = widget.config.dataSources;
    if (dataSources.isEmpty) return;

    setState(() {
      // 0: Autopilot state (REQUIRED)
      if (dataSources.isNotEmpty) {
        final stateData = widget.signalKService.getValue(dataSources[0].path);
        if (stateData?.value != null) {
          _mode = stateData!.value.toString();
        }
      }

      // 1: Autopilot mode (optional - may be same as state in V1)
      // Skip for now, using state for mode

      // 2: Autopilot engaged (optional - V2 only)
      if (dataSources.length > 2) {
        final engagedData = widget.signalKService.getValue(dataSources[2].path);
        if (engagedData?.value != null) {
          _engaged = engagedData!.value as bool;
        } else {
          // V1: engaged if not in standby
          _engaged = _mode.toLowerCase() != 'standby';
        }
      } else {
        // V1: engaged if not in standby
        _engaged = _mode.toLowerCase() != 'standby';
      }

      // 3: Target heading (REQUIRED)
      if (dataSources.length > 3) {
        final targetData = widget.signalKService.getValue(dataSources[3].path);
        if (targetData?.value != null) {
          _targetHeading = _radiansToDegrees(targetData!.value as num);
        }
      }

      // 4: Current heading (REQUIRED)
      if (dataSources.length > 4) {
        final headingData = widget.signalKService.getValue(dataSources[4].path);
        if (headingData?.value != null) {
          _currentHeading = _radiansToDegrees(headingData!.value as num);
        }
      }

      // 5: Rudder angle (REQUIRED)
      if (dataSources.length > 5) {
        final rudderData = widget.signalKService.getValue(dataSources[5].path);
        if (rudderData?.value != null) {
          _rudderAngle = _radiansToDegrees(rudderData!.value as num);

          // Apply invert rudder config if set
          final invertRudder = widget.config.style.customProperties?['invertRudder'] as bool? ?? false;
          if (invertRudder) {
            _rudderAngle = -_rudderAngle;
          }
        }
      }

      // 6: Apparent wind angle (optional)
      if (dataSources.length > 6) {
        final awaData = widget.signalKService.getValue(dataSources[6].path);
        if (awaData?.value != null) {
          _apparentWindAngle = _radiansToDegrees(awaData!.value as num);
        }
      }

      // 7: Cross track error (optional)
      if (dataSources.length > 7) {
        final xteData = widget.signalKService.getValue(dataSources[7].path);
        if (xteData?.value != null) {
          _crossTrackError = (xteData!.value as num).toDouble();
        }
      }

      // Additional paths not in config but subscribed
      // True heading (optional)
      final headingTrueData = widget.signalKService.getValue('navigation.headingTrue');
      if (headingTrueData?.value != null) {
        _currentHeadingTrue = _radiansToDegrees(headingTrueData!.value as num);
      }

      // True wind angle (optional)
      final twaData = widget.signalKService.getValue('environment.wind.angleTrueWater');
      if (twaData?.value != null) {
        _trueWindAngle = _radiansToDegrees(twaData!.value as num);
      }
    });
  }

  /// Convert radians to degrees
  double _radiansToDegrees(num radians) {
    return (radians * 180 / 3.14159265359) % 360;
  }

  /// Send V1 autopilot command via PUT request
  Future<void> _sendV1Command(String path, dynamic value) async {
    try {
      await widget.signalKService.sendPutRequest(path, value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Autopilot command failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Handle engage/disengage
  void _handleEngageDisengage() {
    if (_engaged) {
      // Disengage: set to standby
      _sendV1Command('steering.autopilot.state', 'standby');
    } else {
      // Engage: set to auto mode
      _sendV1Command('steering.autopilot.state', 'auto');
    }
  }

  /// Handle mode change
  void _handleModeChange(String mode) {
    _sendV1Command('steering.autopilot.state', mode.toLowerCase());
  }

  /// Handle heading adjustment
  void _handleAdjustHeading(int degrees) {
    _sendV1Command('steering.autopilot.actions.adjustHeading', degrees);
  }

  /// Handle tack
  void _handleTack(String direction) {
    _sendV1Command('steering.autopilot.actions.tack', direction);
  }

  @override
  Widget build(BuildContext context) {
    // Check minimum configuration
    if (widget.config.dataSources.length < 6) {
      return const Center(
        child: Text(
          'Autopilot requires at least 6 data sources:\n'
          '1. Autopilot State\n'
          '2. Autopilot Mode\n'
          '3. Autopilot Engaged\n'
          '4. Target Heading\n'
          '5. Current Heading\n'
          '6. Rudder Angle',
          textAlign: TextAlign.center,
        ),
      );
    }

    // Parse color from hex string
    Color primaryColor = Colors.red;
    if (widget.config.style.primaryColor != null) {
      try {
        final colorString = widget.config.style.primaryColor!.replaceAll('#', '');
        primaryColor = Color(int.parse('FF$colorString', radix: 16));
      } catch (e) {
        // Keep default color if parsing fails
      }
    }

    // Get heading preference from config
    final headingTrue = widget.config.style.customProperties?['headingTrue'] as bool? ?? false;

    // Select the appropriate heading based on config
    final displayHeading = headingTrue ? _currentHeadingTrue : _currentHeading;

    // Determine which wind angle to display based on mode
    double? displayWindAngle;
    if (_mode.toLowerCase() == 'wind') {
      // In wind mode, show apparent wind angle
      displayWindAngle = _apparentWindAngle;
    } else if (_mode.toLowerCase() == 'true wind') {
      // In true wind mode, show true wind angle
      displayWindAngle = _trueWindAngle;
    }

    return AutopilotWidget(
      currentHeading: displayHeading,
      targetHeading: _targetHeading,
      rudderAngle: _rudderAngle,
      mode: _mode,
      engaged: _engaged,
      apparentWindAngle: displayWindAngle,
      crossTrackError: _crossTrackError,
      headingTrue: headingTrue,
      primaryColor: primaryColor,
      onEngageDisengage: _handleEngageDisengage,
      onModeChange: _handleModeChange,
      onAdjustHeading: _handleAdjustHeading,
      onTack: _handleTack,
    );
  }
}

/// Builder for autopilot tools
class AutopilotToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'autopilot',
      name: 'Autopilot',
      description: 'Full autopilot control with compass display, mode selection, and tacking. Supports V1 (plugin) and V2 (REST) autopilot APIs.',
      category: ToolCategory.control,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: true,
        minPaths: 6,
        maxPaths: 10,
        styleOptions: const [
          'primaryColor',
          'headingTrue',      // Boolean: use true vs magnetic heading
          'invertRudder',     // Boolean: invert rudder angle display
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
        DataSource(path: 'steering.autopilot.engaged', label: 'Autopilot Engaged (V2 only)'),
        DataSource(path: 'steering.autopilot.target.headingMagnetic', label: 'Target Heading'),
        DataSource(path: 'navigation.headingMagnetic', label: 'Current Heading'),
        DataSource(path: 'steering.rudderAngle', label: 'Rudder Angle'),
        DataSource(path: 'environment.wind.angleApparent', label: 'Apparent Wind Angle'),
        DataSource(path: 'navigation.course.calcValues.crossTrackError', label: 'Cross Track Error'),
      ],
      style: StyleConfig(
        primaryColor: '#FF0000', // Red for autopilot
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return AutopilotTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
