/// Centralized zone caching service for ZedDisplay
library;

import 'package:flutter/foundation.dart';
import '../models/zone_data.dart';
import 'zones_service.dart';

/// Service for caching zone definitions to avoid redundant HTTP requests
///
/// Multiple gauge tools on the same dashboard may request zones for the same
/// paths. This service caches zone data to reduce server load and improve
/// performance.
class ZonesCacheService extends ChangeNotifier {
  final Map<String, List<ZoneDefinition>> _cache = {};
  final Map<String, Future<List<ZoneDefinition>?>> _pending = {};
  final ZonesService _zonesService;

  ZonesCacheService({
    required String serverUrl,
    required bool useSecureConnection,
  }) : _zonesService = ZonesService(
          serverUrl: serverUrl,
          useSecureConnection: useSecureConnection,
        );

  /// Gets zones for a given path
  ///
  /// Returns cached zones if available, otherwise fetches from server
  /// and caches the result.
  ///
  /// Returns null if the path has no zones or if the fetch fails.
  Future<List<ZoneDefinition>?> getZones(String path) async {
    // Return cached if available
    if (_cache.containsKey(path)) {
      return _cache[path];
    }

    // Deduplicate: if a request for this path is already in-flight, await it
    if (_pending.containsKey(path)) {
      return _pending[path];
    }

    // Fire the request and track it
    final future = _fetchAndCache(path);
    _pending[path] = future;
    try {
      return await future;
    } finally {
      _pending.remove(path);
    }
  }

  Future<List<ZoneDefinition>?> _fetchAndCache(String path) async {
    try {
      final zones = await _zonesService.fetchZones(path);
      if (zones != null && zones.hasZones) {
        _cache[path] = zones.zones;
        notifyListeners();
      }
      return _cache[path];
    } catch (e) {
      if (kDebugMode) {
        print('Failed to fetch zones for $path: $e');
      }
      return null;
    }
  }

  /// Clears all cached zone data
  void clearCache() {
    _cache.clear();
    notifyListeners();
  }

  /// Clears cached zone data for a specific path
  void clearPath(String path) {
    _cache.remove(path);
    notifyListeners();
  }

  /// Checks if zones are cached for a given path
  bool isCached(String path) {
    return _cache.containsKey(path);
  }

  /// Gets the number of cached paths
  int get cacheSize => _cache.length;
}
