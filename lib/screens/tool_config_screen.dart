import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../models/tool_config.dart';
import '../models/tool.dart';
import '../services/signalk_service.dart';
import '../services/tool_registry.dart';
import '../services/tool_service.dart';
import '../widgets/config/path_selector.dart';
import '../widgets/config/source_selector.dart';

/// Screen for configuring a tool
class ToolConfigScreen extends StatefulWidget {
  final Tool? existingTool; // null for new tool
  final String screenId;
  final int? existingWidth;
  final int? existingHeight;

  const ToolConfigScreen({
    super.key,
    this.existingTool,
    required this.screenId,
    this.existingWidth,
    this.existingHeight,
  });

  @override
  State<ToolConfigScreen> createState() => _ToolConfigScreenState();
}

class _ToolConfigScreenState extends State<ToolConfigScreen> {
  final _formKey = GlobalKey<FormState>();

  // Configuration state
  String? _selectedToolTypeId;
  List<DataSource> _dataSources = [];

  // Style configuration
  double? _minValue;
  double? _maxValue;
  String? _unit;
  String? _primaryColor;
  double? _fontSize;
  bool _showLabel = true;
  bool _showValue = true;
  bool _showUnit = true;
  int? _ttlSeconds; // Data staleness threshold
  bool _showTickLabels = false;
  bool _pointerOnly = false; // Show only pointer, no filled bar/arc
  int _divisions = 10;
  String _orientation = 'horizontal';
  String _gaugeStyle = 'arc'; // For radial gauge: arc, full, half, threequarter
  String _linearGaugeStyle = 'bar'; // For linear gauge: bar, thermometer, step, bullet
  String _compassStyle = 'classic'; // For compass: classic, arc, minimal, rose
  String _chartStyle = 'area'; // For historical chart: area, line, column, stepLine

  // Chart-specific configuration
  String _chartDuration = '1h';
  int? _chartResolution; // null means auto
  bool _chartShowLegend = true;
  bool _chartShowGrid = true;
  bool _chartAutoRefresh = false;
  int _chartRefreshInterval = 60;

  // Slider-specific configuration
  int _sliderDecimalPlaces = 1;

  // Size configuration
  int _toolWidth = 1;
  int _toolHeight = 1;

  @override
  void initState() {
    super.initState();
    if (widget.existingTool != null) {
      _loadExistingTool();
    }
    // Load existing size if provided
    if (widget.existingWidth != null) {
      _toolWidth = widget.existingWidth!;
    }
    if (widget.existingHeight != null) {
      _toolHeight = widget.existingHeight!;
    }
  }

  void _loadDefaultsForToolType(String toolTypeId) {
    final registry = ToolRegistry();
    final signalKService = Provider.of<SignalKService>(context, listen: false);
    final vesselId = signalKService.serverUrl;

    final defaultConfig = registry.getDefaultConfig(toolTypeId, vesselId);
    if (defaultConfig != null && defaultConfig.dataSources.isNotEmpty) {
      _dataSources = List.from(defaultConfig.dataSources);

      // Also load default style if available
      final style = defaultConfig.style;
      if (style.primaryColor != null) {
        _primaryColor = style.primaryColor;
      }
    }
  }

