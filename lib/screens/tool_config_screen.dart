import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../models/tool_config.dart';
import '../models/tool.dart';
import '../models/tool_definition.dart' as def;
import '../services/signalk_service.dart';
import '../services/tool_registry.dart';
import '../services/tool_service.dart';
import '../services/tool_config_service.dart';
import '../widgets/config/path_selector.dart';
import '../widgets/config/configure_data_source_dialog.dart';
import '../widgets/config/source_selector.dart';
import 'tool_config/base_tool_configurator.dart';
import 'tool_config/tool_configurator_factory.dart';
import 'tool_config/configurators/tanks_configurator.dart';

/// Screen for configuring a tool
class ToolConfigScreen extends StatefulWidget {
  final Tool? existingTool; // null for new tool
  final String screenId;
  final int? existingWidth;
  final int? existingHeight;
  final String? initialToolTypeId; // Pre-select tool type (from ToolSelectorScreen)

  const ToolConfigScreen({
    super.key,
    this.existingTool,
    required this.screenId,
    this.existingWidth,
    this.existingHeight,
    this.initialToolTypeId,
  });

  @override
  State<ToolConfigScreen> createState() => _ToolConfigScreenState();
}

class _ToolConfigScreenState extends State<ToolConfigScreen> {
  final _formKey = GlobalKey<FormState>();

  // Tool-specific configurator (handles tool-specific UI and config)
  ToolConfigurator? _configurator;

  // Configuration state
  String? _selectedToolTypeId;
  List<DataSource> _dataSources = [];

  // Style configuration
  double? _minValue;
  double? _maxValue;
  String? _unit;
  String? _primaryColor;
  String? _secondaryColor;
  bool _showLabel = true;
  bool _showValue = true;
  bool _showUnit = true;
  int? _ttlSeconds; // Data staleness threshold

  // NOTE: Tool-specific variables (chart, gauge, compass, etc.) are now handled
  // by their respective configurators in lib/screens/tool_config/configurators/
  // Only common configuration remains here (min/max, color, show/hide, ttl)

  // Old compass tool support (for 'compass' tool type - not wind_compass or autopilot)
  bool _showTickLabels = false;
  String _compassStyle = 'classic';

  // WeatherFlow forecast options
  int _hoursToShow = 12;
  bool _showCurrentConditions = true;

  // Size configuration
  int _toolWidth = 1;
  int _toolHeight = 1;

