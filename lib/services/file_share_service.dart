import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../models/shared_file.dart';
import 'signalk_service.dart';
import 'storage_service.dart';
import 'crew_service.dart';

/// Service for sharing files between crew members
class FileShareService extends ChangeNotifier {
  final SignalKService _signalKService;
  final StorageService _storageService;
  final CrewService _crewService;

  // Files cache (sorted by timestamp, newest first)
  final List<SharedFile> _files = [];
  List<SharedFile> get files => List.unmodifiable(_files);

  // Resources API configuration
  static const String _fileResourceType = 'notes';
  static const String _fileGroupName = 'zeddisplay-files';

  // Polling timer
  Timer? _pollTimer;
  static const Duration _pollInterval = Duration(seconds: 10);

  // Track if Resources API is available
  bool _resourcesApiAvailable = true;
  bool get isResourcesApiAvailable => _resourcesApiAvailable;

  // Storage key for local file metadata cache
  static const String _filesStorageKey = 'crew_files_cache';

  // File size limit for embedding in SignalK notes (100KB)
  static const int _embeddedFileSizeLimit = 100 * 1024;

  // Track connection state
  bool _wasConnected = false;

  // Downloads directory
  Directory? _downloadsDir;

  FileShareService(this._signalKService, this._storageService, this._crewService);

  /// Initialize the file share service
  Future<void> initialize() async {
    // Get downloads directory
    await _initDownloadsDir();

    // Load cached file metadata from storage
    await _loadCachedFiles();

    // Listen to SignalK connection changes
    _signalKService.addListener(_onSignalKChanged);

    // If already connected, start polling
    if (_signalKService.isConnected) {
      _onConnected();
    }

    if (kDebugMode) {
      print('FileShareService initialized with ${_files.length} cached files');
    }
  }

  Future<void> _initDownloadsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    _downloadsDir = Directory('${appDir.path}/crew_files');
    if (!await _downloadsDir!.exists()) {
      await _downloadsDir!.create(recursive: true);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _signalKService.removeListener(_onSignalKChanged);
    super.dispose();
  }

  /// Load cached file metadata from local storage
  Future<void> _loadCachedFiles() async {
    final cachedJson = _storageService.getSetting(_filesStorageKey);
    if (cachedJson != null) {
      try {
        final List<dynamic> fileList = jsonDecode(cachedJson);
        _files.clear();
        for (final fileJson in fileList) {
          try {
            final file = SharedFile.fromJson(fileJson as Map<String, dynamic>);
            _files.add(file);
          } catch (e) {
            // Skip invalid entries
          }
        }
        _files.sort((a, b) => b.timestamp.compareTo(a.timestamp)); // Newest first
      } catch (e) {
        if (kDebugMode) {
          print('Error loading cached files: $e');
        }
      }
    }
  }

  /// Save file metadata to local storage
  Future<void> _saveCachedFiles() async {
    // Don't store the actual file data in the cache, just metadata
    final fileList = _files.map((f) {
      final json = f.toJson();
      // Remove large data from cache
      json.remove('data');
      return json;
    }).toList();
    await _storageService.saveSetting(_filesStorageKey, jsonEncode(fileList));
  }

  /// Handle SignalK connection changes
  void _onSignalKChanged() {
    final isConnected = _signalKService.isConnected;
    if (isConnected == _wasConnected) return;
    _wasConnected = isConnected;

    if (isConnected) {
      _onConnected();
    } else {
      _onDisconnected();
    }
  }

  void _onConnected() {
    if (kDebugMode) {
      print('FileShareService: Connected');
    }
    _startPolling();
    _fetchFiles();
  }