  void _loadExistingTool() {
    final tool = widget.existingTool!;
    _selectedToolTypeId = tool.toolTypeId;
    _dataSources = List.from(tool.config.dataSources);

    final style = tool.config.style;
    _minValue = style.minValue;
    _maxValue = style.maxValue;
    _unit = style.unit;
    _primaryColor = style.primaryColor;
    _fontSize = style.fontSize;
    _showLabel = style.showLabel ?? true;
    _showValue = style.showValue ?? true;
    _showUnit = style.showUnit ?? true;
    _ttlSeconds = style.ttlSeconds;
    _showTickLabels = style.customProperties?['showTickLabels'] as bool? ?? false;
    _pointerOnly = style.customProperties?['pointerOnly'] as bool? ?? false;
    _divisions = style.customProperties?['divisions'] as int? ?? 10;
    _orientation = style.customProperties?['orientation'] as String? ?? 'horizontal';
    _gaugeStyle = style.customProperties?['gaugeStyle'] as String? ?? 'arc';
    _linearGaugeStyle = style.customProperties?['gaugeStyle'] as String? ?? 'bar';
    _compassStyle = style.customProperties?['compassStyle'] as String? ?? 'classic';
    _chartStyle = style.customProperties?['chartStyle'] as String? ?? 'area';

    // Load chart-specific settings from customProperties
    if (style.customProperties != null) {
      _chartDuration = style.customProperties!['duration'] as String? ?? '1h';
      _chartResolution = style.customProperties!['resolution'] as int?; // null = auto
      _chartShowLegend = style.customProperties!['showLegend'] as bool? ?? true;
      _chartShowGrid = style.customProperties!['showGrid'] as bool? ?? true;
      _chartAutoRefresh = style.customProperties!['autoRefresh'] as bool? ?? false;
      _chartRefreshInterval = style.customProperties!['refreshInterval'] as int? ?? 60;
      _sliderDecimalPlaces = style.customProperties!['decimalPlaces'] as int? ?? 1;
    }

    // Size is managed in placements, not tools
    _toolWidth = 1;
    _toolHeight = 1;
  }

