import 'dart:async';
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../models/intercom_channel.dart';
import 'signalk_service.dart';
import 'storage_service.dart';
import 'crew_service.dart';
import 'notification_service.dart';

/// One WebRTC connection to a single remote peer. Unifies what used to be
/// spread across `_peerConnection` + `_peerConnections` + `_remoteStreams` +
/// `_audioRenderers` + a channel-wide pending-candidate list, so every
/// offer/answer/ICE/teardown routes through one record keyed by peer id.
class _PeerSession {
  final String peerId;
  // Distinguishes a 1:1 direct call from a channel-mesh session. Both can exist
  // for the SAME peer at once, so the map key is scoped by this (see
  // `_sessionKey`) to stop one from tearing down the other.
  final bool direct;
  final RTCPeerConnection pc;
  RTCVideoRenderer? renderer;
  MediaStream? remoteStream;
  final List<RTCIceCandidate> pendingCandidates = [];
  bool remoteDescSet = false;
  String? sessionId;
  bool isOfferer;
  bool restartAttempted = false;
  Timer? disconnectTimer;

  _PeerSession({
    required this.peerId,
    required this.pc,
    required this.sessionId,
    required this.isOfferer,
    this.direct = false,
  });
}

/// Service for voice intercom using WebRTC
class IntercomService extends ChangeNotifier {
  final SignalKService _signalKService;
  final StorageService _storageService;
  final CrewService _crewService;

  // Channels
  final List<IntercomChannel> _channels = [];
  List<IntercomChannel> get channels => List.unmodifiable(_channels);

  // Current state
  IntercomChannel? _currentChannel;
  IntercomChannel? get currentChannel => _currentChannel;

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  bool _isPTTActive = false;
  bool get isPTTActive => _isPTTActive;

  bool _isListening = false;
  bool get isListening => _isListening;

  // Intercom mode (PTT vs Duplex)
  IntercomMode _mode = IntercomMode.ptt;
  IntercomMode get mode => _mode;
  bool get isDuplexMode => _mode == IntercomMode.duplex;

  // Who is currently transmitting (supports multiple transmitters)
  final Map<String, String> _activeTransmitters = {}; // id -> name
  Map<String, String> get activeTransmitters => Map.unmodifiable(_activeTransmitters);
  bool get hasActiveTransmitters => _activeTransmitters.isNotEmpty;

  // Legacy single transmitter getters (for backwards compatibility)
  String? get currentTransmitterId => _activeTransmitters.keys.firstOrNull;
  String? get currentTransmitterName => _activeTransmitters.values.firstOrNull;

  // WebRTC — one _PeerSession per remote peer, keyed by scope + peer id (so a
  // channel-mesh session and a direct call with the same peer don't collide).
  MediaStream? _localStream;
  final Map<String, _PeerSession> _sessions = {};

  /// Map key for a peer session. Channel-mesh sessions key on the bare peerId;
  /// direct (1:1) calls are scoped under `direct:` so the two can coexist.
  String _sessionKey(String peerId, {required bool direct}) =>
      direct ? 'direct:$peerId' : peerId;
  MediaStream? get remoteStream =>
      _sessions.values.map((s) => s.remoteStream).firstWhere(
            (s) => s != null,
            orElse: () => null,
          );

  // Disposed guard — block notifyListeners() after dispose (async onTrack etc.).
  bool _disposed = false;

  // Channel membership for multi-peer mesh PTT: channelId -> set of peer ids
  // currently present (learned from join/leave/pttStart signaling).
  final Map<String, Set<String>> _channelMembers = {};

  // Outbound signaling queued while disconnected (flushed on reconnect).
  // Bounded; SDP is intentionally not replayed (stale), but pttEnd/hangup/
  // channelLeave are worth delivering.
  final List<Map<String, dynamic>> _pendingSignaling = [];
  static const int _pendingSignalingMax = 20;

  // Resources API configuration - uses custom resource type for isolation
  static const String _channelResourceType = 'zeddisplay-channels';

  // Periodic timer for channel sync (RTC signaling now uses WebSocket deltas)
  Timer? _pollTimer;

  // Track connection state
  bool _wasConnected = false;
  bool _initialized = false;
  bool get initialized => _initialized;

  // Microphone permission
  bool _hasMicPermission = false;
  bool get hasMicPermission => _hasMicPermission;

  // Storage keys
  static const String _channelsStorageKey = 'intercom_channels_cache';
  static const String _lastChannelKey = 'intercom_last_channel';

  // Channel subscriptions: userId → Set of channelIds
  final Map<String, Set<String>> _userSubscriptions = {};

  // Emergency channel ID (always subscribed)
  static const String emergencyChannelId = 'ch16';

  // Session tracking
  String? _currentSessionId;
  final Set<String> _processedSignalingIds = {};
  final Set<String> _answeredSessions = {}; // Track sessions we've already answered

  IntercomService(this._signalKService, this._storageService, this._crewService);

  /// Initialize the intercom service
  Future<void> initialize() async {
    // Load cached channels
    await _loadCachedChannels();

    // Check microphone permission
    await _checkMicPermission();

    // Register connection callback for sequential execution (prevents HTTP overload)
    _signalKService.registerConnectionCallback(_onConnected);

    // Listen to SignalK connection changes for disconnection handling
    _signalKService.addListener(_onSignalKChanged);

    // Register for real-time RTC signaling via WebSocket
    _signalKService.registerRtcDeltaCallback(_handleRtcDelta);

    // If already connected, start
    if (_signalKService.isConnected) {
      await _onConnected();
    }

    _initialized = true;
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _signalKService.unregisterConnectionCallback(_onConnected);
    _signalKService.removeListener(_onSignalKChanged);
    _signalKService.unregisterRtcDeltaCallback();
    // Fire-and-forget teardown: dispose() is sync, but swallow any async
    // platform WebRTC close errors so they don't surface unhandled.
    unawaited(_teardownAll().catchError((Object e) {
      if (kDebugMode) print('Intercom teardown error: $e');
    }));
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Apply the current mute state to a freshly-acquired local stream.
  void _applyMuteState(MediaStream stream) {
    for (final track in stream.getAudioTracks()) {
      track.enabled = !_isMuted;
    }
  }

  /// Create a peer connection to [peerId] and register it as a session.
  /// LAN-only: no STUN/TURN. Wires ICE/track/connection-state handlers and
  /// adds local audio (mute reapplied). Replaces any existing session.
  Future<_PeerSession> _createSession(
    String peerId, {
    required String? sessionId,
    required bool isOfferer,
    bool direct = false,
  }) async {
    final key = _sessionKey(peerId, direct: direct);
    await _teardownSession(peerId, direct: direct, notify: false);

    final pc = await createPeerConnection({
      'iceServers': const [],
      'sdpSemantics': 'unified-plan',
    });
    final session = _PeerSession(
        peerId: peerId,
        pc: pc,
        sessionId: sessionId,
        isOfferer: isOfferer,
        direct: direct);
    _sessions[key] = session;

    final local = _localStream;
    if (local != null) {
      _applyMuteState(local);
      for (final track in local.getTracks()) {
        await pc.addTrack(track, local);
      }
    }

    pc.onTrack = (RTCTrackEvent event) async {
      if (event.streams.isEmpty) return;
      final stream = event.streams[0];
      session.remoteStream = stream;
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      renderer.srcObject = stream;
      // Session may have been torn down during the await.
      if (_disposed || _sessions[key] != session) {
        await renderer.dispose();
        return;
      }
      session.renderer = renderer;
      _safeNotify();
    };

    // Capture the session instance (not just peerId) so a late callback from a
    // replaced RTCPeerConnection can be recognized as stale and ignored.
    pc.onConnectionState =
        (RTCPeerConnectionState state) => _onPeerConnectionState(session, state);
    pc.onIceConnectionState = (RTCIceConnectionState state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _onPeerConnectionState(
            session, RTCPeerConnectionState.RTCPeerConnectionStateFailed);
      }
    };

    return session;
  }

