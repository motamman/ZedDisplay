import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/zone_data.dart';
import '../models/auth_token.dart';

/// Service to fetch zone data from signalk-units-preference API
class ZonesService {
  final String serverUrl;
  final bool useSecureConnection;
  final AuthToken? authToken;
  final Map<String, PathZones> _cache = {};

  ZonesService({
    required this.serverUrl,
    this.useSecureConnection = false,
    this.authToken,
  });

  /// Get HTTP headers with authentication if available (currently unused, kept for future)
  // Map<String, String> _getHeaders() {
  //   final headers = <String, String>{};
  //   if (authToken != null) {
  //     headers['Authorization'] = 'Bearer ${authToken!.token}';
  //   }
  //   return headers;
  // }

  /// Fetch zones for a single path
  ///
  /// Parameters:
  /// - path: SignalK path to query zones for
  /// - useCache: Whether to use cached zones (default: true)
  Future<PathZones?> fetchZones(
    String path, {
    bool useCache = true,
  }) async {
    // Check cache first
    if (useCache && _cache.containsKey(path)) {
      return _cache[path];
    }

    final protocol = useSecureConnection ? 'https' : 'http';
    final uri = Uri.parse(
      '$protocol://$serverUrl/signalk/v1/zones/$path',
    );

    if (kDebugMode) {
      print('Fetching zones for path: $path from $uri');
    }

    try {
      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (kDebugMode) {
          print('Zones received for $path: ${data['zones']?.length ?? 0} zones');
        }

        final pathZones = PathZones.fromJson(data);

        // Cache the result
        _cache[path] = pathZones;

        return pathZones;
      } else if (response.statusCode == 404) {
        // Path not found or no zones defined - not an error
        if (kDebugMode) {
          print('No zones defined for path: $path');
        }
        return null;
      } else {
        throw Exception(
          'Failed to fetch zones: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching zones for $path: $e');
      }
      rethrow;
    }
  }

  /// Fetch zones for multiple paths in bulk
  ///
  /// Parameters:
  /// - paths: List of SignalK paths to query zones for
  /// - useCache: Whether to use cached zones (default: true)
  Future<Map<String, PathZones>> fetchBulkZones(
    List<String> paths, {
    bool useCache = true,
  }) async {
    if (paths.isEmpty) {
      return {};
    }

    // Check cache first
    if (useCache) {
      final cachedResults = <String, PathZones>{};
      final missingPaths = <String>[];

      for (final path in paths) {
        if (_cache.containsKey(path)) {
          cachedResults[path] = _cache[path]!;
        } else {
          missingPaths.add(path);
        }
      }

      // If all paths are cached, return immediately
      if (missingPaths.isEmpty) {
        return cachedResults;
      }

      // Otherwise fetch missing paths
      paths = missingPaths;
    }

    final protocol = useSecureConnection ? 'https' : 'http';
    final uri = Uri.parse(
      '$protocol://$serverUrl/signalk/v1/zones/bulk',
    );

    if (kDebugMode) {
      print('Fetching bulk zones for ${paths.length} paths from $uri');
    }

    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'paths': paths}),
          )
          .timeout(
            const Duration(seconds: 15),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (kDebugMode) {
          print('Bulk zones received: ${data['zones']?.keys.length ?? 0} paths');
        }

        final bulkResponse = BulkZonesResponse.fromJson(data);

        // Cache all results
        _cache.addAll(bulkResponse.zones);

        // Combine with any cached results if using cache
        if (useCache) {
          return {..._cache}..removeWhere((key, _) => !paths.contains(key));
        }

        return bulkResponse.zones;
      } else {
        throw Exception(
          'Failed to fetch bulk zones: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching bulk zones: $e');
      }
      rethrow;
    }
  }

  /// Get all paths that have zones defined
  Future<List<String>> getAvailableZonePaths() async {
    final protocol = useSecureConnection ? 'https' : 'http';
    final uri = Uri.parse(
      '$protocol://$serverUrl/signalk/v1/zones',
    );

    if (kDebugMode) {
      print('Fetching available zone paths from: $uri');
    }

    try {
      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['paths'] is List) {
          return (data['paths'] as List).map((e) => e.toString()).toList();
        }
        return [];
      } else {
        throw Exception(
          'Failed to fetch available zone paths: ${response.statusCode}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching available zone paths: $e');
      }
      rethrow;
    }
  }

  /// Clear the cache
  void clearCache() {
    _cache.clear();
  }

  /// Remove a specific path from cache
  void invalidatePath(String path) {
    _cache.remove(path);
  }

  /// Check if a path is cached
  bool isCached(String path) {
    return _cache.containsKey(path);
  }
}
