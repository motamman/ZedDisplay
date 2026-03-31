import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'chart_tile_cache_service.dart';

enum DownloadStatus { idle, calculating, downloading, completed, cancelled, error }

/// Bulk tile downloader with progress tracking.
///
/// Downloads all tiles within a bounding box for specified zoom levels.
/// Tiles already in cache are skipped. Supports cancellation.
class ChartDownloadManager extends ChangeNotifier {
  final ChartTileCacheService cacheService;

  ChartDownloadManager({required this.cacheService});

  DownloadStatus _status = DownloadStatus.idle;
  int _totalTiles = 0;
  int _downloadedTiles = 0;
  String? _errorMessage;
  bool _cancelled = false;

  DownloadStatus get status => _status;
  int get totalTiles => _totalTiles;
  int get downloadedTiles => _downloadedTiles;
  double get progress => _totalTiles > 0 ? _downloadedTiles / _totalTiles : 0.0;
  String? get errorMessage => _errorMessage;

  // ---------------------------------------------------------------------------
  // Tile index math (standard Web Mercator XYZ)
  // ---------------------------------------------------------------------------

  static int lonToTileX(double lon, int z) =>
      ((lon + 180.0) / 360.0 * (1 << z)).floor().clamp(0, (1 << z) - 1);

  static int latToTileY(double lat, int z) {
    final latRad = lat * math.pi / 180.0;
    return ((1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) /
            2.0 *
            (1 << z))
        .floor()
        .clamp(0, (1 << z) - 1);
  }

  /// Estimate total tile count for a bounding box across zoom levels.
  int estimateTileCount({
    required double minLon,
    required double minLat,
    required double maxLon,
    required double maxLat,
    required int minZoom,
    required int maxZoom,
  }) {
    int count = 0;
    for (int z = minZoom; z <= maxZoom; z++) {
      final x0 = lonToTileX(minLon, z);
      final x1 = lonToTileX(maxLon, z);
      final y0 = latToTileY(maxLat, z); // note: lat inverted in tile coords
      final y1 = latToTileY(minLat, z);
      count += (x1 - x0 + 1) * (y1 - y0 + 1);
    }
    return count;
  }

  /// Build a flat list of (z, x, y) tile coordinates for a bounding box.
  List<(int, int, int)> _buildTileList({
    required double minLon,
    required double minLat,
    required double maxLon,
    required double maxLat,
    required int minZoom,
    required int maxZoom,
  }) {
    final tiles = <(int, int, int)>[];
    for (int z = minZoom; z <= maxZoom; z++) {
      final x0 = lonToTileX(minLon, z);
      final x1 = lonToTileX(maxLon, z);
      final y0 = latToTileY(maxLat, z);
      final y1 = latToTileY(minLat, z);
      for (int x = x0; x <= x1; x++) {
        for (int y = y0; y <= y1; y++) {
          tiles.add((z, x, y));
        }
      }
    }
    return tiles;
  }

  // ---------------------------------------------------------------------------
  // Download
  // ---------------------------------------------------------------------------

  /// Download all tiles within a bounding box.
  Future<void> downloadArea({
    required double minLon,
    required double minLat,
    required double maxLon,
    required double maxLat,
    required int minZoom,
    required int maxZoom,
    required String baseUrl,
    String? authToken,
    String? regionName,
    bool flush = false,
  }) async {
    _cancelled = false;
    _errorMessage = null;
    _status = DownloadStatus.calculating;
    notifyListeners();

    // Build tile list — skip cached tiles unless flush mode
    final allTiles = _buildTileList(
      minLon: minLon, minLat: minLat,
      maxLon: maxLon, maxLat: maxLat,
      minZoom: minZoom, maxZoom: maxZoom,
    );
    final tiles = flush
        ? allTiles
        : allTiles.where((t) => !cacheService.hasTile(t.$1, t.$2, t.$3)).toList();

    _totalTiles = tiles.length;
    _downloadedTiles = 0;

    if (tiles.isEmpty) {
      _status = DownloadStatus.completed;
      notifyListeners();
      return;
    }

    _status = DownloadStatus.downloading;
    notifyListeners();

    // Download with concurrency limit
    const concurrency = 4;
    int index = 0;
    int errors = 0;

    Future<void> worker() async {
      while (index < tiles.length && !_cancelled) {
        final i = index++;
        final (z, x, y) = tiles[i];
        final url = '$baseUrl/plugins/signalk-charts-provider-simple/01CGD_ENCs/$z/$x/$y';
        try {
          final response = await http.get(
            Uri.parse(url),
            headers: {
              if (authToken != null && authToken.isNotEmpty)
                'Authorization': 'Bearer $authToken',
            },
          );
          if (response.statusCode == 200) {
            await cacheService.putTile(z, x, y, response.bodyBytes);
          } else {
            errors++;
          }
        } catch (_) {
          errors++;
        }
        _downloadedTiles++;
        notifyListeners();
      }
    }

    // Launch concurrent workers
    await Future.wait(List.generate(
      math.min(concurrency, tiles.length),
      (_) => worker(),
    ));

    if (_cancelled) {
      _status = DownloadStatus.cancelled;
    } else if (errors > tiles.length ~/ 2) {
      _status = DownloadStatus.error;
      _errorMessage = '$errors of ${tiles.length} tiles failed';
    } else {
      _status = DownloadStatus.completed;
    }
    notifyListeners();

    // Save region metadata
    if (_status == DownloadStatus.completed || _status == DownloadStatus.cancelled) {
      final region = CacheRegion(
        id: const Uuid().v4(),
        name: regionName ?? 'Downloaded area',
        minLon: minLon,
        minLat: minLat,
        maxLon: maxLon,
        maxLat: maxLat,
        minZoom: minZoom,
        maxZoom: maxZoom,
        tileCount: allTiles.length,
        downloadedAt: DateTime.now(),
      );
      await cacheService.saveRegion(region);
    }
  }

  /// Cancel an in-progress download.
  void cancel() {
    _cancelled = true;
  }

  /// Reset state back to idle.
  void reset() {
    _status = DownloadStatus.idle;
    _totalTiles = 0;
    _downloadedTiles = 0;
    _errorMessage = null;
    _cancelled = false;
    notifyListeners();
  }
}
