import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;
import 'package:open_filex/open_filex.dart';
import '../../models/shared_file.dart';
import '../../services/file_share_service.dart';
import '../../services/setup_service.dart';

/// Widget for viewing and managing a shared file
class FileViewer extends StatefulWidget {
  final SharedFile sharedFile;

  const FileViewer({
    super.key,
    required this.sharedFile,
  });

  @override
  State<FileViewer> createState() => _FileViewerState();
}

class _FileViewerState extends State<FileViewer> {
  bool _isDownloading = false;
  bool _isImporting = false;
  String? _localPath;

  /// Check if this is a ZedDisplay dashboard file
  bool get _isDashboardFile =>
      widget.sharedFile.filename.toLowerCase().endsWith('.zedjson');

  @override
  void initState() {
    super.initState();
    _checkLocalFile();
  }

  void _checkLocalFile() {
    final fileShareService = context.read<FileShareService>();
    _localPath = fileShareService.getLocalPath(widget.sharedFile);
    if (_localPath != null) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.sharedFile;

    return Scaffold(
      appBar: AppBar(
        title: Text(file.filename),
        actions: [
          if (_localPath != null)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: _shareFile,
              tooltip: 'Share',
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _confirmDelete,
            tooltip: 'Delete',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // File preview
            _buildPreview(),

            // File info
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Filename
                  Text(
                    file.filename,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),

                  // File metadata
                  _InfoRow(label: 'Type', value: file.fileType.label),
                  _InfoRow(label: 'Size', value: file.sizeDisplay),
                  _InfoRow(label: 'From', value: file.fromName),
                  _InfoRow(
                    label: 'Sent',
                    value: _formatDateTime(file.timestamp),
                  ),
                  if (file.toId != null)
                    _InfoRow(label: 'To', value: file.toId == 'all' ? 'All crew' : 'Direct'),

                  const SizedBox(height: 24),

                  // Status
                  _buildStatusSection(),

                  const SizedBox(height: 24),

                  // Action buttons
                  _buildActionButtons(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final file = widget.sharedFile;

    // Image preview
    if (file.fileType == SharedFileType.image) {
      Widget? imageWidget;

      // Check for local file first
      if (_localPath != null) {
        imageWidget = Image.file(
          File(_localPath!),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => _buildPlaceholder(),
        );
      }
      // Then check for embedded thumbnail
      else if (file.thumbnailData != null) {
        try {
          final bytes = base64Decode(file.thumbnailData!);
          imageWidget = Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => _buildPlaceholder(),
          );
        } catch (e) {
          imageWidget = _buildPlaceholder();
        }
      }
      // Then check for embedded data
      else if (file.isEmbedded && file.data != null) {
        try {
          final bytes = base64Decode(file.data!);
          imageWidget = Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => _buildPlaceholder(),
          );
        } catch (e) {
          imageWidget = _buildPlaceholder();
        }
      }

      if (imageWidget != null) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.4,
          ),
          color: Colors.black,
          child: Center(child: imageWidget),
        );
      }
    }

    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    final file = widget.sharedFile;
    IconData icon;
    Color color;

    switch (file.fileType) {
      case SharedFileType.image:
        icon = Icons.image;
        color = Colors.blue;
        break;
      case SharedFileType.document:
        icon = Icons.description;
        color = Colors.red;
        break;
      case SharedFileType.waypoint:
        icon = Icons.location_on;
        color = Colors.green;
        break;
      case SharedFileType.audio:
        icon = Icons.audiotrack;
        color = Colors.purple;
        break;
      case SharedFileType.other:
        icon = Icons.insert_drive_file;
        color = Colors.grey;
        break;
    }

