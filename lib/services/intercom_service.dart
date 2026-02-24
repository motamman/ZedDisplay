import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../models/intercom_channel.dart';
import 'signalk_service.dart';
import 'storage_service.dart';
import 'crew_service.dart';
import 'notification_service.dart';

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

  // WebRTC
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final Map<String, MediaStream> _remoteStreams = {}; // peerId -> stream
  MediaStream? get remoteStream => _remoteStreams.values.firstOrNull;

  // Audio renderers for playback
  final Map<String, RTCVideoRenderer> _audioRenderers = {};

  final Map<String, RTCPeerConnection> _peerConnections = {};

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
    _pollTimer?.cancel();
    _signalKService.unregisterConnectionCallback(_onConnected);
    _signalKService.removeListener(_onSignalKChanged);
    _signalKService.unregisterRtcDeltaCallback();
    _cleanup();
    super.dispose();
  }

  /// Cleanup a specific peer's connection and stream
  Future<void> _cleanupPeer(String peerId) async {
    // Cleanup remote stream for this peer
    final stream = _remoteStreams.remove(peerId);
    await stream?.dispose();

    // Cleanup audio renderer
    final renderer = _audioRenderers.remove(peerId);
    await renderer?.dispose();

    // Close peer connection
    final pc = _peerConnections.remove(peerId);
    await pc?.close();
  }

  Future<void> _cleanup() async {
    await _localStream?.dispose();
    _localStream = null;

    // Cleanup all remote streams
    for (final stream in _remoteStreams.values) {
      await stream.dispose();
    }
    _remoteStreams.clear();

    // Cleanup audio renderers
    for (final renderer in _audioRenderers.values) {
      await renderer.dispose();
    }
    _audioRenderers.clear();

    await _peerConnection?.close();
    _peerConnection = null;

    for (final pc in _peerConnections.values) {
      await pc.close();
    }
    _peerConnections.clear();

    _activeTransmitters.clear();
    _answeredSessions.clear();
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

      notifyListeners();
      return _hasMicPermission;
    } catch (e) {
      if (kDebugMode) {
        print('Error requesting microphone permission: $e');
      }
      return false;
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
    _leaveChannel();
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

      // Create offer and start WebRTC connection
      await _createOffer();

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

      // Close peer connections
      await _peerConnection?.close();
      _peerConnection = null;

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

  // Queue for ICE candidates received before peer connection is ready
  final List<SignalingMessage> _pendingIceCandidates = [];

  /// Start a direct call to a specific crew member
  Future<bool> startDirectCall(String targetId, String targetName) async {
    if (_isInDirectCall) return false;
    if (!_hasMicPermission) {
      final granted = await requestMicPermission();
      if (!granted) return false;
    }

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
    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _localStream = null;

    await _peerConnection?.close();
    _peerConnection = null;

    _isInDirectCall = false;
    _directCallTargetId = null;
    _directCallTargetName = null;
    _currentSessionId = null;
    _pendingIceCandidates.clear();
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

      // Create peer connection
      _peerConnection = await createPeerConnection({
        'iceServers': [],
        'sdpSemantics': 'unified-plan',
      });

      // Add local stream
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      // Handle ICE candidates
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        final iceMessage = SignalingMessage(
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
        );
        _sendSignalingMessage(iceMessage);
      };

      // Handle remote stream
      _peerConnection!.onTrack = (RTCTrackEvent event) async {
        if (event.streams.isNotEmpty) {
          final stream = event.streams[0];
          _remoteStreams[callerId] = stream;

          // Create renderer for playback
          final renderer = RTCVideoRenderer();
          await renderer.initialize();
          renderer.srcObject = stream;
          _audioRenderers[callerId] = renderer;

          notifyListeners();
        }
      };

      // Set remote description (the offer)
      await _peerConnection!.setRemoteDescription(RTCSessionDescription(
        offer.data!['sdp'] as String,
        offer.data!['type'] as String,
      ));

      // Create and send answer
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      final answerMessage = SignalingMessage(
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
      );

      _sendSignalingMessage(answerMessage);

      // Process any queued ICE candidates now that peer connection is ready
      if (_pendingIceCandidates.isNotEmpty) {
        if (kDebugMode) {
          print('Processing ${_pendingIceCandidates.length} queued ICE candidates');
        }
        for (final iceMsg in _pendingIceCandidates) {
          try {
            await _peerConnection!.addCandidate(RTCIceCandidate(
              iceMsg.data!['candidate'] as String?,
              iceMsg.data!['sdpMid'] as String?,
              iceMsg.data!['sdpMLineIndex'] as int?,
            ));
          } catch (e) {
            if (kDebugMode) {
              print('Error adding queued ICE candidate: $e');
            }
          }
        }
        _pendingIceCandidates.clear();
      }

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
    _pendingIceCandidates.clear();
    notifyListeners();
  }

  /// Create WebRTC offer for direct call
  Future<void> _createDirectCallOffer(String targetId) async {
    final profile = _crewService.localProfile;
    if (profile == null) return;

    try {
      _peerConnection = await createPeerConnection({
        'iceServers': [],
        'sdpSemantics': 'unified-plan',
      });

      // Add local stream
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          _peerConnection!.addTrack(track, _localStream!);
        });
      }

      // Handle ICE candidates
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        final iceMessage = SignalingMessage(
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
          },
        );
        _sendSignalingMessage(iceMessage);
      };

      // Handle remote stream
      _peerConnection!.onTrack = (RTCTrackEvent event) async {
        if (event.streams.isNotEmpty) {
          final stream = event.streams[0];
          _remoteStreams[targetId] = stream;

          // Create renderer for playback
          final renderer = RTCVideoRenderer();
          await renderer.initialize();
          renderer.srcObject = stream;
          _audioRenderers[targetId] = renderer;

          notifyListeners();
        }
      };

      // Create offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // Send offer
      final offerMessage = SignalingMessage(
        id: const Uuid().v4(),
        sessionId: _currentSessionId!,
        channelId: 'direct_$targetId',
        fromId: profile.id,
        fromName: profile.name,
        type: SignalingType.offer,
        data: {'sdp': offer.sdp, 'type': offer.type, 'directCall': true},
      );

      _sendSignalingMessage(offerMessage);
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

      // Create offer and start WebRTC connection
      await _createOffer();

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

  /// Create WebRTC offer
  Future<void> _createOffer() async {
    final profile = _crewService.localProfile;
    if (profile == null || _currentChannel == null || _currentSessionId == null) return;

    try {
      // Create peer connection
      _peerConnection = await createPeerConnection({
        'iceServers': [
          // Use local network - no STUN/TURN needed for LAN
        ],
        'sdpSemantics': 'unified-plan',
      });

      // Add local stream
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          _peerConnection!.addTrack(track, _localStream!);
        });
      }

      // Handle ICE candidates
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        _sendIceCandidate(candidate);
      };

      // Handle remote stream (when receiving audio back in duplex mode)
      _peerConnection!.onTrack = (RTCTrackEvent event) async {
        if (event.streams.isNotEmpty) {
          // In duplex mode, we might receive audio from answerers
          // Store in remoteStreams map
          final stream = event.streams[0];
          // Use a generic key for self-initiated streams
          _remoteStreams['self_receive'] = stream;

          // Create renderer for playback
          final renderer = RTCVideoRenderer();
          await renderer.initialize();
          renderer.srcObject = stream;
          _audioRenderers['self_receive'] = renderer;

          notifyListeners();
        }
      };

      // Create offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // Send offer via SignalK
      final message = SignalingMessage(
        id: const Uuid().v4(),
        sessionId: _currentSessionId!,
        channelId: _currentChannel!.id,
        fromId: profile.id,
        fromName: profile.name,
        type: SignalingType.offer,
        data: {'sdp': offer.sdp, 'type': offer.type},
      );

      _sendSignalingMessage(message);
    } catch (e) {
      if (kDebugMode) {
        print('Error creating offer: $e');
      }
    }
  }

  /// Send ICE candidate
  Future<void> _sendIceCandidate(RTCIceCandidate candidate) async {
    final profile = _crewService.localProfile;
    if (profile == null || _currentChannel == null || _currentSessionId == null) return;

    final message = SignalingMessage(
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
      },
    );

    _sendSignalingMessage(message);
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
        // Add to active transmitters (supports multiple)
        _activeTransmitters[message.fromId] = message.fromName;
        notifyListeners();
        break;

      case SignalingType.pttEnd:
        // Remove from active transmitters
        _activeTransmitters.remove(message.fromId);
        // Cleanup that peer's stream and connection
        await _cleanupPeer(message.fromId);
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
        // Update channel member list
        if (kDebugMode) {
          print('${message.fromName} joined channel');
        }
        break;

      case SignalingType.channelLeave:
        if (kDebugMode) {
          print('${message.fromName} left channel');
        }
        break;

      case SignalingType.hangup:
        await _cleanup();
        break;
    }
  }

  /// Handle incoming offer
  Future<void> _handleOffer(SignalingMessage message) async {
    final profile = _crewService.localProfile;
    if (profile == null || _currentChannel == null) return;

    final peerId = message.fromId;
    final sessionKey = '${message.sessionId}_$peerId';

    // Check if we've already answered this session
    if (_answeredSessions.contains(sessionKey)) {
      if (kDebugMode) {
        print('Already answered session from ${message.fromName}, skipping');
      }
      return;
    }

    try {
      // Mark as answered before processing to prevent duplicates
      _answeredSessions.add(sessionKey);

      // Cleanup old session keys (keep last 50)
      if (_answeredSessions.length > 50) {
        final toRemove = _answeredSessions.take(_answeredSessions.length - 50).toList();
        _answeredSessions.removeAll(toRemove);
      }

      // Cleanup existing connection for this peer if any
      await _cleanupPeer(peerId);

      // Create peer connection for this sender
      final pc = await createPeerConnection({
        'iceServers': [],
        'sdpSemantics': 'unified-plan',
      });
      _peerConnections[peerId] = pc;

      // Handle ICE candidates
      pc.onIceCandidate = (RTCIceCandidate candidate) {
        final answerMessage = SignalingMessage(
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
          },
        );
        _sendSignalingMessage(answerMessage);
      };

      // In duplex mode, add our local audio so they can hear us too
      if (isDuplexMode && _hasMicPermission) {
        // Create local stream if we don't have one
        if (_localStream == null) {
          _localStream = await navigator.mediaDevices.getUserMedia({
            'audio': {
              'echoCancellation': true,
              'noiseSuppression': true,
              'autoGainControl': true,
            },
            'video': false,
          });
        }

        // Add our audio tracks to this peer connection
        for (final track in _localStream!.getAudioTracks()) {
          await pc.addTrack(track, _localStream!);
        }

        // Mark us as actively transmitting so the UI shows it
        if (!_isPTTActive) {
          _isPTTActive = true;
          _activeTransmitters[profile.id] = profile.name;

          // Create a session ID if we don't have one
          _currentSessionId ??= const Uuid().v4();

          // Notify others that we've started transmitting
          final pttStartMessage = SignalingMessage(
            id: const Uuid().v4(),
            sessionId: _currentSessionId!,
            channelId: _currentChannel!.id,
            fromId: profile.id,
            fromName: profile.name,
            type: SignalingType.pttStart,
            data: {'mode': 'duplex'},
          );
          _sendSignalingMessage(pttStartMessage);
        }

        if (kDebugMode) {
          print('Added local audio to duplex connection with ${message.fromName}');
        }
      }

      // Handle remote stream (the audio from the transmitter)
      pc.onTrack = (RTCTrackEvent event) async {
        if (event.streams.isNotEmpty) {
          final stream = event.streams[0];
          _remoteStreams[peerId] = stream;

          // Create audio renderer for playback
          final renderer = RTCVideoRenderer();
          await renderer.initialize();
          renderer.srcObject = stream;
          _audioRenderers[peerId] = renderer;

          if (kDebugMode) {
            print('Audio stream connected from ${message.fromName}');
          }
          notifyListeners();
        }
      };

      // Set remote description (the offer)
      await pc.setRemoteDescription(RTCSessionDescription(
        message.data!['sdp'] as String,
        message.data!['type'] as String,
      ));

      // Create and send answer
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      final answerMessage = SignalingMessage(
        id: const Uuid().v4(),
        sessionId: message.sessionId,
        channelId: _currentChannel!.id,
        fromId: profile.id,
        fromName: profile.name,
        type: SignalingType.answer,
        data: {'sdp': answer.sdp, 'type': answer.type},
      );

      _sendSignalingMessage(answerMessage);

      if (kDebugMode) {
        print('Answered offer from ${message.fromName}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling offer: $e');
      }
    }
  }

  /// Handle incoming answer
  Future<void> _handleAnswer(SignalingMessage message) async {
    if (_peerConnection == null) return;

    // Only process answer if we're in the correct state (have-local-offer)
    // and the answer is for our current session
    if (_currentSessionId != message.sessionId) {
      if (kDebugMode) {
        print('Ignoring answer for different session: ${message.sessionId}');
      }
      return;
    }

    final signalingState = _peerConnection!.signalingState;
    if (signalingState != RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
      if (kDebugMode) {
        print('Ignoring answer - wrong state: $signalingState');
      }
      return;
    }

    try {
      await _peerConnection!.setRemoteDescription(RTCSessionDescription(
        message.data!['sdp'] as String,
        message.data!['type'] as String,
      ));
      if (kDebugMode) {
        print('Successfully set remote description from ${message.fromName}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling answer: $e');
      }
    }
  }

  /// Handle incoming ICE candidate
  Future<void> _handleIceCandidate(SignalingMessage message) async {
    final pc = _peerConnection ?? _peerConnections[message.fromId];
    if (pc == null) return;

    try {
      await pc.addCandidate(RTCIceCandidate(
        message.data!['candidate'] as String?,
        message.data!['sdpMid'] as String?,
        message.data!['sdpMLineIndex'] as int?,
      ));
    } catch (e) {
      if (kDebugMode) {
        print('Error handling ICE candidate: $e');
      }
    }
  }

  /// Send signaling message via SignalK WebSocket delta (real-time broadcast)
  void _sendSignalingMessage(SignalingMessage message) {
    if (!_signalKService.isConnected) return;

    // Send via WebSocket delta - broadcasts to all connected clients
    _signalKService.sendRtcSignaling(message.id, message.toJson());

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
        // Answer to our outgoing call
        if (_isInDirectCall && _peerConnection != null) {
          final signalingState = _peerConnection!.signalingState;
          if (signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
            try {
              await _peerConnection!.setRemoteDescription(RTCSessionDescription(
                message.data!['sdp'] as String,
                message.data!['type'] as String,
              ));
              if (kDebugMode) {
                print('Direct call connected with ${message.fromName}');
              }
            } catch (e) {
              if (kDebugMode) {
                print('Error setting remote description: $e');
              }
            }
          }
        }
        break;

      case SignalingType.iceCandidate:
        // ICE candidate for direct call
        if (_peerConnection != null) {
          try {
            await _peerConnection!.addCandidate(RTCIceCandidate(
              message.data!['candidate'] as String?,
              message.data!['sdpMid'] as String?,
              message.data!['sdpMLineIndex'] as int?,
            ));
          } catch (e) {
            if (kDebugMode) {
              print('Error adding ICE candidate: $e');
            }
          }
        } else if (hasIncomingCall && message.fromId == _incomingCallFromId) {
          // Queue ICE candidate until peer connection is ready (for incoming call)
          if (kDebugMode) {
            print('Queuing ICE candidate from ${message.fromName} (awaiting answer)');
          }
          _pendingIceCandidates.add(message);
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
  Map<String, MediaStream> get remoteStreams => Map.unmodifiable(_remoteStreams);

  /// Get audio renderers (for widgets that need to render audio)
  Map<String, RTCVideoRenderer> get audioRenderers => Map.unmodifiable(_audioRenderers);

  /// Check if receiving from anyone
  bool get isReceiving => _activeTransmitters.entries
      .any((e) => e.key != _crewService.localProfile?.id);
}