  /// Add an ICE candidate now if the remote description is set, else buffer it
  /// (candidates routinely arrive before the offer/answer is applied).
  Future<void> _addOrBufferCandidate(_PeerSession s, RTCIceCandidate c) async {
    if (s.remoteDescSet) {
      try {
        await s.pc.addCandidate(c);
      } catch (e) {
        if (kDebugMode) print('addCandidate failed for ${s.peerId}: $e');
      }
    } else {
      s.pendingCandidates.add(c);
    }
  }

  /// Mark the remote description set and drain buffered candidates.
  Future<void> _flushPendingCandidates(_PeerSession s) async {
    s.remoteDescSet = true;
    final pending = List<RTCIceCandidate>.from(s.pendingCandidates);
    s.pendingCandidates.clear();
    for (final c in pending) {
      try {
        await s.pc.addCandidate(c);
      } catch (e) {
        if (kDebugMode) print('flush addCandidate failed for ${s.peerId}: $e');
      }
    }
  }

  /// Detect dead/recovering peers: clean up failed/closed, give a disconnect a
  /// short grace then one ICE-restart (offerer) or teardown.
  void _onPeerConnectionState(_PeerSession s, RTCPeerConnectionState state) {
    final key = _sessionKey(s.peerId, direct: s.direct);
    // Ignore callbacks from a peer connection that's already been replaced.
    if (_sessions[key] != s) return;
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        s.disconnectTimer?.cancel();
        s.disconnectTimer = null;
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        s.disconnectTimer?.cancel();
        s.disconnectTimer = Timer(const Duration(seconds: 5), () async {
          if (_sessions[key] != s) return;
          if (s.isOfferer && !s.restartAttempted) {
            s.restartAttempted = true;
            await _restartIce(s);
          } else {
            await _teardownSession(s.peerId, direct: s.direct);
          }
        });
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        _teardownSession(s.peerId, direct: s.direct);
        break;
      default:
        break;
    }
  }

  /// Single ICE-restart attempt — re-offer to the peer.
  Future<void> _restartIce(_PeerSession s) async {
    final profile = _crewService.localProfile;
    if (profile == null || _currentChannel == null) {
      await _teardownSession(s.peerId, direct: s.direct);
      return;
    }
    try {
      final offer = await s.pc.createOffer({'iceRestart': true});
      await s.pc.setLocalDescription(offer);
      s.remoteDescSet = false;
      _sendSignalingMessage(SignalingMessage(
        id: const Uuid().v4(),
        sessionId: s.sessionId ?? '',
        channelId: _currentChannel!.id,
        fromId: profile.id,
        fromName: profile.name,
        type: SignalingType.offer,
        data: {'sdp': offer.sdp, 'type': offer.type, 'targetId': s.peerId},
      ));
    } catch (e) {
      if (kDebugMode) print('ICE restart failed for ${s.peerId}: $e');
      await _teardownSession(s.peerId, direct: s.direct);
    }
  }

  /// Tear down and remove a single peer session.
  Future<void> _teardownSession(String peerId,
      {bool direct = false, bool notify = true}) async {
    final s = _sessions.remove(_sessionKey(peerId, direct: direct));
    if (s == null) return;
    s.disconnectTimer?.cancel();
    _activeTransmitters.remove(peerId);
    try {
      await s.pc.close();
    } catch (_) {}
    await s.renderer?.dispose();
    await s.remoteStream?.dispose();
    if (notify) _safeNotify();
  }

  /// Tear down every peer session and the local mic stream.
  Future<void> _teardownAll() async {
    for (final s in _sessions.values.toList()) {
      await _teardownSession(s.peerId, direct: s.direct, notify: false);
    }
    _sessions.clear();
    _activeTransmitters.clear();
    _answeredSessions.clear();
    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    _localStream = null;
    _safeNotify();
  }

  /// Check and request microphone permission
  Future<bool> _checkMicPermission() async {
    // Permission handler doesn't support Linux, so assume permission is granted
    if (defaultTargetPlatform == TargetPlatform.linux) {
      _hasMicPermission = true;
      return true;
    }
    
    final status = await Permission.microphone.status;
    _hasMicPermission = status.isGranted;
    return _hasMicPermission;
  }

  /// Request microphone permission
  Future<bool> requestMicPermission() async {
    // Permission handler doesn't support Linux, so assume permission is granted
    if (defaultTargetPlatform == TargetPlatform.linux) {
      _hasMicPermission = true;
      return true;
    }
    
    try {
      final status = await Permission.microphone.request();
      _hasMicPermission = status.isGranted;

      if (kDebugMode) {
        print('Microphone permission status: $status');
        print('isGranted: ${status.isGranted}');
        print('isDenied: ${status.isDenied}');
        print('isPermanentlyDenied: ${status.isPermanentlyDenied}');
      }

      // If permanently denied, open app settings
      if (status.isPermanentlyDenied) {
        if (kDebugMode) {
          print('Permission permanently denied, opening settings...');
        }
        await openAppSettings();
      }

      // Mic just granted (first run) — line up Bluetooth routing now too.
      await _ensureBluetoothPermission();

      notifyListeners();
      return _hasMicPermission;
    } catch (e) {
      if (kDebugMode) {
        print('Error requesting microphone permission: $e');
      }
      return false;
    }
  }

  // Bluetooth permission is requested at most once per session.
  bool _btPermissionRequested = false;

  /// Android 12+ requires BLUETOOTH_CONNECT at runtime before flutter_webrtc
  /// can enumerate/route to a Bluetooth headset. Requested independently of the
  /// mic permission — which may already be granted from a prior run, in which
  /// case requestMicPermission() never runs and the BT request would be missed.
  /// Best-effort and non-blocking: a denial just falls back to speaker/earpiece.
  Future<void> _ensureBluetoothPermission() async {
    if (_btPermissionRequested) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _btPermissionRequested = true;
    try {
      // BLUETOOTH_CONNECT is a runtime permission only on Android 12 (API 31)+.
      // On Android 11 and below the legacy BLUETOOTH permission applies (normal
      // install-time perm), so requesting bluetoothConnect there is a no-op at
      // best — pick the permission that matches the device's API level.
      final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      final permission =
          sdkInt >= 31 ? Permission.bluetoothConnect : Permission.bluetooth;
      final btStatus = await permission.request();
      if (kDebugMode) {
        print('Bluetooth permission status (sdk $sdkInt): $btStatus');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error requesting bluetooth permission: $e');
      }
    }
  }

  /// Load cached channels from storage
  Future<void> _loadCachedChannels() async {
    final cachedJson = _storageService.getSetting(_channelsStorageKey);
    if (cachedJson != null) {
      try {
        final List<dynamic> channelList = jsonDecode(cachedJson);
        _channels.clear();
        for (final chJson in channelList) {
          try {
            final channel = IntercomChannel.fromJson(chJson as Map<String, dynamic>);
            _channels.add(channel);
          } catch (e) {
            // Skip invalid entries
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error loading cached channels: $e');
        }
      }
    }

    // Add default channels if none exist
    if (_channels.isEmpty) {
      _channels.addAll(IntercomChannel.defaultChannels);
      await _saveCachedChannels();
    }

    _channels.sort((a, b) => a.priority.compareTo(b.priority));

    // Restore last selected channel
    final lastChannelId = _storageService.getSetting(_lastChannelKey);
    if (lastChannelId != null) {
      _currentChannel = _channels.firstWhere(
        (c) => c.id == lastChannelId,
        orElse: () => _channels.first,
      );
    }
  }

  /// Save channels to local storage
  Future<void> _saveCachedChannels() async {
    final channelList = _channels.map((c) => c.toJson()).toList();
    await _storageService.saveSetting(_channelsStorageKey, jsonEncode(channelList));
  }

  /// Handle SignalK connection changes (only for disconnection)
  /// Connection is handled via registerConnectionCallback for sequential execution
  void _onSignalKChanged() {
    final isConnected = _signalKService.isConnected;
    if (isConnected == _wasConnected) return;
    _wasConnected = isConnected;

    // Only handle disconnection here - connection is handled via callback
    if (!isConnected) {
      _onDisconnected();
    }
  }

  Future<void> _onConnected() async {
    // Flush queued control signaling (pttEnd/hangup/channelLeave) first.
    if (_pendingSignaling.isNotEmpty) {
      final pending = List<Map<String, dynamic>>.from(_pendingSignaling);
      _pendingSignaling.clear();
      final nowIso = DateTime.now().toUtc().toIso8601String();
      for (final m in pending) {
        // Refresh the timestamp before replaying: receivers drop messages
        // older than 30s, so control messages (pttEnd/hangup/channelLeave)
        // queued during a long disconnect would otherwise be silently ignored,
        // leaving peers with stuck transmitter/call state.
        final json = Map<String, dynamic>.from(m['json'] as Map<String, dynamic>);
        json['timestamp'] = nowIso;
        _signalKService.sendRtcSignaling(m['id'] as String, json);
      }
    }
    await _ensureResourceType();
    _startPolling();
    await _syncChannels();
  }

  /// Ensure the custom resource type exists on the server
  Future<void> _ensureResourceType() async {
    await _signalKService.ensureResourceTypeExists(
      _channelResourceType,
      description: 'ZedDisplay intercom channels',
    );
  }

  void _onDisconnected() {
    _pollTimer?.cancel();
    _pollTimer = null;
    // Tear down all peer connections and reset active-call state. Keep
    // _currentChannel/_isListening so the user stays "on" the channel and
    // sessions rebuild from fresh offers after reconnect. Don't send here —
    // the socket is down (control messages were queued in _sendSignalingMessage).
    _teardownAll();
    _isPTTActive = false;
    _isInDirectCall = false;
    _directCallTargetId = null;
    _directCallTargetName = null;
    _currentSessionId = null;
    _channelMembers.clear();
    _safeNotify();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    // Polling now only used for channel sync, not RTC signaling (which uses WebSocket)
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _syncChannels();
    });
  }

  /// Handle incoming RTC signaling delta from WebSocket (real-time)
  void _handleRtcDelta(String path, dynamic value) {
    if (value == null || value is! Map<String, dynamic>) return;

    final myId = _crewService.localProfile?.id;
    if (myId == null) return;

    try {
      // Parse the signaling message from the delta value
      final message = SignalingMessage.fromJson(value.cast<String, dynamic>());

      // Skip messages from self
      if (message.fromId == myId) return;

      // Only process recent messages (last 30 seconds)
      if (DateTime.now().difference(message.timestamp).inSeconds > 30) return;

      if (kDebugMode) {
        print('RTC delta: ${message.type} from ${message.fromName} on ${message.channelId}');
      }

      // Route to appropriate handler
      if (message.channelId.startsWith('direct_')) {
        _handleDirectCallMessageFromDelta(message, myId);
      } else {
        // For channel messages, check if we should show a notification
        if (message.type == SignalingType.pttStart) {
          _handleChannelActivityNotification(message);
        }

        // Only process signaling for our current channel
        if (_currentChannel != null && message.channelId == _currentChannel!.id) {
          _handleSignalingMessage(message);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling RTC delta: $e');
      }
    }
  }

  /// Show notification for channel activity if we're not actively on that channel
  void _handleChannelActivityNotification(SignalingMessage message) {
    // Don't notify if we're already on this channel and transmitting/listening
    final isOnChannel = _currentChannel?.id == message.channelId;
    final isActiveOnChannel = isOnChannel && (_isPTTActive || _isListening);

    if (isActiveOnChannel) {
      if (kDebugMode) {
        print('Skipping notification - already active on channel ${message.channelId}');
      }
      return;
    }

    // Find the channel to get its name and emergency status
    final channel = _channels.firstWhere(
      (c) => c.id == message.channelId,
      orElse: () => IntercomChannel(id: message.channelId, name: message.channelId),
    );

    // Show notification
    NotificationService().showIntercomNotification(
      channelId: message.channelId,
      channelName: channel.name,
      transmitterName: message.fromName,
      isEmergency: channel.isEmergency,
    );

    if (kDebugMode) {
      print('Showed intercom notification: ${message.fromName} on ${channel.name}');
    }
  }

  /// Handle direct call message from WebSocket delta
  Future<void> _handleDirectCallMessageFromDelta(SignalingMessage message, String myId) async {
    final targetId = message.channelId.replaceFirst('direct_', '');

    // Check if this is targeted at us
    final dataTargetId = message.data?['targetId'] as String?;
    final isForUs = targetId == myId || dataTargetId == myId;

    // Also check if it's from our direct call target (for answers/ICE)
    final isFromOurTarget = _isInDirectCall && message.fromId == _directCallTargetId;

    if (kDebugMode) {
      print('Direct call routing: targetId=$targetId, myId=$myId, dataTargetId=$dataTargetId');
      print('  isForUs=$isForUs, isFromOurTarget=$isFromOurTarget, isInDirectCall=$_isInDirectCall');
    }

    if (isForUs || isFromOurTarget) {
      await _handleDirectCallMessage(message);
    } else if (kDebugMode) {
      print('  SKIPPED - not for us');
    }
  }

  /// Select a channel to listen to
  Future<void> selectChannel(IntercomChannel channel) async {
    // If same channel selected, treat as "rejoin" to restart transmission in duplex mode
    final isSameChannel = _currentChannel?.id == channel.id;

    // Leave current channel first (unless same channel)
    if (_currentChannel != null && !isSameChannel) {
      await _leaveChannel();
    }

    _currentChannel = channel;
    await _storageService.saveSetting(_lastChannelKey, channel.id);
    notifyListeners();

    // Join the channel (or rejoin if same channel)
    await _joinChannel(channel);
  }

  /// Join a channel
  Future<void> _joinChannel(IntercomChannel channel) async {
    final profile = _crewService.localProfile;
    if (profile == null) return;

    // Send join message
    final message = SignalingMessage(
      id: const Uuid().v4(),
      sessionId: '',
      channelId: channel.id,
      fromId: profile.id,
      fromName: profile.name,
      type: SignalingType.channelJoin,
    );

    _sendSignalingMessage(message);

    _isListening = true;
    notifyListeners();

    if (kDebugMode) {
      print('Joined channel: ${channel.name}');
    }

    // If in duplex mode, start transmitting immediately
    if (_mode == IntercomMode.duplex) {
      await _startDuplexTransmission();
    }
  }

  /// Leave current channel
  Future<void> _leaveChannel() async {
    if (_currentChannel == null) return;

    final profile = _crewService.localProfile;
    if (profile == null) return;

    // Stop any active transmission
    if (_isPTTActive) {
      await stopPTT();
    }

    // Send leave message
    final message = SignalingMessage(
      id: const Uuid().v4(),
      sessionId: '',
      channelId: _currentChannel!.id,
      fromId: profile.id,
      fromName: profile.name,
      type: SignalingType.channelLeave,
    );

    _sendSignalingMessage(message);

    // Tear down channel peer sessions; direct calls live under a separate
    // scope and are left untouched.
    for (final s in _sessions.values.toList()) {
      if (s.direct) continue;
      await _teardownSession(s.peerId, notify: false);
    }
    _channelMembers.remove(_currentChannel!.id);

    _isListening = false;
    _currentChannel = null;
    notifyListeners();
  }

  /// Start push-to-talk transmission
  Future<bool> startPTT() async {
    if (_currentChannel == null) return false;
    if (_isPTTActive) return true;
    if (!_hasMicPermission) {
      final granted = await requestMicPermission();
      if (!granted) return false;
    }
    // Ensure BT routing even when mic was already granted (so requestMicPermission
    // — and the BT request it makes — was skipped). One-shot, non-blocking.
    await _ensureBluetoothPermission();

    final profile = _crewService.localProfile;
    if (profile == null) return false;

    try {
      // Get microphone stream
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });

      // Create new session
      _currentSessionId = const Uuid().v4();

      // Send PTT start message
      final message = SignalingMessage(
        id: const Uuid().v4(),
        sessionId: _currentSessionId!,
        channelId: _currentChannel!.id,
        fromId: profile.id,
        fromName: profile.name,
        type: SignalingType.pttStart,
      );

      _sendSignalingMessage(message);

      _isPTTActive = true;
      // Add self to active transmitters
      _activeTransmitters[profile.id] = profile.name;
      notifyListeners();

      // Open a peer connection + offer to every listener on the channel.
      await _startBroadcast();

      if (kDebugMode) {
        print('PTT started on channel: ${_currentChannel!.name}');
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error starting PTT: $e');
      }
      return false;
    }
  }

  /// Stop push-to-talk transmission
  Future<void> stopPTT() async {
    if (!_isPTTActive) return;

    final profile = _crewService.localProfile;
    if (profile == null) return;

    try {
      // Send PTT end message
      if (_currentChannel != null && _currentSessionId != null) {
        final message = SignalingMessage(
          id: const Uuid().v4(),
          sessionId: _currentSessionId!,
          channelId: _currentChannel!.id,
          fromId: profile.id,
          fromName: profile.name,
          type: SignalingType.pttEnd,
        );

        _sendSignalingMessage(message);
      }

      // Stop local stream
      _localStream?.getTracks().forEach((track) {
        track.stop();
      });
      await _localStream?.dispose();
      _localStream = null;

      // Tear down the broadcast (offerer) channel sessions; direct calls live
      // under a separate scope and are left untouched.
      for (final s in _sessions.values.toList()) {
        if (s.direct || !s.isOfferer) continue;
        await _teardownSession(s.peerId, notify: false);
      }

      _isPTTActive = false;
      // Remove self from active transmitters
      _activeTransmitters.remove(profile.id);
      _currentSessionId = null;
      notifyListeners();

      if (kDebugMode) {
        print('PTT stopped');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error stopping PTT: $e');
      }
    }
  }

  // Direct call state
  String? _directCallTargetId;
  String? _directCallTargetName;
  bool _isInDirectCall = false;
  String? get directCallTargetId => _directCallTargetId;
  String? get directCallTargetName => _directCallTargetName;
  bool get isInDirectCall => _isInDirectCall;

  // Incoming call state
  String? _incomingCallFromId;
  String? _incomingCallFromName;
  String? _incomingCallSessionId;
  SignalingMessage? _pendingIncomingOffer;
  bool get hasIncomingCall => _incomingCallFromId != null;
  String? get incomingCallFromId => _incomingCallFromId;
  String? get incomingCallFromName => _incomingCallFromName;

  // ICE candidates for an incoming direct call that arrive before the user
  // answers (no session exists yet); drained into the session on answer.
  final List<RTCIceCandidate> _incomingIce = [];

  /// Start a direct call to a specific crew member
  Future<bool> startDirectCall(String targetId, String targetName) async {
    if (_isInDirectCall) return false;
    if (!_hasMicPermission) {
      final granted = await requestMicPermission();
      if (!granted) return false;
    }
    // Ensure BT routing even when mic was already granted (so requestMicPermission
    // — and the BT request it makes — was skipped). One-shot, non-blocking.
    await _ensureBluetoothPermission();

    final profile = _crewService.localProfile;
    if (profile == null) return false;

    try {
      // Get microphone stream
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });

      // Create new session for direct call
      _currentSessionId = const Uuid().v4();
      _directCallTargetId = targetId;
      _directCallTargetName = targetName;
      _isInDirectCall = true;

      // Create WebRTC offer and send via signaling
      await _createDirectCallOffer(targetId);

      if (kDebugMode) {
        print('Direct call started to: $targetName');
      }

      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error starting direct call: $e');
      }
      _isInDirectCall = false;
      _directCallTargetId = null;
      _directCallTargetName = null;
      return false;
    }
  }

  /// End a direct call
  Future<void> endDirectCall() async {
    if (!_isInDirectCall) return;

    final profile = _crewService.localProfile;
    if (profile != null && _directCallTargetId != null) {
      // Send hangup message
      final message = SignalingMessage(
        id: const Uuid().v4(),
        sessionId: _currentSessionId ?? '',
        channelId: 'direct_$_directCallTargetId',
        fromId: profile.id,
        fromName: profile.name,
        type: SignalingType.hangup,
      );
      _sendSignalingMessage(message);
    }

    // Cleanup
    final targetId = _directCallTargetId;
    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _localStream = null;

    if (targetId != null) {
      await _teardownSession(targetId, direct: true, notify: false);
    }

    _isInDirectCall = false;
    _directCallTargetId = null;
    _directCallTargetName = null;
    _currentSessionId = null;
    notifyListeners();

    if (kDebugMode) {
      print('Direct call ended');
    }
  }

  /// Answer an incoming direct call
  Future<bool> answerIncomingCall() async {
    if (_pendingIncomingOffer == null || _incomingCallFromId == null) return false;
    if (!_hasMicPermission) {
      final granted = await requestMicPermission();
      if (!granted) return false;
    }
    // Ensure BT routing even when mic was already granted (so requestMicPermission
    // — and the BT request it makes — was skipped). One-shot, non-blocking.
    await _ensureBluetoothPermission();

    final profile = _crewService.localProfile;
    if (profile == null) return false;

    try {
      // Get microphone stream
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });

      final callerId = _incomingCallFromId!;
      final callerName = _incomingCallFromName!;
      final offer = _pendingIncomingOffer!;

      _isInDirectCall = true;
      _directCallTargetId = callerId;
      _directCallTargetName = callerName;
      _currentSessionId = offer.sessionId;

      // Clear incoming call state
      _incomingCallFromId = null;
      _incomingCallFromName = null;
      _incomingCallSessionId = null;
      _pendingIncomingOffer = null;

      // Create session for the caller (local audio added by _createSession).
      final session = await _createSession(callerId,
          sessionId: offer.sessionId, isOfferer: false, direct: true);

      session.pc.onIceCandidate = (RTCIceCandidate candidate) {
        _sendSignalingMessage(SignalingMessage(
          id: const Uuid().v4(),
          sessionId: _currentSessionId!,
          channelId: 'direct_${profile.id}',
          fromId: profile.id,
          fromName: profile.name,
          type: SignalingType.iceCandidate,
          data: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
            'targetId': callerId,
          },
        ));
      };

      // Set remote description (the offer), then drain any candidates that
      // arrived before the user answered.
      await session.pc.setRemoteDescription(RTCSessionDescription(
        offer.data!['sdp'] as String,
        offer.data!['type'] as String,
      ));
      await _flushPendingCandidates(session);
      for (final c in _incomingIce) {
        await _addOrBufferCandidate(session, c);
      }
      _incomingIce.clear();

      // Create and send answer
      final answer = await session.pc.createAnswer();
      await session.pc.setLocalDescription(answer);

      _sendSignalingMessage(SignalingMessage(
        id: const Uuid().v4(),
        sessionId: offer.sessionId,
        channelId: 'direct_${profile.id}',
        fromId: profile.id,
        fromName: profile.name,
        type: SignalingType.answer,
        data: {
          'sdp': answer.sdp,
          'type': answer.type,
          'directCall': true,
          'targetId': callerId,
        },
      ));

      if (kDebugMode) {
        print('Answered call from $callerName');
      }

      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error answering call: $e');
      }
      _clearIncomingCall();
      return false;
    }
  }

  /// Decline an incoming direct call
  Future<void> declineIncomingCall() async {
    if (_incomingCallFromId == null) return;

    final profile = _crewService.localProfile;
    if (profile != null) {
      // Send decline/hangup message
      final message = SignalingMessage(
        id: const Uuid().v4(),
        sessionId: _incomingCallSessionId ?? '',
        channelId: 'direct_${profile.id}',
        fromId: profile.id,
        fromName: profile.name,
        type: SignalingType.hangup,
        data: {'declined': true, 'targetId': _incomingCallFromId},
      );
      _sendSignalingMessage(message);
    }

    _clearIncomingCall();

    if (kDebugMode) {
      print('Declined incoming call');
    }
  }

  void _clearIncomingCall() {
    _incomingCallFromId = null;
    _incomingCallFromName = null;
    _incomingCallSessionId = null;
    _pendingIncomingOffer = null;
    _incomingIce.clear();
    notifyListeners();
  }

  /// Create WebRTC offer for direct call
  Future<void> _createDirectCallOffer(String targetId) async {
    final profile = _crewService.localProfile;
    if (profile == null) return;

    try {
      final session = await _createSession(targetId,
          sessionId: _currentSessionId, isOfferer: true, direct: true);

      session.pc.onIceCandidate = (RTCIceCandidate candidate) {
        _sendSignalingMessage(SignalingMessage(
          id: const Uuid().v4(),
          sessionId: _currentSessionId!,
          channelId: 'direct_$targetId',
          fromId: profile.id,
          fromName: profile.name,
          type: SignalingType.iceCandidate,
          data: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
            'targetId': targetId,
          },
        ));
      };

      final offer = await session.pc.createOffer();
      await session.pc.setLocalDescription(offer);

      _sendSignalingMessage(SignalingMessage(
        id: const Uuid().v4(),
        sessionId: _currentSessionId!,
        channelId: 'direct_$targetId',
        fromId: profile.id,
        fromName: profile.name,
        type: SignalingType.offer,
        data: {'sdp': offer.sdp, 'type': offer.type, 'directCall': true},
      ));
    } catch (e) {
      if (kDebugMode) {
        print('Error creating direct call offer: $e');
      }
    }
  }

  /// Toggle mute state
  void toggleMute() {
    _isMuted = !_isMuted;
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !_isMuted;
    });
    notifyListeners();
  }

  /// Set intercom mode (PTT or Duplex)
  Future<void> setMode(IntercomMode newMode) async {
    if (_mode == newMode) return;

    // If switching modes while in a channel, need to handle transition
    final wasInChannel = _currentChannel != null;
    final channel = _currentChannel;

    if (wasInChannel) {
      // Stop current transmission if active
      if (_isPTTActive) {
        await stopPTT();
      }
    }

    _mode = newMode;
    notifyListeners();

    // If in duplex mode and in a channel, start transmitting
    if (wasInChannel && channel != null && newMode == IntercomMode.duplex) {
      await _startDuplexTransmission();
    }
  }

  /// Toggle between PTT and Duplex mode
  Future<void> toggleMode() async {
    await setMode(_mode == IntercomMode.ptt ? IntercomMode.duplex : IntercomMode.ptt);
  }

  /// Start duplex (open channel) transmission
  Future<bool> _startDuplexTransmission() async {
    if (_currentChannel == null) return false;
    if (_isPTTActive) return true;  // Already transmitting
    if (!_hasMicPermission) {
      final granted = await requestMicPermission();
      if (!granted) return false;
    }
    // Ensure BT routing even when mic was already granted (so requestMicPermission
    // — and the BT request it makes — was skipped). One-shot, non-blocking.
    await _ensureBluetoothPermission();

    final profile = _crewService.localProfile;
    if (profile == null) return false;

    try {
      // Get microphone stream
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });

      // Create new session
      _currentSessionId = const Uuid().v4();

      // Send channel join with duplex indicator
      final message = SignalingMessage(
        id: const Uuid().v4(),
        sessionId: _currentSessionId!,
        channelId: _currentChannel!.id,
        fromId: profile.id,
        fromName: profile.name,
        type: SignalingType.pttStart,
        data: {'mode': 'duplex'},
      );

      _sendSignalingMessage(message);

      _isPTTActive = true;
      notifyListeners();

      // Open a peer connection + offer to every listener on the channel.
      await _startBroadcast();

      if (kDebugMode) {
        print('Duplex mode started on channel: ${_currentChannel!.name}');
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error starting duplex transmission: $e');
      }
      return false;
    }
  }

  /// Broadcast to every other online crew member (mesh): one peer connection +
  /// targeted offer each. Non-members ignore the offer (they only process
  /// offers for their current channel), so exact membership isn't required to
  /// start; a mid-broadcast joiner is offered to via _handleSignalingMessage.
  Future<void> _startBroadcast() async {
    final profile = _crewService.localProfile;
    if (profile == null || _currentChannel == null || _currentSessionId == null) {
      return;
    }
    final listeners = _crewService.onlineCrew
        .map((c) => c.id)
        .where((id) => id != profile.id)
        .toSet();
    (_channelMembers[_currentChannel!.id] ??= {}).addAll(listeners);
    for (final peerId in listeners) {
      await _offerToPeer(peerId);
    }
  }

  /// Create a session to [peerId] and send it a targeted channel offer.
  Future<void> _offerToPeer(String peerId) async {
    final profile = _crewService.localProfile;
    if (profile == null ||
        _currentChannel == null ||
        _currentSessionId == null) {
      return;
    }
    try {
      final session = await _createSession(peerId,
          sessionId: _currentSessionId, isOfferer: true);

      session.pc.onIceCandidate = (RTCIceCandidate candidate) {
        _sendSignalingMessage(SignalingMessage(
          id: const Uuid().v4(),
          sessionId: _currentSessionId!,
          channelId: _currentChannel!.id,
          fromId: profile.id,
          fromName: profile.name,
          type: SignalingType.iceCandidate,
          data: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
            'targetId': peerId,
          },
        ));
      };

      final offer = await session.pc.createOffer();
      await session.pc.setLocalDescription(offer);

      _sendSignalingMessage(SignalingMessage(
        id: const Uuid().v4(),
        sessionId: _currentSessionId!,
        channelId: _currentChannel!.id,
        fromId: profile.id,
        fromName: profile.name,
        type: SignalingType.offer,
        data: {'sdp': offer.sdp, 'type': offer.type, 'targetId': peerId},
      ));
    } catch (e) {
      if (kDebugMode) {
        print('Error offering to $peerId: $e');
      }
    }
  }

  /// Handle incoming signaling message
  Future<void> _handleSignalingMessage(SignalingMessage message) async {
    // Skip messages from self
    final myId = _crewService.localProfile?.id;
    if (message.fromId == myId) return;

    // Skip messages for other channels
    if (_currentChannel == null || message.channelId != _currentChannel!.id) return;

    // Skip already processed messages
    if (_processedSignalingIds.contains(message.id)) return;
    _processedSignalingIds.add(message.id);

    // Cleanup old message IDs (keep last 100)
    if (_processedSignalingIds.length > 100) {
      final toRemove = _processedSignalingIds.take(_processedSignalingIds.length - 100).toList();
      _processedSignalingIds.removeAll(toRemove);
    }

    switch (message.type) {
      case SignalingType.pttStart:
        _activeTransmitters[message.fromId] = message.fromName;
        (_channelMembers[message.channelId] ??= {}).add(message.fromId);
        notifyListeners();
        break;

      case SignalingType.pttEnd:
        _activeTransmitters.remove(message.fromId);
        await _teardownSession(message.fromId);
        notifyListeners();
        break;

      case SignalingType.offer:
        await _handleOffer(message);
        break;

      case SignalingType.answer:
        await _handleAnswer(message);
        break;

      case SignalingType.iceCandidate:
        await _handleIceCandidate(message);
        break;

      case SignalingType.channelJoin:
        (_channelMembers[message.channelId] ??= {}).add(message.fromId);
        // React only to an original join, not to the reply announcements every
        // existing member broadcasts back — re-offering to already-connected
        // peers would tear down and recreate stable sessions mid-broadcast.
        if (message.data?['reply'] != true) {
          // Announce back (once) so the joiner learns we're already present.
          _announcePresenceToChannel(message.channelId);
          // If we're mid-broadcast, bring the new peer into the mesh.
          if (_isPTTActive && _currentSessionId != null) {
            await _offerToPeer(message.fromId);
          }
        }
        break;

      case SignalingType.channelLeave:
        _channelMembers[message.channelId]?.remove(message.fromId);
        _activeTransmitters.remove(message.fromId);
        await _teardownSession(message.fromId);
        break;

      case SignalingType.hangup:
        await _teardownSession(message.fromId);
        break;
    }
  }

  /// Reply to a channelJoin so the new member learns we're already on the
  /// channel (lets a mid-session joiner converge on membership). Marked
  /// `reply:true` so it doesn't trigger another announce-back (no loop).
  void _announcePresenceToChannel(String channelId) {
    final profile = _crewService.localProfile;
    if (profile == null) return;
    _sendSignalingMessage(SignalingMessage(
      id: const Uuid().v4(),
      sessionId: '',
      channelId: channelId,
      fromId: profile.id,
      fromName: profile.name,
      type: SignalingType.channelJoin,
      data: {'reply': true},
    ));
  }

  /// Handle incoming offer
  Future<void> _handleOffer(SignalingMessage message) async {
    final profile = _crewService.localProfile;
    if (profile == null || _currentChannel == null) return;

    final peerId = message.fromId;

    // Mesh: ignore offers addressed to someone else.
    final targetId = message.data?['targetId'] as String?;
    if (targetId != null && targetId != profile.id) return;

    final existing = _sessions[peerId];
    if (existing != null) {
      // Glare: both sides offered. Lexicographically-smaller id stays the
      // offerer; the larger id yields and answers instead.
      if (existing.isOfferer && profile.id.compareTo(peerId) < 0) return;
      // Replace the existing session and (re)answer. A same-session re-offer is
      // a renegotiation/ICE-restart and must NOT be dropped as a duplicate —
      // true duplicates are already filtered by _processedSignalingIds above.
      await _teardownSession(peerId, notify: false);
    }

    try {
      // In duplex we also send our audio, so ensure a local stream exists
      // before _createSession adds it.
      if (isDuplexMode && _hasMicPermission) {
        _localStream ??= await navigator.mediaDevices.getUserMedia({
          'audio': {
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
          },
          'video': false,
        });
        if (!_isPTTActive) {
          _isPTTActive = true;
          _activeTransmitters[profile.id] = profile.name;
          _currentSessionId ??= const Uuid().v4();
          _sendSignalingMessage(SignalingMessage(
            id: const Uuid().v4(),
            sessionId: _currentSessionId!,
            channelId: _currentChannel!.id,
            fromId: profile.id,
            fromName: profile.name,
            type: SignalingType.pttStart,
            data: {'mode': 'duplex'},
          ));
        }
      }

      final session = await _createSession(peerId,
          sessionId: message.sessionId, isOfferer: false);

      session.pc.onIceCandidate = (RTCIceCandidate candidate) {
        _sendSignalingMessage(SignalingMessage(
          id: const Uuid().v4(),
          sessionId: message.sessionId,
          channelId: _currentChannel!.id,
          fromId: profile.id,
          fromName: profile.name,
          type: SignalingType.iceCandidate,
          data: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
            'targetId': peerId,
          },
        ));
      };

      await session.pc.setRemoteDescription(RTCSessionDescription(
        message.data!['sdp'] as String,
        message.data!['type'] as String,
      ));
      await _flushPendingCandidates(session);

      final answer = await session.pc.createAnswer();
      await session.pc.setLocalDescription(answer);

      _sendSignalingMessage(SignalingMessage(
        id: const Uuid().v4(),
        sessionId: message.sessionId,
        channelId: _currentChannel!.id,
        fromId: profile.id,
        fromName: profile.name,
        type: SignalingType.answer,
        data: {'sdp': answer.sdp, 'type': answer.type, 'targetId': peerId},
      ));

      if (kDebugMode) {
        print('Answered offer from ${message.fromName}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling offer: $e');
      }
    }
  }

  /// Handle incoming answer — route to the per-peer session (each pc has its
  /// own HaveLocalOffer state, so every listener's answer applies).
  Future<void> _handleAnswer(SignalingMessage message) async {
    final profile = _crewService.localProfile;
    final targetId = message.data?['targetId'] as String?;
    if (targetId != null && profile != null && targetId != profile.id) return;

    final session = _sessions[message.fromId];
    if (session == null || !session.isOfferer) return;
    if (session.sessionId != null && session.sessionId != message.sessionId) {
      return;
    }
    if (session.remoteDescSet) return; // already answered

    try {
      await session.pc.setRemoteDescription(RTCSessionDescription(
        message.data!['sdp'] as String,
        message.data!['type'] as String,
      ));
      await _flushPendingCandidates(session);
      if (kDebugMode) {
        print('Set remote answer from ${message.fromName}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling answer: $e');
      }
    }
  }

  /// Handle incoming ICE candidate — route to the per-peer session, buffering
  /// if the remote description isn't set yet.
  Future<void> _handleIceCandidate(SignalingMessage message) async {
    final profile = _crewService.localProfile;
    final targetId = message.data?['targetId'] as String?;
    if (targetId != null && profile != null && targetId != profile.id) return;

    final session = _sessions[message.fromId];
    if (session == null) return;
    // Drop stale candidates from a previous PTT session with the same peer.
    if (session.sessionId != null &&
        message.sessionId.isNotEmpty &&
        session.sessionId != message.sessionId) {
      return;
    }

    await _addOrBufferCandidate(
      session,
      RTCIceCandidate(
        message.data!['candidate'] as String?,
        message.data!['sdpMid'] as String?,
        message.data!['sdpMLineIndex'] as int?,
      ),
    );
  }

  /// Send signaling message via SignalK WebSocket delta (real-time broadcast).
  /// While disconnected, queue control messages (pttEnd/hangup/channelLeave) for
  /// delivery on reconnect; SDP (offer/answer/ICE) is dropped since it's stale
  /// once the gap passes.
  void _sendSignalingMessage(SignalingMessage message) {
    final json = message.toJson();
    if (!_signalKService.isConnected) {
      if (message.type == SignalingType.pttEnd ||
          message.type == SignalingType.hangup ||
          message.type == SignalingType.channelLeave) {
        _pendingSignaling.add({'id': message.id, 'json': json});
        while (_pendingSignaling.length > _pendingSignalingMax) {
          _pendingSignaling.removeAt(0);
        }
      }
      return;
    }

    _signalKService.sendRtcSignaling(message.id, json);

    if (kDebugMode) {
      print('Sent RTC signaling: ${message.type} to ${message.channelId}');
    }
  }

  /// Handle direct call signaling messages
  Future<void> _handleDirectCallMessage(SignalingMessage message) async {
    // Skip already processed messages
    if (_processedSignalingIds.contains(message.id)) return;
    _processedSignalingIds.add(message.id);

    if (kDebugMode) {
      print('Direct call message: ${message.type} from ${message.fromName}');
    }

    switch (message.type) {
      case SignalingType.offer:
        // Incoming call!
        if (!_isInDirectCall && !hasIncomingCall) {
          _incomingCallFromId = message.fromId;
          _incomingCallFromName = message.fromName;
          _incomingCallSessionId = message.sessionId;
          _pendingIncomingOffer = message;
          notifyListeners();
          if (kDebugMode) {
            print('Incoming call from ${message.fromName}');
          }
        }
        break;

      case SignalingType.answer:
        // Answer to our outgoing direct call.
        final session = _sessions[_sessionKey(message.fromId, direct: true)];
        if (_isInDirectCall && session != null && session.isOfferer &&
            !session.remoteDescSet) {
          try {
            await session.pc.setRemoteDescription(RTCSessionDescription(
              message.data!['sdp'] as String,
              message.data!['type'] as String,
            ));
            await _flushPendingCandidates(session);
            if (kDebugMode) {
              print('Direct call connected with ${message.fromName}');
            }
          } catch (e) {
            if (kDebugMode) {
              print('Error setting remote description: $e');
            }
          }
        }
        break;

      case SignalingType.iceCandidate:
        // ICE candidate for direct call.
        final c = RTCIceCandidate(
          message.data!['candidate'] as String?,
          message.data!['sdpMid'] as String?,
          message.data!['sdpMLineIndex'] as int?,
        );
        final s = _sessions[_sessionKey(message.fromId, direct: true)];
        if (s != null) {
          // Drop stale candidates from a previous call with the same peer.
          if (s.sessionId != null &&
              message.sessionId.isNotEmpty &&
              s.sessionId != message.sessionId) {
            break;
          }
          await _addOrBufferCandidate(s, c);
        } else if (hasIncomingCall && message.fromId == _incomingCallFromId) {
          // No session yet (user hasn't answered) — buffer until answer.
          _incomingIce.add(c);
        } else if (kDebugMode) {
          print('Ignoring ICE candidate - no active call or incoming call');
        }
        break;

      case SignalingType.hangup:
        // Call ended by other party
        if (_isInDirectCall) {
          await endDirectCall();
        } else if (hasIncomingCall && message.fromId == _incomingCallFromId) {
          _clearIncomingCall();
        }
        break;

      default:
        break;
    }
  }

  /// Sync channels from SignalK
  Future<void> _syncChannels() async {
    if (!_signalKService.isConnected) return;

    try {
      final resources = await _signalKService.getResources(_channelResourceType);

      for (final entry in resources.entries) {
        final resourceId = entry.key;
        final resourceData = entry.value as Map<String, dynamic>;

        try {
          final channel = IntercomChannel.fromNoteResource(resourceId, resourceData);

          // Add or update channel
          final existingIndex = _channels.indexWhere((c) => c.id == channel.id);
          if (existingIndex >= 0) {
            _channels[existingIndex] = channel;
          } else {
            _channels.add(channel);
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing channel $resourceId: $e');
          }
        }
      }

      _channels.sort((a, b) => a.priority.compareTo(b.priority));
      await _saveCachedChannels();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error syncing channels: $e');
      }
    }
  }

  /// Create a new channel
  Future<bool> createChannel({
    required String name,
    String? description,
    int priority = 10,
  }) async {
    final channel = IntercomChannel(
      id: const Uuid().v4(),
      name: name,
      description: description,
      priority: priority,
    );

    _channels.add(channel);
    _channels.sort((a, b) => a.priority.compareTo(b.priority));
    await _saveCachedChannels();
    notifyListeners();

    // Sync to SignalK
    if (_signalKService.isConnected) {
      await _signalKService.putResource(
        _channelResourceType,
        channel.id,
        channel.toNoteResource(),
      );
    }

    return true;
  }

  /// Delete a channel
  Future<bool> deleteChannel(String channelId) async {
    // Can't delete default channels
    final channel = _channels.firstWhere(
      (c) => c.id == channelId,
      orElse: () => IntercomChannel(id: '', name: ''),
    );
    if (channel.id.isEmpty) return false;
    if (IntercomChannel.defaultChannels.any((c) => c.id == channelId)) {
      return false;
    }

    _channels.removeWhere((c) => c.id == channelId);
    await _saveCachedChannels();
    notifyListeners();

    // Remove from SignalK
    if (_signalKService.isConnected) {
      await _signalKService.deleteResource(_channelResourceType, channelId);
    }

    return true;
  }

  /// Get all remote streams for audio playback
  Map<String, MediaStream> get remoteStreams => {
        for (final s in _sessions.values)
          if (s.remoteStream != null) s.peerId: s.remoteStream!,
      };

  /// Get audio renderers (for widgets that need to render audio)
  Map<String, RTCVideoRenderer> get audioRenderers => {
        for (final s in _sessions.values)
          if (s.renderer != null) s.peerId: s.renderer!,
      };

  /// Check if receiving from anyone
  bool get isReceiving => _activeTransmitters.entries
      .any((e) => e.key != _crewService.localProfile?.id);

  // ===== Channel Subscriptions =====

  /// Get subscribed channels for a user
  /// Returns all channels including emergency (ch16) which is always subscribed
  Set<String> getSubscribedChannels(String userId) {
    // Load from cache if not in memory
    if (!_userSubscriptions.containsKey(userId)) {
      _loadUserSubscriptions(userId);
    }

    final subscriptions = _userSubscriptions[userId] ?? _getDefaultSubscriptions();
    // Emergency channel is always included
    return {...subscriptions, emergencyChannelId};
  }

  /// Check if a user is subscribed to a specific channel
  bool isSubscribed(String userId, String channelId) {
    // Emergency channel is always subscribed
    if (channelId == emergencyChannelId) return true;
    return getSubscribedChannels(userId).contains(channelId);
  }

  /// Subscribe a user to a channel
  Future<void> subscribeToChannel(String userId, String channelId) async {
    final subscriptions = getSubscribedChannels(userId);
    if (subscriptions.contains(channelId)) return; // Already subscribed

    final newSubscriptions = {...subscriptions, channelId};
    _userSubscriptions[userId] = newSubscriptions;
    await _storageService.saveChannelSubscriptions(userId, newSubscriptions);
    notifyListeners();

    if (kDebugMode) {
      print('User $userId subscribed to channel $channelId');
    }
  }

  /// Unsubscribe a user from a channel
  /// Note: Cannot unsubscribe from emergency channel (ch16)
  Future<void> unsubscribeFromChannel(String userId, String channelId) async {
    // Cannot unsubscribe from emergency channel
    if (channelId == emergencyChannelId) {
      if (kDebugMode) {
        print('Cannot unsubscribe from emergency channel');
      }
      return;
    }

    final subscriptions = getSubscribedChannels(userId);
    if (!subscriptions.contains(channelId)) return; // Not subscribed

    final newSubscriptions = subscriptions.where((id) => id != channelId).toSet();
    _userSubscriptions[userId] = newSubscriptions;
    await _storageService.saveChannelSubscriptions(userId, newSubscriptions);
    notifyListeners();

    if (kDebugMode) {
      print('User $userId unsubscribed from channel $channelId');
    }
  }

  /// Toggle subscription for a channel
  Future<void> toggleChannelSubscription(String userId, String channelId) async {
    if (isSubscribed(userId, channelId)) {
      await unsubscribeFromChannel(userId, channelId);
    } else {
      await subscribeToChannel(userId, channelId);
    }
  }

  /// Set all subscriptions for a user (used by admin)
  Future<void> setUserSubscriptions(String userId, Set<String> channelIds) async {
    // Always include emergency channel
    final subscriptions = {...channelIds, emergencyChannelId};
    _userSubscriptions[userId] = subscriptions;
    await _storageService.saveChannelSubscriptions(userId, subscriptions);
    notifyListeners();

    if (kDebugMode) {
      print('Set subscriptions for $userId: ${subscriptions.length} channels');
    }
  }

  /// Load subscriptions for a user from storage
  void _loadUserSubscriptions(String userId) {
    final saved = _storageService.loadChannelSubscriptions(userId);
    if (saved != null) {
      // Always include emergency channel
      _userSubscriptions[userId] = {...saved, emergencyChannelId};
    } else {
      // Default: subscribe to all channels
      _userSubscriptions[userId] = _getDefaultSubscriptions();
    }
  }

  /// Get default subscriptions (all channels)
  Set<String> _getDefaultSubscriptions() {
    return _channels.map((c) => c.id).toSet();
  }
}