  Future<void> _addDataSource() async {
    final signalKService = Provider.of<SignalKService>(context, listen: false);
    String? selectedPath;
    String? selectedSource;
    String? customLabel;

    // Path selection dialog
    await showDialog(
      context: context,
      builder: (context) => PathSelectorDialog(
        signalKService: signalKService,
        onSelect: (path) {
          selectedPath = path;
        },
      ),
    );

    if (selectedPath == null) return;

    // Source selection dialog (optional)
    if (mounted) {
      await showDialog(
        context: context,
        builder: (context) => SourceSelectorDialog(
          signalKService: signalKService,
          path: selectedPath!,
          currentSource: null,
          onSelect: (source) {
            selectedSource = source;
          },
        ),
      );
    }

    // Label input dialog
    if (mounted) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Custom Label'),
          content: TextField(
            decoration: const InputDecoration(
              labelText: 'Label (optional)',
              helperText: 'Leave empty to auto-generate from path',
            ),
            autofocus: true,
            onChanged: (value) => customLabel = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _dataSources.add(DataSource(
                    path: selectedPath!,
                    source: selectedSource,
                    label: customLabel?.trim().isEmpty == true ? null : customLabel,
                  ));
                });
                Navigator.of(context).pop();
              },
              child: const Text('Add'),
            ),
          ],
        ),
      );
    }
  }

  void _removeDataSource(int index) {
    setState(() {
      _dataSources.removeAt(index);
    });
  }

  void _editDataSource(int index) async {
    final dataSource = _dataSources[index];
    final signalKService = Provider.of<SignalKService>(context, listen: false);

    await showDialog(
      context: context,
      builder: (context) => _EditDataSourceDialog(
        dataSource: dataSource,
        signalKService: signalKService,
        onSave: (newSource, newLabel) {
          setState(() {
            _dataSources[index] = DataSource(
              path: dataSource.path,
              source: newSource,
              label: newLabel?.trim().isEmpty == true ? null : newLabel,
            );
          });
        },
      ),
    );
  }

  bool _canAddMoreDataSources() {
    if (_selectedToolTypeId == null) return false;

    final registry = ToolRegistry();
    final definition = registry.getDefinition(_selectedToolTypeId!);
    if (definition == null) return false;

    final schema = definition.configSchema;
    if (!schema.allowsMultiplePaths) return _dataSources.isEmpty;

    return _dataSources.length < schema.maxPaths;
  }

  String _getDataSourceLimitsText() {
    final registry = ToolRegistry();
    final definition = registry.getDefinition(_selectedToolTypeId!);
    if (definition == null) return '';

    final schema = definition.configSchema;
    if (!schema.allowsMultiplePaths) {
      return '(1 path only)';
    }

    return '(${_dataSources.length}/${schema.maxPaths} paths)';
  }

  Future<void> _selectColor() async {
    // Parse current color or use default
    Color currentColor = Colors.blue;
    if (_primaryColor != null && _primaryColor!.isNotEmpty) {
      try {
        final hexColor = _primaryColor!.replaceAll('#', '');
        currentColor = Color(int.parse('FF$hexColor', radix: 16));
      } catch (e) {
        // Invalid color, use default
      }
    }

    Color? pickedColor;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick a color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: currentColor,
            onColorChanged: (color) {
              pickedColor = color;
            },
            pickerAreaHeightPercent: 0.8,
            enableAlpha: false,
            displayThumbColor: true,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (pickedColor != null) {
                setState(() {
                  _primaryColor = '#${pickedColor!.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
                });
              }
              Navigator.of(context).pop();
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveTool() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedToolTypeId == null || _dataSources.isEmpty) return;

    final toolService = Provider.of<ToolService>(context, listen: false);

    // Create tool config with tool-specific properties
    final Map<String, dynamic>? customProperties;
    if (_selectedToolTypeId == 'historical_chart') {
      customProperties = {
        'duration': _chartDuration,
        'resolution': _chartResolution,
        'showLegend': _chartShowLegend,
        'showGrid': _chartShowGrid,
        'autoRefresh': _chartAutoRefresh,
        'refreshInterval': _chartRefreshInterval,
        'chartStyle': _chartStyle,
      };
    } else if (_selectedToolTypeId == 'slider' || _selectedToolTypeId == 'knob') {
      customProperties = {
        'decimalPlaces': _sliderDecimalPlaces,
      };
    } else {
      // Add gauge-specific properties
      final Map<String, dynamic> baseProperties = {
        'divisions': _divisions,
        'orientation': _orientation,
        'showTickLabels': _showTickLabels,
        'pointerOnly': _pointerOnly,
      };

      // Add style variant based on tool type
      if (_selectedToolTypeId == 'radial_gauge') {
        baseProperties['gaugeStyle'] = _gaugeStyle;
      } else if (_selectedToolTypeId == 'linear_gauge') {
        baseProperties['gaugeStyle'] = _linearGaugeStyle;
      } else if (_selectedToolTypeId == 'compass') {
        baseProperties['compassStyle'] = _compassStyle;
      }

      customProperties = baseProperties;
    }

    final config = ToolConfig(
      dataSources: _dataSources,
      style: StyleConfig(
        minValue: _minValue,
        maxValue: _maxValue,
        unit: _unit?.trim().isEmpty == true ? null : _unit,
        primaryColor: _primaryColor,
        fontSize: _fontSize,
        showLabel: _showLabel,
        showValue: _showValue,
        showUnit: _showUnit,
        ttlSeconds: _ttlSeconds,
        customProperties: customProperties,
      ),
    );

    final Tool tool;

    // Generate name from data sources
    final toolName = _dataSources.length == 1
        ? (_dataSources.first.label ?? _dataSources.first.path.split('.').last)
        : '${_dataSources.length} paths';

    final toolDescription = _dataSources.length == 1
        ? 'Custom tool for ${_dataSources.first.path}'
        : 'Custom tool for ${_dataSources.map((ds) => ds.path).join(', ')}';

    if (widget.existingTool != null) {
      // Update existing tool - preserve ID and metadata
      tool = widget.existingTool!.copyWith(
        toolTypeId: _selectedToolTypeId,
        config: config,
        name: toolName,
        description: toolDescription,
        updatedAt: DateTime.now(),
        tags: [_selectedToolTypeId!],
      );
    } else {
      // Create new tool with metadata
      tool = toolService.createTool(
        toolTypeId: _selectedToolTypeId!,
        config: config,
        name: toolName,
        description: toolDescription,
        author: 'Local User',
        category: ToolCategory.other,
        tags: [_selectedToolTypeId!],
      );
    }

    // Save the tool
    await toolService.saveTool(tool);

    if (mounted) {
      // Return both tool and size
      Navigator.of(context).pop({
        'tool': tool,
        'width': _toolWidth,
        'height': _toolHeight,
      });
    }
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
            onPressed: _selectedToolTypeId != null && _dataSources.isNotEmpty
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
                            setState(() {
                              _selectedToolTypeId = def.id;
                              // Load default paths when tool type is selected (only if no paths configured yet)
                              if (_dataSources.isEmpty && widget.existingTool == null) {
                                _loadDefaultsForToolType(def.id);
                              }
                            });
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '2. Configure Data Sources',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (_selectedToolTypeId != null)
                          Text(
                            _getDataSourceLimitsText(),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // List of data sources
                    if (_dataSources.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('No data sources configured'),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _dataSources.length,
                        itemBuilder: (context, index) {
                          final ds = _dataSources[index];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text('${index + 1}'),
                              ),
                              title: Text(ds.label ?? ds.path.split('.').last),
                              subtitle: Text(ds.path),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _editDataSource(index),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () => _removeDataSource(index),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 16),
                    // Add button
                    if (_canAddMoreDataSources())
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: _addDataSource,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Data Source'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Size Configuration
            if (_selectedToolTypeId != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '3. Configure Size',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Width (columns)'),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: [1, 2, 3, 4, 5, 6, 7, 8].map((width) {
                                    return ChoiceChip(
                                      label: Text('$width'),
                                      selected: _toolWidth == width,
                                      onSelected: (_) {
                                        setState(() => _toolWidth = width);
                                      },
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Height (rows)'),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: [1, 2, 3, 4, 5, 6, 7, 8].map((height) {
                                    return ChoiceChip(
                                      label: Text('$height'),
                                      selected: _toolHeight == height,
                                      onSelected: (_) {
                                        setState(() => _toolHeight = height);
                                      },
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Size: $_toolWidth × $_toolHeight cells',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Chart-specific Configuration
            if (_selectedToolTypeId == 'historical_chart')
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '4. Chart Settings',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Time Duration',
                          border: OutlineInputBorder(),
                        ),
                        value: _chartDuration,
                        items: const [
                          DropdownMenuItem(value: '15m', child: Text('15 minutes')),
                          DropdownMenuItem(value: '30m', child: Text('30 minutes')),
                          DropdownMenuItem(value: '1h', child: Text('1 hour')),
                          DropdownMenuItem(value: '2h', child: Text('2 hours')),
                          DropdownMenuItem(value: '6h', child: Text('6 hours')),
                          DropdownMenuItem(value: '12h', child: Text('12 hours')),
                          DropdownMenuItem(value: '1d', child: Text('1 day')),
                          DropdownMenuItem(value: '2d', child: Text('2 days')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _chartDuration = value);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int?>(
                        decoration: const InputDecoration(
                          labelText: 'Data Resolution',
                          border: OutlineInputBorder(),
                          helperText: 'Auto lets the server optimize for the timeframe',
                        ),
                        value: _chartResolution,
                        items: const [
                          DropdownMenuItem(value: null, child: Text('Auto (Recommended)')),
                          DropdownMenuItem(value: 30000, child: Text('30 seconds')),
                          DropdownMenuItem(value: 60000, child: Text('1 minute')),
                          DropdownMenuItem(value: 300000, child: Text('5 minutes')),
                          DropdownMenuItem(value: 600000, child: Text('10 minutes')),
                        ],
                        onChanged: (value) {
                          setState(() => _chartResolution = value);
                        },
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Show Legend'),
                        value: _chartShowLegend,
                        onChanged: (value) {
                          setState(() => _chartShowLegend = value);
                        },
                      ),
                      SwitchListTile(
                        title: const Text('Show Grid'),
                        value: _chartShowGrid,
                        onChanged: (value) {
                          setState(() => _chartShowGrid = value);
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Chart Style',
                          border: OutlineInputBorder(),
                          helperText: 'Visual style of the chart',
                        ),
                        value: _chartStyle,
                        items: const [
                          DropdownMenuItem(value: 'area', child: Text('Area (filled spline)')),
                          DropdownMenuItem(value: 'line', child: Text('Line (spline only)')),
                          DropdownMenuItem(value: 'column', child: Text('Column (vertical bars)')),
                          DropdownMenuItem(value: 'stepLine', child: Text('Step Line (stepped)')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _chartStyle = value);
                          }
                        },
                      ),
                      const Divider(),
                      SwitchListTile(
                        title: const Text('Auto Refresh'),
                        subtitle: const Text('Automatically reload data'),
                        value: _chartAutoRefresh,
                        onChanged: (value) {
                          setState(() => _chartAutoRefresh = value);
                        },
                      ),
                      if (_chartAutoRefresh)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: DropdownButtonFormField<int>(
                            decoration: const InputDecoration(
                              labelText: 'Refresh Interval',
                              border: OutlineInputBorder(),
                            ),
                            value: _chartRefreshInterval,
                            items: const [
                              DropdownMenuItem(value: 30, child: Text('30 seconds')),
                              DropdownMenuItem(value: 60, child: Text('1 minute')),
                              DropdownMenuItem(value: 120, child: Text('2 minutes')),
                              DropdownMenuItem(value: 300, child: Text('5 minutes')),
                              DropdownMenuItem(value: 600, child: Text('10 minutes')),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _chartRefreshInterval = value);
                              }
                            },
                          ),
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
                        _selectedToolTypeId == 'historical_chart'
                            ? '5. Configure Style'
                            : '4. Configure Style',
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
            if (_selectedToolTypeId != null && _dataSources.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedToolTypeId == 'historical_chart'
                            ? '6. Preview'
                            : '5. Preview',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 200,
                        child: Consumer<SignalKService>(
                          builder: (context, service, child) {
                            // Build preview customProperties same as save
                            final Map<String, dynamic>? previewCustomProperties;
                            if (_selectedToolTypeId == 'historical_chart') {
                              previewCustomProperties = {
                                'duration': _chartDuration,
                                'resolution': _chartResolution,
                                'showLegend': _chartShowLegend,
                                'showGrid': _chartShowGrid,
                                'autoRefresh': _chartAutoRefresh,
                                'refreshInterval': _chartRefreshInterval,
                                'chartStyle': _chartStyle,
                              };
                            } else if (_selectedToolTypeId == 'slider' || _selectedToolTypeId == 'knob') {
                              previewCustomProperties = {
                                'decimalPlaces': _sliderDecimalPlaces,
                              };
                            } else {
                              final Map<String, dynamic> basePreviewProperties = {
                                'divisions': _divisions,
                                'orientation': _orientation,
                                'showTickLabels': _showTickLabels,
                                'pointerOnly': _pointerOnly,
                              };

                              // Add gauge style to preview
                              if (_selectedToolTypeId == 'radial_gauge') {
                                basePreviewProperties['gaugeStyle'] = _gaugeStyle;
                              } else if (_selectedToolTypeId == 'linear_gauge') {
                                basePreviewProperties['gaugeStyle'] = _linearGaugeStyle;
                              } else if (_selectedToolTypeId == 'compass') {
                                basePreviewProperties['compassStyle'] = _compassStyle;
                              }

                              previewCustomProperties = basePreviewProperties;
                            }

                            return registry.buildTool(
                              _selectedToolTypeId!,
                              ToolConfig(
                                dataSources: _dataSources,
                                style: StyleConfig(
                                  minValue: _minValue,
                                  maxValue: _maxValue,
                                  unit: _unit,
                                  primaryColor: _primaryColor,
                                  fontSize: _fontSize,
                                  showLabel: _showLabel,
                                  showValue: _showValue,
                                  showUnit: _showUnit,
                                  ttlSeconds: _ttlSeconds,
                                  customProperties: previewCustomProperties,
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

    // Min/Max Values
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

    // Unit
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
    ]);

    // Color
    widgets.addAll([
      ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _primaryColor != null && _primaryColor!.isNotEmpty
                ? () {
                    try {
                      final hexColor = _primaryColor!.replaceAll('#', '');
                      return Color(int.parse('FF$hexColor', radix: 16));
                    } catch (e) {
                      return Colors.blue;
                    }
                  }()
                : Colors.blue,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade400, width: 2),
          ),
        ),
        title: const Text('Primary Color'),
        subtitle: Text(_primaryColor ?? 'Default (Blue)'),
        trailing: const Icon(Icons.edit),
        onTap: _selectColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      const SizedBox(height: 16),
    ]);

    // Show/Hide Options
    widgets.addAll([
      SwitchListTile(
        title: const Text('Show Label'),
        value: _showLabel,
        onChanged: (value) {
          setState(() => _showLabel = value);
        },
      ),
      SwitchListTile(
        title: const Text('Show Value'),
        value: _showValue,
        onChanged: (value) {
          setState(() => _showValue = value);
        },
      ),
      SwitchListTile(
        title: const Text('Show Unit'),
        value: _showUnit,
        onChanged: (value) {
          setState(() => _showUnit = value);
        },
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<int?>(
        decoration: const InputDecoration(
          labelText: 'Data Staleness Threshold (TTL)',
          border: OutlineInputBorder(),
          helperText: 'Show "--" if data is older than this threshold',
        ),
        value: _ttlSeconds,
        items: const [
          DropdownMenuItem(value: null, child: Text('No check (always show data)')),
          DropdownMenuItem(value: 5, child: Text('5 seconds')),
          DropdownMenuItem(value: 10, child: Text('10 seconds')),
          DropdownMenuItem(value: 30, child: Text('30 seconds')),
          DropdownMenuItem(value: 60, child: Text('1 minute')),
          DropdownMenuItem(value: 120, child: Text('2 minutes')),
          DropdownMenuItem(value: 300, child: Text('5 minutes')),
          DropdownMenuItem(value: 600, child: Text('10 minutes')),
        ],
        onChanged: (value) {
          setState(() => _ttlSeconds = value);
        },
      ),
    ]);

    // Compass-specific options
    if (_selectedToolTypeId == 'compass') {
      widgets.addAll([
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Compass Style',
            border: OutlineInputBorder(),
            helperText: 'Visual style of the compass',
          ),
          value: _compassStyle,
          items: const [
            DropdownMenuItem(value: 'classic', child: Text('Classic (full circle with needle)')),
            DropdownMenuItem(value: 'arc', child: Text('Arc (180° semicircle)')),
            DropdownMenuItem(value: 'minimal', child: Text('Minimal (clean modern)')),
            DropdownMenuItem(value: 'rose', child: Text('Rose (traditional compass rose)')),
            DropdownMenuItem(value: 'marine', child: Text('Marine (rotating card, fixed needle)')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _compassStyle = value);
            }
          },
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Show Tick Labels'),
          subtitle: const Text('Display degree values'),
          value: _showTickLabels,
          onChanged: (value) {
            setState(() => _showTickLabels = value);
          },
        ),
      ]);
    }

    // Radial gauge-specific options
    if (_selectedToolTypeId == 'radial_gauge') {
      widgets.addAll([
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Gauge Style',
            border: OutlineInputBorder(),
            helperText: 'Visual style of the gauge',
          ),
          value: _gaugeStyle,
          items: const [
            DropdownMenuItem(value: 'arc', child: Text('Arc (270° default)')),
            DropdownMenuItem(value: 'full', child: Text('Full Circle (360° with needle)')),
            DropdownMenuItem(value: 'half', child: Text('Half Circle (180° semicircle)')),
            DropdownMenuItem(value: 'threequarter', child: Text('Three Quarter (270° from bottom)')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _gaugeStyle = value);
            }
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          decoration: const InputDecoration(
            labelText: 'Divisions (tick marks)',
            border: OutlineInputBorder(),
            helperText: 'Number of major divisions on the gauge',
          ),
          keyboardType: TextInputType.number,
          initialValue: _divisions.toString(),
          onChanged: (value) {
            final parsed = int.tryParse(value);
            if (parsed != null && parsed > 0) {
              setState(() => _divisions = parsed);
            }
          },
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Show Tick Labels'),
          subtitle: const Text('Display numeric values at tick marks'),
          value: _showTickLabels,
          onChanged: (value) {
            setState(() => _showTickLabels = value);
          },
        ),
        SwitchListTile(
          title: const Text('Pointer Only Mode'),
          subtitle: const Text('Show needle pointer without filled arc'),
          value: _pointerOnly,
          onChanged: (value) {
            setState(() => _pointerOnly = value);
          },
        ),
      ]);
    }

    // Linear gauge orientation
    if (_selectedToolTypeId == 'linear_gauge') {
      widgets.addAll([
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Gauge Style',
            border: OutlineInputBorder(),
            helperText: 'Visual style of the linear gauge',
          ),
          value: _linearGaugeStyle,
          items: const [
            DropdownMenuItem(value: 'bar', child: Text('Bar (filled bar)')),
            DropdownMenuItem(value: 'thermometer', child: Text('Thermometer (rounded top)')),
            DropdownMenuItem(value: 'step', child: Text('Step (segmented levels)')),
            DropdownMenuItem(value: 'bullet', child: Text('Bullet Chart (thin bar with marker)')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _linearGaugeStyle = value);
            }
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Orientation',
            border: OutlineInputBorder(),
          ),
          value: _orientation,
          items: const [
            DropdownMenuItem(value: 'horizontal', child: Text('Horizontal')),
            DropdownMenuItem(value: 'vertical', child: Text('Vertical')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _orientation = value);
            }
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          decoration: const InputDecoration(
            labelText: 'Divisions (tick marks)',
            border: OutlineInputBorder(),
            helperText: 'Number of major divisions on the gauge',
          ),
          keyboardType: TextInputType.number,
          initialValue: _divisions.toString(),
          onChanged: (value) {
            final parsed = int.tryParse(value);
            if (parsed != null && parsed > 0) {
              setState(() => _divisions = parsed);
            }
          },
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Show Tick Labels'),
          subtitle: const Text('Display numeric values at tick marks'),
          value: _showTickLabels,
          onChanged: (value) {
            setState(() => _showTickLabels = value);
          },
        ),
        SwitchListTile(
          title: const Text('Pointer Only Mode'),
          subtitle: const Text('Show triangle pointer without filled bar'),
          value: _pointerOnly,
          onChanged: (value) {
            setState(() => _pointerOnly = value);
          },
        ),
      ]);
    }

    // Slider and Knob-specific options
    if (_selectedToolTypeId == 'slider' || _selectedToolTypeId == 'knob') {
      widgets.addAll([
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          decoration: const InputDecoration(
            labelText: 'Decimal Places',
            border: OutlineInputBorder(),
            helperText: 'Number of decimal places to display',
          ),
          value: _sliderDecimalPlaces,
          items: const [
            DropdownMenuItem(value: 0, child: Text('0 (e.g., 42)')),
            DropdownMenuItem(value: 1, child: Text('1 (e.g., 42.5)')),
            DropdownMenuItem(value: 2, child: Text('2 (e.g., 42.50)')),
            DropdownMenuItem(value: 3, child: Text('3 (e.g., 42.500)')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _sliderDecimalPlaces = value);
            }
          },
        ),
      ]);
    }

    return widgets;
  }
}

