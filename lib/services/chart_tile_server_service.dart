import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'chart_tile_cache_service.dart';

/// Localhost HTTP server that proxies chart tile requests through a file cache.
///
/// The WebView points its tile URL to `http://localhost:{port}/tiles/{z}/{x}/{y}`.
/// On each request: serve from cache if available, otherwise fetch upstream,
/// cache, and serve. Modeled on [FileServerService].
class ChartTileServerService extends ChangeNotifier {
  final ChartTileCacheService cacheService;

  ChartTileServerService({required this.cacheService});

  HttpServer? _server;
  int _port = 8770;

  String? _upstreamBaseUrl;
  String? _authToken;
  TileFreshness _refreshThreshold = TileFreshness.stale;

  /// Per-chart upstream tile URL templates, keyed by chartId. The
  /// V3 chart plotter populates this from each chart resource's `url`
  /// field after `getResources('charts')` returns. A template may be
  /// absolute (`http(s)://…`) or server-relative (e.g.
  /// `/plugins/signalk-charts-provider-simple/01CGD_ENCs/{z}/{x}/{y}`).
  /// Substitution is `{z}`/`{x}`/`{y}` per OpenLayers `XYZ` /
  /// `VectorTileSource` convention — same shape Freeboard hands
  /// straight to its OL sources.
  ///
  /// Charts with no registered template fall back to the legacy V1
  /// path (`signalk-charts-provider-simple/{chartId}/...`) so the V1
  /// chart plotter — which pre-dates this registry — keeps working
  /// for its hardcoded `01CGD_ENCs`.
  Map<String, String> _chartUpstreamTemplates = const {};

  bool get isRunning => _server != null;
  int get port => _port;

  /// Set the upstream SignalK server URL and auth token.
  /// Called when the chart plotter connects.
  void configure({
    required String upstreamBaseUrl,
    String? authToken,
    TileFreshness refreshThreshold = TileFreshness.stale,
  }) {
    _upstreamBaseUrl = upstreamBaseUrl;
    _authToken = authToken;
    _refreshThreshold = refreshThreshold;
  }

  /// Replace the per-chart upstream URL template registry. Pass an
  /// empty map to revert to legacy hardcoded-path behaviour (V1 mode).
  /// Called by the V3 tool after each `getResources('charts')` round
  /// trip.
  void setChartUpstreamTemplates(Map<String, String> templates) {
    _chartUpstreamTemplates = Map.unmodifiable(templates);
  }

  /// Build the upstream tile URL for [chartId] at (z, x, y).
  /// - Looks up the per-chart template; if absent, falls back to the
  ///   legacy `signalk-charts-provider-simple` hardcoded path.
  /// - Substitutes `{z}` / `{x}` / `{y}` (OL convention).
  /// - Resolves server-relative templates (no scheme) against
  ///   `_upstreamBaseUrl`.
  String? _upstreamUrl(String chartId, int z, int x, int y) {
    final template = _chartUpstreamTemplates[chartId];
    if (template != null) {
      final substituted = template
          .replaceAll('{z}', '$z')
          .replaceAll('{x}', '$x')
          .replaceAll('{y}', '$y');
      if (substituted.startsWith('http://') ||
          substituted.startsWith('https://')) {
        return substituted;
      }
      final base = _upstreamBaseUrl;
      if (base == null) return null;
      return substituted.startsWith('/')
          ? '$base$substituted'
          : '$base/$substituted';
    }
    // Legacy fallback — only useful when the chart happens to live at
    // the well-known signalk-charts-provider-simple path.
    if (_upstreamBaseUrl == null) return null;
    return '$_upstreamBaseUrl/plugins/signalk-charts-provider-simple/$chartId/$z/$x/$y';
  }

