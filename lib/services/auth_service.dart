import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
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

  /// Get saved token for a server
  AuthToken? getSavedToken(String serverUrl) {
    return _storage.getAuthToken(serverUrl);
  }

  /// Delete saved token for a server
  Future<void> deleteSavedToken(String serverUrl) async {
    await _storage.deleteAuthToken(serverUrl);
  }

  /// Save an approved token
  Future<void> _saveApprovedToken(String serverUrl, AccessRequest request) async {
    if (request.token == null) return;

    final authToken = AuthToken(
      token: request.token!,
      clientId: request.clientId,
      expiresAt: request.expiresAt,
      serverUrl: serverUrl,
    );

    await _storage.saveAuthToken(authToken);

    if (kDebugMode) {
      print('Token saved for $serverUrl');
    }
  }

  /// Reset current request
  void resetCurrentRequest() {
    _currentRequest = null;
    stopPolling();
    notifyListeners();
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
