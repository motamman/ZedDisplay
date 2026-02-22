import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/dashboard_layout.dart';
import '../models/dashboard_setup.dart';
import '../models/auth_token.dart';
import '../models/server_connection.dart';

/// Service for local storage of dashboards, templates, and configurations
class StorageService extends ChangeNotifier {
  static const String _dashboardsBoxName = 'dashboards';
  static const String _templatesBoxName = 'templates';
  static const String _settingsBoxName = 'settings';
  static const String _authTokenBoxName = 'authTokens';
  static const String _connectionsBoxName = 'connections';
  static const String _setupsBoxName = 'saved_setups';
  static const String _conversionsBoxName = 'conversions_cache';
  static const String _startupScreenIdKey = 'startup_screen_id';

  late Box<String> _dashboardsBox;
  late Box<String> _templatesBox;
  late Box<String> _settingsBox;
  late Box<String> _authTokenBox;
  late Box<String> _connectionsBox;
  late Box<String> _setupsBox;
  late Box<String> _conversionsBox;

  bool _initialized = false;
  bool get initialized => _initialized;

  /// Initialize Hive and open boxes
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Hive.initFlutter();

      _dashboardsBox = await Hive.openBox<String>(_dashboardsBoxName);
      _templatesBox = await Hive.openBox<String>(_templatesBoxName);
      _settingsBox = await Hive.openBox<String>(_settingsBoxName);
      _authTokenBox = await Hive.openBox<String>(_authTokenBoxName);
      _connectionsBox = await Hive.openBox<String>(_connectionsBoxName);
      _setupsBox = await Hive.openBox<String>(_setupsBoxName);
      _conversionsBox = await Hive.openBox<String>(_conversionsBoxName);

      _initialized = true;
      notifyListeners();

