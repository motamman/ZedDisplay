import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import '../../models/path_metadata.dart';
import '../../models/tool_config.dart';
import '../../models/tool_definition.dart';
import '../../services/signalk_service.dart';
import '../../services/storage_service.dart';
import '../../services/tool_registry.dart';
import '../../services/alarm_audio_player.dart';
import '../../services/alert_coordinator.dart';
import '../../services/dodge_autopilot_service.dart';
import '../../services/find_home_target_service.dart';
import '../../models/alert_event.dart';
import '../../utils/angle_utils.dart';
import '../../widgets/countdown_confirmation_overlay.dart';
import '../../utils/cpa_utils.dart';
import '../../utils/dodge_utils.dart';
import '../tool_info_button.dart';

/// Find Home Tool - ILS-style approach display for navigating back to an
/// anchored vessel at night.
///
/// Data sources:
///   - Dinghy position / COG / SOG: device GPS via geolocator
///   - Home target: manual position (persisted) or SignalK path
///
/// Haptic feedback: 1 buzz = turn port, 2 buzzes = turn starboard.
class FindHomeTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const FindHomeTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<FindHomeTool> createState() => _FindHomeToolState();
}

class _FindHomeToolState extends State<FindHomeTool> {
  static const _ownerId = 'find_home';
  static const _apStatePath = 'steering.autopilot.state';
  static const _defaultTargetPath = 'navigation.position';
  static const _defaultTrackCogPath = 'navigation.courseOverGroundTrue';
  static const _defaultTrackSogPath = 'navigation.speedOverGround';

  /// Full deflection angle in degrees
  static const _maxDeviation = 30.0;

  /// Minimum SOG (m/s) to compute ETA and deviation
  static const _sogThreshold = 0.5;

  /// Deviation threshold for haptic feedback (degrees)
  static const _hapticDeviationThreshold = 5.0;

  /// Feedback interval from config (5-60 seconds, default 10)
  int get _feedbackIntervalSec {
    final val = widget.config.style.customProperties?['feedbackInterval'] as int?;
    return (val ?? 10).clamp(5, 60);
  }

  /// Sound asset path from config (default: whistle)
  String get _soundAsset {
    final key = widget.config.style.customProperties?['alertSound'] as String? ?? 'whistle';
    return AlarmAudioPlayer.alarmSounds[key] ?? 'sounds/alarm_whistle.mp3';
  }

  bool _active = false;
  bool _whistleEnabled = false;
  Timer? _hapticTimer;
  AudioPlayer? _whistlePlayer;

  // Device GPS state
  StreamSubscription<Position>? _positionSub;
  Position? _devicePosition;
  String? _gpsError;

  // Manual home position (persisted)
  double? _manualLat;
  double? _manualLon;
  bool _storageLoaded = false;
  StorageService? _storage;

  // AIS target mode
  FindHomeTargetService? _findHomeTargetService;
  String? _aisVesselId;       // Tracked AIS vessel URN/MMSI
  String? _aisVesselName;     // Display name
  bool _trackMode = false;    // Use SignalK position instead of device GPS
  double? _lastKnownAisLat;   // Stale fallback
  double? _lastKnownAisLon;
  bool _aisTargetStale = false;

  // Dodge mode
  bool _dodgeMode = false;       // dodge vs track view
  bool _dodgeBowPass = false;    // stern (default) vs bow

  // Auto-dodge autopilot integration
  DodgeAutopilotService? _dodgeAutopilotService;
  bool _autoDodgeEnabled = false;
  bool _dodgeCompleting = false;
  AlertCoordinator? _alertCoordinator;

  /// Safe pass distance in SI meters (from config, default 300m).
  /// Stored in SI; displayed via MetadataStore through _formatDistance().
  double get _dodgeSafeDistanceM {
    final val = widget.config.style.customProperties?['dodgeDistance'] as num?;
    return val?.toDouble() ?? 300.0;
  }

  /// SignalK path for the home target (boat position)
  String get _targetPath {
    if (widget.config.dataSources.isNotEmpty &&
        widget.config.dataSources[0].path.isNotEmpty) {
      return widget.config.dataSources[0].path;
    }
    return _defaultTargetPath;
  }

  /// SignalK path for vessel COG in track mode
  String get _trackCogPath {
    return widget.config.style.customProperties?['trackCogPath'] as String?
        ?? _defaultTrackCogPath;
  }

  /// SignalK path for vessel SOG in track mode
  String get _trackSogPath {
    return widget.config.style.customProperties?['trackSogPath'] as String?
        ?? _defaultTrackSogPath;
  }

