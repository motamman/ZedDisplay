import 'package:flutter/material.dart';
import '../../services/signalk_service.dart';

/// Dialog for selecting a data source for a specific path
class SourceSelectorDialog extends StatefulWidget {
  final SignalKService signalKService;
  final String path;
  final String? currentSource;
  final Function(String? source) onSelect;

  const SourceSelectorDialog({
    super.key,
    required this.signalKService,
    required this.path,
    this.currentSource,
    required this.onSelect,
  });

  @override
  State<SourceSelectorDialog> createState() => _SourceSelectorDialogState();
}

class _SourceSelectorDialogState extends State<SourceSelectorDialog> {
  Map<String, dynamic>? _sources;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sources = await widget.signalKService.getSourcesForPath(widget.path);
      setState(() {
        _sources = sources;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pathParts = widget.path.split('.');
    final pathName = pathParts.isNotEmpty ? pathParts.last : widget.path;

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 600,
          maxHeight: 800,
          minWidth: 500,
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.sensors,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Data Source',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          pathName,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer
                                    .withValues(alpha: 0.7),
                                fontFamily: 'monospace',
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline,
                                    size: 64, color: Colors.red[300]),
                                const SizedBox(height: 16),
                                Text(
                                  'Error loading sources',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _error!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.red,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _loadSources,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _buildSourceList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceList() {
    if (_sources == null || _sources!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.source, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No sources available',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This path has no available data sources',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        // "Auto" option (no source preference)
        ListTile(
          leading: const Icon(Icons.auto_awesome),
          title: const Text('Auto (Use Active Source)'),
          subtitle: const Text('Automatically use the active data source'),
          trailing: widget.currentSource == null
              ? Icon(Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary)
              : null,
          selected: widget.currentSource == null,
          onTap: () {
            widget.onSelect(null);
            Navigator.of(context).pop();
          },
        ),
        const Divider(),

        // Available sources
        ..._sources!.entries.map((entry) {
          final sourceId = entry.key;
          final sourceData = entry.value as Map<String, dynamic>;
          final isActive = sourceData['isActive'] == true;
          final value = sourceData['value'];
          final timestamp = sourceData['timestamp'] as String?;

          final isSelected = widget.currentSource == sourceId;

          return ListTile(
            dense: true,
            leading: Icon(
              isSelected ? Icons.check_circle : (isActive ? Icons.star : Icons.circle_outlined),
              color: isSelected ? Theme.of(context).colorScheme.primary : (isActive ? Colors.orange : Colors.grey),
            ),
            title: Text(
              sourceId,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (value != null)
                  Text(
                    'Value: $value',
                    style: const TextStyle(fontSize: 11),
                  ),
                if (timestamp != null)
                  Text(
                    'Updated: ${_formatTimestamp(timestamp)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                  ),
                if (isActive && !isSelected)
                  const Text(
                    'SignalK Default (Auto will use this)',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (isSelected)
                  Text(
                    'SELECTED',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            trailing: isSelected
                ? Icon(Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary)
                : (isActive ? const Icon(Icons.star, color: Colors.orange, size: 20) : null),
            selected: isSelected,
            onTap: () {
              widget.onSelect(sourceId);
              Navigator.of(context).pop();
            },
          );
        }),
      ],
    );
  }

  String _formatTimestamp(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp);
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inSeconds < 60) {
        return '${diff.inSeconds}s ago';
      } else if (diff.inMinutes < 60) {
        return '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        return '${diff.inHours}h ago';
      } else {
        return '${diff.inDays}d ago';
      }
    } catch (e) {
      return timestamp;
    }
  }
}
