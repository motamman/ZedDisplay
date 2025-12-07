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

  // Who is currently transmitting
  String? _currentTransmitterId;
  String? _currentTransmitterName;
  String? get currentTransmitterId => _currentTransmitterId;
  String? get currentTransmitterName => _currentTransmitterName;

  // WebRTC
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final Map<String, RTCPeerConnection> _peerConnections = {};

  // Resources API configuration
  static const String _channelResourceType = 'notes';
  static const String _channelGroupName = 'zeddisplay-channels';
  static const String _rtcGroupName = 'zeddisplay-rtc';

  // Polling timer
  Timer? _pollTimer;
  static const Duration _pollInterval = Duration(seconds: 2);

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

  IntercomService(this._signalKService, this._storageService, this._crewService);

  /// Initialize the intercom service
  Future<void> initialize() async {
    // Load cached channels
    await _loadCachedChannels();

    // Check microphone permission
    await _checkMicPermission();

    // Listen to SignalK connection changes
    _signalKService.addListener(_onSignalKChanged);

    // If already connected, start polling
    if (_signalKService.isConnected) {
      _onConnected();
    }

    _initialized = true;

    if (kDebugMode) {
      print('IntercomService initialized with ${_channels.length} channels');
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _signalKService.removeListener(_onSignalKChanged);
    _cleanup();
    super.dispose();
  }

  Future<void> _cleanup() async {
    await _localStream?.dispose();
    await _remoteStream?.dispose();
    await _peerConnection?.close();
    for (final pc in _peerConnections.values) {
      await pc.close();
    }
    _peerConnections.clear();
  }

  /// Check and request microphone permission
  Future<bool> _checkMicPermission() async {
    final status = await Permission.microphone.status;
    _hasMicPermission = status.isGranted;
    return _hasMicPermission;
  }

  /// Request microphone permission
  Future<bool> requestMicPermission() async {
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

  /// Handle SignalK connection changes
  void _onSignalKChanged() {
    final isConnected = _signalKService.isConnected;
    if (isConnected == _wasConnected) return;
    _wasConnected = isConnected;

    if (isConnected) {
      _onConnected();
    } else {
      _onDisconnected();
    }
  }

  void _onConnected() {
    if (kDebugMode) {
      print('IntercomService: Connected');
    }
    _startPolling();
    _syncChannels();
  }

  void _onDisconnected() {
    if (kDebugMode) {
      print('IntercomService: Disconnected');
    }
    _pollTimer?.cancel();
    _pollTimer = null;
    _leaveChannel();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      _fetchSignaling();
    });
  }

  /// Select a channel to listen to
  Future<void> selectChannel(IntercomChannel channel) async {
    if (_currentChannel?.id == channel.id) return;

    // Leave current channel first
    if (_currentChannel != null) {
      await _leaveChannel();
    }

    _currentChannel = channel;
    await _storageService.saveSetting(_lastChannelKey, channel.id);
    notifyListeners();

    // Join the new channel
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

    await _sendSignalingMessage(message);

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

    await _sendSignalingMessage(message);

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

      await _sendSignalingMessage(message);

      _isPTTActive = true;
      _currentTransmitterId = profile.id;
      _currentTransmitterName = profile.name;
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

        await _sendSignalingMessage(message);
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
      _currentTransmitterId = null;
      _currentTransmitterName = null;
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

      await _sendSignalingMessage(message);

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

      // Handle remote stream
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
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

      await _sendSignalingMessage(message);
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

    await _sendSignalingMessage(message);
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
        _currentTransmitterId = message.fromId;
        _currentTransmitterName = message.fromName;
        notifyListeners();
        break;

      case SignalingType.pttEnd:
        if (_currentTransmitterId == message.fromId) {
          _currentTransmitterId = null;
          _currentTransmitterName = null;
          // Close remote stream
          await _remoteStream?.dispose();
          _remoteStream = null;
          notifyListeners();
        }
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

    try {
      // Create peer connection for this sender
      final pc = await createPeerConnection({
        'iceServers': [],
        'sdpSemantics': 'unified-plan',
      });
      _peerConnections[message.fromId] = pc;

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

      // Handle remote stream (the audio from the transmitter)
      pc.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
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

      await _sendSignalingMessage(answerMessage);
    } catch (e) {
      if (kDebugMode) {
        print('Error handling offer: $e');
      }
    }
  }

  /// Handle incoming answer
  Future<void> _handleAnswer(SignalingMessage message) async {
    if (_peerConnection == null) return;

    try {
      await _peerConnection!.setRemoteDescription(RTCSessionDescription(
        message.data!['sdp'] as String,
        message.data!['type'] as String,
      ));
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

  /// Send signaling message via SignalK Resources API
  Future<void> _sendSignalingMessage(SignalingMessage message) async {
    if (!_signalKService.isConnected) return;

    final posData = _signalKService.getValue('navigation.position');
    double lat = 0.0;
    double lng = 0.0;
    if (posData?.value is Map) {
      final pos = posData!.value as Map;
      lat = (pos['latitude'] as num?)?.toDouble() ?? 0.0;
      lng = (pos['longitude'] as num?)?.toDouble() ?? 0.0;
    }

    await _signalKService.putResource(
      _channelResourceType,
      message.id,
      message.toNoteResource(lat: lat, lng: lng),
    );
  }

  /// Fetch signaling messages from SignalK
  Future<void> _fetchSignaling() async {
    if (!_signalKService.isConnected) return;
    if (_currentChannel == null) return;

    try {
      final resources = await _signalKService.getResources(_channelResourceType);
      if (resources.isEmpty) return;

      for (final entry in resources.entries) {
        final noteId = entry.key;
        final noteData = entry.value as Map<String, dynamic>;

        // Filter by RTC group
        final group = noteData['group'] as String?;
        if (group != _rtcGroupName) continue;

        try {
          final descriptionJson = noteData['description'] as String?;
          if (descriptionJson == null) continue;

          final msgData = jsonDecode(descriptionJson) as Map<String, dynamic>;
          final message = SignalingMessage.fromJson(msgData);

          // Only process recent messages (last 30 seconds)
          if (DateTime.now().difference(message.timestamp).inSeconds > 30) continue;

          await _handleSignalingMessage(message);
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing signaling message $noteId: $e');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching signaling: $e');
      }
    }
  }

  /// Sync channels from SignalK
  Future<void> _syncChannels() async {
    if (!_signalKService.isConnected) return;

    try {
      final resources = await _signalKService.getResources(_channelResourceType);

      for (final entry in resources.entries) {
        final noteId = entry.key;
        final noteData = entry.value as Map<String, dynamic>;

        // Filter by channel group
        final group = noteData['group'] as String?;
        if (group != _channelGroupName) continue;

        try {
          final channel = IntercomChannel.fromNoteResource(noteId, noteData);

          // Add or update channel
          final existingIndex = _channels.indexWhere((c) => c.id == channel.id);
          if (existingIndex >= 0) {
            _channels[existingIndex] = channel;
          } else {
            _channels.add(channel);
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing channel $noteId: $e');
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

  /// Get remote stream for audio playback
  MediaStream? get remoteStream => _remoteStream;
}
