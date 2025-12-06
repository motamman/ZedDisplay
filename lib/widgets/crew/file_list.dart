import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/shared_file.dart';
import '../../services/file_share_service.dart';
import '../../services/crew_service.dart';
import 'file_viewer.dart';
import 'file_picker_widget.dart';

/// Widget for displaying a list of shared files
class FileList extends StatelessWidget {
  /// Filter to show only broadcast files
  final bool broadcastOnly;

  /// Filter to show files from/to a specific crew member
  final String? crewId;

  const FileList({
    super.key,
    this.broadcastOnly = false,
    this.crewId,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<FileShareService>(
      builder: (context, fileShareService, child) {
        List<SharedFile> files;

        if (crewId != null) {
          files = fileShareService.getFilesWithCrew(crewId!);
        } else if (broadcastOnly) {
          files = fileShareService.broadcastFiles;
        } else {
          files = fileShareService.files;
        }

        if (files.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.folder_open,
                  size: 64,
                  color: Colors.grey,
                ),
                SizedBox(height: 16),
                Text(
                  'No shared files',
                  style: TextStyle(color: Colors.grey),
                ),
                SizedBox(height: 8),
                Text(
                  'Share files with your crew',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: files.length,
          itemBuilder: (context, index) {
            final file = files[index];
            return _FileListItem(file: file);
          },
        );
      },
    );
  }
}

/// Individual file list item
class _FileListItem extends StatelessWidget {
  final SharedFile file;

  const _FileListItem({required this.file});

  @override
  Widget build(BuildContext context) {
    final myId = context.read<CrewService>().localProfile?.id;
    final isFromMe = file.fromId == myId;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => _openFile(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // File type icon with thumbnail
              _buildThumbnail(context),
              const SizedBox(width: 12),

              // File info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.filename,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          isFromMe ? 'You' : file.fromName,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          file.sizeDisplay,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey,
                              ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(file.timestamp),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Status indicator
              _buildStatusIcon(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    // Try to show image thumbnail
    if (file.fileType == SharedFileType.image) {
      Widget? imageWidget;

      // Check for embedded thumbnail
      if (file.thumbnailData != null) {
        try {
          final bytes = base64Decode(file.thumbnailData!);
          imageWidget = Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          );
        } catch (e) {
          // Fall through to placeholder
        }
      }
      // Check for embedded data
      else if (file.isEmbedded && file.data != null && file.size < 50 * 1024) {
        try {
          final bytes = base64Decode(file.data!);
          imageWidget = Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          );
        } catch (e) {
          // Fall through to placeholder
        }
      }

      if (imageWidget != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 48,
            height: 48,
            child: imageWidget,
          ),
        );
      }
    }

    // Default icon
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: _getTypeColor().withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        _getTypeIcon(),
        color: _getTypeColor(),
      ),
    );
  }

  Widget _buildStatusIcon() {
    switch (file.status) {
      case FileTransferStatus.uploading:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case FileTransferStatus.downloading:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case FileTransferStatus.available:
        return Icon(
          file.isEmbedded ? Icons.cloud_done : Icons.cloud_download,
          color: Colors.green,
          size: 20,
        );
      case FileTransferStatus.completed:
        return const Icon(
          Icons.check_circle,
          color: Colors.green,
          size: 20,
        );
      case FileTransferStatus.failed:
        return const Icon(
          Icons.error,
          color: Colors.red,
          size: 20,
        );
      case FileTransferStatus.pending:
        return const Icon(
          Icons.hourglass_empty,
          color: Colors.grey,
          size: 20,
        );
    }
  }

  IconData _getTypeIcon() {
    switch (file.fileType) {
      case SharedFileType.image:
        return Icons.image;
      case SharedFileType.document:
        return Icons.description;
      case SharedFileType.waypoint:
        return Icons.location_on;
      case SharedFileType.audio:
        return Icons.audiotrack;
      case SharedFileType.other:
        return Icons.insert_drive_file;
    }
  }

  Color _getTypeColor() {
    switch (file.fileType) {
      case SharedFileType.image:
        return Colors.blue;
      case SharedFileType.document:
        return Colors.red;
      case SharedFileType.waypoint:
        return Colors.green;
      case SharedFileType.audio:
        return Colors.purple;
      case SharedFileType.other:
        return Colors.grey;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final localTime = time.toLocal();

    if (now.difference(time).inDays == 0) {
      return '${localTime.hour.toString().padLeft(2, '0')}:'
          '${localTime.minute.toString().padLeft(2, '0')}';
    } else if (now.difference(time).inDays == 1) {
      return 'Yesterday';
    } else {
      return '${localTime.day}/${localTime.month}';
    }
  }

  void _openFile(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FileViewer(sharedFile: file),
      ),
    );
  }
}

/// Screen for browsing all shared files
class FilesScreen extends StatelessWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared Files'),
      ),
      body: const FileList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showFilePickerSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Share File'),
      ),
    );
  }
}
