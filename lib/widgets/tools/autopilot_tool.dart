import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/color_extensions.dart';
import '../../utils/conversion_utils.dart';
import '../../config/ui_constants.dart';
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

class _AutopilotToolState extends State<AutopilotTool> with AutomaticKeepAliveClientMixin {
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
  bool _isSailingVessel = true; // Default to true to show wind options unless we know otherwise

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Subscribe to SignalK data updates
    widget.signalKService.addListener(_onSignalKUpdate);
    _subscribeToAutopilotPaths();

    // Do an initial update after a short delay to let subscriptions settle
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

  /// Subscribe to autopilot SignalK paths from config
  void _subscribeToAutopilotPaths() {
    // Get paths from tool config data sources
    final configuredPaths = widget.config.dataSources.map((ds) => ds.path).toList();

    // Always include these additional optional paths for enhanced functionality
    final additionalPaths = [
      'steering.autopilot.target.windAngleApparent',
      'navigation.headingTrue',
      'environment.wind.angleTrueWater',
      // COMMENTED OUT - Expensive route calculations causing server CPU overload
      // 'navigation.course.calcValues.bearingMagnetic',
      // 'navigation.course.calcValues.bearingTrue',
      // 'navigation.courseGreatCircle.nextPoint.position',
      // 'navigation.course.calcValues.distance',
      // 'navigation.course.calcValues.timeToGo',
      // 'navigation.course.calcValues.estimatedTimeOfArrival',
      'design.aisShipType', // Vessel type to determine if sailing
    ];

    // Combine configured paths with additional paths (removing duplicates)
    final allPaths = {...configuredPaths, ...additionalPaths}.toList();

    // Use autopilot-specific subscription (standard SignalK stream, not units-preference)
    widget.signalKService.subscribeToAutopilotPaths(allPaths);
  }

