import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/crew_member.dart';
import 'signalk_service.dart';
import 'storage_service.dart';

/// Service for managing crew identity, presence, and communication
class CrewService extends ChangeNotifier {
  final SignalKService _signalKService;
  final StorageService _storageService;

  // Local crew profile
  CrewMember? _localProfile;
  CrewMember? get localProfile => _localProfile;

  // Online crew members (including self)
  final Map<String, CrewMember> _crewMembers = {};
  Map<String, CrewMember> get crewMembers => Map.unmodifiable(_crewMembers);

  // Presence tracking
  final Map<String, CrewPresence> _presence = {};
  Map<String, CrewPresence> get presence => Map.unmodifiable(_presence);

  // Heartbeat timer
  Timer? _heartbeatTimer;
  static const Duration _heartbeatInterval = Duration(seconds: 30);
  static const Duration _presenceTimeout = Duration(seconds: 60);

  // Track connection state to avoid duplicate handlers
  bool _wasConnected = false;

  // Resources API type for crew data - uses custom resource type for isolation
  static const String _crewResourceType = 'zeddisplay-crew';

  // Polling timer for fetching crew updates
  Timer? _pollTimer;
  static const Duration _pollInterval = Duration(seconds: 15);

  // Track if Resources API is available
  bool _resourcesApiAvailable = true;

  // Storage keys
  static const String _localProfileKey = 'crew_local_profile';
  static const String _deviceIdKey = 'crew_device_id';

  CrewService(this._signalKService, this._storageService);

  /// Initialize the crew service
  Future<void> initialize() async {
    // Load local profile from storage
    await _loadLocalProfile();

    // Listen to SignalK connection changes
    _signalKService.addListener(_onSignalKChanged);

    // If already connected, start presence
    if (_signalKService.isConnected) {
      await _onConnected();
    }

    if (kDebugMode) {
      print('CrewService initialized');
    }
  }