    return Container(
      height: 200,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: color),
            const SizedBox(height: 8),
            Text(
              file.fileType.label,
              style: TextStyle(color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSection() {
    final file = widget.sharedFile;
    final status = file.status;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case FileTransferStatus.pending:
        statusColor = Colors.grey;
        statusText = 'Pending';
        statusIcon = Icons.hourglass_empty;
        break;
      case FileTransferStatus.uploading:
        statusColor = Colors.blue;
        statusText = 'Uploading...';
        statusIcon = Icons.cloud_upload;
        break;
      case FileTransferStatus.available:
        statusColor = Colors.green;
        statusText = file.isEmbedded ? 'Available' : 'Available for download';
        statusIcon = Icons.cloud_done;
        break;
      case FileTransferStatus.downloading:
        statusColor = Colors.blue;
        statusText = 'Downloading...';
        statusIcon = Icons.cloud_download;
        break;
      case FileTransferStatus.completed:
        statusColor = Colors.green;
        statusText = 'Downloaded';
        statusIcon = Icons.check_circle;
        break;
      case FileTransferStatus.failed:
        statusColor = Colors.red;
        statusText = 'Failed';
        statusIcon = Icons.error;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor),
          const SizedBox(width: 12),
          Text(
            statusText,
            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
          ),
          if (file.progress != null) ...[
            const Spacer(),
            Text(
              '${(file.progress! * 100).toInt()}%',
              style: TextStyle(color: statusColor),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final hasLocal = _localPath != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // For dashboard files, show Import button
        if (_isDashboardFile) ...[
          FilledButton.icon(
            onPressed: _isImporting ? null : _importDashboard,
            icon: _isImporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.dashboard_customize),
            label: Text(_isImporting ? 'Importing...' : 'Import Dashboard'),
          ),
          const SizedBox(height: 12),
        ] else ...[
          // Download/Open button for other files
          if (!hasLocal)
            FilledButton.icon(
              onPressed: _isDownloading ? null : _downloadFile,
              icon: _isDownloading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: Text(_isDownloading ? 'Downloading...' : 'Download'),
            )
          else
            FilledButton.icon(
              onPressed: _openFile,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open'),
            ),
          const SizedBox(height: 12),
        ],

        // Share button (if downloaded)
        if (hasLocal)
          OutlinedButton.icon(
            onPressed: _shareFile,
            icon: const Icon(Icons.share),
            label: const Text('Share to Other Apps'),
          ),
      ],
    );
  }

  Future<void> _downloadFile() async {
    setState(() => _isDownloading = true);

    try {
      final fileShareService = context.read<FileShareService>();
      final path = await fileShareService.downloadFile(widget.sharedFile);

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _localPath = path;
        });

        if (path != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File downloaded')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Download failed')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _importDashboard() async {
    setState(() => _isImporting = true);

    try {
      // First download the file if not already downloaded
      String? path = _localPath;
      if (path == null) {
        final fileShareService = context.read<FileShareService>();
        path = await fileShareService.downloadFile(widget.sharedFile);
        if (path == null) {
          throw Exception('Failed to download dashboard file');
        }
        _localPath = path;
      }

      // Read the JSON content
      final file = File(path);
      final jsonString = await file.readAsString();

      // Ask user if they want to switch immediately
      if (!mounted) return;
      final switchNow = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Import Dashboard'),
          content: Text(
            'Import "${widget.sharedFile.filename.replaceAll('.zedjson', '')}"?\n\n'
            'Would you like to switch to it now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Import Only'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Import & Switch'),
            ),
          ],
        ),
      );

      if (switchNow == null) {
        setState(() => _isImporting = false);
        return;
      }

      // Import the dashboard
      final setupService = context.read<SetupService>();
      if (switchNow) {
        await setupService.importAndLoadSetup(jsonString);
      } else {
        await setupService.importSetup(jsonString);
      }

      if (mounted) {
        setState(() => _isImporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(switchNow
                ? 'Dashboard imported and activated'
                : 'Dashboard imported'),
            backgroundColor: Colors.green,
          ),
        );
        if (switchNow) {
          // Go back to dashboard
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isImporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openFile() async {
    if (_localPath == null) return;

    try {
      final result = await OpenFilex.open(_localPath!);

      if (result.type != ResultType.done) {
        if (mounted) {
          // Show error or fallback to share
          if (result.type == ResultType.noAppToOpen) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No app available to open this file type')),
            );
            // Offer to share instead
            await _shareFile();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Cannot open file: ${result.message}')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot open file: $e')),
        );
      }
    }
  }

  Future<void> _shareFile() async {
    if (_localPath == null) return;

    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(_localPath!)], text: widget.sharedFile.filename),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing: $e')),
        );
      }
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete File?'),
        content: const Text('This file will be removed from your device and the shared list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final fileShareService = context.read<FileShareService>();
      await fileShareService.deleteFile(widget.sharedFile.id);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  String _formatDateTime(DateTime time) {
    final localTime = time.toLocal();
    return '${localTime.day}/${localTime.month}/${localTime.year} '
        '${localTime.hour.toString().padLeft(2, '0')}:'
        '${localTime.minute.toString().padLeft(2, '0')}';
  }
}

/// Info row widget
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
