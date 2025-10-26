import 'package:flutter/material.dart';
import '../models/tool.dart';

/// Dialog for editing tool metadata
class SaveTemplateDialog extends StatefulWidget {
  final Tool tool;

  const SaveTemplateDialog({
    super.key,
    required this.tool,
  });

  @override
  State<SaveTemplateDialog> createState() => _SaveTemplateDialogState();
}

class _SaveTemplateDialogState extends State<SaveTemplateDialog> {
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

  void _saveTemplate() {
    if (!_formKey.currentState!.validate()) return;

    // Parse tags
    final tags = _tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    // Return metadata for template creation
    final templateData = {
      'name': _nameController.text.trim(),
      'description': _descriptionController.text.trim(),
      'author': _authorController.text.trim(),
      'category': _selectedCategory,
      'tags': tags,
    };

    Navigator.of(context).pop(templateData);
  }

  @override
  Widget build(BuildContext context) {
    // Auto-generate a suggested name from the tool's path
    final suggestedName = _getSuggestedName();
    if (_nameController.text.isEmpty && suggestedName.isNotEmpty) {
      _nameController.text = suggestedName;
    }

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.save,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Edit Tool',
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

            // Form
            Expanded(
              child: SingleChildScrollView(
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
                                'Create a reusable template from this tool configuration',
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
                          labelText: 'Template Name *',
                          hintText: 'e.g., Speed Over Ground Gauge',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a template name';
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
                          hintText: 'Describe what this tool displays',
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
                      const SizedBox(height: 16),

                      // Preview section
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        'Tool Configuration Preview',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _buildConfigPreview(),
                    ],
                  ),
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
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _saveTemplate,
                    icon: const Icon(Icons.save),
                    label: const Text('Save Changes'),
                  ),
                ],
              ),
            ),
          ],
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

  String _getSuggestedName() {
    final dataSources = widget.tool.config.dataSources;
    if (dataSources.isEmpty) return '';

    final firstPath = dataSources.first.path;
    final parts = firstPath.split('.');
    if (parts.isEmpty) return '';

    // Convert camelCase to Title Case
    final lastPart = parts.last;
    final result = lastPart.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)}',
    ).trim();

    return result.isEmpty ? lastPart : result;
  }

  String _categoryLabel(ToolCategory category) {
    return category.name[0].toUpperCase() + category.name.substring(1);
  }
}
