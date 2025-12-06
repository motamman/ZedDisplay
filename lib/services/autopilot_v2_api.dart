import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/autopilot_v2_models.dart';
import '../models/autopilot_errors.dart';

/// Client for SignalK V2 Autopilot API
///
/// The V2 API uses REST endpoints for autopilot control with:
/// - Instance discovery and selection
/// - Separate engage/disengage operations
/// - Enhanced features (dodge mode, gybe support)
/// - Better error reporting
class AutopilotV2Api {
  final String baseUrl;
  final String? authToken;
  final http.Client _client;

  AutopilotV2Api({
    required this.baseUrl,
    this.authToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  String get _authHeader => authToken != null ? 'Bearer $authToken' : '';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': _authHeader,
      };

  /// Discover available autopilot instances
  ///
  /// Returns list of autopilot instances available on the server.
  /// Throws [AutopilotV2NotAvailableException] if V2 API is not supported.
  Future<List<AutopilotInstance>> discoverInstances() async {
    final url = Uri.parse('$baseUrl/signalk/v2/api/vessels/self/autopilots');

    try {
      final response = await _client.get(url, headers: _headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final instances = <AutopilotInstance>[];

        // Parse instances from response
        if (data['autopilots'] != null) {
          for (var entry in (data['autopilots'] as Map).entries) {
            instances.add(AutopilotInstance.fromJson({
              'id': entry.key,
              ...entry.value as Map<String, dynamic>,
            }));
          }
        }

        return instances;
      } else if (response.statusCode == 404) {
        throw AutopilotV2NotAvailableException();
      } else {
        throw AutopilotException(
          'Failed to discover autopilots: ${response.statusCode}',
          type: AutopilotErrorType.serverError,
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      if (e is AutopilotException) rethrow;
      throw AutopilotException(
        'Network error during discovery: $e',
        type: AutopilotErrorType.networkError,
      );
    }
  }

  /// Get autopilot info and capabilities
  ///
  /// Returns the current state and available options for the specified autopilot.
  Future<AutopilotInfo> getAutopilotInfo(String instanceId) async {
    final url =
        Uri.parse('$baseUrl/signalk/v2/api/vessels/self/autopilots/$instanceId');

    final response = await _client.get(url, headers: _headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return AutopilotInfo.fromJson(data);
    } else {
      throw AutopilotException(
        'Failed to get autopilot info: ${response.statusCode}',
        type: AutopilotErrorType.serverError,
        statusCode: response.statusCode,
      );
    }
  }

  /// Engage autopilot
  Future<void> engage(String instanceId) async {
    final url = Uri.parse(
        '$baseUrl/signalk/v2/api/vessels/self/autopilots/$instanceId/engage');

    await _executeCommand(url, 'POST');
  }

  /// Disengage autopilot
  Future<void> disengage(String instanceId) async {
    final url = Uri.parse(
        '$baseUrl/signalk/v2/api/vessels/self/autopilots/$instanceId/disengage');

    await _executeCommand(url, 'POST');
  }

  /// Set autopilot mode
  Future<void> setMode(String instanceId, String mode) async {
    final url = Uri.parse(
        '$baseUrl/signalk/v2/api/vessels/self/autopilots/$instanceId/mode');

    await _executeCommand(url, 'PUT', body: {'value': mode});
  }

  /// Set absolute target heading (degrees)
  Future<void> setTarget(String instanceId, double heading) async {
    final url = Uri.parse(
        '$baseUrl/signalk/v2/api/vessels/self/autopilots/$instanceId/target');

    await _executeCommand(url, 'PUT', body: {
      'value': heading,
      'units': 'deg',
    });
  }

  /// Adjust target heading by relative amount (degrees)
  Future<void> adjustTarget(String instanceId, int degrees) async {
    final url = Uri.parse(
        '$baseUrl/signalk/v2/api/vessels/self/autopilots/$instanceId/target/adjust');

    await _executeCommand(url, 'PUT', body: {
      'value': degrees,
      'units': 'deg',
    });
  }

  /// Initiate tack maneuver
  Future<void> tack(String instanceId, String direction) async {
    final url = Uri.parse(
        '$baseUrl/signalk/v2/api/vessels/self/autopilots/$instanceId/tack/$direction');

    await _executeCommand(url, 'POST');
  }

  /// Initiate gybe maneuver (V2 only feature)
  Future<void> gybe(String instanceId, String direction) async {
    final url = Uri.parse(
        '$baseUrl/signalk/v2/api/vessels/self/autopilots/$instanceId/gybe/$direction');

    await _executeCommand(url, 'POST');
  }

  /// Activate dodge mode (V2 only feature)
  ///
  /// Dodge mode temporarily adjusts heading to avoid obstacles
  /// while maintaining route awareness.
  Future<void> activateDodge(String instanceId) async {
    final url = Uri.parse(
        '$baseUrl/signalk/v2/api/vessels/self/autopilots/$instanceId/dodge');

    await _executeCommand(url, 'POST');
  }

  /// Deactivate dodge mode
  Future<void> deactivateDodge(String instanceId) async {
    final url = Uri.parse(
        '$baseUrl/signalk/v2/api/vessels/self/autopilots/$instanceId/dodge');

    await _executeCommand(url, 'DELETE');
  }

  /// Execute HTTP command with comprehensive error handling
  Future<void> _executeCommand(
    Uri url,
    String method, {
    Map<String, dynamic>? body,
  }) async {
    try {
      http.Response response;

      switch (method) {
        case 'POST':
          response = await _client.post(
            url,
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        case 'PUT':
          response = await _client.put(
            url,
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        case 'DELETE':
          response = await _client.delete(url, headers: _headers);
          break;
        default:
          throw ArgumentError('Unsupported HTTP method: $method');
      }

      // Handle response status codes
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Success - command accepted
        return;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw AutopilotException(
          'Authentication failed',
          type: AutopilotErrorType.authenticationError,
          statusCode: response.statusCode,
        );
      } else if (response.statusCode == 400) {
        // Parse error message from response
        try {
          final data = jsonDecode(response.body);
          final message = data['message'] ?? 'Invalid command';
          throw AutopilotException(
            message,
            type: AutopilotErrorType.commandRejected,
            statusCode: response.statusCode,
            serverMessage: message,
          );
        } catch (_) {
          throw AutopilotException(
            'Invalid command',
            type: AutopilotErrorType.commandRejected,
            statusCode: response.statusCode,
          );
        }
      } else if (response.statusCode == 404) {
        throw AutopilotException(
          'Autopilot instance not found',
          type: AutopilotErrorType.instanceNotFound,
          statusCode: response.statusCode,
        );
      } else {
        throw AutopilotException(
          'Server error: ${response.statusCode}',
          type: AutopilotErrorType.serverError,
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      if (e is AutopilotException) rethrow;
      throw AutopilotException(
        'Network error: $e',
        type: AutopilotErrorType.networkError,
      );
    }
  }

  void dispose() {
    _client.close();
  }
}

/// Exception thrown when V2 API is not available on the server
class AutopilotV2NotAvailableException implements Exception {
  @override
  String toString() => 'V2 API not available on this SignalK server';
}
