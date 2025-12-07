import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../models/shared_file.dart';
import '../../services/signalk_service.dart';
import '../../services/file_share_service.dart';
import '../../services/crew_service.dart';
import '../../services/tool_registry.dart';
import '../crew/file_picker_widget.dart';
import '../crew/file_viewer.dart';

/// Dashboard tool for file sharing
class FileShareTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const FileShareTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer2<FileShareService, CrewService>(
      builder: (context, fileShareService, crewService, child) {
        if (!crewService.hasProfile) {
          return _buildNoProfileView();
        }

        final files = fileShareService.files;

        return ClipRect(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with share button
              _buildHeader(context, files.length),

              // Files list
              Flexible(
                child: files.isEmpty
                    ? _buildEmptyView()
                    : _buildFilesList(context, files),
              ),

              // Share button
              _buildShareButton(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_shared, size: 20),
          const SizedBox(width: 8),
          const Text(
            'Shared Files',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            '$count files',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesList(BuildContext context, List<SharedFile> files) {
    // Show most recent first
    final sortedFiles = List<SharedFile>.from(files)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Limit to last 10 files
    final displayFiles = sortedFiles.take(10).toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      shrinkWrap: true,
      itemCount: displayFiles.length,
      itemBuilder: (context, index) {
        final file = displayFiles[index];
        return _FileListItem(file: file);
      },
    );
  }

  Widget _buildShareButton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => _showFilePicker(context),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Share File'),
        ),
      ),
    );
  }

  void _showFilePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) {
          return const FilePickerWidget();
        },
      ),
    );
  }

  Widget _buildEmptyView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_off, size: 48, color: Colors.grey),
          SizedBox(height: 8),
          Text(
            'No shared files',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildNoProfileView() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text(
              'Create a crew profile to share files',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Individual file list item
class _FileListItem extends StatelessWidget {
  final SharedFile file;

  const _FileListItem({required this.file});

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat.Hm();

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: _getFileColor(file.mimeType),
        child: Icon(
          _getFileIcon(file.mimeType),
          size: 16,
          color: Colors.white,
        ),
      ),
      title: Text(
        file.filename,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        '${file.fromName} • ${timeFormat.format(file.timestamp.toLocal())}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
          icon: const Icon(Icons.download, size: 18),
          onPressed: () => _viewFile(context),
          padding: EdgeInsets.zero,
        ),
      ),
      onTap: () => _viewFile(context),
    );
  }

  void _viewFile(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.7,
          child: FileViewer(sharedFile: file),
        ),
      ),
    );
  }

  IconData _getFileIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.video_file;
    if (mimeType.startsWith('audio/')) return Icons.audio_file;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('gpx') || mimeType.contains('xml')) return Icons.map;
    if (mimeType.contains('text')) return Icons.description;
    return Icons.insert_drive_file;
  }

  Color _getFileColor(String mimeType) {
    if (mimeType.startsWith('image/')) return Colors.purple;
    if (mimeType.startsWith('video/')) return Colors.red;
    if (mimeType.startsWith('audio/')) return Colors.orange;
    if (mimeType.contains('pdf')) return Colors.red.shade700;
    if (mimeType.contains('gpx') || mimeType.contains('xml')) return Colors.green;
    if (mimeType.contains('text')) return Colors.blue;
    return Colors.grey;
  }
}

/// Builder for the file share tool
class FileShareToolBuilder implements ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'file_share',
      name: 'Shared Files',
      description: 'Share and receive files with crew members',
      category: ToolCategory.system,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return FileShareTool(
      config: config,
      signalKService: signalKService,
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) => null;
}
