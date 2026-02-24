import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/anchor_state.dart';
import '../utils/conversion_utils.dart';
import 'signalk_service.dart';
import 'notification_service.dart';
import 'messaging_service.dart';

/// Configuration for SignalK paths used by anchor alarm
class AnchorAlarmPaths {
  final String anchorPosition;
  final String maxRadius;
  final String currentRadius;
  final String rodeLength;
  final String bearing;
  final String vesselPosition;
  final String heading;
  final String gpsFromBow;
  final String depth;
  final String fudgeFactor;
  final String vesselLength;

  // Default paths
  static const _defaults = [
    'navigation.anchor.position',      // 0
    'navigation.anchor.maxRadius',     // 1
    'navigation.anchor.currentRadius', // 2
    'navigation.anchor.rodeLength',    // 3
    'navigation.anchor.bearingTrue',   // 4
    'navigation.position',             // 5
    'navigation.headingTrue',          // 6
    'sensors.gps.fromBow',             // 7
    'environment.depth.belowSurface',  // 8
    'navigation.anchor.fudgeFactor',   // 9
    'design.length',                   // 10
  ];

  const AnchorAlarmPaths({
    this.anchorPosition = 'navigation.anchor.position',
    this.maxRadius = 'navigation.anchor.maxRadius',
    this.currentRadius = 'navigation.anchor.currentRadius',
    this.rodeLength = 'navigation.anchor.rodeLength',
    this.bearing = 'navigation.anchor.bearingTrue',
    this.vesselPosition = 'navigation.position',
    this.heading = 'navigation.headingTrue',
    this.gpsFromBow = 'sensors.gps.fromBow',
    this.depth = 'environment.depth.belowSurface',
    this.fudgeFactor = 'navigation.anchor.fudgeFactor',
    this.vesselLength = 'design.length',
  });

  /// Create from dataSources list (from ToolConfig)
  factory AnchorAlarmPaths.fromDataSources(List<dynamic>? dataSources) {
    String getPath(int index) {
      if (dataSources != null && dataSources.length > index) {
        final ds = dataSources[index];
        if (ds != null) {
          // Handle both DataSource objects and maps
          final path = ds is Map ? ds['path'] : ds.path;
          if (path != null && path.toString().isNotEmpty) {
            return path.toString();
          }
        }
      }
      return _defaults[index];
    }

    return AnchorAlarmPaths(
      anchorPosition: getPath(0),
      maxRadius: getPath(1),
      currentRadius: getPath(2),
      rodeLength: getPath(3),
      bearing: getPath(4),
      vesselPosition: getPath(5),
      heading: getPath(6),
      gpsFromBow: getPath(7),
      depth: getPath(8),
      fudgeFactor: getPath(9),
      vesselLength: getPath(10),
    );
  }
}

/// Service for managing anchor alarm functionality
/// Integrates with SignalK anchor alarm plugin via REST API
class AnchorAlarmService extends ChangeNotifier {
  final SignalKService _signalKService;
  final NotificationService _notificationService;
  final MessagingService? _messagingService;

  // Configurable SignalK paths
  AnchorAlarmPaths _paths = const AnchorAlarmPaths();
  AnchorAlarmPaths get paths => _paths;

  // Current state
  AnchorState _state = AnchorState.initial();
  AnchorState get state => _state;

  // Track history
  List<TrackPoint> _trackHistory = [];
  List<TrackPoint> get trackHistory => List.unmodifiable(_trackHistory);

  // Check-in system
  CheckInConfig _checkInConfig = const CheckInConfig();
  CheckInConfig get checkInConfig => _checkInConfig;
  Timer? _checkInTimer;
  Timer? _checkInGraceTimer;
  bool _awaitingCheckIn = false;
  bool get awaitingCheckIn => _awaitingCheckIn;
  DateTime? _checkInDeadline;
  DateTime? get checkInDeadline => _checkInDeadline;

  // Audio playback
  AudioPlayer? _alarmPlayer;
  Timer? _alarmRepeatTimer;
  String _alarmSound = 'foghorn';
  bool _alarmSoundPlaying = false;

  // Track connection state
  bool _wasConnected = false;

  // SignalK notification key for anchor alarm
  static const _anchorNotificationKey = 'navigation.anchor';

  // GPS distance from bow (from vessel design data)
  double? _gpsFromBow;
  double? get gpsFromBow => _gpsFromBow;