      if (kDebugMode) {
        print('StorageService initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing StorageService: $e');
      }
      rethrow;
    }
  }

  /// Close all boxes
  @override
  Future<void> dispose() async {
    await _dashboardsBox.close();
    await _templatesBox.close();
    await _settingsBox.close();
    await _authTokenBox.close();
    await _connectionsBox.close();
    await _setupsBox.close();
    await _conversionsBox.close();
    super.dispose();
  }

  // ===== Dashboard Management =====

  /// Save a dashboard layout
  Future<void> saveDashboard(DashboardLayout layout) async {
    if (!_initialized) throw Exception('StorageService not initialized');

    try {
      final json = jsonEncode(layout.toJson());
      await _dashboardsBox.put(layout.id, json);
      notifyListeners();

    } catch (e) {
      if (kDebugMode) {
        print('Error saving dashboard: $e');
      }
      rethrow;
    }
  }

  /// Load a specific dashboard by ID
  Future<DashboardLayout?> loadDashboard(String id) async {
    if (!_initialized) throw Exception('StorageService not initialized');

    try {
      final json = _dashboardsBox.get(id);
      if (json != null) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        return DashboardLayout.fromJson(map);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading dashboard $id: $e');
      }
    }
    return null;
  }

  /// Load all dashboards
  Future<List<DashboardLayout>> loadAllDashboards() async {
    if (!_initialized) throw Exception('StorageService not initialized');

    final dashboards = <DashboardLayout>[];

    for (final json in _dashboardsBox.values) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        dashboards.add(DashboardLayout.fromJson(map));
      } catch (e) {
        if (kDebugMode) {
          print('Error parsing dashboard: $e');
        }
      }
    }

    return dashboards;
  }

  /// Delete a dashboard
  Future<void> deleteDashboard(String id) async {
    if (!_initialized) throw Exception('StorageService not initialized');

    await _dashboardsBox.delete(id);
    notifyListeners();

    if (kDebugMode) {
      print('Dashboard deleted: $id');
    }
  }

  /// Get the default dashboard (first one, or null if none exist)
  Future<DashboardLayout?> getDefaultDashboard() async {
    final dashboards = await loadAllDashboards();
    return dashboards.isNotEmpty ? dashboards.first : null;
  }

  /// Save the active dashboard ID
  Future<void> saveActiveDashboardId(String id) async {
    if (!_initialized) throw Exception('StorageService not initialized');
    await _settingsBox.put('active_dashboard_id', id);
  }

  /// Get the active dashboard ID
  String? getActiveDashboardId() {
    if (!_initialized) return null;
    return _settingsBox.get('active_dashboard_id');
  }

  // ===== Template Management =====

  /// Save a template (stored as JSON string)
  Future<void> saveTemplate(String templateId, Map<String, dynamic> templateData) async {
    if (!_initialized) throw Exception('StorageService not initialized');

    try {
      final json = jsonEncode(templateData);
      await _templatesBox.put(templateId, json);
      notifyListeners();

      if (kDebugMode) {
        print('Template saved: $templateId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving template: $e');
      }
      rethrow;
    }
  }

  /// Load a specific template by ID
  Future<Map<String, dynamic>?> loadTemplate(String templateId) async {
    if (!_initialized) throw Exception('StorageService not initialized');

    try {
      final json = _templatesBox.get(templateId);
      if (json != null) {
        return jsonDecode(json) as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading template $templateId: $e');
      }
    }
    return null;
  }

  /// Load all templates
  Future<List<Map<String, dynamic>>> loadAllTemplates() async {
    if (!_initialized) throw Exception('StorageService not initialized');

    final templates = <Map<String, dynamic>>[];

    for (final json in _templatesBox.values) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        templates.add(map);
      } catch (e) {
        if (kDebugMode) {
          print('Error parsing template: $e');
        }
      }
    }

    return templates;
  }

  /// Delete a template
  Future<void> deleteTemplate(String templateId) async {
    if (!_initialized) throw Exception('StorageService not initialized');

    await _templatesBox.delete(templateId);
    notifyListeners();

    if (kDebugMode) {
      print('Template deleted: $templateId');
    }
  }

  /// Check if a template exists
  bool templateExists(String templateId) {
    if (!_initialized) return false;
    return _templatesBox.containsKey(templateId);
  }

  // ===== Settings Management =====

  /// Save a generic setting
  Future<void> saveSetting(String key, String value) async {
    if (!_initialized) throw Exception('StorageService not initialized');
    await _settingsBox.put(key, value);
  }

  /// Get a generic setting
  String? getSetting(String key) {
    if (!_initialized) return null;
    return _settingsBox.get(key);
  }

  /// Delete a setting
  Future<void> deleteSetting(String key) async {
    if (!_initialized) throw Exception('StorageService not initialized');
    await _settingsBox.delete(key);
  }

  // ============ Startup Screen ============

  /// Get startup screen ID (null = use last viewed)
  String? get startupScreenId => _settingsBox.get(_startupScreenIdKey);

  /// Set startup screen ID (null to clear and use last viewed)
  Future<void> setStartupScreenId(String? screenId) async {
    if (screenId == null) {
      await _settingsBox.delete(_startupScreenIdKey);
    } else {
      await _settingsBox.put(_startupScreenIdKey, screenId);
    }
    notifyListeners();
  }

  // ===== Theme Settings =====

  /// Save theme mode preference
  Future<void> saveThemeMode(String mode) async {
    if (!_initialized) throw Exception('StorageService not initialized');
    await _settingsBox.put('theme_mode', mode);
    notifyListeners();

    if (kDebugMode) {
      print('Saved theme mode: $mode');
    }
  }

  /// Get theme mode preference (defaults to 'dark')
  String getThemeMode() {
    if (!_initialized) return 'dark';
    return _settingsBox.get('theme_mode', defaultValue: 'dark')!;
  }

  // ===== Connection Settings =====

  /// Save the last successful connection details
  Future<void> saveLastConnection(String serverUrl, bool useSecure) async {
    if (!_initialized) throw Exception('StorageService not initialized');
    await _settingsBox.put('last_server_url', serverUrl);
    await _settingsBox.put('last_use_secure', useSecure ? 'true' : 'false');

    if (kDebugMode) {
      print('Saved last connection: $serverUrl (secure: $useSecure)');
    }
  }

  /// Get the last connection server URL
  String? getLastServerUrl() {
    if (!_initialized) return null;
    return _settingsBox.get('last_server_url');
  }

  /// Get the last connection secure flag
  bool getLastUseSecure() {
    if (!_initialized) return false;
    return _settingsBox.get('last_use_secure') == 'true';
  }

  /// Clear last connection settings
  Future<void> clearLastConnection() async {
    if (!_initialized) throw Exception('StorageService not initialized');
    await _settingsBox.delete('last_server_url');
    await _settingsBox.delete('last_use_secure');

    if (kDebugMode) {
      print('Cleared last connection settings');
    }
  }

  // ===== Utility Methods =====

  /// Clear all data (dangerous!)
  Future<void> clearAllData() async {
    if (!_initialized) throw Exception('StorageService not initialized');

    await _dashboardsBox.clear();
    await _templatesBox.clear();
    await _settingsBox.clear();
    notifyListeners();

    if (kDebugMode) {
      print('All data cleared');
    }
  }

  /// Get storage statistics
  Map<String, int> getStorageStats() {
    if (!_initialized) return {};

    return {
      'dashboards': _dashboardsBox.length,
      'templates': _templatesBox.length,
      'settings': _settingsBox.length,
      'authTokens': _authTokenBox.length,
      'connections': _connectionsBox.length,
      'setups': _setupsBox.length,
      'conversions': _conversionsBox.length,
    };
  }

  // ===== Setup Management =====

  /// Save a complete dashboard setup (for saving/switching between setups)
  Future<void> saveSetup(DashboardSetup setup) async {
    if (!_initialized) throw Exception('StorageService not initialized');

    try {
      final json = jsonEncode(setup.toJson());
      await _setupsBox.put(setup.layout.id, json);
      notifyListeners();

      if (kDebugMode) {
        print('Setup saved: ${setup.metadata.name}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving setup: $e');
      }
      rethrow;
    }
  }

  /// Load a specific setup by ID
  Future<DashboardSetup?> loadSetup(String id) async {
    if (!_initialized) throw Exception('StorageService not initialized');

    try {
      final json = _setupsBox.get(id);
      if (json != null) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        return DashboardSetup.fromJson(map);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading setup $id: $e');
      }
    }
    return null;
  }

  /// Load all saved setups
  Future<List<DashboardSetup>> loadAllSetups() async {
    if (!_initialized) throw Exception('StorageService not initialized');

    final setups = <DashboardSetup>[];

    for (final json in _setupsBox.values) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        setups.add(DashboardSetup.fromJson(map));
      } catch (e) {
        if (kDebugMode) {
          print('Error parsing setup: $e');
        }
      }
    }

    // Sort by last used (most recent first), then by created date
    setups.sort((a, b) {
      final aLastUsed = a.metadata.updatedAt ?? a.metadata.createdAt;
      final bLastUsed = b.metadata.updatedAt ?? b.metadata.createdAt;
      return bLastUsed.compareTo(aLastUsed);
    });

    return setups;
  }

  /// Delete a saved setup
  Future<void> deleteSetup(String id) async {
    if (!_initialized) throw Exception('StorageService not initialized');

    await _setupsBox.delete(id);
    notifyListeners();

    if (kDebugMode) {
      print('Setup deleted: $id');
    }
  }

  /// Get saved setup references (lightweight list for UI)
  List<SavedSetup> getSavedSetupReferences() {
    if (!_initialized) return [];

    final references = <SavedSetup>[];

    for (final json in _setupsBox.values) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        final setup = DashboardSetup.fromJson(map);
        references.add(SavedSetup.fromDashboardSetup(setup));
      } catch (e) {
        if (kDebugMode) {
          print('Error parsing setup reference: $e');
        }
      }
    }

    // Sort by last used (most recent first), then by created date
    references.sort((a, b) {
      if (a.lastUsedAt != null && b.lastUsedAt != null) {
        return b.lastUsedAt!.compareTo(a.lastUsedAt!);
      } else if (a.lastUsedAt != null) {
        return -1;
      } else if (b.lastUsedAt != null) {
        return 1;
      } else {
        return b.createdAt.compareTo(a.createdAt);
      }
    });

    return references;
  }

  /// Check if a setup exists
  bool setupExists(String id) {
    if (!_initialized) return false;
    return _setupsBox.containsKey(id);
  }

  // ===== Server Connection Management =====

  /// Save a server connection
  Future<void> saveConnection(ServerConnection connection) async {
    if (!_initialized) throw Exception('StorageService not initialized');

    try {
      final json = jsonEncode(connection.toJson());
      await _connectionsBox.put(connection.id, json);
      notifyListeners();

      if (kDebugMode) {
        print('Server connection saved: ${connection.name} (${connection.serverUrl})');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving server connection: $e');
      }
      rethrow;
    }
  }

  /// Get a specific server connection by ID
  ServerConnection? getConnection(String id) {
    if (!_initialized) throw Exception('StorageService not initialized');

    try {
      final json = _connectionsBox.get(id);
      if (json == null) return null;

      final data = jsonDecode(json) as Map<String, dynamic>;
      return ServerConnection.fromJson(data);
    } catch (e) {
      if (kDebugMode) {
        print('Error loading connection $id: $e');
      }
      return null;
    }
  }

  /// Get all saved server connections
  List<ServerConnection> getAllConnections() {
    if (!_initialized) throw Exception('StorageService not initialized');

    final connections = <ServerConnection>[];

    for (final json in _connectionsBox.values) {
      try {
        final data = jsonDecode(json) as Map<String, dynamic>;
        connections.add(ServerConnection.fromJson(data));
      } catch (e) {
        if (kDebugMode) {
          print('Error parsing connection: $e');
        }
      }
    }

    // Sort by last connected (most recent first), then by name
    connections.sort((a, b) {
      if (a.lastConnectedAt != null && b.lastConnectedAt != null) {
        return b.lastConnectedAt!.compareTo(a.lastConnectedAt!);
      } else if (a.lastConnectedAt != null) {
        return -1;
      } else if (b.lastConnectedAt != null) {
        return 1;
      } else {
        return a.name.compareTo(b.name);
      }
    });

    return connections;
  }

  /// Delete a server connection and all associated data (auth token, etc.)
  Future<void> deleteConnection(String id) async {
    if (!_initialized) throw Exception('StorageService not initialized');

    // Delete associated auth token
    await _authTokenBox.delete(id);

    // Delete the connection itself
    await _connectionsBox.delete(id);

    notifyListeners();

    if (kDebugMode) {
      print('Server connection and associated data deleted: $id');
    }
  }

  /// Find a connection by server URL
  ServerConnection? findConnectionByUrl(String serverUrl) {
    final connections = getAllConnections();
    try {
      return connections.firstWhere((c) => c.serverUrl == serverUrl);
    } catch (e) {
      return null;
    }
  }

  /// Update connection's last connected time
  Future<void> updateConnectionLastConnected(String connectionId) async {
    final connection = getConnection(connectionId);
    if (connection != null) {
      await saveConnection(
        connection.copyWith(lastConnectedAt: DateTime.now()),
      );
    }
  }

  // ===== Authentication Token Management =====

  /// Save auth token for a connection
  /// Uses connectionId as key to support multiple connections to same server
  Future<void> saveAuthToken(AuthToken token, {required String connectionId}) async {
    if (!_initialized) throw Exception('StorageService not initialized');

    try {
      // Create token with connectionId
      final tokenWithConnection = AuthToken(
        token: token.token,
        clientId: token.clientId,
        expiresAt: token.expiresAt,
        issuedAt: token.issuedAt,
        serverUrl: token.serverUrl,
        connectionId: connectionId,
      );
      final json = jsonEncode(tokenWithConnection.toJson());
      await _authTokenBox.put(connectionId, json);
      notifyListeners();

      if (kDebugMode) {
        print('Auth token saved for connection $connectionId (${token.serverUrl})');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving auth token: $e');
      }
      rethrow;
    }
  }

  /// Get auth token for a connection
  AuthToken? getAuthToken(String connectionId) {
    if (!_initialized) throw Exception('StorageService not initialized');

    try {
      final json = _authTokenBox.get(connectionId);
      if (json == null) return null;

      final tokenData = jsonDecode(json) as Map<String, dynamic>;
      final token = AuthToken.fromJson(tokenData);

      // Check if expired
      if (token.isExpired) {
        if (kDebugMode) {
          print('Token for connection $connectionId is expired, removing...');
        }
        _authTokenBox.delete(connectionId);
        return null;
      }

      return token;
    } catch (e) {
      if (kDebugMode) {
        print('Error loading auth token for connection $connectionId: $e');
      }
      return null;
    }
  }

  /// Delete auth token for a connection
  Future<void> deleteAuthToken(String connectionId) async {
    if (!_initialized) throw Exception('StorageService not initialized');

    await _authTokenBox.delete(connectionId);
    notifyListeners();

    if (kDebugMode) {
      print('Auth token deleted for connection $connectionId');
    }
  }

  /// Clear all auth tokens
  Future<void> clearAllAuthTokens() async {
    if (!_initialized) throw Exception('StorageService not initialized');

    await _authTokenBox.clear();
    notifyListeners();

    if (kDebugMode) {
      print('All auth tokens cleared');
    }
  }

  // ===== Notifications Settings =====

  /// Save notifications enabled preference
  Future<void> saveNotificationsEnabled(bool enabled) async {
    if (!_initialized) throw Exception('StorageService not initialized');
    await _settingsBox.put('notifications_enabled', enabled ? 'true' : 'false');
    notifyListeners();

    if (kDebugMode) {
      print('Saved notifications enabled: $enabled');
    }
  }

  /// Get notifications enabled preference (defaults to false)
  bool getNotificationsEnabled() {
    if (!_initialized) return false;
    return _settingsBox.get('notifications_enabled', defaultValue: 'false') == 'true';
  }

  /// Save in-app notification level filter
  Future<void> saveInAppNotificationFilter(String level, bool enabled) async {
    if (!_initialized) throw Exception('StorageService not initialized');
    await _settingsBox.put('notification_inapp_$level', enabled ? 'true' : 'false');
    notifyListeners();

    if (kDebugMode) {
      print('Saved in-app notification level $level: $enabled');
    }
  }

  /// Get in-app notification level filter (defaults: only emergency enabled)
  bool getInAppNotificationFilter(String level) {
    if (!_initialized) {
      return level.toLowerCase() == 'emergency'; // Default: only emergency
    }

    // Defaults: only emergency enabled, all others disabled
    final defaultValue = level.toLowerCase() == 'emergency' ? 'true' : 'false';
    return _settingsBox.get('notification_inapp_$level', defaultValue: defaultValue) == 'true';
  }

  /// Save system notification level filter
  Future<void> saveSystemNotificationFilter(String level, bool enabled) async {
    if (!_initialized) throw Exception('StorageService not initialized');
    await _settingsBox.put('notification_system_$level', enabled ? 'true' : 'false');
    notifyListeners();

    if (kDebugMode) {
      print('Saved system notification level $level: $enabled');
    }
  }

  /// Get system notification level filter (defaults: only emergency enabled)
  bool getSystemNotificationFilter(String level) {
    if (!_initialized) {
      return level.toLowerCase() == 'emergency';
    }

    final defaultValue = level.toLowerCase() == 'emergency' ? 'true' : 'false';
    return _settingsBox.get('notification_system_$level', defaultValue: defaultValue) == 'true';
  }

  // Legacy method for backward compatibility - maps to in-app filter
  Future<void> saveNotificationLevelFilter(String level, bool enabled) async {
    await saveInAppNotificationFilter(level, enabled);
  }

  // Legacy method for backward compatibility - maps to in-app filter
  bool getNotificationLevelFilter(String level) {
    return getInAppNotificationFilter(level);
  }

  // ===== Conversions Cache Management =====

  /// Save conversions data to local cache
  /// This allows the app to use cached conversions on startup before server data arrives
  Future<void> saveConversionsCache(String serverUrl, Map<String, dynamic> conversionsData) async {
    if (!_initialized) throw Exception('StorageService not initialized');

    try {
      final cacheEntry = {
        'serverUrl': serverUrl,
        'timestamp': DateTime.now().toIso8601String(),
        'conversions': conversionsData,
      };
      final json = jsonEncode(cacheEntry);
      await _conversionsBox.put(serverUrl, json);

      if (kDebugMode) {
        print('Conversions cache saved for $serverUrl (${conversionsData.length} paths)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving conversions cache: $e');
      }
    }
  }

  /// Load cached conversions for a server
  /// Returns null if no cache exists or cache is expired (older than 30 days)
  Map<String, dynamic>? loadConversionsCache(String serverUrl, {Duration maxAge = const Duration(days: 30)}) {
    if (!_initialized) return null;

    try {
      final json = _conversionsBox.get(serverUrl);
      if (json == null) return null;

      final cacheEntry = jsonDecode(json) as Map<String, dynamic>;
      final timestamp = DateTime.parse(cacheEntry['timestamp'] as String);
      final age = DateTime.now().difference(timestamp);

      // Check if cache is expired
      if (age > maxAge) {
        if (kDebugMode) {
          print('Conversions cache expired for $serverUrl (age: ${age.inDays} days)');
        }
        return null;
      }

      final conversions = cacheEntry['conversions'] as Map<String, dynamic>;
      if (kDebugMode) {
        print('Loaded conversions cache for $serverUrl (${conversions.length} paths, age: ${age.inHours}h)');
      }
      return conversions;
    } catch (e) {
      if (kDebugMode) {
        print('Error loading conversions cache: $e');
      }
      return null;
    }
  }

  /// Clear conversions cache for a specific server
  Future<void> clearConversionsCache(String serverUrl) async {
    if (!_initialized) throw Exception('StorageService not initialized');
    await _conversionsBox.delete(serverUrl);

    if (kDebugMode) {
      print('Conversions cache cleared for $serverUrl');
    }
  }

  /// Clear all conversions caches
  Future<void> clearAllConversionsCaches() async {
    if (!_initialized) throw Exception('StorageService not initialized');
    await _conversionsBox.clear();

    if (kDebugMode) {
      print('All conversions caches cleared');
    }
  }
}
