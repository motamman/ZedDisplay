import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import '../../config/app_colors.dart';
import '../../models/path_metadata.dart';
import '../../models/tool_config.dart';
import '../../models/tool_definition.dart';
import '../../services/signalk_service.dart';
import '../../services/storage_service.dart';
import '../../services/tool_registry.dart';
import '../../services/alarm_audio_player.dart';
import '../../services/alert_coordinator.dart';
import '../../services/autopilot_command_service.dart';
import '../../services/autopilot_state_verifier.dart';
import '../../services/route_arrival_monitor.dart';
import '../../services/dodge_autopilot_service.dart';
import '../../services/find_home_target_service.dart';
import '../../models/alert_event.dart';
import '../../models/autopilot_errors.dart';
import '../../utils/angle_utils.dart';
import '../../widgets/countdown_confirmation_overlay.dart';
import '../../utils/cpa_utils.dart';
import '../../utils/dodge_utils.dart';
import '../../utils/sun_calc.dart';
import 'find_home_dodge_dialog.dart';
import 'find_home_set_dialog.dart';
import 'find_home_runway_painter.dart';


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

  /// SignalK paths for route navigation data
  static const _routePaths = [
    'navigation.course.calcValues.bearingTrue',
    'navigation.course.calcValues.crossTrackError',
    'navigation.course.calcValues.distance',
    'navigation.course.calcValues.timeToGo',
    'navigation.course.calcValues.estimatedTimeOfArrival',
    'navigation.courseGreatCircle.nextPoint.position',
    'navigation.course.activeRoute',
  ];

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

  // Sun/moon sky display
  double _sunAltitudeDeg = -90;
  double _sunAzimuthDeg = 0;
  double _moonAltitudeDeg = -90;
  double _moonAzimuthDeg = 0;
  double _moonPhase = 0;
  double _moonFraction = 0;
  Timer? _skyTimer;

  // Auto-dodge autopilot integration
  DodgeAutopilotService? _dodgeAutopilotService;
  bool _autoDodgeEnabled = false;
  bool _dodgeCompleting = false;
  AlertCoordinator? _alertCoordinator;

  // Route mode
  bool _routeMode = false;
  AutopilotCommandService? _routeApService;
  RouteArrivalMonitor? _routeArrivalMonitor;
  StreamSubscription<RouteArrivalEvent>? _arrivalSub;
  bool _routeApEngaged = false;
  String _routeApMode = 'Standby';
  bool _routeDodgeActive = false;
  double? _routeBearingTrue;       // degrees (converted from radians)
  double? _routeXteMeters;         // signed: +starboard, -port
  double? _routeDistanceMeters;
  Duration? _routeTimeToGo;
  DateTime? _routeEta;
  int? _routePointIndex;
  int? _routePointTotal;

  /// Safe pass distance in SI meters (from config, default 300m).
  /// Stored in SI; displayed via MetadataStore through _formatDistance().
  double get _dodgeSafeDistanceM {
    final val = widget.config.style.customProperties?['dodgeDistance'] as num?;
    return val?.toDouble() ?? 300.0;
  }

  /// Full lateral deflection in meters for route XTE display (default 0.1nm = 185.2m).
  double get _routeXteScaleMeters {
    final val = widget.config.style.customProperties?['routeXteScale'] as num?;
    return val?.toDouble() ?? 185.2;
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
    // Subscribe to the target position + track-mode nav paths + route paths
    widget.signalKService.subscribeToPaths(
      [_targetPath, _trackCogPath, _trackSogPath, ..._routePaths],
      ownerId: _ownerId,
    );
    widget.signalKService.addListener(_onSignalKUpdate);
    _initDeviceGps();
    // Update sky bodies every 60s so sun/moon move even when stationary
    _skyTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      final pos = _devicePosition;
      if (pos != null && mounted) {
        setState(() => _updateSunMoon(pos.latitude, pos.longitude));
      }
    });
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
    _arrivalSub?.cancel();
    _routeArrivalMonitor?.dispose();
    _routeApService?.dispose();
    _hapticTimer?.cancel();
    _skyTimer?.cancel();
    _positionSub?.cancel();
    _whistlePlayer?.dispose();
    widget.signalKService.removeListener(_onSignalKUpdate);
    widget.signalKService.unsubscribeFromPaths(
      [_targetPath, _trackCogPath, _trackSogPath, _apStatePath, ..._routePaths],
      ownerId: _ownerId,
    );
    _findHomeTargetService?.removeListener(_onFindHomeTargetUpdate);
    if (_aisVesselId != null) {
      widget.signalKService.aisVesselRegistry.removeListener(_onAISRegistryUpdate);
    }
    super.dispose();
  }

  void _onSignalKUpdate() {
    if (!mounted) return;
    setState(() {
      _updateRouteData();
    });
  }

  void _updateRouteData() {
    // Route bearing (radians → degrees)
    final bearingData = widget.signalKService.getValue(
        'navigation.course.calcValues.bearingTrue');
    _routeBearingTrue = bearingData?.value is num
        ? _convertAngle((bearingData!.value as num).toDouble())
        : null;

    // Cross-track error (meters, signed)
    final xteData = widget.signalKService.getValue(
        'navigation.course.calcValues.crossTrackError');
    _routeXteMeters =
        xteData?.value is num ? (xteData!.value as num).toDouble() : null;

    // Distance to waypoint (meters)
    final distData = widget.signalKService.getValue(
        'navigation.course.calcValues.distance');
    _routeDistanceMeters =
        distData?.value is num ? (distData!.value as num).toDouble() : null;

    // Time to go (seconds → Duration)
    final ttgData = widget.signalKService.getValue(
        'navigation.course.calcValues.timeToGo');
    _routeTimeToGo = ttgData?.value is num
        ? Duration(seconds: (ttgData!.value as num).toInt())
        : null;

    // ETA (ISO 8601 string → DateTime)
    final etaData = widget.signalKService.getValue(
        'navigation.course.calcValues.estimatedTimeOfArrival');
    if (etaData?.value != null) {
      try {
        _routeEta = DateTime.parse(etaData!.value.toString());
      } catch (_) {
        _routeEta = null;
      }
    } else {
      _routeEta = null;
    }

    // Active route info (pointIndex / pointTotal)
    final activeRouteData = widget.signalKService.getValue(
        'navigation.course.activeRoute');
    if (activeRouteData?.value is Map) {
      final m = activeRouteData!.value as Map;
      _routePointIndex = m['pointIndex'] as int?;
      _routePointTotal = m['pointTotal'] as int?;
    } else {
      _routePointIndex = null;
      _routePointTotal = null;
    }

    // AP state (only read when in route mode)
    if (_routeMode) {
      final apData = widget.signalKService.getValue(_apStatePath);
      if (apData?.value != null) {
        final raw = apData!.value.toString();
        _routeApMode = raw.isNotEmpty
            ? raw[0].toUpperCase() + raw.substring(1).toLowerCase()
            : 'Standby';
        _routeApEngaged = _routeApMode.toLowerCase() != 'standby';
      }
    }
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
            setState(() {
              _devicePosition = position;
              _updateSunMoon(position.latitude, position.longitude);
            });
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

  /// Angle category metadata (rad → deg or user-configured unit).
  PathMetadata? get _angleMeta =>
      widget.signalKService.metadataStore.get('__category__.angle');

  /// Convert a radian value to the user's preferred angle unit. When
  /// metadata is missing the value flows through unchanged (still in
  /// radians); callers that care render the matching [_angleSymbol].
  double _convertAngle(double radians) =>
      _angleMeta?.convert(radians) ?? radians;

  /// Convert from display angle unit back to radians (for CPA/API calls).
  /// When metadata is missing the input is treated as already-radians.
  double _convertToRadians(double displayAngle) =>
      _angleMeta?.convertToSI(displayAngle) ?? displayAngle;

  /// The symbol for the user's angle unit (e.g., '°'). Falls back to the
  /// SI symbol 'rad' when no angle metadata is registered.
  String get _angleSymbol => _angleMeta?.symbol ?? 'rad';

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
      cogDeg = cogRad != null ? _convertAngle(cogRad) : 0.0;
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

  // --------------- Route nav computation ---------------

  /// Compute route navigation data when in route mode.
  /// Uses vessel position from SignalK and route bearing/XTE from calcValues.
  ({
    double bearing,
    double deviation,
    double distance,
    double cogDeg,
    double sogMs,
    double vesselSogMs,
    bool isWrongWay,
  })? _computeRoute() {
    if (_routeBearingTrue == null) return null;

    // Position source: always SignalK vessel position in route mode
    final posData = widget.signalKService.getValue(_targetPath);
    if (posData?.value is! Map) return null;
    final m = posData!.value as Map;
    final skLat = m['latitude'];
    final skLon = m['longitude'];
    if (skLat is! num || skLon is! num) return null;

    // COG/SOG from vessel
    final cogData = widget.signalKService.getValue(_trackCogPath);
    final sogData = widget.signalKService.getValue(_trackSogPath);
    final sogMs = (sogData?.value as num?)?.toDouble() ?? 0.0;
    final cogRad = (cogData?.value as num?)?.toDouble();
    final cogDeg = cogRad != null ? _convertAngle(cogRad) : 0.0;

    // Bearing: from route calcValues
    final bearing = _routeBearingTrue!;

    // Deviation: XTE mapped to degrees for runway display
    double deviation = 0.0;
    if (_routeXteMeters != null) {
      deviation =
          (_routeXteMeters! / _routeXteScaleMeters) * _maxDeviation;
      deviation = deviation.clamp(-_maxDeviation, _maxDeviation);
    } else if (sogMs >= _sogThreshold) {
      // Fallback: COG vs bearing deviation
      deviation = AngleUtils.difference(cogDeg, bearing);
    }

    final distance = _routeDistanceMeters ?? 0.0;
    final isWrongWay = sogMs >= _sogThreshold &&
        AngleUtils.difference(cogDeg, bearing).abs() > 90.0;

    return (
      bearing: AngleUtils.normalize(bearing),
      deviation: deviation,
      distance: distance,
      cogDeg: AngleUtils.normalize(cogDeg),
      sogMs: sogMs,
      vesselSogMs: sogMs, // same vessel in route mode
      isWrongWay: isWrongWay,
    );
  }

  // --------------- Sun/Moon sky ---------------

  void _updateSunMoon(double lat, double lng) {
    final now = DateTime.now().toUtc();
    final sunPos = SunCalc.getPosition(now, lat, lng);
    final moonPos = MoonCalc.getPosition(now, lat, lng);
    final moonIllum = MoonCalc.getIllumination(now);
    _sunAltitudeDeg = sunPos.altitudeDegrees;
    _sunAzimuthDeg = sunPos.azimuthDegrees;
    _moonAltitudeDeg = moonPos.altitudeDegrees;
    _moonAzimuthDeg = moonPos.azimuthDegrees;
    _moonPhase = moonIllum.phase;
    _moonFraction = moonIllum.fraction;
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
      ownCogDeg = cogRad != null ? _convertAngle(cogRad) : 0.0;
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

    final courseToSteerDeg = _convertAngle(dodgeResult.courseToSteerRad);
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

    final targetCogDeg = _convertAngle(vessel.cogRad!);

    // Feed dodge result to autopilot if auto-dodge is active
    if (_autoDodgeEnabled && dodgeResult.isFeasible) {
      _dodgeAutopilotService?.sendDodgeHeading(dodgeResult);
    }

    // Completion detection: check CPA/TCPA for diverging vessels
    if (_autoDodgeEnabled && _dodgeAutopilotService != null) {
      final cpaTcpa = CpaUtils.calculateCpaTcpa(
        bearingDeg: bearingToTarget,
        distanceM: distToTarget,
        ownCogRad: ownSogMs > 0.1 ? _convertToRadians(ownCogDeg) : null,
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
      builder: (ctx) => FindHomeDodgeRecoveryDialog(
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

  // --------------- Route autopilot controls ---------------

  Future<void> _initRouteAp() async {
    _routeApService ??=
        AutopilotCommandService(signalKService: widget.signalKService);
    await _routeApService!.detect();
    widget.signalKService.subscribeToPaths([_apStatePath], ownerId: _ownerId);
    // Wire AP service into arrival monitor
    _routeArrivalMonitor?.apService = _routeApService;
  }

  void _toggleRouteMode() {
    if (_routeMode) {
      _routeArrivalMonitor?.stop();
      _arrivalSub?.cancel();
      _arrivalSub = null;
      setState(() => _routeMode = false);
    } else {
      _disengageAutoDodge();
      setState(() {
        _routeMode = true;
        _dodgeMode = false;
      });
      // Re-subscribe to route paths — the server may not have been
      // streaming them if the route was activated after our initial subscribe.
      widget.signalKService.subscribeToPaths(
        [..._routePaths, _apStatePath],
        ownerId: _ownerId,
      );
      if (_routeApService == null || !_routeApService!.isDetected) {
        _initRouteAp();
      }
      _startArrivalMonitor();
    }
  }

  void _startArrivalMonitor() {
    _routeArrivalMonitor ??=
        RouteArrivalMonitor(signalKService: widget.signalKService);
    _routeArrivalMonitor!.apService = _routeApService;
    _arrivalSub?.cancel();
    _arrivalSub = _routeArrivalMonitor!.arrivalStream.listen(_onWaypointArrival);
    _routeArrivalMonitor!.start();
  }

  void _onWaypointArrival(RouteArrivalEvent event) {
    if (!mounted || !_routeMode) return;

    if (event.isLastWaypoint) {
      // Last waypoint — offer to end route
      showCountdownConfirmation(
        context: context,
        title: 'Final Waypoint Reached',
        action: 'End Route',
      ).then((confirmed) {
        if (confirmed) _toggleRouteMode();
      });
    } else {
      // Auto-advance with countdown
      showCountdownConfirmation(
        context: context,
        title: 'Waypoint ${event.pointIndex + 1}/${event.pointTotal} Reached',
        action: 'Next Waypoint',
      ).then((confirmed) {
        if (confirmed) {
          _routeApCommand(
            'Advance Waypoint',
            () => _routeArrivalMonitor!.advance(),
          );
        }
      });
    }
  }

  /// Shared snackbar wrapper for route AP commands.
  Future<void> _routeApCommand(
    String desc,
    Future<void> Function() cmd, {
    String? verifyPath,
    dynamic verifyValue,
  }) async {
    try {
      await cmd();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$desc...'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      if (verifyPath != null && verifyValue != null) {
        final verifier = AutopilotStateVerifier(
          widget.signalKService,
          timeout: const Duration(seconds: 10),
        );
        final ok = await verifier.verifyChange(
          path: verifyPath,
          expectedValue: verifyValue,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ok ? 'Command successful' : 'Command sent but not confirmed',
              ),
              backgroundColor: ok ? Colors.green : Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Command successful'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
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
          ),
        );
      }
    }
  }

  void _routeEngageDisengage() => _routeApCommand(
        _routeApEngaged ? 'Disengage' : 'Engage',
        () => _routeApEngaged
            ? _routeApService!.disengage()
            : _routeApService!.engage(),
        verifyPath: _apStatePath,
        verifyValue: _routeApEngaged ? 'standby' : 'auto',
      );

  void _routeAdjustHeading(int deg) => _routeApCommand(
        'Adjust ${deg > 0 ? "+" : ""}$deg$_angleSymbol',
        () => _routeApService!.adjustHeading(deg),
      );

  void _routeAdvanceWaypoint() async {
    final confirmed = await showCountdownConfirmation(
      context: context,
      title: 'Advance to Next Waypoint?',
      action: 'Advance Waypoint',
    );
    if (!confirmed) return;
    _routeApCommand(
      'Advance Waypoint',
      () => _routeApService!.advanceWaypoint(),
    );
  }

  void _routeDodgeToggle() async {
    if (_routeApService == null || !_routeApService!.isV2) {
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
    final newState = !_routeDodgeActive;
    await _routeApCommand(
      newState ? 'Activate dodge' : 'Deactivate dodge',
      () => newState
          ? _routeApService!.activateDodge()
          : _routeApService!.deactivateDodge(),
    );
    if (mounted) {
      setState(() => _routeDodgeActive = newState);
    }
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
      builder: (context) => FindHomeSetDialog(
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
    return '${degrees.toStringAsFixed(0)}$_angleSymbol';
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

  /// Format a Duration as h:mm or m:ss
  String _formatDuration(Duration d) {
    final totalMins = d.inMinutes;
    if (totalMins >= 60) {
      final hrs = totalMins ~/ 60;
      final mins = totalMins % 60;
      return '$hrs:${mins.toString().padLeft(2, '0')}';
    }
    final secs = d.inSeconds % 60;
    return '$totalMins:${secs.toString().padLeft(2, '0')}';
  }

  /// Format lat/lon in degrees decimal minutes (shared with SetHomeDialog)
  String _formatDDM(double lat, double lon) => formatDDM(lat, lon);

  // --------------- Build ---------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Route mode: compute from route data (independent of home/AIS target)
    if (_routeMode) {
      final routeNav = _computeRoute();
      if (routeNav == null) {
        return _buildNoActiveRoute(isDark);
      }
      return _buildRunway(
        bearing: routeNav.bearing,
        deviation: routeNav.deviation,
        distance: routeNav.distance,
        cogDeg: routeNav.cogDeg,
        sogMs: routeNav.sogMs,
        vesselSogMs: routeNav.vesselSogMs,
        isWrongWay: routeNav.isWrongWay,
        isDark: isDark,
        inDodge: false,
        inRoute: true,
      );
    }

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

    return _buildRunway(
      bearing: displayBearing,
      deviation: displayDeviation,
      distance: displayDistance,
      cogDeg: displayCogDeg,
      sogMs: displaySogMs,
      vesselSogMs: displayVesselSogMs,
      isWrongWay: displayIsWrongWay,
      isDark: isDark,
      inDodge: inDodge,
      inRoute: false,
      dodgeTargetCogDeg: dodgeNav?.targetCogDeg,
    );
  }

  Widget _buildRunway({
    required double bearing,
    required double deviation,
    required double distance,
    required double cogDeg,
    required double sogMs,
    required double vesselSogMs,
    required bool isWrongWay,
    required bool isDark,
    required bool inDodge,
    required bool inRoute,
    double? dodgeTargetCogDeg,
  }) {
    final distMeta = _pickDistanceMeta(distance);
    double metersPerUnit = 1.0;
    String unitSymbol = 'm';
    if (distMeta != null) {
      final oneConverted = distMeta.convert(1.0);
      if (oneConverted != null && oneConverted > 0) {
        metersPerUnit = 1.0 / oneConverted;
      }
      unitSymbol = distMeta.symbol ?? 'm';
    }

    return Column(
      children: [
        _buildHeader(
          bearing: bearing,
          deviation: deviation,
          distance: distance,
          cogDeg: cogDeg,
          sogMs: sogMs,
          vesselSogMs: vesselSogMs,
          isWrongWay: isWrongWay,
          isDark: isDark,
          inDodge: inDodge,
          inRoute: inRoute,
        ),
        Expanded(
          child: ClipRect(
            child: CustomPaint(
              painter: FindHomeRunwayPainter(
                deviation: deviation,
                maxDeviation: _maxDeviation,
                distanceMeters: distance,
                metersPerUnit: metersPerUnit,
                unitSymbol: unitSymbol,
                isDark: isDark,
                active: _active,
                hapticThreshold: _hapticDeviationThreshold,
                isWrongWay: isWrongWay,
                isAisMode: _aisVesselId != null,
                isStaleTarget: _aisTargetStale,
                isTrackMode: _trackMode || inRoute,
                isDodgeMode: inDodge,
                isRouteMode: inRoute,
                targetCogDeg: dodgeTargetCogDeg,
                isBowPass: _dodgeBowPass,
                sunAltitudeDeg: _sunAltitudeDeg,
                sunAzimuthDeg: _sunAzimuthDeg,
                moonAltitudeDeg: _moonAltitudeDeg,
                moonAzimuthDeg: _moonAzimuthDeg,
                moonPhase: _moonPhase,
                moonFraction: _moonFraction,
                vesselCogDeg: cogDeg,
                vesselLatitude: _devicePosition?.latitude ?? 0,
              ),
              size: Size.infinite,
            ),
          ),
        ),
        _buildFooter(
          bearing: bearing,
          deviation: deviation,
          distance: distance,
          cogDeg: cogDeg,
          sogMs: sogMs,
          vesselSogMs: vesselSogMs,
          isWrongWay: isWrongWay,
          isDark: isDark,
          inDodge: inDodge,
          inRoute: inRoute,
        ),
      ],
    );
  }

  Widget _buildNoActiveRoute(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.route, size: 32, color: Colors.grey),
          const SizedBox(height: 8),
          const Text(
            'No active route',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 4),
          const Text(
            'Activate a route on the SignalK server',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _toggleRouteMode,
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Exit Route'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoTarget(bool isDark) {
    return Center(
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
    );
  }

  Widget _buildGpsError(bool isDark) {
    return Center(
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
    );
  }

  Widget _buildAcquiringGps(bool isDark) {
    return Center(
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
    );
  }

  Widget _buildWaitingForSignalK(bool isDark) {
    return Center(
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
    bool inRoute = false,
  }) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final labelColor = isDark ? Colors.white60 : Colors.black54;
    final (homeLat, homeLon) = _getTargetPosition();
    final hasManual = _manualLat != null && _manualLon != null;
    final inAisMode = _aisVesselId != null;
    final String headerTitle;
    if (inRoute && _routePointIndex != null && _routePointTotal != null) {
      headerTitle = 'ROUTE ${_routePointIndex! + 1}/$_routePointTotal';
    } else if (inRoute) {
      headerTitle = 'ROUTE';
    } else if (inDodge) {
      headerTitle = 'DODGE';
    } else {
      headerTitle = 'FIND HOME';
    }
    final headerColor = inRoute
        ? Colors.green
        : inDodge
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
                        color: (inDodge || inRoute) ? headerColor : labelColor,
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
                    if (!inAisMode && !inRoute) ...[
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
                inRoute
                    ? 'DTW ${_formatDistance(distance)}'
                    : inDodge
                        ? 'APEX ${_formatDistance(distance)}'
                        : _formatDistance(distance),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: (inDodge || inRoute) ? headerColor : textColor,
                ),
              ),
            ],
          ),
          if (inRoute)
            Text(
              _routeEta != null
                  ? 'ETA ${_routeEta!.toLocal().hour.toString().padLeft(2, '0')}:${_routeEta!.toLocal().minute.toString().padLeft(2, '0')}  BRG ${_formatAngle(bearing)}'
                  : _routeTimeToGo != null
                      ? 'TTW ${_formatDuration(_routeTimeToGo!)}  BRG ${_formatAngle(bearing)}'
                      : 'BRG ${_formatAngle(bearing)}',
              style: TextStyle(fontSize: 10, color: headerColor, fontFamily: 'monospace'),
            )
          else if (inDodge)
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

  Widget _buildPillButton(
    String label,
    Color color,
    VoidCallback onTap, {
    bool enabled = true,
  }) {
    final effectiveColor = enabled ? color : Colors.grey.withValues(alpha: 0.4);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: effectiveColor.withValues(alpha: enabled ? 0.2 : 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: effectiveColor, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: effectiveColor,
          ),
        ),
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
    bool inRoute = false,
  }) {
    final labelColor = isDark ? Colors.white60 : Colors.black54;
    final absDev = deviation.abs();
    final devSide = deviation > 0 ? 'P' : 'S';
    final inAisMode = _aisVesselId != null;

    Color devColor;
    if (isWrongWay) {
      devColor = Colors.red;
    } else if (inRoute) {
      // XTE-based coloring: tighter thresholds
      if (absDev < 5) {
        devColor = Colors.green;
      } else if (absDev < 15) {
        devColor = Colors.amber;
      } else {
        devColor = Colors.red;
      }
    } else if (absDev < 5) {
      devColor = Colors.green;
    } else if (absDev < 15) {
      devColor = Colors.amber;
    } else {
      devColor = Colors.red;
    }

    final String devLabel;
    if (isWrongWay) {
      devLabel = 'WRONG WAY';
    } else if (inRoute && _routeXteMeters != null) {
      // Show XTE in distance units with port/starboard
      final xteSide = _routeXteMeters! > 0 ? 'S' : 'P';
      devLabel = 'XTE ${_formatDistance(_routeXteMeters!.abs())} $xteSide';
    } else {
      devLabel = 'DEV ${absDev.toStringAsFixed(0)}$_angleSymbol $devSide';
    }

    final String etaLabel;
    if (isWrongWay) {
      etaLabel = 'ETA --:--';
    } else if (inRoute && _routeTimeToGo != null) {
      etaLabel = 'TTW ${_formatDuration(_routeTimeToGo!)}';
    } else {
      etaLabel = 'ETA ${_formatEta(distance, sogMs)}';
    }

    // Labels change based on AIS mode, track mode, dodge mode, route mode
    final String bearingLabel;
    if (inRoute) {
      bearingLabel = 'WPT ${_formatAngle(bearing)}';
    } else if (inDodge) {
      bearingLabel = 'STR ${_formatAngle(bearing)}';
    } else if (inAisMode) {
      bearingLabel = 'TO ${_aisVesselName ?? 'AIS'}';
    } else {
      bearingLabel = 'TO BOAT';
    }
    final youLabel = (inRoute || _trackMode) ? 'VESSEL' : 'YOU';

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
                  (inDodge || inRoute) ? bearingLabel : '$bearingLabel ${_formatAngle(bearing)}',
                  style: TextStyle(
                      fontSize: 12, fontFamily: 'monospace', color: inRoute ? Colors.green : inDodge ? (_dodgeBowPass ? Colors.orange : Colors.cyan) : labelColor),
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
                '$youLabel ${_formatSpeed(sogMs, skPath: (_trackMode || inRoute) ? 'navigation.speedOverGround' : null)}',
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
              if (inRoute)
                Text(
                  'AP ${_routeApMode.toUpperCase()}',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: _routeApEngaged ? Colors.green : Colors.grey,
                  ),
                )
              else if (inDodge)
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
                  // ROUTE button (visible when not in AIS mode)
                  // Always tappable — route data may arrive after subscribe
                  if (!inAisMode) ...[
                    GestureDetector(
                      onTap: _toggleRouteMode,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _routeMode
                              ? Colors.green.withValues(alpha: 0.3)
                              : Colors.grey.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _routeMode ? Colors.green : Colors.grey,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          'ROUTE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _routeMode ? Colors.green : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Route AP controls (when route mode active and AP detected)
                  if (inRoute && _routeApService?.isDetected == true) ...[
                    // Engage/Stop
                    GestureDetector(
                      onTap: _routeEngageDisengage,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _routeApEngaged
                              ? AppColors.alarmRed.withValues(alpha: 0.3)
                              : AppColors.successGreen.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _routeApEngaged
                                ? AppColors.alarmRed
                                : AppColors.successGreen,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          _routeApEngaged ? 'STOP' : 'ENGAGE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _routeApEngaged
                                ? AppColors.alarmRed
                                : AppColors.successGreen,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Dodge active: ±1/±10 heading adjust + EXIT
                    if (_routeDodgeActive) ...[
                      _buildPillButton('-10', Colors.red, () => _routeAdjustHeading(-10),
                          enabled: _routeApEngaged),
                      const SizedBox(width: 4),
                      _buildPillButton('-1', Colors.red, () => _routeAdjustHeading(-1),
                          enabled: _routeApEngaged),
                      const SizedBox(width: 4),
                      _buildPillButton('EXIT', Colors.orange, _routeDodgeToggle),
                      const SizedBox(width: 4),
                      _buildPillButton('+1', Colors.green, () => _routeAdjustHeading(1),
                          enabled: _routeApEngaged),
                      const SizedBox(width: 4),
                      _buildPillButton('+10', Colors.green, () => _routeAdjustHeading(10),
                          enabled: _routeApEngaged),
                    ],
                    // Not dodging: DODGE + WPT advance
                    if (!_routeDodgeActive) ...[
                      if (_routeApService!.isV2 && _routeApEngaged)
                        _buildPillButton('DODGE', const Color(0xFF00B0FF), _routeDodgeToggle),
                      if (_routeApService!.isV2 && _routeApEngaged)
                        const SizedBox(width: 4),
                      _buildPillButton('WPT\u203A', Colors.blue, _routeAdvanceWaypoint,
                          enabled: _routeApEngaged),
                    ],
                    const SizedBox(width: 8),
                  ],
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
                                ? 'AP\u2192${hdg.toStringAsFixed(0)}$_angleSymbol'
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
        allowsUnitSelection: false,
        allowsVisibilityToggles: false,
        allowsTTL: false,
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
          'routeXteScale': 185.2, // meters (0.1nm) — full deflection XTE
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