  // Current depth from sensor
  double? _currentDepth;
  double? get currentDepth => _currentDepth;
  bool get hasDepthSensor => _currentDepth != null;

  // Fudge factor (margin) from plugin
  double? _fudgeFactor;
  double? get fudgeFactor => _fudgeFactor;

  // Vessel LOA (Length Overall) from design.length.overall
  double? _vesselLOA;
  double? get vesselLOA => _vesselLOA;

  // Available alarm sounds
  static const Map<String, String> alarmSounds = {
    'bell': 'sounds/alarm_bell.mp3',
    'foghorn': 'sounds/alarm_foghorn.mp3',
    'chimes': 'sounds/alarm_chimes.mp3',
    'ding': 'sounds/alarm_ding.mp3',
    'whistle': 'sounds/alarm_whistle.mp3',
    'dog': 'sounds/alarm_dog.mp3',
  };

  AnchorAlarmService({
    required SignalKService signalKService,
    NotificationService? notificationService,
    MessagingService? messagingService,
  })  : _signalKService = signalKService,
        _notificationService = notificationService ?? NotificationService(),
        _messagingService = messagingService;

  /// Initialize and start listening to SignalK updates
  void initialize() {
    _signalKService.addListener(_onSignalKUpdate);

    // Subscribe to anchor paths via WebSocket
    _subscribeToAnchorPaths();

    if (_signalKService.isConnected) {
      _wasConnected = true;
      _refreshState();
    }
  }

  /// Subscribe to all anchor-related paths
  void _subscribeToAnchorPaths() {
    final paths = [
      _paths.anchorPosition,
      _paths.maxRadius,
      _paths.currentRadius,
      _paths.rodeLength,
      _paths.bearing,
      _paths.vesselPosition,
      _paths.heading,
      _paths.gpsFromBow,
      _paths.depth,
      _paths.fudgeFactor,
      _paths.vesselLength,
      'navigation.anchor.distanceFromBow',
      'navigation.headingMagnetic',
    ];
    _signalKService.subscribeToPaths(paths);
  }

  /// Unsubscribe from anchor paths
  void _unsubscribeFromAnchorPaths() {
    final paths = [
      _paths.anchorPosition,
      _paths.maxRadius,
      _paths.currentRadius,
      _paths.rodeLength,
      _paths.bearing,
      _paths.vesselPosition,
      _paths.heading,
      _paths.gpsFromBow,
      _paths.depth,
      _paths.fudgeFactor,
      _paths.vesselLength,
      'navigation.anchor.distanceFromBow',
      'navigation.headingMagnetic',
    ];
    _signalKService.unsubscribeFromPaths(paths);
  }

  @override
  void dispose() {
    _unsubscribeFromAnchorPaths();
    _signalKService.removeListener(_onSignalKUpdate);
    _checkInTimer?.cancel();
    _checkInGraceTimer?.cancel();
    _alarmRepeatTimer?.cancel();
    _alarmPlayer?.dispose();
    super.dispose();
  }

  /// Set alarm sound to use
  void setAlarmSound(String sound) {
    if (alarmSounds.containsKey(sound)) {
      _alarmSound = sound;
    }
  }

  /// Configure SignalK paths
  void setPaths(AnchorAlarmPaths paths) {
    _paths = paths;
  }

  /// Configure check-in system
  void setCheckInConfig(CheckInConfig config) {
    final wasEnabled = _checkInConfig.enabled;
    _checkInConfig = config;

    if (config.enabled && _state.isActive && !wasEnabled) {
      _startCheckInTimer();
    } else if (!config.enabled && wasEnabled) {
      _stopCheckInTimer();
    }

    notifyListeners();
  }

  // === REST API Methods ===

