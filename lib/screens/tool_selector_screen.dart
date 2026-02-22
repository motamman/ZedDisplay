/// Tool Selector Screen for SignalK
/// Visual grid-based tool selection that opens ToolConfigScreen
library;

import 'package:flutter/material.dart';
import '../models/tool_definition.dart' as def;
import '../services/tool_registry.dart';
import 'tool_config_screen.dart';

/// Screen for selecting a tool type to add to the dashboard
class ToolSelectorScreen extends StatefulWidget {
  final String screenId;

  const ToolSelectorScreen({
    super.key,
    required this.screenId,
  });

  @override
  State<ToolSelectorScreen> createState() => _ToolSelectorScreenState();
}

class _ToolSelectorScreenState extends State<ToolSelectorScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  def.ToolCategory? _selectedCategory;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<def.ToolDefinition> _filterDefinitions(List<def.ToolDefinition> definitions) {
    var filtered = definitions;

    // Filter by category
    if (_selectedCategory != null) {
      filtered = filtered.where((d) => d.category == _selectedCategory).toList();
    }

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((d) =>
        d.name.toLowerCase().contains(query) ||
        d.description.toLowerCase().contains(query)
      ).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final toolRegistry = ToolRegistry();
    final definitions = toolRegistry.getAllDefinitions();
    final filtered = _filterDefinitions(definitions);

    // Count per category for chips
    final categoryCounts = <def.ToolCategory, int>{};
    for (final toolDef in definitions) {
      categoryCounts[toolDef.category] = (categoryCounts[toolDef.category] ?? 0) + 1;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Widget'),
      ),
      body: definitions.isEmpty
          ? _buildEmpty(context)
          : Column(
              children: [
                // Search field
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search widgets...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),

                // Category filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      _buildCategoryChip(
                        context,
                        label: 'All',
                        count: definitions.length,
                        isSelected: _selectedCategory == null,
                        color: Theme.of(context).colorScheme.primary,
                        onTap: () => setState(() => _selectedCategory = null),
                      ),
                      ...def.ToolCategory.values.map((category) {
                        final count = categoryCounts[category] ?? 0;
                        if (count == 0) return const SizedBox.shrink();
                        return _buildCategoryChip(
                          context,
                          label: category.displayName,
                          count: count,
                          isSelected: _selectedCategory == category,
                          color: category.color,
                          onTap: () => setState(() => _selectedCategory = category),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Grid of widget cards
                Expanded(
                  child: filtered.isEmpty
                      ? _buildNoResults(context)
                      : GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.85,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            return _WidgetCard(
                              definition: filtered[index],
                              onTap: () => _openToolConfig(context, filtered[index]),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildCategoryChip(
    BuildContext context, {
    required String label,
    required int count,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text('$label ($count)'),
        selected: isSelected,
        onSelected: (_) => onTap(),
        selectedColor: color.withValues(alpha: 0.2),
        checkmarkColor: color,
        labelStyle: TextStyle(
          color: isSelected ? color : null,
          fontWeight: isSelected ? FontWeight.bold : null,
        ),
        side: isSelected
            ? BorderSide(color: color, width: 1.5)
            : BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.widgets_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No widgets available',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Register tools in the ToolRegistry',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No widgets found',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search or category',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  /// Open ToolConfigScreen with pre-selected tool type
  Future<void> _openToolConfig(BuildContext context, def.ToolDefinition definition) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ToolConfigScreen(
          screenId: widget.screenId,
          initialToolTypeId: definition.id,
        ),
      ),
    );

    // Pass result back to dashboard for placement
    if (result != null && mounted && context.mounted) {
      Navigator.of(context).pop(result);
    }
  }
}

/// Card widget for displaying a tool in the grid
class _WidgetCard extends StatelessWidget {
  final def.ToolDefinition definition;
  final VoidCallback onTap;

  const _WidgetCard({
    required this.definition,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = definition.category.color;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Colored header with icon
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.15 : 0.1),
              ),
              child: Icon(
                definition.category.icon,
                size: 32,
                color: color,
              ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name
                    Text(
                      definition.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Description
                    Expanded(
                      child: Text(
                        definition.description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Size badge
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${definition.defaultWidth}x${definition.defaultHeight}',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.add_circle_outline,
                          size: 20,
                          color: color,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
