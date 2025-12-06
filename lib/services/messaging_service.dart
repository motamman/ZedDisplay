import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/crew_message.dart';
import '../models/crew_member.dart';
import 'signalk_service.dart';
import 'storage_service.dart';
import 'crew_service.dart';

/// Service for crew text messaging
class MessagingService extends ChangeNotifier {
  final SignalKService _signalKService;
  final StorageService _storageService;
  final CrewService _crewService;

  // Messages cache (sorted by timestamp, newest last)
  final List<CrewMessage> _messages = [];
  List<CrewMessage> get messages => List.unmodifiable(_messages);

  // Unread count for badge display
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  // Resources API configuration
  static const String _messageResourceType = 'notes';
  static const String _messageGroupName = 'zeddisplay-messages';

  // Polling timer
  Timer? _pollTimer;
  static const Duration _pollInterval = Duration(seconds: 5);

  // Track if Resources API is available
  bool _resourcesApiAvailable = true;
  bool get isResourcesApiAvailable => _resourcesApiAvailable;

  // Storage key for local message cache
  static const String _messagesStorageKey = 'crew_messages_cache';

  // Message retention (30 days)
  static const Duration _messageRetention = Duration(days: 30);

  // Track connection state
  bool _wasConnected = false;

  // Last fetch timestamp to only get new messages
  DateTime? _lastFetchTime;

  MessagingService(this._signalKService, this._storageService, this._crewService);

  /// Initialize the messaging service
  Future<void> initialize() async {
    // Load cached messages from storage
    await _loadCachedMessages();

    // Listen to SignalK connection changes
    _signalKService.addListener(_onSignalKChanged);

    // If already connected, start polling
    if (_signalKService.isConnected) {
      _onConnected();
    }

    if (kDebugMode) {
      print('MessagingService initialized with ${_messages.length} cached messages');
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _signalKService.removeListener(_onSignalKChanged);
    super.dispose();
  }

  /// Load cached messages from local storage
  Future<void> _loadCachedMessages() async {
    final cachedJson = _storageService.getSetting(_messagesStorageKey);
    if (cachedJson != null) {
      try {
        final List<dynamic> messageList = jsonDecode(cachedJson);
        _messages.clear();
        for (final msgJson in messageList) {
          try {
            final msg = CrewMessage.fromJson(msgJson as Map<String, dynamic>);
            _messages.add(msg);
          } catch (e) {
            // Skip invalid messages
          }
        }
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        _pruneOldMessages();
        _updateUnreadCount();
      } catch (e) {
        if (kDebugMode) {
          print('Error loading cached messages: $e');
        }
      }
    }
  }

  /// Save messages to local storage
  Future<void> _saveCachedMessages() async {
    final messageList = _messages.map((m) => m.toJson()).toList();
    await _storageService.saveSetting(_messagesStorageKey, jsonEncode(messageList));
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
      print('MessagingService: Connected');
    }
    _startPolling();
    _fetchMessages();
  }

