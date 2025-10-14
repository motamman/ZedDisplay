import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tool_config.dart';
import '../models/tool_instance.dart';
import '../services/signalk_service.dart';
import '../services/tool_registry.dart';
import '../widgets/config/path_selector.dart';
import '../widgets/config/source_selector.dart';

/// Screen for configuring a tool instance
class ToolConfigScreen extends StatefulWidget {
  final ToolInstance? existingTool; // null for new tool
  final String screenId;

  const ToolConfigScreen({
    super.key,
    this.existingTool,
    required this.screenId,
  });

  @override
  State<ToolConfigScreen> createState() => _ToolConfigScreenState();
}

class _ToolConfigScreenState extends State<ToolConfigScreen> {
  final _formKey = GlobalKey<FormState>();

  // Configuration state
  String? _selectedToolTypeId;
  String? _selectedPath;
  String? _selectedSource;
  String? _customLabel;

  // Style configuration
  double? _minValue;
  double? _maxValue;
  String? _unit;
  String? _primaryColor;
  double? _fontSize;

  @override
  void initState() {
    super.initState();
    if (widget.existingTool != null) {
      _loadExistingTool();
    }
  }

  void _loadExistingTool() {
    final tool = widget.existingTool!;
    _selectedToolTypeId = tool.toolTypeId;

    if (tool.config.dataSources.isNotEmpty) {
      final dataSource = tool.config.dataSources.first;
      _selectedPath = dataSource.path;
      _selectedSource = dataSource.source;
      _customLabel = dataSource.label;
    }

    final style = tool.config.style;
    _minValue = style.minValue;
    _maxValue = style.maxValue;
    _unit = style.unit;
    _primaryColor = style.primaryColor;
    _fontSize = style.fontSize;
  }

  Future<void> _selectPath() async {
    final signalKService = Provider.of<SignalKService>(context, listen: false);

    await showDialog(
      context: context,
      builder: (context) => PathSelectorDialog(
        signalKService: signalKService,
        onSelect: (path) {
          setState(() {
            _selectedPath = path;
            _selectedSource = null; // Reset source when path changes
          });
        },
      ),
    );
  }

  Future<void> _selectSource() async {
    if (_selectedPath == null) return;

    final signalKService = Provider.of<SignalKService>(context, listen: false);

    await showDialog(
      context: context,
      builder: (context) => SourceSelectorDialog(
        signalKService: signalKService,
        path: _selectedPath!,
        currentSource: _selectedSource,
        onSelect: (source) {
          setState(() => _selectedSource = source);
        },
      ),
    );
  }

  void _saveTool() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedToolTypeId == null || _selectedPath == null) return;

    final toolInstance = ToolInstance(
      id: widget.existingTool?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      toolTypeId: _selectedToolTypeId!,
      screenId: widget.screenId,
      position: widget.existingTool?.position ?? GridPosition(row: 0, col: 0),
      config: ToolConfig(
        dataSources: [
          DataSource(
            path: _selectedPath!,
            source: _selectedSource,
            label: _customLabel?.trim().isEmpty == true ? null : _customLabel,
          ),
        ],
        style: StyleConfig(
          minValue: _minValue,
          maxValue: _maxValue,
          unit: _unit?.trim().isEmpty == true ? null : _unit,
          primaryColor: _primaryColor,
          fontSize: _fontSize,
        ),
      ),
    );

    Navigator.of(context).pop(toolInstance);
  }

  @override
  Widget build(BuildContext context) {
    final registry = ToolRegistry();
    final toolDefinitions = registry.getAllDefinitions();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingTool == null ? 'Add Tool' : 'Edit Tool'),
        actions: [
          TextButton.icon(
            onPressed: _selectedToolTypeId != null && _selectedPath != null
                ? _saveTool
                : null,
            icon: const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Tool Type Selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '1. Select Tool Type',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: toolDefinitions.map((def) {
                        final isSelected = _selectedToolTypeId == def.id;
                        return ChoiceChip(
                          label: Text(def.name),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() => _selectedToolTypeId = def.id);
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Data Source Configuration
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '2. Configure Data Source',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.route),
                      title: const Text('Data Path'),
                      subtitle: Text(_selectedPath ?? 'Not selected'),
                      trailing: const Icon(Icons.edit),
                      onTap: _selectPath,
                    ),
                    if (_selectedPath != null)
                      ListTile(
                        leading: const Icon(Icons.sensors),
                        title: const Text('Data Source'),
                        subtitle: Text(_selectedSource ?? 'Auto'),
                        trailing: const Icon(Icons.edit),
                        onTap: _selectSource,
                      ),
                    const SizedBox(height: 8),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Custom Label (optional)',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: _customLabel,
                      onChanged: (value) => _customLabel = value,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Style Configuration
            if (_selectedToolTypeId != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '3. Configure Style',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      ..._buildStyleOptions(),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Preview
            if (_selectedToolTypeId != null && _selectedPath != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '4. Preview',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 200,
                        child: Consumer<SignalKService>(
                          builder: (context, service, child) {
                            return registry.buildTool(
                              _selectedToolTypeId!,
                              ToolConfig(
                                dataSources: [
                                  DataSource(
                                    path: _selectedPath!,
                                    source: _selectedSource,
                                    label: _customLabel,
                                  ),
                                ],
                                style: StyleConfig(
                                  minValue: _minValue,
                                  maxValue: _maxValue,
                                  unit: _unit,
                                  primaryColor: _primaryColor,
                                  fontSize: _fontSize,
                                ),
                              ),
                              service,
                            );
                          },
                        ),
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

  List<Widget> _buildStyleOptions() {
    final registry = ToolRegistry();
    final definition = registry.getDefinition(_selectedToolTypeId!);
    if (definition == null) return [];

    final schema = definition.configSchema;
    final widgets = <Widget>[];

    if (schema.allowsMinMax) {
      widgets.addAll([
        Row(
          children: [
            Expanded(
              child: TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Min Value',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                initialValue: _minValue?.toString(),
                onChanged: (value) =>
                    _minValue = double.tryParse(value),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Max Value',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                initialValue: _maxValue?.toString(),
                onChanged: (value) =>
                    _maxValue = double.tryParse(value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ]);
    }

    widgets.addAll([
      TextFormField(
        decoration: const InputDecoration(
          labelText: 'Unit (optional)',
          border: OutlineInputBorder(),
        ),
        initialValue: _unit,
        onChanged: (value) => _unit = value,
      ),
      const SizedBox(height: 16),
      TextFormField(
        decoration: const InputDecoration(
          labelText: 'Color (hex, e.g. #0000FF)',
          border: OutlineInputBorder(),
        ),
        initialValue: _primaryColor,
        onChanged: (value) => _primaryColor = value,
      ),
    ]);

    return widgets;
  }
}
