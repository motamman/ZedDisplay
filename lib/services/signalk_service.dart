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

  // Getters
  bool get isConnected => _isConnected;
  String? get errorMessage => _errorMessage;
  Map<String, SignalKDataPoint> get latestData => Map.unmodifiable(_latestData);

  /// Connect to SignalK server
  Future<void> connect(String serverUrl, {bool secure = false}) async {
    _serverUrl = serverUrl;
    _useSecureConnection = secure;

    try {
      // First, discover the WebSocket endpoint
      final wsUrl = await _discoverWebSocketEndpoint();

      // Connect to WebSocket
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Subscribe to all updates with wildcard
      _sendSubscription();

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
    } catch (e) {
      _errorMessage = 'Connection failed: $e';
      _isConnected = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Discover WebSocket endpoint from SignalK server
  Future<String> _discoverWebSocketEndpoint() async {
    final protocol = _useSecureConnection ? 'https' : 'http';
    final wsProtocol = _useSecureConnection ? 'wss' : 'ws';

    try {
      final response = await http.get(
        Uri.parse('$protocol://$_serverUrl/signalk'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final endpoints = data['endpoints']?['v1'];

        if (endpoints != null) {
          // Try to find WebSocket endpoint
          if (endpoints['signalk-ws'] != null) {
            return endpoints['signalk-ws'].toString();
          }
          if (endpoints['signalk-http'] != null) {
            // Fallback to converting HTTP to WS
            final httpUrl = endpoints['signalk-http'].toString();
            return httpUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Discovery failed, using default: $e');
      }
    }

    // Default WebSocket path
    return '$wsProtocol://$_serverUrl/signalk/v1/stream';
  }

  /// Send subscription request to receive all data
  void _sendSubscription() {
    final subscription = {
      'context': 'vessels.self',
      'subscribe': [
        {
          'path': '*', // Subscribe to all paths
          'period': 1000, // Update every second
          'format': 'delta',
          'policy': 'instant',
        }
      ]
    };

    _channel?.sink.add(jsonEncode(subscription));
  }

  /// Handle incoming WebSocket messages
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);

      // Check if it's a delta update
      if (data['updates'] != null) {
        final update = SignalKUpdate.fromJson(data);

        // Process each value update
        for (final updateValue in update.updates) {
          for (final value in updateValue.values) {
            _latestData[value.path] = SignalKDataPoint(
              path: value.path,
              value: value.value,
              timestamp: updateValue.timestamp,
            );
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
        headers: {'Content-Type': 'application/json'},
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
