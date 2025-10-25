import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:http/http.dart' as http;
import '../models/signalk_data.dart';
import '../models/auth_token.dart';
import 'zones_cache_service.dart';
import 'interfaces/data_service.dart';

/// Service to connect to SignalK server and stream data
class SignalKService extends ChangeNotifier implements DataService {
  // Main data WebSocket (units-preference endpoint)
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  // Autopilot WebSocket (standard endpoint for autopilot data)
  WebSocketChannel? _autopilotChannel;
  StreamSubscription? _autopilotSubscription;

  // Separate notification WebSocket (standard endpoint)
  WebSocketChannel? _notificationChannel;
  StreamSubscription? _notificationSubscription;

  // Connection state
  bool _isConnected = false;
  String? _errorMessage;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  bool _intentionalDisconnect = false;

  // Data storage - keeps latest value for each path
  final Map<String, SignalKDataPoint> _latestData = {};

  // Active subscriptions - only paths currently needed by UI
  final Set<String> _activePaths = {};
  final Set<String> _autopilotPaths = {}; // Separate tracking for autopilot paths
  String? _vesselContext;

  // Notifications
  bool _notificationsEnabled = false;
  final StreamController<SignalKNotification> _notificationController =
      StreamController<SignalKNotification>.broadcast();
  final Map<String, String> _lastNotificationState = {}; // Track last state per notification key

  // Configuration
  String _serverUrl = 'localhost:3000';
  bool _useSecureConnection = false;
  AuthToken? _authToken;

  // Zones cache service
  ZonesCacheService? _zonesCache;

  // Getters
  bool get isConnected => _isConnected;
  String? get errorMessage => _errorMessage;
  Map<String, SignalKDataPoint> get latestData => Map.unmodifiable(_latestData);
  String get serverUrl => _serverUrl;
  bool get useSecureConnection => _useSecureConnection;
  bool get notificationsEnabled => _notificationsEnabled;
  Stream<SignalKNotification> get notificationStream => _notificationController.stream;
  AuthToken? get authToken => _authToken;
  ZonesCacheService? get zonesCache => _zonesCache;

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
        if (kDebugMode) {
          print('Connecting with Authorization header to: $wsUrl');
          print('Token: ${_authToken!.token.substring(0, min(20, _authToken!.token.length))}...');
          print('🔑 FULL TOKEN FOR TESTING: ${_authToken!.token}');
        }

        final headers = <String, String>{
          'Authorization': 'Bearer ${_authToken!.token}',
        };

