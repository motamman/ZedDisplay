import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/historical_data.dart';
import '../models/auth_token.dart';

/// Service to fetch historical data from signalk-parquet History API
class HistoricalDataService {
  final String serverUrl;
  final bool useSecureConnection;
  final AuthToken? authToken;

  HistoricalDataService({
    required this.serverUrl,
    this.useSecureConnection = false,
    this.authToken,
  });

  /// Fetch historical data for specified paths
  ///
  /// Parameters:
  /// - paths: List of SignalK paths to query (max 3 recommended)
  ///   Supports full path expression syntax: path:aggregation:smoothing:param
  ///   Examples:
  ///     - 'navigation.speedOverGround' (defaults to :average)
  ///     - 'navigation.speedOverGround:average:sma:5' (5-point SMA)
  ///     - 'navigation.speedOverGround:average:ema:0.3' (EMA with alpha=0.3)
  /// - duration: Time duration to query backwards (e.g., '1h', '30m', '2d')
  /// - resolution: Time bucket size in milliseconds (null = auto, API optimizes based on duration)
  /// - context: SignalK context (default: 'vessels.self')
  Future<HistoricalDataResponse> fetchHistoricalData({
    required List<String> paths,
    String duration = '1h',
    int? resolution,
    String context = 'vessels.self',
  }) async {
    if (paths.isEmpty) {
      throw ArgumentError('At least one path must be specified');
    }

    if (paths.length > 3) {
      throw ArgumentError('Maximum 3 paths are supported');
    }

    final protocol = useSecureConnection ? 'https' : 'http';

    // Paths can include full expression syntax: path:aggregation:smoothing:param
    final pathsParam = paths.join(',');

    final queryParams = {
      'context': context,
      'start': 'now',
      'duration': duration,
      'paths': pathsParam,
      'convertUnits': 'false', // Get raw SI units for client-side conversion
      'convertTimesToLocal': 'true',
    };

    // Only add resolution if specified (null means let API auto-optimize)
    if (resolution != null) {
      queryParams['resolution'] = resolution.toString();
    }

    final uri = Uri.parse('$protocol://$serverUrl/signalk/v1/history/values')
        .replace(queryParameters: queryParams);

    if (kDebugMode) {
      print('Fetching historical data from: $uri');
    }

    try {
      final headers = <String, String>{};
      if (authToken != null) {
        headers['Authorization'] = 'Bearer ${authToken!.token}';
      }

      final response = await http.get(uri, headers: headers).timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (kDebugMode) {
          print('Historical data received: ${data.keys}');
        }
        return HistoricalDataResponse.fromJson(data);
      } else {
        throw Exception(
          'Failed to fetch historical data: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching historical data: $e');
      }
      rethrow;
    }
  }

  /// Fetch historical data with custom time range (forward querying)
  ///
  /// Parameters:
  /// - paths: List of SignalK paths to query (max 3 recommended)
  /// - from: Start datetime
  /// - to: End datetime
  /// - resolution: Time bucket size in milliseconds (null = auto, API optimizes)
  /// - context: SignalK context (default: 'vessels.self')
  Future<HistoricalDataResponse> fetchHistoricalDataRange({
    required List<String> paths,
    required DateTime from,
    required DateTime to,
    int? resolution,
    String context = 'vessels.self',
  }) async {
    if (paths.isEmpty) {
      throw ArgumentError('At least one path must be specified');
    }

    if (paths.length > 3) {
      throw ArgumentError('Maximum 3 paths are supported');
    }

    final protocol = useSecureConnection ? 'https' : 'http';

    // Build the paths parameter
    final pathsParam = paths.join(',');

    final queryParams = {
      'context': context,
      'from': from.toIso8601String(),
      'to': to.toIso8601String(),
      'paths': pathsParam,
      'convertUnits': 'false', // Get raw SI units for client-side conversion
      'convertTimesToLocal': 'true',
    };

    // Only add resolution if specified (null means let API auto-optimize)
    if (resolution != null) {
      queryParams['resolution'] = resolution.toString();
    }

    final uri = Uri.parse('$protocol://$serverUrl/signalk/v1/history/values')
        .replace(queryParameters: queryParams);

    if (kDebugMode) {
      print('Fetching historical data from: $uri');
    }

    try {
      final headers = <String, String>{};
      if (authToken != null) {
        headers['Authorization'] = 'Bearer ${authToken!.token}';
      }

      final response = await http.get(uri, headers: headers).timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (kDebugMode) {
          print('Historical data received: ${data.keys}');
        }
        return HistoricalDataResponse.fromJson(data);
      } else {
        throw Exception(
          'Failed to fetch historical data: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching historical data: $e');
      }
      rethrow;
    }
  }

  /// Get available paths from the history API
  Future<List<String>> getAvailablePaths() async {
    final protocol = useSecureConnection ? 'https' : 'http';
    final uri = Uri.parse('$protocol://$serverUrl/signalk/v1/history/paths');

    if (kDebugMode) {
      print('Fetching available paths from: $uri');
    }

    try {
      final headers = <String, String>{};
      if (authToken != null) {
        headers['Authorization'] = 'Bearer ${authToken!.token}';
      }

      final response = await http.get(uri, headers: headers).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return data.map((e) => e.toString()).toList();
        }
        return [];
      } else {
        throw Exception(
          'Failed to fetch available paths: ${response.statusCode}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching available paths: $e');
      }
      rethrow;
    }
  }

  /// Get available contexts from the history API
  Future<List<String>> getAvailableContexts() async {
    final protocol = useSecureConnection ? 'https' : 'http';
    final uri = Uri.parse('$protocol://$serverUrl/signalk/v1/history/contexts');

    if (kDebugMode) {
      print('Fetching available contexts from: $uri');
    }

    try {
      final headers = <String, String>{};
      if (authToken != null) {
        headers['Authorization'] = 'Bearer ${authToken!.token}';
      }

      final response = await http.get(uri, headers: headers).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return data.map((e) => e.toString()).toList();
        }
        return [];
      } else {
        throw Exception(
          'Failed to fetch available contexts: ${response.statusCode}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching available contexts: $e');
      }
      rethrow;
    }
  }
}
