import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:http/http.dart' as http;
import '../models/signalk_data.dart';
import '../models/auth_token.dart';
import 'zones_cache_service.dart';
import 'interfaces/data_service.dart';
import 'storage_service.dart';
import 'metadata_store.dart';
import '../models/path_metadata.dart';
import '../utils/nws_alert_utils.dart';
import 'ais_vessel_registry.dart';
import 'diagnostic_service.dart';

/// Connection state for SignalK server
enum SignalKConnectionState {
  connected,
  reconnecting,
  disconnected,
}

/// Service to connect to SignalK server and stream data
class SignalKService extends ChangeNotifier implements DataService {
  // Single WebSocket connection for all data (data, autopilot, notifications)
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  // Connection state
  bool _isConnected = false;
  String? _errorMessage;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  bool _intentionalDisconnect = false;
  bool _isConnecting = false;
  bool _wasConnected = false;

  // Throttled notifyListeners — coalesce rapid WS updates via microtask
  bool _notifyScheduled = false;
  int _notifyCount = 0; // Cumulative per-connect: total notifyListeners requests
  int _notifyThrottledCount = 0; // Cumulative per-connect: coalesced (skipped) calls

  int get notifyCount => _notifyCount;
  int get notifyThrottledCount => _notifyThrottledCount;

  void _scheduleNotify() {
    _notifyCount++;
    if (_notifyScheduled) {
      _notifyThrottledCount++;
      return;
    }
    _notifyScheduled = true;
    Future.microtask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  /// Reset diagnostic counters (called on connect)
  void _resetDiagnosticCounters() {
    _notifyCount = 0;
    _notifyThrottledCount = 0;
  }

  // Connection state stream (for UI overlay without triggering rebuilds)
  final _connectionStateController = StreamController<SignalKConnectionState>.broadcast();
  SignalKConnectionState _connectionState = SignalKConnectionState.disconnected;

  // Data storage - moved to _DataCacheManager
  UnmodifiableMapView<String, SignalKDataPoint>? _latestDataView;

  // Conversion data - moved to _ConversionManager
  UnmodifiableMapView<String, PathConversionData>? _conversionsDataView;

  // NWS weather-alerts dashboard checker (injected from main.dart)
  bool Function() _isWeatherAlertsOnDashboard = () => false;

  void setWeatherAlertsChecker(bool Function() checker) {
    _isWeatherAlertsOnDashboard = checker;
  }

  // Active subscriptions — centralized via PathSubscriptionRegistry
  final PathSubscriptionRegistry _subscriptionRegistry = PathSubscriptionRegistry();
  // Legacy accessors (backing _activePaths with registry)
  Set<String> get _activePaths => _subscriptionRegistry.allPaths;
  final Set<String> _autopilotPaths = {}; // Separate tracking for autopilot paths (until Phase 7 merges)
  String? _vesselContext;

  // Path catalog — all paths available on the server (from /skServer/availablePaths)
  List<String> _availablePaths = [];
  Timer? _availablePathsRefreshTimer;

  // User's display unit preferences from WebSocket meta (sendMeta=all per subscription)
  // Maps path to displayUnits configuration: {category, targetUnit, formula, inverseFormula, symbol}
  final Map<String, Map<String, dynamic>> _displayUnitsCache = {};
  Timer? _displayUnitsSaveTimer;

  // Configuration
  String _serverUrl = 'localhost:3000';
  bool _useSecureConnection = false;
  AuthToken? _authToken;

  // Zones cache service
  ZonesCacheService? _zonesCache;

  // RTC signaling callback for real-time WebRTC signaling
  void Function(String path, dynamic value)? _rtcDeltaCallback;

  // Connection callbacks - executed sequentially after connection to avoid HTTP overload
  final List<Future<void> Function()> _connectionCallbacks = [];

  // Storage service for caching conversions
  final StorageService? _storageService;

  // Device ID for source identification
  String get _deviceId => _storageService?.getSetting('crew_device_id') ?? 'unknown';

  // Internal managers
  late final _DataCacheManager _dataCache;
  late final _ConversionManager _conversionManager;
  late final _NotificationManager _notificationManager;
  late final _AISManager _aisManager;

  // Single source of truth for path metadata and conversions
  final MetadataStore _metadataStore = MetadataStore();

  // Diagnostic service for memory leak investigation (nullable, opt-in)
  DiagnosticService? _diagnosticService;

  /// Set the diagnostic service for REST/WS instrumentation.
  void setDiagnosticService(DiagnosticService service) {
    _diagnosticService = service;
  }

  /// Get current RSS in KB for diagnostic instrumentation.
  int _diagnosticRssKB() {
    try {
      if (Platform.isAndroid) {
        final status = File('/proc/self/status');
        if (!status.existsSync()) return 0;
        for (var line in status.readAsLinesSync()) {
          if (line.startsWith('VmRSS:')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 2) return int.parse(parts[1]);
          }
        }
        return 0;
      }
      final rss = ProcessInfo.currentRss;
      return rss > 0 ? (rss / 1024).round() : 0;
    } catch (_) {
      return 0;
    }
  }

  // Constructor
  SignalKService({StorageService? storageService}) : _storageService = storageService {
    _dataCache = _DataCacheManager(
      getActivePaths: () => _activePaths,
      isConnected: () => _isConnected,
      onCacheChanged: () => _latestDataView = null,
    );
    _conversionManager = _ConversionManager(
      getServerUrl: () => _serverUrl,
      useSecureConnection: () => _useSecureConnection,
      getHeaders: () => _getHeaders(),
      saveToCache: _saveConversionsToCache,
      loadFromCache: _loadConversionsFromCache,
      getMetadataStore: () => _metadataStore,
    );
    _notificationManager = _NotificationManager(
      getAuthToken: () => _authToken,
      getNotificationEndpoint: () => _getNotificationEndpoint(),
      isWeatherAlertsOnDashboard: () => _isWeatherAlertsOnDashboard(),
      getLatestData: () => _dataCache.internalDataMap,
      getDiagnosticService: () => _diagnosticService,
      getVesselContext: () => _vesselContext,
    );
    _aisManager = _AISManager(
      getServerUrl: () => _serverUrl,
      useSecureConnection: () => _useSecureConnection,
      getHeaders: () => _getHeaders(),
      isConnected: () => _isConnected,
      getChannel: () => _channel,
      getVesselContext: () => _vesselContext,
      getDataCache: () => _dataCache.internalDataMap,
    );
  }

  // Cache helper methods
  Future<void> _saveConversionsToCache(Map<String, dynamic> data) async {
    final storage = _storageService;
    if (storage != null) {
      await storage.saveConversionsCache(_serverUrl, data);
    }
  }

  Map<String, dynamic>? _loadConversionsFromCache() {
    return _storageService?.loadConversionsCache(_serverUrl);
  }

  // Load cached displayUnits for instant unit conversions on startup
  void _loadDisplayUnitsFromCache() {
    final cached = _storageService?.loadDisplayUnitsCache(_serverUrl);
    if (cached != null) {
      _displayUnitsCache.addAll(cached);

      // Also populate MetadataStore (single source of truth)
      _metadataStore.updateFromMap(cached);
    }
  }

  // Save displayUnits cache with debounce to avoid excessive writes
  void _saveDisplayUnitsToCache() {
    _displayUnitsSaveTimer?.cancel();
    _displayUnitsSaveTimer = Timer(const Duration(seconds: 2), () {
      _storageService?.saveDisplayUnitsCache(_serverUrl, _displayUnitsCache);
    });
  }

  // Getters
  @override
  bool get isConnected => _isConnected;
  String? get errorMessage => _errorMessage;
  Map<String, SignalKDataPoint> get latestData {
    _latestDataView ??= UnmodifiableMapView(_dataCache.internalDataMap);
    return _latestDataView!;
  }
  Map<String, PathConversionData> get conversionsData {
    _conversionsDataView ??= UnmodifiableMapView(_conversionManager.internalDataMap);
    return _conversionsDataView!;
  }
  bool get hasConversions => _conversionManager.internalDataMap.isNotEmpty;

  /// Single source of truth for path metadata and conversions.
  /// Populated from WebSocket meta deltas (sendMeta=all).
  MetadataStore get metadataStore => _metadataStore;

  /// Indexed AIS vessel store with single-authority pruning.
  AISVesselRegistry get aisVesselRegistry => _aisManager.registry;

  /// Path subscription registry for diagnostic access.
  PathSubscriptionRegistry get subscriptionRegistry => _subscriptionRegistry;

  // Cache size getters for diagnostics instrumentation
  int get displayUnitsCacheCount => _displayUnitsCache.length;
  int get availablePathsCount => _availablePaths.length;
  int get conversionsDataCount => _conversionManager.internalDataMap.length;
  int get notificationStateCount => _notificationManager.stateMapSize;
  int get notificationTimeCount => _notificationManager.timeMapSize;

  @override
  String get serverUrl => _serverUrl;
  @override
  bool get useSecureConnection => _useSecureConnection;
  bool get notificationsEnabled => _notificationManager.notificationsEnabled;
  Stream<SignalKNotification> get notificationStream => _notificationManager.notificationStream;

  // Connection state stream and properties
  Stream<SignalKConnectionState> get connectionStateStream => _connectionStateController.stream;
  SignalKConnectionState get connectionState => _connectionState;
  int get reconnectAttempt => _reconnectAttempts;
  int get maxReconnectAttempts => _maxReconnectAttempts;
  bool get wasConnected => _wasConnected;

  /// The full vessel context path (e.g., 'vessels.urn:mrn:imo:mmsi:367780840')
  /// Used for PUT requests to ensure proper routing
  String? get vesselContext => _vesselContext;

  /// Get recent notifications (last 10 seconds by default)
  List<SignalKNotification> getRecentNotifications({Duration maxAge = const Duration(seconds: 10)}) {
    return _notificationManager.getRecentNotifications(maxAge: maxAge);
  }

  AuthToken? get authToken => _authToken;
  ZonesCacheService? get zonesCache => _zonesCache;

  /// Check if current user has admin permissions
  /// Decodes the JWT token to check the permissions claim
  bool get isAdmin {
    if (_authToken == null) return false;
    try {
      // JWT format: header.payload.signature
      final parts = _authToken!.token.split('.');
      if (parts.length != 3) return false;

      // Decode the payload (middle part)
      String payload = parts[1];
      // Add padding if needed for base64
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decoded = utf8.decode(base64Url.decode(payload));
      final data = jsonDecode(decoded) as Map<String, dynamic>;

      // Check permissions field (SignalK uses 'permissions' with value like 'admin')
      final permissions = data['permissions'] as String?;
      return permissions == 'admin';
    } catch (e) {
      return false;
    }
  }

  /// Register a callback to be executed sequentially after SignalK connects.
  /// This prevents HTTP request overload when multiple services need to
  /// initialize resources (e.g., ensureResourceTypeExists) on connection.
  void registerConnectionCallback(Future<void> Function() callback) {
    _connectionCallbacks.add(callback);
  }

  /// Unregister a previously registered connection callback.
  void unregisterConnectionCallback(Future<void> Function() callback) {
    _connectionCallbacks.remove(callback);
  }

