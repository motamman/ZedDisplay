import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:path_provider/path_provider.dart';

/// Service that runs a local HTTP server to serve shared files
class FileServerService extends ChangeNotifier {
  HttpServer? _server;
  int _port = 8765;
  String? _localIp;

  // Track files being served: fileId -> filePath
  final Map<String, String> _servedFiles = {};

  bool get isRunning => _server != null;
  int get port => _port;
  String? get localIp => _localIp;

  /// Get the base URL for the file server
  String? get baseUrl {
    if (_localIp == null || !isRunning) return null;
    return 'http://$_localIp:$_port';
  }

  /// Initialize and start the file server
  Future<bool> start() async {
    if (_server != null) return true;

    try {
      // Get local IP address
      _localIp = await _getLocalIpAddress();
      if (_localIp == null) {
        if (kDebugMode) {
          print('FileServer: Could not determine local IP');
        }
        return false;
      }

      final router = Router();

      // Serve files by ID
      router.get('/files/<fileId>', _handleFileRequest);

      // Health check endpoint
      router.get('/health', (Request request) {
        return Response.ok('OK');
      });

      final handler = const Pipeline()
          .addMiddleware(logRequests())
          .addHandler(router.call);

      // Try to start server, increment port if busy
      for (int attempt = 0; attempt < 10; attempt++) {
        try {
          _server = await shelf_io.serve(
            handler,
            InternetAddress.anyIPv4,
            _port + attempt,
          );
          _port = _port + attempt;
          break;
        } catch (e) {
          if (kDebugMode) {
            print('FileServer: Port ${_port + attempt} busy, trying next');
          }
        }
      }

      if (_server == null) {
        if (kDebugMode) {
          print('FileServer: Could not find available port');
        }
        return false;
      }

      if (kDebugMode) {
        print('FileServer: Started at http://$_localIp:$_port');
      }

      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('FileServer: Error starting server: $e');
      }
      return false;
    }
  }

  /// Stop the file server
  Future<void> stop() async {
    await _server?.close();
    _server = null;
    _servedFiles.clear();
    notifyListeners();

    if (kDebugMode) {
      print('FileServer: Stopped');
    }
  }

  /// Register a file to be served
  /// Returns the download URL for the file
  String? serveFile(String fileId, String filePath) {
    if (!isRunning || _localIp == null) return null;

    _servedFiles[fileId] = filePath;
    final url = 'http://$_localIp:$_port/files/$fileId';

    if (kDebugMode) {
      print('FileServer: Serving $fileId at $url');
    }

    return url;
  }

  /// Stop serving a file
  void unserveFile(String fileId) {
    _servedFiles.remove(fileId);
  }

  /// Handle file download request
  Future<Response> _handleFileRequest(Request request, String fileId) async {
    final filePath = _servedFiles[fileId];

    if (filePath == null) {
      if (kDebugMode) {
        print('FileServer: File not found: $fileId');
      }
      return Response.notFound('File not found');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      if (kDebugMode) {
        print('FileServer: File does not exist: $filePath');
      }
      _servedFiles.remove(fileId);
      return Response.notFound('File not found');
    }

    try {
      final bytes = await file.readAsBytes();
      final mimeType = _getMimeType(filePath);

      if (kDebugMode) {
        print('FileServer: Serving ${bytes.length} bytes for $fileId');
      }

      return Response.ok(
        bytes,
        headers: {
          'Content-Type': mimeType,
          'Content-Length': '${bytes.length}',
          'Content-Disposition': 'attachment; filename="${filePath.split('/').last}"',
        },
      );
    } catch (e) {
      if (kDebugMode) {
        print('FileServer: Error serving file: $e');
      }
      return Response.internalServerError(body: 'Error reading file');
    }
  }

  /// Get local IP address on the network
  Future<String?> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final interface in interfaces) {
        // Skip loopback and docker interfaces
        if (interface.name.contains('lo') ||
            interface.name.contains('docker') ||
            interface.name.contains('veth')) {
          continue;
        }

        for (final addr in interface.addresses) {
          // Prefer addresses that look like local network IPs
          if (addr.address.startsWith('192.168.') ||
              addr.address.startsWith('10.') ||
              addr.address.startsWith('172.')) {
            if (kDebugMode) {
              print('FileServer: Found local IP ${addr.address} on ${interface.name}');
            }
            return addr.address;
          }
        }
      }

      // Fallback: return first non-loopback address
      for (final interface in interfaces) {
        if (interface.name.contains('lo')) continue;
        if (interface.addresses.isNotEmpty) {
          return interface.addresses.first.address;
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('FileServer: Error getting IP: $e');
      }
      return null;
    }
  }

  /// Get MIME type from file path
  String _getMimeType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      case 'gpx':
        return 'application/gpx+xml';
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
        return 'audio/mp4';
      case 'txt':
        return 'text/plain';
      case 'json':
        return 'application/json';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
