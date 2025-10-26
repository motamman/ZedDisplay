import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tool.dart';
import '../services/tool_service.dart';
import '../services/signalk_service.dart';

/// Screen for browsing and using tools
class TemplateLibraryScreen extends StatefulWidget {
  const TemplateLibraryScreen({super.key});

  @override
  State<TemplateLibraryScreen> createState() => _TemplateLibraryScreenState();
}

class _TemplateLibraryScreenState extends State<TemplateLibraryScreen> {
  String _searchQuery = '';
  ToolCategory? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tool Library'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search tools...',
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
      body: Consumer<ToolService>(
        builder: (context, toolService, child) {
          if (!toolService.initialized) {
            return const Center(child: CircularProgressIndicator());
          }

          // Get filtered tools
          var tools = _searchQuery.isEmpty
              ? toolService.tools
              : toolService.searchTools(_searchQuery);

          if (_selectedCategory != null) {
            tools = tools
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
                    ...ToolCategory.values.map((category) {
                      final count = toolService
                          .getToolsByCategory(category)
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

              // Tool list
              Expanded(
                child: tools.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.collections_bookmark,
                                size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'No tools available'
                                  : 'No tools found',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Create a tool'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: tools.length,
                        itemBuilder: (context, index) {
                          final tool = tools[index];
                          return _TemplateCard(
                            tool: tool,
                            onTap: () => _showTemplateDetails(tool),
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

  Future<void> _showTemplateDetails(Tool tool) async {
    final result = await showDialog(
      context: context,
      builder: (context) => _TemplateDetailsDialog(tool: tool),
    );

    // If a tool instance was returned, pop the entire screen with it
    if (result != null && mounted) {
      Navigator.of(context).pop(result);
    }
  }
}

/// Card widget for displaying a template in the list
class _TemplateCard extends StatelessWidget {
  final Tool tool;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.tool,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: tool.thumbnailUrl != null
            ? Image.network(
                tool.thumbnailUrl!,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _defaultIcon(),
              )
            : _defaultIcon(),
        title: Text(tool.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tool.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: tool.tags.take(3).map((tag) {
                return Chip(
                  label: Text(tag, style: const TextStyle(fontSize: 10)),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                );
              }).toList(),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (tool.isLocal)
                  const Icon(Icons.computer, size: 16, color: Colors.blue)
                else
                  const Icon(Icons.cloud_download, size: 16, color: Colors.green),
                const SizedBox(height: 4),
                if (tool.ratingCount > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, size: 12, color: Colors.amber),
                      Text(
                        tool.rating.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
              ],
            ),
            // Context menu for local templates
            if (tool.isLocal) ...[
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 18),
                        SizedBox(width: 8),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) async {
                  if (value == 'edit') {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => _EditToolScreen(tool: tool),
                      ),
                    );
                  } else if (value == 'delete') {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete Tool'),
                        content: Text(
                          'Are you sure you want to delete "${tool.name}"? This action cannot be undone.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true && context.mounted) {
                      final toolService = Provider.of<ToolService>(
                        context,
                        listen: false,
                      );
                      await toolService.deleteTool(tool.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Tool "${tool.name}" deleted'),
                          ),
                        );
                      }
                    }
                  }
                },
              ),
            ],
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
  final Tool tool;

  const _TemplateDetailsDialog({required this.tool});

  @override
  Widget build(BuildContext context) {
    final signalKService = Provider.of<SignalKService>(context, listen: false);
    final toolService = Provider.of<ToolService>(context, listen: false);

    // Check compatibility
    final availablePaths = signalKService.latestData.keys.toList();
    final isCompatible = tool.isCompatible(availablePaths);
    final missingPaths = tool.getMissingPaths(availablePaths);

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
                      tool.name,
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
                      tool.description,
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),

                    // Metadata
                    _InfoRow(
                      icon: Icons.person,
                      label: 'Author',
                      value: tool.author,
                    ),
                    _InfoRow(
                      icon: Icons.category,
                      label: 'Category',
                      value: tool.category.name,
                    ),
                    _InfoRow(
                      icon: Icons.update,
                      label: 'Version',
                      value: tool.version,
                    ),
                    const SizedBox(height: 16),

                    // Tags
                    if (tool.tags.isNotEmpty) ...[
                      const Text(
                        'Tags',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: tool.tags.map((tag) {
                          return Chip(label: Text(tag));
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Required paths
                    if (tool.requiredPaths.isNotEmpty) ...[
                      const Text(
                        'Required SignalK Paths',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ...tool.requiredPaths.map((path) {
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
                children: [
                  // Edit and Delete buttons for local templates only
                  if (tool.isLocal) ...[
                    OutlinedButton.icon(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Tool'),
                            content: Text(
                              'Are you sure you want to delete "${tool.name}"? This action cannot be undone.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(true),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );

                        if (confirmed == true && context.mounted) {
                          await toolService.deleteTool(tool.id);
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        }
                      },
                      icon: const Icon(Icons.delete),
                      label: const Text('Delete'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final result = await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => _EditToolScreen(tool: tool),
                          ),
                        );
                        if (result == true && context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit'),
                    ),
                  ],
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: isCompatible
                        ? () {
                            // Return the tool with its saved default size
                            Navigator.of(context).pop({
                              'tool': tool,
                              'width': tool.defaultWidth,
                              'height': tool.defaultHeight,
                            });
                          }
                        : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Use Tool'),
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

/// Screen for editing an existing template
class _EditToolScreen extends StatefulWidget {
  final Tool tool;

  const _EditToolScreen({required this.tool});

  @override
  State<_EditToolScreen> createState() => _EditToolScreenState();
}

class _EditToolScreenState extends State<_EditToolScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _authorController;
  late TextEditingController _tagsController;
  late ToolCategory _selectedCategory;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.tool.name);
    _descriptionController = TextEditingController(text: widget.tool.description);
    _authorController = TextEditingController(text: widget.tool.author);
    _tagsController = TextEditingController(text: widget.tool.tags.join(', '));
    _selectedCategory = widget.tool.category;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _authorController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    final toolService = Provider.of<ToolService>(context, listen: false);

    // Parse tags
    final tags = _tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    // Create updated tool
    final updatedTool = widget.tool.copyWith(
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      author: _authorController.text.trim(),
      category: _selectedCategory,
      tags: tags,
      updatedAt: DateTime.now(),
    );

    try {
      await toolService.saveTool(updatedTool);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Template updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update template: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Tool'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saveChanges,
            tooltip: 'Save changes',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info message
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Edit tool metadata. Data configuration cannot be modified.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Name
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Tool Name *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a tool name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Description
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description *',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a description';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Author
              TextFormField(
                controller: _authorController,
                decoration: const InputDecoration(
                  labelText: 'Author',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // Category
              DropdownButtonFormField<ToolCategory>(
                initialValue: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: ToolCategory.values.map((category) {
                  return DropdownMenuItem(
                    value: category,
                    child: Text(_categoryLabel(category)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedCategory = value);
                  }
                },
              ),
              const SizedBox(height: 16),

              // Tags
              TextFormField(
                controller: _tagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags (comma-separated)',
                  hintText: 'e.g., speed, navigation, gauge',
                  border: OutlineInputBorder(),
                  helperText: 'Separate tags with commas',
                ),
              ),
              const SizedBox(height: 24),

              // Preview section
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'Tool Configuration (Read-only)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _buildConfigPreview(),
              const SizedBox(height: 24),

              // Save button
              ElevatedButton.icon(
                onPressed: _saveChanges,
                icon: const Icon(Icons.save),
                label: const Text('Save Changes'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfigPreview() {
    final config = widget.tool.config;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tool Type: ${widget.tool.toolTypeId}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 8),
          const Text(
            'Data Paths:',
            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          ),
          ...config.dataSources.map((ds) {
            return Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Text(
                '• ${ds.path}${ds.label != null ? " (${ds.label})" : ""}',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            );
          }),
          if (config.style.minValue != null || config.style.maxValue != null) ...[
            const SizedBox(height: 8),
            Text(
              'Range: ${config.style.minValue ?? "auto"} - ${config.style.maxValue ?? "auto"}',
              style: const TextStyle(fontSize: 11),
            ),
          ],
          if (config.style.primaryColor != null) ...[
            const SizedBox(height: 4),
            Text(
              'Color: ${config.style.primaryColor}',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  String _categoryLabel(ToolCategory category) {
    return category.name[0].toUpperCase() + category.name.substring(1);
  }
}
