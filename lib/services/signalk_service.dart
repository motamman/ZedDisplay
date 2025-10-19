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

/// Service to connect to SignalK server and stream data
class SignalKService extends ChangeNotifier {
  // Main data WebSocket (units-preference endpoint)
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  // Separate notification WebSocket (standard endpoint)
  WebSocketChannel? _notificationChannel;
  StreamSubscription? _notificationSubscription;

  // Connection state
  bool _isConnected = false;
  String? _errorMessage;

  // Data storage - keeps latest value for each path
  final Map<String, SignalKDataPoint> _latestData = {};

  // Active subscriptions - only paths currently needed by UI
  final Set<String> _activePaths = {};
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

  // Getters
  bool get isConnected => _isConnected;
  String? get errorMessage => _errorMessage;
  Map<String, SignalKDataPoint> get latestData => Map.unmodifiable(_latestData);
  String get serverUrl => _serverUrl;
  bool get useSecureConnection => _useSecureConnection;
  bool get notificationsEnabled => _notificationsEnabled;
  Stream<SignalKNotification> get notificationStream => _notificationController.stream;

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

            // Store at default path
            _latestData[value.path] = dataPoint;
            // if (kDebugMode && (value.path.contains('heading') || value.path.contains('autopilot'))) {
            //   print('📦 Stored ${value.path} at DEFAULT key: ${value.path} = ${dataPoint.value}');
            // }

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
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing message: $e');
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
            'period': 1000,
            'format': 'delta',
            'policy': 'instant',
          }).toList(),
        };

        _channel?.sink.add(jsonEncode(dataSubscription));

        if (kDebugMode) {
          print('Updated data subscription: ${pathsToSubscribe.length} active paths');
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
      // Disconnect main data channel
      await _subscription?.cancel();
      _subscription = null;

      await _channel?.sink.close();
      _channel = null;

      _isConnected = false;
      _latestData.clear();
      _activePaths.clear();
      _vesselContext = null;

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
