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

  bool get isRunning => _server != null;
  int get port => _port;

  /// Set the upstream SignalK server URL and auth token.
  /// Called when the chart plotter connects.
  void configure({required String upstreamBaseUrl, String? authToken}) {
    _upstreamBaseUrl = upstreamBaseUrl;
    _authToken = authToken;
  }

  /// Start the local tile proxy server.
  Future<bool> start() async {
    if (_server != null) return true;

    try {
      final router = Router();
      router.get('/tiles/<z>/<x>/<y>', _handleTileRequest);
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
  Future<Response> _handleTileRequest(Request request, String zStr, String xStr, String yStr) async {
    final z = int.tryParse(zStr);
    final x = int.tryParse(xStr);
    final y = int.tryParse(yStr);
    if (z == null || x == null || y == null) {
      return Response.notFound('Invalid tile coordinates');
    }

    // 1. Check cache
    final cachedFile = cacheService.getTileFile(z, x, y);
    if (cachedFile != null) {
      final bytes = await cachedFile.readAsBytes();
      return Response.ok(bytes, headers: {
        'Content-Type': 'application/x-protobuf',
        'X-Cache': 'HIT',
      });
    }

    // 2. Fetch upstream
    if (_upstreamBaseUrl == null) {
      return Response.notFound('No upstream configured and tile not cached');
    }

    final url = '$_upstreamBaseUrl/plugins/signalk-charts-provider-simple/01CGD_ENCs/$z/$x/$y';
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
      await cacheService.putTile(z, x, y, response.bodyBytes);

      return Response.ok(response.bodyBytes, headers: {
        'Content-Type': 'application/x-protobuf',
        'X-Cache': 'MISS',
      });
    } catch (e) {
      return Response.internalServerError(body: 'Upstream fetch failed: $e');
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
