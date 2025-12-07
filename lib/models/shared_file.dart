import 'dart:convert';

/// Types of files that can be shared
enum SharedFileType {
  image,      // PNG, JPG, GIF
  document,   // PDF
  waypoint,   // GPX
  audio,      // MP3, AAC, M4A (voice memos)
  other,      // Unknown type
}

/// Represents a file shared between crew members
class SharedFile {
  final String id;
  final String fromId;
  final String fromName;
  final String? toId;  // null = broadcast, otherwise specific crew ID
  final String filename;
  final String mimeType;
  final int size;  // bytes
  final DateTime timestamp;
  final String? thumbnailData;  // Base64 for images

  /// For small files (< 100KB): base64 encoded content
  /// For large files: null (use downloadUrl)
  final String? data;

  /// For large files: URL to download from sender's device
  final String? downloadUrl;

  /// Status for downloads
  final FileTransferStatus status;
  final double? progress;  // 0.0 to 1.0 for downloads

  SharedFile({
    required this.id,
    required this.fromId,
    required this.fromName,
    this.toId,
    required this.filename,
    required this.mimeType,
    required this.size,
    required this.timestamp,
    this.thumbnailData,
    this.data,
    this.downloadUrl,
    this.status = FileTransferStatus.pending,
    this.progress,
  });

  /// Get the file type from mime type
  SharedFileType get fileType {
    if (mimeType.startsWith('image/')) return SharedFileType.image;
    if (mimeType == 'application/pdf') return SharedFileType.document;
    if (mimeType.contains('gpx') || filename.toLowerCase().endsWith('.gpx')) {
      return SharedFileType.waypoint;
    }
    if (mimeType.startsWith('audio/')) return SharedFileType.audio;
    return SharedFileType.other;
  }

  /// Check if file is embedded (small file with data)
  bool get isEmbedded => data != null && data!.isNotEmpty;

  /// Check if file requires download
  bool get requiresDownload => !isEmbedded && downloadUrl != null;

  /// Human-readable file size
  String get sizeDisplay {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// File extension
  String get extension => filename.contains('.')
      ? filename.split('.').last.toLowerCase()
      : '';

  SharedFile copyWith({
    String? id,
    String? fromId,
    String? fromName,
    String? toId,
    String? filename,
    String? mimeType,
    int? size,
    DateTime? timestamp,
    String? thumbnailData,
    String? data,
    String? downloadUrl,
    FileTransferStatus? status,
    double? progress,
  }) {
    return SharedFile(
      id: id ?? this.id,
      fromId: fromId ?? this.fromId,
      fromName: fromName ?? this.fromName,
      toId: toId ?? this.toId,
      filename: filename ?? this.filename,
      mimeType: mimeType ?? this.mimeType,
      size: size ?? this.size,
      timestamp: timestamp ?? this.timestamp,
      thumbnailData: thumbnailData ?? this.thumbnailData,
      data: data ?? this.data,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      status: status ?? this.status,
      progress: progress ?? this.progress,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fromId': fromId,
      'fromName': fromName,
      'toId': toId,
      'filename': filename,
      'mimeType': mimeType,
      'size': size,
      'timestamp': timestamp.toIso8601String(),
      'thumbnailData': thumbnailData,
      'data': data,
      'downloadUrl': downloadUrl,
      'status': status.name,
      'progress': progress,
    };
  }

  factory SharedFile.fromJson(Map<String, dynamic> json) {
    return SharedFile(
      id: json['id'] as String,
      fromId: json['fromId'] as String,
      fromName: json['fromName'] as String,
      toId: json['toId'] as String?,
      filename: json['filename'] as String,
      mimeType: json['mimeType'] as String,
      size: json['size'] as int,
      timestamp: DateTime.parse(json['timestamp'] as String),
      thumbnailData: json['thumbnailData'] as String?,
      data: json['data'] as String?,
      downloadUrl: json['downloadUrl'] as String?,
      status: FileTransferStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => FileTransferStatus.pending,
      ),
      progress: (json['progress'] as num?)?.toDouble(),
    );
  }

  /// Create SignalK notes resource format
  Map<String, dynamic> toNoteResource({double lat = 0.0, double lng = 0.0}) {
    // Don't include large data in the note - only metadata
    final fileData = toJson();
    // Remove actual file data from notes (too large)
    if (size > 100 * 1024) {
      fileData.remove('data');
    }

    return {
      'name': '$fromName: $filename',
      'description': jsonEncode(fileData),
      'group': 'zeddisplay-files',
      'position': {'latitude': lat, 'longitude': lng},
    };
  }

  factory SharedFile.fromNoteResource(String id, Map<String, dynamic> resource) {
    final description = resource['description'] as String;
    final data = jsonDecode(description) as Map<String, dynamic>;
    return SharedFile.fromJson({...data, 'id': id});
  }
}

/// Status of file transfer
enum FileTransferStatus {
  pending,      // Not started
  uploading,    // Sending to server
  available,    // Ready to download
  downloading,  // Currently downloading
  completed,    // Successfully downloaded
  failed,       // Transfer failed
}

/// Extension to get display info for file types
extension SharedFileTypeExtension on SharedFileType {
  String get label {
    switch (this) {
      case SharedFileType.image:
        return 'Image';
      case SharedFileType.document:
        return 'Document';
      case SharedFileType.waypoint:
        return 'Waypoint';
      case SharedFileType.audio:
        return 'Audio';
      case SharedFileType.other:
        return 'File';
    }
  }

  String get icon {
    switch (this) {
      case SharedFileType.image:
        return 'image';
      case SharedFileType.document:
        return 'description';
      case SharedFileType.waypoint:
        return 'location_on';
      case SharedFileType.audio:
        return 'audiotrack';
      case SharedFileType.other:
        return 'insert_drive_file';
    }
  }
}
