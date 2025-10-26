import 'package:flutter/material.dart';
import '../../services/signalk_service.dart';

/// Dialog for configuring source and label for a selected path (combines steps 2 & 3)
class ConfigureDataSourceDialog extends StatefulWidget {
  final SignalKService signalKService;
  final String path;

  const ConfigureDataSourceDialog({
    super.key,
    required this.signalKService,
    required this.path,
  });

  @override
  State<ConfigureDataSourceDialog> createState() => _ConfigureDataSourceDialogState();
}

class _ConfigureDataSourceDialogState extends State<ConfigureDataSourceDialog> {
  final TextEditingController _labelController = TextEditingController();
  Map<String, dynamic>? _sources;
  bool _loadingSources = false;
  String? _selectedSource;
  bool _showSourceSelection = false;

  @override
  void initState() {
    super.initState();
    // Auto-generate label from path
    final parts = widget.path.split('.');
    _labelController.text = parts.length > 1 ? parts.last : widget.path;
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _loadSources() async {
    setState(() {
      _loadingSources = true;
      _sources = null;
    });

    try {
      final sources = await widget.signalKService.getSourcesForPath(widget.path);
      if (mounted) {
        setState(() {
          _sources = sources;
          _loadingSources = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingSources = false;
        });
      }
    }
  }

  void _add() {
    Navigator.of(context).pop({
      'source': _selectedSource,
      'label': _labelController.text.trim().isEmpty ? null : _labelController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configure Data Source'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Show selected path
              Text(
                'Path',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.path,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Label input
              TextField(
                controller: _labelController,
                decoration: const InputDecoration(
                  labelText: 'Display Label',
                  helperText: 'How this data will be labeled',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),

              // Advanced: Source selection (collapsible)
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _showSourceSelection = !_showSourceSelection;
                    if (_showSourceSelection && _sources == null && !_loadingSources) {
                      _loadSources();
                    }
                  });
                },
                icon: Icon(_showSourceSelection ? Icons.expand_less : Icons.expand_more),
                label: const Text('Data Source (Optional)'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                ),
              ),

              // Source selection
              if (_showSourceSelection) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),

                if (_loadingSources)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_sources == null || _sources!.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Using default source (auto)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        RadioListTile<String?>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Auto (default)', style: TextStyle(fontSize: 13)),
                          subtitle: const Text('Use active source', style: TextStyle(fontSize: 11)),
                          value: null,
                          groupValue: _selectedSource,
                          onChanged: (value) => setState(() => _selectedSource = value),
                        ),
                        ..._sources!.entries.map((entry) {
                          final sourceId = entry.key;
                          final sourceData = entry.value as Map<String, dynamic>;
                          final isActive = sourceData['isActive'] == true;

                          return RadioListTile<String>(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              sourceId,
                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                            ),
                            subtitle: isActive
                                ? const Text(
                                    'Default',
                                    style: TextStyle(fontSize: 10, color: Colors.orange),
                                  )
                                : null,
                            value: sourceId,
                            groupValue: _selectedSource,
                            onChanged: (value) => setState(() => _selectedSource = value),
                          );
                        }),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add'),
        ),
      ],
    );
  }
}
