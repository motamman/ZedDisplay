import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../config/navigation_constants.dart';
import '../models/tool_config.dart';
import '../models/tool_definition.dart' show SlotDefinition, ToolDefinition;
import '../models/tool.dart';
import '../services/ais_favorites_service.dart';
import '../services/signalk_service.dart';
import '../services/tool_registry.dart';
import '../services/tool_service.dart';
import '../services/tool_config_service.dart';
import '../widgets/config/path_selector.dart';
import '../widgets/config/configure_data_source_dialog.dart';
import '../widgets/config/source_selector.dart';
import '../utils/chart_axis_utils.dart';
import 'tool_config/base_tool_configurator.dart';
import 'tool_config/tool_configurator_factory.dart';
import 'tool_config/configurators/chart_configurator.dart';
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

  // Size configuration (default to full grid 8x8)
  int _toolWidth = 8;
  int _toolHeight = 8;

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

    // Pad data sources to slot count if slot definitions exist
    final definition = registry.getDefinition(toolTypeId);
    _padDataSourcesToSlots(definition);

    // All tools default to full grid 8x8 - user can resize on dashboard
    _toolWidth = 8;
    _toolHeight = 8;
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

    // Pad data sources to slot count if slot definitions exist
    final registry = ToolRegistry();
    final definition = registry.getDefinition(tool.toolTypeId);
    _padDataSourcesToSlots(definition);

    // Size is managed in placements, not tools (default to full grid)
    _toolWidth = 8;
    _toolHeight = 8;
  }

  /// Pad _dataSources to match slotDefinitions length, filling missing slots
  /// with defaults. Existing saved configs with fewer sources load correctly.
  void _padDataSourcesToSlots(ToolDefinition? definition) {
    final slots = definition?.configSchema.slotDefinitions;
    if (slots == null) return;
    while (_dataSources.length < slots.length) {
      final slot = slots[_dataSources.length];
      _dataSources.add(DataSource(
        path: slot.defaultPath ?? '',
      ));
    }
  }

  /// Whether the current tool uses slot mode (fixed positional data sources).
  bool get _isSlotMode {
    if (_selectedToolTypeId == null) return false;
    final registry = ToolRegistry();
    final definition = registry.getDefinition(_selectedToolTypeId!);
    return definition?.configSchema.slotDefinitions != null;
  }

  /// Get slot definitions for the current tool, or null.
  List<SlotDefinition>? get _slotDefinitions {
    if (_selectedToolTypeId == null) return null;
    final registry = ToolRegistry();
    final definition = registry.getDefinition(_selectedToolTypeId!);
    return definition?.configSchema.slotDefinitions;
  }

  Future<void> _addDataSource() async {
    final signalKService = Provider.of<SignalKService>(context, listen: false);
    String? selectedPath;

    // Determine if this is a chart tool that needs numeric-only filtering and axis compatibility
    final isChartTool = _selectedToolTypeId == 'realtime_chart' ||
                        _selectedToolTypeId == 'historical_chart';
    final isCompassTool = _selectedToolTypeId == 'compass';

    // For chart tools, determine current axis units for compatibility filtering
    String? primaryAxisBaseUnit;
    String? secondaryAxisBaseUnit;
    if (isChartTool && _dataSources.isNotEmpty) {
      final units = ChartAxisUtils.determineAxisUnits(
        _dataSources,
        signalKService.metadataStore,
      );
      primaryAxisBaseUnit = units.primary;
      secondaryAxisBaseUnit = units.secondary;

      // Debug: log axis detection
      debugPrint('🔍 Chart axis detection:');
      debugPrint('   dataSources: ${_dataSources.length}');
      for (final ds in _dataSources) {
        final unitKey = ChartAxisUtils.getUnitKey(ds.path, signalKService.metadataStore, storedBaseUnit: ds.baseUnit);
        debugPrint('   - ${ds.path}: unitKey=$unitKey, stored=${ds.baseUnit}');
      }
      debugPrint('   primary=$primaryAxisBaseUnit, secondary=$secondaryAxisBaseUnit');
    }

    // Tool types that support AIS vessel context
    const aisContextTools = {
      'radial_gauge', 'linear_gauge', 'compass', 'text_display', 'position_display', 'realtime_chart', 'historical_chart',
    };
    final allowAIS = aisContextTools.contains(_selectedToolTypeId);

    // Gauges need numeric-only filtering too
    final isGaugeTool = _selectedToolTypeId == 'radial_gauge' ||
                        _selectedToolTypeId == 'linear_gauge';

    // Step 1: Select path (with optional AIS vessel context)
    String? selectedVesselContext;
    await showDialog(
      context: context,
      builder: (context) => PathSelectorDialog(
        signalKService: signalKService,
        useHistoricalPaths: _selectedToolTypeId == 'historical_chart',
        historicalContext: _selectedToolTypeId == 'historical_chart'
            ? (_configurator as ChartConfigurator?)?.chartContext
            : null,
        numericOnly: isChartTool || isCompassTool || isGaugeTool,
        primaryAxisBaseUnit: primaryAxisBaseUnit,
        secondaryAxisBaseUnit: secondaryAxisBaseUnit,
        showBaseUnitInLabel: isChartTool,
        requiredCategory: isCompassTool ? 'angle' : null,
        allowAISContext: allowAIS,
        onSelectWithContext: (allowAIS || _selectedToolTypeId == 'historical_chart')
            ? (path, vesselContext) {
                selectedPath = path;
                selectedVesselContext = vesselContext;
              }
            : null,
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
      // Get unitKey for chart tools (for axis assignment persistence)
      final baseUnit = isChartTool
          ? ChartAxisUtils.getUnitKey(selectedPath!, signalKService.metadataStore)
          : null;

      setState(() {
        _dataSources.add(DataSource(
          path: selectedPath!,
          source: config['source'] as String?,
          label: config['label'] as String?,
          baseUnit: baseUnit,
          vesselContext: selectedVesselContext,
        ));
      });
    }
  }

  void _removeDataSource(int index) {
    setState(() {
      _dataSources.removeAt(index);
    });
  }

  /// Build a display label for a vessel context URN (e.g., "⭐ WILLIAM F FALLON JR (367073820)").
  String _vesselContextLabel(String vesselContext) {
    final signalKService = Provider.of<SignalKService>(context, listen: false);
    final vessel = signalKService.aisVesselRegistry.vessels[vesselContext];
    final mmsi = RegExp(r'(\d{9})').firstMatch(vesselContext)?.group(1);

    // Check favorites
    try {
      final favService = context.read<AISFavoritesService>();
      if (mmsi != null && favService.isFavorite(mmsi)) {
        final fav = favService.favorites.firstWhere((f) => f.mmsi == mmsi);
        return '⭐ ${fav.name} ($mmsi)';
      }
    } catch (_) {}

    if (vessel?.name != null) {
      return mmsi != null ? '${vessel!.name} ($mmsi)' : vessel!.name!;
    }
    return mmsi != null ? 'MMSI $mmsi' : vesselContext;
  }

  // NOTE: _loadSignalKWebApps() method removed - WebViewConfigurator handles this now

  void _editDataSource(int index) async {
    final dataSource = _dataSources[index];
    final signalKService = Provider.of<SignalKService>(context, listen: false);

    // Tool types that support AIS vessel context
    const aisContextTools = {
      'radial_gauge', 'linear_gauge', 'compass', 'text_display', 'position_display', 'realtime_chart', 'historical_chart',
    };
    final allowAIS = aisContextTools.contains(_selectedToolTypeId);

    final isChartToolEdit = _selectedToolTypeId == 'realtime_chart' ||
                            _selectedToolTypeId == 'historical_chart';
    final isCompassToolEdit = _selectedToolTypeId == 'compass';
    final isGaugeToolEdit = _selectedToolTypeId == 'radial_gauge' ||
                            _selectedToolTypeId == 'linear_gauge';

    await showDialog(
      context: context,
      builder: (context) => _EditDataSourceDialog(
        dataSource: dataSource,
        signalKService: signalKService,
        slotMode: _isSlotMode,
        allowAISContext: allowAIS,
        useHistoricalPaths: _selectedToolTypeId == 'historical_chart',
        numericOnly: isChartToolEdit || isCompassToolEdit || isGaugeToolEdit,
        showBaseUnitInLabel: isChartToolEdit,
        requiredCategory: isCompassToolEdit ? 'angle' : null,
        onSave: (newPath, newSource, newLabel, newVesselContext) {
          setState(() {
            _dataSources[index] = DataSource(
              path: newPath ?? dataSource.path,
              source: newSource,
              label: newLabel?.trim().isEmpty == true ? null : newLabel,
              baseUnit: dataSource.baseUnit,
              color: dataSource.color,
              vesselContext: newVesselContext,
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
    // Tools without data sources don't need them to save
    if (_selectedToolTypeId == null) return;
    final requiresDataSources = ToolRegistry().getDefinition(_selectedToolTypeId!)?.configSchema.allowsDataSources ?? true;
    if (requiresDataSources && _dataSources.isEmpty) return;

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
      aisMaxRangeMeters: 5.0 * NavigationConstants.metersPerNauticalMile,
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

    // Inject toolId into customProperties for self-reference
    final propsWithId = {
      ...?tool.config.style.customProperties,
      '_toolId': tool.id,
    };
    final toolWithId = tool.copyWith(
      config: ToolConfig(
        vesselId: tool.config.vesselId,
        dataSources: tool.config.dataSources,
        style: StyleConfig(
          minValue: tool.config.style.minValue,
          maxValue: tool.config.style.maxValue,
          unit: tool.config.style.unit,
          primaryColor: tool.config.style.primaryColor,
          secondaryColor: tool.config.style.secondaryColor,
          showLabel: tool.config.style.showLabel,
          showValue: tool.config.style.showValue,
          showUnit: tool.config.style.showUnit,
          ttlSeconds: tool.config.style.ttlSeconds,
          laylineAngle: tool.config.style.laylineAngle,
          targetTolerance: tool.config.style.targetTolerance,
          customProperties: propsWithId,
        ),
      ),
    );

    // Save the tool
    await toolService.saveTool(toolWithId);

    if (mounted) {
      // Return both tool and size
      Navigator.of(context).pop({
        'tool': toolWithId,
        'width': _toolWidth,
        'height': _toolHeight,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final registry = ToolRegistry();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingTool == null ? 'Add Tool' : 'Edit Tool'),
        actions: [
          TextButton.icon(
            onPressed: _selectedToolTypeId != null && (_dataSources.isNotEmpty || !(registry.getDefinition(_selectedToolTypeId!)?.configSchema.allowsDataSources ?? true))
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
            // Data Source Configuration
            if (registry.getDefinition(_selectedToolTypeId ?? '')?.configSchema.allowsDataSources ?? true)
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
                          final slots = _slotDefinitions;
                          final inSlotMode = slots != null;

                          // Role labels: prefer slot definitions, fall back to hardcoded
                          String? roleLabel;
                          if (slots != null && index < slots.length) {
                            roleLabel = slots[index].roleLabel;
                          } else if (_selectedToolTypeId == 'polar_radar_chart') {
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
                          final isSlotEmpty = inSlotMode && ds.path.isEmpty;
                          final slotIsRequired = inSlotMode && index < slots.length && slots[index].required;

                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isSlotEmpty
                                    ? Colors.grey.shade700
                                    : null,
                                child: isWebView
                                    ? const Icon(Icons.web, size: 18)
                                    : Text('${index + 1}'),
                              ),
                              title: Text(
                                isWebView
                                    ? 'Web Page'
                                    : inSlotMode
                                        ? (roleLabel ?? ds.path.split('.').last)
                                        : isSlotEmpty
                                            ? '(empty)'
                                            : (ds.label ?? ds.path.split('.').last),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(isWebView ? (ds.label ?? 'No URL') : (isSlotEmpty ? 'Tap edit to assign a path' : ds.path)),
                                  if (ds.vesselContext != null)
                                    Text(
                                      _vesselContextLabel(ds.vesselContext!),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(context).colorScheme.tertiary,
                                      ),
                                    ),
                                  if (!inSlotMode && roleLabel != null)
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
                                  if (inSlotMode) ...[
                                    // Clear button instead of delete (only for non-required, non-empty slots)
                                    if (!slotIsRequired && !isSlotEmpty)
                                      IconButton(
                                        icon: const Icon(Icons.clear),
                                        tooltip: 'Clear this slot',
                                        onPressed: () {
                                          setState(() {
                                            _dataSources[index] = DataSource(
                                              path: '',
                                            );
                                          });
                                        },
                                      ),
                                  ] else ...[
                                    IconButton(
                                      icon: const Icon(Icons.delete),
                                      onPressed: () => _removeDataSource(index),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 16),
                    // Add button (hidden in slot mode)
                    if (!_isSlotMode && _canAddMoreDataSources())
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: _addDataSource,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Path'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Style Configuration
            if (_selectedToolTypeId != null && (registry.getDefinition(_selectedToolTypeId!)?.configSchema.allowsStyleConfig ?? true))
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

            // Preview (show when data sources configured, or tool doesn't need them)
            if (_selectedToolTypeId != null && (_dataSources.isNotEmpty || !(registry.getDefinition(_selectedToolTypeId!)?.configSchema.allowsDataSources ?? true)) && _selectedToolTypeId != 'server_manager')
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
                              aisMaxRangeMeters: 5.0 * NavigationConstants.metersPerNauticalMile,
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
    if (schema.allowsUnitSelection) {
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
      if (schema.allowsSecondaryColor) {
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
    if (schema.allowsVisibilityToggles) {
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
    if (schema.allowsTTL) {
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
          initialValue: _hoursToShow,
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
  final Function(String?, String?, String?, String?) onSave; // (newPath, newSource, newLabel, newVesselContext)
  final bool slotMode;
  final bool allowAISContext;
  final bool useHistoricalPaths;
  final bool numericOnly;
  final bool showBaseUnitInLabel;
  final String? requiredCategory;

  const _EditDataSourceDialog({
    required this.dataSource,
    required this.signalKService,
    required this.onSave,
    this.slotMode = false,
    this.allowAISContext = false,
    this.useHistoricalPaths = false,
    this.numericOnly = false,
    this.showBaseUnitInLabel = false,
    this.requiredCategory,
  });

  @override
  State<_EditDataSourceDialog> createState() => _EditDataSourceDialogState();
}

class _EditDataSourceDialogState extends State<_EditDataSourceDialog> {
  late String _newPath;
  late String? _newSource;
  late String? _newLabel;
  late String? _newVesselContext;

  @override
  void initState() {
    super.initState();
    _newPath = widget.dataSource.path;
    _newSource = widget.dataSource.source;
    _newLabel = widget.dataSource.label;
    _newVesselContext = widget.dataSource.vesselContext;
  }

  Future<void> _selectPath() async {
    await showDialog(
      context: context,
      builder: (context) => PathSelectorDialog(
        signalKService: widget.signalKService,
        allowAISContext: widget.allowAISContext,
        useHistoricalPaths: widget.useHistoricalPaths,
        numericOnly: widget.numericOnly,
        showBaseUnitInLabel: widget.showBaseUnitInLabel,
        requiredCategory: widget.requiredCategory,
        initialVesselContext: widget.allowAISContext ? _newVesselContext : null,
        onSelectWithContext: (widget.allowAISContext || widget.useHistoricalPaths)
            ? (path, vesselContext) {
                setState(() {
                  _newPath = path;
                  _newVesselContext = vesselContext;
                });
              }
            : null,
        onSelect: (path) {
          setState(() {
            _newPath = path;
          });
        },
      ),
    );
  }

  Future<void> _selectSource() async {
    await showDialog(
      context: context,
      builder: (context) => SourceSelectorDialog(
        signalKService: widget.signalKService,
        path: _newPath,
        currentSource: _newSource,
        vesselContext: _newVesselContext,
        onSelect: (source) {
          setState(() {
            _newSource = source;
          });
        },
      ),
    );
  }

  /// Build a display label for a vessel context URN.
  String _vesselContextLabel(String vesselContext) {
    final vessel = widget.signalKService.aisVesselRegistry.vessels[vesselContext];
    final mmsi = RegExp(r'(\d{9})').firstMatch(vesselContext)?.group(1);

    // Check favorites
    AISFavoritesService? favService;
    try {
      favService = context.read<AISFavoritesService>();
    } catch (_) {}
    if (mmsi != null && favService != null && favService.isFavorite(mmsi)) {
      final fav = favService.favorites.firstWhere((f) => f.mmsi == mmsi);
      return '${fav.name} ($mmsi)';
    }

    if (vessel?.name != null) {
      return mmsi != null ? '${vessel!.name} ($mmsi)' : vessel!.name!;
    }
    return mmsi != null ? 'MMSI $mmsi' : vesselContext;
  }

  @override
  Widget build(BuildContext context) {
    final displayPath = _newPath.isEmpty ? '(none)' : _newPath;
    return AlertDialog(
      title: Text('Edit ${widget.dataSource.label ?? widget.dataSource.path}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Path selection
          ListTile(
            leading: const Icon(Icons.route),
            title: const Text('Path'),
            subtitle: Text(displayPath),
            trailing: const Icon(Icons.edit),
            onTap: _selectPath,
          ),
          // Vessel context indicator
          if (_newVesselContext != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.directions_boat, size: 14, color: Colors.blue[400]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _vesselContextLabel(_newVesselContext!),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[400],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(),
          // Source selection
          ListTile(
            leading: const Icon(Icons.sensors),
            title: const Text('Data Source'),
            subtitle: Text(_newSource ?? 'Auto'),
            trailing: const Icon(Icons.edit),
            onTap: _newPath.isNotEmpty ? _selectSource : null,
          ),
          if (!widget.slotMode) ...[
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            widget.onSave(_newPath, _newSource, _newLabel, _newVesselContext);
            Navigator.of(context).pop();
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