  void _onDisconnected() {
    if (kDebugMode) {
      print('MessagingService: Disconnected');
    }
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      _fetchMessages();
    });
  }

  /// Send a text message
  Future<bool> sendMessage(String content, {String toId = 'all'}) async {
    final profile = _crewService.localProfile;
    if (profile == null) {
      if (kDebugMode) {
        print('Cannot send message: no crew profile');
      }
      return false;
    }

    final message = CrewMessage(
      id: const Uuid().v4(),
      fromId: profile.id,
      fromName: profile.name,
      toId: toId,
      type: MessageType.text,
      content: content,
    );

    return _sendMessage(message);
  }

  /// Send a status broadcast
  Future<bool> sendStatusBroadcast(String status) async {
    final profile = _crewService.localProfile;
    if (profile == null) return false;

    final message = CrewMessage(
      id: const Uuid().v4(),
      fromId: profile.id,
      fromName: profile.name,
      toId: 'all',
      type: MessageType.status,
      content: status,
    );

    return _sendMessage(message);
  }

  /// Send an alert broadcast
  Future<bool> sendAlert(String alert) async {
    final profile = _crewService.localProfile;
    if (profile == null) return false;

    final message = CrewMessage(
      id: const Uuid().v4(),
      fromId: profile.id,
      fromName: profile.name,
      toId: 'all',
      type: MessageType.alert,
      content: alert,
    );

    return _sendMessage(message);
  }

  /// Internal method to send a message
  Future<bool> _sendMessage(CrewMessage message) async {
    // Add to local cache immediately (optimistic update)
    _messages.add(message);
    _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    notifyListeners();

    // Sync to SignalK
    if (_signalKService.isConnected && _resourcesApiAvailable) {
      final resourceData = _buildMessageResource(message);
      final success = await _signalKService.putResource(
        _messageResourceType,
        message.id,
        resourceData,
      );

      if (!success) {
        if (kDebugMode) {
          print('Failed to sync message to SignalK');
        }
        // Keep in local cache anyway
      }
    }

    // Save to local storage
    await _saveCachedMessages();

    return true;
  }

  /// Build a notes resource from message data
  Map<String, dynamic> _buildMessageResource(CrewMessage message) {
    // Get vessel position for the note
    final posData = _signalKService.getValue('navigation.position');
    double lat = 0.0;
    double lng = 0.0;
    if (posData?.value is Map) {
      final pos = posData!.value as Map;
      lat = (pos['latitude'] as num?)?.toDouble() ?? 0.0;
      lng = (pos['longitude'] as num?)?.toDouble() ?? 0.0;
    }

    return {
      'name': '${message.fromName}: ${_truncate(message.content, 50)}',
      'description': jsonEncode(message.toJson()),
      'group': _messageGroupName,
      'position': {
        'latitude': lat,
        'longitude': lng,
      },
    };
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 3)}...';
  }

  /// Fetch messages from SignalK
  Future<void> _fetchMessages() async {
    if (!_signalKService.isConnected) return;

    try {
      final resources = await _signalKService.getResources(_messageResourceType);

      if (resources.isEmpty) return;

      bool changed = false;
      final myId = _crewService.localProfile?.id;

      for (final entry in resources.entries) {
        final noteId = entry.key;
        final noteData = entry.value as Map<String, dynamic>;

        // Filter by our group
        final group = noteData['group'] as String?;
        if (group != _messageGroupName) continue;

        // Skip messages we already have
        if (_messages.any((m) => m.id == noteId)) continue;

        try {
          final descriptionJson = noteData['description'] as String?;
          if (descriptionJson == null) continue;

          final msgData = jsonDecode(descriptionJson) as Map<String, dynamic>;
          final message = CrewMessage.fromJson(msgData);

          // Check if this message is for us (broadcast or direct to us)
          if (message.toId == 'all' || message.toId == myId || message.fromId == myId) {
            _messages.add(message);
            changed = true;

            // Count as unread if not from us
            if (message.fromId != myId && !message.read) {
              _unreadCount++;
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing message $noteId: $e');
          }
        }
      }

      if (changed) {
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        _pruneOldMessages();
        await _saveCachedMessages();
        notifyListeners();
      }

      _lastFetchTime = DateTime.now();
      _resourcesApiAvailable = true;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching messages: $e');
      }
    }
  }

  /// Remove messages older than retention period
  void _pruneOldMessages() {
    final cutoff = DateTime.now().subtract(_messageRetention);
    _messages.removeWhere((m) => m.timestamp.isBefore(cutoff));
  }

  /// Update unread count
  void _updateUnreadCount() {
    final myId = _crewService.localProfile?.id;
    _unreadCount = _messages.where((m) => m.fromId != myId && !m.read).length;
  }

  /// Mark all messages as read
  void markAllAsRead() {
    bool changed = false;
    for (int i = 0; i < _messages.length; i++) {
      if (!_messages[i].read) {
        _messages[i] = _messages[i].copyWith(read: true);
        changed = true;
      }
    }
    if (changed) {
      _unreadCount = 0;
      _saveCachedMessages();
      notifyListeners();
    }
  }

  /// Get messages for broadcast channel
  List<CrewMessage> get broadcastMessages {
    return _messages.where((m) => m.toId == 'all').toList();
  }

  /// Get direct messages with a specific crew member
  List<CrewMessage> getDirectMessages(String crewId) {
    final myId = _crewService.localProfile?.id;
    return _messages.where((m) =>
        (m.fromId == crewId && m.toId == myId) ||
        (m.fromId == myId && m.toId == crewId)
    ).toList();
  }

  /// Clear all messages (for testing/debug)
  Future<void> clearAllMessages() async {
    _messages.clear();
    _unreadCount = 0;
    await _saveCachedMessages();
    notifyListeners();
  }
}
