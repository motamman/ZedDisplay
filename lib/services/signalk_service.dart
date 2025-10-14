import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import '../models/signalk_data.dart';

/// Service to connect to SignalK server and stream data
class SignalKService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  // Connection state
  bool _isConnected = false;
  String? _errorMessage;

  // Data storage - keeps latest value for each path
  final Map<String, SignalKDataPoint> _latestData = {};

  // Configuration
  String _serverUrl = 'localhost:3000';
  bool _useSecureConnection = false;
  String? _authToken;
  String? _username;
  String? _password;

  // Getters
  bool get isConnected => _isConnected;
  String? get errorMessage => _errorMessage;
  Map<String, SignalKDataPoint> get latestData => Map.unmodifiable(_latestData);

  /// Login to SignalK server and get JWT token
  Future<void> login(String serverUrl, String username, String password, {bool secure = false}) async {
    _serverUrl = serverUrl;
    _useSecureConnection = secure;

    final protocol = secure ? 'https' : 'http';

    try {
      final response = await http.post(
        Uri.parse('$protocol://$serverUrl/signalk/v1/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 10));

      if (kDebugMode) {
        print('Login request to: $protocol://$serverUrl/signalk/v1/auth/login');
        print('Login response status: ${response.statusCode}');
        print('Login response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _authToken = data['token'];

        if (kDebugMode) {
          print('Login successful, token obtained');
        }
      } else {
        throw Exception('Login failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Login failed: $e');
    }
  }

  /// Connect to SignalK server (optionally with authentication)
  Future<void> connect(String serverUrl, {bool secure = false, String? username, String? password}) async {
    _serverUrl = serverUrl;
    _useSecureConnection = secure;
    _username = username;
    _password = password;

    try {
      // Login first if credentials provided (to get token for HTTP requests)
      if (username != null && password != null && username.isNotEmpty && password.isNotEmpty) {
        await login(serverUrl, username, password, secure: secure);
      }

      // First, discover the WebSocket endpoint
      final wsUrl = await _discoverWebSocketEndpoint();

      // Connect to WebSocket
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

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

      // Send WebSocket login if credentials provided
      if (_username != null && _password != null) {
        _sendWebSocketLogin();
        // Wait a moment for authentication to complete
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Subscribe to all available paths (must be done after connection and auth)
      await _sendSubscription();
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
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  /// Discover WebSocket endpoint from SignalK server
  Future<String> _discoverWebSocketEndpoint() async {
    final wsProtocol = _useSecureConnection ? 'wss' : 'ws';

    // If authentication is not configured, use standard SignalK endpoint
    // The units-preference plugin endpoint requires authentication
    if (_username == null || _password == null) {
      final standardEndpoint = '$wsProtocol://$_serverUrl/signalk/v1/stream?subscribe=self';
      if (kDebugMode) {
        print('Using standard SignalK endpoint (no auth): $standardEndpoint');
      }
      return standardEndpoint;
    }

    // Use signalk-units-preference plugin endpoint for pre-converted values
    final unitsPreferenceEndpoint = '$wsProtocol://$_serverUrl/plugins/signalk-units-preference/stream';

    if (kDebugMode) {
      print('Using units-preference endpoint (with auth): $unitsPreferenceEndpoint');
    }

    return unitsPreferenceEndpoint;
  }

  /// Send WebSocket login message (SignalK authentication protocol)
  void _sendWebSocketLogin() {
    if (_username != null && _password != null) {
      final loginMessage = {
        'requestId': '${DateTime.now().millisecondsSinceEpoch}',
        'login': {
          'username': _username,
          'password': _password,
        },
      };

      _channel?.sink.add(jsonEncode(loginMessage));

      if (kDebugMode) {
        print('Sent WebSocket login message');
      }
    }
  }

  /// Send subscription request to receive all data
  Future<void> _sendSubscription() async {
    try {
      // Standard SignalK endpoint supports wildcard subscriptions
      if (_username == null || _password == null) {
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
        return;
      }

      // The units-preference plugin doesn't support wildcard subscriptions
      // Get all paths from SignalK API, then subscribe to each one
      final tree = await getAvailablePaths();

      if (tree == null) {
        if (kDebugMode) {
          print('No paths available - tree is null');
        }
        return;
      }

      final paths = extractPathsFromTree(tree);

      if (paths.isEmpty) {
        if (kDebugMode) {
          print('No paths extracted from tree');
        }
        return;
      }

      final subscription = {
        'context': 'vessels.self',
        'subscribe': paths.map((path) => {
          'path': path,
          'period': 1000,
          'format': 'delta',
          'policy': 'instant',
        }).toList(),
      };

      _channel?.sink.add(jsonEncode(subscription));

      if (kDebugMode) {
        print('Subscribed to ${paths.length} paths explicitly');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error subscribing to paths: $e');
      }
    }
  }

  /// Handle incoming WebSocket messages
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);

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
        final update = SignalKUpdate.fromJson(data);

        // Process each value update
        for (final updateValue in update.updates) {
          for (final value in updateValue.values) {
            // Check if value is from units-preference plugin (has converted format)
            if (value.value is Map<String, dynamic>) {
              final valueMap = value.value as Map<String, dynamic>;

              _latestData[value.path] = SignalKDataPoint(
                path: value.path,
                value: valueMap['converted'] ?? valueMap['value'],
                timestamp: updateValue.timestamp,
                converted: valueMap['converted'] as double?,
                formatted: valueMap['formatted'] as String?,
                symbol: valueMap['symbol'] as String?,
                original: valueMap['original'],
              );
            } else {
              // Standard SignalK format (fallback)
              _latestData[value.path] = SignalKDataPoint(
                path: value.path,
                value: value.value,
                timestamp: updateValue.timestamp,
              );
            }
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

    try {
      final response = await http.put(
        Uri.parse('$protocol://$_serverUrl/signalk/v1/api/vessels/self/$path'),
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

  /// Get value for specific path
  SignalKDataPoint? getValue(String path) {
    return _latestData[path];
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
      ).timeout(const Duration(seconds: 10));

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
      ).timeout(const Duration(seconds: 5));

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

  /// Disconnect from server
  void disconnect() {
    _subscription?.cancel();
    _channel?.sink.close();
    _isConnected = false;
    _latestData.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