  /// Update local state from SignalK data
  void _onSignalKUpdate() {
    if (!mounted) return;

    final dataSources = widget.config.dataSources;
    if (dataSources.isEmpty) return;

    setState(() {
      // 0: Autopilot state (REQUIRED)
      // In V1 API, steering.autopilot.state contains the mode (auto, wind, route, standby)
      if (dataSources.isNotEmpty) {
        final statePath = dataSources[0].path;
        final stateSource = dataSources[0].source;
        final stateData = widget.signalKService.getValue(statePath, source: stateSource);

        if (stateData?.value != null) {
          final rawMode = stateData!.value.toString();
          // Capitalize first letter for display consistency
          final newMode = rawMode.isNotEmpty
              ? rawMode[0].toUpperCase() + rawMode.substring(1).toLowerCase()
              : 'Standby';

          if (newMode != _mode) {
            if (kDebugMode) {
              print('🌊 Autopilot state from WebSocket delta: $_mode -> $newMode (raw: $rawMode)');
            }
            _mode = newMode;
          }
        }
        // Don't log missing data - normal when autopilot is off or not configured
      }

      // 1: Autopilot mode (optional - may be same as state in V1)
      // In V1, this is redundant with state. In V2, this would be a separate path.
      // Skip for now, using state for mode

      // 2: Autopilot engaged (optional - V2 only)
      // In V1, we derive engaged state from the mode
      final bool newEngaged;
      if (dataSources.length > 2) {
        final engagedData = widget.signalKService.getValue(
          dataSources[2].path,
          source: dataSources[2].source,
        );
        if (engagedData?.value != null && engagedData!.value is bool) {
          // V2: Use explicit engaged boolean
          newEngaged = engagedData.value as bool;
        } else {
          // V1: engaged if not in standby
          newEngaged = _mode.toLowerCase() != 'standby';
        }
      } else {
        // V1: engaged if not in standby
        newEngaged = _mode.toLowerCase() != 'standby';
      }

      if (newEngaged != _engaged) {
        if (kDebugMode) {
          print('Autopilot engaged state changed: $_engaged -> $newEngaged');
        }
        _engaged = newEngaged;
      }

      // 3: Target heading (REQUIRED)
      if (dataSources.length > 3) {
        final converted = ConversionUtils.getConvertedValue(
          widget.signalKService,
          dataSources[3].path,
        );
        if (converted != null) {
          _targetHeading = converted;
        }
      }

      // 4: Current heading (REQUIRED)
      if (dataSources.length > 4) {
        final converted = ConversionUtils.getConvertedValue(
          widget.signalKService,
          dataSources[4].path,
        );
        if (converted != null) {
          _currentHeading = converted;
        }
      }

      // 5: Rudder angle (REQUIRED)
      if (dataSources.length > 5) {
        final converted = ConversionUtils.getConvertedValue(
          widget.signalKService,
          dataSources[5].path,
        );
        if (converted != null) {
          // Invert by default (positive rudder = turn right = card turns left visually)
          _rudderAngle = -converted;

          // Apply additional invert rudder config if set (for double-negative = normal)
          final invertRudder = widget.config.style.customProperties?['invertRudder'] as bool? ?? false;
          if (invertRudder) {
            _rudderAngle = -_rudderAngle;
          }
        }
      }

      // 6: Apparent wind angle (optional)
      if (dataSources.length > 6) {
        final converted = ConversionUtils.getConvertedValue(
          widget.signalKService,
          dataSources[6].path,
        );
        if (converted != null) {
          _apparentWindAngle = converted;
        }
      }

      // 7: Cross track error (optional)
      if (dataSources.length > 7) {
        final xteData = widget.signalKService.getValue(
          dataSources[7].path,
          source: dataSources[7].source,
        );
        if (xteData?.value != null) {
          _crossTrackError = (xteData!.value as num).toDouble();
        }
      }

      // Additional paths not in config but subscribed
      // True heading (optional)
      final convertedHeadingTrue = ConversionUtils.getConvertedValue(
        widget.signalKService,
        'navigation.headingTrue',
      );
      if (convertedHeadingTrue != null) {
        _currentHeadingTrue = convertedHeadingTrue;
      }

      // True wind angle (optional)
      final convertedTwa = ConversionUtils.getConvertedValue(
        widget.signalKService,
        'environment.wind.angleTrueWater',
      );
      if (convertedTwa != null) {
        _trueWindAngle = convertedTwa;
      }

      // Vessel type (to determine if sailing)
      final vesselTypeData = widget.signalKService.getValue('design.aisShipType');
      if (vesselTypeData?.value != null) {
        final vesselType = vesselTypeData!.value;
        if (vesselType is Map) {
          // Check both name and id for sailing vessel
          final name = vesselType['name']?.toString().toLowerCase() ?? '';
          final id = vesselType['id'];
          _isSailingVessel = name.contains('sail') || id == 36;
        } else if (vesselType is num) {
          // If it's just the id number
          _isSailingVessel = vesselType == 36;
        }
      }
    });
  }

