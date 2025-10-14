import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/template.dart';
import '../services/template_service.dart';
import '../services/signalk_service.dart';

/// Screen for browsing and applying tool templates
class TemplateLibraryScreen extends StatefulWidget {
  const TemplateLibraryScreen({super.key});

  @override
  State<TemplateLibraryScreen> createState() => _TemplateLibraryScreenState();
}

class _TemplateLibraryScreenState extends State<TemplateLibraryScreen> {
  String _searchQuery = '';
  TemplateCategory? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Template Library'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search templates...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                filled: true,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),
        ),
      ),
      body: Consumer<TemplateService>(
        builder: (context, templateService, child) {
          if (!templateService.initialized) {
            return const Center(child: CircularProgressIndicator());
          }

          // Get filtered templates
          var templates = _searchQuery.isEmpty
              ? templateService.templates
              : templateService.searchTemplates(_searchQuery);

          if (_selectedCategory != null) {
            templates = templates
                .where((t) => t.category == _selectedCategory)
                .toList();
          }

          return Column(
            children: [
              // Category filter chips
              SizedBox(
                height: 50,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    FilterChip(
                      label: const Text('All'),
                      selected: _selectedCategory == null,
                      onSelected: (_) {
                        setState(() => _selectedCategory = null);
                      },
                    ),
                    const SizedBox(width: 8),
                    ...TemplateCategory.values.map((category) {
                      final count = templateService
                          .getTemplatesByCategory(category)
                          .length;
                      if (count == 0) return const SizedBox.shrink();

                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text('${category.name} ($count)'),
                          selected: _selectedCategory == category,
                          onSelected: (_) {
                            setState(() => _selectedCategory = category);
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Template list
              Expanded(
                child: templates.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.collections_bookmark,
                                size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'No templates available'
                                  : 'No templates found',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () {
                                // TODO: Navigate to template creation or import
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Create your first template'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: templates.length,
                        itemBuilder: (context, index) {
                          final template = templates[index];
                          return _TemplateCard(
                            template: template,
                            onTap: () => _showTemplateDetails(template),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showTemplateDetails(Template template) async {
    final result = await showDialog(
      context: context,
      builder: (context) => _TemplateDetailsDialog(template: template),
    );

    // If a tool instance was returned, pop the entire screen with it
    if (result != null && mounted) {
      Navigator.of(context).pop(result);
    }
  }
}

/// Card widget for displaying a template in the list
class _TemplateCard extends StatelessWidget {
  final Template template;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.template,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: template.thumbnailUrl != null
            ? Image.network(
                template.thumbnailUrl!,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _defaultIcon(),
              )
            : _defaultIcon(),
        title: Text(template.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              template.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: template.tags.take(3).map((tag) {
                return Chip(
                  label: Text(tag, style: const TextStyle(fontSize: 10)),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                );
              }).toList(),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (template.isLocal)
              const Icon(Icons.computer, size: 16, color: Colors.blue)
            else
              const Icon(Icons.cloud_download, size: 16, color: Colors.green),
            const SizedBox(height: 4),
            if (template.ratingCount > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, size: 12, color: Colors.amber),
                  Text(
                    template.rating.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
          ],
        ),
        isThreeLine: true,
        onTap: onTap,
      ),
    );
  }

  Widget _defaultIcon() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.dashboard_customize, color: Colors.blue),
    );
  }
}

/// Dialog showing template details and apply button
class _TemplateDetailsDialog extends StatelessWidget {
  final Template template;

  const _TemplateDetailsDialog({required this.template});

  @override
  Widget build(BuildContext context) {
    final signalKService = Provider.of<SignalKService>(context, listen: false);
    final templateService = Provider.of<TemplateService>(context, listen: false);

    // Check compatibility
    final availablePaths = signalKService.latestData.keys.toList();
    final isCompatible = template.isCompatible(availablePaths);
    final missingPaths = template.getMissingPaths(availablePaths);

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.dashboard_customize,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      template.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Description
                    Text(
                      template.description,
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),

                    // Metadata
                    _InfoRow(
                      icon: Icons.person,
                      label: 'Author',
                      value: template.author,
                    ),
                    _InfoRow(
                      icon: Icons.category,
                      label: 'Category',
                      value: template.category.name,
                    ),
                    _InfoRow(
                      icon: Icons.update,
                      label: 'Version',
                      value: template.version,
                    ),
                    const SizedBox(height: 16),

                    // Tags
                    if (template.tags.isNotEmpty) ...[
                      const Text(
                        'Tags',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: template.tags.map((tag) {
                          return Chip(label: Text(tag));
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Required paths
                    if (template.requiredPaths.isNotEmpty) ...[
                      const Text(
                        'Required SignalK Paths',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ...template.requiredPaths.map((path) {
                        final available = availablePaths.contains(path);
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            available ? Icons.check_circle : Icons.cancel,
                            color: available ? Colors.green : Colors.red,
                            size: 16,
                          ),
                          title: Text(
                            path,
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 16),
                    ],

                    // Compatibility warning
                    if (!isCompatible) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.warning, color: Colors.orange),
                                SizedBox(width: 8),
                                Text(
                                  'Compatibility Warning',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'This template requires ${missingPaths.length} path(s) '
                              'that are not currently available in your SignalK data.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (!template.isLocal)
                    OutlinedButton.icon(
                      onPressed: () async {
                        // TODO: Delete template
                        await templateService.deleteTemplate(template.id);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                      icon: const Icon(Icons.delete),
                      label: const Text('Delete'),
                    )
                  else
                    const SizedBox.shrink(),
                  ElevatedButton.icon(
                    onPressed: isCompatible
                        ? () {
                            // Apply template
                            final toolInstance = templateService.applyTemplate(
                              template: template,
                              screenId: 'main',
                            );
                            Navigator.of(context).pop(toolInstance);
                          }
                        : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Apply Template'),
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

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(value),
        ],
      ),
    );
  }
}