  /// Clean up resources
  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _pollTimer?.cancel();
    _signalKService.removeListener(_onSignalKChanged);
    super.dispose();
  }

  /// Get or generate a unique device ID
  Future<String> _getDeviceId() async {
    String? deviceId = _storageService.getSetting(_deviceIdKey);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await _storageService.saveSetting(_deviceIdKey, deviceId);
    }
    return deviceId;
  }

  /// Load local profile from storage
  Future<void> _loadLocalProfile() async {
    final profileJson = _storageService.getSetting(_localProfileKey);
    if (profileJson != null) {
      try {
        final map = jsonDecode(profileJson) as Map<String, dynamic>;
        _localProfile = CrewMember.fromJson(map);
        if (kDebugMode) {
          print('Loaded local crew profile: ${_localProfile?.name}');
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error loading crew profile: $e');
        }
      }
    }
  }

  /// Save local profile to storage
  Future<void> _saveLocalProfile() async {
    if (_localProfile != null) {
      final json = jsonEncode(_localProfile!.toJson());
      await _storageService.saveSetting(_localProfileKey, json);
    }
  }

  /// Check if user has set up a crew profile
  bool get hasProfile => _localProfile != null;

  /// Create or update the local crew profile
  Future<void> setProfile({
    required String name,
    CrewRole role = CrewRole.crew,
    CrewStatus status = CrewStatus.offWatch,
    String? avatar,
  }) async {
    final deviceId = await _getDeviceId();

    if (_localProfile == null) {
      // Create new profile
      _localProfile = CrewMember(
        id: const Uuid().v4(),
        name: name,
        role: role,
        status: status,
        deviceId: deviceId,
        avatar: avatar,
      );
    } else {
      // Update existing profile
      _localProfile = _localProfile!.copyWith(
        name: name,
        role: role,
        status: status,
        avatar: avatar,
      );
    }

    await _saveLocalProfile();
    notifyListeners();

    // Announce presence if connected
    if (_signalKService.isConnected) {
      await _announcePresence();
    }

    if (kDebugMode) {
      print('Crew profile updated: $name ($role)');
    }
  }

  /// Update status only
  Future<void> setStatus(CrewStatus status) async {
    if (_localProfile != null) {
      _localProfile = _localProfile!.copyWith(status: status);
      await _saveLocalProfile();
      notifyListeners();

      if (_signalKService.isConnected) {
        await _announcePresence();
      }
    }
  }

  /// Handle SignalK connection changes
  void _onSignalKChanged() {
    final isConnected = _signalKService.isConnected;

    // Only handle actual state changes
    if (isConnected == _wasConnected) return;
    _wasConnected = isConnected;

    if (isConnected) {
      _onConnected();
    } else {
      _onDisconnected();
    }
  }

  /// Handle connection to SignalK
  Future<void> _onConnected() async {
    if (kDebugMode) {
      print('CrewService: SignalK connected');
    }

    // Ensure custom resource type exists on server
    await _ensureResourceType();

    // Start heartbeat timer
    _startHeartbeat();

    // Start polling for crew updates
    _startPolling();

    // Announce our presence
    if (_localProfile != null) {
      await _announcePresence();
    }

    // Fetch existing crew members
    await _fetchCrewMembers();
  }

  /// Ensure the custom resource type exists on the server
  Future<void> _ensureResourceType() async {
    await _signalKService.ensureResourceTypeExists(
      _crewResourceType,
      description: 'ZedDisplay crew profiles and presence',
    );
  }

  /// Handle disconnection from SignalK
  void _onDisconnected() {
    if (kDebugMode) {
      print('CrewService: SignalK disconnected');
    }

    // Stop heartbeat and polling
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;

    // Mark all crew as offline
    for (final crewId in _presence.keys) {
      _presence[crewId] = _presence[crewId]!.copyWith(online: false);
    }
    notifyListeners();
  }

  /// Start the heartbeat timer
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      _sendHeartbeat();
      _pruneStalePresence();
    });
  }

  /// Start polling for crew updates
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      _fetchCrewMembers();
    });
  }

  /// Build a notes resource from crew member data
  Map<String, dynamic> _buildCrewNoteResource(CrewMember member, DateTime lastSeen) {
    // Store crew data as JSON in description field
    final crewData = {
      ...member.toJson(),
      'lastSeen': lastSeen.toIso8601String(),
    };

    // Get current vessel position if available, otherwise use 0,0
    final posData = _signalKService.getValue('navigation.position');
    double lat = 0.0;
    double lng = 0.0;
    if (posData?.value is Map) {
      final pos = posData!.value as Map;
      lat = (pos['latitude'] as num?)?.toDouble() ?? 0.0;
      lng = (pos['longitude'] as num?)?.toDouble() ?? 0.0;
    }

    return {
      'name': '${member.name} (${member.roleDisplay})',
      'description': jsonEncode(crewData),
      'position': {
        'latitude': lat,
        'longitude': lng,
      },
    };
  }

  /// Send heartbeat to SignalK via Resources API
  Future<void> _sendHeartbeat() async {
    if (_localProfile == null || !_signalKService.isConnected) return;

    final now = DateTime.now();

    // Update local presence
    _presence[_localProfile!.id] = CrewPresence(
      crewId: _localProfile!.id,
      online: true,
      lastSeen: now,
    );

    // Sync to SignalK Resources API if available
    if (_resourcesApiAvailable) {
      final resourceData = _buildCrewNoteResource(_localProfile!, now);

      final success = await _signalKService.putResource(
        _crewResourceType,
        _localProfile!.id,
        resourceData,
      );

      if (!success && kDebugMode) {
        print('Failed to sync crew heartbeat to Resources API');
      }
    }

    notifyListeners();
  }

  /// Announce our presence with full profile via Resources API
  Future<void> _announcePresence() async {
    if (_localProfile == null || !_signalKService.isConnected) return;

    final now = DateTime.now();

    // Add ourselves to local cache
    _crewMembers[_localProfile!.id] = _localProfile!;
    _presence[_localProfile!.id] = CrewPresence(
      crewId: _localProfile!.id,
      online: true,
      lastSeen: now,
    );

    // Sync to SignalK Resources API (using notes format)
    final resourceData = _buildCrewNoteResource(_localProfile!, now);

    final success = await _signalKService.putResource(
      _crewResourceType,
      _localProfile!.id,
      resourceData,
    );

    if (success) {
      _resourcesApiAvailable = true;
      if (kDebugMode) {
        print('Crew profile synced via Resources API: ${_localProfile!.name}');
      }
    } else {
      // Resources API might not be available - fall back to local-only
      _resourcesApiAvailable = false;
      if (kDebugMode) {
        print('Resources API not available - crew sync is local-only');
      }
    }

    notifyListeners();
  }

  /// Fetch crew members from Resources API
  Future<void> _fetchCrewMembers() async {
    if (!_signalKService.isConnected || !_resourcesApiAvailable) return;

    try {
      final resources = await _signalKService.getResources(_crewResourceType);

      if (resources.isEmpty) {
        // No notes resources found
        return;
      }

      final now = DateTime.now();
      bool changed = false;

      for (final entry in resources.entries) {
        final resourceId = entry.key;
        final resourceData = entry.value as Map<String, dynamic>;

        // Skip our own profile (we already have it locally)
        if (resourceId == _localProfile?.id) continue;

        try {
          // Parse crew data from description field (JSON string)
          final descriptionJson = resourceData['description'] as String?;
          if (descriptionJson == null) continue;

          final crewData = jsonDecode(descriptionJson) as Map<String, dynamic>;

          // Parse crew member
          final member = CrewMember.fromJson(crewData);
          _crewMembers[resourceId] = member;

          // Parse presence data
          final lastSeenStr = crewData['lastSeen'] as String?;
          final lastSeen = lastSeenStr != null
              ? DateTime.tryParse(lastSeenStr) ?? now
              : now;

          final isOnline = now.difference(lastSeen) < _presenceTimeout;

          _presence[resourceId] = CrewPresence(
            crewId: resourceId,
            online: isOnline,
            lastSeen: lastSeen,
          );

          changed = true;
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing crew resource $resourceId: $e');
          }
        }
      }

      if (changed) {
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching crew members: $e');
      }
    }
  }

  /// Remove stale presence entries
  void _pruneStalePresence() {
    final now = DateTime.now();
    bool changed = false;

    for (final entry in _presence.entries) {
      if (entry.value.online &&
          now.difference(entry.value.lastSeen) > _presenceTimeout) {
        _presence[entry.key] = entry.value.copyWith(online: false);
        changed = true;
        if (kDebugMode) {
          print('Crew member ${entry.key} marked as offline (stale)');
        }
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  /// Get list of online crew members
  List<CrewMember> get onlineCrew {
    return _crewMembers.values
        .where((member) =>
            _presence[member.id]?.online == true)
        .toList();
  }

  /// Get list of offline crew members
  List<CrewMember> get offlineCrew {
    return _crewMembers.values
        .where((member) =>
            _presence[member.id]?.online != true)
        .toList();
  }

  /// Check if Resources API is available for crew sync
  bool get isResourcesApiAvailable => _resourcesApiAvailable;

  /// Check if current user can delete a crew member
  /// Rules: Captain can delete anyone, self can delete self
  bool canDelete(String crewId) {
    if (_localProfile == null) return false;

    // Self can always delete self
    if (crewId == _localProfile!.id) return true;

    // Captain can delete anyone
    if (_localProfile!.role == CrewRole.captain) return true;

    return false;
  }

  /// Delete a crew member from the server
  /// Returns true if successful
  Future<bool> deleteCrewMember(String crewId) async {
    if (!canDelete(crewId)) {
      if (kDebugMode) {
        print('CrewService: Not authorized to delete crew member $crewId');
      }
      return false;
    }

    if (!_signalKService.isConnected || !_resourcesApiAvailable) {
      if (kDebugMode) {
        print('CrewService: Cannot delete - not connected or Resources API unavailable');
      }
      return false;
    }

    // Delete from SignalK Resources API
    final success = await _signalKService.deleteResource(_crewResourceType, crewId);

    if (success) {
      // Remove from local cache
      _crewMembers.remove(crewId);
      _presence.remove(crewId);

      // If deleting self, also clear local profile
      if (crewId == _localProfile?.id) {
        await clearLocalProfile();
      }

      notifyListeners();

      if (kDebugMode) {
        print('CrewService: Deleted crew member $crewId');
      }
    } else {
      if (kDebugMode) {
        print('CrewService: Failed to delete crew member $crewId from server');
      }
    }

    return success;
  }

  /// Clear the local profile (removes from device storage only)
  Future<void> clearLocalProfile() async {
    _localProfile = null;
    await _storageService.deleteSetting(_localProfileKey);

    // Stop heartbeat since we no longer have a profile
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    notifyListeners();

    if (kDebugMode) {
      print('CrewService: Local profile cleared');
    }
  }
}
