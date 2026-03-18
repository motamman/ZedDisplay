import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/ais_favorites_service.dart';
import '../../services/signalk_service.dart';
import '../../services/historical_data_service.dart';
import '../../utils/chart_axis_utils.dart';

/// Dialog for selecting a SignalK data path
class PathSelectorDialog extends StatefulWidget {
  final SignalKService signalKService;
  final Function(String path) onSelect;
  final bool useHistoricalPaths;
  final bool numericOnly;                // Filter to numeric paths only
  final String? primaryAxisBaseUnit;     // For axis compatibility filtering
  final String? secondaryAxisBaseUnit;   // For axis compatibility filtering
  final bool showBaseUnitInLabel;        // Show base unit in path labels
  final String? requiredCategory;        // Filter to paths in this unit category (e.g., 'angle')
  final bool allowAISContext;            // Show vessel context picker
  final void Function(String path, String? vesselContext)? onSelectWithContext;

  const PathSelectorDialog({
    super.key,
    required this.signalKService,
    required this.onSelect,
    this.useHistoricalPaths = false,
    this.numericOnly = false,
    this.primaryAxisBaseUnit,
    this.secondaryAxisBaseUnit,
    this.showBaseUnitInLabel = false,
    this.requiredCategory,
    this.allowAISContext = false,
    this.onSelectWithContext,
  });

  @override
  State<PathSelectorDialog> createState() => _PathSelectorDialogState();
}

class _PathSelectorDialogState extends State<PathSelectorDialog> {
  List<String> _allPaths = [];
  List<String> _filteredPaths = [];
  Set<String> _pathsWithHistory = {}; // Paths that have historical data
  bool _loading = true;
  String _searchQuery = '';
  String? _selectedCategory;