        try {
          // Use dart:io WebSocket.connect which supports headers
          if (kDebugMode) {
            print('Connecting to WebSocket URL: $wsUrl');
          }

          // Pass the URL string directly - don't parse and re-stringify
          final socket = await WebSocket.connect(wsUrl, headers: headers);
          // Keep connection alive with ping frames every 30 seconds
          socket.pingInterval = const Duration(seconds: 30);
          _channel = IOWebSocketChannel(socket);

          if (kDebugMode) {
            print('WebSocket connection established successfully');
          }
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
      _errorMessage = null;
      _reconnectAttempts = 0; // Reset reconnect attempts on successful connection
      _intentionalDisconnect = false;
      notifyListeners();

      if (kDebugMode) {
        print('Connected to SignalK server: $wsUrl');
      }

      // Note: units-preference plugin does NOT use WebSocket-level authentication
      // The auth token is used only for HTTP requests to the API
      // The WebSocket connection is already authenticated at the HTTP upgrade level

      // Subscribe to paths immediately
      await _sendSubscription();

      // Auto-connect notification channel if notifications are enabled
      if (_notificationsEnabled && _authToken != null) {
        await _connectNotificationChannel();
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

  /// Discover WebSocket endpoint for DATA (always units-preference when authenticated)
  Future<String> _discoverWebSocketEndpoint() async {
    final wsProtocol = _useSecureConnection ? 'wss' : 'ws';

    // Use the server URL as-is - don't add default ports
    // Many servers are behind reverse proxies and don't need explicit ports
    if (kDebugMode) {
      print('Server URL: $_serverUrl (secure: $_useSecureConnection)');
    }

    // Use units-preference endpoint if authenticated (for unit conversions)
    if (_authToken != null) {
      final endpoint = '$wsProtocol://$_serverUrl/plugins/signalk-units-preference/stream';
      if (kDebugMode) {
        print('Using units-preference endpoint (authenticated): $endpoint');
      }
      return endpoint;
    }

    // Fallback to standard SignalK stream
    final endpoint = '$wsProtocol://$_serverUrl/signalk/v1/stream?subscribe=self';
    if (kDebugMode) {
      print('Using standard endpoint (no auth): $endpoint');
    }
    return endpoint;
  }

  /// Get notification WebSocket endpoint (always standard SignalK)
  String _getNotificationEndpoint() {
    final wsProtocol = _useSecureConnection ? 'wss' : 'ws';
    return '$wsProtocol://$_serverUrl/signalk/v1/stream?subscribe=none';
  }

  /// Get autopilot WebSocket endpoint (always standard SignalK stream)
  String _getAutopilotEndpoint() {
    final wsProtocol = _useSecureConnection ? 'wss' : 'ws';
    return '$wsProtocol://$_serverUrl/signalk/v1/stream';
  }

  /// Connect autopilot channel to standard SignalK stream
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

  /// Send WebSocket authentication with token
  void _sendWebSocketAuth() {
    if (_authToken == null) return;

    final authMessage = {
      'requestId': '${DateTime.now().millisecondsSinceEpoch}',
      'token': _authToken!.token,
    };

    _channel?.sink.add(jsonEncode(authMessage));

    if (kDebugMode) {
      print('Sent WebSocket authentication with token');
    }
  }

  /// Initialize subscriptions after connection
  /// Call this with all paths from deployed templates
  Future<void> _sendSubscription() async {
    try {
      // For units-preference plugin, get vessel context
      if (_authToken != null) {
        final vesselId = await getVesselSelfId();
        _vesselContext = vesselId != null ? 'vessels.$vesselId' : 'vessels.self';

        if (kDebugMode) {
          print('Vessel context: $_vesselContext');
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
            'period': 1000,
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
        // Verbose logging disabled
        final update = SignalKUpdate.fromJson(data);

        // Process each value update
        for (final updateValue in update.updates) {
          final source = updateValue.source; // Source label (e.g., "can0.115", "pypilot")

          // if (kDebugMode) {
          //   print('🔍 Processing update from source: $source (${updateValue.values.length} values)');
          // }

          for (final value in updateValue.values) {
            SignalKDataPoint dataPoint;

            // Check if value is from units-preference plugin (has converted format)
            if (value.value is Map<String, dynamic>) {
              final valueMap = value.value as Map<String, dynamic>;

              // Extract values from plugin response
              final convertedValue = valueMap['converted'];
              final originalValue = valueMap['original'];
              final formattedString = valueMap['formatted'] as String?;
              final symbolString = valueMap['symbol'] as String?;

              // For numeric values, use converted number for charts/gauges
              // For objects (like position), keep as-is
              final numericValue = convertedValue is num ? convertedValue.toDouble() : null;

              dataPoint = SignalKDataPoint(
                path: value.path,
                value: numericValue ?? convertedValue ?? originalValue, // Prefer numeric converted, fallback to object/original
                timestamp: updateValue.timestamp,
                converted: numericValue, // Numeric converted value for charts/gauges
                formatted: formattedString, // Display string like "12.6 kn" for labels
                symbol: symbolString, // Unit symbol like "kn"
                original: originalValue, // Raw SI value
              );

              // if (kDebugMode && numericValue != null) {
              //   print('${value.path}: original=$originalValue -> converted=$numericValue (formatted: $formattedString)');
              // }
            } else {
              // Standard SignalK format (raw SI values, no conversion)
              dataPoint = SignalKDataPoint(
                path: value.path,
                value: value.value,
                timestamp: updateValue.timestamp,
              );
            }

            // Store at default path (for self vessel and backward compatibility)
            _latestData[value.path] = dataPoint;

            // ALSO store with full vessel context for multi-vessel support (AIS)
            final contextPath = '${update.context}.${value.path}';
            _latestData[contextPath] = dataPoint;

            // ALSO store at source-specific path if source is provided
            if (source != null) {
              final sourceKey = '${value.path}@$source';
              _latestData[sourceKey] = dataPoint;
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
    notifyListeners();

    if (kDebugMode) {
      print('Disconnected from SignalK server');
    }

    // Attempt reconnection if not intentional disconnect
    if (!_intentionalDisconnect && _serverUrl.isNotEmpty) {
      _attemptReconnect();
    }
  }

  /// Attempt to reconnect with exponential backoff
  void _attemptReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      if (kDebugMode) {
        print('Max reconnect attempts reached. Giving up.');
      }
      _errorMessage = 'Connection lost. Please reconnect manually.';
      notifyListeners();
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(seconds: 2 * _reconnectAttempts); // Exponential backoff: 2s, 4s, 6s, 8s, 10s

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
        // _handleDisconnect will be called again, triggering next attempt
      }
    });
  }

  /// Send PUT request to SignalK server
  Future<void> sendPutRequest(String path, dynamic value) async {
    final protocol = _useSecureConnection ? 'https' : 'http';

    // Convert dot notation to slash notation for URL
    // e.g., 'steering.autopilot.state' -> 'steering/autopilot/state'
    final urlPath = path.replaceAll('.', '/');

    try {
      final response = await http.put(
        Uri.parse('$protocol://$_serverUrl/signalk/v1/api/vessels/self/$urlPath'),
        headers: _getHeaders(),
        body: jsonEncode({'value': value}),
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

  /// Get value for specific path, optionally from a specific source
  SignalKDataPoint? getValue(String path, {String? source}) {
    if (source == null) {
      // No source specified, return default value
      return _latestData[path];
    }

    // Source specified, construct source-specific path
    final sourceKey = '$path@$source';
    final result = _latestData[sourceKey];

    return result ?? _latestData[path]; // Fallback to default if source not found
  }

  /// Check if data is fresh (within TTL threshold)
  /// Returns true if data is fresh, false if stale or missing
  bool isDataFresh(String path, {String? source, int? ttlSeconds}) {
    if (ttlSeconds == null) {
      // No TTL check requested
      return true;
    }

    final dataPoint = getValue(path, source: source);
    if (dataPoint == null) {
      // No data available
      return false;
    }

    final now = DateTime.now();
    final age = now.difference(dataPoint.timestamp);
    return age.inSeconds <= ttlSeconds;
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
    final dataPoint = _latestData[path];
    if (dataPoint?.value is num) {
      return (dataPoint!.value as num).toDouble();
    }
    return null;
  }

  /// Get formatted value string from units-preference plugin
  /// Returns pre-formatted string like "10.0 kn" or falls back to raw value
  String getFormattedValue(String path) {
    final dataPoint = _latestData[path];

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
  double? getConvertedValue(String path) {
    final dataPoint = _latestData[path];
    return dataPoint?.converted ?? (dataPoint?.value is num ? (dataPoint!.value as num).toDouble() : null);
  }

  /// Get unit symbol for a path (e.g., "kn", "°C")
  String? getUnitSymbol(String path) {
    final dataPoint = _latestData[path];
    return dataPoint?.symbol;
  }

  /// Get live AIS vessel data from WebSocket cache
  /// Returns vessel data populated by vessels.* wildcard subscription
  Map<String, Map<String, dynamic>> getLiveAISVessels() {
    final vessels = <String, Map<String, dynamic>>{};

    // Scan _latestData for vessel context keys
    final vesselContexts = <String>{};

    for (final key in _latestData.keys) {
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

      // Skip self vessel
      if (vesselContext == _vesselContext || vesselContext.contains('self')) {
        continue;
      }

      // Get position
      final positionData = _latestData['$vesselContext.navigation.position'];
      if (positionData?.value is Map<String, dynamic>) {
        final position = positionData!.value as Map<String, dynamic>;
        final lat = position['latitude'];
        final lon = position['longitude'];

        if (lat is num && lon is num) {
          // Get COG and SOG (already converted by units-preference)
          final cog = _latestData['$vesselContext.navigation.courseOverGroundTrue']?.converted;
          final sog = _latestData['$vesselContext.navigation.speedOverGround']?.converted;

          // Get vessel name
          final name = _latestData['$vesselContext.name']?.value as String?;

          vessels[vesselId] = {
            'latitude': lat.toDouble(),
            'longitude': lon.toDouble(),
            'name': name,
            'cog': cog,
            'sog': sog,
          };
        }
      }
    }

    return vessels;
  }

  /// Get all AIS vessels with their positions from REST API
  /// Uses units-preference endpoint for converted units
  Future<Map<String, Map<String, dynamic>>> getAllAISVessels() async {
    final vessels = <String, Map<String, dynamic>>{};
    final protocol = _useSecureConnection ? 'https' : 'http';

    // Use units-preference converted endpoint
    final endpoint = '$protocol://$_serverUrl/signalk/v1/vessels';

    if (kDebugMode) {
      print('🌐 Fetching AIS vessels from: $endpoint');
    }

    try {
      final response = await http.get(
        Uri.parse(endpoint),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 5));

      if (kDebugMode) {
        print('🌐 Response status: ${response.statusCode}');
        if (response.statusCode != 200) {
          print('🌐 Response body: ${response.body}');
        }
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final vesselsData = data['vessels'] as Map<String, dynamic>?;

        if (kDebugMode) {
          print('🌐 Received ${vesselsData?.length ?? 0} vessel entries');
        }

        if (vesselsData == null) {
          return vessels;
        }

        for (final entry in vesselsData.entries) {
          final vesselId = entry.key;

          final vesselData = entry.value as Map<String, dynamic>?;
          if (vesselData != null) {
            // Get position (already in lat/lon format, no .value wrapper)
            final navigation = vesselData['navigation'] as Map<String, dynamic>?;
            final position = navigation?['position'] as Map<String, dynamic>?;

            if (position != null) {
              final lat = position['latitude'];
              final lon = position['longitude'];

              if (lat is num && lon is num) {
                // Get additional data
                final name = vesselData['name'] as String?;

                // Extract COG and SOG (already converted by units-preference)
                final cogData = navigation?['courseOverGroundTrue'];
                final sogData = navigation?['speedOverGround'];

                // Get converted values (units-preference format same as WebSocket)
                double? cog;
                double? sog;

                if (cogData is Map<String, dynamic>) {
                  cog = (cogData['converted'] as num?)?.toDouble();
                } else if (cogData is num) {
                  cog = cogData.toDouble();
                }

                if (sogData is Map<String, dynamic>) {
                  sog = (sogData['converted'] as num?)?.toDouble();
                } else if (sogData is num) {
                  sog = sogData.toDouble();
                }

                vessels[vesselId] = {
                  'latitude': lat.toDouble(),
                  'longitude': lon.toDouble(),
                  'name': name,
                  'cog': cog,
                  'sog': sog,
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

  /// Fetch vessel self ID from SignalK server
  Future<String?> getVesselSelfId() async {
    final protocol = _useSecureConnection ? 'https' : 'http';

    try {
      final response = await http.get(
        Uri.parse('$protocol://$_serverUrl/signalk/v1/api/vessels'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // Get the first vessel key (usually the self vessel)
        if (data.isNotEmpty) {
          final vesselId = data.keys.first;
          if (kDebugMode) {
            print('Vessel self ID: $vesselId');
          }
          return vesselId;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching vessel ID: $e');
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

  /// Extract all paths from vessel data tree recursively
  /// Returns a list of path strings (e.g., 'navigation.speedOverGround')
  List<String> extractPathsFromTree(Map<String, dynamic> tree, [String prefix = '']) {
    final paths = <String>[];

    tree.forEach((key, value) {
      // Skip metadata keys
      if (key.startsWith('_') || key == '\$source' || key == 'timestamp') {
        return;
      }

      final currentPath = prefix.isEmpty ? key : '$prefix.$key';

      if (value is Map<String, dynamic>) {
        // Check if this is a leaf node with a value
        if (value.containsKey('value')) {
          paths.add(currentPath);
        } else {
          // Recursively process nested objects
          paths.addAll(extractPathsFromTree(value, currentPath));
        }
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
  Future<void> _updateSubscription() async {
    if (!_isConnected || _channel == null) return;

    final pathsToSubscribe = <String>[..._activePaths];

    if (pathsToSubscribe.isEmpty && !_notificationsEnabled) return;

    if (_authToken != null && _vesselContext != null) {
      // Units-preference plugin: subscribe to specific paths (data only)
      if (pathsToSubscribe.isNotEmpty) {
        final dataSubscription = {
          'context': _vesselContext,
          'subscribe': pathsToSubscribe.map((path) => {
            'path': path,
            'minPeriod': 500,   // Minimum 500ms between updates
            'format': 'delta',
            'policy': 'instant',  // Send on change, but throttled by minPeriod
          }).toList(),
        };

        _channel?.sink.add(jsonEncode(dataSubscription));

        if (kDebugMode) {
          print('Updated data subscription: ${pathsToSubscribe.length} active paths (instant + minPeriod 500ms)');
        }
      }

      // NOTE: Notifications are handled by separate WebSocket connection
    } else {
      // Standard SignalK: use wildcard (fallback)
      final subscription = {
        'context': 'vessels.self',
        'subscribe': [
          {
            'path': '*',
            'period': 1000,
            'format': 'delta',
            'policy': 'instant',
          }
        ]
      };

      _channel?.sink.add(jsonEncode(subscription));
    }
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
        'policy': 'instant',  // Use 'instant' to only send updates when data changes (no period needed)
      }).toList(),
    };

    _autopilotChannel?.sink.add(jsonEncode(subscription));

    if (kDebugMode) {
      print('Sent autopilot subscription: ${_autopilotPaths.length} paths to standard stream (instant policy)');
    }
  }

  /// Load initial AIS vessel data and subscribe for updates
  /// Two-phase approach:
  /// 1. Fetch all existing vessels via REST API
  /// 2. Subscribe for real-time updates only
  Future<void> loadAndSubscribeAISVessels() async {
    // Phase 1: Get all current vessels from REST API
    final vessels = await getAllAISVessels();

    // Store vessels in cache with full context paths
    for (final entry in vessels.entries) {
      final vesselId = entry.key;
      final vesselData = entry.value;
      final vesselContext = 'vessels.$vesselId';

      // Store position
      if (vesselData['latitude'] != null && vesselData['longitude'] != null) {
        final position = {
          'latitude': vesselData['latitude'],
          'longitude': vesselData['longitude'],
        };
        _latestData['$vesselContext.navigation.position'] = SignalKDataPoint(
          path: 'navigation.position',
          value: position,
          timestamp: DateTime.now(),
        );
      }

      // Store COG
      if (vesselData['cog'] != null) {
        _latestData['$vesselContext.navigation.courseOverGroundTrue'] = SignalKDataPoint(
          path: 'navigation.courseOverGroundTrue',
          value: vesselData['cog'],
          timestamp: DateTime.now(),
          converted: vesselData['cog'], // Already in user units from REST
        );
      }

      // Store SOG
      if (vesselData['sog'] != null) {
        _latestData['$vesselContext.navigation.speedOverGround'] = SignalKDataPoint(
          path: 'navigation.speedOverGround',
          value: vesselData['sog'],
          timestamp: DateTime.now(),
          converted: vesselData['sog'], // Already in user units from REST
        );
      }

      // Store name
      if (vesselData['name'] != null) {
        _latestData['$vesselContext.name'] = SignalKDataPoint(
          path: 'name',
          value: vesselData['name'],
          timestamp: DateTime.now(),
        );
      }
    }

    // Notify listeners that initial data is loaded
    notifyListeners();

    // Phase 2: Subscribe for real-time updates only
    subscribeToAllAISVessels();
  }

  /// Subscribe to all AIS vessels using wildcard subscription
  /// Requires units-preference plugin with wildcard support
  void subscribeToAllAISVessels() {
    if (_channel == null) return;

    // Subscribe to all vessels with wildcard context (vessels.*)
    final aisSubscription = {
      'context': 'vessels.*',
      'subscribe': [
        {'path': 'navigation.position', 'period': 2000, 'format': 'delta', 'policy': 'instant', 'minPeriod': 500},
        {'path': 'navigation.courseOverGroundTrue', 'period': 2000, 'format': 'delta', 'policy': 'instant', 'minPeriod': 500},
        {'path': 'navigation.speedOverGround', 'period': 2000, 'format': 'delta', 'policy': 'instant', 'minPeriod': 500},
        {'path': 'name', 'period': 60000, 'format': 'delta', 'policy': 'ideal'},
      ],
    };

    _channel?.sink.add(jsonEncode(aisSubscription));
  }

  /// Enable or disable notifications (manages separate WebSocket connection)
  Future<void> setNotificationsEnabled(bool enabled) async {
    if (_notificationsEnabled == enabled) {
      return;
    }

    _notificationsEnabled = enabled;

    if (enabled) {
      // Connect notification WebSocket
      await _connectNotificationChannel();
    } else {
      // Disconnect notification WebSocket
      await _disconnectNotificationChannel();
    }

    notifyListeners();
  }

  /// Connect to notification WebSocket (separate from data connection)
  Future<void> _connectNotificationChannel() async {
    if (_authToken == null) {
      return;
    }

    try {
      final wsUrl = _getNotificationEndpoint();

      final headers = <String, String>{
        'Authorization': 'Bearer ${_authToken!.token}',
      };

      final socket = await WebSocket.connect(wsUrl, headers: headers);
      // Keep connection alive with ping frames every 30 seconds
      socket.pingInterval = const Duration(seconds: 30);
      _notificationChannel = IOWebSocketChannel(socket);

      // Listen to incoming messages on notification channel
      _notificationSubscription = _notificationChannel!.stream.listen(
        _handleNotificationMessage,
        onError: (error) {
          if (kDebugMode) {
            print('❌ Notification WebSocket error: $error');
          }
        },
        onDone: () {
          // Connection closed
        },
      );

      // Subscribe to notifications
      await Future.delayed(const Duration(milliseconds: 100));
      _subscribeToNotifications();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error connecting notification channel: $e');
      }
    }
  }

  /// Disconnect notification WebSocket
  Future<void> _disconnectNotificationChannel() async {
    try {
      await _notificationSubscription?.cancel();
      _notificationSubscription = null;

      await _notificationChannel?.sink.close();
      _notificationChannel = null;

      // Clear notification state tracking
      _lastNotificationState.clear();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error disconnecting notification channel: $e');
      }
    }
  }

  /// Subscribe to notifications on the notification channel
  void _subscribeToNotifications() {
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
  void _handleNotificationMessage(dynamic message) {
    try {
      final data = jsonDecode(message);

      // Skip non-Map messages
      if (data is! Map<String, dynamic>) {
        return;
      }

      // Process delta updates for notifications
      if (data['updates'] != null) {
        final update = SignalKUpdate.fromJson(data);

        for (final updateValue in update.updates) {
          for (final value in updateValue.values) {
            if (value.path.startsWith('notifications.')) {
              _handleNotification(value.path, value.value, updateValue.timestamp);
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
  void _handleNotification(String path, dynamic value, DateTime timestamp) {
    try {
      // Extract notification key from path (e.g., "notifications.mob" -> "mob")
      final key = path.replaceFirst('notifications.', '');

      if (value is Map<String, dynamic>) {
        final state = value['state'] as String?;
        final message = value['message'] as String?;
        final method = value['method'] as List?;

        if (state != null && message != null) {
          // Deduplicate: only emit if state changed for this notification key
          final lastState = _lastNotificationState[key];
          if (lastState == state) {
            return;
          }

          // Update last state
          _lastNotificationState[key] = state;

          final notification = SignalKNotification(
            key: key,
            state: state,
            message: message,
            method: method?.map((e) => e.toString()).toList() ?? [],
            timestamp: timestamp,
          );

          _notificationController.add(notification);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error handling notification: $e');
      }
    }
  }

  /// Disconnect from server
  Future<void> disconnect() async {
    try {
      // Mark as intentional disconnect to prevent auto-reconnect
      _intentionalDisconnect = true;
      _reconnectTimer?.cancel();
      _reconnectAttempts = 0;

      // Disconnect main data channel
      await _subscription?.cancel();
      _subscription = null;

      await _channel?.sink.close();
      _channel = null;

      _isConnected = false;
      _latestData.clear();
      _activePaths.clear();
      _autopilotPaths.clear();
      _vesselContext = null;

      // Disconnect autopilot channel
      await _autopilotSubscription?.cancel();
      _autopilotSubscription = null;
      await _autopilotChannel?.sink.close();
      _autopilotChannel = null;

      // Also disconnect notification channel if it's connected
      await _disconnectNotificationChannel();

      if (kDebugMode) {
        print('Disconnected and cleaned up WebSocket channels');

      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error during disconnect: $e');
      }
    }
  }

  @override
  void dispose() {
    disconnect();
    _notificationController.close();
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