  @override
  void initState() {
    super.initState();
    // Subscribe to the target position + track-mode nav paths from SignalK
    widget.signalKService.subscribeToPaths(
      [_targetPath, _trackCogPath, _trackSogPath],
      ownerId: _ownerId,
    );
    widget.signalKService.addListener(_onSignalKUpdate);
    _initDeviceGps();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_storageLoaded) {
      _storageLoaded = true;
      _storage = Provider.of<StorageService>(context, listen: false);
      _manualLat = double.tryParse(_storage!.getSetting('find_home_lat') ?? '');
      _manualLon = double.tryParse(_storage!.getSetting('find_home_lon') ?? '');
      final wasActive = _storage!.getSetting('find_home_active') == 'true';
      if (wasActive && (_manualLat != null && _manualLon != null || _getSignalKPosition().$1 != null)) {
        _active = true;
        // Feedback will start once GPS stream delivers the first position
      }

      // Alert coordinator for dodge notifications
      _alertCoordinator = Provider.of<AlertCoordinator>(context, listen: false);

      // Listen for AIS target requests from the AIS chart
      _findHomeTargetService = Provider.of<FindHomeTargetService>(context, listen: false);
      _findHomeTargetService!.addListener(_onFindHomeTargetUpdate);
      // Check if a target was set before we loaded
      _onFindHomeTargetUpdate();
    }
  }

  void _onFindHomeTargetUpdate() {
    final service = _findHomeTargetService;
    if (service == null) return;
    final id = service.aisVesselId;
    final name = service.aisVesselName;
    if (id == null) return;

    // Consume the target
    service.clearTarget();

    setState(() {
      _aisVesselId = id;
      _aisVesselName = name;
      _aisTargetStale = false;
      _lastKnownAisLat = null;
      _lastKnownAisLon = null;
    });

    // Listen to AIS registry for position updates
    widget.signalKService.aisVesselRegistry.addListener(_onAISRegistryUpdate);

    // Auto-activate
    if (!_active) _toggleActive();
  }

  void _onAISRegistryUpdate() {
    if (_aisVesselId != null && mounted) setState(() {});
  }

  void _clearAisMode() {
    _disengageAutoDodge();
    widget.signalKService.aisVesselRegistry.removeListener(_onAISRegistryUpdate);
    setState(() {
      _aisVesselId = null;
      _aisVesselName = null;
      _trackMode = false;
      _aisTargetStale = false;
      _lastKnownAisLat = null;
      _lastKnownAisLon = null;
      _dodgeMode = false;
      _dodgeBowPass = false;
    });
  }

  @override
  void dispose() {
    _dodgeAutopilotService?.deactivate();
    _dodgeAutopilotService?.dispose();
    _hapticTimer?.cancel();
    _positionSub?.cancel();
    _whistlePlayer?.dispose();
    widget.signalKService.removeListener(_onSignalKUpdate);
    widget.signalKService.unsubscribeFromPaths(
      [_targetPath, _trackCogPath, _trackSogPath, _apStatePath],
      ownerId: _ownerId,
    );
    _findHomeTargetService?.removeListener(_onFindHomeTargetUpdate);
    if (_aisVesselId != null) {
      widget.signalKService.aisVesselRegistry.removeListener(_onAISRegistryUpdate);
    }
    super.dispose();
  }

  void _onSignalKUpdate() {
    if (mounted) setState(() {});
  }

  // --------------- Device GPS ---------------

  Future<void> _initDeviceGps() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _gpsError = 'Location services disabled');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _gpsError = 'Location permission denied');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _gpsError = 'Location permanently denied');
        }
        return;
      }

      // Get an immediate position first so the UI doesn't wait for the stream
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted) {
        setState(() => _devicePosition = lastKnown);
      } else if (mounted) {
        try {
          final current = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          );
          if (mounted) setState(() => _devicePosition = current);
        } catch (_) {
          // Stream below will provide position eventually
        }
      }

      final LocationSettings settings;
      if (Platform.isAndroid) {
        settings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          intervalDuration: const Duration(seconds: 1),
          forceLocationManager: false,
        );
      } else {
        settings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        );
      }

      _positionSub =
          Geolocator.getPositionStream(locationSettings: settings).listen(
        (position) {
          if (mounted) {
            setState(() => _devicePosition = position);
            // Auto-start feedback when GPS ready and active was restored
            if (_active && _hapticTimer == null) {
              _startFeedback();
            }
          }
        },
        onError: (error) {
          debugPrint('FindHome GPS stream error: $error');
          if (mounted) setState(() => _gpsError = 'GPS error');
        },
      );
    } catch (e) {
      debugPrint('FindHome GPS init error: $e');
      if (mounted) setState(() => _gpsError = 'GPS init failed');
    }
  }

  // --------------- Data helpers ---------------

  /// Get home target position from SignalK only
  (double?, double?) _getSignalKPosition() {
    final data = widget.signalKService.getValue(_targetPath);
    if (data?.value is Map) {
      final m = data!.value as Map;
      final lat = m['latitude'];
      final lon = m['longitude'];
      if (lat is num && lon is num) {
        return (lat.toDouble(), lon.toDouble());
      }
    }
    return (null, null);
  }

  /// Get home target position: AIS vessel first, then manual, then SignalK
  (double?, double?) _getTargetPosition() {
    // AIS mode: target is the AIS vessel position
    if (_aisVesselId != null) {
      final registry = widget.signalKService.aisVesselRegistry;
      final vessel = registry.vessels[_aisVesselId];
      if (vessel != null && vessel.latitude != null && vessel.longitude != null) {
        _lastKnownAisLat = vessel.latitude;
        _lastKnownAisLon = vessel.longitude;
        // Stale if last seen > 5 minutes ago
        final ageMinutes = DateTime.now().difference(vessel.lastSeen).inMinutes;
        _aisTargetStale = ageMinutes > 5;
        return (vessel.latitude!, vessel.longitude!);
      }
      // Vessel not found or no position — use last known
      if (_lastKnownAisLat != null && _lastKnownAisLon != null) {
        _aisTargetStale = true;
        return (_lastKnownAisLat!, _lastKnownAisLon!);
      }
      // No position at all for this AIS target
      return (null, null);
    }

    if (_manualLat != null && _manualLon != null) {
      return (_manualLat!, _manualLon!);
    }
    return _getSignalKPosition();
  }

  // --------------- Persistence helpers ---------------

  void _saveManualPosition(double lat, double lon) {
    setState(() {
      _manualLat = lat;
      _manualLon = lon;
    });
    _storage?.saveSetting('find_home_lat', lat.toString());
    _storage?.saveSetting('find_home_lon', lon.toString());
  }

  void _clearManualPosition() {
    setState(() {
      _manualLat = null;
      _manualLon = null;
    });
    _storage?.saveSetting('find_home_lat', '');
    _storage?.saveSetting('find_home_lon', '');
  }

  void _persistActiveState() {
    _storage?.saveSetting('find_home_active', _active ? 'true' : 'false');
  }

  // --------------- Unit helpers ---------------

  /// Returns the metadata to use for formatting [meters]:
  /// - distance category (e.g., nm) when value >= 1 in that unit
  /// - length category (e.g., ft, m) for shorter distances
  PathMetadata? _pickDistanceMeta(double meters) {
    final store = widget.signalKService.metadataStore;

    // Direct lookup of canonical category entries from REST preset
    // (getByCategory can return path-specific WS meta with wrong units)
    final distMeta = store.get('__category__.distance');
    if (distMeta != null) {
      final converted = distMeta.convert(meters);
      if (converted != null && converted >= 1.0) {
        return distMeta;
      }
    }

    // < 1 distance unit → use length (e.g., ft, m)
    final lengthMeta = store.get('__category__.length');
    if (lengthMeta != null) return lengthMeta;

    // Fall back to distance even if < 1
    return distMeta;
  }

  // --------------- Computed nav data ---------------

  ({
    double bearing,
    double deviation,
    double distance,
    double cogDeg,
    double sogMs,
    double vesselSogMs,
    bool isWrongWay,
  })? _computeNav() {
    double lat, lon, sogMs, cogDeg;

    if (_trackMode) {
      // Track mode: own position from SignalK (primary vessel)
      final posData = widget.signalKService.getValue(_targetPath);
      if (posData?.value is! Map) return null;
      final m = posData!.value as Map;
      final skLat = m['latitude'];
      final skLon = m['longitude'];
      if (skLat is! num || skLon is! num) return null;
      lat = skLat.toDouble();
      lon = skLon.toDouble();

      final cogData = widget.signalKService.getValue(_trackCogPath);
      final sogData = widget.signalKService.getValue(_trackSogPath);
      sogMs = (sogData?.value as num?)?.toDouble() ?? 0.0;
      // SignalK COG is in radians
      final cogRad = (cogData?.value as num?)?.toDouble();
      cogDeg = cogRad != null ? cogRad * 180.0 / math.pi : 0.0;
    } else {
      // Dinghy mode: own position from device GPS
      final pos = _devicePosition;
      if (pos == null) return null;
      lat = pos.latitude;
      lon = pos.longitude;
      sogMs = pos.speed >= 0 ? pos.speed : 0.0;
      cogDeg = pos.heading >= 0 ? pos.heading : 0.0;
    }

    final (homeLat, homeLon) = _getTargetPosition();
    if (homeLat == null || homeLon == null) return null;

    final bearing = AngleUtils.bearing(lat, lon, homeLat, homeLon);
    final distance = CpaUtils.calculateDistance(lat, lon, homeLat, homeLon);

    // Default COG to bearing when not moving
    if (sogMs < _sogThreshold) cogDeg = bearing;

    // Vessel SOG from SignalK
    final vesselSogData = widget.signalKService.getValue(_trackSogPath);
    final vesselSogMs = (vesselSogData?.value as num?)?.toDouble() ?? 0.0;

    // Only compute deviation when actually moving
    final deviation = sogMs >= _sogThreshold
        ? AngleUtils.difference(cogDeg, bearing)
        : 0.0;

    // Wrong way: heading more than 90° away from target
    final isWrongWay = sogMs >= _sogThreshold && deviation.abs() > 90.0;

    return (
      bearing: bearing,
      deviation: deviation,
      distance: distance,
      cogDeg: AngleUtils.normalize(cogDeg),
      sogMs: sogMs,
      vesselSogMs: vesselSogMs,
      isWrongWay: isWrongWay,
    );
  }

  // --------------- Dodge computation ---------------

  /// Whether the current AIS target has COG/SOG data (is moving).
  bool get _aisTargetIsMoving {
    if (_aisVesselId == null) return false;
    final vessel = widget.signalKService.aisVesselRegistry.vessels[_aisVesselId];
    if (vessel == null) return false;
    return vessel.cogRad != null && (vessel.sogMs ?? 0) > 0.1;
  }

  /// Compute dodge intercept when in dodge mode.
  /// Returns a record with dodge-derived nav data for the runway display,
  /// or null if infeasible.
  ({
    double bearing,       // course to steer (degrees)
    double deviation,     // deviation from recommended course
    double distance,      // distance to apex (meters)
    double cogDeg,        // own COG (degrees)
    double sogMs,         // own SOG (m/s)
    double vesselSogMs,   // own vessel SOG from SignalK
    bool isWrongWay,
    DodgeResult dodge,    // full dodge result
    double targetCogDeg,  // target COG for painter
  })? _computeDodge() {
    if (_aisVesselId == null) return null;

    final registry = widget.signalKService.aisVesselRegistry;
    final vessel = registry.vessels[_aisVesselId];
    if (vessel == null || !vessel.hasPosition) return null;
    if (vessel.cogRad == null || (vessel.sogMs ?? 0) < 0.1) return null;

    // Own vessel position and motion
    double ownLat, ownLon, ownSogMs, ownCogDeg;

    if (_trackMode) {
      final posData = widget.signalKService.getValue(_targetPath);
      if (posData?.value is! Map) return null;
      final m = posData!.value as Map;
      final skLat = m['latitude'];
      final skLon = m['longitude'];
      if (skLat is! num || skLon is! num) return null;
      ownLat = skLat.toDouble();
      ownLon = skLon.toDouble();

      final cogData = widget.signalKService.getValue(_trackCogPath);
      final sogData = widget.signalKService.getValue(_trackSogPath);
      ownSogMs = (sogData?.value as num?)?.toDouble() ?? 0.0;
      final cogRad = (cogData?.value as num?)?.toDouble();
      ownCogDeg = cogRad != null ? cogRad * 180.0 / math.pi : 0.0;
    } else {
      final pos = _devicePosition;
      if (pos == null) return null;
      ownLat = pos.latitude;
      ownLon = pos.longitude;
      ownSogMs = pos.speed >= 0 ? pos.speed : 0.0;
      ownCogDeg = pos.heading >= 0 ? pos.heading : 0.0;
    }

    // Bearing and distance to target
    final bearingToTarget = CpaUtils.calculateBearing(
      ownLat, ownLon, vessel.latitude!, vessel.longitude!,
    );
    final distToTarget = CpaUtils.calculateDistance(
      ownLat, ownLon, vessel.latitude!, vessel.longitude!,
    );

    // Calculate dodge
    final dodgeResult = DodgeUtils.calculateDodge(
      bearingDeg: bearingToTarget,
      distanceM: distToTarget,
      ownSogMs: ownSogMs,
      targetCogRad: vessel.cogRad!,
      targetSogMs: vessel.sogMs!,
      safeDistanceM: _dodgeSafeDistanceM,
      bowPass: _dodgeBowPass,
    );

    if (dodgeResult == null || !dodgeResult.isFeasible) return null;

    final courseToSteerDeg = dodgeResult.courseToSteerRad * 180.0 / math.pi;
    final apexDist = math.sqrt(
      dodgeResult.apexX * dodgeResult.apexX +
      dodgeResult.apexY * dodgeResult.apexY,
    );

    // Deviation from recommended dodge course
    final deviation = ownSogMs >= _sogThreshold
        ? AngleUtils.difference(ownCogDeg, courseToSteerDeg)
        : 0.0;

    final isWrongWay = ownSogMs >= _sogThreshold && deviation.abs() > 90.0;

    // Vessel SOG from SignalK
    final vesselSogData = widget.signalKService.getValue(_trackSogPath);
    final vesselSogMs = (vesselSogData?.value as num?)?.toDouble() ?? 0.0;

    final targetCogDeg = vessel.cogRad! * 180.0 / math.pi;

    // Feed dodge result to autopilot if auto-dodge is active
    if (_autoDodgeEnabled && dodgeResult.isFeasible) {
      _dodgeAutopilotService?.sendDodgeHeading(dodgeResult);
    }

    // Completion detection: check CPA/TCPA for diverging vessels
    if (_autoDodgeEnabled && _dodgeAutopilotService != null) {
      final cpaTcpa = CpaUtils.calculateCpaTcpa(
        bearingDeg: bearingToTarget,
        distanceM: distToTarget,
        ownCogRad: ownSogMs > 0.1 ? ownCogDeg * math.pi / 180.0 : null,
        ownSogMs: ownSogMs,
        targetCogRad: vessel.cogRad,
        targetSogMs: vessel.sogMs,
      );
      final reason = _dodgeAutopilotService!.checkCompletion(
        tcpa: cpaTcpa?.tcpa,
        dodgeFeasible: true,
      );
      if (reason != DodgeCompletionReason.none) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _onDodgeComplete(reason));
      }
    }

    return (
      bearing: AngleUtils.normalize(courseToSteerDeg),
      deviation: deviation,
      distance: apexDist,
      cogDeg: AngleUtils.normalize(ownCogDeg),
      sogMs: ownSogMs,
      vesselSogMs: vesselSogMs,
      isWrongWay: isWrongWay,
      dodge: dodgeResult,
      targetCogDeg: AngleUtils.normalize(targetCogDeg),
    );
  }

  // --------------- Auto-dodge autopilot ---------------

  Future<void> _handleAutoDodgeTap() async {
    if (_autoDodgeEnabled) {
      _disengageAutoDodge();
      return;
    }

    // Step 1: Subscribe to AP state path so cache is populated
    widget.signalKService.subscribeToPaths([_apStatePath], ownerId: _ownerId);
    await Future.delayed(const Duration(milliseconds: 500));

    // Lazy-create the service
    _dodgeAutopilotService ??=
        DodgeAutopilotService(signalKService: widget.signalKService);

    // Step 2: Detect autopilot
    final detected = await _dodgeAutopilotService!.detectAutopilot();
    if (!detected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No autopilot detected')),
        );
      }
      return;
    }

    // Step 3: Ensure AP is in auto mode (engage if needed)
    final error = await _dodgeAutopilotService!.ensureAutopilotInAuto();
    if (error != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
      return;
    }

    // Step 4: Countdown confirmation
    if (!mounted) return;
    final preDodge = _dodgeAutopilotService!.preDodgeApState;
    final confirmTitle = preDodge != null
        ? 'Engage Auto-Dodge?\nAP switched from $preDodge → auto'
        : 'Engage Auto-Dodge?';
    final confirmed = await showCountdownConfirmation(
      context: context,
      title: confirmTitle,
      action: 'Engage',
      countdownSeconds: 5,
    );
    if (!confirmed) {
      // User cancelled — restore AP if we changed it
      if (preDodge != null) {
        await _dodgeAutopilotService!.restorePreDodgeState();
      }
      return;
    }

    // Step 5: Activate
    _dodgeAutopilotService!.activate();
    setState(() => _autoDodgeEnabled = true);

    _alertCoordinator?.submitAlert(AlertEvent(
      subsystem: AlertSubsystem.dodge,
      severity: AlertSeverity.alert,
      title: 'Auto-Dodge',
      body: preDodge != null
          ? 'Auto-dodge engaged — AP switched from $preDodge to auto'
          : 'Auto-dodge engaged — sending headings to autopilot',
      wantsInAppSnackbar: true,
    ));
  }

  void _disengageAutoDodge() {
    if (!_autoDodgeEnabled) return;
    _dodgeAutopilotService?.deactivate();
    widget.signalKService.unsubscribeFromPaths([_apStatePath], ownerId: _ownerId);
    setState(() => _autoDodgeEnabled = false);

    _alertCoordinator?.submitAlert(const AlertEvent(
      subsystem: AlertSubsystem.dodge,
      severity: AlertSeverity.alert,
      title: 'Auto-Dodge',
      body: 'Auto-dodge off. AP holding last heading.',
      wantsInAppSnackbar: true,
    ));
  }

  // --------------- Post-dodge recovery ---------------

  void _onDodgeComplete(DodgeCompletionReason reason) {
    if (_dodgeCompleting || !_autoDodgeEnabled || !mounted) return;
    _dodgeCompleting = true;

    // Stop sending headings immediately
    _dodgeAutopilotService?.deactivate();

    final preDodge = _dodgeAutopilotService?.preDodgeApState;
    final reasonLabel = reason == DodgeCompletionReason.vesselsDiverging
        ? 'Vessels diverging — safe passage'
        : 'Dodge no longer feasible';

    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DodgeRecoveryDialog(
        reasonLabel: reasonLabel,
        preDodgeApState: preDodge,
      ),
    ).then((choice) async {
      choice ??= 'continue'; // default on auto-dismiss

      switch (choice) {
        case 'restore':
          await _dodgeAutopilotService?.restorePreDodgeState();
          break;
        case 'disengage':
          await _dodgeAutopilotService?.disengageAutopilot();
          break;
        case 'continue':
        default:
          break; // AP holds current heading
      }

      widget.signalKService.unsubscribeFromPaths([_apStatePath], ownerId: _ownerId);

      if (mounted) {
        setState(() {
          _autoDodgeEnabled = false;
          _dodgeMode = false; // fall back to track mode
        });
      }

      final actionLabel = choice == 'restore'
          ? 'AP restored to $preDodge'
          : choice == 'disengage'
              ? 'AP disengaged'
              : 'AP holding current course';

      _alertCoordinator?.submitAlert(AlertEvent(
        subsystem: AlertSubsystem.dodge,
        severity: AlertSeverity.alert,
        title: 'Auto-Dodge Complete',
        body: '$reasonLabel. $actionLabel.',
        wantsInAppSnackbar: true,
      ));

      _dodgeCompleting = false;
    });
  }

  // --------------- Feedback engine ---------------

  void _toggleActive() {
    setState(() {
      _active = !_active;
    });
    _persistActiveState();
    if (_active) {
      _startFeedback();
    } else {
      _stopFeedback();
    }
  }

  void _toggleWhistle() {
    setState(() {
      _whistleEnabled = !_whistleEnabled;
    });
  }

  void _startFeedback() {
    _hapticTimer?.cancel();
    _hapticTimer = Timer.periodic(
      Duration(seconds: _feedbackIntervalSec),
      (_) => _fireFeedback(),
    );
  }

  void _stopFeedback() {
    _hapticTimer?.cancel();
    _hapticTimer = null;
  }

  void _fireFeedback() {
    if (!_active || !mounted) return;

    // In dodge mode, use dodge-derived deviation
    final double deviation;
    final bool isWrongWay;
    if (_dodgeMode) {
      final dodge = _computeDodge();
      if (dodge == null) return;
      deviation = dodge.deviation;
      isWrongWay = dodge.isWrongWay;
    } else {
      final nav = _computeNav();
      if (nav == null) return;
      deviation = nav.deviation;
      isWrongWay = nav.isWrongWay;
    }

    // Wrong way: 3 rapid buzzes regardless of direction
    if (isWrongWay) {
      _vibrateTriple();
      if (_whistleEnabled) _whistleTriple();
      return;
    }

    final absDev = deviation.abs();
    if (absDev < _hapticDeviationThreshold) return;

    if (deviation > 0) {
      // On PORT side of course → turn starboard → 2 buzzes / 2 whistles
      _vibrateDouble();
      if (_whistleEnabled) _whistleDouble();
    } else {
      // On STARBOARD side of course → turn port → 1 buzz / 1 whistle
      _vibrateSingle();
      if (_whistleEnabled) _whistleSingle();
    }
  }

  /// Single long vibration: 500ms at max intensity
  void _vibrateSingle() {
    Vibration.vibrate(
      pattern: [0, 500],
      intensities: [0, 255],
    );
  }

  /// Double long vibration: 500ms, pause 300ms, 500ms
  void _vibrateDouble() {
    Vibration.vibrate(
      pattern: [0, 500, 300, 500],
      intensities: [0, 255, 0, 255],
    );
  }

  /// Triple rapid vibration: wrong-way signal
  void _vibrateTriple() {
    Vibration.vibrate(
      pattern: [0, 300, 200, 300, 200, 300],
      intensities: [0, 255, 0, 255, 0, 255],
    );
  }

  /// Play one whistle blast
  Future<void> _whistleSingle() async {
    try {
      _whistlePlayer?.dispose();
      _whistlePlayer = AudioPlayer();
      await _whistlePlayer!.play(AssetSource(_soundAsset));
    } catch (e) {
      debugPrint('FindHome whistle error: $e');
    }
  }

  /// Play two whistle blasts
  Future<void> _whistleDouble() async {
    try {
      _whistlePlayer?.dispose();
      _whistlePlayer = AudioPlayer();
      await _whistlePlayer!.play(AssetSource(_soundAsset));
      // Wait for first blast to finish, then play second
      _whistlePlayer!.onPlayerComplete.first.then((_) async {
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted || !_active) return;
        _whistlePlayer?.dispose();
        _whistlePlayer = AudioPlayer();
        await _whistlePlayer!.play(AssetSource(_soundAsset));
      });
    } catch (e) {
      debugPrint('FindHome whistle error: $e');
    }
  }

  /// Play three rapid whistle blasts: wrong-way signal
  Future<void> _whistleTriple() async {
    try {
      var remaining = 3;
      void playNext() async {
        remaining--;
        if (remaining <= 0 || !mounted || !_active) return;
        await Future.delayed(const Duration(milliseconds: 150));
        if (!mounted || !_active) return;
        _whistlePlayer?.dispose();
        _whistlePlayer = AudioPlayer();
        await _whistlePlayer!.play(AssetSource(_soundAsset));
        _whistlePlayer!.onPlayerComplete.first.then((_) => playNext());
      }

      _whistlePlayer?.dispose();
      _whistlePlayer = AudioPlayer();
      await _whistlePlayer!.play(AssetSource(_soundAsset));
      _whistlePlayer!.onPlayerComplete.first.then((_) => playNext());
    } catch (e) {
      debugPrint('FindHome whistle error: $e');
    }
  }

  // --------------- Map Picker ---------------

  Future<void> _showSetHomeDialog() async {
    debugPrint('FindHome: opening Set Home dialog');
    final result = await showDialog<(double, double)>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _SetHomeDialog(
        initialLat: _manualLat,
        initialLon: _manualLon,
        devicePosition: _devicePosition,
      ),
    );
    debugPrint('FindHome: dialog result = $result');
    if (result != null) {
      if (result.$1 == double.infinity) {
        // Sentinel: reset to SignalK default
        _clearManualPosition();
      } else {
        _saveManualPosition(result.$1, result.$2);
        if (!_active) {
          _toggleActive();
        }
      }
    }
  }

  // --------------- Formatting ---------------

  String _formatDistance(double meters) {
    final meta = _pickDistanceMeta(meters);
    if (meta != null) {
      final converted = meta.convert(meters);
      if (converted != null) {
        return '${converted.toStringAsFixed(converted < 10 ? 2 : 1)} ${meta.symbol ?? 'm'}';
      }
    }
    // Fallback: raw SI (meters)
    return '${meters.toStringAsFixed(meters < 10 ? 1 : 0)} m';
  }

  String _formatAngle(double degrees) {
    return '${degrees.toStringAsFixed(0)}°';
  }

  /// Format a speed value using metadata.
  /// [skPath] — if provided, check path-specific WS meta first, then category.
  ///            If null (device GPS), use category only.
  String _formatSpeed(double speedMs, {String? skPath}) {
    final store = widget.signalKService.metadataStore;
    final meta = (skPath != null ? store.get(skPath) : null)
        ?? store.get('__category__.speed');
    if (meta != null) {
      return meta.format(speedMs, decimals: 1);
    }
    // Fallback: raw SI (m/s)
    return '${speedMs.toStringAsFixed(1)} m/s';
  }

  String _formatEta(double distanceM, double sogMs) {
    if (sogMs < _sogThreshold) return '--:--';
    final seconds = distanceM / sogMs;
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    if (mins >= 60) {
      final hrs = mins ~/ 60;
      final remMins = mins % 60;
      return '$hrs:${remMins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  /// Format lat/lon in degrees decimal minutes
  String _formatDDM(double lat, double lon) {
    String fmt(double v, String pos, String neg) {
      final h = v >= 0 ? pos : neg;
      final a = v.abs();
      final d = a.floor();
      final m = (a - d) * 60;
      return '$d\u00B0${m.toStringAsFixed(3)}\'$h';
    }
    return '${fmt(lat, 'N', 'S')} ${fmt(lon, 'E', 'W')}';
  }

  // --------------- Build ---------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Check for target position (manual or SignalK)
    final (homeLat, _) = _getTargetPosition();
    if (homeLat == null) {
      return _buildNoTarget(isDark);
    }

    // Check for device GPS errors (skip in track mode — using SignalK position)
    if (!_trackMode && _gpsError != null) {
      return _buildGpsError(isDark);
    }

    // Check for position fix (device GPS or SignalK in track mode)
    final nav = _computeNav();
    if (nav == null) {
      return _trackMode
          ? _buildWaitingForSignalK(isDark)
          : _buildAcquiringGps(isDark);
    }

    // Dodge mode: compute dodge and use dodge-derived values for display
    final dodgeNav = _dodgeMode ? _computeDodge() : null;
    final inDodge = dodgeNav != null;

    // Dodge infeasible while auto-dodge active → trigger completion
    if (_autoDodgeEnabled && dodgeNav == null && _dodgeMode) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _onDodgeComplete(DodgeCompletionReason.dodgeInfeasible),
      );
    }

    // Extract display values — dodge overrides nav when active
    final displayBearing = inDodge ? dodgeNav.bearing : nav.bearing;
    final displayDeviation = inDodge ? dodgeNav.deviation : nav.deviation;
    final displayDistance = inDodge ? dodgeNav.distance : nav.distance;
    final displayCogDeg = inDodge ? dodgeNav.cogDeg : nav.cogDeg;
    final displaySogMs = inDodge ? dodgeNav.sogMs : nav.sogMs;
    final displayVesselSogMs = inDodge ? dodgeNav.vesselSogMs : nav.vesselSogMs;
    final displayIsWrongWay = inDodge ? dodgeNav.isWrongWay : nav.isWrongWay;

    final distMeta = _pickDistanceMeta(displayDistance);
    // Derive metersPerUnit from metadata for the runway painter
    double metersPerUnit = 1.0; // fallback: SI meters
    String unitSymbol = 'm';
    if (distMeta != null) {
      final oneConverted = distMeta.convert(1.0);
      if (oneConverted != null && oneConverted > 0) {
        metersPerUnit = 1.0 / oneConverted;
      }
      unitSymbol = distMeta.symbol ?? 'm';
    }

    return Stack(
      children: [
        Column(
          children: [
            _buildHeader(
              bearing: displayBearing,
              deviation: displayDeviation,
              distance: displayDistance,
              cogDeg: displayCogDeg,
              sogMs: displaySogMs,
              vesselSogMs: displayVesselSogMs,
              isWrongWay: displayIsWrongWay,
              isDark: isDark,
              inDodge: inDodge,
            ),
            Expanded(
              child: ClipRect(
                child: CustomPaint(
                  painter: _RunwayPainter(
                    deviation: displayDeviation,
                    maxDeviation: _maxDeviation,
                    distanceMeters: displayDistance,
                    metersPerUnit: metersPerUnit,
                    unitSymbol: unitSymbol,
                    isDark: isDark,
                    active: _active,
                    hapticThreshold: _hapticDeviationThreshold,
                    isWrongWay: displayIsWrongWay,
                    isAisMode: _aisVesselId != null,
                    isStaleTarget: _aisTargetStale,
                    isTrackMode: _trackMode,
                    isDodgeMode: inDodge,
                    targetCogDeg: dodgeNav?.targetCogDeg,
                    isBowPass: _dodgeBowPass,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
            _buildFooter(
              bearing: displayBearing,
              deviation: displayDeviation,
              distance: displayDistance,
              cogDeg: displayCogDeg,
              sogMs: displaySogMs,
              vesselSogMs: displayVesselSogMs,
              isWrongWay: displayIsWrongWay,
              isDark: isDark,
              inDodge: inDodge,
            ),
          ],
        ),
        _buildInfoButton(),
      ],
    );
  }

  Widget _buildInfoButton() {
    return Positioned(
      top: 8,
      right: 8,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: ToolInfoButton(
          toolId: 'find_home',
          signalKService: widget.signalKService,
          iconSize: 20,
          iconColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildNoTarget(bool isDark) {
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.anchor, size: 32, color: Colors.grey),
              const SizedBox(height: 8),
              const Text(
                'No home position',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _showSetHomeDialog,
                icon: const Icon(Icons.home, size: 18),
                label: const Text('Set Home'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        _buildInfoButton(),
      ],
    );
  }

  Widget _buildGpsError(bool isDark) {
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_disabled,
                  size: 32, color: Colors.orange),
              const SizedBox(height: 8),
              Text(
                _gpsError ?? 'GPS unavailable',
                style: const TextStyle(color: Colors.orange),
              ),
              const SizedBox(height: 4),
              const Text(
                'Enable location services',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
        _buildInfoButton(),
      ],
    );
  }

  Widget _buildAcquiringGps(bool isDark) {
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_searching, size: 32, color: Colors.grey),
              const SizedBox(height: 8),
              const Text(
                'Acquiring device GPS...',
                style: TextStyle(color: Colors.grey),
              ),
              if (_aisVesselName != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Target: $_aisVesselName',
                  style: const TextStyle(color: Colors.cyan, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        _buildInfoButton(),
      ],
    );
  }

  Widget _buildWaitingForSignalK(bool isDark) {
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.sailing, size: 32, color: Colors.grey),
              const SizedBox(height: 8),
              const Text(
                'Waiting for vessel position...',
                style: TextStyle(color: Colors.grey),
              ),
              if (_aisVesselName != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Target: $_aisVesselName',
                  style: const TextStyle(color: Colors.cyan, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        _buildInfoButton(),
      ],
    );
  }

  Widget _buildHeader({
    required double bearing,
    required double deviation,
    required double distance,
    required double cogDeg,
    required double sogMs,
    required double vesselSogMs,
    required bool isWrongWay,
    required bool isDark,
    required bool inDodge,
  }) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final labelColor = isDark ? Colors.white60 : Colors.black54;
    final (homeLat, homeLon) = _getTargetPosition();
    final hasManual = _manualLat != null && _manualLon != null;
    final inAisMode = _aisVesselId != null;
    final headerTitle = inDodge ? 'DODGE' : 'FIND HOME';
    final headerColor = inDodge
        ? (_dodgeBowPass ? Colors.orange : Colors.cyan)
        : labelColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 40, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  children: [
                    Text(
                      headerTitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: inDodge ? headerColor : labelColor,
                        letterSpacing: 1.2,
                      ),
                    ),
                    if (inAisMode) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 12, color: headerColor),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _aisVesselName ?? 'AIS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: headerColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: _clearAisMode,
                        child: Icon(Icons.close, size: 14, color: headerColor),
                      ),
                    ],
                    if (!inAisMode) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _showSetHomeDialog,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(Icons.edit_location_alt, size: 18, color: labelColor),
                        ),
                      ),
                      if (hasManual) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                          onLongPress: _clearManualPosition,
                          child: Icon(Icons.close, size: 14, color: Colors.grey.shade600),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              Text(
                inDodge
                    ? 'APEX ${_formatDistance(distance)}'
                    : _formatDistance(distance),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: inDodge ? headerColor : textColor,
                ),
              ),
            ],
          ),
          if (inDodge)
            Text(
              '${_dodgeBowPass ? 'BOW' : 'STERN'} PASS @ ${_formatDistance(_dodgeSafeDistanceM)}  STR ${_formatAngle(bearing)}',
              style: TextStyle(fontSize: 10, color: headerColor, fontFamily: 'monospace'),
            )
          else if (homeLat != null && homeLon != null)
            Text(
              _formatDDM(homeLat, homeLon),
              style: TextStyle(fontSize: 10, color: labelColor, fontFamily: 'monospace'),
            ),
        ],
      ),
    );
  }

  Widget _buildFooter({
    required double bearing,
    required double deviation,
    required double distance,
    required double cogDeg,
    required double sogMs,
    required double vesselSogMs,
    required bool isWrongWay,
    required bool isDark,
    required bool inDodge,
  }) {
    final labelColor = isDark ? Colors.white60 : Colors.black54;
    final absDev = deviation.abs();
    final devSide = deviation > 0 ? 'P' : 'S';
    final inAisMode = _aisVesselId != null;

    Color devColor;
    if (isWrongWay) {
      devColor = Colors.red;
    } else if (absDev < 5) {
      devColor = Colors.green;
    } else if (absDev < 15) {
      devColor = Colors.amber;
    } else {
      devColor = Colors.red;
    }

    final devLabel = isWrongWay
        ? 'WRONG WAY'
        : 'DEV ${absDev.toStringAsFixed(0)}° $devSide';
    final etaLabel = isWrongWay
        ? 'ETA --:--'
        : 'ETA ${_formatEta(distance, sogMs)}';

    // Labels change based on AIS mode, track mode, and dodge mode
    final String bearingLabel;
    if (inDodge) {
      bearingLabel = 'STR ${_formatAngle(bearing)}';
    } else if (inAisMode) {
      bearingLabel = 'TO ${_aisVesselName ?? 'AIS'}';
    } else {
      bearingLabel = 'TO BOAT';
    }
    final youLabel = _trackMode ? 'VESSEL' : 'YOU';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'COG ${_formatAngle(cogDeg)}',
                style: TextStyle(
                    fontSize: 12, fontFamily: 'monospace', color: labelColor),
              ),
              Flexible(
                child: Text(
                  inDodge ? bearingLabel : '$bearingLabel ${_formatAngle(bearing)}',
                  style: TextStyle(
                      fontSize: 12, fontFamily: 'monospace', color: inDodge ? (_dodgeBowPass ? Colors.orange : Colors.cyan) : labelColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                devLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  color: devColor,
                ),
              ),
              Text(
                '$youLabel ${_formatSpeed(sogMs, skPath: _trackMode ? 'navigation.speedOverGround' : null)}',
                style: TextStyle(
                    fontSize: 12, fontFamily: 'monospace', color: labelColor),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                etaLabel,
                style: TextStyle(
                    fontSize: 12, fontFamily: 'monospace', color: labelColor),
              ),
              if (inDodge)
                Text(
                  '${_dodgeBowPass ? 'BOW' : 'STERN'} PASS',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: _dodgeBowPass ? Colors.orange : Colors.cyan,
                  ),
                )
              else
                Text(
                  'BOAT ${_formatSpeed(vesselSogMs, skPath: _trackSogPath)}',
                  style: TextStyle(
                      fontSize: 12, fontFamily: 'monospace', color: labelColor),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
                  // Return-to-home button + Track/Dodge toggles (only in AIS mode)
                  if (inAisMode) ...[
                    // HOME button
                    GestureDetector(
                      onTap: _clearAisMode,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          widget.signalKService.getValue('name')?.value as String? ?? 'HOME',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // TRACK button (hidden when dodge is active)
                    if (!_dodgeMode)
                      GestureDetector(
                        onTap: () => setState(() => _trackMode = !_trackMode),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _trackMode
                                ? Colors.cyan.withValues(alpha: 0.3)
                                : Colors.grey.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _trackMode ? Colors.cyan : Colors.grey,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            'TRACK',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _trackMode ? Colors.cyan : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    if (!_dodgeMode) const SizedBox(width: 8),
                    // DODGE button (only when target is moving)
                    if (_aisTargetIsMoving) ...[
                      GestureDetector(
                        onTap: () => setState(() {
                          _dodgeMode = !_dodgeMode;
                          if (_dodgeMode) {
                            _trackMode = true; // dodge uses SignalK position
                          } else {
                            _disengageAutoDodge(); // turning off dodge disengages auto-dodge
                          }
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _dodgeMode
                                ? Colors.cyan.withValues(alpha: 0.3)
                                : Colors.grey.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _dodgeMode ? Colors.cyan : Colors.grey,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            'DODGE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _dodgeMode ? Colors.cyan : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // STERN/BOW toggle (only in dodge mode)
                    if (_dodgeMode) ...[
                      GestureDetector(
                        onTap: () => setState(() => _dodgeBowPass = !_dodgeBowPass),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _dodgeBowPass
                                ? Colors.orange.withValues(alpha: 0.3)
                                : Colors.cyan.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _dodgeBowPass ? Colors.orange : Colors.cyan,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            _dodgeBowPass ? 'BOW' : 'STERN',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _dodgeBowPass ? Colors.orange : Colors.cyan,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // AUTO button (auto-dodge to autopilot)
                      GestureDetector(
                        onTap: _handleAutoDodgeTap,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _autoDodgeEnabled
                                ? (_dodgeAutopilotService?.lastError != null
                                    ? Colors.red.withValues(alpha: 0.3)
                                    : Colors.green.withValues(alpha: 0.3))
                                : Colors.grey.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _autoDodgeEnabled
                                  ? (_dodgeAutopilotService?.lastError != null
                                      ? Colors.red
                                      : Colors.green)
                                  : Colors.grey,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            'AUTO',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _autoDodgeEnabled
                                  ? (_dodgeAutopilotService?.lastError != null
                                      ? Colors.red
                                      : Colors.green)
                                  : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      // Status label showing last sent heading
                      if (_autoDodgeEnabled) ...[
                        const SizedBox(width: 4),
                        Builder(builder: (_) {
                          final status = _dodgeAutopilotService?.status;
                          final hdg = status?.lastSentHeadingDeg;
                          return Text(
                            hdg != null
                                ? 'AP\u2192${hdg.toStringAsFixed(0)}\u00B0'
                                : 'AP\u2192...',
                            style: const TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: Colors.green,
                            ),
                          );
                        }),
                      ],
                      const SizedBox(width: 8),
                    ],
                  ],
                  // Whistle toggle
                  GestureDetector(
                    onTap: _toggleWhistle,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _whistleEnabled
                            ? Colors.orange.withValues(alpha: 0.3)
                            : Colors.grey.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              _whistleEnabled ? Colors.orange : Colors.grey,
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        _whistleEnabled
                            ? Icons.volume_up
                            : Icons.volume_off,
                        size: 14,
                        color:
                            _whistleEnabled ? Colors.orange : Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Vibration/active toggle
                  GestureDetector(
                    onTap: _toggleActive,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _active
                            ? Colors.green.withValues(alpha: 0.3)
                            : Colors.grey.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _active ? Colors.green : Colors.grey,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _active ? 'ACTIVE' : 'OFF',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _active ? Colors.green : Colors.grey,
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

// --------------- Dodge Recovery Dialog ---------------

class _DodgeRecoveryDialog extends StatefulWidget {
  final String reasonLabel;
  final String? preDodgeApState;

  const _DodgeRecoveryDialog({
    required this.reasonLabel,
    required this.preDodgeApState,
  });

  @override
  State<_DodgeRecoveryDialog> createState() => _DodgeRecoveryDialogState();
}

class _DodgeRecoveryDialogState extends State<_DodgeRecoveryDialog> {
  static const _timeoutSeconds = 30;
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = _timeoutSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) {
        Navigator.of(context).pop('continue');
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasPrevState = widget.preDodgeApState != null;

    return AlertDialog(
      backgroundColor: Colors.grey.shade900,
      title: const Text(
        'Dodge Complete',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.reasonLabel,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Text(
            'Auto-selecting "Continue" in $_remaining s',
            style: const TextStyle(color: Colors.amber, fontSize: 12),
          ),
        ],
      ),
      actions: [
        if (hasPrevState)
          TextButton(
            onPressed: () => Navigator.of(context).pop('restore'),
            child: Text(
              'Resume ${widget.preDodgeApState}',
              style: const TextStyle(color: Colors.cyan),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop('continue'),
          child: const Text(
            'Continue current course',
            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop('disengage'),
          child: const Text(
            'Disengage autopilot',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }
}

// --------------- Set Home Dialog ---------------

class _SetHomeDialog extends StatefulWidget {
  final double? initialLat;
  final double? initialLon;
  final Position? devicePosition;

  const _SetHomeDialog({
    this.initialLat,
    this.initialLon,
    this.devicePosition,
  });

  @override
  State<_SetHomeDialog> createState() => _SetHomeDialogState();
}

class _SetHomeDialogState extends State<_SetHomeDialog> {
  late TextEditingController _latController;
  late TextEditingController _lonController;
  final MapController _mapController = MapController();
  double? _selectedLat;
  double? _selectedLon;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _selectedLat = widget.initialLat;
    _selectedLon = widget.initialLon;

    _latController = TextEditingController(
      text: _selectedLat != null ? _formatCoordForEdit(_selectedLat!, true) : '',
    );
    _lonController = TextEditingController(
      text: _selectedLon != null ? _formatCoordForEdit(_selectedLon!, false) : '',
    );
  }

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  /// Format a coordinate for the text field: "47 36.352 N"
  String _formatCoordForEdit(double value, bool isLat) {
    final h = isLat ? (value >= 0 ? 'N' : 'S') : (value >= 0 ? 'E' : 'W');
    final a = value.abs();
    final d = a.floor();
    final m = (a - d) * 60;
    return '$d ${m.toStringAsFixed(3)} $h';
  }

  /// Parse a coordinate string into decimal degrees.
  /// Accepts: "47.605867", "-47.605867", "47 36.352", "47 36.352 N"
  double? _parseCoordinate(String input) {
    final cleaned = input.trim().replaceAll(RegExp('[°\'"\\u00B0]'), ' ').trim();
    if (cleaned.isEmpty) return null;

    final tokens = cleaned.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return null;

    // Determine sign from hemisphere letter
    double sign = 1.0;
    final lastToken = tokens.last.toUpperCase();
    if (lastToken == 'S' || lastToken == 'W') {
      sign = -1.0;
      tokens.removeLast();
    } else if (lastToken == 'N' || lastToken == 'E') {
      tokens.removeLast();
    }

    if (tokens.isEmpty) return null;

    if (tokens.length == 1) {
      // Decimal degrees: sign from hemisphere if present, else from number
      final dd = double.tryParse(tokens[0]);
      if (dd == null) return null;
      // If hemisphere was given, use its sign; otherwise keep number's sign
      if (sign < 0) return -dd.abs();
      return dd;
    }

    if (tokens.length == 2) {
      // Degrees + decimal minutes
      final deg = double.tryParse(tokens[0]);
      final min = double.tryParse(tokens[1]);
      if (deg == null || min == null) return null;
      return sign * (deg.abs() + min / 60);
    }

    return null;
  }

  void _onLatLonTextChanged() {
    final lat = _parseCoordinate(_latController.text);
    final lon = _parseCoordinate(_lonController.text);
    if (lat != null && lon != null && lat.abs() <= 90 && lon.abs() <= 180) {
      setState(() {
        _selectedLat = lat;
        _selectedLon = lon;
      });
      if (_mapReady) {
        _mapController.move(LatLng(lat, lon), _mapController.camera.zoom);
      }
    }
  }

  void _onMapTap(TapPosition tapPos, LatLng point) {
    debugPrint('FindHome map tap: ${point.latitude}, ${point.longitude}');
    setState(() {
      _selectedLat = point.latitude;
      _selectedLon = point.longitude;
      _latController.text = _formatCoordForEdit(point.latitude, true);
      _lonController.text = _formatCoordForEdit(point.longitude, false);
    });
  }

  void _useCurrentGps() {
    final pos = widget.devicePosition;
    if (pos == null) return;
    setState(() {
      _selectedLat = pos.latitude;
      _selectedLon = pos.longitude;
      _latController.text = _formatCoordForEdit(pos.latitude, true);
      _lonController.text = _formatCoordForEdit(pos.longitude, false);
    });
    if (_mapReady) {
      _mapController.move(
        LatLng(pos.latitude, pos.longitude),
        _mapController.camera.zoom,
      );
    }
  }

  LatLng get _mapCenter {
    if (_selectedLat != null && _selectedLon != null) {
      return LatLng(_selectedLat!, _selectedLon!);
    }
    if (widget.devicePosition != null) {
      return LatLng(widget.devicePosition!.latitude, widget.devicePosition!.longitude);
    }
    return const LatLng(0, 0);
  }

  /// Format preview as DDM
  String get _preview {
    if (_selectedLat == null || _selectedLon == null) return '';
    String fmt(double v, String pos, String neg) {
      final h = v >= 0 ? pos : neg;
      final a = v.abs();
      final d = a.floor();
      final m = (a - d) * 60;
      return '$d\u00B0${m.toStringAsFixed(3)}\'$h';
    }
    return '${fmt(_selectedLat!, 'N', 'S')} ${fmt(_selectedLon!, 'E', 'W')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasSelection = _selectedLat != null && _selectedLon != null;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Set Home Position',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Lat/Lon text fields
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _latController,
                      decoration: const InputDecoration(
                        labelText: 'Lat',
                        hintText: '47 36.352 N',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                      onChanged: (_) => _onLatLonTextChanged(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _lonController,
                      decoration: const InputDecoration(
                        labelText: 'Lon',
                        hintText: '122 19.876 W',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                      onChanged: (_) => _onLatLonTextChanged(),
                    ),
                  ),
                ],
              ),

              // Preview
              if (hasSelection) ...[
                const SizedBox(height: 4),
                Text(
                  _preview,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.black54,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 12),

              // Map
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _mapCenter,
                      initialZoom: 12,
                      minZoom: 3,
                      maxZoom: 18,
                      onTap: _onMapTap,
                      onMapReady: () => _mapReady = true,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.zennora.signalk',
                      ),
                      TileLayer(
                        urlTemplate: 'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.zennora.signalk',
                      ),
                      MarkerLayer(
                          markers: [
                            if (hasSelection)
                              Marker(
                                point: LatLng(_selectedLat!, _selectedLon!),
                                width: 40,
                                height: 40,
                                child: const Icon(
                                  Icons.location_on,
                                  color: Colors.red,
                                  size: 40,
                                ),
                              ),
                            if (widget.devicePosition != null)
                              Marker(
                                point: LatLng(
                                  widget.devicePosition!.latitude,
                                  widget.devicePosition!.longitude,
                                ),
                                width: 24,
                                height: 24,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Buttons
              Row(
                children: [
                  TextButton.icon(
                    onPressed: widget.devicePosition != null ? _useCurrentGps : null,
                    icon: const Icon(Icons.my_location, size: 18),
                    label: const Text('GPS'),
                  ),
                  const SizedBox(width: 4),
                  if (widget.initialLat != null)
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop((double.infinity, double.infinity)),
                      icon: const Icon(Icons.restore, size: 18),
                      label: const Text('Reset'),
                      style: TextButton.styleFrom(foregroundColor: Colors.orange),
                    ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: hasSelection
                        ? () => Navigator.of(context).pop((_selectedLat!, _selectedLon!))
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Set Home'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------- Runway CustomPainter ---------------

class _RunwayPainter extends CustomPainter {
  final double deviation;
  final double maxDeviation;
  final double distanceMeters;
  final double metersPerUnit;
  final String unitSymbol;
  final bool isDark;
  final bool active;
  final double hapticThreshold;
  final bool isWrongWay;
  final bool isAisMode;
  final bool isStaleTarget;
  final bool isTrackMode;
  final bool isDodgeMode;
  final double? targetCogDeg;
  final bool isBowPass;

  _RunwayPainter({
    required this.deviation,
    required this.maxDeviation,
    required this.distanceMeters,
    required this.metersPerUnit,
    required this.unitSymbol,
    required this.isDark,
    required this.active,
    required this.hapticThreshold,
    required this.isWrongWay,
    this.isAisMode = false,
    this.isStaleTarget = false,
    this.isTrackMode = false,
    this.isDodgeMode = false,
    this.targetCogDeg,
    this.isBowPass = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final centerX = w / 2;

    final bgColor =
        isDark ? const Color(0xFF1A1A2E) : const Color(0xFFE8EAF6);
    final centerLineColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : Colors.black.withValues(alpha: 0.4);

    final absDev = deviation.abs();
    Color devColor;
    if (absDev < 5) {
      devColor = Colors.green;
    } else if (absDev < 15) {
      devColor = Colors.amber;
    } else {
      devColor = Colors.red;
    }

    // Background — red tint when wrong way, subtle dodge tint in dodge mode
    Color effectiveBg;
    if (isWrongWay) {
      effectiveBg = Color.lerp(bgColor, Colors.red.shade900, 0.4)!;
    } else if (isDodgeMode) {
      final tintColor = isBowPass ? Colors.orange.shade900 : Colors.cyan.shade900;
      effectiveBg = Color.lerp(bgColor, tintColor, 0.15)!;
    } else {
      effectiveBg = bgColor;
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = effectiveBg,
    );

    // Dim runway elements when wrong way
    final dimFactor = isWrongWay ? 0.5 : 1.0;

    // Runway geometry — apex (anchor) at top, base (vessel) at bottom
    final apexY = 20.0;
    final baseY = h - 20.0;
    final runwayHeight = baseY - apexY;
    final baseHalfWidth = (w / 2) - 20;

    // --- Localizer beam triangle (full ±30° cone) ---
    final beamPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.04 * dimFactor)
          : Colors.black.withValues(alpha: 0.03 * dimFactor);
    final beamPath = Path()
      ..moveTo(centerX, apexY)
      ..lineTo(centerX - baseHalfWidth, baseY)
      ..lineTo(centerX + baseHalfWidth, baseY)
      ..close();
    canvas.drawPath(beamPath, beamPaint);

    // Beam edge lines
    final beamEdgePaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.15 * dimFactor)
          : Colors.black.withValues(alpha: 0.1 * dimFactor)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(centerX, apexY),
        Offset(centerX - baseHalfWidth, baseY), beamEdgePaint);
    canvas.drawLine(Offset(centerX, apexY),
        Offset(centerX + baseHalfWidth, baseY), beamEdgePaint);

    // --- Haptic corridor triangle (±5° on-course zone) ---
    final hapticFrac = hapticThreshold / maxDeviation;
    final hapticBaseHalf = baseHalfWidth * hapticFrac;
    final hapticFillPaint = Paint()
      ..color = Colors.green.withValues(alpha: (isDark ? 0.10 : 0.07) * dimFactor);
    final hapticPath = Path()
      ..moveTo(centerX, apexY)
      ..lineTo(centerX - hapticBaseHalf, baseY)
      ..lineTo(centerX + hapticBaseHalf, baseY)
      ..close();
    canvas.drawPath(hapticPath, hapticFillPaint);

    // Haptic corridor edge lines
    final hapticEdgePaint = Paint()
      ..color = Colors.green.withValues(alpha: 0.35 * dimFactor)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(centerX, apexY),
        Offset(centerX - hapticBaseHalf, baseY), hapticEdgePaint);
    canvas.drawLine(Offset(centerX, apexY),
        Offset(centerX + hapticBaseHalf, baseY), hapticEdgePaint);

    // --- Center line (dashed) ---
    final centerPaint = Paint()
      ..color = centerLineColor
      ..strokeWidth = 1.5;
    const dashLen = 8.0;
    const gapLen = 6.0;
    var y = apexY;
    while (y < baseY) {
      canvas.drawLine(
        Offset(centerX, y),
        Offset(centerX, math.min(y + dashLen, baseY)),
        centerPaint,
      );
      y += dashLen + gapLen;
    }

    // --- Distance countdown markers along centerline ---
    final distInUnits = distanceMeters / metersPerUnit;
    _drawDistanceMarkers(
        canvas, centerX, apexY, baseY, runwayHeight, distInUnits);

    // --- Target icon at apex ---
    if (isDodgeMode && targetCogDeg != null) {
      // In dodge mode: draw target vessel chevron rotated to its COG
      _drawTargetVesselAtApex(canvas, Offset(centerX, apexY + 10), targetCogDeg!);
    } else if (isTrackMode) {
      _drawBoatIcon(canvas, Offset(centerX, apexY + 10));
    } else {
      _drawAnchorIcon(canvas, Offset(centerX, apexY + 10));
    }

    // --- Label over apex icon ---
    if (isDodgeMode) {
      final dodgeColor = isBowPass ? Colors.orange : Colors.cyan;
      final label = isBowPass ? 'BOW' : 'STERN';
      final labelStyle = TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w900,
        color: dodgeColor,
        letterSpacing: 0.5,
      );
      final labelTp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      labelTp.paint(canvas, Offset(centerX - labelTp.width / 2, apexY - 4));
    } else if (isAisMode) {
      final aisColor = isStaleTarget ? Colors.orange : Colors.cyan;
      final aisStyle = TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w900,
        color: aisColor,
        letterSpacing: 0.5,
      );
      final aisTp = TextPainter(
        text: TextSpan(text: isStaleTarget ? 'AIS ?' : 'AIS', style: aisStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      aisTp.paint(canvas, Offset(centerX - aisTp.width / 2, apexY - 4));
    }

    // --- Vessel triangle ---
    // deviation > 0 = on PORT side (bearing is CW from COG) → triangle LEFT
    // deviation < 0 = on STARBOARD side → triangle RIGHT
    final clampedDev = deviation.clamp(-maxDeviation, maxDeviation);
    final vesselX = centerX - (clampedDev / maxDeviation) * baseHalfWidth;
    final vesselY = baseY - 16;

    // --- COG line (dotted, from vessel upward — where you're actually heading) ---
    // Only draw when vessel is within the runway (not clamped at edge)
    final isClamped = deviation.abs() >= maxDeviation;
    if (!isClamped) {
      final cogPaint = Paint()
        ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.4)
        ..strokeWidth = 1.0;
      _drawDashedLine(canvas, Offset(vesselX, vesselY - 12),
          Offset(vesselX, apexY + 20), cogPaint, 5, 4);
    }

    // --- Bearing line (dotted, from vessel to apex — where you need to go) ---
    final bearingLineColor = isDodgeMode
        ? (isBowPass ? Colors.orange : Colors.cyan).withValues(alpha: active ? 0.7 : 0.4)
        : devColor.withValues(alpha: active ? 0.7 : 0.4);
    final bearingPaint = Paint()
      ..color = bearingLineColor
      ..strokeWidth = 1.5;
    _drawDashedLine(canvas, Offset(vesselX, vesselY - 12),
        Offset(centerX, apexY + 18), bearingPaint, 6, 4);

    // --- Target COG track line through apex (dodge mode only) ---
    if (isDodgeMode && targetCogDeg != null) {
      final cogTrackColor = (isBowPass ? Colors.orange : Colors.cyan)
          .withValues(alpha: 0.3);
      final cogTrackPaint = Paint()
        ..color = cogTrackColor
        ..strokeWidth = 1.0;
      // Draw a line extending upward from apex in target's COG direction
      // Since runway is heading-up, we just draw a vertical-ish line from apex
      _drawDashedLine(
        canvas,
        Offset(centerX, apexY + 20),
        Offset(centerX, apexY - 10),
        cogTrackPaint,
        4,
        3,
      );
    }

    // Vessel chevron — open V-shape rotated by COG deviation
    canvas.save();
    canvas.translate(vesselX, vesselY);
    canvas.rotate(-deviation * math.pi / 180);
    final chevronPaint = Paint()
      ..color = devColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final chevronPath = Path()
      ..moveTo(-8, 6)
      ..lineTo(0, -8)
      ..lineTo(8, 6);
    canvas.drawPath(chevronPath, chevronPaint);
    canvas.restore();

    // --- P / S labels ---
    final labelStyle = TextStyle(
      fontSize: 11,
      color: isDark ? Colors.white38 : Colors.black38,
      fontWeight: FontWeight.bold,
    );
    _drawText(canvas, 'P', Offset(8, baseY - 20), labelStyle);
    _drawText(canvas, 'S', Offset(w - 16, baseY - 20), labelStyle);

    // --- Wrong-way overlay ---
    if (isWrongWay) {
      _drawWrongWayOverlay(canvas, size, deviation);
    }
  }

  void _drawWrongWayOverlay(Canvas canvas, Size size, double deviation) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // "TURN AROUND" title
    final titleStyle = TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w900,
      color: Colors.red.shade300,
      letterSpacing: 2.0,
    );
    final titleTp = TextPainter(
      text: TextSpan(text: 'TURN AROUND', style: titleStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    titleTp.paint(
      canvas,
      Offset(centerX - titleTp.width / 2, centerY - titleTp.height - 4),
    );

    // Direction hint: deviation > 0 means boat is to port → turn starboard
    final turnDir = deviation > 0 ? 'TURN STARBOARD' : 'TURN PORT';
    final arrow = deviation > 0 ? '\u21BB' : '\u21BA'; // ↻ or ↺
    final dirStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: Colors.red.shade200,
      letterSpacing: 1.0,
    );
    final dirTp = TextPainter(
      text: TextSpan(text: '$arrow $turnDir', style: dirStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    dirTp.paint(
      canvas,
      Offset(centerX - dirTp.width / 2, centerY + 4),
    );
  }

  /// Draw 3-4 evenly spaced distance markers ON the centerline.
  /// Labels show distance from the destination (0 at apex/anchor).
  /// Positioned at nice round fractions of total distance.
  void _drawDistanceMarkers(
    Canvas canvas,
    double centerX,
    double apexY,
    double baseY,
    double runwayHeight,
    double distInUnits,
  ) {
    if (distInUnits < 0.001) return;

    // Pick 3 evenly-spaced marker positions at 25%, 50%, 75% of distance
    final fractions = [0.25, 0.50, 0.75];

    final markerColor = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : Colors.black.withValues(alpha: 0.4);
    final markerStyle = TextStyle(
      fontSize: 10,
      color: markerColor,
      fontFamily: 'monospace',
      fontWeight: FontWeight.w500,
    );

    for (final frac in fractions) {
      // Distance from destination at this marker
      final distFromDest = distInUnits * frac;
      // Y position: frac=0 is at apex (destination), frac=1 is at base (vessel)
      final markerY = apexY + frac * runwayHeight;

      // Skip if too close to anchor icon or vessel triangle
      if (markerY < apexY + 30 || markerY > baseY - 34) continue;

      // Format the distance label
      final label = _formatSmartDistance(distFromDest);

      // Draw label centered on the centerline
      final tp = TextPainter(
        text: TextSpan(text: label, style: markerStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      // Background pill behind text for readability
      final pillRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX, markerY),
          width: tp.width + 10,
          height: tp.height + 4,
        ),
        const Radius.circular(4),
      );
      canvas.drawRRect(
        pillRect,
        Paint()..color = (isDark ? Colors.black : Colors.white).withValues(alpha: 0.6),
      );

      tp.paint(
        canvas,
        Offset(centerX - tp.width / 2, markerY - tp.height / 2),
      );
    }
  }

  /// Format distance with minimal clutter. No unit symbol on every marker —
  /// just the number. Unit is already shown in the header.
  String _formatSmartDistance(double value) {
    if (value >= 10) return value.toStringAsFixed(0);
    if (value >= 1) return value.toStringAsFixed(1);
    if (value >= 0.1) return value.toStringAsFixed(2);
    return value.toStringAsFixed(3);
  }

  void _drawAnchorIcon(Canvas canvas, Offset center) {
    final Color anchorColor;
    if (isAisMode && isStaleTarget) {
      anchorColor = Colors.orange;
    } else if (isAisMode) {
      anchorColor = Colors.cyan;
    } else {
      anchorColor = isDark ? Colors.white70 : Colors.black54;
    }
    final paint = Paint()
      ..color = anchorColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final x = center.dx;
    final y = center.dy;

    canvas.drawLine(Offset(x, y - 6), Offset(x, y + 6), paint);
    canvas.drawLine(Offset(x - 5, y - 3), Offset(x + 5, y - 3), paint);
    canvas.drawCircle(Offset(x, y - 7), 2, paint);
    final flukePath = Path()
      ..moveTo(x - 6, y + 2)
      ..quadraticBezierTo(x - 6, y + 7, x, y + 6)
      ..quadraticBezierTo(x + 6, y + 7, x + 6, y + 2);
    canvas.drawPath(flukePath, paint);
  }

  /// Draw a simple boat icon pointing up (bow at top).
  void _drawBoatIcon(Canvas canvas, Offset center) {
    final Color boatColor;
    if (isAisMode && isStaleTarget) {
      boatColor = Colors.orange;
    } else if (isAisMode) {
      boatColor = Colors.cyan;
    } else {
      boatColor = isDark ? Colors.white70 : Colors.black54;
    }
    final paint = Paint()
      ..color = boatColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final x = center.dx;
    final y = center.dy;

    // Hull outline — pointed bow at top, flat stern at bottom
    final hull = Path()
      ..moveTo(x, y - 8)          // bow
      ..lineTo(x - 6, y + 2)      // port chine
      ..lineTo(x - 5, y + 6)      // port stern
      ..lineTo(x + 5, y + 6)      // starboard stern
      ..lineTo(x + 6, y + 2)      // starboard chine
      ..close();
    canvas.drawPath(hull, paint);

    // Keel line (centerline from bow down)
    canvas.drawLine(Offset(x, y - 8), Offset(x, y + 6), paint);
  }

  /// Draw target vessel chevron at apex, rotated to target COG.
  /// The rotation is relative: 0° means target heading same as dodge course (up).
  void _drawTargetVesselAtApex(Canvas canvas, Offset center, double cogDeg) {
    final color = isBowPass ? Colors.orange : Colors.cyan;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Draw a filled vessel shape rotated to target COG
    // Since the runway is heading-up (dodge course = up), the rotation
    // relative to vertical is (targetCOG - dodgeCourse). For simplicity,
    // we don't have dodgeCourse here, so we draw a non-rotated chevron
    // (the apex IS the target's track, so its COG line goes through it).
    canvas.save();
    canvas.translate(center.dx, center.dy);

    // Vessel hull
    final hull = Path()
      ..moveTo(0, -8)       // bow
      ..lineTo(-6, 2)       // port
      ..lineTo(-5, 6)       // port stern
      ..lineTo(5, 6)        // starboard stern
      ..lineTo(6, 2)        // starboard
      ..close();
    canvas.drawPath(hull, paint);

    // Fill with translucent color
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawPath(hull, fillPaint);

    canvas.restore();
  }

  void _drawDashedLine(Canvas canvas, Offset from, Offset to, Paint paint,
      double dashLen, double gapLen) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 1) return;
    final ux = dx / dist;
    final uy = dy / dist;
    var drawn = 0.0;
    while (drawn < dist) {
      final segEnd = math.min(drawn + dashLen, dist);
      canvas.drawLine(
        Offset(from.dx + ux * drawn, from.dy + uy * drawn),
        Offset(from.dx + ux * segEnd, from.dy + uy * segEnd),
        paint,
      );
      drawn = segEnd + gapLen;
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_RunwayPainter oldDelegate) {
    return oldDelegate.deviation != deviation ||
        oldDelegate.distanceMeters != distanceMeters ||
        oldDelegate.isDark != isDark ||
        oldDelegate.active != active ||
        oldDelegate.metersPerUnit != metersPerUnit ||
        oldDelegate.isWrongWay != isWrongWay ||
        oldDelegate.isAisMode != isAisMode ||
        oldDelegate.isStaleTarget != isStaleTarget ||
        oldDelegate.isTrackMode != isTrackMode ||
        oldDelegate.isDodgeMode != isDodgeMode ||
        oldDelegate.targetCogDeg != targetCogDeg ||
        oldDelegate.isBowPass != isBowPass;
  }
}

// --------------- Builder ---------------

class FindHomeToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'find_home',
      name: 'Find Home',
      description:
          'ILS-style approach display for navigating back to your anchored vessel',
      category: ToolCategory.navigation,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 1,
        styleOptions: const [],
      ),
      defaultWidth: 2,
      defaultHeight: 3,
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: [
        DataSource(path: 'navigation.position', label: 'Home Target'),
      ],
      style: StyleConfig(
        customProperties: {
          'feedbackInterval': 10, // seconds (5-60)
          'alertSound': 'whistle',
          'trackCogPath': 'navigation.courseOverGroundTrue',
          'trackSogPath': 'navigation.speedOverGround',
          'dodgeDistance': 300.0, // meters (SI) — displayed via MetadataStore
        },
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return FindHomeTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