  /// Connect to SignalK server (optionally with authentication)
  Future<void> connect(
    String serverUrl, {
    bool secure = false,
    AuthToken? authToken,
  }) async {
    if (_isConnecting) return;
    _isConnecting = true;

    // Disconnect any existing connection first
    if (_isConnected || _channel != null) {
      await disconnect();
      // Give the socket time to fully close
      await Future.delayed(const Duration(milliseconds: 800));
    }

    _serverUrl = serverUrl;
    _useSecureConnection = secure;
    _authToken = authToken;

    // Load cached conversions immediately for instant display
    // Server data will replace this when it arrives
    _conversionManager.loadFromLocalCache();
    _loadDisplayUnitsFromCache(); // Load displayUnits for instant unit conversions
    _conversionsDataView = null; // Invalidate cache view
    notifyListeners();

    // Initialize zones cache service
    _zonesCache = ZonesCacheService(
      serverUrl: serverUrl,
      useSecureConnection: secure,
    );

    try {
      // Discover the WebSocket endpoint
      final wsUrl = await _discoverWebSocketEndpoint();

      // Connect to WebSocket with authentication headers if we have a token
      if (_authToken != null) {
        final headers = <String, String>{
          'Authorization': 'Bearer ${_authToken!.token}',
        };

        try {
          // Use dart:io WebSocket.connect which supports headers
          // Pass the URL string directly - don't parse and re-stringify
          final socket = await WebSocket.connect(wsUrl, headers: headers);
          // Keep connection alive with ping frames every 30 seconds
          socket.pingInterval = const Duration(seconds: 30);
          _channel = IOWebSocketChannel(socket);
        } catch (e) {
          if (kDebugMode) {
            print('WebSocket.connect failed: $e');
          }
          rethrow;
        }
      } else {
        // Standard connection without authentication
        _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      }

      // Listen to incoming messages
      // cancelOnError: false keeps listening after errors (e.g., stale reads on resume)
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
        cancelOnError: false,
      );

      _isConnected = true;
      _wasConnected = true;
      _errorMessage = null;
      _reconnectAttempts = 0; // Reset reconnect attempts on successful connection
      _resetDiagnosticCounters();
      _intentionalDisconnect = false;
      _connectionState = SignalKConnectionState.connected;
      _connectionStateController.add(SignalKConnectionState.connected);
      notifyListeners();


      // Note: units-preference plugin does NOT use WebSocket-level authentication
      // The auth token is used only for HTTP requests to the API
      // The WebSocket connection is already authenticated at the HTTP upgrade level

      // Fetch unit preferences from server (replaces broken /conversions endpoint)
      await _conversionManager.fetchConversions();
      _conversionsDataView = null;

      // Subscribe to paths immediately
      await _sendSubscription();

      // Subscribe to RTC paths if callback is registered
      if (_rtcDeltaCallback != null) {
        _subscribeToRtcPaths();
      }

      // Fetch path catalog from server (lightweight, no auth required)
      _fetchAvailablePaths();
      _startAvailablePathsRefresh();

      // Start periodic cache cleanup to prevent memory growth
      _startCacheCleanup();

      // Subscribe to notifications on main channel if enabled
      if (_notificationManager.notificationsEnabled && _authToken != null) {
        _subscriptionRegistry.register('notifications', ['notifications.*']);
      }

      // Execute connection callbacks sequentially to prevent HTTP overload
      // Services like CrewService, MessagingService, etc. register callbacks
      // that need to make HTTP requests (e.g., ensureResourceTypeExists)
      for (final callback in _connectionCallbacks) {
        try {
          await callback();
        } catch (e) {
          if (kDebugMode) {
            print('Connection callback error: $e');
          }
          // Continue with other callbacks even if one fails
        }
      }

      _isConnecting = false;
    } catch (e) {
      _isConnecting = false;
      _errorMessage = 'Connection failed: $e';
      _isConnected = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Get the REST API vessel path segment.
  /// Uses MMSI/URN if available, falls back to 'self'.
  String get _vesselRestPath {
    if (_vesselContext != null && _vesselContext!.startsWith('vessels.')) {
      return _vesselContext!.substring('vessels.'.length);
    }
    return 'self';
  }

  /// Get HTTP headers with authentication if available
  Map<String, String> _getHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer ${_authToken!.token}';
    }
    return headers;
  }

  /// Discover WebSocket endpoint - standard SignalK stream
  /// sendMeta=all on URL to receive displayUnits with each path's metadata
  Future<String> _discoverWebSocketEndpoint() async {
    final wsProtocol = _useSecureConnection ? 'wss' : 'ws';

    // Standard SignalK stream with sendMeta=all — REST populates MetadataStore on connect,
    // but WS meta overrides keep us in sync with runtime changes (new paths, user pref changes)
    var endpoint = '$wsProtocol://$_serverUrl/signalk/v1/stream?subscribe=none&sendMeta=all';
    if (_authToken != null) {
      endpoint += '&token=${Uri.encodeComponent(_authToken!.token)}';
    }
    return endpoint;
  }

  /// Get notification WebSocket endpoint (always standard SignalK)
  String _getNotificationEndpoint() {
    final wsProtocol = _useSecureConnection ? 'wss' : 'ws';
    var endpoint = '$wsProtocol://$_serverUrl/signalk/v1/stream?subscribe=none';
    if (_authToken != null) {
      endpoint += '&token=${Uri.encodeComponent(_authToken!.token)}';
    }
    return endpoint;
  }


  /// Send WebSocket authentication with token (currently unused, kept for future)
  // void _sendWebSocketAuth() {
  //   if (_authToken == null) return;
  //
  //   final authMessage = {
  //     'requestId': '${DateTime.now().millisecondsSinceEpoch}',
  //     'token': _authToken!.token,
  //   };
  //
  //   _channel?.sink.add(jsonEncode(authMessage));
  //
  //   if (kDebugMode) {
  //     print('Sent WebSocket authentication with token');
  //   }
  // }

  /// Initialize subscriptions after connection
  /// Call this with all paths from deployed templates
  Future<void> _sendSubscription() async {
    try {
      // Always get vessel context for self-vessel filtering (used by AIS)
      final vesselId = await getVesselSelfId();
      _vesselContext = vesselId != null ? 'vessels.$vesselId' : 'vessels.self';
      _selfMMSI = vesselId != null ? RegExp(r'(\d{9})').firstMatch(vesselId)?.group(1) : null;
      _aisManager.registry.setSelfVesselId(vesselId);

      // Don't subscribe yet - wait for setActiveTemplatePaths() to be called
      // Auth guard: no auth = no subscriptions (prevents wildcard flooding)
      if (_authToken == null) {
        if (kDebugMode) {
          print('Auth guard: no auth token, skipping subscription');
        }
        return;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Subscription setup error: $e');
      }
    }
  }

  /// Set paths from active templates and subscribe to them
  /// Call this when dashboards/templates change
  Future<void> setActiveTemplatePaths(List<String> paths) async {
    if (!_isConnected || _channel == null) return;

    // Check if paths have actually changed
    final pathsSet = Set<String>.from(paths);
    final currentDashboardPaths = _subscriptionRegistry.getPathsForOwner('dashboard');

    if (pathsSet.length == currentDashboardPaths.length &&
        pathsSet.containsAll(currentDashboardPaths)) {
      return;
    }

    // Register dashboard paths in the subscription registry
    _subscriptionRegistry.register('dashboard', paths);
    await _updateSubscription();
  }

  /// Handle incoming WebSocket messages
  void _handleMessage(dynamic message) {
    try {
      // Verbose logging disabled - only log errors

      final data = jsonDecode(message);

      // Handle plain string messages (server warnings/info)
      if (data is String) return;

      // Must be a Map to process
      if (data is! Map<String, dynamic>) return;

      // Check if it's an authentication response
      if (data['requestId'] != null && data['state'] != null) {
        // Auth response - no logging needed
        return;
      }

      // Check if it's a delta update
      if (data['updates'] != null) {
        _diagnosticService?.instrumentWsMessage('delta');

        final update = SignalKUpdate.fromJson(data);

        // Process each value update
        for (final updateValue in update.updates) {
          final source = updateValue.source; // Source label (e.g., "can0.115", "pypilot")

          // Process meta entries (from sendMeta=all) - extract displayUnits
          // Populate MetadataStore (single source of truth) and legacy cache
          bool displayUnitsChanged = false;
          if (updateValue.metaEntries.isNotEmpty) {
            _diagnosticService?.instrumentWsMessage('meta');
          }
          for (final metaEntry in updateValue.metaEntries) {
            if (metaEntry.displayUnits != null) {
              // Update single source of truth (MetadataStore)
              _metadataStore.updateFromMeta(metaEntry.path, metaEntry.displayUnits!);

              // Also update legacy cache for backward compatibility
              _displayUnitsCache[metaEntry.path] = metaEntry.displayUnits!;
              displayUnitsChanged = true;
            }
          }
          if (displayUnitsChanged) {
            _saveDisplayUnitsToCache(); // Persist for instant display on restart
            notifyListeners(); // Trigger widget rebuild to show new units
          }

          // Process value updates
          for (final value in updateValue.values) {
            // Route notification paths to notification manager (single WS)
            if (value.path.startsWith('notifications.') &&
                !value.path.startsWith('notifications.crew.rtc.')) {
              if (_notificationManager.notificationsEnabled) {
                _notificationManager.handleNotification(
                    value.path, value.value, updateValue.timestamp);
              }
              continue; // Don't store notifications in data cache
            }

            // Check for RTC signaling notifications - route to callback immediately
            if (value.path.startsWith('notifications.crew.rtc.') && _rtcDeltaCallback != null) {
              try {
                // Parse the signaling data from notification message field
                final notifValue = value.value;
                if (notifValue is Map<String, dynamic> && notifValue['message'] != null) {
                  final messageJson = notifValue['message'] as String;
                  final signalingData = jsonDecode(messageJson) as Map<String, dynamic>;
                  _rtcDeltaCallback!(value.path, signalingData);
                }
              } catch (e) {
                if (kDebugMode) {
                  print('Error parsing RTC notification: $e');
                }
              }
              continue; // Don't store RTC signaling in data cache
            }

            SignalKDataPoint dataPoint;

            // Check if value is from units-preference plugin (has converted/original/formatted fields)
            if (value.value is Map<String, dynamic>) {
              final valueMap = value.value as Map<String, dynamic>;

              // Check if this is actually units-preference format (has converted/original keys)
              // vs a regular object value like position {longitude, latitude}
              final isUnitsPreference = valueMap.containsKey('converted') ||
                                       valueMap.containsKey('original') ||
                                       valueMap.containsKey('formatted');

              if (isUnitsPreference) {
                // Units-preference format - extract converted values
                final convertedValue = valueMap['converted'];
                final originalValue = valueMap['original'];
                final formattedString = valueMap['formatted'] as String?;
                final symbolString = valueMap['symbol'] as String?;

                // For numeric values, use converted number for charts/gauges
                final numericValue = convertedValue is num ? convertedValue.toDouble() : null;

                dataPoint = SignalKDataPoint(
                  path: value.path,
                  value: numericValue ?? convertedValue ?? originalValue,
                  timestamp: updateValue.timestamp,
                  lastSeen: DateTime.now(),
                  converted: numericValue,
                  formatted: formattedString,
                  symbol: symbolString,
                  original: originalValue,
                  source: source,
                );
              } else {
                // Regular object value (like position) - NOT units-preference format
                dataPoint = SignalKDataPoint(
                  path: value.path,
                  value: valueMap, // Keep the object as-is
                  timestamp: updateValue.timestamp,
                  lastSeen: DateTime.now(),
                  source: source,
                );
              }
            } else {
              // Standard SignalK format - scalar value
              dataPoint = SignalKDataPoint(
                path: value.path,
                value: value.value,
                timestamp: updateValue.timestamp,
                lastSeen: DateTime.now(),
                source: source,
              );
            }

            // Route AIS vessel deltas to registry, own vessel to flat cache
            if (update.context.startsWith('vessels.') && !_isSelfContext(update.context)) {
              // AIS vessel — route to registry (not flat cache)
              final vesselId = update.context.substring('vessels.'.length);
              _aisManager.registry.updateVessel(
                vesselId, value.path, dataPoint.original ?? dataPoint.value,
                updateValue.timestamp,
              );
              // Still store detail data in flat cache for _getExtraVesselData() lookups
              final contextPath = '${update.context}.${value.path}';
              _dataCache.internalDataMap[contextPath] = dataPoint;
              continue; // Skip self-vessel storage
            }

            // Own vessel — store in flat cache (single entry per path)
            // Source is stored on the dataPoint itself, not as separate cache key
            _dataCache.internalDataMap[value.path] = dataPoint;
          }
        }

        // Notify AIS registry once per delta batch (not per path)
        _aisManager.registry.notifyChanged();

        // Invalidate cache when data changes
        _latestDataView = null;
        _scheduleNotify();
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('Error parsing message: $e');
        print('Stack trace: $stackTrace');
        print('Raw message: $message');
      }
    }
  }

  /// Handle WebSocket errors
  void _handleError(Object error) {
    _errorMessage = 'WebSocket error: $error';
    _isConnected = false;
    notifyListeners();

    if (kDebugMode) {
      print('WebSocket error: $error');
    }
  }

  /// Handle WebSocket disconnect
  void _handleDisconnect() {
    if (!_isConnected && _channel == null) return; // already handled

    _isConnected = false;
    _isConnecting = false;

    _subscription?.cancel();
    _subscription = null;
    _channel = null;

    if (kDebugMode) {
      print('Disconnected from SignalK server');
    }

    // Attempt reconnection if not intentional disconnect
    if (!_intentionalDisconnect && _serverUrl.isNotEmpty) {
      _connectionState = SignalKConnectionState.reconnecting;
      _connectionStateController.add(SignalKConnectionState.reconnecting);
      _attemptReconnect();
    } else {
      _connectionState = SignalKConnectionState.disconnected;
      _connectionStateController.add(SignalKConnectionState.disconnected);
    }
  }

  /// Attempt to reconnect with exponential backoff.
  /// Uses lightweight reconnect to preserve cached data across short dropouts.
  void _attemptReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      if (kDebugMode) {
        print('Max reconnect attempts reached. Giving up.');
      }
      _connectionState = SignalKConnectionState.disconnected;
      _connectionStateController.add(SignalKConnectionState.disconnected);
      _errorMessage = 'Connection lost. Please reconnect manually.';
      notifyListeners();
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(seconds: 2 * _reconnectAttempts); // Exponential backoff: 2s, 4s, 6s, 8s, 10s

    // Re-emit reconnecting state so UI updates with new attempt count
    _connectionState = SignalKConnectionState.reconnecting;
    _connectionStateController.add(SignalKConnectionState.reconnecting);

    if (kDebugMode) {
      print('Attempting reconnect #$_reconnectAttempts in ${delay.inSeconds}s...');
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      try {
        await _reconnectLight();
        if (kDebugMode) {
          print('Reconnected successfully (lightweight)!');
        }
      } catch (e) {
        if (kDebugMode) {
          print('Reconnect attempt #$_reconnectAttempts failed: $e');
        }
        _attemptReconnect();
      }
    });
  }

  /// Lightweight reconnect: replace WebSocket and re-send subscriptions
  /// without clearing cached data (metadata, conversions, AIS, data cache).
  /// This makes short dropouts (subway, Wi-Fi handoff) nearly invisible.
  Future<void> _reconnectLight() async {
    // Tear down old socket only
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    // Open new WebSocket
    final wsUrl = await _discoverWebSocketEndpoint();

    if (_authToken != null) {
      final headers = <String, String>{
        'Authorization': 'Bearer ${_authToken!.token}',
      };
      final socket = await WebSocket.connect(wsUrl, headers: headers);
      socket.pingInterval = const Duration(seconds: 30);
      _channel = IOWebSocketChannel(socket);
    } else {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    }

    // Listen on new stream
    _subscription = _channel!.stream.listen(
      _handleMessage,
      onError: _handleError,
      onDone: _handleDisconnect,
      cancelOnError: false,
    );

    _isConnected = true;
    _errorMessage = null;
    _reconnectAttempts = 0;
    _intentionalDisconnect = false;
    _connectionState = SignalKConnectionState.connected;
    _connectionStateController.add(SignalKConnectionState.connected);
    notifyListeners();

    // Re-send existing subscriptions to the new WebSocket
    await _updateSubscription();

    // Re-subscribe RTC paths if active
    if (_rtcDeltaCallback != null) {
      _subscribeToRtcPaths();
    }
  }

  /// Send PUT request to SignalK server
  ///
  /// If [source] is provided, it specifies which source/plugin should handle the PUT.
  /// This is required when multiple sources exist for the same path.
  @override
  Future<void> sendPutRequest(String path, dynamic value, {String? source}) async {
    final protocol = _useSecureConnection ? 'https' : 'http';

    // Convert dot notation to slash notation for URL
    // e.g., 'commands.captureMoored.auto' -> 'commands/captureMoored/auto'
    // Use vessels/self as context - plugins register handlers for this context
    // The 'source' in body selects which handler when multiple exist
    final urlPath = path.replaceAll('.', '/');

    final body = <String, dynamic>{'value': value};
    if (source != null) {
      body['source'] = source;
    }

    try {
      final memBefore = _diagnosticRssKB();
      final response = await http.put(
        Uri.parse('$protocol://$_serverUrl/signalk/v1/api/vessels/$_vesselRestPath/$urlPath'),
        headers: _getHeaders(),
        body: jsonEncode(body),
      );
      _diagnosticService?.instrumentRestCall('PUT', memBefore, _diagnosticRssKB());

      if (response.statusCode != 200) {
        throw Exception('PUT request failed: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('PUT request error: $e');
      }
      rethrow;
    }
  }

  // ===== RTC Signaling via WebSocket =====

  /// Register callback to receive RTC signaling deltas in real-time
  /// The callback receives (path, value) when crew.rtc.* paths change
  void registerRtcDeltaCallback(void Function(String path, dynamic value) callback) {
    _rtcDeltaCallback = callback;
    // Subscribe to RTC paths if connected
    if (_isConnected) {
      _subscribeToRtcPaths();
    }
  }

  /// Unregister RTC delta callback
  void unregisterRtcDeltaCallback() {
    _rtcDeltaCallback = null;
  }

  /// Subscribe to notifications.crew.rtc.* for real-time signaling
  void _subscribeToRtcPaths() {
    if (_channel == null) return;

    final subscriptionContext = _vesselContext ?? 'vessels.self';
    final subscribeMessage = {
      'context': subscriptionContext,
      'subscribe': [
        {'path': 'notifications.crew.rtc.*'},
      ],
    };

    _channel?.sink.add(jsonEncode(subscribeMessage));
  }

  /// Send RTC signaling data via SignalK notification (broadcasts to all clients)
  void sendRtcSignaling(String signalingPath, Map<String, dynamic> data) {
    if (_channel == null) return;

    // Send as a notification - notifications are broadcast to all connected clients
    final subscriptionContext = _vesselContext ?? 'vessels.self';
    final notification = {
      'context': subscriptionContext,
      'updates': [
        {
          '\$source': 'zeddisplay.$_deviceId',
          'values': [
            {
              'path': 'notifications.crew.rtc.$signalingPath',
              'value': {
                'state': 'normal',
                'method': ['visual'],
                'message': jsonEncode(data),
              }
            }
          ]
        }
      ]
    };

    _channel?.sink.add(jsonEncode(notification));
  }

  // ===== Resources API (v2) =====
  // SignalK Resources API for storing custom data (routes, waypoints, notes, etc.)
  // Uses v2 API: /signalk/v2/api/resources/

  /// Get all resources of a specific type
  /// Returns a Map of resource IDs to resource data
  Future<Map<String, dynamic>> getResources(String resourceType) async {
    final protocol = _useSecureConnection ? 'https' : 'http';
    final url = '$protocol://$_serverUrl/signalk/v2/api/resources/$resourceType';

    try {
      final memBefore = _diagnosticRssKB();
      final response = await http.get(
        Uri.parse(url),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 10));
      _diagnosticService?.instrumentRestCall('GET', memBefore, _diagnosticRssKB());

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          return data;
        }
      } else if (response.statusCode == 404) {
        // Resource type doesn't exist yet, return empty map
        return {};
      }
    } catch (_) {
      // Ignore resource fetch errors
    }
    return {};
  }

  /// Get a specific resource by type and ID
  Future<Map<String, dynamic>?> getResource(String resourceType, String id) async {
    final protocol = _useSecureConnection ? 'https' : 'http';

    try {
      final response = await http.get(
        Uri.parse('$protocol://$_serverUrl/signalk/v2/api/resources/$resourceType/$id'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
    } catch (_) {
      // Ignore resource fetch errors
    }
    return null;
  }

  /// Create or update a resource
  /// Returns true if successful
  Future<bool> putResource(String resourceType, String id, Map<String, dynamic> data) async {
    final protocol = _useSecureConnection ? 'https' : 'http';
    final url = '$protocol://$_serverUrl/signalk/v2/api/resources/$resourceType/$id';

    try {
      final memBefore = _diagnosticRssKB();
      final response = await http.put(
        Uri.parse(url),
        headers: _getHeaders(),
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 10));
      _diagnosticService?.instrumentRestCall('PUT', memBefore, _diagnosticRssKB());

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      }
    } catch (_) {
      // Ignore put errors
    }
    return false;
  }

  /// Delete a resource
  /// Returns true if successful
  Future<bool> deleteResource(String resourceType, String id) async {
    final protocol = _useSecureConnection ? 'https' : 'http';

    try {
      final memBefore = _diagnosticRssKB();
      final response = await http.delete(
        Uri.parse('$protocol://$_serverUrl/signalk/v2/api/resources/$resourceType/$id'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 10));
      _diagnosticService?.instrumentRestCall('DELETE', memBefore, _diagnosticRssKB());

      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      }
    } catch (_) {
      // Ignore delete errors
    }
    return false;
  }

  // Track which custom resource types have been ensured this session
  final Set<String> _ensuredResourceTypes = {};

  /// Ensure a custom resource type exists on the SignalK server
  /// Uses the resources-provider plugin's configuration API
  /// Returns true if the resource type exists or was created successfully
  Future<bool> ensureResourceTypeExists(String resourceType, {String? description}) async {
    // Skip if already ensured this session
    if (_ensuredResourceTypes.contains(resourceType)) {
      return true;
    }

    final protocol = _useSecureConnection ? 'https' : 'http';

    try {
      // First check if the resource type already exists by trying to GET it
      final checkResponse = await http.get(
        Uri.parse('$protocol://$_serverUrl/signalk/v2/api/resources/$resourceType'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 5));

      if (checkResponse.statusCode == 200) {
        // Resource type exists
        _ensuredResourceTypes.add(resourceType);
        return true;
      }

      // Resource type doesn't exist, try to create it via resources-provider plugin API
      final createResponse = await http.post(
        Uri.parse('$protocol://$_serverUrl/plugins/resources-provider/_config/$resourceType'),
        headers: _getHeaders(),
        body: jsonEncode({
          'description': description ?? 'ZedDisplay $resourceType',
        }),
      ).timeout(const Duration(seconds: 10));

      if (createResponse.statusCode == 200 || createResponse.statusCode == 201) {
        _ensuredResourceTypes.add(resourceType);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Make an authenticated POST request to a plugin API endpoint
  /// Returns the response body as a Map, or null on failure
  Future<http.Response> postPluginApi(String pluginPath, {Map<String, dynamic>? body}) async {
    final protocol = _useSecureConnection ? 'https' : 'http';
    final url = '$protocol://$_serverUrl$pluginPath';

    final memBefore = _diagnosticRssKB();
    final response = await http.post(
      Uri.parse(url),
      headers: _getHeaders(),
      body: body != null ? jsonEncode(body) : null,
    ).timeout(const Duration(seconds: 10));
    _diagnosticService?.instrumentRestCall('POST', memBefore, _diagnosticRssKB());
    return response;
  }

  /// Make an authenticated GET request to a plugin API endpoint
  /// Returns the response body as a Map, or null on failure
  Future<http.Response> getPluginApi(String pluginPath) async {
    final protocol = _useSecureConnection ? 'https' : 'http';
    final url = '$protocol://$_serverUrl$pluginPath';

    final memBefore = _diagnosticRssKB();
    final response = await http.get(
      Uri.parse(url),
      headers: _getHeaders(),
    ).timeout(const Duration(seconds: 10));
    _diagnosticService?.instrumentRestCall('GET', memBefore, _diagnosticRssKB());
    return response;
  }

  /// Get value for specific path, optionally from a specific source
  @override
  SignalKDataPoint? getValue(String path, {String? source}) {
    return _dataCache.getValue(path, source: source);
  }

  /// Get the raw value for a path (convenience method)
  dynamic getPathValue(String path, {String? source}) {
    return getValue(path, source: source)?.value;
  }

  /// Check if data is fresh (within TTL threshold)
  /// Returns true if data is fresh, false if stale or missing
  @override
  bool isDataFresh(String path, {String? source, int? ttlSeconds}) {
    return _dataCache.isDataFresh(path, source: source, ttlSeconds: ttlSeconds);
  }

  /// Get value for specific path directly from REST API
  /// This is useful when WebSocket delta updates aren't working
  Future<dynamic> getRestValue(String path) async {
    final protocol = _useSecureConnection ? 'https' : 'http';

    // Convert dot notation to slash notation for URL
    // e.g., 'steering.autopilot.state' -> 'steering/autopilot/state'
    final urlPath = path.replaceAll('.', '/');

    try {
      final response = await http.get(
        Uri.parse('$protocol://$_serverUrl/signalk/v1/api/vessels/$_vesselRestPath/$urlPath'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 10)); // Increased from 3s for busy servers

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // SignalK REST API returns the value in the 'value' field
        if (data.containsKey('value')) {
          return data['value'];
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching REST value for path $path: $e');
      }
    }

    return null;
  }

  /// Get numeric value for specific path (returns null if not numeric)
  double? getNumericValue(String path) {
    return _dataCache.getNumericValue(path);
  }

  /// Get formatted value string from units-preference plugin
  /// Returns pre-formatted string like "10.0 kn" or falls back to raw value
  String getFormattedValue(String path) {
    final dataPoint = _dataCache.internalDataMap[path];

    if (dataPoint == null) {
      return '---';
    }

    // Use formatted value from units-preference plugin if available
    if (dataPoint.formatted != null) {
      return dataPoint.formatted!;
    }

    // Fallback to raw value
    if (dataPoint.value is num) {
      return dataPoint.value.toStringAsFixed(1);
    }

    return dataPoint.value.toString();
  }

  /// Get converted numeric value (already in user's preferred units)
  @override
  double? getConvertedValue(String path) {
    return _dataCache.getConvertedValue(path);
  }

  /// Get unit symbol for a path (e.g., "kn", "°C")
  @override
  String? getUnitSymbol(String path) {
    final dataPoint = _dataCache.internalDataMap[path];

    // First try to get symbol from data point (units-preference plugin)
    if (dataPoint?.symbol != null) {
      return dataPoint!.symbol;
    }

    // Fallback: get symbol from conversions data (standard stream with client-side conversions)
    final availableUnits = getAvailableUnits(path);
    if (availableUnits.isEmpty) {
      return null;
    }

    // Get the first/preferred conversion for this path
    final unit = availableUnits.first;
    final conversionInfo = getConversionInfo(path, unit);
    return conversionInfo?.symbol;
  }

  /// Get live AIS vessel data from WebSocket cache
  /// Returns vessel data populated by vessels.* wildcard subscription
  Map<String, Map<String, dynamic>> getLiveAISVessels() {
    return _aisManager.getLiveAISVessels();
  }

  /// Fetch all AIS vessels from REST API and populate the registry.
  Future<void> fetchAllAISVessels() async {
    await _aisManager.fetchAndPopulateRegistry();
  }

  // Cached self MMSI for fast matching in hot path
  String? _selfMMSI;

  /// Check if a delta context refers to the own vessel.
  bool _isSelfContext(String context) {
    if (context == _vesselContext) return true;
    if (_selfMMSI != null && context.contains(_selfMMSI!)) return true;
    return false;
  }

  /// Fetch vessel self ID from SignalK server using the /self endpoint
  /// Returns the vessel identifier (e.g., "urn:mrn:signalk:uuid:..." or "urn:mrn:imo:mmsi:...")
  Future<String?> getVesselSelfId() async {
    final protocol = _useSecureConnection ? 'https' : 'http';

    try {
      // Use the proper SignalK /self endpoint which returns the self vessel reference
      final response = await http.get(
        Uri.parse('$protocol://$_serverUrl/signalk/v1/api/self'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        // Response is a JSON string like "vessels.urn:mrn:imo:mmsi:367780840"
        final selfRef = response.body.replaceAll('"', '').trim();

        // Extract vessel ID (remove "vessels." prefix if present)
        final vesselId = selfRef.startsWith('vessels.')
            ? selfRef.substring('vessels.'.length)
            : selfRef;
        return vesselId;
      }
    } catch (_) {
      // Ignore vessel ID fetch errors
    }

    return null;
  }

  /// Fetch all available paths from SignalK server
  /// Returns a map of paths with their current values and metadata
  Future<Map<String, dynamic>?> getAvailablePaths() async {
    final protocol = _useSecureConnection ? 'https' : 'http';

    try {
      final response = await http.get(
        Uri.parse('$protocol://$_serverUrl/signalk/v1/api/vessels/$_vesselRestPath'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 30)); // Increased from 10s for busy servers

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {
      // Ignore path fetch errors
    }

    return null;
  }

  /// Get the list of all available paths on the server.
  /// Populated on connect via GET /skServer/availablePaths.
  List<String> get availablePathsList => _availablePaths;

  /// Fetch available paths from the lightweight /skServer/availablePaths endpoint.
  /// Returns a clean JSON array of path names (no values, no auth required).
  Future<void> _fetchAvailablePaths() async {
    final protocol = _useSecureConnection ? 'https' : 'http';

    try {
      final response = await http.get(
        Uri.parse('$protocol://$_serverUrl/skServer/availablePaths'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          _availablePaths = data.cast<String>()..sort();
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Available paths fetch error: $e');
      }
    }
  }

  /// Start periodic refresh of available paths (every 5 minutes).
  void _startAvailablePathsRefresh() {
    _availablePathsRefreshTimer?.cancel();
    _availablePathsRefreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (!_isConnected) {
        timer.cancel();
        return;
      }
      _fetchAvailablePaths();
    });
  }

  /// Fetch conversion formulas from SignalK server
  /// Gets base units, categories, and conversion formulas for all paths
  Future<void> fetchConversions() async {
    await _conversionManager.fetchConversions();
    // Invalidate cache when conversions update
    _conversionsDataView = null;
  }

  /// Manually reload conversions from server
  /// Useful when user changes preferences on server and wants immediate update
  Future<void> loadConversions() async {
    await fetchConversions();
    notifyListeners(); // Notify UI to update
  }

  /// Fetch and cache user's unit preferences
  /// GET /signalk/v1/unitpreferences/config - get active preset name
  /// GET /signalk/v1/unitpreferences/presets/:name - get preset details
  Future<void> fetchUserUnitPreferences() async {
    final connectionId = _authToken?.connectionId;
    final protocol = _useSecureConnection ? 'https' : 'http';

    try {
      // Get the current unit preferences config (active preset name)
      final configResponse = await http.get(
        Uri.parse('$protocol://$_serverUrl/signalk/v1/unitpreferences/config'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 10));

      if (configResponse.statusCode == 200) {
        final data = jsonDecode(configResponse.body);
        final activePreset = data['activePreset'] as String?;

        if (activePreset != null && activePreset.isNotEmpty) {
          // Fetch the full preset data
          await _fetchAndCacheUserPreset(connectionId, activePreset);
        }
      }
    } catch (_) {
      // Ignore unit preferences fetch errors
    }
  }

  /// Fetch a specific preset and cache it locally
  Future<void> _fetchAndCacheUserPreset(String? connectionId, String presetName) async {
    final protocol = _useSecureConnection ? 'https' : 'http';

    try {
      // Fetch the preset details
      final presetResponse = await http.get(
        Uri.parse('$protocol://$_serverUrl/signalk/v1/unitpreferences/presets/$presetName'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 10));

      if (presetResponse.statusCode == 200) {
        final presetData = jsonDecode(presetResponse.body) as Map<String, dynamic>;

        // Cache locally via StorageService if we have a connection ID
        if (connectionId != null) {
          await _storageService?.saveUserUnitPreferences(
            connectionId: connectionId,
            presetName: presetName,
            presetData: presetData,
          );
        }
      }
    } catch (_) {
      // Ignore preset fetch errors
    }
  }

  /// Fetch the active unit preferences preset from the server
  /// GET /signalk/v1/unitpreferences/active
  /// This returns the fully-resolved preset with conversion formulas per category
  /// Used for REST API data that doesn't include meta.displayUnits
  Future<Map<String, dynamic>?> fetchActiveUnitPreferences() async {
    final protocol = _useSecureConnection ? 'https' : 'http';

    try {
      final response = await http.get(
        Uri.parse('$protocol://$_serverUrl/signalk/v1/unitpreferences/active'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {
      // Ignore active unit preferences fetch errors
    }

    return null;
  }

  /// Get cached user unit preferences if available
  Map<String, dynamic>? getCachedUserUnitPreferences() {
    if (_authToken == null || _authToken!.authType != AuthType.user) {
      return null;
    }

    final connectionId = _authToken!.connectionId;
    if (connectionId == null) return null;

    return _storageService?.getUserUnitPreset(connectionId);
  }

  /// Get the name of the cached user preset
  String? getCachedUserPresetName() {
    if (_authToken == null || _authToken!.authType != AuthType.user) {
      return null;
    }

    final connectionId = _authToken!.connectionId;
    if (connectionId == null) return null;

    return _storageService?.getUserUnitPresetName(connectionId);
  }

  /// Get conversion data for a specific path
  PathConversionData? getConversionDataForPath(String path) {
    return _conversionManager.getConversionDataForPath(path);
  }

  /// Get base unit for a specific path
  String? getBaseUnit(String path) {
    return _conversionManager.getBaseUnit(path);
  }

  /// Get available target units for a specific path
  List<String> getAvailableUnits(String path) {
    return _conversionManager.getAvailableUnits(path);
  }

  /// Get conversion info for a specific path and target unit
  ConversionInfo? getConversionInfo(String path, String targetUnit) {
    return _conversionManager.getConversionInfo(path, targetUnit);
  }

  /// Get the category for a specific path
  String getCategory(String path) {
    return _conversionManager.getCategory(path);
  }

  /// Get conversion using unitpreferences pattern matching (Data Browser approach)
  /// This is the new approach that works for paths without explicit displayUnits
  ConversionInfo? getUnitPreferencesConversion(String path, String siUnit) {
    return _conversionManager.getUnitPreferencesConversion(path, siUnit);
  }

  /// Get conversion for a known category
  /// Looks up the SI unit from categoryToBaseUnit, or uses provided siUnit as fallback
  ConversionInfo? getConversionForCategory(String category, [String? siUnit]) {
    return _conversionManager.getConversionForCategory(category, siUnit);
  }

  /// Find category for a path using default-categories patterns
  String? findCategoryForPath(String path) {
    return _conversionManager.findCategoryForPath(path);
  }

  /// Convert a value using category-based unit preferences.
  /// Used for locally-calculated values (like distance) that don't have a specific SignalK path.
  double? convertByCategory(String category, double siValue) {
    final conversionInfo = getConversionForCategory(category);
    if (conversionInfo == null) return null;

    // Use PathMetadata's formula evaluation
    final metadata = PathMetadata(
      path: '_category_$category',
      formula: conversionInfo.formula,
      inverseFormula: conversionInfo.inverseFormula,
      symbol: conversionInfo.symbol,
    );
    return metadata.convert(siValue);
  }

  /// Get the unit symbol for a category.
  String? getSymbolForCategory(String category) {
    return getConversionForCategory(category)?.symbol;
  }

  /// Get the unit definitions map (siUnit → conversions)
  Map<String, dynamic>? get unitDefinitions => _conversionManager.unitDefinitions;

  /// Get the default categories map (category → path patterns)
  Map<String, dynamic>? get defaultCategories => _conversionManager.defaultCategories;

  /// Get the preset details map (category → targetUnit/symbol)
  Map<String, dynamic>? get presetDetails => _conversionManager.presetDetails;

  /// Get the active preset name
  String? get activePresetName => _conversionManager.activePresetName;

  /// Get user's display unit preferences for a path (from WebSocket meta)
  /// Returns displayUnits map containing: {units, formula, symbol}
  Map<String, dynamic>? getDisplayUnits(String path) {
    return _displayUnitsCache[path];
  }

  /// Check if we have display unit preferences for a path
  bool hasDisplayUnits(String path) {
    return _displayUnitsCache.containsKey(path);
  }

  /// Get display unit formula for a path (for client-side conversion)
  String? getDisplayUnitFormula(String path) {
    final displayUnits = _displayUnitsCache[path];
    if (displayUnits == null) return null;
    return displayUnits['formula'] as String?;
  }

  /// Get display unit symbol for a path
  String? getDisplayUnitSymbol(String path) {
    final displayUnits = _displayUnitsCache[path];
    if (displayUnits == null) return null;
    return displayUnits['symbol'] as String?;
  }

  /// Clear display units cache (called on disconnect or user logout)
  void clearDisplayUnitsCache() {
    _displayUnitsCache.clear();
  }

  /// Extract all paths from vessel data tree recursively
  /// Returns a list of path strings (e.g., 'navigation.speedOverGround')
  List<String> extractPathsFromTree(Map<String, dynamic> tree, [String prefix = '']) {
    final paths = <String>[];

    tree.forEach((key, value) {
      // Skip metadata keys
      if (key.startsWith('_') || key == '\$source' || key == 'timestamp' || key == 'meta' || key == 'values') {
        return;
      }

      final currentPath = prefix.isEmpty ? key : '$prefix.$key';

      if (value is Map<String, dynamic>) {
        // Add path if it has a value
        if (value.containsKey('value')) {
          paths.add(currentPath);
        }
        // Always recurse to find nested paths (nodes can have both value AND children)
        paths.addAll(extractPathsFromTree(value, currentPath));
      }
    });

    return paths;
  }

  /// Get available sources for a specific path
  /// Returns a map of source labels and their metadata
  Future<Map<String, dynamic>?> getSourcesForPath(String path) async {
    final protocol = _useSecureConnection ? 'https' : 'http';

    // Convert path to API format (e.g., navigation.speedOverGround -> navigation/speedOverGround)
    final apiPath = path.replaceAll('.', '/');

    try {
      final response = await http.get(
        Uri.parse('$protocol://$_serverUrl/signalk/v1/api/vessels/$_vesselRestPath/$apiPath'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 20)); // Increased from 5s for busy servers

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // SignalK format: sources are in the 'values' object
        if (data.containsKey('values') && data['values'] is Map) {
          final sources = data['values'] as Map<String, dynamic>;

          // Add the current active source to the result
          final result = <String, dynamic>{};
          final currentSource = data['\$source'] as String?;

          sources.forEach((key, value) {
            result[key] = {
              ...value as Map<String, dynamic>,
              'isActive': key == currentSource,
            };
          });

          return result;
        }

        // Fallback: if no 'values' field, return basic info
        if (data.containsKey('\$source')) {
          return {
            data['\$source'] as String: {
              'value': data['value'],
              'timestamp': data['timestamp'],
              'isActive': true,
            }
          };
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching sources for path $path: $e');
      }
    }

    return null;
  }

  /// Subscribe to a set of paths (called when template/dashboard loads)
  /// [ownerId] identifies the subscriber for registry tracking.
  Future<void> subscribeToPaths(List<String> paths, {String ownerId = 'general'}) async {
    if (!_isConnected || _channel == null) {
      if (kDebugMode) {
        print('Cannot subscribe: not connected');
      }
      return;
    }

    _subscriptionRegistry.addPaths(ownerId, paths);
    await _updateSubscription();
  }

  /// Unsubscribe from paths (called when template/dashboard unloads)
  /// [ownerId] identifies the subscriber to unregister.
  Future<void> unsubscribeFromPaths(List<String> paths, {String ownerId = 'general'}) async {
    if (!_isConnected || _channel == null) return;

    _subscriptionRegistry.removePaths(ownerId, paths);

    // NOTE: Per-path unsubscribe is NOT supported by SignalK server.
    // Server only supports wildcard: {"context":"*","unsubscribe":[{"path":"*"}]}
    // Sending per-path unsubscribe causes server to throw error and close socket.
    // Subscriptions are cleaned up automatically when WebSocket disconnects/reconnects.
    // Internal state (registry) is still updated above for accurate tracking.
  }

  /// Update subscription with current active paths
  /// ALWAYS uses standard SignalK stream format (client-side conversions)
  Future<void> _updateSubscription() async {
    if (!_isConnected || _channel == null) return;
    // Auth guard: no auth = no subscriptions
    if (_authToken == null) return;

    final pathsToSubscribe = <String>[..._activePaths];

    if (pathsToSubscribe.isEmpty) return;

    // Standard SignalK subscription format with sendMeta per path
    // Use MMSI/URN context if available, fall back to vessels.self
    final subscriptionContext = _vesselContext ?? 'vessels.self';
    final subscription = {
      'context': subscriptionContext,
      'subscribe': pathsToSubscribe.map((path) => {
        'path': path,
        'format': 'delta',
        'policy': 'instant',
        'sendMeta': 'all',
      }).toList(),
    };

    _channel?.sink.add(jsonEncode(subscription));

  }

  /// Subscribe to autopilot paths (now uses main channel — single WS connection)
  Future<void> subscribeToAutopilotPaths(List<String> paths) async {
    if (!_isConnected || _channel == null) {
      if (kDebugMode) {
        print('Cannot subscribe to autopilot paths: not connected');
      }
      return;
    }

    final newPaths = paths.where((p) => !_autopilotPaths.contains(p)).toList();
    if (newPaths.isEmpty) return;

    _autopilotPaths.addAll(newPaths);

    // Subscribe via main channel using the registry
    _subscriptionRegistry.addPaths('autopilot', newPaths);
    await _updateSubscription();
  }

  /// Load initial AIS vessel data and subscribe for updates
  /// Two-phase approach:
  /// 1. Fetch all existing vessels via REST API (once only)
  /// 2. Subscribe for real-time updates only
  Future<void> loadAndSubscribeAISVessels() async {
    await _aisManager.loadAndSubscribeAISVessels();
  }

  /// Start periodic cache cleanup to prevent unbounded memory growth
  void _startCacheCleanup() {
    _dataCache.startCacheCleanup();
  }
  /// Subscribe to all AIS vessels using wildcard subscription
  /// Requires units-preference plugin with wildcard support
  void subscribeToAllAISVessels() {
    _aisManager.subscribeToAllAISVessels();
  }

  /// Enable or disable notifications (now uses main WS channel — single connection)
  Future<void> setNotificationsEnabled(bool enabled) async {
    _notificationManager.setNotificationsEnabledFlag(enabled);
    if (enabled) {
      // Subscribe to notifications via main channel
      _subscriptionRegistry.register('notifications', ['notifications.*']);
    } else {
      _subscriptionRegistry.unregister('notifications');
    }
    if (_isConnected) {
      await _updateSubscription();
    }
    notifyListeners();
  }

  /// Disconnect from server
  Future<void> disconnect() async {
    try {
      // Mark as intentional disconnect to prevent auto-reconnect
      _intentionalDisconnect = true;
      _reconnectTimer?.cancel();
      // Flush displayUnits cache immediately before clearing
      if (_displayUnitsSaveTimer?.isActive ?? false) {
        _displayUnitsSaveTimer!.cancel();
        await _storageService?.saveDisplayUnitsCache(_serverUrl, _displayUnitsCache);
      }
      _aisManager.dispose();
      _reconnectAttempts = 0;

      // Disconnect main data channel
      await _subscription?.cancel();
      _subscription = null;

      await _channel?.sink.close();
      _channel = null;

      _isConnected = false;
      _dataCache.internalDataMap.clear();
      _latestDataView = null;
      _conversionManager.internalDataMap.clear();
      _conversionsDataView = null;
      _subscriptionRegistry.clear();
      _autopilotPaths.clear();
      _vesselContext = null;
      _availablePaths = [];
      _availablePathsRefreshTimer?.cancel();
      _selfMMSI = null;
      _ensuredResourceTypes.clear();
      _displayUnitsCache.clear();
      _metadataStore.clear();
      _aisManager.registry.clear();

      // Disconnect notification channel if it's connected
      // (still separate until notification routing is moved to main _handleMessage)
      await _notificationManager.disconnectNotificationChannel();

      if (kDebugMode) {
        print('Disconnected and cleaned up WebSocket channels');

      }

      // Only emit disconnected if not in the middle of reconnecting
      // This prevents the "Connection Lost" overlay from flashing during retry attempts
      if (_connectionState != SignalKConnectionState.reconnecting) {
        _connectionState = SignalKConnectionState.disconnected;
        _connectionStateController.add(SignalKConnectionState.disconnected);
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error during disconnect: $e');
      }
    }
  }

  /// Manually trigger reconnection (e.g., from retry button)
  Future<void> reconnect() async {
    if (_serverUrl.isEmpty) return;

    _reconnectAttempts = 0;
    _intentionalDisconnect = false;
    _connectionState = SignalKConnectionState.reconnecting;
    _connectionStateController.add(SignalKConnectionState.reconnecting);

    try {
      await connect(
        _serverUrl,
        secure: _useSecureConnection,
        authToken: _authToken,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Manual reconnect failed: $e');
      }
      // connect() failure doesn't trigger _handleDisconnect (that's only for established connections)
      // Start the auto-retry loop
      _attemptReconnect();
    }
  }

  @override
  void dispose() {
    disconnect();
    _connectionStateController.close();
    _dataCache.dispose();
    _conversionManager.dispose();
    _notificationManager.dispose();
    _aisManager.dispose();
    _metadataStore.dispose();
    super.dispose();
  }
}

/// SignalK Notification model
class SignalKNotification {
  final String key;
  final String state; // normal, alert, warn, alarm, emergency
  final String message;
  final List<String> method; // visual, sound
  final DateTime timestamp;

  SignalKNotification({
    required this.key,
    required this.state,
    required this.message,
    required this.method,
    required this.timestamp,
  });
}

/// Conversion info for a specific unit
class ConversionInfo {
  final String formula;
  final String inverseFormula;
  final String symbol;
  final String? dateFormat;
  final bool? useLocalTime;

  ConversionInfo({
    required this.formula,
    required this.inverseFormula,
    required this.symbol,
    this.dateFormat,
    this.useLocalTime,
  });

  factory ConversionInfo.fromJson(Map<String, dynamic> json) {
    return ConversionInfo(
      formula: json['formula'] as String,
      inverseFormula: json['inverseFormula'] as String,
      symbol: json['symbol'] as String,
      dateFormat: json['dateFormat'] as String?,
      useLocalTime: json['useLocalTime'] as bool?,
    );
  }
}

/// Path conversion data from SignalK server
class PathConversionData {
  final String? baseUnit;
  final String category;
  final Map<String, ConversionInfo> conversions;

  PathConversionData({
    this.baseUnit,
    required this.category,
    required this.conversions,
  });

  factory PathConversionData.fromJson(Map<String, dynamic> json) {
    final conversionsMap = <String, ConversionInfo>{};
    final conversionsJson = json['conversions'] as Map<String, dynamic>? ?? {};

    conversionsJson.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        conversionsMap[key] = ConversionInfo.fromJson(value);
      }
    });

    return PathConversionData(
      baseUnit: json['baseUnit'] as String?,
      category: json['category'] as String,
      conversions: conversionsMap,
    );
  }
}

/// Central registry for path subscriptions with owner tracking.
/// Each subscriber registers with an owner ID; the union of all owners' paths
/// is the full subscription set.
class PathSubscriptionRegistry {
  final Map<String, Set<String>> _subscriptionsByOwner = {};

  /// Register paths for an owner. Replaces any previous paths for this owner.
  void register(String ownerId, List<String> paths) {
    _subscriptionsByOwner[ownerId] = Set<String>.from(paths);
  }

  /// Add paths to an existing owner's set (additive).
  void addPaths(String ownerId, List<String> paths) {
    _subscriptionsByOwner.putIfAbsent(ownerId, () => {}).addAll(paths);
  }

  /// Unregister all paths for an owner.
  void unregister(String ownerId) {
    _subscriptionsByOwner.remove(ownerId);
  }

  /// Remove specific paths from an owner's set.
  void removePaths(String ownerId, List<String> paths) {
    _subscriptionsByOwner[ownerId]?.removeAll(paths);
    if (_subscriptionsByOwner[ownerId]?.isEmpty ?? false) {
      _subscriptionsByOwner.remove(ownerId);
    }
  }

  /// Get the union of all owners' paths.
  Set<String> get allPaths {
    final result = <String>{};
    for (final paths in _subscriptionsByOwner.values) {
      result.addAll(paths);
    }
    return result;
  }

  /// Get paths for a specific owner.
  Set<String> getPathsForOwner(String ownerId) {
    return _subscriptionsByOwner[ownerId] ?? {};
  }

  /// Check if any paths are registered.
  bool get isEmpty => _subscriptionsByOwner.isEmpty;

  /// Clear all subscriptions.
  void clear() {
    _subscriptionsByOwner.clear();
  }

  /// Get all owner IDs.
  Set<String> get owners => _subscriptionsByOwner.keys.toSet();
}

/// Internal manager for data caching and cleanup
/// Handles _latestData map, cache pruning, and data access methods
class _DataCacheManager {
  // Data storage - keeps latest value for each path
  final Map<String, SignalKDataPoint> _latestData = {};
  Timer? _cacheCleanupTimer;

  // Dependencies injected via function getters for dynamic access
  final Set<String> Function() getActivePaths;
  final bool Function() isConnected;
  final void Function()? onCacheChanged;

  _DataCacheManager({
    required this.getActivePaths,
    required this.isConnected,
    this.onCacheChanged,
  });

  // Direct access to internal map for SignalKService
  Map<String, SignalKDataPoint> get internalDataMap => _latestData;

  /// Get value for specific path, optionally from a specific source
  SignalKDataPoint? getValue(String path, {String? source}) {
    final dataPoint = _latestData[path];
    if (source == null) {
      return dataPoint;
    }
    // Source stored on the data point itself — return if it matches or if no source filter needed
    if (dataPoint?.source == source) {
      return dataPoint;
    }
    // Fallback: return the data point even if source doesn't match
    // (better to show data from a different source than nothing)
    return dataPoint;
  }

  /// Check if data is fresh (within TTL threshold)
  bool isDataFresh(String path, {String? source, int? ttlSeconds}) {
    if (ttlSeconds == null) {
      return true;
    }
    final dataPoint = getValue(path, source: source);
    if (dataPoint == null) {
      return false;
    }
    final now = DateTime.now();
    final age = now.difference(dataPoint.timestamp);
    return age.inSeconds <= ttlSeconds;
  }

  /// Get numeric value for specific path
  double? getNumericValue(String path) {
    final dataPoint = _latestData[path];
    if (dataPoint?.value is num) {
      return (dataPoint!.value as num).toDouble();
    }
    return null;
  }

  /// Get converted numeric value (already in user's preferred units)
  double? getConvertedValue(String path) {
    final dataPoint = _latestData[path];
    return dataPoint?.converted ?? (dataPoint?.value is num ? (dataPoint!.value as num).toDouble() : null);
  }

  /// Start periodic cache cleanup to prevent unbounded memory growth
  void startCacheCleanup() {
    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (!isConnected()) {
        timer.cancel();
        return;
      }
      pruneStaleData();
    });
  }

  /// Remove stale data from cache to prevent memory leaks
  void pruneStaleData() {
    final now = DateTime.now();
    final beforeSize = _latestData.length;
    final activePaths = getActivePaths();

    _latestData.removeWhere((key, dataPoint) {
      // Never prune actively subscribed paths (own vessel data uses bare paths)
      if (activePaths.contains(key)) {
        return false;
      }
      // Never prune environment data (weather, sun/moon, etc.) - updates infrequently
      if (key.startsWith('environment.')) {
        return false;
      }
      // AIS vessel detail data in flat cache - prune if older than 20 minutes
      // (Navigation data is now in AISVesselRegistry which handles its own pruning)
      if (key.startsWith('vessels.')) {
        final age = now.difference(dataPoint.timestamp);
        return age.inMinutes > 20;
      }
      // Other data - prune if older than 15 minutes
      final age = now.difference(dataPoint.timestamp);
      return age.inMinutes > 15;
    });

    final afterSize = _latestData.length;
    final removed = beforeSize - afterSize;
    if (removed > 0) {
      // Notify parent to invalidate cached views
      onCacheChanged?.call();
    }
  }

  void dispose() {
    _cacheCleanupTimer?.cancel();
    _latestData.clear();
  }
}

/// Internal manager for unit conversion operations
/// Uses /signalk/v1/unitpreferences/* endpoints (like Data Browser)
class _ConversionManager {
  // Legacy conversion data (for backward compatibility)
  final Map<String, PathConversionData> _conversionsData = {};

  // New unitpreferences data (from Data Browser approach)
  Map<String, dynamic>? _unitDefinitions;      // siUnit → conversions
  Map<String, dynamic>? _defaultCategories;    // category → path patterns
  Map<String, dynamic>? _presetDetails;        // category → targetUnit/symbol
  Map<String, String>? _categoryToBaseUnit;    // category → SI unit (e.g., "distance" → "m")
  String? _activePresetName;

  // Dependencies injected via function getters
  final String Function() getServerUrl;
  final bool Function() useSecureConnection;
  final Map<String, String> Function() getHeaders;
  final Future<void> Function(Map<String, dynamic>) saveToCache;
  final Map<String, dynamic>? Function() loadFromCache;
  final MetadataStore Function() getMetadataStore;

  _ConversionManager({
    required this.getServerUrl,
    required this.useSecureConnection,
    required this.getHeaders,
    required this.saveToCache,
    required this.loadFromCache,
    required this.getMetadataStore,
  });

  // Direct access to internal map (legacy)
  Map<String, PathConversionData> get internalDataMap => _conversionsData;

  // New accessors for unitpreferences data
  Map<String, dynamic>? get unitDefinitions => _unitDefinitions;
  Map<String, dynamic>? get defaultCategories => _defaultCategories;
  Map<String, dynamic>? get presetDetails => _presetDetails;
  Map<String, String>? get categoryToBaseUnit => _categoryToBaseUnit;
  String? get activePresetName => _activePresetName;

  /// Load conversions from local cache (used at startup before server data)
  void loadFromLocalCache() {
    final cached = loadFromCache();
    if (cached != null) {
      // Load new unitpreferences format if available
      if (cached.containsKey('_unitDefinitions')) {
        _unitDefinitions = cached['_unitDefinitions'] as Map<String, dynamic>?;
        _defaultCategories = cached['_defaultCategories'] as Map<String, dynamic>?;
        _presetDetails = cached['_presetDetails'] as Map<String, dynamic>?;
        _activePresetName = cached['_activePresetName'] as String?;
        // Load categoryToBaseUnit if available
        final ctbu = cached['_categoryToBaseUnit'];
        if (ctbu is Map<String, dynamic>) {
          _categoryToBaseUnit = ctbu.map((k, v) => MapEntry(k, v as String));
        }
      } else if (_conversionsData.isEmpty) {
        // Legacy format - path-based conversions
        _conversionsData.clear();
        cached.forEach((path, conversionJson) {
          if (conversionJson is Map<String, dynamic> && !path.startsWith('_')) {
            _conversionsData[path] = PathConversionData.fromJson(conversionJson);
          }
        });
      }
    }
  }

  /// Fetch unit preferences from server using Data Browser endpoints
  /// GET /signalk/v1/unitpreferences/definitions
  /// GET /signalk/v1/unitpreferences/default-categories
  /// GET /signalk/v1/unitpreferences/categories
  /// GET /signalk/v1/unitpreferences/config
  /// GET /signalk/v1/unitpreferences/presets/{name}
  Future<void> fetchConversions() async {
    final protocol = useSecureConnection() ? 'https' : 'http';
    final serverUrl = getServerUrl();
    final headers = getHeaders();

    try {
      // Fetch all four endpoints in parallel
      final results = await Future.wait([
        http.get(
          Uri.parse('$protocol://$serverUrl/signalk/v1/unitpreferences/definitions'),
          headers: headers,
        ).timeout(const Duration(seconds: 10)),
        http.get(
          Uri.parse('$protocol://$serverUrl/signalk/v1/unitpreferences/default-categories'),
          headers: headers,
        ).timeout(const Duration(seconds: 10)),
        http.get(
          Uri.parse('$protocol://$serverUrl/signalk/v1/unitpreferences/config'),
          headers: headers,
        ).timeout(const Duration(seconds: 10)),
        http.get(
          Uri.parse('$protocol://$serverUrl/signalk/v1/unitpreferences/categories'),
          headers: headers,
        ).timeout(const Duration(seconds: 10)),
      ]);

      final definitionsResponse = results[0];
      final defaultCategoriesResponse = results[1];
      final configResponse = results[2];
      final categoriesResponse = results[3];

      // Parse unit definitions
      if (definitionsResponse.statusCode == 200) {
        _unitDefinitions = jsonDecode(definitionsResponse.body) as Map<String, dynamic>;
      }

      // Parse default categories (path patterns)
      if (defaultCategoriesResponse.statusCode == 200) {
        _defaultCategories = jsonDecode(defaultCategoriesResponse.body) as Map<String, dynamic>;
      }

      // Parse categories (categoryToBaseUnit mapping)
      if (categoriesResponse.statusCode == 200) {
        final data = jsonDecode(categoriesResponse.body) as Map<String, dynamic>;
        final ctbu = data['categoryToBaseUnit'] as Map<String, dynamic>?;
        if (ctbu != null) {
          _categoryToBaseUnit = ctbu.map((k, v) => MapEntry(k, v as String));
        }
      }

      // Get user's active preset - try user applicationData first, then fall back to global config
      String? activePreset;

      // Try user-specific preference first
      try {
        final userResponse = await http.get(
          Uri.parse('$protocol://$serverUrl/signalk/v1/applicationData/user/unitpreferences/1.0.0'),
          headers: headers,
        ).timeout(const Duration(seconds: 10));

        if (userResponse.statusCode == 200) {
          final userConfig = jsonDecode(userResponse.body) as Map<String, dynamic>;
          activePreset = userConfig['activePreset'] as String?;
        }
      } catch (_) {
        // Ignore user applicationData fetch errors
      }

      // Fall back to global config if no user preference
      if (activePreset == null || activePreset.isEmpty) {
        if (configResponse.statusCode == 200) {
          final config = jsonDecode(configResponse.body) as Map<String, dynamic>;
          activePreset = config['activePreset'] as String?;
        }
      }

      _activePresetName = activePreset;

      // Fetch the preset details using the active preset name
      if (_activePresetName != null && _activePresetName!.isNotEmpty) {
        try {
          final presetResponse = await http.get(
            Uri.parse('$protocol://$serverUrl/signalk/v1/unitpreferences/presets/$_activePresetName'),
            headers: headers,
          ).timeout(const Duration(seconds: 10));

          if (presetResponse.statusCode == 200) {
            final presetData = jsonDecode(presetResponse.body) as Map<String, dynamic>;
            _presetDetails = presetData['categories'] as Map<String, dynamic>?;
          }
        } catch (_) {
          // Ignore preset fetch errors
        }
      }


      // Populate MetadataStore from REST data (single source of truth)
      if (_defaultCategories != null && _presetDetails != null && _unitDefinitions != null) {
        getMetadataStore().populateFromPreset(
          defaultCategories: _defaultCategories!,
          presetDetails: _presetDetails!,
          unitDefinitions: _unitDefinitions!,
          categoryToBaseUnit: _categoryToBaseUnit,
        );
      }

      // Save to local cache
      await saveToCache({
        '_unitDefinitions': _unitDefinitions,
        '_defaultCategories': _defaultCategories,
        '_presetDetails': _presetDetails,
        '_categoryToBaseUnit': _categoryToBaseUnit,
        '_activePresetName': _activePresetName,
      });
    } catch (e) {
      if (kDebugMode) {
        print('Unit preferences fetch error: $e');
      }
    }
  }

  /// Find category for a path using defaultCategories patterns
  /// Matches patterns like "*.temperature*", "navigation.heading*"
  String? findCategoryForPath(String path) {
    if (_defaultCategories == null) return null;

    for (final entry in _defaultCategories!.entries) {
      final category = entry.key;
      final categoryData = entry.value;

      if (categoryData is! Map<String, dynamic>) continue;

      final paths = categoryData['paths'];
      if (paths is! List) continue;

      for (final pattern in paths) {
        if (pattern is! String) continue;

        // Convert wildcard pattern to regex
        // *.temperature* → .*\.temperature.*
        // navigation.heading* → navigation\.heading.*
        final regexPattern = pattern
            .replaceAll('.', r'\.')
            .replaceAll('*', '.*');

        try {
          final regex = RegExp('^$regexPattern\$', caseSensitive: false);
          if (regex.hasMatch(path)) {
            return category;
          }
        } catch (e) {
          // Invalid regex, skip this pattern
          continue;
        }
      }
    }

    return null;
  }

  /// Get conversion formula for a path using unitpreferences data
  /// Returns ConversionInfo if found, null otherwise
  ConversionInfo? getUnitPreferencesConversion(String path, String siUnit) {
    if (_unitDefinitions == null || _presetDetails == null) return null;

    // Find category for this path
    final category = findCategoryForPath(path);
    if (category == null) return null;

    return getConversionForCategory(category, siUnit);
  }

  /// Get conversion formula for a known category
  /// Looks up SI unit from categoryToBaseUnit, target unit from user's active preset
  ConversionInfo? getConversionForCategory(String category, [String? siUnit]) {
    if (_presetDetails == null) return null;

    // Step 1: Get SI unit from categoryToBaseUnit (static mapping), fallback to siUnit param
    final resolvedSiUnit = _categoryToBaseUnit?[category] ?? siUnit;
    if (resolvedSiUnit == null) return null;

    // Step 2: Get user's target unit from their active preset
    final categoryPrefs = _presetDetails![category];
    if (categoryPrefs is! Map<String, dynamic>) return null;

    final targetUnit = categoryPrefs['targetUnit'] as String?;
    if (targetUnit == null) return null;

    // If target equals source, no conversion needed - identity
    if (targetUnit == resolvedSiUnit) {
      return ConversionInfo(
        formula: 'value',
        inverseFormula: 'value',
        symbol: resolvedSiUnit,
      );
    }

    // Need unit definitions for non-identity conversions
    if (_unitDefinitions == null) return null;

    // Step 3: Get conversion formula from unit definitions
    final siUnitDef = _unitDefinitions![resolvedSiUnit];
    if (siUnitDef is! Map<String, dynamic>) return null;

    final conversions = siUnitDef['conversions'];
    if (conversions is! Map<String, dynamic>) return null;

    final conversion = conversions[targetUnit];
    if (conversion is! Map<String, dynamic>) return null;

    final formula = conversion['formula'] as String?;
    final symbol = conversion['symbol'] as String?;

    if (formula == null) return null;

    // Build inverse formula if available
    final inverseFormula = conversion['inverseFormula'] as String? ?? '';

    return ConversionInfo(
      formula: formula,
      inverseFormula: inverseFormula,
      symbol: symbol ?? targetUnit,
    );
  }

  /// Get the target unit for a category from the active preset
  String? getTargetUnitForCategory(String category) {
    if (_presetDetails == null) return null;

    final categoryPrefs = _presetDetails![category];
    if (categoryPrefs is! Map<String, dynamic>) return null;

    return categoryPrefs['targetUnit'] as String?;
  }

  /// Get symbol for a category from the active preset
  String? getSymbolForCategory(String category) {
    if (_presetDetails == null) return null;

    final categoryPrefs = _presetDetails![category];
    if (categoryPrefs is! Map<String, dynamic>) return null;

    return categoryPrefs['symbol'] as String?;
  }

  /// Save user's unit preference for a category to the server
  Future<bool> setTargetUnitForCategory(String category, String targetUnit) async {
    final protocol = useSecureConnection() ? 'https' : 'http';
    final serverUrl = getServerUrl();
    final headers = getHeaders();
    headers['Content-Type'] = 'application/json';

    try {
      // Update the category's targetUnit
      final body = jsonEncode({
        'categories': {
          category: {
            'targetUnit': targetUnit,
          }
        }
      });

      final response = await http.put(
        Uri.parse('$protocol://$serverUrl/signalk/v1/unitpreferences/active'),
        headers: headers,
        body: body,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // Update local cache
        _presetDetails ??= {};
        final categoryPrefs = _presetDetails![category] as Map<String, dynamic>? ?? {};
        categoryPrefs['targetUnit'] = targetUnit;
        _presetDetails![category] = categoryPrefs;

        await saveToCache({
          '_unitDefinitions': _unitDefinitions,
          '_defaultCategories': _defaultCategories,
          '_presetDetails': _presetDetails,
          '_categoryToBaseUnit': _categoryToBaseUnit,
          '_activePresetName': _activePresetName,
        });

        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('setTargetUnitForCategory error: $e');
      }
      return false;
    }
  }

  // Legacy methods for backward compatibility
  PathConversionData? getConversionDataForPath(String path) => _conversionsData[path];
  String? getBaseUnit(String path) => _conversionsData[path]?.baseUnit;
  String getCategory(String path) {
    // Try new approach first
    final category = findCategoryForPath(path);
    if (category != null) return category;
    // Fall back to legacy
    return _conversionsData[path]?.category ?? 'none';
  }

  List<String> getAvailableUnits(String path) {
    final conversionData = _conversionsData[path];
    if (conversionData == null) return [];
    return conversionData.conversions.keys.toList();
  }

  ConversionInfo? getConversionInfo(String path, String targetUnit) {
    return _conversionsData[path]?.conversions[targetUnit];
  }

  void dispose() {
    _conversionsData.clear();
    _unitDefinitions = null;
    _defaultCategories = null;
    _presetDetails = null;
    _activePresetName = null;
  }
}

/// Internal manager for notification system
/// Handles notification WebSocket and notification processing
class _NotificationManager {
  // Notification WebSocket
  WebSocketChannel? _notificationChannel;
  StreamSubscription? _notificationSubscription;

  // Notification state
  bool _notificationsEnabled = false;
  final StreamController<SignalKNotification> _notificationController =
      StreamController<SignalKNotification>.broadcast();
  final Map<String, String> _lastNotificationState = {};
  final Map<String, DateTime> _lastNotificationTime = {};

  int get stateMapSize => _lastNotificationState.length;
  int get timeMapSize => _lastNotificationTime.length;

  // Recent notifications cache (last 10 seconds)
  final List<SignalKNotification> _recentNotifications = [];

  // Dependencies injected via function getters
  final AuthToken? Function() getAuthToken;
  final String Function() getNotificationEndpoint;
  final bool Function() isWeatherAlertsOnDashboard;
  final Map<String, SignalKDataPoint> Function() getLatestData;
  final DiagnosticService? Function() getDiagnosticService;
  final String? Function() getVesselContext;

  _NotificationManager({
    required this.getAuthToken,
    required this.getNotificationEndpoint,
    required this.isWeatherAlertsOnDashboard,
    required this.getLatestData,
    required this.getDiagnosticService,
    required this.getVesselContext,
  });

  // Getters
  bool get notificationsEnabled => _notificationsEnabled;
  Stream<SignalKNotification> get notificationStream => _notificationController.stream;

  /// Get recent notifications (last 10 seconds)
  List<SignalKNotification> getRecentNotifications({Duration maxAge = const Duration(seconds: 10)}) {
    final cutoff = DateTime.now().subtract(maxAge);
    _recentNotifications.removeWhere((n) => n.timestamp.isBefore(cutoff));
    return List.unmodifiable(_recentNotifications);
  }

  /// Enable or disable notifications (WS connection now managed by SignalKService)
  Future<void> setNotificationsEnabled(bool enabled) async {
    if (_notificationsEnabled == enabled) {
      return;
    }

    _notificationsEnabled = enabled;

    if (enabled) {
      await connectNotificationChannel();
    } else {
      await disconnectNotificationChannel();
    }
  }

  /// Set the enabled flag without managing WS connections.
  /// Used when notifications route through the main channel.
  void setNotificationsEnabledFlag(bool enabled) {
    _notificationsEnabled = enabled;
    if (!enabled) {
      _lastNotificationState.clear();
      _lastNotificationTime.clear();
      _recentNotifications.clear();
    }
  }

  /// Connect to notification WebSocket
  Future<void> connectNotificationChannel() async {
    final authToken = getAuthToken();
    if (authToken == null) {
      return;
    }

    try {
      final wsUrl = getNotificationEndpoint();

      final headers = <String, String>{
        'Authorization': 'Bearer ${authToken.token}',
      };

      final socket = await WebSocket.connect(wsUrl, headers: headers);
      socket.pingInterval = const Duration(seconds: 30);
      _notificationChannel = IOWebSocketChannel(socket);

      _notificationSubscription = _notificationChannel!.stream.listen(
        handleNotificationMessage,
        onError: (error) {
          if (kDebugMode) {
            print('❌ Notification WebSocket error: $error');
          }
        },
        onDone: () {},
      );

      await Future.delayed(const Duration(milliseconds: 100));
      subscribeToNotifications();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error connecting notification channel: $e');
      }
    }
  }

  /// Disconnect notification WebSocket
  Future<void> disconnectNotificationChannel() async {
    try {
      await _notificationSubscription?.cancel();
      _notificationSubscription = null;

      await _notificationChannel?.sink.close();
      _notificationChannel = null;

      _lastNotificationState.clear();
      _lastNotificationTime.clear();
      _recentNotifications.clear();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error disconnecting notification channel: $e');
      }
    }
  }

  /// Subscribe to notifications on the notification channel
  void subscribeToNotifications() {
    if (_notificationChannel == null) return;

    final subscriptionContext = getVesselContext() ?? 'vessels.self';
    final subscription = {
      'context': subscriptionContext,
      'subscribe': [
        {
          'path': 'notifications.*',
          'format': 'delta',
          'policy': 'instant',
        }
      ]
    };

    _notificationChannel?.sink.add(jsonEncode(subscription));
  }

  /// Handle messages from notification WebSocket
  void handleNotificationMessage(dynamic message) {
    try {
      getDiagnosticService()?.instrumentWsMessage('notification');
      final data = jsonDecode(message);

      if (data is! Map<String, dynamic>) {
        return;
      }

      if (data['updates'] != null) {
        final update = SignalKUpdate.fromJson(data);

        for (final updateValue in update.updates) {
          for (final value in updateValue.values) {
            if (value.path.startsWith('notifications.')) {
              handleNotification(value.path, value.value, updateValue.timestamp);
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error parsing notification message: $e');
      }
    }
  }

  /// Handle incoming notification
  void handleNotification(String path, dynamic value, DateTime timestamp) {
    try {
      final key = path.replaceFirst('notifications.', '');

      // Gate NWS weather notifications
      if (key.startsWith('weather.nws.')) {
        // Gate 1: Only show if weather_alerts widget is on the dashboard
        if (!isWeatherAlertsOnDashboard()) return;

        // Gate 2: Only show if the alert is still active
        // Extract alertId from key like "weather.nws.alert.{alertId}.xxx"
        final parts = key.split('.');
        if (parts.length >= 4) {
          final alertId = parts[3];
          final data = getLatestData();
          final prefix = 'environment.outside.nws.alert.$alertId';

          // Look up expires, ends, urgency from cached data
          final expiresStr = data['$prefix.expires']?.value?.toString();
          final endsStr = data['$prefix.ends']?.value?.toString();
          final urgencyStr = data['$prefix.urgency']?.value?.toString();

          final expires = expiresStr != null ? DateTime.tryParse(expiresStr) : null;
          final ends = endsStr != null ? DateTime.tryParse(endsStr) : null;

          if (!NWSAlertUtils.isAlertActive(
            expires: expires,
            ends: ends,
            urgency: urgencyStr,
          )) {
            return;
          }
        }
      }

      if (value is Map<String, dynamic>) {
        final state = value['state'] as String?;
        final message = value['message'] as String?;
        final method = value['method'] as List?;

        if (state != null && message != null) {
          final lastState = _lastNotificationState[key];
          if (lastState == state) {
            return;
          }

          // Temporal throttle: suppress same key+state within 30 seconds
          final throttleKey = '$key:$state';
          final lastTime = _lastNotificationTime[throttleKey];
          if (lastTime != null && timestamp.difference(lastTime).inSeconds < 30) {
            return;
          }

          _lastNotificationState[key] = state;
          _lastNotificationTime[throttleKey] = timestamp;

          final notification = SignalKNotification(
            key: key,
            state: state,
            message: message,
            method: method?.map((e) => e.toString()).toList() ?? [],
            timestamp: timestamp,
          );

          _notificationController.add(notification);
          _recentNotifications.add(notification);
          // Prevent unbounded growth - prune old entries
          final cutoff = DateTime.now().subtract(const Duration(seconds: 10));
          _recentNotifications.removeWhere((n) => n.timestamp.isBefore(cutoff));
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error processing notification: $e');
      }
    }
  }

  Future<void> dispose() async {
    await disconnectNotificationChannel();
    await _notificationController.close();
  }
}

/// Internal manager for AIS vessel tracking
/// Handles vessel data fetching, caching, and periodic refresh
class _AISManager {
  // Fields
  Timer? _aisRefreshTimer;
  bool _aisInitialLoadDone = false;

  /// Indexed vessel store — single authority for AIS data and pruning.
  late final AISVesselRegistry registry = AISVesselRegistry();

  /// Core navigation paths — fast-changing, subscribed at instant rate
  static const _aisNavPaths = [
    'navigation.position',
    'navigation.courseOverGroundTrue',
    'navigation.speedOverGround',
    'navigation.headingTrue',
  ];

  /// Detail/metadata paths — slow-changing, subscribed at 60s rate
  /// Single source of truth: drives subscription, REST caching, and context scanning
  static const _aisDetailPaths = [
    'navigation.state',
    'navigation.destination.commonName',
    'design.aisShipType',
    'design.length',
    'design.beam',
    'design.draft',
    'sensors.ais.class',
    'sensors.ais.status', // from sk-ais-status-plugin
    'communication.callsignVhf',
    'registrations',
    'name',
  ];

  // Dependencies (inject as function getters)
  final String Function() getServerUrl;
  final bool Function() useSecureConnection;
  final Map<String, String> Function() getHeaders;
  final bool Function() isConnected;
  final WebSocketChannel? Function() getChannel;
  final String? Function() getVesselContext;
  final Map<String, SignalKDataPoint> Function() getDataCache;

  // Cached self vessel ID for filtering
  String? _cachedSelfVesselId;

  _AISManager({
    required this.getServerUrl,
    required this.useSecureConnection,
    required this.getHeaders,
    required this.isConnected,
    required this.getChannel,
    required this.getVesselContext,
    required this.getDataCache,
  });

  /// Get live AIS vessel data — delegates to registry.
  /// Returns raw SI values (radians, m/s). Callers must convert for display.
  Map<String, Map<String, dynamic>> getLiveAISVessels() {
    final vessels = <String, Map<String, dynamic>>{};

    for (final entry in registry.vessels.entries) {
      final vessel = entry.value;
      if (!vessel.hasPosition) continue;

      vessels[vessel.vesselId] = {
        'latitude': vessel.latitude,
        'longitude': vessel.longitude,
        'name': vessel.name,
        'cog': vessel.cogRad,           // Raw SI: radians
        'sog': vessel.sogMs,            // Raw SI: m/s
        'sogRaw': vessel.sogMs,         // Alias for backward compat
        'timestamp': vessel.lastSeen,
        'fromGET': vessel.fromREST,
        'aisShipType': vessel.aisShipType,
        'navState': vessel.navState,
        'headingTrue': vessel.headingTrueRad, // Raw SI: radians
        'aisStatus': vessel.aisStatus,
      };
    }

    return vessels;
  }

  /// Resolve a dotted SignalK path from nested REST JSON
  /// Unwraps {value: ...} wrappers automatically
  static dynamic _resolveRestValue(Map<String, dynamic> data, String path) {
    final parts = path.split('.');
    dynamic current = data;
    for (final part in parts) {
      if (current is Map<String, dynamic>) {
        current = current[part];
      } else {
        return null;
      }
    }
    // SignalK REST wraps leaf values in {value: ...}
    if (current is Map<String, dynamic> && current.containsKey('value')) {
      return current['value'];
    }
    return current;
  }

  /// Fetch AIS vessels from REST API and populate the registry.
  /// Stores raw SI values (no conversions).
  Future<void> fetchAndPopulateRegistry() async {
    final protocol = useSecureConnection() ? 'https' : 'http';
    final endpoint = '$protocol://${getServerUrl()}/signalk/v1/api/vessels';

    try {
      final response = await http.get(
        Uri.parse(endpoint),
        headers: getHeaders(),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final vesselsData = jsonDecode(response.body) as Map<String, dynamic>;

        // Fetch self vessel ID directly from /self endpoint
        try {
          final selfResponse = await http.get(
            Uri.parse('$protocol://${getServerUrl()}/signalk/v1/api/self'),
            headers: getHeaders(),
          ).timeout(const Duration(seconds: 5));

          if (selfResponse.statusCode == 200) {
            final selfRef = selfResponse.body.replaceAll('"', '').trim();
            _cachedSelfVesselId = selfRef.startsWith('vessels.')
                ? selfRef.substring('vessels.'.length)
                : selfRef;
            registry.setSelfVesselId(_cachedSelfVesselId);
          }
        } catch (_) {
          // Ignore self-fetch errors
        }

        // Build registry-compatible data: vesselId → {path: value, ...}
        final registryData = <String, Map<String, dynamic>>{};
        final dataCache = getDataCache();
        final now = DateTime.now();

        for (final entry in vesselsData.entries) {
          final vesselId = entry.key;
          if (vesselId == 'self' || vesselId == _cachedSelfVesselId) continue;

          final vesselData = entry.value as Map<String, dynamic>?;
          if (vesselData == null) continue;

          final navigation = vesselData['navigation'] as Map<String, dynamic>?;
          final position = navigation?['position'] as Map<String, dynamic>?;
          if (position == null) continue;

          final positionValue = position['value'] as Map<String, dynamic>?;
          final lat = positionValue?['latitude'];
          final lon = positionValue?['longitude'];
          if (lat is! num || lon is! num) continue;

          final fields = <String, dynamic>{
            'navigation.position': {'latitude': lat.toDouble(), 'longitude': lon.toDouble()},
          };

          // Resolve nav and detail paths — raw SI, no conversion
          for (final path in [..._aisNavPaths, ..._aisDetailPaths]) {
            if (path == 'navigation.position') continue;
            final value = _resolveRestValue(vesselData, path);
            if (value != null) {
              fields[path] = value;
            }
          }

          // Resolve name separately (not in nav/detail lists but needed)
          final nameVal = _resolveRestValue(vesselData, 'name');
          if (nameVal is String) fields['name'] = nameVal;

          registryData[vesselId] = fields;

          // Also store detail data in flat cache for _getExtraVesselData() lookups
          final vesselContext = 'vessels.$vesselId';
          for (final path in _aisDetailPaths) {
            final value = _resolveRestValue(vesselData, path);
            if (value != null) {
              dataCache['$vesselContext.$path'] = SignalKDataPoint(
                path: path,
                value: value,
                timestamp: now,
                fromGET: true,
              );
            }
          }
        }

        registry.updateFromREST(registryData);
        registry.notifyChanged();
      }
    } catch (e) {
      if (kDebugMode) {
        print('AIS fetch error: $e');
      }
    }
  }

  /// Load AIS vessels from REST and subscribe for WebSocket updates.
  Future<void> loadAndSubscribeAISVessels() async {
    if (!_aisInitialLoadDone) {
      _aisInitialLoadDone = true;
      await fetchAndPopulateRegistry();
      registry.startPruning();

      await Future.delayed(const Duration(seconds: 10));
      startAISRefreshTimer();
    }

    subscribeToAllAISVessels();
  }

  /// Start periodic AIS refresh timer — only updates slow-changing detail data.
  /// Skips vessels whose WebSocket data is recent (within 30s).
  void startAISRefreshTimer() {
    _aisRefreshTimer?.cancel();
    _aisRefreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      if (!isConnected()) {
        timer.cancel();
        return;
      }

      // Re-fetch from REST to pick up new vessels and slow-changing details
      await fetchAndPopulateRegistry();
    });
  }

  /// Subscribe to all AIS vessels using wildcard subscription
  void subscribeToAllAISVessels() {
    final channel = getChannel();
    if (channel == null) return;

    final aisSubscription = {
      'context': 'vessels.*',
      'subscribe': [
        for (final path in _aisNavPaths)
          {'path': path, 'format': 'delta', 'policy': 'instant'},
        for (final path in _aisDetailPaths)
          {'path': path, 'period': 60000, 'format': 'delta', 'policy': 'ideal'},
      ],
    };

    channel.sink.add(jsonEncode(aisSubscription));
  }

  void dispose() {
    _aisRefreshTimer?.cancel();
    _aisRefreshTimer = null;
    _aisInitialLoadDone = false;
    registry.clear();
  }
}
