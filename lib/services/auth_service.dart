import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../models/auth_token.dart';
import '../models/access_request.dart';
import 'storage_service.dart';

/// Service for handling SignalK authentication and access requests
class AuthService extends ChangeNotifier {
  final StorageService _storage;

  AccessRequest? _currentRequest;
  Timer? _pollingTimer;

  AuthService(this._storage);

  AccessRequest? get currentRequest => _currentRequest;

  /// Generate a unique client ID for this device
  String generateClientId() {
    return const Uuid().v4();
  }

  /// Generate a device description for access requests
  /// Uses setupName if provided, otherwise falls back to device model
  static Future<String> generateDeviceDescription({String? setupName}) async {
    String identifier = '';

    if (setupName != null && setupName.isNotEmpty) {
      identifier = setupName;
    } else {
      // Get device model as fallback
      try {
        final deviceInfo = DeviceInfoPlugin();
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          identifier = '${androidInfo.manufacturer} ${androidInfo.model}';
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          identifier = iosInfo.model;
        } else if (Platform.isMacOS) {
          final macInfo = await deviceInfo.macOsInfo;
          identifier = macInfo.model;
        } else if (Platform.isWindows) {
          final windowsInfo = await deviceInfo.windowsInfo;
          identifier = windowsInfo.computerName;
        } else if (Platform.isLinux) {
          final linuxInfo = await deviceInfo.linuxInfo;
          identifier = linuxInfo.prettyName;
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error getting device info: $e');
        }
      }
    }