  void _onDisconnected() {
    if (kDebugMode) {
      print('FileShareService: Disconnected');
    }
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      _fetchFiles();
    });
  }

  /// Share a file with crew
  /// For files <= 100KB: embedded as base64 in SignalK note
  /// For larger files: metadata only (TODO: implement HTTP server fallback)
  Future<bool> shareFile({
    required String filePath,
    String? toId,  // null = broadcast
    Uint8List? thumbnailData,
  }) async {
    final profile = _crewService.localProfile;
    if (profile == null) {
      if (kDebugMode) {
        print('Cannot share file: no crew profile');
      }
      return false;
    }

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        if (kDebugMode) {
          print('File does not exist: $filePath');
        }
        return false;
      }

      final bytes = await file.readAsBytes();
      final filename = filePath.split('/').last;
      final mimeType = _getMimeType(filename);

      final sharedFile = SharedFile(
        id: const Uuid().v4(),
        fromId: profile.id,
        fromName: profile.name,
        toId: toId,
        filename: filename,
        mimeType: mimeType,
        size: bytes.length,
        timestamp: DateTime.now().toUtc(),
        thumbnailData: thumbnailData != null ? base64Encode(thumbnailData) : null,
        data: bytes.length <= _embeddedFileSizeLimit ? base64Encode(bytes) : null,
        status: FileTransferStatus.uploading,
      );

      // Add to local cache immediately
      _files.insert(0, sharedFile);
      notifyListeners();

      // Sync to SignalK
      bool success = false;
      if (_signalKService.isConnected && _resourcesApiAvailable) {
        final resourceData = sharedFile.toNoteResource(
          lat: _getVesselLat(),
          lng: _getVesselLng(),
        );
        success = await _signalKService.putResource(
          _fileResourceType,
          sharedFile.id,
          resourceData,
        );
      }

      // Update status
      final index = _files.indexWhere((f) => f.id == sharedFile.id);
      if (index != -1) {
        _files[index] = sharedFile.copyWith(
          status: success ? FileTransferStatus.available : FileTransferStatus.failed,
        );
      }

      await _saveCachedFiles();
      notifyListeners();

      return success;
    } catch (e) {
      if (kDebugMode) {
        print('Error sharing file: $e');
      }
      return false;
    }
  }

  /// Share bytes directly (useful for in-memory data like voice memos)
  Future<bool> shareBytes({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    String? toId,
    Uint8List? thumbnailData,
  }) async {
    final profile = _crewService.localProfile;
    if (profile == null) return false;

    try {
      final sharedFile = SharedFile(
        id: const Uuid().v4(),
        fromId: profile.id,
        fromName: profile.name,
        toId: toId,
        filename: filename,
        mimeType: mimeType,
        size: bytes.length,
        timestamp: DateTime.now().toUtc(),
        thumbnailData: thumbnailData != null ? base64Encode(thumbnailData) : null,
        data: bytes.length <= _embeddedFileSizeLimit ? base64Encode(bytes) : null,
        status: FileTransferStatus.uploading,
      );

      // Add to local cache
      _files.insert(0, sharedFile);
      notifyListeners();

      // Sync to SignalK
      bool success = false;
      if (_signalKService.isConnected && _resourcesApiAvailable) {
        final resourceData = sharedFile.toNoteResource(
          lat: _getVesselLat(),
          lng: _getVesselLng(),
        );
        success = await _signalKService.putResource(
          _fileResourceType,
          sharedFile.id,
          resourceData,
        );
      }

      // Update status
      final index = _files.indexWhere((f) => f.id == sharedFile.id);
      if (index != -1) {
        _files[index] = sharedFile.copyWith(
          status: success ? FileTransferStatus.available : FileTransferStatus.failed,
        );
      }

      await _saveCachedFiles();
      notifyListeners();

      return success;
    } catch (e) {
      if (kDebugMode) {
        print('Error sharing bytes: $e');
      }
      return false;
    }
  }

  /// Download a file (for embedded files, decode from base64)
  Future<String?> downloadFile(SharedFile sharedFile) async {
    if (sharedFile.isEmbedded && sharedFile.data != null) {
      try {
        // Update status to downloading
        _updateFileStatus(sharedFile.id, FileTransferStatus.downloading);

        final bytes = base64Decode(sharedFile.data!);
        final localPath = await _saveToLocal(sharedFile.filename, bytes);

        // Update status to completed
        _updateFileStatus(sharedFile.id, FileTransferStatus.completed);

        return localPath;
      } catch (e) {
        if (kDebugMode) {
          print('Error downloading embedded file: $e');
        }
        _updateFileStatus(sharedFile.id, FileTransferStatus.failed);
        return null;
      }
    } else if (sharedFile.downloadUrl != null) {
      // Download from URL (for large files)
      try {
        _updateFileStatus(sharedFile.id, FileTransferStatus.downloading);

        final response = await http.get(Uri.parse(sharedFile.downloadUrl!));
        if (response.statusCode == 200) {
          final localPath = await _saveToLocal(sharedFile.filename, response.bodyBytes);
          _updateFileStatus(sharedFile.id, FileTransferStatus.completed);
          return localPath;
        } else {
          _updateFileStatus(sharedFile.id, FileTransferStatus.failed);
          return null;
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error downloading file from URL: $e');
        }
        _updateFileStatus(sharedFile.id, FileTransferStatus.failed);
        return null;
      }
    }

    return null;
  }

  /// Get the local file path if already downloaded
  String? getLocalPath(SharedFile sharedFile) {
    if (_downloadsDir == null) return null;
    final localPath = '${_downloadsDir!.path}/${sharedFile.id}_${sharedFile.filename}';
    final file = File(localPath);
    if (file.existsSync()) {
      return localPath;
    }
    return null;
  }

  /// Save file bytes to local downloads directory
  Future<String> _saveToLocal(String filename, Uint8List bytes) async {
    await _initDownloadsDir();
    final uniqueFilename = '${const Uuid().v4()}_$filename';
    final localPath = '${_downloadsDir!.path}/$uniqueFilename';
    await File(localPath).writeAsBytes(bytes);
    return localPath;
  }

  void _updateFileStatus(String fileId, FileTransferStatus status, {double? progress}) {
    final index = _files.indexWhere((f) => f.id == fileId);
    if (index != -1) {
      _files[index] = _files[index].copyWith(status: status, progress: progress);
      notifyListeners();
    }
  }

  /// Fetch files from SignalK
  Future<void> _fetchFiles() async {
    if (!_signalKService.isConnected) return;

    try {
      final resources = await _signalKService.getResources(_fileResourceType);

      if (resources.isEmpty) return;

      bool changed = false;
      final myId = _crewService.localProfile?.id;

      for (final entry in resources.entries) {
        final noteId = entry.key;
        final noteData = entry.value as Map<String, dynamic>;

        // Filter by our group
        final group = noteData['group'] as String?;
        if (group != _fileGroupName) continue;

        // Skip files we already have
        if (_files.any((f) => f.id == noteId)) continue;

        try {
          final descriptionJson = noteData['description'] as String?;
          if (descriptionJson == null) continue;

          final fileData = jsonDecode(descriptionJson) as Map<String, dynamic>;
          var sharedFile = SharedFile.fromJson(fileData);

          // Check if this file is for us (broadcast or direct to us)
          if (sharedFile.toId == null || sharedFile.toId == myId || sharedFile.fromId == myId) {
            // Set status to available for received files
            sharedFile = sharedFile.copyWith(
              status: FileTransferStatus.available,
            );
            _files.insert(0, sharedFile);
            changed = true;
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing file $noteId: $e');
          }
        }
      }

      if (changed) {
        _files.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        await _saveCachedFiles();
        notifyListeners();
      }

      _resourcesApiAvailable = true;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching files: $e');
      }
    }
  }

  /// Delete a shared file
  Future<bool> deleteFile(String fileId) async {
    // Remove from local cache
    _files.removeWhere((f) => f.id == fileId);
    await _saveCachedFiles();
    notifyListeners();

    // Remove from SignalK
    if (_signalKService.isConnected) {
      await _signalKService.deleteResource(_fileResourceType, fileId);
    }

    // Delete local file if exists
    if (_downloadsDir != null) {
      final dir = _downloadsDir!;
      final files = dir.listSync();
      for (final file in files) {
        if (file.path.contains(fileId)) {
          await file.delete();
        }
      }
    }

    return true;
  }

  /// Get files for broadcast (sent to all)
  List<SharedFile> get broadcastFiles {
    return _files.where((f) => f.toId == null).toList();
  }

  /// Get files from/to a specific crew member
  List<SharedFile> getFilesWithCrew(String crewId) {
    final myId = _crewService.localProfile?.id;
    return _files.where((f) =>
        (f.fromId == crewId && f.toId == myId) ||
        (f.fromId == myId && f.toId == crewId)
    ).toList();
  }

  /// Get files I've shared
  List<SharedFile> get mySharedFiles {
    final myId = _crewService.localProfile?.id;
    return _files.where((f) => f.fromId == myId).toList();
  }

  /// Get files shared with me
  List<SharedFile> get receivedFiles {
    final myId = _crewService.localProfile?.id;
    return _files.where((f) => f.fromId != myId).toList();
  }

  double _getVesselLat() {
    final posData = _signalKService.getValue('navigation.position');
    if (posData?.value is Map) {
      final pos = posData!.value as Map;
      return (pos['latitude'] as num?)?.toDouble() ?? 0.0;
    }
    return 0.0;
  }

  double _getVesselLng() {
    final posData = _signalKService.getValue('navigation.position');
    if (posData?.value is Map) {
      final pos = posData!.value as Map;
      return (pos['longitude'] as num?)?.toDouble() ?? 0.0;
    }
    return 0.0;
  }

  /// Get MIME type from filename
  String _getMimeType(String filename) {
    final parts = filename.split('.');
    final ext = parts.length > 1 ? '.${parts.last.toLowerCase()}' : '';
    switch (ext) {
      // Images
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      // Documents
      case '.pdf':
        return 'application/pdf';
      case '.doc':
        return 'application/msword';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      // Navigation
      case '.gpx':
        return 'application/gpx+xml';
      case '.kml':
        return 'application/vnd.google-earth.kml+xml';
      // Audio
      case '.mp3':
        return 'audio/mpeg';
      case '.m4a':
        return 'audio/mp4';
      case '.aac':
        return 'audio/aac';
      case '.wav':
        return 'audio/wav';
      // Text
      case '.txt':
        return 'text/plain';
      case '.json':
        return 'application/json';
      default:
        return 'application/octet-stream';
    }
  }

  /// Clear all files (for testing/debug)
  Future<void> clearAllFiles() async {
    _files.clear();
    await _saveCachedFiles();
    notifyListeners();
  }
}
