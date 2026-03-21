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

        // Server returns instances at top level: {"raySTNGConv": {...}, ...}
        for (var entry in data.entries) {
          instances.add(AutopilotInstance.fromJson({
            'id': entry.key,
            ...(entry.value as Map<String, dynamic>),
          }));
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

  /// Set autopilot state (standby, auto, wind, route)
  ///
  /// V2 API uses "state" not "mode" — states map to engage/disengage + mode.
  Future<void> setMode(String instanceId, String mode) async {
    final url = Uri.parse(
        '$baseUrl/signalk/v2/api/vessels/self/autopilots/$instanceId/state');

    await _executeCommand(url, 'PUT', body: {'value': mode});
  }

  /// Set absolute target heading (degrees).
  ///
  /// Workaround: signalk-autopilot plugin has a bug where `apData.mode` is
  /// never populated, so the V2 `setTarget` endpoint always throws 500.
  /// We compute the delta from current target and use `adjustTarget` instead.
  /// See devdocs/signalk-autopilot-setTarget-bug.md
  Future<void> setTarget(String instanceId, double headingDeg) async {
    // Get current target from autopilot info
    final info = await getAutopilotInfo(instanceId);
    final currentTargetRad = info.target;

    if (currentTargetRad != null) {
      // Convert current target from radians to degrees
      final currentDeg = currentTargetRad * 180.0 / 3.141592653589793;
      // Compute shortest delta
      double delta = headingDeg - currentDeg;
      // Normalize to -180..+180
      while (delta > 180) delta -= 360;
      while (delta < -180) delta += 360;

      final deltaInt = delta.round();
      if (deltaInt != 0) {
        await adjustTarget(instanceId, deltaInt);
      }
    } else {
      // No current target — fall back to direct API (may 500 due to plugin bug)
      final url = Uri.parse(
          '$baseUrl/signalk/v2/api/vessels/self/autopilots/$instanceId/target');
      final headingRad = headingDeg * 3.141592653589793 / 180.0;
      await _executeCommand(url, 'PUT', body: {'value': headingRad});
    }
  }

  /// Adjust target heading by relative amount (degrees, converted to radians)
  Future<void> adjustTarget(String instanceId, int degrees) async {
    final url = Uri.parse(
        '$baseUrl/signalk/v2/api/vessels/self/autopilots/$instanceId/target/adjust');

    // Plugin does radiansToDegrees(value), so send radians
    final radians = degrees * 3.141592653589793 / 180.0;
    await _executeCommand(url, 'PUT', body: {
      'value': radians,
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