  // AIS context state
  String? _selectedContext;        // null = self, else vesselId URN
  String _contextSearchQuery = ''; // filter vessels by name/MMSI

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
    if (widget.allowAISContext) {
      widget.signalKService.aisVesselRegistry.addListener(_onRegistryChanged);
      widget.signalKService.fetchAllAISVessels();
    }
    _loadPaths();
  }

  @override
  void dispose() {
    if (widget.allowAISContext) {
      widget.signalKService.aisVesselRegistry.removeListener(_onRegistryChanged);
    }
    super.dispose();
  }

  void _onRegistryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPaths() async {
    setState(() => _loading = true);

    try {
      List<String> paths;

      // AIS context: load paths from the selected vessel
      if (_selectedContext != null) {
        final vessel = widget.signalKService.aisVesselRegistry
            .vessels[_selectedContext];
        if (vessel != null) {
          paths = vessel.availablePathValues.keys.toList();

          // Apply numericOnly filter
          if (widget.numericOnly) {
            paths = paths.where((path) {
              final value = vessel.availablePathValues[path];
              return value is num;
            }).toList();
          }

          // Apply required category filter
          if (widget.requiredCategory != null) {
            final store = widget.signalKService.metadataStore;
            paths = paths.where((path) {
              final unitKey = ChartAxisUtils.getUnitKey(path, store);
              return unitKey == widget.requiredCategory;
            }).toList();
          }

          // Apply axis compatibility filter
          if (widget.primaryAxisBaseUnit != null &&
              widget.secondaryAxisBaseUnit != null) {
            paths = paths.where((path) {
              final unitKey = ChartAxisUtils.getUnitKey(
                path,
                widget.signalKService.metadataStore,
              );
              return ChartAxisUtils.isPathCompatible(
                unitKey,
                widget.primaryAxisBaseUnit,
                widget.secondaryAxisBaseUnit,
              );
            }).toList();
          }
        } else {
          paths = [];
        }
      } else if (widget.useHistoricalPaths || widget.numericOnly) {
        // For historical chart or numericOnly: show only numeric paths from live data
        // but mark which ones have historical data available
        final numericPaths = <String>[];
        for (final entry in widget.signalKService.latestData.entries) {
          final path = entry.key;
          final value = entry.value.value;

          // Skip source-specific paths (contain :: or @)
          if (path.contains('::') || path.contains('@')) continue;

          // Skip AIS vessel paths (stored with context prefix in cache)
          if (path.startsWith('vessels.')) continue;

          // Only include paths with numeric values
          if (value is num) {
            numericPaths.add(path);
          }
        }
        paths = numericPaths;

        // Fetch paths that have historical data (for badge indicator) - only for historical mode
        if (widget.useHistoricalPaths) {
          try {
            final historicalService = HistoricalDataService(
              serverUrl: widget.signalKService.serverUrl,
              useSecureConnection: widget.signalKService.useSecureConnection,
            );
            final historyPaths = await historicalService.getAvailablePaths();
            _pathsWithHistory = historyPaths.toSet();
          } catch (e) {
            debugPrint('Error loading history paths: $e');
          }
        }
      } else {
        // Load all SignalK paths — prefer lightweight catalog if available
        final catalogPaths = widget.signalKService.availablePathsList;
        if (catalogPaths.isNotEmpty) {
          paths = catalogPaths;
        } else {
          // Fallback to full REST tree
          final tree = await widget.signalKService.getAvailablePaths();
          if (tree != null) {
            paths = widget.signalKService.extractPathsFromTree(tree);
          } else {
            paths = [];
          }
        }
      }

      // Filter by axis compatibility if both axes are already defined (self-vessel only)
      if (_selectedContext == null &&
          widget.primaryAxisBaseUnit != null &&
          widget.secondaryAxisBaseUnit != null) {
        debugPrint('🔍 Filtering paths for axis compatibility:');
        debugPrint('   primary=${widget.primaryAxisBaseUnit}, secondary=${widget.secondaryAxisBaseUnit}');
        final beforeCount = paths.length;
        paths = paths.where((path) {
          final unitKey = ChartAxisUtils.getUnitKey(
            path,
            widget.signalKService.metadataStore,
          );
          final compatible = ChartAxisUtils.isPathCompatible(
            unitKey,
            widget.primaryAxisBaseUnit,
            widget.secondaryAxisBaseUnit,
          );
          if (!compatible) {
            debugPrint('   ❌ Filtered out: $path (unitKey=$unitKey)');
          }
          return compatible;
        }).toList();
        debugPrint('   Filtered: $beforeCount → ${paths.length} paths');
      } else if (_selectedContext == null) {
        debugPrint('🔍 No axis filtering (primary=${widget.primaryAxisBaseUnit}, secondary=${widget.secondaryAxisBaseUnit})');
      }

      // Filter by required category (self-vessel only, AIS already filtered above)
      if (_selectedContext == null && widget.requiredCategory != null) {
        final store = widget.signalKService.metadataStore;
        paths = paths.where((path) {
          final unitKey = ChartAxisUtils.getUnitKey(path, store);
          return unitKey == widget.requiredCategory;
        }).toList();
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

  /// Extract bare MMSI from a vessel ID URN.
  String? _extractMMSI(String vesselId) {
    final match = RegExp(r'(\d{9})').firstMatch(vesselId);
    return match?.group(1);
  }

  /// Build a display name for a vessel context.
  String _vesselDisplayName(String? vesselId) {
    if (vesselId == null) {
      final nameData = widget.signalKService.getValue('name');
      final name = nameData?.value is String ? nameData!.value as String : null;
      return name != null ? 'Self ($name)' : 'Self';
    }
    final mmsi = _extractMMSI(vesselId);
    final vessel =
        widget.signalKService.aisVesselRegistry.vessels[vesselId];

    // Check if it's a favorite
    AISFavoritesService? favService;
    try {
      favService = context.read<AISFavoritesService>();
    } catch (_) {
      // Provider not available in this context
    }
    if (mmsi != null && favService != null && favService.isFavorite(mmsi)) {
      final fav = favService.favorites.firstWhere((f) => f.mmsi == mmsi);
      return '⭐ ${fav.name} ($mmsi)';
    }

    if (vessel?.name != null) {
      return mmsi != null ? '${vessel!.name} ($mmsi)' : vessel!.name!;
    }
    return mmsi != null ? 'MMSI $mmsi' : vesselId;
  }

  /// Build the sorted list of vessel context entries for the picker.
  List<String?> _buildVesselList() {
    final vessels = widget.signalKService.aisVesselRegistry.vessels;
    final entries = <String?>[null]; // Self always first

    AISFavoritesService? favService;
    try {
      favService = context.read<AISFavoritesService>();
    } catch (_) {}

    final favMMSIs = favService?.favorites.map((f) => f.mmsi).toSet() ?? {};

    final favorited = <String>[];
    final others = <String>[];

    for (final vesselId in vessels.keys) {
      final mmsi = _extractMMSI(vesselId);
      if (mmsi != null && favMMSIs.contains(mmsi)) {
        favorited.add(vesselId);
      } else {
        others.add(vesselId);
      }
    }

    // Sort favorited by name
    favorited.sort((a, b) {
      final va = vessels[a];
      final vb = vessels[b];
      return (va?.name ?? '').compareTo(vb?.name ?? '');
    });

    // Sort others by name, then MMSI for unnamed
    others.sort((a, b) {
      final va = vessels[a];
      final vb = vessels[b];
      final nameA = va?.name ?? '';
      final nameB = vb?.name ?? '';
      if (nameA.isNotEmpty && nameB.isNotEmpty) return nameA.compareTo(nameB);
      if (nameA.isNotEmpty) return -1;
      if (nameB.isNotEmpty) return 1;
      return (_extractMMSI(a) ?? a).compareTo(_extractMMSI(b) ?? b);
    });

    // Apply context search filter
    final query = _contextSearchQuery.toLowerCase();
    bool matchesQuery(String vesselId) {
      if (query.isEmpty) return true;
      final vessel = vessels[vesselId];
      final name = vessel?.name?.toLowerCase() ?? '';
      final mmsi = _extractMMSI(vesselId) ?? '';
      return name.contains(query) || mmsi.contains(query);
    }

    entries.addAll(favorited.where(matchesQuery));
    entries.addAll(others.where(matchesQuery));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final isAISContext = _selectedContext != null;

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

            // Vessel context picker (only when allowAISContext is true)
            if (widget.allowAISContext)
              _buildContextPicker(context),

            // Helper text for filtered paths
            if (widget.useHistoricalPaths || widget.numericOnly)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.requiredCategory != null
                            ? 'Showing ${widget.requiredCategory} paths'
                            : 'Showing numeric paths',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                      ),
                    ),
                    if (widget.useHistoricalPaths)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history, size: 14, color: Colors.green.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'has history',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
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

            // Category filter chips (hidden for AIS context — too few paths)
            if (!isAISContext)
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
                            final hasHistory = _pathsWithHistory.contains(path);
                            final baseUnit = widget.signalKService.metadataStore.get(path)?.baseUnit;

                            // Build display path with optional base unit
                            final displayPath = (widget.showBaseUnitInLabel && baseUnit != null)
                                ? '$path [$baseUnit]'
                                : path;

                            // Build subtitle: value display
                            Widget? subtitle;
                            if (isAISContext) {
                              final vessel = widget.signalKService
                                  .aisVesselRegistry.vessels[_selectedContext];
                              final rawValue = vessel?.availablePathValues[path];
                              if (rawValue != null && rawValue is num) {
                                final metadata = widget.signalKService.metadataStore.get(path);
                                final formatted = metadata?.format(rawValue.toDouble(), decimals: 2);
                                subtitle = Text(
                                  formatted ?? rawValue.toStringAsFixed(2),
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                );
                              } else if (rawValue != null) {
                                subtitle = Text(
                                  rawValue.toString(),
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                );
                              }
                            } else {
                              final value = widget.signalKService.getConvertedValue(path);
                              final unit = widget.signalKService.getUnitSymbol(path);
                              if (value != null) {
                                subtitle = Text(
                                  '${value.toStringAsFixed(2)}${unit != null ? ' $unit' : ''}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                );
                              }
                            }

                            return ListTile(
                              dense: true,
                              leading: hasHistory
                                  ? Icon(
                                      Icons.history,
                                      size: 18,
                                      color: Colors.green.shade700,
                                    )
                                  : const SizedBox(width: 18),
                              title: Text(
                                displayPath,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              subtitle: subtitle,
                              trailing: const Icon(Icons.arrow_forward,
                                  size: 16),
                              onTap: () {
                                if (widget.onSelectWithContext != null) {
                                  widget.onSelectWithContext!(path, _selectedContext);
                                } else {
                                  widget.onSelect(path);
                                }
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

  /// Builds the vessel context picker as an ExpansionTile.
  Widget _buildContextPicker(BuildContext outerContext) {
    final vesselList = _buildVesselList();

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(
        _selectedContext != null ? Icons.directions_boat : Icons.home,
        size: 20,
      ),
      title: Text(
        _vesselDisplayName(_selectedContext),
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        'Vessel context',
        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
      ),
      children: [
        // Search field for filtering vessels
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Filter by name or MMSI...',
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              border: OutlineInputBorder(),
            ),
            onChanged: (query) {
              setState(() => _contextSearchQuery = query);
            },
          ),
        ),
        // Scrollable vessel list
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: vesselList.length <= 1
              ? const Center(
                  child: Text('No AIS vessels in range',
                      style: TextStyle(fontSize: 11)))
              : RadioGroup<String?>(
                  groupValue: _selectedContext,
                  onChanged: (value) {
                    setState(() {
                      _selectedContext = value;
                      _selectedCategory = null;
                      _searchQuery = '';
                    });
                    _loadPaths();
                  },
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: vesselList.length,
                    itemBuilder: (context, index) {
                      final vesselId = vesselList[index];
                      return RadioListTile<String?>(
                        dense: true,
                        value: vesselId,
                        title: Text(
                          _vesselDisplayName(vesselId),
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