    if (identifier.isNotEmpty) {
      return 'ZedDisplay - $identifier';
    }
    return 'ZedDisplay Marine Dashboard';
  }

  /// Submit an access request to SignalK server
  Future<AccessRequest> requestAccess({
    required String serverUrl,
    required String clientId,
    String? description,
    bool secure = false,
  }) async {
    final protocol = secure ? 'https' : 'http';
    final deviceDescription = description ?? 'ZedDisplay Marine Dashboard';

    try {
      final response = await http.post(
        Uri.parse('$protocol://$serverUrl/signalk/v1/access/requests'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'clientId': clientId,
          'description': deviceDescription,
        }),
      ).timeout(const Duration(seconds: 10));

      if (kDebugMode) {
        print('Access request response: ${response.statusCode}');
        print('Access request body: ${response.body}');
      }

      if (response.statusCode == 202 || response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // Transform the response format
        final transformedData = <String, dynamic>{
          'requestId': data['requestId'] ?? clientId,
          'clientId': clientId,
          'description': deviceDescription,
          'state': data['state'] ?? 'PENDING',
        };

        // Handle nested accessRequest if present
        if (data.containsKey('accessRequest')) {
          final accessRequest = data['accessRequest'] as Map<String, dynamic>;
          final permission = accessRequest['permission'] as String?;
          if (permission == 'APPROVED') {
            transformedData['state'] = 'APPROVED';
            transformedData['token'] = accessRequest['token'];
          } else if (permission == 'DENIED') {
            transformedData['state'] = 'DENIED';
          }
        } else if (data.containsKey('token')) {
          transformedData['token'] = data['token'];
        }

        // Preserve other fields
        if (data.containsKey('statusHref')) {
          transformedData['statusHref'] = data['statusHref'];
        }
        if (data.containsKey('href')) {
          transformedData['statusHref'] = data['href'];
        }
        if (data.containsKey('message')) {
          transformedData['message'] = data['message'];
        }

        // Parse response using generated fromJson
        _currentRequest = AccessRequest.fromJson(transformedData);

        notifyListeners();

        // If approved immediately, save token
        if (_currentRequest!.state == AccessRequestState.approved && _currentRequest!.token != null) {
          await _saveApprovedToken(serverUrl, _currentRequest!);
        }

        return _currentRequest!;
      } else if (response.statusCode == 501) {
        throw Exception('Server does not support access requests');
      } else {
        throw Exception('Access request failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Access request error: $e');
    }
  }

  /// Poll the access request status
  Future<AccessRequest> pollRequestStatus({
    required String serverUrl,
    required String requestId,
    bool secure = false,
  }) async {
    final protocol = secure ? 'https' : 'http';

    // Use the statusHref from the current request if available
    String pollUrl;
    if (_currentRequest?.statusHref != null) {
      // Server provided a specific href to poll
      pollUrl = '$protocol://$serverUrl${_currentRequest!.statusHref}';
    } else {
      // Fallback to standard polling endpoint
      pollUrl = '$protocol://$serverUrl/signalk/v1/requests/$requestId';
    }

    if (kDebugMode) {
      print('Polling URL: $pollUrl');
    }

    try {
      final response = await http.get(
        Uri.parse(pollUrl),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (kDebugMode) {
          print('Poll response data: $data');
        }

        // Transform the response format from SignalK server to our expected format
        final transformedData = <String, dynamic>{
          'requestId': data['requestId'],
          'clientId': _currentRequest?.clientId ?? '',
          'description': _currentRequest?.description ?? 'ZedDisplay Marine Dashboard',
        };

        // Handle the nested accessRequest structure
        if (data.containsKey('accessRequest')) {
          final accessRequest = data['accessRequest'] as Map<String, dynamic>;

          // Extract permission and map to state
          final permission = accessRequest['permission'] as String?;
          if (permission == 'APPROVED') {
            transformedData['state'] = 'APPROVED';
            transformedData['token'] = accessRequest['token'];

            // Extract expiration if present (JWT tokens have exp claim)
            if (accessRequest.containsKey('expiresAt')) {
              transformedData['expiresAt'] = accessRequest['expiresAt'];
            }
          } else if (permission == 'DENIED') {
            transformedData['state'] = 'DENIED';
          } else {
            transformedData['state'] = data['state']; // PENDING or COMPLETED
          }
        } else {
          // Fallback to direct state field
          transformedData['state'] = data['state'];
          transformedData['token'] = data['token'];
          if (data.containsKey('expiresAt')) {
            transformedData['expiresAt'] = data['expiresAt'];
          }
        }

        // Preserve other fields
        if (data.containsKey('statusHref')) {
          transformedData['statusHref'] = data['statusHref'];
        }
        if (data.containsKey('message')) {
          transformedData['message'] = data['message'];
        }

        if (kDebugMode) {
          print('Transformed poll data: $transformedData');
        }

        // Parse response using generated fromJson
        try {
          _currentRequest = AccessRequest.fromJson(transformedData);

          if (kDebugMode) {
            print('Parsed request state: ${_currentRequest!.state}');
            print('Token: ${_currentRequest!.token}');
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing AccessRequest: $e');
          }
          throw Exception('Failed to parse access request: $e');
        }

        notifyListeners();

        // If approved, save token and stop polling
        if (_currentRequest!.state == AccessRequestState.approved) {
          if (kDebugMode) {
            print('Request APPROVED! Token: ${_currentRequest!.token}');
          }

          if (_currentRequest!.token != null) {
            await _saveApprovedToken(serverUrl, _currentRequest!);
            stopPolling();
          } else {
            if (kDebugMode) {
              print('WARNING: Approved but no token received');
            }
          }
        }

        // If denied, stop polling
        if (_currentRequest!.state == AccessRequestState.denied) {
          if (kDebugMode) {
            print('Request DENIED');
          }
          stopPolling();
        }

        return _currentRequest!;
      } else {
        if (kDebugMode) {
          print('Poll failed with status: ${response.statusCode}');
          print('Response body: ${response.body}');
        }
        throw Exception('Poll failed: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Poll error details: $e');
      }
      throw Exception('Poll error: $e');
    }
  }

  /// Start polling for request status (every 5 seconds)
  void startPolling({
    required String serverUrl,
    required String requestId,
    bool secure = false,
  }) {
    stopPolling(); // Clear any existing timer

    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        await pollRequestStatus(
          serverUrl: serverUrl,
          requestId: requestId,
          secure: secure,
        );
      } catch (e) {
        if (kDebugMode) {
          print('Polling error: $e');
        }
      }
    });
  }

  /// Stop polling for request status
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Get saved token for a connection
  AuthToken? getSavedToken(String connectionId) {
    return _storage.getAuthToken(connectionId);
  }

  /// Delete saved token for a connection
  Future<void> deleteSavedToken(String connectionId) async {
    await _storage.deleteAuthToken(connectionId);
  }

  /// Save an approved token for a connection
  Future<void> saveApprovedToken(String serverUrl, AccessRequest request, {required String connectionId}) async {
    if (request.token == null) return;

    final authToken = AuthToken(
      token: request.token!,
      clientId: request.clientId,
      expiresAt: request.expiresAt,
      serverUrl: serverUrl,
      connectionId: connectionId,
    );

    await _storage.saveAuthToken(authToken, connectionId: connectionId);

    if (kDebugMode) {
      print('Token saved for connection $connectionId ($serverUrl)');
    }
  }

  /// Internal method to save token (used during polling)
  String? _pendingConnectionId;

  /// Set the connection ID for the current access request
  void setConnectionIdForRequest(String connectionId) {
    _pendingConnectionId = connectionId;
  }

  /// Save an approved token (internal, uses pending connection ID)
  Future<void> _saveApprovedToken(String serverUrl, AccessRequest request) async {
    if (request.token == null || _pendingConnectionId == null) return;

    final authToken = AuthToken(
      token: request.token!,
      clientId: request.clientId,
      expiresAt: request.expiresAt,
      serverUrl: serverUrl,
      connectionId: _pendingConnectionId,
    );

    await _storage.saveAuthToken(authToken, connectionId: _pendingConnectionId!);

    if (kDebugMode) {
      print('Token saved for connection $_pendingConnectionId ($serverUrl)');
    }
  }

  /// Reset current request
  void resetCurrentRequest() {
    _currentRequest = null;
    stopPolling();
    notifyListeners();
  }

  /// Login with username and password (user authentication)
  /// POST /signalk/v1/auth/login
  /// Body: { "username": "...", "password": "..." }
  /// Response: { "token": "jwt..." }
  Future<AuthToken?> loginUser({
    required String serverUrl,
    required String username,
    required String password,
    bool secure = false,
    String? connectionId,
  }) async {
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
        print('User login response: ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final token = data['token'] as String?;

        if (token == null) {
          throw Exception('No token in response');
        }

        // Parse JWT to extract expiration
        DateTime? expiresAt;
        try {
          final parts = token.split('.');
          if (parts.length == 3) {
            final payload = parts[1];
            // Add padding if needed
            final normalized = base64.normalize(payload);
            final decoded = utf8.decode(base64.decode(normalized));
            final payloadData = jsonDecode(decoded) as Map<String, dynamic>;

            if (payloadData.containsKey('exp')) {
              final exp = payloadData['exp'] as int;
              expiresAt = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing JWT expiration: $e');
          }
        }

        final authToken = AuthToken(
          token: token,
          username: username,
          authType: AuthType.user,
          expiresAt: expiresAt,
          serverUrl: serverUrl,
          connectionId: connectionId,
        );

        // Save token if connectionId is provided
        if (connectionId != null) {
          await _storage.saveAuthToken(authToken, connectionId: connectionId);
          if (kDebugMode) {
            print('User token saved for connection $connectionId');
          }
        }

        return authToken;
      } else if (response.statusCode == 401) {
        throw Exception('Invalid username or password');
      } else {
        throw Exception('Login failed: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('User login error: $e');
      }
      rethrow;
    }
  }

  /// Logout user and optionally clear token
  /// PUT /signalk/v1/auth/logout
  Future<void> logoutUser({
    required String serverUrl,
    required AuthToken token,
    bool secure = false,
    bool clearToken = true,
  }) async {
    final protocol = secure ? 'https' : 'http';

    try {
      await http.put(
        Uri.parse('$protocol://$serverUrl/signalk/v1/auth/logout'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token.token}',
        },
      ).timeout(const Duration(seconds: 10));

      if (kDebugMode) {
        print('User logged out from server');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Logout request error (may be expected if token expired): $e');
      }
    }

    // Clear the user token from storage if requested
    if (clearToken && token.connectionId != null) {
      await _storage.deleteAuthToken(token.connectionId!);
      if (kDebugMode) {
        print('User token cleared for connection ${token.connectionId}');
      }
    }

    notifyListeners();
  }

  /// Check if a token is a user token
  bool isUserToken(AuthToken? token) {
    return token?.authType == AuthType.user;
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
