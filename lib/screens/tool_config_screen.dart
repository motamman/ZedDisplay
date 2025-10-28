import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:http/http.dart' as http;
import '../models/tool_config.dart';
import '../models/tool.dart';
import '../models/tool_definition.dart' as def;
import '../services/signalk_service.dart';
import '../services/tool_registry.dart';
import '../services/tool_service.dart';
import '../widgets/config/path_selector.dart';
import '../widgets/config/configure_data_source_dialog.dart';
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
  String? _selectedCategory; // Filter by category
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
  bool _chartShowMovingAverage = false;
  int _chartMovingAverageWindow = 5;

  // Polar chart-specific configuration
  int _polarHistorySeconds = 60;

  // AIS polar chart-specific configuration
  double _aisMaxRangeNm = 5.0;
  int _aisUpdateInterval = 10;

  // Slider-specific configuration
  int _sliderDecimalPlaces = 1;

  // Dropdown-specific configuration
  double _dropdownStepSize = 10.0;

  // Wind compass-specific configuration
  double _laylineAngle = 40.0;       // Target AWA angle in degrees
  double _targetTolerance = 3.0;     // Acceptable deviation from target in degrees
  bool _showAWANumbers = true;       // Show numeric AWA display
  bool _enableVMG = false;           // Enable VMG optimization with polar data

  // Autopilot-specific configuration
  bool _headingTrue = false;         // Use true vs magnetic heading
  bool _invertRudder = false;        // Invert rudder angle display
  int _fadeDelaySeconds = 5;         // Seconds before controls fade

  // WebView-specific configuration
  String _webViewUrl = '';
  List<Map<String, String>> _signalKWebApps = [];
  bool _loadingWebApps = false;

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

  /// Reset all form fields to default values
  void _resetFormFields() {
    _dataSources = [];
    _minValue = null;
    _maxValue = null;
    _unit = null;
    _primaryColor = null;
    _fontSize = null;
    _showLabel = true;
    _showValue = true;
    _showUnit = true;
    _ttlSeconds = null;
    _showTickLabels = false;
    _pointerOnly = false;
    _divisions = 10;
    _orientation = 'horizontal';
    _gaugeStyle = 'arc';
    _linearGaugeStyle = 'bar';
    _compassStyle = 'classic';
    _chartStyle = 'area';
    _chartDuration = '1h';
    _chartResolution = null;
    _chartShowLegend = true;
    _chartShowGrid = true;
    _chartAutoRefresh = false;
    _chartRefreshInterval = 60;
    _chartShowMovingAverage = false;
    _chartMovingAverageWindow = 5;
    _polarHistorySeconds = 60;
    _aisMaxRangeNm = 5.0;
    _aisUpdateInterval = 10;
    _sliderDecimalPlaces = 1;
    _dropdownStepSize = 10.0;
    _laylineAngle = 40.0;
    _targetTolerance = 3.0;
    _showAWANumbers = true;
    _enableVMG = false;
    _headingTrue = false;
    _invertRudder = false;
    _fadeDelaySeconds = 5;
    _webViewUrl = '';
    _signalKWebApps = [];
    _loadingWebApps = false;
    _toolWidth = 1;
    _toolHeight = 1;
  }

  void _loadDefaultsForToolType(String toolTypeId) {
    final registry = ToolRegistry();
    final signalKService = Provider.of<SignalKService>(context, listen: false);
    final vesselId = signalKService.serverUrl;

    // Special handling for conversion_test - add default paths
    if (toolTypeId == 'conversion_test') {
      _dataSources = [
        DataSource(path: 'navigation.position'),
        DataSource(path: 'navigation.headingTrue'),
        DataSource(path: 'navigation.headingMagnetic'),
        DataSource(path: 'environment.wind.directionTrue'),
        DataSource(path: 'environment.wind.angleApparent'),
        DataSource(path: 'environment.wind.speedTrue'),
        DataSource(path: 'environment.wind.speedApparent'),
        DataSource(path: 'navigation.speedOverGround'),
        DataSource(path: 'navigation.courseOverGroundTrue'),
        DataSource(path: 'navigation.courseGreatCircle.nextPoint.bearingTrue'),
        DataSource(path: 'navigation.courseGreatCircle.nextPoint.distance'),
      ];
    } else if (toolTypeId == 'rpi_monitor') {
      // Special handling for rpi_monitor - add default paths
      _dataSources = [
        DataSource(path: 'environment.rpi.cpu.utilisation', label: 'CPU Overall'),
        DataSource(path: 'environment.rpi.cpu.core.1.utilisation', label: 'CPU Core 1'),
        DataSource(path: 'environment.rpi.cpu.core.2.utilisation', label: 'CPU Core 2'),
        DataSource(path: 'environment.rpi.cpu.core.3.utilisation', label: 'CPU Core 3'),
        DataSource(path: 'environment.rpi.cpu.core.4.utilisation', label: 'CPU Core 4'),
        DataSource(path: 'environment.rpi.cpu.temperature', label: 'CPU Temperature'),
        DataSource(path: 'environment.rpi.gpu.temperature', label: 'GPU Temperature'),
        DataSource(path: 'environment.rpi.memory.utilisation', label: 'Memory'),
        DataSource(path: 'environment.rpi.storage.utilisation', label: 'Storage'),
        DataSource(path: 'environment.rpi.uptime', label: 'Uptime'),
      ];
    } else {
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

    // Set default sizes for specific tool types
    switch (toolTypeId) {
      case 'autopilot':
      case 'polar_radar_chart':
      case 'ais_polar_chart':
      case 'wind_compass':
        _toolWidth = 6;
        _toolHeight = 6;
        break;
      case 'conversion_test':
      case 'server_manager':
      case 'rpi_monitor':
      case 'webview':
        _toolWidth = 4;
        _toolHeight = 8;
        break;
      default:
        // Keep current defaults for other tool types
        break;
    }
  }

  /// Filter tool definitions by selected category
  List<def.ToolDefinition> _getFilteredToolDefinitions(List<def.ToolDefinition> allTools) {
    List<def.ToolDefinition> filtered;

    if (_selectedCategory == null || _selectedCategory == 'all') {
      filtered = allTools; // Show all if no category selected or "all" selected
    } else {
      filtered = allTools.where((toolDef) {
        switch (_selectedCategory) {
          case 'gauges':
            // Gauges and text displays
            return toolDef.category == def.ToolCategory.gauge || toolDef.category == def.ToolCategory.display;
          case 'charts':
            return toolDef.category == def.ToolCategory.chart;
          case 'controls':
            return toolDef.category == def.ToolCategory.control;
          case 'system':
            return toolDef.category == def.ToolCategory.system;
          case 'instruments':
            // Compass and other instruments
            return toolDef.category == def.ToolCategory.compass || toolDef.category == def.ToolCategory.other;
          default:
            return true;
        }
      }).toList();
    }

    // Sort by category to group colors together
    filtered.sort((a, b) {
      // Define category order: gauge/display (blue), chart (green), control (orange), compass/other (purple)
      int categoryOrder(def.ToolCategory cat) {
        switch (cat) {
          case def.ToolCategory.gauge:
          case def.ToolCategory.display:
            return 0; // Blue - Gauges & Text
          case def.ToolCategory.chart:
            return 1; // Green - Charts
          case def.ToolCategory.control:
            return 2; // Orange - Controls
          case def.ToolCategory.system:
            return 3; // Red - System tools
          case def.ToolCategory.compass:
          case def.ToolCategory.other:
            return 4; // Purple - Instruments
        }
      }

      final orderA = categoryOrder(a.category);
      final orderB = categoryOrder(b.category);

      if (orderA != orderB) {
        return orderA.compareTo(orderB);
      }

      // Within same category, sort alphabetically by name
      return a.name.compareTo(b.name);
    });

    return filtered;
  }

  /// Get color for a category
  Color _getCategoryColor(def.ToolCategory category) {
    switch (category) {
      case def.ToolCategory.gauge:
      case def.ToolCategory.display:
        return Colors.blue;
      case def.ToolCategory.chart:
        return Colors.green;
      case def.ToolCategory.control:
        return Colors.orange;
      case def.ToolCategory.system:
        return Colors.red.shade700;
      case def.ToolCategory.compass:
      case def.ToolCategory.other:
        return Colors.purple;
    }
  }

  /// Build a category filter button
  Widget _buildCategoryButton(String categoryId, String label, Color color) {
    final isSelected = _selectedCategory == categoryId;

    return FilledButton(
      onPressed: () {
        setState(() {
          _selectedCategory = categoryId;
        });
      },
      style: FilledButton.styleFrom(
        backgroundColor: isSelected ? color : color.withValues(alpha: 0.3),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: isSelected
              ? BorderSide(color: color, width: 2)
              : BorderSide.none,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  /// Build a tool selection button
  Widget _buildToolButton(String toolId, String toolName, Color categoryColor, bool isSelected) {
    return OutlinedButton(
      onPressed: () {
        setState(() {
          // If selecting a different tool, reset form and load new defaults
          if (_selectedToolTypeId != toolId) {
            _resetFormFields();
            _selectedToolTypeId = toolId;
            _loadDefaultsForToolType(toolId);
          }
        });
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: isSelected ? Colors.white : categoryColor,
        backgroundColor: isSelected ? categoryColor : Colors.transparent,
        side: BorderSide(color: categoryColor, width: 2),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(
        toolName,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
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
      _chartShowMovingAverage = style.customProperties!['showMovingAverage'] as bool? ?? false;
      _chartMovingAverageWindow = style.customProperties!['movingAverageWindow'] as int? ?? 5;
      _polarHistorySeconds = style.customProperties!['historySeconds'] as int? ?? 60;
      _aisMaxRangeNm = (style.customProperties!['maxRangeNm'] as num?)?.toDouble() ?? 5.0;
      // Convert milliseconds back to seconds for UI
      final updateIntervalMs = style.customProperties!['updateInterval'] as int? ?? 10000;
      _aisUpdateInterval = (updateIntervalMs / 1000).round();
      _sliderDecimalPlaces = style.customProperties!['decimalPlaces'] as int? ?? 1;
      _dropdownStepSize = (style.customProperties!['stepSize'] as num?)?.toDouble() ?? 10.0;
      // Wind compass settings
      _showAWANumbers = style.customProperties!['showAWANumbers'] as bool? ?? true;
      _enableVMG = style.customProperties!['enableVMG'] as bool? ?? false;
      // Autopilot settings
      _headingTrue = style.customProperties!['headingTrue'] as bool? ?? false;
      _invertRudder = style.customProperties!['invertRudder'] as bool? ?? false;
      _fadeDelaySeconds = style.customProperties!['fadeDelaySeconds'] as int? ?? 5;
      _enableVMG = style.customProperties!['enableVMG'] as bool? ?? false;
      _webViewUrl = style.customProperties!['url'] as String? ?? '';
    }

    // Load wind compass and autopilot settings from style
    _laylineAngle = style.laylineAngle ?? 40.0;
    _targetTolerance = style.targetTolerance ?? 3.0;

    // Size is managed in placements, not tools
    _toolWidth = 1;
    _toolHeight = 1;
  }

  Future<void> _addDataSource() async {
    final signalKService = Provider.of<SignalKService>(context, listen: false);
    String? selectedPath;

    // Step 1: Select path
    await showDialog(
      context: context,
      builder: (context) => PathSelectorDialog(
        signalKService: signalKService,
        useHistoricalPaths: _selectedToolTypeId == 'historical_chart',
        onSelect: (path) {
          selectedPath = path;
        },
      ),
    );

    if (selectedPath == null || !mounted) return;

    // Step 2: Configure source and label
    final config = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ConfigureDataSourceDialog(
        signalKService: signalKService,
        path: selectedPath!,
      ),
    );

    if (config != null && mounted) {
      setState(() {
        _dataSources.add(DataSource(
          path: selectedPath!,
          source: config['source'] as String?,
          label: config['label'] as String?,
        ));
      });
    }
  }

  void _removeDataSource(int index) {
    setState(() {
      _dataSources.removeAt(index);
    });
  }

  Future<void> _loadSignalKWebApps() async {
    setState(() {
      _loadingWebApps = true;
    });

    try {
      final signalKService = Provider.of<SignalKService>(context, listen: false);
      final serverUrl = signalKService.serverUrl;
      final useSecure = signalKService.useSecureConnection;

      if (serverUrl.isEmpty) {
        throw Exception('Not connected to SignalK server');
      }

      final protocol = useSecure ? 'https' : 'http';
      final url = Uri.parse('$protocol://$serverUrl/webapps');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> webapps = json.decode(response.body);

        setState(() {
          _signalKWebApps = webapps.map((app) {
            final name = app['name'] as String? ?? 'Unknown';
            final version = app['version'] as String? ?? '';
            final description = app['description'] as String?;
            final location = app['location'] as String? ?? '';

            // Build full URL
            final webappUrl = '$protocol://$serverUrl$location';

            return {
              'name': name,
              'version': version,
              'description': description ?? 'Version $version',
              'url': webappUrl,
            };
          }).toList();
          _loadingWebApps = false;
        });
      } else {
        throw Exception('Failed to load webapps: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingWebApps = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load SignalK webapps: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
    // WebView, server_manager, and system_monitor don't need data sources, other tools do
    if (_selectedToolTypeId == null) return;
    if (_selectedToolTypeId != 'webview' && _selectedToolTypeId != 'server_manager' && _selectedToolTypeId != 'system_monitor' && _dataSources.isEmpty) return;

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
        'showMovingAverage': _chartShowMovingAverage,
        'movingAverageWindow': _chartMovingAverageWindow,
      };
    } else if (_selectedToolTypeId == 'realtime_chart') {
      customProperties = {
        'showMovingAverage': _chartShowMovingAverage,
        'movingAverageWindow': _chartMovingAverageWindow,
      };
    } else if (_selectedToolTypeId == 'polar_radar_chart') {
      customProperties = {
        'historySeconds': _polarHistorySeconds,
        'showLabels': true,
        'showGrid': true,
      };
    } else if (_selectedToolTypeId == 'ais_polar_chart') {
      customProperties = {
        'maxRangeNm': _aisMaxRangeNm,
        'updateInterval': _aisUpdateInterval * 1000, // Convert to milliseconds
        'showLabels': true,
        'showGrid': true,
      };
    } else if (_selectedToolTypeId == 'slider' || _selectedToolTypeId == 'knob') {
      customProperties = {
        'decimalPlaces': _sliderDecimalPlaces,
      };
    } else if (_selectedToolTypeId == 'dropdown') {
      customProperties = {
        'decimalPlaces': _sliderDecimalPlaces,
        'stepSize': _dropdownStepSize,
      };
    } else if (_selectedToolTypeId == 'wind_compass') {
      customProperties = {
        'showAWANumbers': _showAWANumbers,
        'enableVMG': _enableVMG,
      };
    } else if (_selectedToolTypeId == 'autopilot') {
      customProperties = {
        'headingTrue': _headingTrue,
        'invertRudder': _invertRudder,
        'fadeDelaySeconds': _fadeDelaySeconds,
        'enableVMG': _enableVMG,
      };
    } else if (_selectedToolTypeId == 'webview') {
      customProperties = {
        'url': _webViewUrl,
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
        laylineAngle: (_selectedToolTypeId == 'wind_compass' || _selectedToolTypeId == 'autopilot') ? _laylineAngle : null,
        targetTolerance: (_selectedToolTypeId == 'wind_compass' || _selectedToolTypeId == 'autopilot') ? _targetTolerance : null,
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
        defaultWidth: _toolWidth,
        defaultHeight: _toolHeight,
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
        defaultWidth: _toolWidth,
        defaultHeight: _toolHeight,
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
            onPressed: _selectedToolTypeId != null && (_dataSources.isNotEmpty || _selectedToolTypeId == 'webview' || _selectedToolTypeId == 'server_manager' || _selectedToolTypeId == 'system_monitor')
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
                    // Category filter chips with colors
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildCategoryButton('all', 'All', Colors.grey),
                        _buildCategoryButton('gauges', 'Gauges & Text', Colors.blue),
                        _buildCategoryButton('charts', 'Charts', Colors.green),
                        _buildCategoryButton('controls', 'Controls', Colors.orange),
                        _buildCategoryButton('system', 'System', Colors.red.shade700),
                        _buildCategoryButton('instruments', 'Instruments', Colors.purple),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Tool type chips (filtered by category)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _getFilteredToolDefinitions(toolDefinitions).map((toolDef) {
                        final isSelected = _selectedToolTypeId == toolDef.id;
                        final categoryColor = _getCategoryColor(toolDef.category);
                        return _buildToolButton(
                          toolDef.id,
                          toolDef.name,
                          categoryColor,
                          isSelected,
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Data Source Configuration (hide for webview, server_manager, and system_monitor)
            if (_selectedToolTypeId != 'webview' && _selectedToolTypeId != 'server_manager' && _selectedToolTypeId != 'system_monitor')
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

                          // Add role labels for polar chart
                          String? roleLabel;
                          if (_selectedToolTypeId == 'polar_radar_chart') {
                            if (index == 0) {
                              roleLabel = 'Angle/Direction (e.g., wind direction, course)';
                            } else if (index == 1) {
                              roleLabel = 'Magnitude/Velocity (e.g., wind speed, boat speed)';
                            }
                          } else if (_selectedToolTypeId == 'ais_polar_chart') {
                            if (index == 0) {
                              roleLabel = 'Own Position (default: navigation.position)';
                            }
                          }

                          // Special display for webview
                          final isWebView = _selectedToolTypeId == 'webview';

                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                child: isWebView
                                    ? const Icon(Icons.web, size: 18)
                                    : Text('${index + 1}'),
                              ),
                              title: Text(isWebView ? 'Web Page' : (ds.label ?? ds.path.split('.').last)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(isWebView ? (ds.label ?? 'No URL') : ds.path),
                                  if (roleLabel != null)
                                    Text(
                                      roleLabel,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                ],
                              ),
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

            // Size Configuration (hide for all tools - using pixel positioning instead of grid layout)
            if (_selectedToolTypeId != null &&
                _selectedToolTypeId != 'autopilot' &&
                _selectedToolTypeId != 'wind_compass' &&
                _selectedToolTypeId != 'radial_gauge' &&
                _selectedToolTypeId != 'linear_gauge' &&
                _selectedToolTypeId != 'compass' &&
                _selectedToolTypeId != 'text_display' &&
                _selectedToolTypeId != 'conversion_test' &&
                _selectedToolTypeId != 'slider' &&
                _selectedToolTypeId != 'knob' &&
                _selectedToolTypeId != 'switch' &&
                _selectedToolTypeId != 'checkbox' &&
                _selectedToolTypeId != 'dropdown' &&
                _selectedToolTypeId != 'historical_chart' &&
                _selectedToolTypeId != 'polar_radar_chart' &&
                _selectedToolTypeId != 'ais_polar_chart' &&
                _selectedToolTypeId != 'realtime_chart' &&
                _selectedToolTypeId != 'radial_bar_chart' &&
                _selectedToolTypeId != 'server_manager' &&
                _selectedToolTypeId != 'rpi_monitor' &&
                _selectedToolTypeId != 'system_monitor' &&
                _selectedToolTypeId != 'webview')
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
            if (_selectedToolTypeId == 'polar_radar_chart')
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '3. Polar Chart Settings',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Time Window',
                          border: OutlineInputBorder(),
                          helperText: 'How much historical data to show',
                        ),
                        initialValue: _polarHistorySeconds,
                        items: const [
                          DropdownMenuItem(value: 30, child: Text('30 seconds')),
                          DropdownMenuItem(value: 60, child: Text('1 minute')),
                          DropdownMenuItem(value: 120, child: Text('2 minutes')),
                          DropdownMenuItem(value: 300, child: Text('5 minutes')),
                          DropdownMenuItem(value: 600, child: Text('10 minutes')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _polarHistorySeconds = value);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            if (_selectedToolTypeId == 'ais_polar_chart')
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '3. AIS Chart Settings',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<double>(
                        decoration: const InputDecoration(
                          labelText: 'Maximum Range',
                          border: OutlineInputBorder(),
                          helperText: 'Display vessels within this range (0 = auto)',
                        ),
                        initialValue: _aisMaxRangeNm,
                        items: const [
                          DropdownMenuItem(value: 0.0, child: Text('Auto (fit all vessels)')),
                          DropdownMenuItem(value: 1.0, child: Text('1 nautical mile')),
                          DropdownMenuItem(value: 2.0, child: Text('2 nautical miles')),
                          DropdownMenuItem(value: 5.0, child: Text('5 nautical miles')),
                          DropdownMenuItem(value: 10.0, child: Text('10 nautical miles')),
                          DropdownMenuItem(value: 20.0, child: Text('20 nautical miles')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _aisMaxRangeNm = value);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Update Interval',
                          border: OutlineInputBorder(),
                          helperText: 'How often to refresh vessel data',
                        ),
                        initialValue: _aisUpdateInterval,
                        items: const [
                          DropdownMenuItem(value: 5, child: Text('5 seconds')),
                          DropdownMenuItem(value: 10, child: Text('10 seconds')),
                          DropdownMenuItem(value: 15, child: Text('15 seconds')),
                          DropdownMenuItem(value: 30, child: Text('30 seconds')),
                          DropdownMenuItem(value: 60, child: Text('1 minute')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _aisUpdateInterval = value);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            if (_selectedToolTypeId == 'historical_chart')
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '3. Chart Settings',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Time Duration',
                          border: OutlineInputBorder(),
                        ),
                        initialValue: _chartDuration,
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
                        initialValue: _chartResolution,
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
                        initialValue: _chartStyle,
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
                            initialValue: _chartRefreshInterval,
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
                      const Divider(),
                      SwitchListTile(
                        title: const Text('Show Moving Average'),
                        subtitle: const Text('Display smoothed trend line'),
                        value: _chartShowMovingAverage,
                        onChanged: (value) {
                          setState(() => _chartShowMovingAverage = value);
                        },
                      ),
                      if (_chartShowMovingAverage)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: DropdownButtonFormField<int>(
                            decoration: const InputDecoration(
                              labelText: 'Moving Average Window',
                              border: OutlineInputBorder(),
                              helperText: 'Number of data points to average',
                            ),
                            value: _chartMovingAverageWindow,
                            items: const [
                              DropdownMenuItem(value: 3, child: Text('3 points')),
                              DropdownMenuItem(value: 5, child: Text('5 points')),
                              DropdownMenuItem(value: 10, child: Text('10 points')),
                              DropdownMenuItem(value: 15, child: Text('15 points')),
                              DropdownMenuItem(value: 20, child: Text('20 points')),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _chartMovingAverageWindow = value);
                              }
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (_selectedToolTypeId == 'realtime_chart')
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '3. Chart Settings',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Show Moving Average'),
                        subtitle: const Text('Display smoothed trend line'),
                        value: _chartShowMovingAverage,
                        onChanged: (value) {
                          setState(() => _chartShowMovingAverage = value);
                        },
                      ),
                      if (_chartShowMovingAverage)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: DropdownButtonFormField<int>(
                            decoration: const InputDecoration(
                              labelText: 'Moving Average Window',
                              border: OutlineInputBorder(),
                              helperText: 'Number of data points to average',
                            ),
                            value: _chartMovingAverageWindow,
                            items: const [
                              DropdownMenuItem(value: 3, child: Text('3 points')),
                              DropdownMenuItem(value: 5, child: Text('5 points')),
                              DropdownMenuItem(value: 10, child: Text('10 points')),
                              DropdownMenuItem(value: 15, child: Text('15 points')),
                              DropdownMenuItem(value: 20, child: Text('20 points')),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _chartMovingAverageWindow = value);
                              }
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Style Configuration (hide for conversion_test, server_manager, rpi_monitor, and system_monitor)
            if (_selectedToolTypeId != null && _selectedToolTypeId != 'conversion_test' && _selectedToolTypeId != 'server_manager' && _selectedToolTypeId != 'rpi_monitor' && _selectedToolTypeId != 'system_monitor')
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedToolTypeId == 'webview'
                            ? '2. Configure URL'
                            : (_selectedToolTypeId == 'historical_chart' ||
                                _selectedToolTypeId == 'polar_radar_chart' ||
                                _selectedToolTypeId == 'ais_polar_chart')
                                ? '4. Configure Style'
                                : '3. Configure Style',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      ..._buildStyleOptions(),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Preview (hide for server_manager - it has too much content)
            if (_selectedToolTypeId != null && (_dataSources.isNotEmpty || _selectedToolTypeId == 'webview') && _selectedToolTypeId != 'server_manager')
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedToolTypeId == 'server_manager' || _selectedToolTypeId == 'system_monitor'
                            ? '2. Preview'
                            : (_selectedToolTypeId == 'webview' || _selectedToolTypeId == 'rpi_monitor')
                                ? '3. Preview'
                                : (_selectedToolTypeId == 'historical_chart' ||
                                    _selectedToolTypeId == 'polar_radar_chart' ||
                                    _selectedToolTypeId == 'ais_polar_chart')
                                    ? '5. Preview'
                                    : '4. Preview',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
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
                                'showMovingAverage': _chartShowMovingAverage,
                                'movingAverageWindow': _chartMovingAverageWindow,
                              };
                            } else if (_selectedToolTypeId == 'realtime_chart') {
                              previewCustomProperties = {
                                'showMovingAverage': _chartShowMovingAverage,
                                'movingAverageWindow': _chartMovingAverageWindow,
                              };
                            } else if (_selectedToolTypeId == 'polar_radar_chart') {
                              previewCustomProperties = {
                                'historySeconds': _polarHistorySeconds,
                                'showLabels': true,
                                'showGrid': true,
                              };
                            } else if (_selectedToolTypeId == 'ais_polar_chart') {
                              previewCustomProperties = {
                                'maxRangeNm': _aisMaxRangeNm,
                                'updateInterval': _aisUpdateInterval * 1000, // Convert to milliseconds
                                'showLabels': true,
                                'showGrid': true,
                              };
                            } else if (_selectedToolTypeId == 'slider' || _selectedToolTypeId == 'knob') {
                              previewCustomProperties = {
                                'decimalPlaces': _sliderDecimalPlaces,
                              };
                            } else if (_selectedToolTypeId == 'dropdown') {
                              previewCustomProperties = {
                                'decimalPlaces': _sliderDecimalPlaces,
                                'stepSize': _dropdownStepSize,
                              };
                            } else if (_selectedToolTypeId == 'wind_compass') {
                              previewCustomProperties = {
                                'showAWANumbers': _showAWANumbers,
                                'enableVMG': _enableVMG,
                              };
                            } else if (_selectedToolTypeId == 'autopilot') {
                              previewCustomProperties = {
                                'headingTrue': _headingTrue,
                                'invertRudder': _invertRudder,
                                'fadeDelaySeconds': _fadeDelaySeconds,
                                'enableVMG': _enableVMG,
                              };
                            } else if (_selectedToolTypeId == 'webview') {
                              previewCustomProperties = {
                                'url': _webViewUrl,
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

                            return FittedBox(
                              fit: BoxFit.contain,
                              alignment: Alignment.topCenter,
                              child: SizedBox(
                                width: 300,
                                height: 300,
                                child: registry.buildTool(
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
                                      laylineAngle: (_selectedToolTypeId == 'wind_compass' || _selectedToolTypeId == 'autopilot') ? _laylineAngle : null,
                                      targetTolerance: (_selectedToolTypeId == 'wind_compass' || _selectedToolTypeId == 'autopilot') ? _targetTolerance : null,
                                      customProperties: previewCustomProperties,
                                    ),
                                  ),
                                  service,
                                ),
                              ),
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

    // Unit (not applicable for autopilot or wind_compass)
    if (_selectedToolTypeId != 'autopilot' && _selectedToolTypeId != 'wind_compass') {
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
    }

    // Color (only if tool supports color customization)
    if (schema.allowsColorCustomization) {
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
    }

    // Show/Hide Options (not applicable for autopilot or wind_compass)
    if (_selectedToolTypeId != 'autopilot' && _selectedToolTypeId != 'wind_compass') {
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
      ]);
    } else {
      widgets.addAll([
        const SizedBox(height: 16),
      ]);
    }

    widgets.addAll([
      DropdownButtonFormField<int?>(
        decoration: const InputDecoration(
          labelText: 'Data Staleness Threshold (TTL)',
          border: OutlineInputBorder(),
          helperText: 'Show "--" if data is older than this threshold',
        ),
        initialValue: _ttlSeconds,
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
          initialValue: _compassStyle,
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

    // Wind compass-specific options
    if (_selectedToolTypeId == 'wind_compass') {
      widgets.addAll([
        const SizedBox(height: 16),
        const Text(
          'Performance Sailing Settings',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        // Target AWA slider
        ListTile(
          title: const Text('Target AWA Angle'),
          subtitle: Text(
            '${_laylineAngle.toStringAsFixed(0)}° - Optimal close-hauled angle for your boat',
            style: const TextStyle(fontSize: 12),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        Slider(
          value: _laylineAngle,
          min: 30,
          max: 50,
          divisions: 20,
          label: '${_laylineAngle.toStringAsFixed(0)}°',
          onChanged: (value) {
            setState(() => _laylineAngle = value);
          },
        ),
        const SizedBox(height: 8),
        // Target tolerance slider
        ListTile(
          title: const Text('Target Tolerance'),
          subtitle: Text(
            '±${_targetTolerance.toStringAsFixed(0)}° - Acceptable deviation (green zone)',
            style: const TextStyle(fontSize: 12),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        Slider(
          value: _targetTolerance,
          min: 1,
          max: 10,
          divisions: 9,
          label: '±${_targetTolerance.toStringAsFixed(0)}°',
          onChanged: (value) {
            setState(() => _targetTolerance = value);
          },
        ),
        const SizedBox(height: 8),
        // Show AWA Numbers toggle
        SwitchListTile(
          title: const Text('Show AWA Numbers'),
          subtitle: const Text('Display numeric AWA with performance feedback'),
          value: _showAWANumbers,
          onChanged: (value) {
            setState(() => _showAWANumbers = value);
          },
        ),
        // Enable VMG toggle
        SwitchListTile(
          title: const Text('Enable VMG Optimization'),
          subtitle: const Text('Use polar-based dynamic target AWA (varies with wind speed)'),
          value: _enableVMG,
          onChanged: (value) {
            setState(() => _enableVMG = value);
          },
        ),
        if (_enableVMG)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'VMG Mode Active',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Target AWA will dynamically adjust based on true wind speed using built-in polar data. Manual target angle is overridden.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
      ]);
    }

    // Autopilot-specific options
    if (_selectedToolTypeId == 'autopilot') {
      widgets.addAll([
        const SizedBox(height: 16),
        const Text(
          'Autopilot Display Settings',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Use True Heading'),
          subtitle: const Text('Display true heading instead of magnetic'),
          value: _headingTrue,
          onChanged: (value) {
            setState(() => _headingTrue = value);
          },
        ),
        SwitchListTile(
          title: const Text('Invert Rudder Display'),
          subtitle: const Text('Reverse rudder angle visualization (for non-standard sensor polarity)'),
          value: _invertRudder,
          onChanged: (value) {
            setState(() => _invertRudder = value);
          },
        ),
        const SizedBox(height: 16),
        const Text(
          'Performance Sailing Settings (Wind Mode)',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        // Target AWA slider
        ListTile(
          title: const Text('Target AWA Angle'),
          subtitle: Text(
            '${_laylineAngle.toStringAsFixed(0)}° - Optimal close-hauled angle for your boat',
            style: const TextStyle(fontSize: 12),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        Slider(
          value: _laylineAngle,
          min: 30,
          max: 50,
          divisions: 20,
          label: '${_laylineAngle.toStringAsFixed(0)}°',
          onChanged: (value) {
            setState(() => _laylineAngle = value);
          },
        ),
        const SizedBox(height: 8),
        // Target tolerance slider
        ListTile(
          title: const Text('Target Tolerance'),
          subtitle: Text(
            '±${_targetTolerance.toStringAsFixed(0)}° - Acceptable deviation (green zone)',
            style: const TextStyle(fontSize: 12),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        Slider(
          value: _targetTolerance,
          min: 1,
          max: 10,
          divisions: 9,
          label: '±${_targetTolerance.toStringAsFixed(0)}°',
          onChanged: (value) {
            setState(() => _targetTolerance = value);
          },
        ),
        const SizedBox(height: 16),
        // Fade delay slider
        ListTile(
          title: const Text('Control Fade Delay'),
          subtitle: Text(
            '${_fadeDelaySeconds}s - Seconds before controls fade after activity',
            style: const TextStyle(fontSize: 12),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        Slider(
          value: _fadeDelaySeconds.toDouble(),
          min: 3,
          max: 30,
          divisions: 27,
          label: '${_fadeDelaySeconds}s',
          onChanged: (value) {
            setState(() => _fadeDelaySeconds = value.round());
          },
        ),
        const SizedBox(height: 8),
        // Enable VMG toggle
        SwitchListTile(
          title: const Text('Enable VMG Optimization'),
          subtitle: const Text('Use polar-based dynamic target AWA (varies with wind speed)'),
          value: _enableVMG,
          onChanged: (value) {
            setState(() => _enableVMG = value);
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
          initialValue: _gaugeStyle,
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
          initialValue: _linearGaugeStyle,
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
          initialValue: _orientation,
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

    // Text Display-specific options
    if (_selectedToolTypeId == 'text_display') {
      widgets.addAll([
        const SizedBox(height: 16),
        TextFormField(
          decoration: const InputDecoration(
            labelText: 'Font Size',
            border: OutlineInputBorder(),
            helperText: 'Size of the numeric display (default: 48)',
          ),
          keyboardType: TextInputType.number,
          initialValue: _fontSize?.toString() ?? '48',
          onChanged: (value) {
            final parsed = double.tryParse(value);
            if (parsed != null && parsed > 0) {
              setState(() => _fontSize = parsed);
            }
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
          initialValue: _sliderDecimalPlaces,
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

    // Dropdown-specific options
    if (_selectedToolTypeId == 'dropdown') {
      widgets.addAll([
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          decoration: const InputDecoration(
            labelText: 'Decimal Places',
            border: OutlineInputBorder(),
            helperText: 'Number of decimal places to display',
          ),
          initialValue: _sliderDecimalPlaces,
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
        const SizedBox(height: 16),
        TextFormField(
          decoration: const InputDecoration(
            labelText: 'Step Size',
            border: OutlineInputBorder(),
            helperText: 'Increment between dropdown values',
          ),
          keyboardType: TextInputType.number,
          initialValue: _dropdownStepSize.toString(),
          onChanged: (value) {
            final parsed = double.tryParse(value);
            if (parsed != null && parsed > 0) {
              setState(() => _dropdownStepSize = parsed);
            }
          },
        ),
      ]);
    }

    // WebView-specific options
    if (_selectedToolTypeId == 'webview') {
      // Load webapps on first display
      if (_signalKWebApps.isEmpty && !_loadingWebApps) {
        Future.microtask(() => _loadSignalKWebApps());
      }

      widgets.addAll([
        const SizedBox(height: 16),
        // Custom URL input (always shown)
        TextFormField(
          decoration: const InputDecoration(
            labelText: 'Web Page URL',
            border: OutlineInputBorder(),
            hintText: 'Enter URL or select from SignalK webapps below',
            helperText: 'Enter full URL or select from installed SignalK webapps',
          ),
          initialValue: _webViewUrl,
          onChanged: (value) => _webViewUrl = value,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'URL is required';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        // SignalK webapps section
        if (_loadingWebApps)
          const Center(
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 8),
                Text(
                  'Loading SignalK webapps...',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          )
        else if (_signalKWebApps.isNotEmpty) ...[
          const Divider(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Or select from SignalK webapps:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              TextButton.icon(
                onPressed: _loadSignalKWebApps,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _signalKWebApps.map((app) {
              final isSelected = _webViewUrl == app['url'];
              return FilterChip(
                label: Text(app['name'] ?? 'Unknown'),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _webViewUrl = selected ? app['url']! : '';
                  });
                },
                tooltip: app['description'],
                avatar: isSelected ? const Icon(Icons.check, size: 16) : null,
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          'Examples:\n'
          '• http://192.168.1.88:3000/@signalk/server-admin-ui\n'
          '• https://windy.com\n'
          '• http://192.168.1.88:3000/your-webapp',
          style: TextStyle(fontSize: 11, color: Colors.grey),
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
