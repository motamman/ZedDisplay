import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

/// Staleness tiers for cached chart tiles.
enum TileFreshness { fresh, aging, stale, uncached }

/// A saved download region with bounds and metadata.
class CacheRegion {
  final String id;
  final String name;
  final double minLon, minLat, maxLon, maxLat;
  final int minZoom, maxZoom;
  final int tileCount;
  final DateTime downloadedAt;

  CacheRegion({
    required this.id,
    required this.name,
    required this.minLon,
    required this.minLat,
    required this.maxLon,
    required this.maxLat,
    required this.minZoom,
    required this.maxZoom,
    required this.tileCount,
    required this.downloadedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'minLon': minLon,
        'minLat': minLat,
        'maxLon': maxLon,
        'maxLat': maxLat,
        'minZoom': minZoom,
        'maxZoom': maxZoom,
        'tileCount': tileCount,
        'downloadedAt': downloadedAt.millisecondsSinceEpoch,
      };

  factory CacheRegion.fromJson(Map<String, dynamic> json) => CacheRegion(
        id: json['id'] as String,
        name: json['name'] as String,
        minLon: (json['minLon'] as num).toDouble(),
        minLat: (json['minLat'] as num).toDouble(),
        maxLon: (json['maxLon'] as num).toDouble(),
        maxLat: (json['maxLat'] as num).toDouble(),
        minZoom: json['minZoom'] as int,
        maxZoom: json['maxZoom'] as int,
        tileCount: json['tileCount'] as int,
        downloadedAt:
            DateTime.fromMillisecondsSinceEpoch(json['downloadedAt'] as int),
      );
}

/// File-based chart tile cache with Hive metadata for staleness tracking.
///
/// Tiles stored at `{appSupportDir}/chart_cache/{z}/{x}/{y}.mvt`.
/// Metadata (cache timestamps) stored in Hive for fast freshness lookups.
class ChartTileCacheService extends ChangeNotifier {
  late Directory _cacheDir;
  late Box<int> _metaBox; // key: "z/x/y", value: epoch milliseconds
  late Box<String> _regionBox; // key: region ID, value: JSON
  bool _initialized = false;

  bool get isInitialized => _initialized;
  int get cachedTileCount => _metaBox.length;

  /// Initialize cache directory and Hive boxes.
  Future<void> initialize() async {
    if (_initialized) return;

    final appDir = await getApplicationSupportDirectory();
    _cacheDir = Directory('${appDir.path}/chart_cache');
    if (!_cacheDir.existsSync()) {
      _cacheDir.createSync(recursive: true);
    }

    _metaBox = await Hive.openBox<int>('chart_tile_meta');
    _regionBox = await Hive.openBox<String>('chart_tile_regions');
    _initialized = true;

    if (kDebugMode) {
      print('ChartTileCache: initialized, ${_metaBox.length} tiles cached');
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Tile I/O
  // ---------------------------------------------------------------------------

  String _tilePath(int z, int x, int y) =>
      '${_cacheDir.path}/$z/$x/$y.mvt';

  String _tileKey(int z, int x, int y) => '$z/$x/$y';

  /// Check if a tile exists in cache (fast, metadata-only).
  bool hasTile(int z, int x, int y) =>
      _metaBox.containsKey(_tileKey(z, x, y));

  /// Get the cached tile file, or null if not cached.
  File? getTileFile(int z, int x, int y) {
    final file = File(_tilePath(z, x, y));
    return file.existsSync() ? file : null;
  }

  /// Write tile bytes to disk and update metadata.
  Future<File> putTile(int z, int x, int y, Uint8List data) async {
    final file = File(_tilePath(z, x, y));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data, flush: true);
    await _metaBox.put(
        _tileKey(z, x, y), DateTime.now().millisecondsSinceEpoch);
    return file;
  }

  // ---------------------------------------------------------------------------
  // Staleness
  // ---------------------------------------------------------------------------

  static const _freshDays = 15;
  static const _agingDays = 30;

  /// Get the date a tile was cached, or null if not cached.
  DateTime? getTileCachedDate(int z, int x, int y) {
    final epoch = _metaBox.get(_tileKey(z, x, y));
    return epoch != null ? DateTime.fromMillisecondsSinceEpoch(epoch) : null;
  }

  /// Get the freshness tier for a single tile.
  TileFreshness getTileFreshness(int z, int x, int y) {
    final epoch = _metaBox.get(_tileKey(z, x, y));
    if (epoch == null) return TileFreshness.uncached;
    final age = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(epoch))
        .inDays;
    if (age < _freshDays) return TileFreshness.fresh;
    if (age < _agingDays) return TileFreshness.aging;
    return TileFreshness.stale;
  }

  /// Get the worst freshness among cached tiles in the viewport.
  /// Tiles outside chart coverage (never cached) are ignored.
  /// Returns [TileFreshness.uncached] only if zero sampled tiles are cached.
  TileFreshness getViewportFreshness(List<(int z, int x, int y)> tiles) {
    if (tiles.isEmpty) return TileFreshness.uncached;
    var worst = TileFreshness.fresh;
    int cachedCount = 0;
    for (final (z, x, y) in tiles) {
      final f = getTileFreshness(z, x, y);
      if (f == TileFreshness.uncached) continue; // skip — no chart data here
      cachedCount++;
      if (f.index > worst.index) worst = f;
    }
    return cachedCount > 0 ? worst : TileFreshness.uncached;
  }

  // ---------------------------------------------------------------------------
  // Stats
  // ---------------------------------------------------------------------------

  /// Calculate total cache size on disk (bytes).
  Future<int> getCacheSize() async {
    if (!_cacheDir.existsSync()) return 0;
    int total = 0;
    await for (final entity in _cacheDir.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  // ---------------------------------------------------------------------------
  // Cache management
  // ---------------------------------------------------------------------------

  /// Clear the entire tile cache.
  Future<void> clearCache() async {
    if (_cacheDir.existsSync()) {
      await _cacheDir.delete(recursive: true);
      await _cacheDir.create(recursive: true);
    }
    await _metaBox.clear();
    await _regionBox.clear();
    notifyListeners();
    if (kDebugMode) {
      print('ChartTileCache: cache cleared');
    }
  }

  // ---------------------------------------------------------------------------
  // Regions
  // ---------------------------------------------------------------------------

  /// Get all saved download regions.
  List<CacheRegion> get savedRegions {
    return _regionBox.values.map((jsonStr) {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return CacheRegion.fromJson(map);
    }).toList();
  }

  /// Save a download region.
  Future<void> saveRegion(CacheRegion region) async {
    await _regionBox.put(region.id, jsonEncode(region.toJson()));
    notifyListeners();
  }

  /// Delete a download region (does not delete the tiles themselves).
  Future<void> deleteRegion(String regionId) async {
    await _regionBox.delete(regionId);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _metaBox.close();
    _regionBox.close();
    super.dispose();
  }
}
