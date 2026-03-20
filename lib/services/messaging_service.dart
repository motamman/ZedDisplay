import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/crew_message.dart';
import 'signalk_service.dart';
import 'storage_service.dart';
import 'crew_service.dart';
import 'notification_service.dart';

/// Service for crew text messaging
class MessagingService extends ChangeNotifier {
  final SignalKService _signalKService;
  final StorageService _storageService;
  final CrewService _crewService;
  final NotificationService _notificationService;

  // Messages cache (sorted by timestamp, newest last)
  final List<CrewMessage> _messages = [];
  List<CrewMessage> get messages => List.unmodifiable(_messages);

  // Unread count for badge display
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  // Resources API configuration - uses custom resource type for isolation
  static const String _messageResourceType = 'zeddisplay-messages';

  // WS delta path prefix for real-time message delivery
  static const String _messagePathPrefix = 'crew.messages.';

  // Track if Resources API is available
  bool _resourcesApiAvailable = true;
  bool get isResourcesApiAvailable => _resourcesApiAvailable;

  // Storage key for local message cache
  static const String _messagesStorageKey = 'crew_messages_cache';

  // Message retention (30 days)
  static const Duration _messageRetention = Duration(days: 30);

  // Track connection state
  bool _wasConnected = false;

  MessagingService(this._signalKService, this._storageService, this._crewService)
      : _notificationService = NotificationService();

  /// Initialize the messaging service
  Future<void> initialize() async {
    // Load cached messages from storage
    await _loadCachedMessages();

    // Register connection callback for sequential execution (prevents HTTP overload)
    _signalKService.registerConnectionCallback(_onConnected);

    // Listen to SignalK connection changes for disconnection handling
    _signalKService.addListener(_onSignalKChanged);

    // If already connected, hydrate and subscribe
    if (_signalKService.isConnected) {
      await _onConnected();
    }

  }

  @override
  void dispose() {
    _signalKService.unsubscribeFromPaths(['crew.messages.*'], ownerId: 'messaging');
    _signalKService.unregisterConnectionCallback(_onConnected);
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

  /// Handle SignalK connection changes and process WS deltas
  /// Connection is handled via registerConnectionCallback for sequential execution
  void _onSignalKChanged() {
    final isConnected = _signalKService.isConnected;
    if (isConnected != _wasConnected) {
      _wasConnected = isConnected;

      // Only handle disconnection here - connection is handled via callback
      if (!isConnected) {
        _onDisconnected();
      }
    }

    // Process message WS deltas while connected
    if (isConnected) {
      _processMessageDeltas();
    }
  }

  Future<void> _onConnected() async {
    await _ensureResourceType();
    await _fetchMessages();

    // Subscribe to message paths for real-time delivery
    await _signalKService.subscribeToPaths(['crew.messages.*'], ownerId: 'messaging');
  }

  /// Ensure the custom resource type exists on the server
  Future<void> _ensureResourceType() async {
    await _signalKService.ensureResourceTypeExists(
      _messageResourceType,
      description: 'ZedDisplay crew messaging',
    );
  }

  void _onDisconnected() {
    _signalKService.unsubscribeFromPaths(['crew.messages.*'], ownerId: 'messaging');
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
      // Broadcast via WS delta first (instant delivery to other clients)
      _signalKService.sendDelta('$_messagePathPrefix${message.id}', message.toJson(), source: 'zeddisplay');

      // Persist to Resources API
      final resourceData = _buildMessageResource(message);
      final success = await _signalKService.putResource(
        _messageResourceType,
        message.id,
        resourceData,
      );

      if (!success && kDebugMode) {
        print('Failed to sync message to SignalK');
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
        final resourceId = entry.key;
        final resourceData = entry.value as Map<String, dynamic>;

        // Skip messages we already have
        if (_messages.any((m) => m.id == resourceId)) continue;

        try {
          final descriptionJson = resourceData['description'] as String?;
          if (descriptionJson == null) continue;

          final msgData = jsonDecode(descriptionJson) as Map<String, dynamic>;
          final message = CrewMessage.fromJson(msgData);

          // Check if this message is for us (broadcast or direct to us)
          if (message.toId == 'all' || message.toId == myId || message.fromId == myId) {
            _messages.add(message);
            changed = true;

            // Count as unread and show notification if not from us
            if (message.fromId != myId && !message.read) {
              _unreadCount++;
              // Show system notification if crew notifications are enabled
              final isAlert = message.type == MessageType.alert;
              final showNotification = isAlert
                  ? _storageService.getCrewAlertNotificationsEnabled()
                  : _storageService.getCrewNotificationsEnabled();
              if (showNotification) {
                _notificationService.showCrewMessageNotification(message);
              }
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing message $resourceId: $e');
          }
        }
      }

      if (changed) {
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        _pruneOldMessages();
        await _saveCachedMessages();
        notifyListeners();
      }

      _resourcesApiAvailable = true;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching messages: $e');
      }
    }
  }

  /// Process message deltas received via WebSocket
  void _processMessageDeltas() {
    final latestData = _signalKService.latestData;
    final myId = _crewService.localProfile?.id;
    bool changed = false;

    for (final entry in latestData.entries) {
      if (!entry.key.startsWith(_messagePathPrefix)) continue;

      // Extract message ID from path: crew.messages.<id>
      final messageId = entry.key.substring(_messagePathPrefix.length);

      // Skip messages we already have (also handles self-skip via optimistic update)
      if (_messages.any((m) => m.id == messageId)) continue;

      // Parse the message from the delta value
      try {
        final value = entry.value.value;
        if (value is! Map) continue;
        final msgData = Map<String, dynamic>.from(value);
        final message = CrewMessage.fromJson(msgData);

        // Filter: broadcast, direct to us, or from us
        if (message.toId == 'all' || message.toId == myId || message.fromId == myId) {
          _messages.add(message);
          changed = true;

          // Count as unread and show notification if not from us
          if (message.fromId != myId && !message.read) {
            _unreadCount++;
            final isAlert = message.type == MessageType.alert;
            final showNotification = isAlert
                ? _storageService.getCrewAlertNotificationsEnabled()
                : _storageService.getCrewNotificationsEnabled();
            if (showNotification) {
              _notificationService.showCrewMessageNotification(message);
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error parsing message delta $messageId: $e');
        }
      }
    }

    if (changed) {
      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      _pruneOldMessages();
      _saveCachedMessages();
      notifyListeners();
    }
  }

  // Alert messages sunset after 48 hours
  static const Duration _alertRetention = Duration(hours: 48);

  /// Remove messages older than retention period
  void _pruneOldMessages() {
    final now = DateTime.now();
    final generalCutoff = now.subtract(_messageRetention);
    final alertCutoff = now.subtract(_alertRetention);
    _messages.removeWhere((m) =>
        m.timestamp.isBefore(generalCutoff) ||
        (m.type == MessageType.alert && m.timestamp.isBefore(alertCutoff)));
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

  /// Delete a single message locally and from server.
  Future<void> deleteMessage(String messageId) async {
    _messages.removeWhere((m) => m.id == messageId);
    _updateUnreadCount();
    await _saveCachedMessages();
    notifyListeners();

    // Remove from SignalK Resources API
    if (_signalKService.isConnected && _resourcesApiAvailable) {
      await _signalKService.deleteResource(_messageResourceType, messageId);
    }
  }

  /// Clear all messages (for testing/debug)
  Future<void> clearAllMessages() async {
    _messages.clear();
    _unreadCount = 0;
    await _saveCachedMessages();
    notifyListeners();
  }
}
