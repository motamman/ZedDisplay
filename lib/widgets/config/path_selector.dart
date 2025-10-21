import 'package:flutter/material.dart';
import '../../services/signalk_service.dart';
import '../../services/historical_data_service.dart';

/// Dialog for selecting a SignalK data path
class PathSelectorDialog extends StatefulWidget {
  final SignalKService signalKService;
  final Function(String path) onSelect;
  final bool useHistoricalPaths;

  const PathSelectorDialog({
    super.key,
    required this.signalKService,
    required this.onSelect,
    this.useHistoricalPaths = false,
  });

  @override
  State<PathSelectorDialog> createState() => _PathSelectorDialogState();
}

class _PathSelectorDialogState extends State<PathSelectorDialog> {
  List<String> _allPaths = [];
  List<String> _filteredPaths = [];
  bool _loading = true;
  String _searchQuery = '';
  String? _selectedCategory;

  final Map<String, List<String>> _categorizedPaths = {};
  final List<String> _categories = [
    'navigation',
    'environment',
    'electrical',
    'propulsion',
    'steering',
    'tanks',
    'performance',
  ];

  @override
  void initState() {
    super.initState();
    _loadPaths();
  }

  Future<void> _loadPaths() async {
    setState(() => _loading = true);

    try {
      List<String> paths;

      if (widget.useHistoricalPaths) {
        // Load paths that have historical data
        final historicalService = HistoricalDataService(
          serverUrl: widget.signalKService.serverUrl,
          useSecureConnection: widget.signalKService.useSecureConnection,
        );
        paths = await historicalService.getAvailablePaths();
      } else {
        // Load all SignalK paths
        final tree = await widget.signalKService.getAvailablePaths();
        if (tree != null) {
          paths = widget.signalKService.extractPathsFromTree(tree);
        } else {
          paths = [];
        }
      }

      setState(() {
        _allPaths = paths..sort();
        _filteredPaths = _allPaths;
        _categorizePaths();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _categorizePaths() {
    _categorizedPaths.clear();
    for (final category in _categories) {
      _categorizedPaths[category] = _allPaths
          .where((path) => path.startsWith('$category.'))
          .toList();
    }
    // Add "other" category for paths that don't match known categories
    _categorizedPaths['other'] = _allPaths
        .where((path) => !_categories.any((cat) => path.startsWith('$cat.')))
        .toList();
  }

  void _filterPaths(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty && _selectedCategory == null) {
        _filteredPaths = _allPaths;
      } else {
        _filteredPaths = _allPaths.where((path) {
          final matchesSearch = query.isEmpty ||
              path.toLowerCase().contains(query.toLowerCase());
          final matchesCategory = _selectedCategory == null ||
              path.startsWith('$_selectedCategory.');
          return matchesSearch && matchesCategory;
        }).toList();
      }
    });
  }

  void _selectCategory(String? category) {
    setState(() {
      _selectedCategory = category;
      _filterPaths(_searchQuery);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.route,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.useHistoricalPaths
                        ? 'Select Historical Data Path'
                        : 'Select Data Path',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Helper text for historical paths
            if (widget.useHistoricalPaths)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Only showing paths with recorded historical data',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                ),
              ),

            // Search bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search paths...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: _filterPaths,
              ),
            ),

            // Category filter chips
            SizedBox(
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: _selectedCategory == null,
                    onSelected: (_) => _selectCategory(null),
                  ),
                  const SizedBox(width: 8),
                  ..._categories.map((category) {
                    final count = _categorizedPaths[category]?.length ?? 0;
                    if (count == 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text('$category ($count)'),
                        selected: _selectedCategory == category,
                        onSelected: (_) => _selectCategory(category),
                      ),
                    );
                  }),
                ],
              ),
            ),

            const Divider(height: 1),

            // Path list
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredPaths.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off,
                                  size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'No paths found',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (!widget.signalKService.isConnected)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Not connected to SignalK server',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredPaths.length,
                          itemBuilder: (context, index) {
                            final path = _filteredPaths[index];
                            final value =
                                widget.signalKService.getConvertedValue(path);
                            final unit =
                                widget.signalKService.getUnitSymbol(path);

                            return ListTile(
                              dense: true,
                              title: Text(
                                path,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              subtitle: value != null
                                  ? Text(
                                      '${value.toStringAsFixed(2)}${unit != null ? ' $unit' : ''}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                      ),
                                    )
                                  : null,
                              trailing: const Icon(Icons.arrow_forward,
                                  size: 16),
                              onTap: () {
                                widget.onSelect(path);
                                Navigator.of(context).pop();
                              },
                            );
                          },
                        ),
            ),

            // Footer with path count
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_filteredPaths.length} paths available',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (_loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