  /// Send V1 autopilot command via PUT request
  Future<void> _sendV1Command(String path, dynamic value) async {
    if (kDebugMode) {
      print('Sending autopilot command: $path = $value');
    }

    try {
      await widget.signalKService.sendPutRequest(path, value);

      if (kDebugMode) {
        print('Autopilot command sent successfully');
      }

      // Show success feedback briefly
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Command sent: $value'),
            backgroundColor: Colors.green,
            duration: UIConstants.snackBarShort,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Autopilot command failed: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Autopilot command failed: $e'),
            backgroundColor: Colors.red,
            duration: UIConstants.snackBarLong,
          ),
        );
      }
    }
  }

  /// Handle engage/disengage
  void _handleEngageDisengage() async {
    if (_engaged) {
      // Disengage: set to standby
      await _sendV1Command('steering.autopilot.state', 'standby');
      // UI will update when WebSocket delta confirms state change
    } else {
      // Engage: set to auto mode
      await _sendV1Command('steering.autopilot.state', 'auto');
      // UI will update when WebSocket delta confirms state change
    }
  }

  /// Handle mode change
  void _handleModeChange(String mode) async {
    await _sendV1Command('steering.autopilot.state', mode.toLowerCase());
    // UI will update when WebSocket delta confirms state change
  }

  /// Handle heading adjustment
  void _handleAdjustHeading(int degrees) {
    _sendV1Command('steering.autopilot.actions.adjustHeading', degrees);
    // No verification needed for heading adjustments
  }

  /// Handle tack with confirmation
  void _handleTack(String direction) async {
    // Show confirmation dialog for tacking
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Tack ${direction == 'port' ? 'to Port' : 'to Starboard'}'),
        content: Text(
          'Are you sure you want to tack to ${direction == 'port' ? 'port' : 'starboard'}?\n\n'
          'This will initiate an autopilot tack maneuver.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: direction == 'port' ? Colors.red : Colors.green,
            ),
            child: Text('Tack ${direction == 'port' ? 'Port' : 'Starboard'}'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _sendV1Command('steering.autopilot.actions.tack', direction);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

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
    final primaryColor = widget.config.style.primaryColor?.toColor(
      fallback: Colors.red
    ) ?? Colors.red;

    // Get heading preference from config
    final headingTrue = widget.config.style.customProperties?['headingTrue'] as bool? ?? false;

    // Get polar configuration from config (same fields as wind compass)
    final targetAWA = widget.config.style.laylineAngle ?? 40.0;
    final targetTolerance = widget.config.style.targetTolerance ?? 3.0;

    // Get fade delay from config
    final fadeDelaySeconds = widget.config.style.customProperties?['fadeDelaySeconds'] as int? ?? 5;

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

    // Calculate absolute wind directions for compass display
    double? apparentWindDir;
    double? trueWindDir;

    if (_apparentWindAngle != null) {
      apparentWindDir = (displayHeading + _apparentWindAngle!) % 360;
      if (apparentWindDir < 0) apparentWindDir += 360;
    }

    if (_trueWindAngle != null) {
      trueWindDir = (displayHeading + _trueWindAngle!) % 360;
      if (trueWindDir < 0) trueWindDir += 360;
    }

    // Show wind indicators only in wind mode
    final isWindMode = _mode.toLowerCase() == 'wind' || _mode.toLowerCase() == 'true wind';

    return Stack(
      children: [
        AutopilotWidget(
          currentHeading: displayHeading,
          targetHeading: _targetHeading,
          rudderAngle: _rudderAngle,
          mode: _mode,
          engaged: _engaged,
          apparentWindAngle: displayWindAngle,
          apparentWindDirection: apparentWindDir,
          trueWindDirection: trueWindDir,
          crossTrackError: _crossTrackError,
          headingTrue: headingTrue,
          showWindIndicators: isWindMode,
          primaryColor: primaryColor,
          isSailingVessel: _isSailingVessel,
          targetAWA: targetAWA,
          targetTolerance: targetTolerance,
          fadeDelaySeconds: fadeDelaySeconds,
          onEngageDisengage: _handleEngageDisengage,
          onModeChange: _handleModeChange,
          onAdjustHeading: _handleAdjustHeading,
          onTack: _handleTack,
        ),
      ],
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
      category: ToolCategory.compass,
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
          'laylineAngle',     // Number: optimal close-hauled angle (degrees) - same as wind compass
          'targetTolerance',  // Number: acceptable deviation from target (degrees) - same as wind compass
          'fadeDelaySeconds', // Number: seconds before controls fade (default: 5)
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
        laylineAngle: 40.0,      // Default target AWA
        targetTolerance: 3.0,    // Default tolerance
        customProperties: {
          'fadeDelaySeconds': 5,  // Default fade delay in seconds
        },
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
