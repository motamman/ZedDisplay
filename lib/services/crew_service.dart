import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/crew_member.dart';
import '../models/auth_token.dart';
import 'signalk_service.dart';
import 'storage_service.dart';
import 'auth_service.dart';
import 'setup_service.dart';

/// Service for managing crew identity, presence, and communication
class CrewService extends ChangeNotifier {
  final SignalKService _signalKService;
  final StorageService _storageService;
  SetupService? _setupService;

  /// Set the setup service (called after initialization when SetupService is available)
  void setSetupService(SetupService setupService) {
    _setupService = setupService;
  }

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

  // Storage key prefixes
  static const String _userProfileKeyPrefix = 'crew_profile_user_';
  static const String _deviceProfileKeyPrefix = 'crew_profile_device_';
  static const String _deviceIdKey = 'crew_device_id';

  // Cached device ID for synchronous access
  String? _cachedDeviceId;

  // Track previous auth state for detecting login/logout transitions
  AuthType? _previousAuthType;
  String? _previousUsername;

  CrewService(this._signalKService, this._storageService, [this._setupService]);

  // Auth-aware profile identity helpers

  /// Get the current auth type from SignalK service
  AuthType get _authType =>
      _signalKService.authToken?.authType ?? AuthType.device;

  /// Get the username if using user authentication
  String? get _username => _signalKService.authToken?.username;

  /// Check if currently logged in as a user (vs device)
  bool get _isUserLogin => _authType == AuthType.user && _username != null;

  /// Get the profile identifier based on auth type
  /// Returns 'user:{username}' for user login, 'device:{deviceId}' for device login
  Future<String> _getProfileIdentifier() async {
    if (_isUserLogin) {
      return 'user:${_username!}';
    } else {
      final deviceId = await _getDeviceId();
      return 'device:$deviceId';
    }
  }

  /// Get storage key for the current auth context
  String _getStorageKey() {
    if (_isUserLogin) {
      return '$_userProfileKeyPrefix${_username!}';
    } else {
      // For device login, use cached device ID (must be loaded first)
      return '$_deviceProfileKeyPrefix${_cachedDeviceId ?? 'unknown'}';
    }
  }

  /// Initialize the crew service
  Future<void> initialize() async {
    // Cache device ID early for synchronous storage key access
    await _getDeviceId();

    // Track initial auth state
    _previousAuthType = _authType;
    _previousUsername = _username;

    // Load local profile from storage
    await _loadLocalProfile();

    // Register connection callback for sequential execution (prevents HTTP overload)
    _signalKService.registerConnectionCallback(_onConnected);

    // Listen to SignalK connection changes for disconnection and auth state changes
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
    _signalKService.unregisterConnectionCallback(_onConnected);
    _signalKService.removeListener(_onSignalKChanged);
    super.dispose();
  }