  /// Drop anchor at current position
  Future<bool> dropAnchor({double? radius}) async {
    try {
      final body = radius != null ? {'radius': radius} : null;

      final response = await _signalKService.postPluginApi(
        '/plugins/anchoralarm/dropAnchor',
        body: body,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _refreshState();

        // Start check-in timer if enabled
        if (_checkInConfig.enabled) {
          _startCheckInTimer();
        }

        return true;
      } else {
        if (kDebugMode) {
          print('Drop anchor failed: ${response.statusCode} - ${response.body}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Drop anchor error: $e');
      }
      return false;
    }
  }

  /// Raise anchor (disable alarm)
  Future<bool> raiseAnchor() async {
    try {
      final response = await _signalKService.postPluginApi(
        '/plugins/anchoralarm/raiseAnchor',
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Stop check-in timer
        _stopCheckInTimer();

        // Stop any playing alarm
        await _stopAlarmSound();

        // Clear state
        _state = AnchorState.initial();
        _trackHistory.clear();
        notifyListeners();

        return true;
      } else {
        if (kDebugMode) {
          print('Raise anchor failed: ${response.statusCode} - ${response.body}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Raise anchor error: $e');
      }
      return false;
    }
  }

  /// Set alarm radius (auto-calculate from current position if null)
  Future<bool> setRadius({double? radius}) async {
    try {
      final body = radius != null ? {'radius': radius} : null;

      final response = await _signalKService.postPluginApi(
        '/plugins/anchoralarm/setRadius',
        body: body,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _refreshState();
        return true;
      } else {
        if (kDebugMode) {
          print('Set radius failed: ${response.statusCode} - ${response.body}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Set radius error: $e');
      }
      return false;
    }
  }

  /// Set rode length and calculate radius
  Future<bool> setRodeLength(double length, {double? depth}) async {
    try {
      final bodyMap = <String, dynamic>{'length': length};
      if (depth != null) {
        bodyMap['depth'] = depth;
      }

      final response = await _signalKService.postPluginApi(
        '/plugins/anchoralarm/setRodeLength',
        body: bodyMap,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _refreshState();
        return true;
      } else {
        if (kDebugMode) {
          print('Set rode length failed: ${response.statusCode} - ${response.body}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Set rode length error: $e');
      }
      return false;
    }
  }

  /// Set anchor position via the plugin API
  /// Used to correct anchor position based on user-provided bearing
  Future<bool> setAnchorPosition(double latitude, double longitude) async {
    try {
      final response = await _signalKService.postPluginApi(
        '/plugins/anchoralarm/setAnchorPosition',
        body: {
          'position': {'latitude': latitude, 'longitude': longitude},
        },
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _refreshState();
        return true;
      }
      if (kDebugMode) {
        print('Set anchor position failed: ${response.statusCode}');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Set anchor position error: $e');
      }
      return false;
    }
  }

  /// Calculate anchor position from vessel position, bearing, and distance
  /// Uses the haversine formula to calculate destination point
  static (double lat, double lon) calculateAnchorPosition({
    required double vesselLat,
    required double vesselLon,
    required double bearingDegrees,
    required double distanceMeters,
  }) {
    const earthRadius = 6371000.0;

    final lat1 = vesselLat * math.pi / 180;
    final lon1 = vesselLon * math.pi / 180;
    final bearing = bearingDegrees * math.pi / 180;
    final angularDist = distanceMeters / earthRadius;

    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angularDist) +
      math.cos(lat1) * math.sin(angularDist) * math.cos(bearing)
    );

    final lon2 = lon1 + math.atan2(
      math.sin(bearing) * math.sin(angularDist) * math.cos(lat1),
      math.cos(angularDist) - math.sin(lat1) * math.sin(lat2)
    );

    return (lat2 * 180 / math.pi, lon2 * 180 / math.pi);
  }

  /// Get track history from plugin
  Future<void> fetchTrackHistory() async {
    try {
      final response = await _signalKService.getPluginApi(
        '/plugins/anchoralarm/getTrack',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          _trackHistory = data.map((point) {
            if (point is Map<String, dynamic>) {
              // Plugin format: { position: { latitude, longitude }, time }
              final position = point['position'];
              if (position is Map) {
                final lat = position['latitude'];
                final lon = position['longitude'];
                // Skip points with null coordinates
                if (lat == null || lon == null) return null;
                if (lat is! num || lon is! num) return null;

                // Time is in milliseconds since epoch
                final time = point['time'];
                DateTime timestamp;
                if (time is num) {
                  timestamp = DateTime.fromMillisecondsSinceEpoch(time.toInt());
                } else {
                  timestamp = DateTime.now();
                }

                return TrackPoint(
                  latitude: lat.toDouble(),
                  longitude: lon.toDouble(),
                  timestamp: timestamp,
                );
              }
            }
            return null;
          }).whereType<TrackPoint>().toList();
          notifyListeners();
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Fetch track error: $e');
      }
    }
  }

  // === SignalK Updates ===

  void _onSignalKUpdate() {
    final isConnected = _signalKService.isConnected;

    // Handle connection state change
    if (isConnected != _wasConnected) {
      _wasConnected = isConnected;
      if (isConnected) {
        _refreshState();
        fetchTrackHistory();
      }
    }

    // Update state from cached SignalK values
    _updateStateFromSignalK();
  }

  Future<void> _refreshState() async {
    _updateStateFromSignalK();
    await fetchTrackHistory();
  }

  void _updateStateFromSignalK() {
    // Get anchor position
    AnchorPosition? anchorPos;
    final anchorPosData = _signalKService.getValue(_paths.anchorPosition);
    if (anchorPosData?.value is Map) {
      try {
        anchorPos = AnchorPosition.fromSignalK(
          anchorPosData!.value as Map<String, dynamic>,
        );
      } catch (e) {
        // Ignore parse errors
      }
    }

    // Get vessel position
    AnchorPosition? vesselPos;
    final vesselPosData = _signalKService.getValue(_paths.vesselPosition);
    if (vesselPosData?.value is Map) {
      final posMap = vesselPosData!.value as Map;
      final lat = posMap['latitude'];
      final lon = posMap['longitude'];
      if (lat is num && lon is num) {
        vesselPos = AnchorPosition(
          latitude: lat.toDouble(),
          longitude: lon.toDouble(),
        );
      }
    }

    // Get vessel heading - use raw SI value (radians)
    double? vesselHeading;
    var headingRaw = ConversionUtils.getRawValue(_signalKService, _paths.heading);
    if (headingRaw == null) {
      // Fallback to magnetic if true heading not available
      headingRaw = ConversionUtils.getRawValue(_signalKService, 'navigation.headingMagnetic');
    }
    if (headingRaw != null) {
      // Convert radians to degrees using user preferences
      vesselHeading = ConversionUtils.convertWeatherValue(
        _signalKService,
        WeatherFieldType.angle,
        headingRaw,
      ) ?? headingRaw * 180 / math.pi;
    }

    // Get GPS distance from bow (vessel design data) - use raw SI value
    _gpsFromBow = ConversionUtils.getRawValue(_signalKService, _paths.gpsFromBow);

    // Get current depth from sensor - use raw SI value
    _currentDepth = ConversionUtils.getRawValue(_signalKService, _paths.depth);

    // Get fudge factor (margin) from plugin - use raw SI value
    _fudgeFactor = ConversionUtils.getRawValue(_signalKService, _paths.fudgeFactor);

    // Get vessel LOA from design.length.overall
    final lengthData = _signalKService.getValue(_paths.vesselLength);
    if (lengthData?.value is Map) {
      final overall = (lengthData!.value as Map)['overall'];
      _vesselLOA = overall is num ? overall.toDouble() : null;
    } else {
      _vesselLOA = null;
    }

    // Get other values - use raw SI values via ConversionUtils
    final maxRadius = ConversionUtils.getRawValue(_signalKService, _paths.maxRadius);
    final currentRadius = ConversionUtils.getRawValue(_signalKService, _paths.currentRadius);
    final rodeLength = ConversionUtils.getRawValue(_signalKService, _paths.rodeLength);
    final distanceFromBow = ConversionUtils.getRawValue(_signalKService, 'navigation.anchor.distanceFromBow');
    final bearingTrue = ConversionUtils.getRawValue(_signalKService, _paths.bearing);

    // Get notification/alarm state
    AnchorAlarmState alarmState = AnchorAlarmState.normal;
    String? alarmMessage;

    // Check for notification in recent notifications
    final recentNotifications = _signalKService.getRecentNotifications();
    final notification = recentNotifications.where(
      (n) => n.key == _anchorNotificationKey || n.key.startsWith('$_anchorNotificationKey.'),
    ).lastOrNull;
    if (notification != null) {
      alarmState = AnchorAlarmState.fromString(notification.state);
      alarmMessage = notification.message;
    }

    // Determine if active (anchor position exists)
    final isActive = anchorPos != null;

    final previousState = _state;
    _state = AnchorState(
      isActive: isActive,
      anchorPosition: anchorPos,
      maxRadius: maxRadius,
      currentRadius: currentRadius,
      rodeLength: rodeLength,
      distanceFromBow: distanceFromBow,
      bearingTrue: bearingTrue,
      alarmState: alarmState,
      alarmMessage: alarmMessage,
      vesselPosition: vesselPos,
      vesselHeading: vesselHeading,
    );

    // Check for alarm state change
    if (previousState.alarmState != alarmState) {
      _handleAlarmStateChange(previousState.alarmState, alarmState, alarmMessage);
    }

    notifyListeners();
  }

  // === Alarm Handling ===

  void _handleAlarmStateChange(
    AnchorAlarmState previousState,
    AnchorAlarmState newState,
    String? message,
  ) {
    if (newState.isAlarming && !previousState.isAlarming) {
      // Alarm triggered
      _triggerAlerts(newState, message ?? 'Anchor Alarm!');
    } else if (!newState.isAlarming && previousState.isAlarming) {
      // Alarm cleared
      _stopAlarmSound();
    }
  }

  Future<void> _triggerAlerts(AnchorAlarmState state, String message) async {
    // Play alarm sound
    await _playAlarmSound();

    // Show system notification
    await _notificationService.showAlarmNotification(
      title: 'Anchor Alarm',
      body: message,
    );

    // Send crew alert
    _messagingService?.sendAlert('ANCHOR ALARM: $message');
  }

  Future<void> _playAlarmSound() async {
    if (_alarmSoundPlaying) return;

    final assetPath = alarmSounds[_alarmSound] ?? alarmSounds['foghorn']!;

    try {
      _alarmPlayer?.dispose();
      _alarmPlayer = AudioPlayer();
      await _alarmPlayer!.setVolume(1.0);
      await _alarmPlayer!.play(AssetSource(assetPath));
      _alarmSoundPlaying = true;

      // Repeat every 5 seconds while alarm is active
      _alarmRepeatTimer?.cancel();
      _alarmRepeatTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        if (_state.alarmState.isAlarming) {
          _alarmPlayer?.dispose();
          _alarmPlayer = AudioPlayer();
          await _alarmPlayer!.play(AssetSource(assetPath));
        } else {
          _alarmRepeatTimer?.cancel();
          _alarmSoundPlaying = false;
        }
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error playing alarm sound: $e');
      }
    }
  }

  Future<void> _stopAlarmSound() async {
    _alarmRepeatTimer?.cancel();
    _alarmPlayer?.stop();
    _alarmPlayer?.dispose();
    _alarmPlayer = null;
    _alarmSoundPlaying = false;
  }

  /// Manually trigger alarm for check-in failure
  Future<void> triggerCheckInAlarm() async {
    await _triggerAlerts(
      AnchorAlarmState.alarm,
      'Check-in missed! Please confirm anchor watch.',
    );
  }

  // === Check-In System ===

  void _startCheckInTimer() {
    _checkInTimer?.cancel();
    _checkInGraceTimer?.cancel();
    _awaitingCheckIn = false;
    _checkInDeadline = null;

    if (!_checkInConfig.enabled || !_state.isActive) return;

    _checkInTimer = Timer(_checkInConfig.interval, _onCheckInRequired);
  }

  void _stopCheckInTimer() {
    _checkInTimer?.cancel();
    _checkInGraceTimer?.cancel();
    _checkInTimer = null;
    _checkInGraceTimer = null;
    _awaitingCheckIn = false;
    _checkInDeadline = null;
    notifyListeners();
  }

  void _onCheckInRequired() {
    _awaitingCheckIn = true;
    _checkInDeadline = DateTime.now().add(_checkInConfig.gracePeriod);
    notifyListeners();

    // Show notification requesting check-in
    _notificationService.showAlarmNotification(
      title: 'Anchor Watch Check-In',
      body: _checkInConfig.customMessage ?? 'Please confirm you are monitoring the anchor.',
    );

    // Start grace period timer
    _checkInGraceTimer = Timer(_checkInConfig.gracePeriod, _onCheckInGraceExpired);
  }

  void _onCheckInGraceExpired() {
    if (_awaitingCheckIn) {
      // Check-in was not acknowledged - escalate to alarm
      triggerCheckInAlarm();
    }
  }

  /// Acknowledge check-in
  void acknowledgeCheckIn() {
    _checkInGraceTimer?.cancel();
    _awaitingCheckIn = false;
    _checkInDeadline = null;

    // Restart check-in timer for next interval
    _startCheckInTimer();

    notifyListeners();
  }

  /// Acknowledge and silence alarm
  void acknowledgeAlarm() {
    _stopAlarmSound();
    // Note: This only stops the local sound, the SignalK alarm state
    // will remain until the vessel returns to safe zone
  }
}
