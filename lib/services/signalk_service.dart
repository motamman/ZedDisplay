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
import '../utils/conversion_utils.dart';
import 'zones_cache_service.dart';
import 'interfaces/data_service.dart';
import 'storage_service.dart';

/// Connection state for SignalK server
enum SignalKConnectionState {
  connected,
  reconnecting,
  disconnected,
}

/// Service to connect to SignalK server and stream data
class SignalKService extends ChangeNotifier implements DataService {
  // Main data WebSocket (units-preference endpoint)
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  // Autopilot WebSocket (standard endpoint for autopilot data)
  WebSocketChannel? _autopilotChannel;
  StreamSubscription? _autopilotSubscription;

  // Connection state
  bool _isConnected = false;
  String? _errorMessage;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  bool _intentionalDisconnect = false;
  bool _wasConnected = false;

  // Connection state stream (for UI overlay without triggering rebuilds)
  final _connectionStateController = StreamController<SignalKConnectionState>.broadcast();
  SignalKConnectionState _connectionState = SignalKConnectionState.disconnected;

  // Data cache cleanup
  Timer? _cacheCleanupTimer;

  // Data storage - moved to _DataCacheManager
  UnmodifiableMapView<String, SignalKDataPoint>? _latestDataView;

  // Conversion data - moved to _ConversionManager
  UnmodifiableMapView<String, PathConversionData>? _conversionsDataView;

  // Active subscriptions - only paths currently needed by UI
  final Set<String> _activePaths = {};
  final Set<String> _autopilotPaths = {}; // Separate tracking for autopilot paths
  String? _vesselContext;