  /// Start the local tile proxy server.
  Future<bool> start() async {
    if (_server != null) return true;

    try {
      final router = Router();
      router.get('/tiles/<chartId>/<z>/<x>/<y>', _handleTileRequest);
      router.get('/health', (Request r) => Response.ok('OK'));

      // CORS middleware — required because WebView HTML has opaque origin
      Response corsMiddleware(Response response) {
        return response.change(headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        });
      }

      Handler handler = const Pipeline()
          .addHandler(router.call);

      // Wrap with CORS
      final originalHandler = handler;
      handler = (Request request) async {
        if (request.method == 'OPTIONS') {
          return corsMiddleware(Response.ok(''));
        }
        final response = await originalHandler(request);
        return corsMiddleware(response);
      };

      // Try ports starting at 8770
      for (int attempt = 0; attempt < 10; attempt++) {
        try {
          _server = await shelf_io.serve(
            handler,
            InternetAddress.loopbackIPv4,
            _port + attempt,
          );
          _port = _port + attempt;
          break;
        } catch (e) {
          if (kDebugMode) {
            print('ChartTileServer: Port ${_port + attempt} busy, trying next');
          }
        }
      }

      if (_server == null) {
        if (kDebugMode) {
          print('ChartTileServer: Could not find available port');
        }
        return false;
      }

      if (kDebugMode) {
        print('ChartTileServer: Started at http://localhost:$_port');
      }

      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('ChartTileServer: Error starting: $e');
      }
      return false;
    }
  }

  /// Stop the tile server.
  Future<void> stop() async {
    await _server?.close();
    _server = null;
    notifyListeners();
    if (kDebugMode) {
      print('ChartTileServer: Stopped');
    }
  }

  /// Handle a tile request: cache-first, then upstream fetch.
  Future<Response> _handleTileRequest(Request request, String chartId, String zStr, String xStr, String yStr) async {
    final z = int.tryParse(zStr);
    final x = int.tryParse(xStr);
    final y = int.tryParse(yStr);
    if (z == null || x == null || y == null) {
      return Response.notFound('Invalid tile coordinates');
    }

    // 1. Check cache
    final cachedFile = cacheService.getTileFile(z, x, y, chartId);
    if (cachedFile != null) {
      final bytes = await cachedFile.readAsBytes();

      // Background refresh if tile has reached the staleness threshold
      final freshness = cacheService.getTileFreshness(z, x, y, chartId);
      if (_upstreamBaseUrl != null &&
          freshness.index >= _refreshThreshold.index &&
          _refreshThreshold != TileFreshness.uncached) {
        _backgroundRefresh(z, x, y, chartId, bytes);
      }

      return Response.ok(bytes, headers: {
        'Content-Type': 'application/x-protobuf',
        'X-Cache': 'HIT',
      });
    }

    // 2. Fetch upstream
    final url = _upstreamUrl(chartId, z, x, y);
    if (url == null) {
      return Response.notFound('No upstream configured and tile not cached');
    }
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          if (_authToken != null && _authToken!.isNotEmpty)
            'Authorization': 'Bearer $_authToken',
        },
      );

      if (response.statusCode != 200) {
        return Response(response.statusCode, body: 'Upstream error');
      }

      // Cache the tile
      await cacheService.putTile(z, x, y, response.bodyBytes, chartId);

      return Response.ok(response.bodyBytes, headers: {
        'Content-Type': 'application/x-protobuf',
        'X-Cache': 'MISS',
      });
    } catch (e) {
      return Response.internalServerError(body: 'Upstream fetch failed: $e');
    }
  }

  /// Re-fetch a tile in the background. If bytes match, just reset timestamp.
  /// If different, write the new tile data.
  void _backgroundRefresh(int z, int x, int y, String chartId, Uint8List cachedBytes) {
    final url = _upstreamUrl(chartId, z, x, y);
    if (url == null) return;
    http.get(
      Uri.parse(url),
      headers: {
        if (_authToken != null && _authToken!.isNotEmpty)
          'Authorization': 'Bearer $_authToken',
      },
    ).then((response) {
      if (response.statusCode == 200) {
        if (_bytesEqual(cachedBytes, response.bodyBytes)) {
          // Same content — just reset timestamp to fresh
          cacheService.refreshTimestamp(z, x, y, chartId);
        } else {
          // Different content — write new tile
          cacheService.putTile(z, x, y, response.bodyBytes, chartId);
        }
      }
    }).catchError((_) {
      // Background refresh failure is silent — cached tile still served
    });
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
