# Creating New Tools - Developer Guide

**ZedDisplay Tool Development Guide**
**Version**: 2.0 (Post-Refactoring)
**Last Updated**: October 28, 2025

---

## Table of Contents

1. [Overview](#overview)
2. [Tool Architecture](#tool-architecture)
3. [Quick Start](#quick-start)
4. [Step-by-Step Guide](#step-by-step-guide)
5. [Tool Configuration System](#tool-configuration-system)
6. [Widget Implementation](#widget-implementation)
7. [Examples](#examples)
8. [Best Practices](#best-practices)
9. [Testing](#testing)

---

## Overview

ZedDisplay uses a modular tool system that allows developers to create custom visualization and control widgets for SignalK marine data. Each tool is a self-contained component that can be placed on dashboards and configured by end users.

### What is a Tool?

A **tool** is a widget that:
- Displays or controls marine data from SignalK
- Can be configured by the user (data sources, appearance, behavior)
- Can be placed on multiple dashboards
- Has a reusable definition and configuration

### Tool System Components

```
Tool Definition (ToolDefinition)
    ↓
Tool Configuration (ToolConfig)
    ↓
Tool Configurator (ToolConfigurator) ← NEW in v2.0
    ↓
Tool Widget (e.g., RadialGaugeTool)
```

---

## Tool Architecture

### Core Classes

#### 1. ToolDefinition (`lib/models/tool_definition.dart`)

Defines the **metadata** about a tool type:

```dart
class ToolDefinition {
  final String id;                    // Unique identifier (e.g., 'radial_gauge')
  final String name;                  // Display name
  final String description;           // What it does
  final IconData icon;                // Icon to show in UI
  final ToolCategory category;        // gauge, chart, control, system, etc.
  final ToolConfigSchema configSchema; // What can be configured
  final int defaultWidth;             // Default grid width
  final int defaultHeight;            // Default grid height
}
```

#### 2. Tool (`lib/models/tool.dart`)

An **instance** of a tool with specific configuration:

```dart
class Tool {
  final String id;                    // Unique instance ID
  final String name;                  // User-given name
  final String toolTypeId;            // References ToolDefinition.id
  final ToolConfig config;            // Configuration for this instance
}
```

#### 3. ToolConfig (`lib/models/tool_config.dart`)

Configuration for a tool instance:

```dart
class ToolConfig {
  final List<DataSource> dataSources; // What data to show
  final ToolStyle style;              // How to display it
  final int? refreshRate;             // Update frequency
}
```

#### 4. ToolConfigurator (`lib/screens/tool_config/base_tool_configurator.dart`) **NEW**

Handles tool-specific configuration UI (Strategy pattern):

```dart
abstract class ToolConfigurator {
  // Build configuration UI
  Widget buildConfigUI(BuildContext context, SignalKService signalKService);

  // Get configuration values
  Map<String, dynamic> getConfigValues();

  // Load existing configuration
  void loadConfig(Map<String, dynamic> config);

  // Reset to defaults
  void reset();
}
```

---

## Quick Start

### Creating a Simple Tool (5 Steps)

1. **Define the tool** in `ToolRegistry`
2. **Create the widget** in `lib/widgets/tools/`
3. **Add configurator** (if custom config needed) in `lib/screens/tool_config/configurators/`
4. **Register configurator** in `ToolConfiguratorFactory`
5. **Test and document**

**Time estimate**: 2-4 hours for a simple tool

---

## Step-by-Step Guide

### Step 1: Define the Tool

Edit `lib/services/tool_registry.dart`:

```dart
ToolDefinition(
  id: 'my_custom_gauge',              // Unique ID (use snake_case)
  name: 'My Custom Gauge',            // Display name
  description: 'A custom gauge for displaying boat speed with custom styling',
  icon: Icons.speed,                  // Choose from Material Icons
  category: ToolCategory.gauge,       // gauge, chart, control, system
  configSchema: ToolConfigSchema(
    requiredDataSources: 1,           // Minimum data sources
    maxDataSources: 1,                // Maximum data sources
    allowsMinMax: true,               // Can configure min/max values?
    allowsColorCustomization: true,   // Can change colors?
    allowsUnitSelection: true,        // Can change units?
    customProperties: {               // Tool-specific properties
      'showPointer': true,
      'gaugeStyle': 'arc',            // Options: 'arc', 'circle', 'semicircle'
    },
  ),
  defaultWidth: 2,                    // Grid columns (1-12)
  defaultHeight: 2,                   // Grid rows (1-12)
),
```

### Step 2: Create the Widget

Create `lib/widgets/tools/my_custom_gauge_tool.dart`:

```dart
import 'package:flutter/material.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';

class MyCustomGaugeTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const MyCustomGaugeTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Get the data source
    if (config.dataSources.isEmpty) {
      return const Center(child: Text('No data source configured'));
    }

    final dataSource = config.dataSources.first;

    // 2. Get the current value from SignalK
    final dataPoint = signalKService.getValue(
      dataSource.path,
      source: dataSource.source,
    );

    // 3. Extract the value
    final value = dataPoint?.value as double?;

    // 4. Get style configuration
    final style = config.style;
    final minValue = style.minValue ?? 0.0;
    final maxValue = style.maxValue ?? 10.0;
    final unit = style.unit ?? '';
    final showPointer = style.customProperties?['showPointer'] as bool? ?? true;

    // 5. Build your UI
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Your custom gauge visualization here
            Text(
              '${value?.toStringAsFixed(1) ?? '--'} $unit',
              style: Theme.of(context).textTheme.headlineMedium,
            ),

            // Progress indicator example
            LinearProgressIndicator(
              value: value != null
                ? (value - minValue) / (maxValue - minValue)
                : 0.0,
            ),
          ],
        ),
      ),
    );
  }
}
```

### Step 3: Register the Widget

Edit `lib/services/tool_registry.dart` - Add to widget factory:

```dart
Widget? createWidget(String toolTypeId, ToolConfig config, SignalKService signalKService) {
  switch (toolTypeId) {
    // ... existing cases ...

    case 'my_custom_gauge':
      return MyCustomGaugeTool(
        config: config,
        signalKService: signalKService,
      );

    // ... rest of cases ...
  }
}
```

### Step 4: Create a Configurator (Optional but Recommended)

Create `lib/screens/tool_config/configurators/my_custom_gauge_configurator.dart`:

```dart
import 'package:flutter/material.dart';
import '../base_tool_configurator.dart';
import '../../../services/signalk_service.dart';

class MyCustomGaugeConfigurator extends ToolConfigurator {
  // State variables for your custom properties
  bool _showPointer = true;
  String _gaugeStyle = 'arc';

  @override
  Widget buildConfigUI(BuildContext context, SignalKService signalKService) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Text(
          'Gauge Options',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),

        // Show pointer toggle
        SwitchListTile(
          title: const Text('Show Pointer'),
          subtitle: const Text('Display a pointer on the gauge'),
          value: _showPointer,
          onChanged: (value) {
            // Use setState from parent if needed, or handle in StatefulWidget
            _showPointer = value;
          },
        ),

        // Gauge style dropdown
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Gauge Style',
            border: OutlineInputBorder(),
          ),
          value: _gaugeStyle,
          items: const [
            DropdownMenuItem(value: 'arc', child: Text('Arc (180°)')),
            DropdownMenuItem(value: 'circle', child: Text('Full Circle')),
            DropdownMenuItem(value: 'semicircle', child: Text('Semi Circle')),
          ],
          onChanged: (value) {
            if (value != null) {
              _gaugeStyle = value;
            }
          },
        ),
      ],
    );
  }

  @override
  Map<String, dynamic> getConfigValues() {
    return {
      'showPointer': _showPointer,
      'gaugeStyle': _gaugeStyle,
    };
  }

  @override
  void loadConfig(Map<String, dynamic> config) {
    _showPointer = config['showPointer'] as bool? ?? true;
    _gaugeStyle = config['gaugeStyle'] as String? ?? 'arc';
  }

  @override
  void reset() {
    _showPointer = true;
    _gaugeStyle = 'arc';
  }
}
```

### Step 5: Register the Configurator

Edit `lib/screens/tool_config/tool_configurator_factory.dart`:

```dart
class ToolConfiguratorFactory {
  static ToolConfigurator? create(String toolTypeId) {
    switch (toolTypeId) {
      // ... existing cases ...

      case 'my_custom_gauge':
        return MyCustomGaugeConfigurator();

      // ... rest of cases ...
    }
  }

  static List<String> getConfiguratorToolTypes() {
    return [
      // ... existing types ...
      'my_custom_gauge',
      // ... rest of types ...
    ];
  }
}
```

---

## Tool Configuration System

### Understanding ToolConfigSchema

The schema defines what can be configured:

```dart
ToolConfigSchema(
  requiredDataSources: 1,      // At least 1 data source required
  maxDataSources: 4,           // Up to 4 data sources allowed
  allowsMinMax: true,          // User can set min/max values
  allowsColorCustomization: true, // User can change colors
  allowsUnitSelection: true,   // User can change units
  customProperties: {          // Tool-specific defaults
    'chartStyle': 'line',
    'showLegend': true,
  },
)
```

### Custom Properties

Store tool-specific configuration in `customProperties`:

```dart
// In your tool widget, access custom properties:
final chartStyle = config.style.customProperties?['chartStyle'] as String? ?? 'line';
final showLegend = config.style.customProperties?['showLegend'] as bool? ?? true;
```

### Data Source Configuration

```dart
// Single data source
if (config.dataSources.isEmpty) return const Text('No data');
final dataSource = config.dataSources.first;

// Multiple data sources
for (var i = 0; i < config.dataSources.length; i++) {
  final dataSource = config.dataSources[i];
  final value = signalKService.getValue(dataSource.path);
  // ... use value
}
```

---

## Widget Implementation

### Best Practices

#### 1. Handle Missing Data Gracefully

```dart
final value = signalKService.getValue(dataSource.path);

if (value == null) {
  return const Center(
    child: Text('--', style: TextStyle(fontSize: 24)),
  );
}
```

#### 2. Check Data Staleness

```dart
final dataPoint = signalKService.getValue(dataSource.path);

// Check if data is stale (using TTL)
final isStale = config.style.ttlSeconds != null &&
    dataPoint != null &&
    DateTime.now().difference(dataPoint.timestamp).inSeconds >
    config.style.ttlSeconds!;

if (isStale) {
  return const Text('--', style: TextStyle(color: Colors.grey));
}
```

#### 3. Use Card Wrapper for Consistency

```dart
@override
Widget build(BuildContext context) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: YourContent(),
    ),
  );
}
```

#### 4. Support Dark/Light Themes

```dart
final theme = Theme.of(context);
final textColor = theme.textTheme.bodyLarge?.color;
final backgroundColor = theme.cardColor;
```

#### 5. Listen to SignalK Updates

For real-time updates:

```dart
class MyGaugeTool extends StatefulWidget {
  // ...
}

class _MyGaugeToolState extends State<MyGaugeTool> {
  @override
  void initState() {
    super.initState();
    widget.signalKService.addListener(_onDataUpdate);
  }

  @override
  void dispose() {
    widget.signalKService.removeListener(_onDataUpdate);
    super.dispose();
  }

  void _onDataUpdate() {
    setState(() {}); // Rebuild when data changes
  }

  @override
  Widget build(BuildContext context) {
    // ... your build code
  }
}
```

---

## Examples

### Example 1: Simple Display Tool

A tool that displays text data:

```dart
class SimpleTextTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const SimpleTextTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  Widget build(BuildContext context) {
    final dataSource = config.dataSources.firstOrNull;
    if (dataSource == null) {
      return const Card(child: Center(child: Text('No data source')));
    }

    final dataPoint = signalKService.getValue(dataSource.path);
    final value = dataPoint?.value;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              dataSource.label ?? 'Value',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              value?.toString() ?? '--',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
          ],
        ),
      ),
    );
  }
}
```

### Example 2: Multi-Source Tool

A tool that displays multiple data points:

```dart
class MultiValueTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const MultiValueTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListView.builder(
        padding: const EdgeInsets.all(8.0),
        itemCount: config.dataSources.length,
        itemBuilder: (context, index) {
          final dataSource = config.dataSources[index];
          final dataPoint = signalKService.getValue(dataSource.path);
          final value = dataPoint?.value;

          return ListTile(
            title: Text(dataSource.label ?? dataSource.path),
            trailing: Text(
              value?.toString() ?? '--',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          );
        },
      ),
    );
  }
}
```

### Example 3: Interactive Control Tool

A tool that sends commands to SignalK:

```dart
class ButtonControlTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const ButtonControlTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  Future<void> _sendCommand(String path, dynamic value) async {
    try {
      await signalKService.sendPutRequest(path, value);
    } catch (e) {
      debugPrint('Error sending command: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataSource = config.dataSources.firstOrNull;
    if (dataSource == null) {
      return const Card(child: Center(child: Text('No data source')));
    }

    final buttonValue = config.style.customProperties?['buttonValue'] ?? true;
    final buttonLabel = config.style.customProperties?['buttonLabel'] as String? ?? 'Toggle';

    return Card(
      child: Center(
        child: ElevatedButton(
          onPressed: () => _sendCommand(dataSource.path, buttonValue),
          child: Text(buttonLabel),
        ),
      ),
    );
  }
}
```

---

## Best Practices

### 1. Error Handling

Always handle errors gracefully:

```dart
try {
  final value = dataPoint?.value as double?;
  // ... use value
} catch (e) {
  debugPrint('Error parsing value: $e');
  return const Text('Error');
}
```

### 2. Performance

- Use `const` constructors where possible
- Avoid rebuilding unnecessarily
- For expensive widgets, use `AutomaticKeepAliveClientMixin`

```dart
class _MyToolState extends State<MyTool> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    // ... rest of build
  }
}
```

### 3. Null Safety

Always check for null values:

```dart
final dataSource = config.dataSources.firstOrNull; // Use firstOrNull
if (dataSource == null) return const Text('No data source');

final value = dataPoint?.value as double?; // Safe cast
```

### 4. Configuration Defaults

Always provide sensible defaults:

```dart
final minValue = config.style.minValue ?? 0.0;
final maxValue = config.style.maxValue ?? 100.0;
final unit = config.style.unit ?? '';
final showLabel = config.style.showLabel ?? true;
```

### 5. Documentation

Document your tool's:
- Purpose and use cases
- Required data sources and paths
- Custom properties and their effects
- Configuration examples

---

## Testing

### Manual Testing Checklist

- [ ] Tool appears in tool palette
- [ ] Can be added to dashboard
- [ ] Can be configured via ToolConfigScreen
- [ ] Displays data correctly
- [ ] Handles missing data gracefully
- [ ] Handles stale data (TTL)
- [ ] Respects dark/light theme
- [ ] Resizes properly in grid
- [ ] Configuration persists after save
- [ ] Works with multiple instances

### Test with Various Data

```dart
// Test with different data types
final testCases = {
  'number': 42.5,
  'string': 'Hello',
  'boolean': true,
  'null': null,
  'object': {'lat': 37.7749, 'lon': -122.4194},
};
```

### Common Issues

1. **Tool not appearing in palette**
   - Check `ToolRegistry` definition exists
   - Verify `id` is unique
   - Check `category` is valid

2. **Configuration not saving**
   - Verify configurator implements all methods
   - Check `getConfigValues()` returns correct map
   - Ensure factory is registered

3. **Data not updating**
   - Add listener to `signalKService`
   - Call `setState()` on updates
   - Check data path is correct

---

## Tool Categories

### Available Categories

```dart
enum ToolCategory {
  gauge,      // Radial gauge, linear gauge, text display
  chart,      // Line charts, bar charts, historical data
  display,    // Text displays, status indicators
  control,    // Buttons, sliders, switches
  instrument, // Compass, wind instruments
  system,     // System monitors, diagnostics
}
```

### Choosing a Category

- **gauge**: Single-value displays with visual indication
- **chart**: Time-series or multi-value visualizations
- **display**: Simple text/status displays
- **control**: Interactive elements that send commands
- **instrument**: Specialized marine instruments
- **system**: System monitoring and diagnostics

---

## Advanced Topics

### Custom Configurator with StatefulWidget

For complex configuration UI:

```dart
class MyConfiguratorWidget extends StatefulWidget {
  final MyConfigurator configurator;

  const MyConfiguratorWidget({super.key, required this.configurator});

  @override
  State<MyConfiguratorWidget> createState() => _MyConfiguratorWidgetState();
}

class _MyConfiguratorWidgetState extends State<MyConfiguratorWidget> {
  late bool _option;

  @override
  void initState() {
    super.initState();
    _option = widget.configurator.option;
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: _option,
      onChanged: (value) {
        setState(() {
          _option = value;
          widget.configurator.option = value;
        });
      },
    );
  }
}
```

### Using SignalK Conversions

Get converted values with units:

```dart
final convertedValue = signalKService.getConvertedValue(
  dataSource.path,
  targetUnit: 'knots', // Optional: specific unit
);

// Get available units for a path
final units = signalKService.getAvailableUnits(dataSource.path);

// Get conversion info
final info = signalKService.getConversionInfo(dataSource.path, 'knots');
final symbol = info?.symbol ?? '';
```

### Accessing Multiple Vessel Contexts

```dart
// Access other vessels (AIS)
final vesselPath = 'vessels.urn:mrn:imo:mmsi:123456789.navigation.position';
final vesselData = signalKService.getValue(vesselPath);

// Own vessel
final ownPath = 'vessels.self.navigation.position';
final ownData = signalKService.getValue(ownPath);
```

---

## Resources

### Key Files to Reference

- `lib/services/tool_registry.dart` - Tool definitions
- `lib/models/tool_definition.dart` - Tool metadata model
- `lib/models/tool_config.dart` - Tool configuration model
- `lib/screens/tool_config/base_tool_configurator.dart` - Configurator base class
- `lib/screens/tool_config/tool_configurator_factory.dart` - Configurator factory
- `lib/widgets/tools/` - Example tool widgets

### Example Tools to Study

- **Simple**: `lib/widgets/tools/text_display_tool.dart`
- **Gauge**: `lib/widgets/tools/radial_gauge_tool.dart`
- **Chart**: `lib/widgets/tools/historical_chart_tool.dart`
- **Control**: `lib/widgets/tools/button_tool.dart`
- **Complex**: `lib/widgets/tools/wind_compass_tool.dart`

### SignalK Documentation

- [SignalK Specification](https://signalk.org/specification/)
- [SignalK Data Model](https://signalk.org/specification/latest/doc/data_model.html)
- [Common Paths](https://signalk.org/specification/latest/doc/keys.html)

---

## Troubleshooting

### Debug Checklist

1. **Enable debug logging**
   ```dart
   debugPrint('Tool value: $value');
   ```

2. **Check SignalK connection**
   ```dart
   if (!signalKService.isConnected) {
     return const Text('Not connected');
   }
   ```

3. **Verify data path**
   ```dart
   final allData = signalKService.latestData;
   debugPrint('Available paths: ${allData.keys}');
   ```

4. **Test configuration**
   ```dart
   debugPrint('Config: ${config.toJson()}');
   ```

---

## Support

For questions or issues:
1. Check existing tools in `lib/widgets/tools/`
2. Review configurators in `lib/screens/tool_config/configurators/`
3. Consult the comprehensive code review: `docs/CODE_REVIEW_COMPREHENSIVE_2025-10-28.md`

---

**Happy Tool Development!** 🚢⚓️
