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
  String? _selectedPath;
  String? _selectedSource;
  String? _customLabel;

  // Style configuration
  double? _minValue;
  double? _maxValue;
  String? _unit;
  String? _primaryColor;
  double? _fontSize;
  bool _showLabel = true;
  bool _showValue = true;
  bool _showUnit = true;
  bool _showTickLabels = false;
  int _divisions = 10;
  String _orientation = 'horizontal';

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
    _showLabel = style.showLabel ?? true;
    _showValue = style.showValue ?? true;
    _showUnit = style.showUnit ?? true;
    _showTickLabels = style.customProperties?['showTickLabels'] as bool? ?? false;
    _divisions = style.customProperties?['divisions'] as int? ?? 10;
    _orientation = style.customProperties?['orientation'] as String? ?? 'horizontal';

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
                  _primaryColor = '#${pickedColor!.value.toRadixString(16).substring(2).toUpperCase()}';
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
    if (_selectedToolTypeId == null || _selectedPath == null) return;

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
      };
    } else if (_selectedToolTypeId == 'slider' || _selectedToolTypeId == 'knob') {
      customProperties = {
        'decimalPlaces': _sliderDecimalPlaces,
      };
    } else {
      // Add gauge-specific properties
      customProperties = {
        'divisions': _divisions,
        'orientation': _orientation,
        'showTickLabels': _showTickLabels,
      };
    }

    final config = ToolConfig(
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
        showLabel: _showLabel,
        showValue: _showValue,
        showUnit: _showUnit,
        customProperties: customProperties,
      ),
    );

    final Tool tool;

    if (widget.existingTool != null) {
      // Update existing tool - preserve ID and metadata
      tool = widget.existingTool!.copyWith(
        toolTypeId: _selectedToolTypeId,
        config: config,
        name: _customLabel ?? _selectedPath!.split('.').last,
        description: 'Custom tool for $_selectedPath',
        updatedAt: DateTime.now(),
        tags: [_selectedToolTypeId!],
      );
    } else {
      // Create new tool with metadata
      tool = toolService.createTool(
        toolTypeId: _selectedToolTypeId!,
        config: config,
        name: _customLabel ?? _selectedPath!.split('.').last,
        description: 'Custom tool for $_selectedPath',
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
            if (_selectedToolTypeId != null && _selectedPath != null)
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
                              };
                            } else if (_selectedToolTypeId == 'slider' || _selectedToolTypeId == 'knob') {
                              previewCustomProperties = {
                                'decimalPlaces': _sliderDecimalPlaces,
                              };
                            } else {
                              previewCustomProperties = {
                                'divisions': _divisions,
                                'orientation': _orientation,
                                'showTickLabels': _showTickLabels,
                              };
                            }

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
                                  showLabel: _showLabel,
                                  showValue: _showValue,
                                  showUnit: _showUnit,
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
    ]);

    // Gauge-specific options
    if (_selectedToolTypeId == 'radial_gauge' || _selectedToolTypeId == 'compass_gauge') {
      widgets.addAll([
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
      ]);
    }

    // Linear gauge orientation
    if (_selectedToolTypeId == 'linear_gauge') {
      widgets.addAll([
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
