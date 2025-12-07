import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../services/file_share_service.dart';

/// Widget for picking and sharing files with crew
class FilePickerWidget extends StatefulWidget {
  /// Optional crew ID for direct file sharing
  final String? toCrewId;

  const FilePickerWidget({
    super.key,
    this.toCrewId,
  });

  @override
  State<FilePickerWidget> createState() => _FilePickerWidgetState();
}

class _FilePickerWidgetState extends State<FilePickerWidget> {
  bool _isSharing = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Share File',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Text(
            widget.toCrewId != null
                ? 'Send a file directly to this crew member'
                : 'Share a file with all crew members',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: 24),
          if (_isSharing)
            const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Sharing file...'),
                ],
              ),
            )
          else
            Column(
              children: [
                _FileTypeButton(
                  icon: Icons.image,
                  label: 'Image',
                  description: 'Photos and screenshots',
                  onTap: () => _pickFile(FileType.image),
                ),
                const SizedBox(height: 12),
                _FileTypeButton(
                  icon: Icons.picture_as_pdf,
                  label: 'Document',
                  description: 'PDFs and documents',
                  onTap: () => _pickFile(FileType.custom, extensions: ['pdf', 'doc', 'docx', 'txt']),
                ),
                const SizedBox(height: 12),
                _FileTypeButton(
                  icon: Icons.location_on,
                  label: 'Waypoint/Route',
                  description: 'GPX and KML files',
                  onTap: () => _pickFile(FileType.custom, extensions: ['gpx', 'kml']),
                ),
                const SizedBox(height: 12),
                _FileTypeButton(
                  icon: Icons.audiotrack,
                  label: 'Audio',
                  description: 'Voice memos and audio files',
                  onTap: () => _pickFile(FileType.audio),
                ),
                const SizedBox(height: 12),
                _FileTypeButton(
                  icon: Icons.insert_drive_file,
                  label: 'Any File',
                  description: 'Select any file type',
                  onTap: () => _pickFile(FileType.any),
                ),
              ],
            ),
          const SizedBox(height: 16),
          // Size limit note
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Files up to 100KB are shared instantly. Larger files require direct device connection.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile(FileType type, {List<String>? extensions}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: type,
        allowedExtensions: extensions,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.path != null) {
          await _shareFile(file.path!);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking file: $e')),
        );
      }
    }
  }

  Future<void> _shareFile(String filePath) async {
    setState(() => _isSharing = true);

    try {
      final fileShareService = context.read<FileShareService>();
      final success = await fileShareService.shareFile(
        filePath: filePath,
        toId: widget.toCrewId,
      );

      if (mounted) {
        Navigator.of(context).pop(success);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'File shared successfully' : 'Failed to share file'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSharing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing file: $e')),
        );
      }
    }
  }
}

/// Button for selecting a file type
class _FileTypeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  const _FileTypeButton({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Show file picker as a bottom sheet
Future<bool?> showFilePickerSheet(BuildContext context, {String? toCrewId}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        child: FilePickerWidget(toCrewId: toCrewId),
      ),
    ),
  );
}
