import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../models/autopilot_errors.dart';
import '../../models/autopilot_config.dart';
import '../../services/signalk_service.dart';
import '../../services/autopilot_state_verifier.dart';
import '../../services/autopilot_v2_api.dart';
import '../../services/autopilot_api_detector.dart';
import '../../services/tool_registry.dart';
import '../../utils/color_extensions.dart';
import '../../utils/conversion_utils.dart';
import '../../config/ui_constants.dart';
import '../autopilot_widget.dart';
import '../route_info_panel.dart';
import '../countdown_confirmation_overlay.dart';

/// Autopilot control tool - subscribes to SignalK paths and displays autopilot controls
///
/// Supports both V1 (plugin-based PUT requests) and V2 (REST API with instance discovery).
/// Automatically detects available API version and uses V2 when available, falling back to V1.
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
  // Autopilot configuration
  AutopilotConfig _autopilotConfig = const AutopilotConfig();

  // API version and V2 support
  String? _apiVersion; // 'v1' or 'v2'
  AutopilotV2Api? _v2Api;
  String? _selectedInstanceId;
  bool _dodgeActive = false; // V2 only - dodge mode state

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

  // Route navigation data
  LatLon? _nextWaypoint;
  DateTime? _eta;
  double? _distanceToWaypoint;  // meters
  Duration? _timeToWaypoint;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Subscribe to SignalK data updates
    widget.signalKService.addListener(_onSignalKUpdate);

    // Detect API version and initialize
    _detectAndInitializeApi();

    // Do an initial update after a short delay to let subscriptions settle
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _onSignalKUpdate();
      }
    });
  }

  /// Detect API version and initialize appropriate API client
  Future<void> _detectAndInitializeApi() async {
    try {
      final detector = AutopilotApiDetector(
        baseUrl: widget.signalKService.serverUrl,
        authToken: widget.signalKService.authToken?.token,
      );

      final apiVersion = await detector.detectApiVersion();

      if (!mounted) return;

      setState(() {
        _apiVersion = apiVersion.version;

        if (apiVersion.isV2) {
          // Use default instance or first available
          final defaultInstance = apiVersion.defaultInstance;
          _selectedInstanceId = defaultInstance?.id;

          if (_selectedInstanceId != null) {
            _v2Api = AutopilotV2Api(
              baseUrl: widget.signalKService.serverUrl,
              authToken: widget.signalKService.authToken?.token,
            );

            _initializeV2Api();
          }
        } else {
          // V1 API - existing implementation
          _subscribeToAutopilotPaths();
        }
      });
    } catch (e) {
      if (kDebugMode) {
        print('API detection failed: $e');
      }
      // Fall back to V1
      setState(() {
        _apiVersion = 'v1';
      });
      _subscribeToAutopilotPaths();
    }
  }

  /// Initialize V2 API by fetching autopilot info
  Future<void> _initializeV2Api() async {
    if (_v2Api == null || _selectedInstanceId == null) return;

    try {
      // Get autopilot info and capabilities
      final info = await _v2Api!.getAutopilotInfo(_selectedInstanceId!);

      if (!mounted) return;

      setState(() {
        _engaged = info.engaged;
        _mode = info.mode ?? 'Standby';
        if (info.target != null) {
          _targetHeading = info.target!;
        }
      });

      // Still subscribe to WebSocket for real-time updates
      _subscribeToAutopilotPaths();
    } catch (e) {
      if (kDebugMode) {
        print('V2 API initialization failed: $e');
      }
    }
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
      'design.aisShipType', // Vessel type to determine if sailing
    ];

    // Optionally include route calculation paths (can be CPU-intensive on server)
    if (_autopilotConfig.enableRouteCalculations) {
      additionalPaths.addAll([
        'navigation.course.calcValues.bearingMagnetic',
        'navigation.course.calcValues.bearingTrue',
        'navigation.courseGreatCircle.nextPoint.position',
        'navigation.course.calcValues.distance',
        'navigation.course.calcValues.timeToGo',
        'navigation.course.calcValues.estimatedTimeOfArrival',
      ]);
    }

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

      // Route navigation data (only if enabled)
      if (_autopilotConfig.enableRouteCalculations) {
        // Next waypoint position
        final nextWptData = widget.signalKService.getValue('navigation.courseGreatCircle.nextPoint.position');
        if (nextWptData?.value != null && nextWptData!.value is Map) {
          _nextWaypoint = LatLon.fromJson(nextWptData.value as Map<String, dynamic>);
        }

        // Distance to waypoint (meters)
        final distanceData = widget.signalKService.getValue('navigation.course.calcValues.distance');
        if (distanceData?.value != null) {
          _distanceToWaypoint = (distanceData!.value as num).toDouble();
        }

        // Time to waypoint (seconds)
        final timeData = widget.signalKService.getValue('navigation.course.calcValues.timeToGo');
        if (timeData?.value != null) {
          final seconds = (timeData!.value as num).toInt();
          _timeToWaypoint = Duration(seconds: seconds);
        }

        // ETA (ISO 8601 string)
        final etaData = widget.signalKService.getValue('navigation.course.calcValues.estimatedTimeOfArrival');
        if (etaData?.value != null) {
          try {
            _eta = DateTime.parse(etaData!.value.toString());
          } catch (e) {
            if (kDebugMode) {
              print('Failed to parse ETA: $e');
            }
          }
        }
      }
    });
  }

  /// Unified command sending that works with both V1 and V2 APIs
  Future<void> _sendCommand({
    required String description,
    required Future<void> Function() v1Command,
    required Future<void> Function() v2Command,
    String? verifyPath,
    dynamic verifyValue,
  }) async {
    if (kDebugMode) {
      print('Sending autopilot command ($_apiVersion): $description');
    }

    try {
      // Send command via appropriate API
      if (_apiVersion == 'v2' && _v2Api != null && _selectedInstanceId != null) {
        await v2Command();
      } else {
        await v1Command();
      }

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

      // Verify state change via WebSocket (if verification path provided)
      bool verified = true;
      if (verifyPath != null && verifyValue != null) {
        final verifier = AutopilotStateVerifier(widget.signalKService);
        verified = await verifier.verifyChange(
          path: verifyPath,
          expectedValue: verifyValue,
        );

        if (kDebugMode) {
          print('Autopilot command ${verified ? "verified" : "timed out"}');
        }
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

  /// Handle engage/disengage (works with both V1 and V2)
  void _handleEngageDisengage() async {
    await _sendCommand(
      description: _engaged ? 'Disengage' : 'Engage',
      v1Command: () async {
        await widget.signalKService.sendPutRequest(
          'steering.autopilot.state',
          _engaged ? 'standby' : 'auto',
        );
      },
      v2Command: () async {
        if (_engaged) {
          await _v2Api!.disengage(_selectedInstanceId!);
        } else {
          await _v2Api!.engage(_selectedInstanceId!);
        }
      },
      verifyPath: 'steering.autopilot.state',
      verifyValue: _engaged ? 'standby' : 'auto',
    );
  }

  /// Handle mode change (works with both V1 and V2)
  void _handleModeChange(String mode) async {
    await _sendCommand(
      description: 'Mode change to $mode',
      v1Command: () async {
        await widget.signalKService.sendPutRequest(
          'steering.autopilot.state',
          mode.toLowerCase(),
        );
      },
      v2Command: () async {
        await _v2Api!.setMode(_selectedInstanceId!, mode.toLowerCase());
      },
      verifyPath: 'steering.autopilot.state',
      verifyValue: mode.toLowerCase(),
    );
  }

  /// Handle heading adjustment (works with both V1 and V2)
  void _handleAdjustHeading(int degrees) {
    _sendCommand(
      description: 'Adjust heading ${degrees > 0 ? "+" : ""}$degrees°',
      v1Command: () async {
        await widget.signalKService.sendPutRequest(
          'steering.autopilot.actions.adjustHeading',
          degrees,
        );
      },
      v2Command: () async {
        await _v2Api!.adjustTarget(_selectedInstanceId!, degrees);
      },
      verifyPath: null, // Don't verify heading adjustments
      verifyValue: null,
    );
  }

  /// Handle tack with countdown confirmation (works with both V1 and V2)
  void _handleTack(String direction) async {
    final directionLabel = direction == 'port' ? 'Port' : 'Starboard';

    // Show countdown confirmation
    final confirmed = await showCountdownConfirmation(
      context: context,
      title: 'Tack to $directionLabel?',
      action: 'Tack $directionLabel',
      countdownSeconds: _autopilotConfig.confirmationCountdownSeconds,
    );

    if (!confirmed) return;

    await _sendCommand(
      description: 'Tack $directionLabel',
      v1Command: () async {
        await widget.signalKService.sendPutRequest(
          'steering.autopilot.actions.tack',
          direction,
        );
      },
      v2Command: () async {
        await _v2Api!.tack(_selectedInstanceId!, direction);
      },
      verifyPath: null, // Tacking doesn't have a simple verification path
      verifyValue: null,
    );
  }

  /// Handle advance waypoint with countdown confirmation (V1 only - route management)
  void _handleAdvanceWaypoint() async {
    // Show countdown confirmation
    final confirmed = await showCountdownConfirmation(
      context: context,
      title: 'Advance to Next Waypoint?',
      action: 'Advance Waypoint',
      countdownSeconds: _autopilotConfig.confirmationCountdownSeconds,
    );

    if (!confirmed) return;

    await _sendCommand(
      description: 'Advance Waypoint',
      v1Command: () async {
        await widget.signalKService.sendPutRequest(
          'steering.autopilot.actions.advanceWaypoint',
          1,
        );
      },
      v2Command: () async {
        // V2 API doesn't have a standard advance waypoint endpoint yet
        // Fall back to V1 method
        await widget.signalKService.sendPutRequest(
          'steering.autopilot.actions.advanceWaypoint',
          1,
        );
      },
      verifyPath: null,
      verifyValue: null,
    );
  }

  /// Handle gybe with countdown confirmation (V2 only)
  void _handleGybe(String direction) async {
    // Check if V2 API is available
    if (_apiVersion != 'v2') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gybe support requires V2 API'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final directionLabel = direction == 'port' ? 'Port' : 'Starboard';

    // Show countdown confirmation
    final confirmed = await showCountdownConfirmation(
      context: context,
      title: 'Gybe to $directionLabel?',
      action: 'Gybe $directionLabel',
      countdownSeconds: _autopilotConfig.confirmationCountdownSeconds,
    );

    if (!confirmed) return;

    await _sendCommand(
      description: 'Gybe $directionLabel',
      v1Command: () async {
        throw UnsupportedError('Gybe not available in V1');
      },
      v2Command: () async {
        await _v2Api!.gybe(_selectedInstanceId!, direction);
      },
      verifyPath: null,
      verifyValue: null,
    );
  }

  /// Handle dodge mode toggle (V2 only)
  void _handleDodgeToggle() async {
    // Check if V2 API is available
    if (_apiVersion != 'v2') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dodge mode requires V2 API'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final newState = !_dodgeActive;

    await _sendCommand(
      description: newState ? 'Activate dodge mode' : 'Deactivate dodge mode',
      v1Command: () async {
        throw UnsupportedError('Dodge mode not available in V1');
      },
      v2Command: () async {
        if (newState) {
          await _v2Api!.activateDodge(_selectedInstanceId!);
        } else {
          await _v2Api!.deactivateDodge(_selectedInstanceId!);
        }
      },
      verifyPath: null,
      verifyValue: null,
    );

    // Update local state
    if (mounted) {
      setState(() {
        _dodgeActive = newState;
      });
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
          nextWaypoint: _nextWaypoint,
          eta: _eta,
          distanceToWaypoint: _distanceToWaypoint,
          timeToWaypoint: _timeToWaypoint,
          onlyShowXTEWhenNear: _autopilotConfig.onlyShowXTEWhenNear,
          fadeDelaySeconds: fadeDelaySeconds,
          isV2Api: _apiVersion == 'v2',
          dodgeActive: _dodgeActive,
          onEngageDisengage: _handleEngageDisengage,
          onModeChange: _handleModeChange,
          onAdjustHeading: _handleAdjustHeading,
          onTack: _handleTack,
          onGybe: _handleGybe,
          onAdvanceWaypoint: _handleAdvanceWaypoint,
          onDodgeToggle: _handleDodgeToggle,
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
      category: ToolCategory.navigation,
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