  /// Get or generate a unique device ID (also caches for synchronous access)
  Future<String> _getDeviceId() async {
    if (_cachedDeviceId != null) {
      return _cachedDeviceId!;
    }
    String? deviceId = _storageService.getSetting(_deviceIdKey);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await _storageService.saveSetting(_deviceIdKey, deviceId);
    }
    _cachedDeviceId = deviceId;
    return deviceId;
  }

  /// Get the device name (setup name or device model)
  Future<String?> _getDeviceName() async {
    try {
      // Try to get setup name first
      String? setupName;
      if (_setupService != null) {
        setupName = await _setupService!.getActiveSetupName();
      }
      // Generate device description (will use setup name or fall back to device model)
      final description = await AuthService.generateDeviceDescription(setupName: setupName);
      // Remove "ZedDisplay - " prefix if present to get just the identifier
      if (description.startsWith('ZedDisplay - ')) {
        return description.substring(13);
      }
      return description;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting device name: $e');
      }
      return null;
    }
  }

  /// Load local profile from storage based on current auth context
  Future<void> _loadLocalProfile() async {
    final storageKey = _getStorageKey();
    final profileJson = _storageService.getSetting(storageKey);

    if (profileJson != null) {
      try {
        final map = jsonDecode(profileJson) as Map<String, dynamic>;
        _localProfile = CrewMember.fromJson(map);
        if (kDebugMode) {
          print(
              'Loaded local crew profile: ${_localProfile?.name} (key: $storageKey)');
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error loading crew profile: $e');
        }
      }
    } else {
      _localProfile = null;
      if (kDebugMode) {
        print('No crew profile found for key: $storageKey');
      }
    }
  }

  /// Try to fetch user profile from server (for user login)
  /// Returns true if profile was loaded from server
  Future<bool> _fetchUserProfileFromServer() async {
    if (!_isUserLogin || !_signalKService.isConnected || !_resourcesApiAvailable) {
      return false;
    }

    try {
      final profileId = await _getProfileIdentifier();
      final resources = await _signalKService.getResources(_crewResourceType);

      for (final entry in resources.entries) {
        if (entry.key == profileId) {
          final resourceData = entry.value as Map<String, dynamic>;
          final descriptionJson = resourceData['description'] as String?;
          if (descriptionJson == null) continue;

          final crewData = jsonDecode(descriptionJson) as Map<String, dynamic>;
          _localProfile = CrewMember.fromJson(crewData);

          // Save to local storage for offline access
          await _saveLocalProfile();

          if (kDebugMode) {
            print('Loaded user profile from server: ${_localProfile?.name}');
          }
          return true;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching user profile from server: $e');
      }
    }
    return false;
  }

  /// Save local profile to storage (uses auth-aware storage key)
  Future<void> _saveLocalProfile() async {
    if (_localProfile != null) {
      final storageKey = _getStorageKey();
      final json = jsonEncode(_localProfile!.toJson());
      await _storageService.saveSetting(storageKey, json);
      if (kDebugMode) {
        print('Saved crew profile to: $storageKey');
      }
    }
  }

  /// Check if user has set up a crew profile
  bool get hasProfile => _localProfile != null;

  /// Create or update the local crew profile
  /// Profile ID is based on auth type: 'user:{username}' or 'device:{deviceId}'
  Future<void> setProfile({
    required String name,
    CrewRole role = CrewRole.crew,
    CrewStatus status = CrewStatus.offWatch,
    String? avatar,
  }) async {
    final profileId = await _getProfileIdentifier();
    final deviceId = await _getDeviceId();
    final deviceName = await _getDeviceName();

    if (_localProfile == null) {
      // Create new profile with auth-aware ID
      _localProfile = CrewMember(
        id: profileId,
        name: name,
        role: role,
        status: status,
        deviceId: deviceId,
        deviceName: deviceName,
        avatar: avatar,
      );
    } else {
      // Update existing profile
      // Update ID if it doesn't match current auth context (shouldn't happen normally)
      final newId = _localProfile!.id == profileId ? profileId : profileId;
      _localProfile = _localProfile!.copyWith(
        id: newId,
        name: name,
        role: role,
        status: status,
        deviceName: deviceName,
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
      print('Crew profile updated: $name ($role) [id: $profileId]');
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

  /// Handle SignalK connection changes and auth state transitions
  /// Connection is handled via registerConnectionCallback for sequential execution
  void _onSignalKChanged() {
    final isConnected = _signalKService.isConnected;
    final currentAuthType = _authType;
    final currentUsername = _username;

    // Check for auth state change (login/logout or user switch)
    final authChanged = currentAuthType != _previousAuthType ||
        (currentAuthType == AuthType.user && currentUsername != _previousUsername);

    if (authChanged) {
      if (kDebugMode) {
        print('CrewService: Auth state changed from $_previousAuthType/$_previousUsername '
            'to $currentAuthType/$currentUsername');
      }
      _previousAuthType = currentAuthType;
      _previousUsername = currentUsername;

      // Handle the auth transition
      _handleAuthTransition();
    }

    // Handle connection state changes
    if (isConnected == _wasConnected) return;
    _wasConnected = isConnected;

    // Only handle disconnection here - connection is handled via callback
    if (!isConnected) {
      _onDisconnected();
    }
  }

  /// Handle auth state transitions (login/logout, user switch)
  Future<void> _handleAuthTransition() async {
    // Clear current profile - we'll load the appropriate one
    _localProfile = null;

    // Load profile for new auth context
    await _loadLocalProfile();

    // If user login and connected, try to fetch profile from server
    if (_isUserLogin && _signalKService.isConnected) {
      if (_localProfile == null) {
        // No local profile, try server
        await _fetchUserProfileFromServer();
      }
      // If still no profile, user will need to create one
    }

    notifyListeners();

    // Re-announce presence with new identity if connected and have profile
    if (_signalKService.isConnected && _localProfile != null) {
      await _announcePresence();
    }
  }

  /// Handle connection to SignalK
  Future<void> _onConnected() async {
    if (kDebugMode) {
      print('CrewService: SignalK connected (auth: $_authType, user: $_username)');
    }

    // Ensure custom resource type exists on server
    await _ensureResourceType();

    // For user login, try to fetch profile from server if we don't have one locally
    if (_isUserLogin && _localProfile == null) {
      final fetched = await _fetchUserProfileFromServer();
      if (fetched) {
        notifyListeners();
      }
    }

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

          // Parse crew member - use resourceId as canonical ID to match presence
          final member = CrewMember.fromJson(crewData);
          // Ensure member ID matches resource ID (in case JSON has old UUID)
          final normalizedMember = member.id != resourceId
              ? member.copyWith(id: resourceId)
              : member;
          _crewMembers[resourceId] = normalizedMember;

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

  /// Get list of online crew members (deduplicated by ID)
  List<CrewMember> get onlineCrew {
    if (kDebugMode && _crewMembers.isNotEmpty) {
      print('CrewService: _crewMembers has ${_crewMembers.length} entries: ${_crewMembers.keys.toList()}');
    }
    final seen = <String>{};
    return _crewMembers.values
        .where((member) =>
            _presence[member.id]?.online == true &&
            seen.add(member.id)) // add returns false if already present
        .toList();
  }

  /// Get list of offline crew members (deduplicated by ID)
  List<CrewMember> get offlineCrew {
    final seen = <String>{};
    return _crewMembers.values
        .where((member) =>
            _presence[member.id]?.online != true &&
            seen.add(member.id)) // add returns false if already present
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
    final storageKey = _getStorageKey();
    _localProfile = null;
    await _storageService.deleteSetting(storageKey);

    // Stop heartbeat since we no longer have a profile
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    notifyListeners();

    if (kDebugMode) {
      print('CrewService: Local profile cleared (key: $storageKey)');
    }
  }
}