/// Stateful dialog for editing a data source
class _EditDataSourceDialog extends StatefulWidget {
  final DataSource dataSource;
  final SignalKService signalKService;
  final Function(String?, String?) onSave;

  const _EditDataSourceDialog({
    required this.dataSource,
    required this.signalKService,
    required this.onSave,
  });

  @override
  State<_EditDataSourceDialog> createState() => _EditDataSourceDialogState();
}

class _EditDataSourceDialogState extends State<_EditDataSourceDialog> {
  late String? _newSource;
  late String? _newLabel;

  @override
  void initState() {
    super.initState();
    _newSource = widget.dataSource.source;
    _newLabel = widget.dataSource.label;
  }

  Future<void> _selectSource() async {
    await showDialog(
      context: context,
      builder: (context) => SourceSelectorDialog(
        signalKService: widget.signalKService,
        path: widget.dataSource.path,
        currentSource: _newSource,
        onSelect: (source) {
          setState(() {
            _newSource = source;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.dataSource.path}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Source selection
          ListTile(
            leading: const Icon(Icons.sensors),
            title: const Text('Data Source'),
            subtitle: Text(_newSource ?? 'Auto'),
            trailing: const Icon(Icons.edit),
            onTap: _selectSource,
          ),
          const SizedBox(height: 8),
          // Label input
          TextField(
            decoration: const InputDecoration(
              labelText: 'Custom Label',
              border: OutlineInputBorder(),
            ),
            controller: TextEditingController(text: _newLabel),
            onChanged: (value) => _newLabel = value,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            widget.onSave(_newSource, _newLabel);
            Navigator.of(context).pop();
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
