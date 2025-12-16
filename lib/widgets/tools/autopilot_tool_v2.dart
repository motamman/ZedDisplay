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
import '../autopilot_widget_v2.dart';
import '../route_info_panel.dart';
import '../countdown_confirmation_overlay.dart';

/// Autopilot V2 control tool - reimagined design with center circle controls
///
/// Features:
/// - Controls nested in center circle
/// - +10, -10, +1, -1 buttons arced around inner circle edge
/// - Mode and engage/disengage in center
///
/// Supports both V1 (plugin-based PUT requests) and V2 (REST API with instance discovery).
class AutopilotToolV2 extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const AutopilotToolV2({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<AutopilotToolV2> createState() => _AutopilotToolV2State();
}

class _AutopilotToolV2State extends State<AutopilotToolV2> with AutomaticKeepAliveClientMixin {
  final AutopilotConfig _autopilotConfig = const AutopilotConfig();

  String? _apiVersion;
  AutopilotV2Api? _v2Api;
  String? _selectedInstanceId;
  bool _dodgeActive = false;

  double _currentHeading = 0;
  double _currentHeadingTrue = 0;
  double _targetHeading = 0;
  double _rudderAngle = 0;
  String _mode = 'Standby';
  bool _engaged = false;
  double? _apparentWindAngle;
  double? _trueWindAngle;
  double? _crossTrackError;
  bool _isSailingVessel = true;

  LatLon? _nextWaypoint;
  DateTime? _eta;
  double? _distanceToWaypoint;
  Duration? _timeToWaypoint;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.signalKService.addListener(_onSignalKUpdate);
    _detectAndInitializeApi();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _onSignalKUpdate();
      }
    });
  }

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
          _subscribeToAutopilotPaths();
        }
      });
    } catch (e) {
      if (kDebugMode) {
        print('API detection failed: $e');
      }
      setState(() {
        _apiVersion = 'v1';
      });
      _subscribeToAutopilotPaths();
    }
  }

  Future<void> _initializeV2Api() async {
    if (_v2Api == null || _selectedInstanceId == null) return;

    try {
      final info = await _v2Api!.getAutopilotInfo(_selectedInstanceId!);

      if (!mounted) return;

      setState(() {
        _engaged = info.engaged;
        _mode = info.mode ?? 'Standby';
        if (info.target != null) {
          _targetHeading = info.target!;
        }
      });

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

  void _subscribeToAutopilotPaths() {
    final configuredPaths = widget.config.dataSources.map((ds) => ds.path).toList();

    final additionalPaths = [
      'steering.autopilot.target.windAngleApparent',
      'navigation.headingTrue',
      'environment.wind.angleTrueWater',
      'design.aisShipType',
    ];

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

    final allPaths = {...configuredPaths, ...additionalPaths}.toList();
    widget.signalKService.subscribeToAutopilotPaths(allPaths);
  }

  void _onSignalKUpdate() {
    if (!mounted) return;

    final dataSources = widget.config.dataSources;
    if (dataSources.isEmpty) return;

    setState(() {
      if (dataSources.isNotEmpty) {
        final statePath = dataSources[0].path;
        final stateSource = dataSources[0].source;
        final stateData = widget.signalKService.getValue(statePath, source: stateSource);

        if (stateData?.value != null) {
          final rawMode = stateData!.value.toString();
          final newMode = rawMode.isNotEmpty
              ? rawMode[0].toUpperCase() + rawMode.substring(1).toLowerCase()
              : 'Standby';

          if (newMode != _mode) {
            _mode = newMode;
          }
        }
      }

      final bool newEngaged;
      if (dataSources.length > 2) {
        final engagedData = widget.signalKService.getValue(
          dataSources[2].path,
          source: dataSources[2].source,
        );
        if (engagedData?.value != null && engagedData!.value is bool) {
          newEngaged = engagedData.value as bool;
        } else {
          newEngaged = _mode.toLowerCase() != 'standby';
        }
      } else {
        newEngaged = _mode.toLowerCase() != 'standby';
      }

      if (newEngaged != _engaged) {
        _engaged = newEngaged;
      }

      if (dataSources.length > 3) {
        final converted = ConversionUtils.getConvertedValue(
          widget.signalKService,
          dataSources[3].path,
        );
        if (converted != null) {
          _targetHeading = converted;
        }
      }

      if (dataSources.length > 4) {
        final converted = ConversionUtils.getConvertedValue(
          widget.signalKService,
          dataSources[4].path,
        );
        if (converted != null) {
          _currentHeading = converted;
        }
      }

      if (dataSources.length > 5) {
        final converted = ConversionUtils.getConvertedValue(
          widget.signalKService,
          dataSources[5].path,
        );
        if (converted != null) {
          _rudderAngle = -converted;
          final invertRudder = widget.config.style.customProperties?['invertRudder'] as bool? ?? false;
          if (invertRudder) {
            _rudderAngle = -_rudderAngle;
          }
        }
      }

      if (dataSources.length > 6) {
        final converted = ConversionUtils.getConvertedValue(
          widget.signalKService,
          dataSources[6].path,
        );
        if (converted != null) {
          _apparentWindAngle = converted;
        }
      }

      if (dataSources.length > 7) {
        final xteData = widget.signalKService.getValue(
          dataSources[7].path,
          source: dataSources[7].source,
        );
        if (xteData?.value != null) {
          _crossTrackError = (xteData!.value as num).toDouble();
        }
      }

      final convertedHeadingTrue = ConversionUtils.getConvertedValue(
        widget.signalKService,
        'navigation.headingTrue',
      );
      if (convertedHeadingTrue != null) {
        _currentHeadingTrue = convertedHeadingTrue;
      }

      final convertedTwa = ConversionUtils.getConvertedValue(
        widget.signalKService,
        'environment.wind.angleTrueWater',
      );
      if (convertedTwa != null) {
        _trueWindAngle = convertedTwa;
      }

      final vesselTypeData = widget.signalKService.getValue('design.aisShipType');
      if (vesselTypeData?.value != null) {
        final vesselType = vesselTypeData!.value;
        if (vesselType is Map) {
          final name = vesselType['name']?.toString().toLowerCase() ?? '';
          final id = vesselType['id'];
          _isSailingVessel = name.contains('sail') || id == 36;
        } else if (vesselType is num) {
          _isSailingVessel = vesselType == 36;
        }
      }

      if (_autopilotConfig.enableRouteCalculations) {
        final nextWptData = widget.signalKService.getValue('navigation.courseGreatCircle.nextPoint.position');
        if (nextWptData?.value != null && nextWptData!.value is Map) {
          _nextWaypoint = LatLon.fromJson(nextWptData.value as Map<String, dynamic>);
        }

        final distanceData = widget.signalKService.getValue('navigation.course.calcValues.distance');
        if (distanceData?.value != null) {
          _distanceToWaypoint = (distanceData!.value as num).toDouble();
        }

        final timeData = widget.signalKService.getValue('navigation.course.calcValues.timeToGo');
        if (timeData?.value != null) {
          final seconds = (timeData!.value as num).toInt();
          _timeToWaypoint = Duration(seconds: seconds);
        }

        final etaData = widget.signalKService.getValue('navigation.course.calcValues.estimatedTimeOfArrival');
        if (etaData?.value != null) {
          try {
            _eta = DateTime.parse(etaData!.value.toString());
          } catch (e) {
            // Ignore parse errors
          }
        }
      }
    });
  }

  Future<void> _sendCommand({
    required String description,
    required Future<void> Function() v1Command,
    required Future<void> Function() v2Command,
    String? verifyPath,
    dynamic verifyValue,
  }) async {
    try {
      if (_apiVersion == 'v2' && _v2Api != null && _selectedInstanceId != null) {
        await v2Command();
      } else {
        await v1Command();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sending command...'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }

      bool verified = true;
      if (verifyPath != null && verifyValue != null) {
        final verifier = AutopilotStateVerifier(widget.signalKService);
        verified = await verifier.verifyChange(
          path: verifyPath,
          expectedValue: verifyValue,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(verified
                ? 'Command successful'
                : 'Command sent but not confirmed'),
            backgroundColor: verified ? Colors.green : Colors.orange,
            duration: UIConstants.snackBarShort,
          ),
        );
      }
    } on AutopilotException catch (e) {
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
      verifyPath: null,
      verifyValue: null,
    );
  }

  void _handleTack(String direction) async {
    final directionLabel = direction == 'port' ? 'Port' : 'Starboard';

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
      verifyPath: null,
      verifyValue: null,
    );
  }

  void _handleAdvanceWaypoint() async {
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
        await widget.signalKService.sendPutRequest(
          'steering.autopilot.actions.advanceWaypoint',
          1,
        );
      },
      verifyPath: null,
      verifyValue: null,
    );
  }

  void _handleGybe(String direction) async {
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

  void _handleDodgeToggle() async {
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

    if (mounted) {
      setState(() {
        _dodgeActive = newState;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

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

    final primaryColor = widget.config.style.primaryColor?.toColor(
      fallback: Colors.red
    ) ?? Colors.red;

    final headingTrue = widget.config.style.customProperties?['headingTrue'] as bool? ?? false;
    final targetAWA = widget.config.style.laylineAngle ?? 40.0;
    final targetTolerance = widget.config.style.targetTolerance ?? 3.0;
    final fadeDelaySeconds = widget.config.style.customProperties?['fadeDelaySeconds'] as int? ?? 5;

    final displayHeading = headingTrue ? _currentHeadingTrue : _currentHeading;

    double? displayWindAngle;
    if (_mode.toLowerCase() == 'wind') {
      displayWindAngle = _apparentWindAngle;
    } else if (_mode.toLowerCase() == 'true wind') {
      displayWindAngle = _trueWindAngle;
    }

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

    final isWindMode = _mode.toLowerCase() == 'wind' || _mode.toLowerCase() == 'true wind';

    return AutopilotWidgetV2(
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
    );
  }
}

/// Builder for autopilot V2 tools
class AutopilotToolV2Builder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'autopilot_v2',
      name: 'Autopilot V2',
      description: 'Reimagined autopilot control with center circle design. +10/-10/+1/-1 buttons arc around the inner circle.',
      category: ToolCategory.navigation,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: true,
        minPaths: 6,
        maxPaths: 10,
        styleOptions: const [
          'primaryColor',
          'headingTrue',
          'invertRudder',
          'laylineAngle',
          'targetTolerance',
          'fadeDelaySeconds',
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
        primaryColor: '#FF0000',
        laylineAngle: 40.0,
        targetTolerance: 3.0,
        customProperties: {
          'fadeDelaySeconds': 5,
        },
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return AutopilotToolV2(
      config: config,
      signalKService: signalKService,
    );
  }
}
