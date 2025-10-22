import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/color_extensions.dart';
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

  // Adaptive polling - fast after commands, slow during monitoring
  Timer? _pollingTimer;
  DateTime? _lastCommandTime;
  DateTime? _lastOptimisticUpdate; // Track when we did an optimistic UI update
  static const Duration _fastPollingInterval = Duration(seconds: 5);
  static const Duration _slowPollingInterval = Duration(seconds: 30);
  static const Duration _fastPollingDuration = Duration(seconds: 30); // Stay fast for 30s after command
  static const Duration _optimisticUpdateWindow = Duration(seconds: 3); // Ignore WebSocket for 3s after optimistic update

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
        // REST polling disabled - causes server overload and doesn't support sources
        // WebSocket deltas are the primary and reliable data source
        // _startPolling();
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
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

  /// Get the current polling interval based on recent command activity
  Duration _getPollingInterval() {
    if (_lastCommandTime == null) return _slowPollingInterval;

    final timeSinceCommand = DateTime.now().difference(_lastCommandTime!);
    if (timeSinceCommand < _fastPollingDuration) {
      return _fastPollingInterval;
    }
    return _slowPollingInterval;
  }

  /// Notify that a command was sent (called by autopilot widget)
  void onCommandSent() {
    _lastCommandTime = DateTime.now();
    // Restart polling with fast interval
    _restartPolling();
  }

  /// Restart polling with current interval
  void _restartPolling() {
    _pollingTimer?.cancel();
    _scheduleNextPoll();
  }

  /// Schedule the next poll
  void _scheduleNextPoll() {
    if (!mounted) return;

    final interval = _getPollingInterval();
    _pollingTimer = Timer(interval, () async {
      if (!mounted) return;

      try {
        await _pollAutopilotState();
      } catch (e) {
        if (kDebugMode) {
          print('Error polling autopilot state: $e');
        }
      }

      // Schedule next poll
      _scheduleNextPoll();
    });
  }

  /// Start adaptive polling autopilot state via REST API as fallback
  /// Polls every 5s after commands, 30s during normal monitoring
  void _startPolling() {
    if (kDebugMode) {
      print('Started adaptive autopilot polling (5s after commands, 30s normally)');
    }
    _scheduleNextPoll();
  }

  /// Poll autopilot state from REST API
  Future<void> _pollAutopilotState() async {
    try {
      // Use the SignalK service to fetch current autopilot state
      // Wrap each call individually to handle timeouts gracefully
      final stateValue = await widget.signalKService.getRestValue('steering.autopilot.state')
          .timeout(const Duration(seconds: 8), onTimeout: () => null);

      final targetValue = await widget.signalKService.getRestValue('steering.autopilot.target.headingMagnetic')
          .timeout(const Duration(seconds: 8), onTimeout: () => null);

      if (!mounted) return;

      bool stateChanged = false;

      setState(() {
        // Update state if we got a value from REST API
        if (stateValue != null) {
          final rawMode = stateValue.toString();
          final newMode = rawMode.isNotEmpty
              ? rawMode[0].toUpperCase() + rawMode.substring(1).toLowerCase()
              : 'Standby';

          if (newMode != _mode) {
            if (kDebugMode) {
              print('📡 Autopilot state from REST API: $_mode -> $newMode');
            }
            _mode = newMode;
            stateChanged = true;
          }

          // Update engaged status
          final newEngaged = _mode.toLowerCase() != 'standby';
          if (newEngaged != _engaged) {
            _engaged = newEngaged;
          stateChanged = true;
        }
      }

      // Update target heading from REST API
      if (targetValue != null && targetValue is num) {
        _targetHeading = _radiansToDegrees(targetValue);
      }
    });

    if (stateChanged && kDebugMode) {
      print('State updated from REST polling: mode=$_mode, engaged=$_engaged');
    }
    } catch (e) {
      // Silently ignore polling errors - WebSocket deltas are primary data source
      // Only log in debug mode to avoid console spam
      if (kDebugMode) {
        print('Autopilot polling error (non-critical): $e');
      }
    }
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

          // Ignore WebSocket updates for a few seconds after optimistic update
          // This prevents stale deltas from undoing our optimistic UI
          final shouldIgnoreWebSocket = _lastOptimisticUpdate != null &&
              DateTime.now().difference(_lastOptimisticUpdate!) < _optimisticUpdateWindow;

          if (newMode != _mode && !shouldIgnoreWebSocket) {
            if (kDebugMode) {
              print('🌊 Autopilot state from WebSocket delta: $_mode -> $newMode (raw: $rawMode)');
            }
            _mode = newMode;
          }
          // Don't log ignored deltas - happens too frequently and floods console
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
        final targetData = widget.signalKService.getValue(
          dataSources[3].path,
          source: dataSources[3].source,
        );
        if (targetData?.value != null) {
          // Value is already in degrees from units-preference plugin
          _targetHeading = (targetData!.value as num).toDouble();
        }
      }

      // 4: Current heading (REQUIRED) - THIS IS THE KEY ONE!
      if (dataSources.length > 4) {
        final headingData = widget.signalKService.getValue(
          dataSources[4].path,
          source: 'can0.115', // HARDCODED FOR TESTING
        );
        if (headingData?.value != null) {
          // Value is already in degrees from units-preference plugin's converted field
          final newHeading = (headingData!.value as num).toDouble();
          _currentHeading = newHeading;
        }
        // Don't log missing data - normal during startup or when disconnected
      }

      // 5: Rudder angle (REQUIRED)
      if (dataSources.length > 5) {
        final rudderData = widget.signalKService.getValue(
          dataSources[5].path,
          source: dataSources[5].source,
        );
        if (rudderData?.value != null) {
          // Value is already in degrees from units-preference plugin
          // Invert by default (positive rudder = turn right = card turns left visually)
          _rudderAngle = -(rudderData!.value as num).toDouble();

          // Apply additional invert rudder config if set (for double-negative = normal)
          final invertRudder = widget.config.style.customProperties?['invertRudder'] as bool? ?? false;
          if (invertRudder) {
            _rudderAngle = -_rudderAngle;
          }
        }
      }

      // 6: Apparent wind angle (optional)
      if (dataSources.length > 6) {
        final awaData = widget.signalKService.getValue(
          dataSources[6].path,
          source: dataSources[6].source,
        );
        if (awaData?.value != null) {
          // Value is already in degrees from units-preference plugin
          _apparentWindAngle = (awaData!.value as num).toDouble();
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
      final headingTrueData = widget.signalKService.getValue('navigation.headingTrue');
      if (headingTrueData?.value != null) {
        // Value is already in degrees from units-preference plugin
        _currentHeadingTrue = (headingTrueData!.value as num).toDouble();
      }

      // True wind angle (optional)
      final twaData = widget.signalKService.getValue('environment.wind.angleTrueWater');
      if (twaData?.value != null) {
        // Value is already in degrees from units-preference plugin
        _trueWindAngle = (twaData!.value as num).toDouble();
      }
    });
  }

  /// Convert radians to degrees
  double _radiansToDegrees(num radians) {
    return (radians * 180 / 3.14159265359) % 360;
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
            duration: const Duration(milliseconds: 1000),
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
            duration: const Duration(seconds: 3),
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
      // Only update UI after command succeeds
      if (mounted) {
        setState(() {
          _mode = 'Standby';
          _engaged = false;
          _lastOptimisticUpdate = DateTime.now(); // Block WebSocket for 3s
        });
      }
    } else {
      // Engage: set to auto mode
      await _sendV1Command('steering.autopilot.state', 'auto');
      // Only update UI after command succeeds
      if (mounted) {
        setState(() {
          _mode = 'Auto';
          _engaged = true;
          _lastOptimisticUpdate = DateTime.now(); // Block WebSocket for 3s
        });
      }
    }
  }

  /// Handle mode change
  void _handleModeChange(String mode) async {
    await _sendV1Command('steering.autopilot.state', mode.toLowerCase());
    // Only update UI after command succeeds
    if (mounted) {
      setState(() {
        final capitalizedMode = mode[0].toUpperCase() + mode.substring(1).toLowerCase();
        _mode = capitalizedMode;
        _engaged = mode.toLowerCase() != 'standby';
        _lastOptimisticUpdate = DateTime.now(); // Block WebSocket for 3s
      });
    }
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
          onEngageDisengage: _handleEngageDisengage,
          onModeChange: _handleModeChange,
          onAdjustHeading: _handleAdjustHeading,
          onTack: _handleTack,
        ),
        // Debug overlay button (only in debug mode)
        if (kDebugMode)
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.bug_report, color: Colors.orange),
              onPressed: _showDebugInfo,
            ),
          ),
      ],
    );
  }

  /// Show debug information dialog
  void _showDebugInfo() {
    final autopilotPaths = widget.signalKService.latestData.keys
        .where((k) => k.contains('autopilot') || k.contains('steering'))
        .toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Autopilot Debug Info'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Current Mode: $_mode', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Engaged: $_engaged', style: const TextStyle(fontWeight: FontWeight.bold)),
              const Divider(),
              const Text('Configured Paths:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...widget.config.dataSources.map((ds) => Text('  ${ds.path}')),
              const Divider(),
              const Text('Available Autopilot Paths:', style: TextStyle(fontWeight: FontWeight.bold)),
              if (autopilotPaths.isEmpty)
                const Text('  No autopilot paths found!', style: TextStyle(color: Colors.red))
              else
                ...autopilotPaths.map((path) {
                  final data = widget.signalKService.getValue(path);
                  return Text('  $path: ${data?.value}');
                }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              _onSignalKUpdate();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Force refreshed')),
              );
            },
            child: const Text('Force Refresh'),
          ),
        ],
      ),
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