  // User's display unit preferences from WebSocket meta (sendMeta=all per subscription)
  // Maps path to displayUnits configuration: {category, targetUnit, formula, inverseFormula, symbol}
  final Map<String, Map<String, dynamic>> _displayUnitsCache = {};

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
    );
    _notificationManager = _NotificationManager(
      getAuthToken: () => _authToken,
      getNotificationEndpoint: () => _getNotificationEndpoint(),
    );
    _aisManager = _AISManager(
      getServerUrl: () => _serverUrl,
      useSecureConnection: () => _useSecureConnection,
      getHeaders: () => _getHeaders(),
      isConnected: () => _isConnected,
      getChannel: () => _channel,
      getVesselContext: () => _vesselContext,
      getDataCache: () => _dataCache.internalDataMap,
      convertValueForPath: (path, value) => _convertValueForPath(path, value),
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

  /// Get recent notifications (last 10 seconds by default)
  List<SignalKNotification> getRecentNotifications({Duration maxAge = const Duration(seconds: 10)}) {
    return _notificationManager.getRecentNotifications(maxAge: maxAge);
  }

  AuthToken? get authToken => _authToken;
  ZonesCacheService? get zonesCache => _zonesCache;

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
    // Disconnect any existing connection first
    if (_isConnected || _channel != null) {
      if (kDebugMode) {
        print('Disconnecting existing connection before new connect...');
      }
      await disconnect();
      // Give the socket time to fully close
      await Future.delayed(const Duration(milliseconds: 800));

      if (kDebugMode) {
        print('Old connection closed, starting new connection...');
      }
    }

    _serverUrl = serverUrl;
    _useSecureConnection = secure;
    _authToken = authToken;

    // Load cached conversions immediately for instant display
    // Server data will replace this when it arrives
    _conversionManager.loadFromLocalCache();
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
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
      );

      _isConnected = true;
      _wasConnected = true;
      _errorMessage = null;
      _reconnectAttempts = 0; // Reset reconnect attempts on successful connection
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

      // Start periodic cache cleanup to prevent memory growth
      _startCacheCleanup();

      // Auto-connect notification channel if notifications are enabled
      if (_notificationManager.notificationsEnabled && _authToken != null) {
        await _notificationManager.connectNotificationChannel();
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
    } catch (e) {
      _errorMessage = 'Connection failed: $e';
      _isConnected = false;
      notifyListeners();
      rethrow;
    }
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

    // Standard SignalK stream with sendMeta=all to receive displayUnits
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

  /// Get autopilot WebSocket endpoint (always standard SignalK stream)
  String _getAutopilotEndpoint() {
    final wsProtocol = _useSecureConnection ? 'wss' : 'ws';
    var endpoint = '$wsProtocol://$_serverUrl/signalk/v1/stream';
    if (_authToken != null) {
      endpoint += '?token=${Uri.encodeComponent(_authToken!.token)}';
    }
    return endpoint;
  }

  /// Connect autopilot channel for real-time autopilot data
  Future<void> _connectAutopilotChannel() async {
    if (_autopilotChannel != null) {
      if (kDebugMode) {
        print('Autopilot channel already connected');
      }
      return;
    }

    try {
      final wsUrl = _getAutopilotEndpoint();

      if (kDebugMode) {
        print('Connecting autopilot channel to standard stream: $wsUrl');
      }

      if (_authToken != null) {
        final headers = <String, String>{
          'Authorization': 'Bearer ${_authToken!.token}',
        };
        final socket = await WebSocket.connect(wsUrl, headers: headers);
        socket.pingInterval = const Duration(seconds: 30);
        _autopilotChannel = IOWebSocketChannel(socket);
      } else {
        _autopilotChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      }

      // Listen to autopilot messages (same handler as main channel for data)
      _autopilotSubscription = _autopilotChannel!.stream.listen(
        _handleMessage,
        onError: (error) {
          if (kDebugMode) {
            print('Autopilot channel error: $error');
          }
        },
        onDone: () {
          if (kDebugMode) {
            print('Autopilot channel disconnected');
          }
          _autopilotChannel = null;
          _autopilotSubscription = null;
        },
      );

      if (kDebugMode) {
        print('Autopilot channel connected successfully');
      }

      // Send subscription for autopilot paths if any exist
      await _sendAutopilotSubscription();
    } catch (e) {
      if (kDebugMode) {
        print('Failed to connect autopilot channel: $e');
      }
      _autopilotChannel = null;
      _autopilotSubscription = null;
    }
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

      if (kDebugMode) {
        print('Vessel context: $_vesselContext');
      }

      // For units-preference plugin, wait for template paths
      if (_authToken != null) {
        if (kDebugMode) {
          print('Waiting for template paths to subscribe...');
        }
        // Don't subscribe yet - wait for setActiveTemplatePaths() to be called
        return;
      }

      // Standard SignalK endpoint supports wildcard subscriptions (fallback)
      final subscription = {
        'context': 'vessels.self',
        'subscribe': [
          {
            'path': '*',
            'format': 'delta',
            'policy': 'instant',
          }
        ]
      };

      _channel?.sink.add(jsonEncode(subscription));

      if (kDebugMode) {
        print('Subscribed to all paths with wildcard (*)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error in subscription setup: $e');
      }
    }
  }

  /// Set paths from active templates and subscribe to them
  /// Call this when dashboards/templates change
  Future<void> setActiveTemplatePaths(List<String> paths) async {
    if (!_isConnected || _channel == null) {
      if (kDebugMode) {
        print('Cannot subscribe: not connected');
      }
      return;
    }

    // Check if paths have actually changed
    final pathsSet = Set<String>.from(paths);
    final currentPathsSet = Set<String>.from(_activePaths);

    if (pathsSet.length == currentPathsSet.length &&
        pathsSet.containsAll(currentPathsSet)) {
      if (kDebugMode) {
        print('Template paths unchanged, skipping re-subscription');
      }
      return;
    }

    // Clear old subscriptions and set new ones
    _activePaths.clear();
    _activePaths.addAll(paths);

    if (kDebugMode) {
      print('Setting active template paths: ${_activePaths.length} paths');
    }

    await _updateSubscription();
  }

  /// Handle incoming WebSocket messages
  void _handleMessage(dynamic message) {
    try {
      // Verbose logging disabled - only log errors

      final data = jsonDecode(message);

      // Handle plain string messages (server warnings/info)
      if (data is String) {
        if (kDebugMode) {
          print('Server message: $data');
        }
        return;
      }

      // Must be a Map to process
      if (data is! Map<String, dynamic>) {
        return;
      }

      // if (kDebugMode) {
      //   print('Decoded message keys: ${data.keys.toList()}');
      //   // Log autopilot-related updates
      //   if (data['updates'] != null) {
      //     for (final update in data['updates']) {
      //       if (update['values'] != null) {
      //         for (final value in update['values']) {
      //           final path = value['path'] as String?;
      //           if (path != null && (path.contains('autopilot') || path.contains('steering'))) {
      //             print('🤖 AUTOPILOT UPDATE: $path = ${value['value']}');
      //           }
      //         }
      //       }
      //     }
      //   }
      // }

      // Check if it's an authentication response
      if (data['requestId'] != null && data['state'] != null) {
        if (kDebugMode) {
          print('Auth response: ${data['state']} - ${data['statusCode']}');
        }
        if (data['state'] == 'COMPLETED' && data['statusCode'] == 200) {
          if (kDebugMode) {
            print('WebSocket authentication successful');
          }
        } else {
          if (kDebugMode) {
            print('WebSocket authentication failed: ${data['message']}');
          }
        }
        return;
      }

      // Check if it's a delta update
      if (data['updates'] != null) {
        // DEBUG: Log raw meta data from WebSocket
        if (kDebugMode) {
          for (final rawUpdate in (data['updates'] as List)) {
            if (rawUpdate['meta'] != null) {
              print('🔍 RAW META FROM SERVER: ${jsonEncode(rawUpdate['meta'])}');
            }
          }
        }

        final update = SignalKUpdate.fromJson(data);

        // Process each value update
        for (final updateValue in update.updates) {
          final source = updateValue.source; // Source label (e.g., "can0.115", "pypilot")

          // Process meta entries (from sendMeta=all) - extract displayUnits
          for (final metaEntry in updateValue.metaEntries) {
            if (metaEntry.displayUnits != null) {
              final existingUnits = _displayUnitsCache[metaEntry.path];
              final isNew = existingUnits == null;
              final isChanged = !isNew &&
                  (existingUnits['targetUnit'] != metaEntry.displayUnits!['targetUnit'] ||
                   existingUnits['symbol'] != metaEntry.displayUnits!['symbol']);

              _displayUnitsCache[metaEntry.path] = metaEntry.displayUnits!;

              if (kDebugMode) {
                if (isChanged) {
                  print('📐 Updated displayUnits for ${metaEntry.path}: ${metaEntry.displayUnits}');
                } else if (isNew) {
                  print('📐 Cached displayUnits for ${metaEntry.path}: ${metaEntry.displayUnits}');
                }
              }
            }
          }

          // Process value updates
          for (final value in updateValue.values) {
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
                  converted: numericValue,
                  formatted: formattedString,
                  symbol: symbolString,
                  original: originalValue,
                );
              } else {
                // Regular object value (like position) - NOT units-preference format
                dataPoint = SignalKDataPoint(
                  path: value.path,
                  value: valueMap, // Keep the object as-is
                  timestamp: updateValue.timestamp,
                );
              }
            } else {
              // Standard SignalK format - scalar value
              dataPoint = SignalKDataPoint(
                path: value.path,
                value: value.value,
                timestamp: updateValue.timestamp,
              );
            }

            // Store at default path (for self vessel and backward compatibility)
            _dataCache.internalDataMap[value.path] = dataPoint;

            // ALSO store with full vessel context for multi-vessel support (AIS)
            final contextPath = '${update.context}.${value.path}';
            _dataCache.internalDataMap[contextPath] = dataPoint;

            // ALSO store at source-specific path if source is provided
            if (source != null) {
              final sourceKey = '${value.path}@$source';
              _dataCache.internalDataMap[sourceKey] = dataPoint;
              // if (kDebugMode && (value.path.contains('heading') || value.path.contains('autopilot'))) {
              //   print('📍 ALSO stored ${value.path} from source $source at SOURCE-SPECIFIC key: $sourceKey = ${dataPoint.value}');
              // }
            } // else {
              // if (kDebugMode && (value.path.contains('heading') || value.path.contains('autopilot'))) {
              //   print('⚠️  NO SOURCE provided for ${value.path} - stored ONLY at default path');
              // }
            // }

            // NOTE: Notifications are handled by separate WebSocket connection
          }
        }

        // Invalidate cache when data changes
        _latestDataView = null;
        notifyListeners();
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
  void _handleError(error) {
    _errorMessage = 'WebSocket error: $error';
    _isConnected = false;
    notifyListeners();

    if (kDebugMode) {
      print('WebSocket error: $error');
    }
  }

  /// Handle WebSocket disconnect
  void _handleDisconnect() {
    _isConnected = false;
    // Don't call notifyListeners() for connection state change - use stream instead

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

  /// Attempt to reconnect with exponential backoff
  void _attemptReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      if (kDebugMode) {
        print('Max reconnect attempts reached. Giving up.');
      }
      _connectionState = SignalKConnectionState.disconnected;
      _connectionStateController.add(SignalKConnectionState.disconnected);
      _errorMessage = 'Connection lost. Please reconnect manually.';
      // notifyListeners() only for error message if needed
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
        await connect(
          _serverUrl,
          secure: _useSecureConnection,
          authToken: _authToken,
        );
        if (kDebugMode) {
          print('Reconnected successfully!');
        }
      } catch (e) {
        if (kDebugMode) {
          print('Reconnect attempt #$_reconnectAttempts failed: $e');
        }
        // connect() failure doesn't trigger _handleDisconnect (that's only for established connections)
        // So we need to manually trigger the next attempt
        _attemptReconnect();
      }
    });
  }

  /// Send PUT request to SignalK server
  @override
  Future<void> sendPutRequest(String path, dynamic value) async {
    final protocol = _useSecureConnection ? 'https' : 'http';

    // Convert dot notation to slash notation for URL
    // e.g., 'steering.autopilot.state' -> 'steering/autopilot/state'
    final urlPath = path.replaceAll('.', '/');

    final body = <String, dynamic>{'value': value};

    try {
      final response = await http.put(
        Uri.parse('$protocol://$_serverUrl/signalk/v1/api/vessels/self/$urlPath'),
        headers: _getHeaders(),
        body: jsonEncode(body),
      );

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

    final subscribeMessage = {
      'context': 'vessels.self',
      'subscribe': [
        {'path': 'notifications.crew.rtc.*'},
      ],
    };

    _channel?.sink.add(jsonEncode(subscribeMessage));

    if (kDebugMode) {
      print('Subscribed to notifications.crew.rtc.* for RTC signaling');
    }
  }

  /// Send RTC signaling data via SignalK notification (broadcasts to all clients)
  void sendRtcSignaling(String signalingPath, Map<String, dynamic> data) {
    if (_channel == null) return;

    // Send as a notification - notifications are broadcast to all connected clients
    final notification = {
      'context': 'vessels.self',
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

    if (kDebugMode) {
      print('Sent RTC notification: notifications.crew.rtc.$signalingPath');
    }
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
      final response = await http.get(
        Uri.parse(url),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 10));

      if (kDebugMode) {
        print('getResources($resourceType): status=${response.statusCode}, bodyLength=${response.body.length}');
        if (response.body.length < 500) {
          print('getResources($resourceType): body=${response.body}');
        }
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          return data;
        }
      } else if (response.statusCode == 404) {
        // Resource type doesn't exist yet, return empty map
        if (kDebugMode) {
          print('getResources($resourceType): 404 - resource type not found');
        }
        return {};
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error getting resources ($resourceType): $e');
      }
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
    } catch (e) {
      if (kDebugMode) {
        print('Error getting resource ($resourceType/$id): $e');
      }
    }
    return null;
  }

  /// Create or update a resource
  /// Returns true if successful
  Future<bool> putResource(String resourceType, String id, Map<String, dynamic> data) async {
    final protocol = _useSecureConnection ? 'https' : 'http';
    final url = '$protocol://$_serverUrl/signalk/v2/api/resources/$resourceType/$id';

    if (kDebugMode) {
      print('putResource: PUT $url');
    }

    try {
      final response = await http.put(
        Uri.parse(url),
        headers: _getHeaders(),
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 10));

      if (kDebugMode) {
        print('putResource($resourceType/$id): status=${response.statusCode}');
        if (response.statusCode != 200 && response.statusCode != 201) {
          print('putResource($resourceType/$id): body=${response.body}');
        }
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        if (kDebugMode) {
          print('PUT resource failed ($resourceType/$id): ${response.statusCode} - ${response.body}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error putting resource ($resourceType/$id): $e');
      }
    }
    return false;
  }

  /// Delete a resource
  /// Returns true if successful
  Future<bool> deleteResource(String resourceType, String id) async {
    final protocol = _useSecureConnection ? 'https' : 'http';

    try {
      final response = await http.delete(
        Uri.parse('$protocol://$_serverUrl/signalk/v2/api/resources/$resourceType/$id'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting resource ($resourceType/$id): $e');
      }
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
        if (kDebugMode) {
          print('Resource type "$resourceType" already exists');
        }
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
        if (kDebugMode) {
          print('Created custom resource type "$resourceType"');
        }
        return true;
      } else {
        if (kDebugMode) {
          print('Failed to create resource type "$resourceType": ${createResponse.statusCode} - ${createResponse.body}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error ensuring resource type "$resourceType": $e');
      }
      return false;
    }
  }

  /// Make an authenticated POST request to a plugin API endpoint
  /// Returns the response body as a Map, or null on failure
  Future<http.Response> postPluginApi(String pluginPath, {Map<String, dynamic>? body}) async {
    final protocol = _useSecureConnection ? 'https' : 'http';
    final url = '$protocol://$_serverUrl$pluginPath';

    return await http.post(
      Uri.parse(url),
      headers: _getHeaders(),
      body: body != null ? jsonEncode(body) : null,
    ).timeout(const Duration(seconds: 10));
  }

  /// Make an authenticated GET request to a plugin API endpoint
  /// Returns the response body as a Map, or null on failure
  Future<http.Response> getPluginApi(String pluginPath) async {
    final protocol = _useSecureConnection ? 'https' : 'http';
    final url = '$protocol://$_serverUrl$pluginPath';

    return await http.get(
      Uri.parse(url),
      headers: _getHeaders(),
    ).timeout(const Duration(seconds: 10));
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
        Uri.parse('$protocol://$_serverUrl/signalk/v1/api/vessels/self/$urlPath'),
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

  /// Get all AIS vessels with their positions from REST API
  /// Uses standard SignalK endpoint and applies client-side conversions
  Future<Map<String, Map<String, dynamic>>> getAllAISVessels() async {
    return _aisManager.getAllAISVessels();
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

        if (kDebugMode) {
          print('Vessel self ID from /self endpoint: $vesselId');
        }
        return vesselId;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching vessel self ID: $e');
      }
    }

    return null;
  }

  /// Fetch all available paths from SignalK server
  /// Returns a map of paths with their current values and metadata
  Future<Map<String, dynamic>?> getAvailablePaths() async {
    final protocol = _useSecureConnection ? 'https' : 'http';

    try {
      final response = await http.get(
        Uri.parse('$protocol://$_serverUrl/signalk/v1/api/vessels/self'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 30)); // Increased from 10s for busy servers

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (kDebugMode) {
          print('Fetched vessel data tree');
        }

        return data;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching available paths: $e');
      }
    }

    return null;
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

      if (kDebugMode) {
        print('Unit preferences config response: ${configResponse.statusCode}');
      }

      if (configResponse.statusCode == 200) {
        final data = jsonDecode(configResponse.body);
        final activePreset = data['activePreset'] as String?;

        if (activePreset != null && activePreset.isNotEmpty) {
          // Fetch the full preset data
          await _fetchAndCacheUserPreset(connectionId, activePreset);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching unit preferences: $e');
      }
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

      if (kDebugMode) {
        print('Preset fetch response: ${presetResponse.statusCode}');
      }

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

        if (kDebugMode) {
          print('Preset "$presetName" fetched successfully');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching preset "$presetName": $e');
      }
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

      if (kDebugMode) {
        print('Active unit preferences response: ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (kDebugMode) {
          print('Active unit preferences loaded: ${data.keys.length} categories');
        }
        return data;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching active unit preferences: $e');
      }
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

  /// Find category for a path using default-categories patterns
  String? findCategoryForPath(String path) {
    return _conversionManager.findCategoryForPath(path);
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
    if (kDebugMode) {
      print('Display units cache cleared');
    }
  }

  /// Internal helper to convert a value using the formula for this path
  /// Returns converted value, or raw value if no conversion available
  double? _convertValueForPath(String path, double rawValue) {
    return ConversionUtils.convertValue(this, path, rawValue);
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
        Uri.parse('$protocol://$_serverUrl/signalk/v1/api/vessels/self/$apiPath'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 20)); // Increased from 5s for busy servers

      if (kDebugMode) {
        print('Sources API Response: ${response.statusCode}');
        print('Sources API Body: ${response.body}');
      }

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
  Future<void> subscribeToPaths(List<String> paths) async {
    if (!_isConnected || _channel == null) {
      if (kDebugMode) {
        print('Cannot subscribe: not connected');
      }
      return;
    }

    final newPaths = paths.where((p) => !_activePaths.contains(p)).toList();
    if (newPaths.isEmpty) {
      if (kDebugMode) {
        print('All requested paths already subscribed');
      }
      return;
    }

    _activePaths.addAll(newPaths);

    if (kDebugMode) {
      print('Adding ${newPaths.length} new paths to subscription (total: ${_activePaths.length})');
    }

    await _updateSubscription();
  }

  /// Unsubscribe from paths (called when template/dashboard unloads)
  Future<void> unsubscribeFromPaths(List<String> paths) async {
    if (!_isConnected || _channel == null) return;

    final removedPaths = paths.where((p) => _activePaths.contains(p)).toList();
    if (removedPaths.isEmpty) return;

    _activePaths.removeAll(removedPaths);

    if (kDebugMode) {
      print('Removing ${removedPaths.length} paths from subscription (remaining: ${_activePaths.length})');
    }

    // Send unsubscribe message for units-preference plugin
    if (_authToken != null && _vesselContext != null) {
      final unsubscribeMessage = {
        'context': _vesselContext,
        'unsubscribe': removedPaths.map((path) => {'path': path}).toList(),
      };

      _channel?.sink.add(jsonEncode(unsubscribeMessage));
    }
  }

  /// Update subscription with current active paths
  /// ALWAYS uses standard SignalK stream format (client-side conversions)
  Future<void> _updateSubscription() async {
    if (!_isConnected || _channel == null) return;

    final pathsToSubscribe = <String>[..._activePaths];

    if (pathsToSubscribe.isEmpty) return;

    // Standard SignalK subscription format with sendMeta per path
    final subscription = {
      'context': 'vessels.self',
      'subscribe': pathsToSubscribe.map((path) => {
        'path': path,
        'format': 'delta',
        'policy': 'instant',
        'sendMeta': 'all',
      }).toList(),
    };

    _channel?.sink.add(jsonEncode(subscription));

  }

  /// Subscribe to autopilot paths (uses standard SignalK stream)
  Future<void> subscribeToAutopilotPaths(List<String> paths) async {
    if (!_isConnected) {
      if (kDebugMode) {
        print('Cannot subscribe to autopilot paths: not connected');
      }
      return;
    }

    final newPaths = paths.where((p) => !_autopilotPaths.contains(p)).toList();
    if (newPaths.isEmpty) {
      if (kDebugMode) {
        print('All autopilot paths already subscribed');
      }
      return;
    }

    _autopilotPaths.addAll(newPaths);

    if (kDebugMode) {
      print('Adding ${newPaths.length} autopilot paths (total: ${_autopilotPaths.length})');
    }

    // Connect autopilot channel if not already connected
    if (_autopilotChannel == null) {
      await _connectAutopilotChannel();
    } else {
      await _sendAutopilotSubscription();
    }
  }

  /// Send autopilot subscription to standard SignalK stream
  Future<void> _sendAutopilotSubscription() async {
    if (_autopilotChannel == null || _autopilotPaths.isEmpty) return;

    final subscription = {
      'context': 'vessels.self',
      'subscribe': _autopilotPaths.map((path) => {
        'path': path,
        'format': 'delta',
        'policy': 'instant',
        'sendMeta': 'all',
      }).toList(),
    };

    _autopilotChannel?.sink.add(jsonEncode(subscription));

    if (kDebugMode) {
      print('Sent autopilot subscription: ${_autopilotPaths.length} paths to standard stream (instant policy)');
      print('Autopilot paths: ${_autopilotPaths.join(", ")}');
    }
  }

  /// Load initial AIS vessel data and subscribe for updates
  /// Two-phase approach:
  /// 1. Fetch all existing vessels via REST API (once only)
  /// 2. Subscribe for real-time updates only
  Future<void> loadAndSubscribeAISVessels() async {
    await _aisManager.loadAndSubscribeAISVessels();
    notifyListeners();
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

  /// Enable or disable notifications (manages separate WebSocket connection)
  Future<void> setNotificationsEnabled(bool enabled) async {
    await _notificationManager.setNotificationsEnabled(enabled);
    notifyListeners();
  }

  /// Disconnect from server
  Future<void> disconnect() async {
    try {
      // Mark as intentional disconnect to prevent auto-reconnect
      _intentionalDisconnect = true;
      _reconnectTimer?.cancel();
      _aisManager.dispose();
      _cacheCleanupTimer?.cancel();
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
      _activePaths.clear();
      _autopilotPaths.clear();
      _vesselContext = null;
      _ensuredResourceTypes.clear();
      _displayUnitsCache.clear();

      // Disconnect autopilot channel
      await _autopilotSubscription?.cancel();
      _autopilotSubscription = null;
      await _autopilotChannel?.sink.close();
      _autopilotChannel = null;

      // Also disconnect notification channel if it's connected
      await _notificationManager.disconnectNotificationChannel();

      if (kDebugMode) {
        print('Disconnected and cleaned up WebSocket channels');

      }

      _connectionState = SignalKConnectionState.disconnected;
      _connectionStateController.add(SignalKConnectionState.disconnected);
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
    if (source == null) {
      return _latestData[path];
    }
    final sourceKey = '$path@$source';
    final result = _latestData[sourceKey];
    return result ?? _latestData[path];
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
      // Never prune own vessel data or actively subscribed paths
      if (key.startsWith('vessels.self') || activePaths.contains(key)) {
        return false;
      }
      // Never prune environment data (weather, sun/moon, etc.) - updates infrequently
      if (key.startsWith('environment.')) {
        return false;
      }
      // AIS vessel data - prune if older than 10 minutes
      if (key.startsWith('vessels.')) {
        final age = now.difference(dataPoint.timestamp);
        return age.inMinutes > 10;
      }
      // Other data - prune if older than 15 minutes
      final age = now.difference(dataPoint.timestamp);
      return age.inMinutes > 15;
    });

    final afterSize = _latestData.length;
    final removed = beforeSize - afterSize;
    if (removed > 0) {
      if (kDebugMode) {
        print('Cache pruned: removed $removed stale entries, $afterSize remaining');
      }
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
  String? _activePresetName;

  // Dependencies injected via function getters
  final String Function() getServerUrl;
  final bool Function() useSecureConnection;
  final Map<String, String> Function() getHeaders;
  final Future<void> Function(Map<String, dynamic>) saveToCache;
  final Map<String, dynamic>? Function() loadFromCache;

  _ConversionManager({
    required this.getServerUrl,
    required this.useSecureConnection,
    required this.getHeaders,
    required this.saveToCache,
    required this.loadFromCache,
  });

  // Direct access to internal map (legacy)
  Map<String, PathConversionData> get internalDataMap => _conversionsData;

  // New accessors for unitpreferences data
  Map<String, dynamic>? get unitDefinitions => _unitDefinitions;
  Map<String, dynamic>? get defaultCategories => _defaultCategories;
  Map<String, dynamic>? get presetDetails => _presetDetails;
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
        if (kDebugMode) {
          print('📦 Loaded unitpreferences from local cache (preset: $_activePresetName)');
        }
      } else if (_conversionsData.isEmpty) {
        // Legacy format - path-based conversions
        _conversionsData.clear();
        cached.forEach((path, conversionJson) {
          if (conversionJson is Map<String, dynamic> && !path.startsWith('_')) {
            _conversionsData[path] = PathConversionData.fromJson(conversionJson);
          }
        });
        if (kDebugMode) {
          print('📦 Loaded ${_conversionsData.length} legacy conversions from local cache');
        }
      }
    }
  }

  /// Fetch unit preferences from server using Data Browser endpoints
  /// GET /signalk/v1/unitpreferences/definitions
  /// GET /signalk/v1/unitpreferences/default-categories
  /// GET /signalk/v1/unitpreferences/config
  /// GET /signalk/v1/unitpreferences/presets/{name}
  Future<void> fetchConversions() async {
    final protocol = useSecureConnection() ? 'https' : 'http';
    final serverUrl = getServerUrl();
    final headers = getHeaders();

    try {
      // Fetch all three endpoints in parallel
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
      ]);

      final definitionsResponse = results[0];
      final categoriesResponse = results[1];
      final configResponse = results[2];

      // Parse unit definitions
      if (definitionsResponse.statusCode == 200) {
        _unitDefinitions = jsonDecode(definitionsResponse.body) as Map<String, dynamic>;
        if (kDebugMode) {
          print('✅ Loaded ${_unitDefinitions!.length} unit definitions');
        }
      } else {
        if (kDebugMode) {
          print('⚠️ Failed to fetch unit definitions: ${definitionsResponse.statusCode}');
        }
      }

      // Parse default categories (path patterns)
      if (categoriesResponse.statusCode == 200) {
        _defaultCategories = jsonDecode(categoriesResponse.body) as Map<String, dynamic>;
        if (kDebugMode) {
          print('✅ Loaded ${_defaultCategories!.length} default categories');
        }
      } else {
        if (kDebugMode) {
          print('⚠️ Failed to fetch default categories: ${categoriesResponse.statusCode}');
        }
      }

      // Parse config to get active preset name
      if (configResponse.statusCode == 200) {
        final config = jsonDecode(configResponse.body) as Map<String, dynamic>;
        _activePresetName = config['activePreset'] as String?;
        if (kDebugMode) {
          print('✅ Active preset: $_activePresetName');
        }

        // Fetch the active preset details
        if (_activePresetName != null && _activePresetName!.isNotEmpty) {
          try {
            final presetResponse = await http.get(
              Uri.parse('$protocol://$serverUrl/signalk/v1/unitpreferences/presets/$_activePresetName'),
              headers: headers,
            ).timeout(const Duration(seconds: 10));

            if (presetResponse.statusCode == 200) {
              final presetData = jsonDecode(presetResponse.body) as Map<String, dynamic>;
              _presetDetails = presetData['categories'] as Map<String, dynamic>?;
              if (kDebugMode) {
                print('✅ Loaded preset "$_activePresetName" with ${_presetDetails?.length ?? 0} categories');
              }
            } else {
              if (kDebugMode) {
                print('⚠️ Failed to fetch preset $_activePresetName: ${presetResponse.statusCode}');
              }
            }
          } catch (e) {
            if (kDebugMode) {
              print('⚠️ Error fetching preset $_activePresetName: $e');
            }
          }
        }
      } else {
        if (kDebugMode) {
          print('⚠️ Failed to fetch config: ${configResponse.statusCode}');
        }
      }

      // Save to local cache
      await saveToCache({
        '_unitDefinitions': _unitDefinitions,
        '_defaultCategories': _defaultCategories,
        '_presetDetails': _presetDetails,
        '_activePresetName': _activePresetName,
      });
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Error fetching unit preferences: $e');
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

    // Get target unit from preset
    final categoryPrefs = _presetDetails![category];
    if (categoryPrefs is! Map<String, dynamic>) return null;

    final targetUnit = categoryPrefs['targetUnit'] as String?;
    if (targetUnit == null) return null;

    // Get conversion formula from unit definitions
    final siUnitDef = _unitDefinitions![siUnit];
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

  // Recent notifications cache (last 10 seconds)
  final List<SignalKNotification> _recentNotifications = [];

  // Dependencies injected via function getters
  final AuthToken? Function() getAuthToken;
  final String Function() getNotificationEndpoint;

  _NotificationManager({
    required this.getAuthToken,
    required this.getNotificationEndpoint,
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

  /// Enable or disable notifications
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
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error disconnecting notification channel: $e');
      }
    }
  }

  /// Subscribe to notifications on the notification channel
  void subscribeToNotifications() {
    if (_notificationChannel == null) return;

    final subscription = {
      'context': 'vessels.self',
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

      if (value is Map<String, dynamic>) {
        final state = value['state'] as String?;
        final message = value['message'] as String?;
        final method = value['method'] as List?;

        if (state != null && message != null) {
          final lastState = _lastNotificationState[key];
          if (lastState == state) {
            return;
          }

          _lastNotificationState[key] = state;

          final notification = SignalKNotification(
            key: key,
            state: state,
            message: message,
            method: method?.map((e) => e.toString()).toList() ?? [],
            timestamp: timestamp,
          );

          _notificationController.add(notification);
          _recentNotifications.add(notification);
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

  // Dependencies (inject as function getters)
  final String Function() getServerUrl;
  final bool Function() useSecureConnection;
  final Map<String, String> Function() getHeaders;
  final bool Function() isConnected;
  final WebSocketChannel? Function() getChannel;
  final String? Function() getVesselContext;
  final Map<String, SignalKDataPoint> Function() getDataCache;
  final double? Function(String, double) convertValueForPath;

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
    required this.convertValueForPath,
  });

  /// Get live AIS vessel data from WebSocket cache
  /// Returns vessel data populated by vessels.* wildcard subscription
  Map<String, Map<String, dynamic>> getLiveAISVessels() {
    final vessels = <String, Map<String, dynamic>>{};
    final dataCache = getDataCache();

    // Scan data cache for vessel context keys
    final vesselContexts = <String>{};

    for (final key in dataCache.keys) {
      if (key.startsWith('vessels.') && !key.startsWith('vessels.self')) {
        // Extract vessel context from key like "vessels.urn:mrn:imo:mmsi:123456789.navigation.position"
        final parts = key.split('.');
        if (parts.length >= 2) {
          // Find where the path starts - look for known path prefixes
          for (final pathPrefix in ['navigation', 'name', 'mmsi', 'communication']) {
            final prefixIndex = parts.indexOf(pathPrefix);
            if (prefixIndex > 1) {
              final vesselContext = parts.sublist(0, prefixIndex).join('.');
              vesselContexts.add(vesselContext);
              break;
            }
          }
        }
      }
    }

    // For each vessel context, extract position, COG, SOG, and name
    for (final vesselContext in vesselContexts) {
      final vesselId = vesselContext.substring('vessels.'.length);

      // Skip self vessel - use cached ID or fall back to getVesselContext()
      final selfVesselId = _cachedSelfVesselId;
      final selfContext = selfVesselId != null ? 'vessels.$selfVesselId' : getVesselContext();
      if (vesselContext == selfContext || vesselId == selfVesselId || vesselContext.contains('self')) {
        continue;
      }

      // Get position
      final positionData = dataCache['$vesselContext.navigation.position'];
      if (positionData?.value is Map<String, dynamic>) {
        final position = positionData!.value as Map<String, dynamic>;
        final lat = position['latitude'];
        final lon = position['longitude'];

        if (lat is num && lon is num) {
          // Get COG
          final cogData = dataCache['$vesselContext.navigation.courseOverGroundTrue'];
          double? cog;
          if (cogData?.value is num) {
            final rawCog = (cogData!.value as num).toDouble();
            cog = convertValueForPath('navigation.courseOverGroundTrue', rawCog);
          }

          // Get SOG
          final sogData = dataCache['$vesselContext.navigation.speedOverGround'];
          double? sog;
          double? sogRaw;
          if (sogData?.value is num) {
            sogRaw = (sogData!.value as num).toDouble();
            sog = convertValueForPath('navigation.speedOverGround', sogRaw);
          }

          // Get vessel name
          final name = dataCache['$vesselContext.name']?.value as String?;

          vessels[vesselId] = {
            'latitude': lat.toDouble(),
            'longitude': lon.toDouble(),
            'name': name,
            'cog': cog,
            'sog': sog,
            'sogRaw': sogRaw, // Raw SI value (m/s) for CPA calculations
            'timestamp': positionData.timestamp,
            'fromGET': positionData.fromGET,
          };
        }
      }
    }

    return vessels;
  }

  /// Get all AIS vessels with their positions from REST API
  /// Uses standard SignalK endpoint and applies client-side conversions
  Future<Map<String, Map<String, dynamic>>> getAllAISVessels() async {
    final vessels = <String, Map<String, dynamic>>{};
    final protocol = useSecureConnection() ? 'https' : 'http';

    // Use standard SignalK vessels endpoint
    final endpoint = '$protocol://${getServerUrl()}/signalk/v1/api/vessels';

    if (kDebugMode) {
      print('🌐 Fetching AIS vessels from: $endpoint');
    }

    try {
      final response = await http.get(
        Uri.parse(endpoint),
        headers: getHeaders(),
      ).timeout(const Duration(seconds: 5));

      if (kDebugMode) {
        print('🌐 Response status: ${response.statusCode}');
        if (response.statusCode != 200) {
          print('🌐 Response body: ${response.body}');
        }
      }

      if (response.statusCode == 200) {
        // Response has vessels at root level, NOT wrapped in 'vessels' object
        final vesselsData = jsonDecode(response.body) as Map<String, dynamic>;

        if (kDebugMode) {
          print('🌐 Received ${vesselsData.length} vessel entries');
        }

        // Fetch self vessel ID directly from /self endpoint
        String? selfVesselId;
        try {
          final selfResponse = await http.get(
            Uri.parse('$protocol://${getServerUrl()}/signalk/v1/api/self'),
            headers: getHeaders(),
          ).timeout(const Duration(seconds: 5));

          if (selfResponse.statusCode == 200) {
            final selfRef = selfResponse.body.replaceAll('"', '').trim();
            selfVesselId = selfRef.startsWith('vessels.')
                ? selfRef.substring('vessels.'.length)
                : selfRef;
            // Cache for use by getLiveAISVessels()
            _cachedSelfVesselId = selfVesselId;
            if (kDebugMode) {
              print('🌐 Self vessel ID: $selfVesselId');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('🌐 Error fetching self: $e');
          }
        }

        for (final entry in vesselsData.entries) {
          final vesselId = entry.key;

          // Skip self vessel - check both the literal 'self' key and the actual vessel ID
          if (vesselId == 'self' || vesselId == selfVesselId) {
            if (kDebugMode) {
              print('🌐 Skipping self vessel: $vesselId');
            }
            continue;
          }

          final vesselData = entry.value as Map<String, dynamic>?;
          if (vesselData != null) {
            final navigation = vesselData['navigation'] as Map<String, dynamic>?;
            final position = navigation?['position'] as Map<String, dynamic>?;

            if (position != null) {
              final positionValue = position['value'] as Map<String, dynamic>?;
              final lat = positionValue?['latitude'];
              final lon = positionValue?['longitude'];

              if (lat is num && lon is num) {
                String? name;
                final nameData = vesselData['name'];
                if (nameData is String) {
                  name = nameData;
                } else if (nameData is Map<String, dynamic>) {
                  name = nameData['value'] as String?;
                }

                final cogData = navigation?['courseOverGroundTrue'] as Map<String, dynamic>?;
                final sogData = navigation?['speedOverGround'] as Map<String, dynamic>?;

                double? cog;
                double? sog;
                double? sogRaw;

                if (cogData != null) {
                  final rawCog = (cogData['value'] as num?)?.toDouble();
                  if (rawCog != null) {
                    cog = convertValueForPath('navigation.courseOverGroundTrue', rawCog);
                  }
                }

                if (sogData != null) {
                  sogRaw = (sogData['value'] as num?)?.toDouble();
                  if (sogRaw != null) {
                    sog = convertValueForPath('navigation.speedOverGround', sogRaw);
                  }
                }

                vessels[vesselId] = {
                  'latitude': lat.toDouble(),
                  'longitude': lon.toDouble(),
                  'name': name,
                  'cog': cog,
                  'sog': sog,
                  'sogRaw': sogRaw, // Raw SI value (m/s) for CPA calculations
                };
              }
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('🌐 Error fetching AIS vessels: $e');
      }
    }

    if (kDebugMode) {
      print('🌐 Returning ${vessels.length} vessels with position data');
    }

    return vessels;
  }

  /// Load AIS vessels and subscribe for updates
  Future<void> loadAndSubscribeAISVessels() async {
    if (!_aisInitialLoadDone) {
      _aisInitialLoadDone = true;
      final vessels = await getAllAISVessels();
      final dataCache = getDataCache();
      for (final entry in vessels.entries) {
        final vesselId = entry.key;
        final vesselData = entry.value;
        final vesselContext = 'vessels.$vesselId';

        if (vesselData['latitude'] != null && vesselData['longitude'] != null) {
          dataCache['$vesselContext.navigation.position'] = SignalKDataPoint(
            path: 'navigation.position',
            value: {
              'latitude': vesselData['latitude'],
              'longitude': vesselData['longitude'],
            },
            timestamp: DateTime.now(),
            fromGET: true,
          );
        }

        // Store COG
        if (vesselData['cog'] != null) {
          dataCache['$vesselContext.navigation.courseOverGroundTrue'] = SignalKDataPoint(
            path: 'navigation.courseOverGroundTrue',
            value: vesselData['cog'],
            timestamp: DateTime.now(),
            converted: vesselData['cog'],
          );
        }

        // Store SOG
        if (vesselData['sog'] != null) {
          dataCache['$vesselContext.navigation.speedOverGround'] = SignalKDataPoint(
            path: 'navigation.speedOverGround',
            value: vesselData['sog'],
            timestamp: DateTime.now(),
            converted: vesselData['sog'],
          );
        }

        // Store name
        if (vesselData['name'] != null) {
          dataCache['$vesselContext.name'] = SignalKDataPoint(
            path: 'name',
            value: vesselData['name'],
            timestamp: DateTime.now(),
          );
        }
      }

      await Future.delayed(const Duration(seconds: 10));
      startAISRefreshTimer();
    }

    subscribeToAllAISVessels();
  }

  /// Start periodic AIS refresh timer
  void startAISRefreshTimer() {
    _aisRefreshTimer?.cancel();
    _aisRefreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      if (!isConnected()) {
        timer.cancel();
        return;
      }

      if (kDebugMode) {
        print('🔄 Running periodic AIS GET refresh...');
      }

      final vessels = await getAllAISVessels();
      final dataCache = getDataCache();

      for (final entry in vessels.entries) {
        final vesselId = entry.key;
        final vesselData = entry.value;
        final vesselContext = 'vessels.$vesselId';

        if (dataCache['$vesselContext.navigation.position'] != null) {
          if (vesselData['name'] != null) {
            dataCache['$vesselContext.name'] = SignalKDataPoint(
              path: 'name',
              value: vesselData['name'],
              timestamp: DateTime.now(),
              fromGET: true,
            );
          }
        }
      }
    });
  }

  /// Subscribe to all AIS vessels using wildcard subscription
  void subscribeToAllAISVessels() {
    final channel = getChannel();
    if (channel == null) return;

    final aisSubscription = {
      'context': 'vessels.*',
      'subscribe': [
        {'path': 'navigation.position', 'format': 'delta', 'policy': 'instant'},
        {'path': 'navigation.courseOverGroundTrue', 'format': 'delta', 'policy': 'instant'},
        {'path': 'navigation.speedOverGround', 'format': 'delta', 'policy': 'instant'},
        {'path': 'name', 'period': 60000, 'format': 'delta', 'policy': 'ideal'},
      ],
    };

    channel.sink.add(jsonEncode(aisSubscription));
  }

  void dispose() {
    _aisRefreshTimer?.cancel();
    _aisRefreshTimer = null;
    _aisInitialLoadDone = false;
  }
}
