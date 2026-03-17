import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/historical_data.dart';
import '../models/auth_token.dart';

/// Top-level function for compute() — parses JSON + builds model on background isolate
HistoricalDataResponse _parseHistoricalResponse(String body) {
  final data = jsonDecode(body) as Map<String, dynamic>;
  return HistoricalDataResponse.fromJson(data);
}

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
  /// - resolution: Time bucket size in seconds (null = auto, API optimizes based on duration)
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

    // Convert durations the server doesn't understand
    final apiDuration = duration == '1w' ? '7d' : duration;

    final queryParams = {
      'context': context,
      'duration': apiDuration,
      'paths': pathsParam,
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
        // Parse JSON + build model objects off the main thread
        final result = await compute(_parseHistoricalResponse, response.body);
        if (kDebugMode) {
          print('Historical data received: (context, range, values, data)');
        }
        return result;
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
  /// - resolution: Time bucket size in seconds (null = auto, API optimizes)
  /// - context: SignalK context (default: 'vessels.self')
  Future<HistoricalDataResponse> fetchHistoricalDataRange({
    required List<String> paths,
    required DateTime from,
    required DateTime to,
    int? resolution,
    String context = 'vessels.self',
    String? bbox,
    String? radius,
  }) async {
    if (paths.isEmpty) {
      throw ArgumentError('At least one path must be specified');
    }

    final protocol = useSecureConnection ? 'https' : 'http';

    // Build the paths parameter
    final pathsParam = paths.join(',');

    final queryParams = {
      'context': context,
      'from': from.toIso8601String(),
      'to': to.toIso8601String(),
      'paths': pathsParam,
    };

    // Only add resolution if specified (null means let API auto-optimize)
    if (resolution != null) {
      queryParams['resolution'] = resolution.toString();
    }
    if (bbox != null) queryParams['bbox'] = bbox;
    if (radius != null) queryParams['radius'] = radius;

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
        // Parse JSON + build model objects off the main thread
        final result = await compute(_parseHistoricalResponse, response.body);
        if (kDebugMode) {
          print('Historical data received: (context, range, values, data)');
        }
        return result;
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

  /// Fetch historical data with automatic batching for >3 paths
  ///
  /// Splits queries into batches of 3 paths and merges results.
  Future<HistoricalDataResponse> fetchHistoricalDataBatched({
    required List<String> paths,
    required DateTime from,
    required DateTime to,
    int? resolution,
    String context = 'vessels.self',
    String? bbox,
    String? radius,
  }) async {
    if (paths.length <= 3) {
      return fetchHistoricalDataRange(
        paths: paths, from: from, to: to,
        resolution: resolution, context: context,
        bbox: bbox, radius: radius,
      );
    }
    // When spatial filtering, navigation.position must be in every batch
    // so the server can correlate positions for filtering.
    final hasSpatial = bbox != null || radius != null;
    const posPath = 'navigation.position';
    final hasPos = paths.contains(posPath);

    // Remove position from the list to avoid double-counting in batches,
    // then prepend it to each batch below.
    final dataPaths = hasPos && hasSpatial
        ? paths.where((p) => p != posPath).toList()
        : paths;

    // Each batch holds up to 3 paths (or 2 data paths + position)
    final batchSize = hasSpatial && hasPos ? 2 : 3;
    final batches = <List<String>>[];
    for (var i = 0; i < dataPaths.length; i += batchSize) {
      final batch = dataPaths.sublist(i, math.min(i + batchSize, dataPaths.length));
      if (hasSpatial && hasPos) {
        batch.insert(0, posPath);
      }
      batches.add(batch);
    }
    final results = await Future.wait(
      batches.map((batch) => fetchHistoricalDataRange(
        paths: batch, from: from, to: to,
        resolution: resolution, context: context,
        bbox: bbox, radius: radius,
      )),
    );
    var merged = results.first;
    for (var i = 1; i < results.length; i++) {
      merged = HistoricalDataResponse.merge(merged, results[i]);
    }
    return merged;
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

  /// Get available contexts from the history API.
  ///
  /// The server only scans parquet files when time params are provided.
  /// Without them it returns only `vessels.self`.
  Future<List<String>> getAvailableContexts({
    DateTime? from,
    DateTime? to,
  }) async {
    final protocol = useSecureConnection ? 'https' : 'http';
    final params = <String, String>{};
    if (from != null) params['from'] = from.toUtc().toIso8601String();
    if (to != null) params['to'] = to.toUtc().toIso8601String();
    final uri = Uri.parse(
      '$protocol://$serverUrl/signalk/v1/history/contexts',
    ).replace(queryParameters: params.isEmpty ? null : params);

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

  /// Get contexts with spatial filtering — only vessels that had positions
  /// within the given area during the time range.
  Future<List<String>> getSpatialContexts({
    required DateTime from,
    required DateTime to,
    String? bbox,
    String? radius,
  }) async {
    final protocol = useSecureConnection ? 'https' : 'http';
    final params = <String, String>{
      'from': from.toUtc().toIso8601String(),
      'to': to.toUtc().toIso8601String(),
    };
    if (bbox != null) params['bbox'] = bbox;
    if (radius != null) params['radius'] = radius;
    final uri = Uri.parse(
      '$protocol://$serverUrl/api/history/contexts/spatial',
    ).replace(queryParameters: params);

    if (kDebugMode) {
      print('Fetching spatial contexts from: $uri');
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
        if (data is List) {
          return data.map((e) => e.toString()).toList();
        }
        return [];
      } else {
        throw Exception(
          'Failed to fetch spatial contexts: ${response.statusCode}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching spatial contexts: $e');
      }
      rethrow;
    }
  }
}