  @override
  void initState() {
    super.initState();
    if (widget.existingTool != null) {
      _loadExistingTool();
    } else if (widget.initialToolTypeId != null) {
      // Pre-select tool type from ToolSelectorScreen
      _selectedToolTypeId = widget.initialToolTypeId;
      // Load defaults after first frame when context is available
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeForToolType(widget.initialToolTypeId!);
      });
    }
    // Load existing size if provided
    if (widget.existingWidth != null) {
      _toolWidth = widget.existingWidth!;
    }
    if (widget.existingHeight != null) {
      _toolHeight = widget.existingHeight!;
    }
  }

  /// Initialize configurator and defaults for a tool type (called after context available)
  void _initializeForToolType(String toolId) {
    if (!mounted) return;
    setState(() {
      // Create tool-specific configurator
      final signalKService = Provider.of<SignalKService>(context, listen: false);
      _configurator = ToolConfiguratorFactory.create(toolId);
      _configurator?.loadDefaults(signalKService);

      // Set default size from configurator if available
      if (_configurator != null) {
        _toolWidth = _configurator!.defaultSize.width.toInt();
        _toolHeight = _configurator!.defaultSize.height.toInt();
      }

      _loadDefaultsForToolType(toolId);
    });
  }

  /// Reset all form fields to default values
  void _resetFormFields() {
    // Reset common configuration
    _dataSources = [];
    _minValue = null;
    _maxValue = null;
    _unit = null;
    _primaryColor = null;
    _secondaryColor = null;
    _showLabel = true;
    _showValue = true;
    _showUnit = true;
    _ttlSeconds = null;

    // Reset old compass tool support
    _showTickLabels = false;
    _compassStyle = 'classic';

    // Reset WeatherFlow forecast options
    _hoursToShow = 12;
    _showCurrentConditions = true;

    // Reset size
    _toolWidth = 1;
    _toolHeight = 1;

    // NOTE: Tool-specific fields are reset by their configurators
    // The configurator's reset() method is called when created
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
      case 'gnss_status':
        _toolWidth = 4;
        _toolHeight = 4;
        break;
      case 'attitude_indicator':
        _toolWidth = 3;
        _toolHeight = 3;
        break;
      case 'weatherflow_forecast':
        _toolWidth = 4;
        _toolHeight = 4;
        break;
      case 'clock_alarm':
      case 'weather_api_spinner':
        _toolWidth = 4;
        _toolHeight = 4;
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

  void _loadExistingTool() {
    final tool = widget.existingTool!;
    _selectedToolTypeId = tool.toolTypeId;
    _dataSources = List.from(tool.config.dataSources);

    // Create and load tool-specific configurator
    _configurator = ToolConfiguratorFactory.create(tool.toolTypeId);
    _configurator?.loadFromTool(tool);

    // Load common configuration from style
    final style = tool.config.style;
    _minValue = style.minValue;
    _maxValue = style.maxValue;
    _unit = style.unit;
    _primaryColor = style.primaryColor;
    _secondaryColor = style.secondaryColor;
    _showLabel = style.showLabel ?? true;
    _showValue = style.showValue ?? true;
    _showUnit = style.showUnit ?? true;
    _ttlSeconds = style.ttlSeconds;

    // Old compass tool support (for 'compass' tool type)
    _showTickLabels = style.customProperties?['showTickLabels'] as bool? ?? false;
    _compassStyle = style.customProperties?['compassStyle'] as String? ?? 'classic';

    // WeatherFlow forecast options
    _hoursToShow = style.customProperties?['hoursToShow'] as int? ?? 12;
    _showCurrentConditions = style.customProperties?['showCurrentConditions'] as bool? ?? true;

    // NOTE: Tool-specific config is loaded by configurator's loadFromTool() method above

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

  // NOTE: _loadSignalKWebApps() method removed - WebViewConfigurator handles this now

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

  Future<void> _selectSecondaryColor() async {
    // Parse current color or use default
    Color currentColor = Colors.grey;
    if (_secondaryColor != null && _secondaryColor!.isNotEmpty) {
      try {
        final hexColor = _secondaryColor!.replaceAll('#', '');
        currentColor = Color(int.parse('FF$hexColor', radix: 16));
      } catch (e) {
        // Invalid color, use default
      }
    }

    Color? pickedColor;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick secondary color'),
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
                  _secondaryColor = '#${pickedColor!.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
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
    // WebView, server_manager, system_monitor, and crew tools don't need data sources
    if (_selectedToolTypeId == null) return;
    if (_selectedToolTypeId != 'webview' && _selectedToolTypeId != 'server_manager' && _selectedToolTypeId != 'system_monitor' && _selectedToolTypeId != 'crew_messages' && _selectedToolTypeId != 'crew_list' && _selectedToolTypeId != 'intercom' && _selectedToolTypeId != 'file_share' && _selectedToolTypeId != 'weather_alerts' && _selectedToolTypeId != 'clock_alarm' && _selectedToolTypeId != 'weather_api_spinner' && _selectedToolTypeId != 'victron_flow' && _selectedToolTypeId != 'device_access_manager' && _dataSources.isEmpty) return;

    final toolService = Provider.of<ToolService>(context, listen: false);

    // Get configurator config if available
    final configuratorConfig = _configurator?.getConfig();

    // Build config with common properties + defaults for tool-specific ones
    // Tool-specific properties will be overridden by configurator merge below
    var config = ToolConfigService.buildToolConfig(
      dataSources: _dataSources,
      toolTypeId: _selectedToolTypeId!,
      minValue: _minValue,
      maxValue: _maxValue,
      unit: _unit,
      primaryColor: _primaryColor,
      showLabel: _showLabel,
      showValue: _showValue,
      showUnit: _showUnit,
      ttlSeconds: _ttlSeconds,
      // Tool-specific: Use defaults, configurator will override
      laylineAngle: 40.0,
      targetTolerance: 3.0,
      chartDuration: '1h',
      chartResolution: null,
      chartShowLegend: true,
      chartShowGrid: true,
      chartAutoRefresh: false,
      chartRefreshInterval: 60,
      chartStyle: 'area',
      chartShowMovingAverage: false,
      chartMovingAverageWindow: 5,
      chartTitle: '',
      polarHistorySeconds: 60,
      aisMaxRangeNm: 5.0,
      aisUpdateInterval: 10,
      sliderDecimalPlaces: 1,
      dropdownStepSize: 10.0,
      showAWANumbers: true,
      enableVMG: false,
      headingTrue: false,
      invertRudder: false,
      fadeDelaySeconds: 5,
      webViewUrl: '',
      divisions: 10,
      orientation: 'horizontal',
      showTickLabels: _showTickLabels,
      pointerOnly: false,
      gaugeStyle: 'arc',
      linearGaugeStyle: 'bar',
      compassStyle: _compassStyle,
    );

    // Merge configurator's config if available
    if (configuratorConfig != null) {
      config = ToolConfig(
        // Use configurator's dataSources if it provides them, otherwise use screen's
        dataSources: configuratorConfig.dataSources.isNotEmpty
            ? configuratorConfig.dataSources
            : config.dataSources,
        style: StyleConfig(
          minValue: configuratorConfig.style.minValue ?? config.style.minValue,
          maxValue: configuratorConfig.style.maxValue ?? config.style.maxValue,
          unit: configuratorConfig.style.unit ?? config.style.unit,
          primaryColor: configuratorConfig.style.primaryColor ?? config.style.primaryColor,
          secondaryColor: configuratorConfig.style.secondaryColor ?? _secondaryColor,
          // Use screen state directly - StyleConfig defaults (true) would override user's settings
          showLabel: _showLabel,
          showValue: _showValue,
          showUnit: _showUnit,
          ttlSeconds: configuratorConfig.style.ttlSeconds ?? config.style.ttlSeconds,
          // Merge configurator's style fields (compass/autopilot)
          laylineAngle: configuratorConfig.style.laylineAngle ?? config.style.laylineAngle,
          targetTolerance: configuratorConfig.style.targetTolerance ?? config.style.targetTolerance,
          customProperties: {
            ...?config.style.customProperties,
            ...?configuratorConfig.style.customProperties,
            // WeatherFlow forecast options
            if (_selectedToolTypeId == 'weatherflow_forecast') ...{
              'hoursToShow': _hoursToShow,
              'showCurrentConditions': _showCurrentConditions,
            },
          },
        ),
      );
    } else if (_selectedToolTypeId == 'weatherflow_forecast') {
      // Handle weatherflow_forecast without configurator
      config = ToolConfig(
        dataSources: config.dataSources,
        style: StyleConfig(
          minValue: config.style.minValue,
          maxValue: config.style.maxValue,
          unit: config.style.unit,
          primaryColor: config.style.primaryColor,
          secondaryColor: _secondaryColor,
          showLabel: config.style.showLabel,
          showValue: config.style.showValue,
          showUnit: config.style.showUnit,
          ttlSeconds: config.style.ttlSeconds,
          customProperties: {
            ...?config.style.customProperties,
            'hoursToShow': _hoursToShow,
            'showCurrentConditions': _showCurrentConditions,
          },
        ),
      );
    }

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
            onPressed: _selectedToolTypeId != null && (_dataSources.isNotEmpty || _selectedToolTypeId == 'webview' || _selectedToolTypeId == 'server_manager' || _selectedToolTypeId == 'system_monitor' || _selectedToolTypeId == 'crew_messages' || _selectedToolTypeId == 'crew_list' || _selectedToolTypeId == 'intercom' || _selectedToolTypeId == 'file_share' || _selectedToolTypeId == 'weather_alerts' || _selectedToolTypeId == 'clock_alarm' || _selectedToolTypeId == 'weather_api_spinner' || _selectedToolTypeId == 'victron_flow' || _selectedToolTypeId == 'device_access_manager')
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
            // Data Source Configuration (hide for webview, server_manager, system_monitor, crew tools, weather_alerts, clock_alarm, weather_api_spinner, victron_flow, device_access_manager)
            if (_selectedToolTypeId != 'webview' && _selectedToolTypeId != 'server_manager' && _selectedToolTypeId != 'system_monitor' && _selectedToolTypeId != 'crew_messages' && _selectedToolTypeId != 'crew_list' && _selectedToolTypeId != 'intercom' && _selectedToolTypeId != 'file_share' && _selectedToolTypeId != 'weather_alerts' && _selectedToolTypeId != 'clock_alarm' && _selectedToolTypeId != 'weather_api_spinner' && _selectedToolTypeId != 'victron_flow' && _selectedToolTypeId != 'device_access_manager')
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
                          'Configure Data Sources',
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

                          // Add role labels for tools with multiple indexed paths
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
                          } else if (_selectedToolTypeId == 'gnss_status') {
                            switch (index) {
                              case 0:
                                roleLabel = 'Satellites in view count';
                                break;
                              case 1:
                                roleLabel = 'Fix type / method quality';
                                break;
                              case 2:
                                roleLabel = 'HDOP (Horizontal Dilution of Precision)';
                                break;
                              case 3:
                                roleLabel = 'VDOP - optional, leave empty if not available';
                                break;
                              case 4:
                                roleLabel = 'PDOP - optional, leave empty if not available';
                                break;
                              case 5:
                                roleLabel = 'Horizontal accuracy - optional';
                                break;
                              case 6:
                                roleLabel = 'Vertical accuracy - optional';
                                break;
                              case 7:
                                roleLabel = 'Position (lat/lon object)';
                                break;
                              case 8:
                                roleLabel = 'Satellite details (positions & SNR for sky view)';
                                break;
                            }
                          } else if (_selectedToolTypeId == 'attitude_indicator') {
                            if (index == 0) {
                              roleLabel = 'Attitude object (contains roll, pitch, yaw)';
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

            // Size Configuration (only show for new tools, hide for most tool types that use pixel positioning)
            if (widget.existingTool == null &&
                _selectedToolTypeId != null &&
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
                _selectedToolTypeId != 'webview' &&
                _selectedToolTypeId != 'gnss_status' &&
                _selectedToolTypeId != 'attitude_indicator' &&
                _selectedToolTypeId != 'weatherflow_forecast' &&
                _selectedToolTypeId != 'device_access_manager')
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Configure Size',
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
            const SizedBox(height: 16),

            // Style Configuration (hide for conversion_test, server_manager, rpi_monitor, system_monitor, crew tools, weather_alerts, and device_access_manager)
            if (_selectedToolTypeId != null && _selectedToolTypeId != 'conversion_test' && _selectedToolTypeId != 'server_manager' && _selectedToolTypeId != 'rpi_monitor' && _selectedToolTypeId != 'system_monitor' && _selectedToolTypeId != 'crew_messages' && _selectedToolTypeId != 'crew_list' && _selectedToolTypeId != 'intercom' && _selectedToolTypeId != 'file_share' && _selectedToolTypeId != 'weather_alerts' && _selectedToolTypeId != 'device_access_manager')
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedToolTypeId == 'webview'
                            ? 'Configure URL'
                            : 'Configure Style',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      // Always show common configuration, then tool-specific
                      ..._buildStyleOptions(),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Preview (hide for server_manager - it has too much content)
            if (_selectedToolTypeId != null && (_dataSources.isNotEmpty || _selectedToolTypeId == 'webview' || _selectedToolTypeId == 'crew_messages' || _selectedToolTypeId == 'crew_list' || _selectedToolTypeId == 'intercom' || _selectedToolTypeId == 'file_share' || _selectedToolTypeId == 'weather_alerts' || _selectedToolTypeId == 'clock_alarm' || _selectedToolTypeId == 'weather_api_spinner') && _selectedToolTypeId != 'server_manager')
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Preview',
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
                            // Use service to build preview config
                            final previewConfig = ToolConfigService.buildToolConfig(
                              dataSources: _dataSources,
                              toolTypeId: _selectedToolTypeId!,
                              minValue: _minValue,
                              maxValue: _maxValue,
                              unit: _unit,
                              primaryColor: _primaryColor,
                              showLabel: _showLabel,
                              showValue: _showValue,
                              showUnit: _showUnit,
                              ttlSeconds: _ttlSeconds,
                              // Tool-specific: defaults (configurator values not used in preview)
                              laylineAngle: 40.0,
                              targetTolerance: 3.0,
                              chartDuration: '1h',
                              chartResolution: null,
                              chartShowLegend: true,
                              chartShowGrid: true,
                              chartAutoRefresh: false,
                              chartRefreshInterval: 60,
                              chartStyle: 'area',
                              chartShowMovingAverage: false,
                              chartMovingAverageWindow: 5,
                              chartTitle: '',
                              polarHistorySeconds: 60,
                              aisMaxRangeNm: 5.0,
                              aisUpdateInterval: 10,
                              sliderDecimalPlaces: 1,
                              dropdownStepSize: 10.0,
                              showAWANumbers: true,
                              enableVMG: false,
                              headingTrue: false,
                              invertRudder: false,
                              fadeDelaySeconds: 5,
                              webViewUrl: '',
                              divisions: 10,
                              orientation: 'horizontal',
                              showTickLabels: _showTickLabels,
                              pointerOnly: false,
                              gaugeStyle: 'arc',
                              linearGaugeStyle: 'bar',
                              compassStyle: _compassStyle,
                            );

                            return FittedBox(
                              fit: BoxFit.contain,
                              alignment: Alignment.topCenter,
                              child: SizedBox(
                                width: 300,
                                height: 300,
                                child: registry.buildTool(
                                  _selectedToolTypeId!,
                                  previewConfig,
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

    // Unit (not applicable for certain complex tools)
    const excludeUnitOptions = ['autopilot', 'wind_compass', 'weatherflow_forecast', 'tanks', 'clock_alarm', 'weather_api_spinner', 'anchor_alarm', 'position_display', 'victron_flow', 'device_access_manager'];
    if (!excludeUnitOptions.contains(_selectedToolTypeId)) {
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
        const SizedBox(height: 8),
      ]);

      // Secondary color picker (only for tools that use it)
      const secondaryColorTools = ['switch', 'checkbox', 'wind_compass', 'autopilot', 'windsteer'];
      if (secondaryColorTools.contains(_selectedToolTypeId)) {
        widgets.addAll([
          ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _secondaryColor != null && _secondaryColor!.isNotEmpty
                    ? () {
                        try {
                          final hexColor = _secondaryColor!.replaceAll('#', '');
                          return Color(int.parse('FF$hexColor', radix: 16));
                        } catch (e) {
                          return Colors.grey;
                        }
                      }()
                    : Colors.grey,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade400, width: 2),
              ),
            ),
            title: const Text('Secondary Color'),
            subtitle: Text(_secondaryColor ?? 'Default (Grey)'),
            trailing: const Icon(Icons.edit),
            onTap: _selectSecondaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          const SizedBox(height: 16),
        ]);
      } else {
        widgets.add(const SizedBox(height: 8));
      }
    }

    // Show/Hide Options (not applicable for certain tools)
    const excludeShowHideOptions = ['autopilot', 'wind_compass', 'weatherflow_forecast', 'tanks', 'clock_alarm', 'weather_api_spinner', 'anchor_alarm', 'position_display', 'victron_flow', 'device_access_manager'];
    if (!excludeShowHideOptions.contains(_selectedToolTypeId)) {
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

    // TTL (not applicable for certain tools that have their own state management)
    const excludeTTLOptions = ['clock_alarm', 'anchor_alarm', 'server_manager', 'crew_messages', 'crew_list', 'intercom', 'file_share', 'position_display', 'victron_flow', 'device_access_manager'];
    if (!excludeTTLOptions.contains(_selectedToolTypeId)) {
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
    }

    // WeatherFlow forecast specific options
    if (_selectedToolTypeId == 'weatherflow_forecast') {
      widgets.addAll([
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 16),
        Text(
          'Forecast Options',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          decoration: const InputDecoration(
            labelText: 'Hours to Show',
            border: OutlineInputBorder(),
            helperText: 'Number of forecast hours to display',
          ),
          value: _hoursToShow,
          items: const [
            DropdownMenuItem(value: 6, child: Text('6 hours')),
            DropdownMenuItem(value: 12, child: Text('12 hours')),
            DropdownMenuItem(value: 24, child: Text('24 hours')),
            DropdownMenuItem(value: 48, child: Text('48 hours')),
            DropdownMenuItem(value: 72, child: Text('72 hours')),
          ],
          onChanged: (value) {
            setState(() => _hoursToShow = value ?? 12);
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Show Current Conditions'),
          subtitle: const Text('Display current temperature, humidity, pressure, and wind'),
          value: _showCurrentConditions,
          onChanged: (value) {
            setState(() => _showCurrentConditions = value);
          },
        ),
      ]);
    }

    // If we have a configurator, use it for tool-specific options
    if (_configurator != null) {
      // Update tanks configurator with current data source count
      if (_selectedToolTypeId == 'tanks' && _configurator is TanksConfigurator) {
        (_configurator as TanksConfigurator).updateDataSourceCount(_dataSources.length);
      }
      widgets.addAll([
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 16),
        _configurator!.buildConfigUI(
          context,
          Provider.of<SignalKService>(context, listen: false),
        ),
      ]);
      return widgets;
    }

    // Fallback: All tools should have configurators now
    // If we reach here, just return common config widgets
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
