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

  // Set of crew IDs we're tracking via WS
  final Set<String> _trackedCrewIds = {};

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
  }

  /// Clean up resources
  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _signalKService.unsubscribeFromPaths(['crew.*'], ownerId: 'crew');
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
      } catch (_) {
        // Ignore profile load errors
      }
    } else {
      _localProfile = null;
    }
  }

  /// Try to fetch user profile from server
  /// Returns true if profile was loaded from server
  Future<bool> _fetchUserProfileFromServer() async {
    if (!_signalKService.isConnected || !_resourcesApiAvailable) return false;

    try {
      final profileId = await _getProfileIdentifier();
      final resources = await _signalKService.getResources(_crewResourceType);

      for (final entry in resources.entries) {
        final key = entry.key;
        // Flexible key matching - handle URL-encoded keys
        final keyMatches = key == profileId || Uri.decodeComponent(key) == profileId;

        if (keyMatches) {
          final resourceData = entry.value as Map<String, dynamic>;
          final descriptionJson = resourceData['description'] as String?;
          if (descriptionJson == null) continue;

          final crewData = jsonDecode(descriptionJson) as Map<String, dynamic>;
          _localProfile = CrewMember.fromJson(crewData);

          // Save to local storage for offline access
          await _saveLocalProfile();
          return true;
        }

        // Also check by profile ID in the crew data
        try {
          final resourceData = entry.value as Map<String, dynamic>;
          final descriptionJson = resourceData['description'] as String?;
          if (descriptionJson != null) {
            final crewData = jsonDecode(descriptionJson) as Map<String, dynamic>;
            if (crewData['id'] == profileId) {
              _localProfile = CrewMember.fromJson(crewData);
              await _saveLocalProfile();
              return true;
            }
          }
        } catch (_) {}
      }
    } catch (_) {
      // Ignore fetch errors
    }
    return false;
  }

  /// Save local profile to storage (uses auth-aware storage key)
  Future<void> _saveLocalProfile() async {
    if (_localProfile != null) {
      final storageKey = _getStorageKey();
      final json = jsonEncode(_localProfile!.toJson());
      await _storageService.saveSetting(storageKey, json);
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
  }

  /// Update status only
  Future<void> setStatus(CrewStatus status) async {
    if (_localProfile != null) {
      _localProfile = _localProfile!.copyWith(status: status);
      _crewMembers[_localProfile!.id] = _localProfile!;
      await _saveLocalProfile();
      notifyListeners();

      if (_signalKService.isConnected) {
        // Broadcast status via WS delta first (seeds cache before announcePresence round-trip)
        _signalKService.sendDelta(
          '${_crewPath(_localProfile!.id)}.status',
          _statusToJsonString(status),
        );

        // Persist full profile to Resources API
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
      _previousAuthType = currentAuthType;
      _previousUsername = currentUsername;

      // Handle the auth transition
      _handleAuthTransition();
    }

    // Handle connection state changes
    if (isConnected != _wasConnected) {
      _wasConnected = isConnected;

      // Only handle disconnection here - connection is handled via callback
      if (!isConnected) {
        _onDisconnected();
      }
    }

    // Process crew WS deltas while connected
    if (isConnected) {
      _processCrewDeltas();
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
    // Ensure custom resource type exists on server
    await _ensureResourceType();

    // Validate profile against server FIRST - server is source of truth
    final validated = await _validateProfileWithServer();

    // Fetch existing crew members (one-time hydration from Resources API)
    await _fetchCrewMembers();

    // Subscribe to crew paths for real-time updates via WS
    await _signalKService.subscribeToPaths(['crew.*'], ownerId: 'crew');

    // Populate tracked IDs from initial fetch
    _trackedCrewIds.clear();
    _trackedCrewIds.addAll(_crewMembers.keys);
    if (_localProfile != null) _trackedCrewIds.add(_localProfile!.id);

    if (validated && _localProfile != null) {
      // Start heartbeat timer
      _startHeartbeat();

      // Announce our presence only after server validation
      await _announcePresence();
    }
  }

  /// Validate local profile against server
  /// Server is source of truth - if profile doesn't exist on server, clear local cache
  /// Returns true if profile is valid (exists on server or was fetched from server)
  Future<bool> _validateProfileWithServer() async {
    if (!_signalKService.isConnected || !_resourcesApiAvailable) {
      // Can't validate - keep local state but don't announce
      return false;
    }

    try {
      final profileId = await _getProfileIdentifier();
      final resources = await _signalKService.getResources(_crewResourceType);

      // Check if server has this profile - be flexible with key matching
      // Resource keys may be URL-encoded (e.g., "user%3Amaurice" vs "user:maurice")
      // Also handle legacy format where key might be just username instead of "user:username"
      String? matchingKey;
      final username = _username; // For user login, extract username for flexible matching

      for (final key in resources.keys) {
        // Check exact match or URL-decoded match
        if (key == profileId || Uri.decodeComponent(key) == profileId) {
          matchingKey = key;
          break;
        }

        // For user login, also match if key is just the username (legacy format)
        if (_isUserLogin && username != null) {
          if (key == username || Uri.decodeComponent(key) == username) {
            matchingKey = key;
            break;
          }
        }

        // Also check the profile ID inside the resource data
        try {
          final resourceData = resources[key] as Map<String, dynamic>;
          final descriptionJson = resourceData['description'] as String?;
          if (descriptionJson != null) {
            final crewData = jsonDecode(descriptionJson) as Map<String, dynamic>;
            final embeddedId = crewData['id'] as String?;
            // Match exact ID or legacy username format
            if (embeddedId == profileId ||
                (_isUserLogin && username != null && embeddedId == username)) {
              matchingKey = key;
              break;
            }
          }
        } catch (_) {}
      }

      if (matchingKey != null) {
        // Server has this profile - load it to ensure we have latest data
        final loaded = await _fetchUserProfileFromServer();

        // Fallback: if fetch failed but we found the profile, load it directly
        if (!loaded && _localProfile == null) {
          try {
            final resourceData = resources[matchingKey] as Map<String, dynamic>;
            final descriptionJson = resourceData['description'] as String?;
            if (descriptionJson != null) {
              final crewData = jsonDecode(descriptionJson) as Map<String, dynamic>;
              _localProfile = CrewMember.fromJson(crewData);
              await _saveLocalProfile();
            }
          } catch (_) {
            // Ignore fallback load errors
          }
        }

        return _localProfile != null;
      } else {
        // Server does NOT have this profile - clear local cache
        // This prevents auto-pushing stale local profiles to server
        if (_localProfile != null) {
          _localProfile = null;
          await _storageService.deleteSetting(_getStorageKey());
          notifyListeners();
        }
        return false;
      }
    } catch (_) {
      // On error, don't clear local profile but don't announce either
      return false;
    }
  }

  /// Ensure the custom resource type exists on the server
  Future<bool> _ensureResourceType() async {
    return await _signalKService.ensureResourceTypeExists(
      _crewResourceType,
      description: 'ZedDisplay crew profiles and presence',
    );
  }

  /// Handle disconnection from SignalK
  void _onDisconnected() {
    // Stop heartbeat
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    // Unsubscribe from crew paths
    _signalKService.unsubscribeFromPaths(['crew.*'], ownerId: 'crew');

    // Mark all crew as offline
    for (final crewId in _presence.keys) {
      _presence[crewId] = _presence[crewId]!.copyWith(online: false);
    }
    notifyListeners();
  }

  /// Start the heartbeat timer, offset 15s from poll start.
  /// Poll fires at T=0,30,60..., heartbeat at T=15,45,75...
  /// This ensures _localProfile is fresh from the last poll before we PUT.
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    Future.delayed(const Duration(seconds: 15), () {
      if (!_signalKService.isConnected || _localProfile == null) return;
      _sendHeartbeat();
      _pruneStalePresence();
      _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
        _sendHeartbeat();
        _pruneStalePresence();
      });
    });
  }

  /// Build SignalK path prefix for a crew member
  String _crewPath(String crewId) => 'crew.$crewId';

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

  /// Send heartbeat via WS delta (broadcasts lastSeen to all subscribed clients)
  void _sendHeartbeat() {
    if (_localProfile == null || !_signalKService.isConnected) return;

    final now = DateTime.now();

    // Update local presence
    _presence[_localProfile!.id] = CrewPresence(
      crewId: _localProfile!.id,
      online: true,
      lastSeen: now,
    );

    // PUT crew.<id>.lastSeen — broadcasts to all subscribed clients via WS
    _signalKService.sendDelta(
      '${_crewPath(_localProfile!.id)}.lastSeen',
      now.toIso8601String(),
    );

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

    _resourcesApiAvailable = success;
    notifyListeners();
  }

  /// Fetch crew members from Resources API
  Future<void> _fetchCrewMembers() async {
    if (!_signalKService.isConnected || !_resourcesApiAvailable) return;

    try {
      final resources = await _signalKService.getResources(_crewResourceType);
      if (resources.isEmpty) return;

      final now = DateTime.now();
      bool changed = false;

      for (final entry in resources.entries) {
        final resourceId = entry.key;
        final resourceData = entry.value as Map<String, dynamic>;

        // Skip own resource — we trust local profile
        if (resourceId == _localProfile?.id ||
            (_isUserLogin && _username != null && resourceId == _username) ||
            (_localProfile != null && resourceId == Uri.decodeComponent(_localProfile!.id))) {
          continue;
        }

        try {
          // Parse crew data from description field (JSON string)
          final descriptionJson = resourceData['description'] as String?;
          if (descriptionJson == null) continue;

          final crewData = jsonDecode(descriptionJson) as Map<String, dynamic>;

          // Parse crew member
          final member = CrewMember.fromJson(crewData);

          // Use the embedded ID if it's in the new format (user: or device:)
          // Otherwise fall back to resource key
          final useEmbeddedId = member.id.startsWith('user:') || member.id.startsWith('device:');
          final canonicalId = useEmbeddedId ? member.id : resourceId;
          final normalizedMember = member.id != canonicalId
              ? member.copyWith(id: canonicalId)
              : member;
          _crewMembers[canonicalId] = normalizedMember;

          // Parse presence data
          final lastSeenStr = crewData['lastSeen'] as String?;
          final lastSeen = lastSeenStr != null
              ? DateTime.tryParse(lastSeenStr) ?? now
              : now;

          final isOnline = now.difference(lastSeen) < _presenceTimeout;

          // Store presence using canonicalId to match crew member lookup
          _presence[canonicalId] = CrewPresence(
            crewId: canonicalId,
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

      // Seed crew paths on server for WS subscription
      for (final member in _crewMembers.values) {
        _signalKService.sendDelta(
          '${_crewPath(member.id)}.status',
          _statusToJsonString(member.status),
        );
      }
      // Also seed own lastSeen
      if (_localProfile != null) {
        _signalKService.sendDelta(
          '${_crewPath(_localProfile!.id)}.lastSeen',
          DateTime.now().toIso8601String(),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching crew members: $e');
      }
    }
  }

  /// Process crew WS deltas for real-time status and presence updates
  void _processCrewDeltas() {
    bool changed = false;
    final now = DateTime.now();

    // Check known crew members for status/lastSeen updates
    // Skip own crew ID — we are the authority for our own status
    for (final crewId in _trackedCrewIds) {
      if (crewId == _localProfile?.id) continue;

      final prefix = _crewPath(crewId);

      // Check status delta
      final statusPoint = _signalKService.getValue('$prefix.status');
      if (statusPoint != null) {
        final statusStr = statusPoint.value as String?;
        if (statusStr != null) {
          final newStatus = _parseCrewStatus(statusStr);
          final existing = _crewMembers[crewId];
          if (existing != null && newStatus != null && existing.status != newStatus) {
            _crewMembers[crewId] = existing.copyWith(status: newStatus);
            changed = true;
          }
        }
      }

      // Check lastSeen delta (heartbeat)
      final lastSeenPoint = _signalKService.getValue('$prefix.lastSeen');
      if (lastSeenPoint != null) {
        final lastSeenStr = lastSeenPoint.value as String?;
        final lastSeen = lastSeenStr != null ? DateTime.tryParse(lastSeenStr) : null;
        if (lastSeen != null) {
          final isOnline = now.difference(lastSeen) < _presenceTimeout;
          final currentPresence = _presence[crewId];
          if (currentPresence == null || currentPresence.lastSeen != lastSeen) {
            _presence[crewId] = CrewPresence(
              crewId: crewId,
              online: isOnline,
              lastSeen: lastSeen,
            );
            changed = true;
          }
        }
      }
    }

    // Detect new crew members (unknown paths in data cache)
    _detectNewCrewMembers();

    if (changed) {
      notifyListeners();
    }
  }

  /// Detect new crew members from unknown delta paths in data cache
  void _detectNewCrewMembers() {
    final latestData = _signalKService.latestData;
    final newIds = <String>{};

    for (final path in latestData.keys) {
      if (path.startsWith('crew.')) {
        // Extract crew ID: crew.<id>.status or crew.<id>.lastSeen
        final parts = path.split('.');
        if (parts.length >= 2) {
          final crewId = parts[1];
          if (!_trackedCrewIds.contains(crewId)) {
            newIds.add(crewId);
          }
        }
      }
    }

    if (newIds.isNotEmpty) {
      _trackedCrewIds.addAll(newIds);
      // Fetch full profiles from Resources API for unknown members
      _fetchCrewMembers();
    }
  }

  /// Parse a JSON status string to CrewStatus enum
  CrewStatus? _parseCrewStatus(String statusStr) {
    switch (statusStr) {
      case 'on_watch':
        return CrewStatus.onWatch;
      case 'off_watch':
        return CrewStatus.offWatch;
      case 'standby':
        return CrewStatus.standby;
      case 'resting':
        return CrewStatus.resting;
      case 'away':
        return CrewStatus.away;
      default:
        return null;
    }
  }

  /// Convert CrewStatus to its JSON string value
  String _statusToJsonString(CrewStatus status) {
    switch (status) {
      case CrewStatus.onWatch:
        return 'on_watch';
      case CrewStatus.offWatch:
        return 'off_watch';
      case CrewStatus.standby:
        return 'standby';
      case CrewStatus.resting:
        return 'resting';
      case CrewStatus.away:
        return 'away';
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

  /// Delete my profile from server and clear local cache
  /// Use this when user explicitly wants to remove their profile
  Future<bool> deleteMyProfile() async {
    if (_localProfile == null) return true; // Already no profile

    final profileId = _localProfile!.id;

    // Remove from server if connected
    if (_signalKService.isConnected && _resourcesApiAvailable) {
      final success = await _signalKService.deleteResource(_crewResourceType, profileId);
      if (!success) {
        if (kDebugMode) {
          print('CrewService: Failed to delete profile from server: $profileId');
        }
        return false;
      }
    }

    // Clear local cache
    await clearLocalProfile();

    // Remove from crew members map
    _crewMembers.remove(profileId);
    _presence.remove(profileId);

    notifyListeners();

    if (kDebugMode) {
      print('CrewService: Deleted my profile: $profileId');
    }

    return true;
  }

  /// Clear ALL local crew caches (nuclear option for troubleshooting)
  /// This clears all crew-related storage but does NOT remove profiles from server
  Future<void> clearAllLocalCrewData() async {
    // Clear current profile
    _localProfile = null;

    // Stop timers
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    // Clear all crew-related storage keys
    final allSettings = _storageService.getAllSettings();
    for (final key in allSettings.keys) {
      if (key.startsWith('crew_profile_') ||
          key.startsWith(_userProfileKeyPrefix) ||
          key.startsWith(_deviceProfileKeyPrefix) ||
          key == _deviceIdKey) {
        await _storageService.deleteSetting(key);
      }
    }

    // Clear cached device ID so a new one is generated
    _cachedDeviceId = null;

    // Clear in-memory state
    _crewMembers.clear();
    _presence.clear();

    notifyListeners();

    if (kDebugMode) {
      print('CrewService: Cleared all local crew data');
    }
  }
}
