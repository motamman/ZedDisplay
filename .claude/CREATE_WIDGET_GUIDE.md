# Creating a Dashboard Widget (Tool)

Guide to adding a new dashboard tool to ZedDisplay. A "tool" is a widget that users can place on their dashboard grid.

## Files You Need

| File | Purpose |
|------|---------|
| `lib/widgets/tools/<name>_tool.dart` | Tool widget + `ToolBuilder` subclass |
| `lib/screens/tool_config/configurators/<name>_configurator.dart` | Custom config UI (optional) |

## Files You Modify

| File | What to add |
|------|-------------|
| `lib/services/tool_registry.dart` | Import + `register('tool_id', YourToolBuilder())` in `registerDefaults()` |
| `lib/screens/tool_config/tool_configurator_factory.dart` | Import + `case` in `create()` + add to `getConfiguratorToolTypes()` list |
| `lib/screens/tool_config_screen.dart` | Exclusion lists (see below) |

## Step 1: Tool Widget + Builder

```dart
import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../tool_info_button.dart';

class MyTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const MyTool({super.key, required this.config, required this.signalKService});

  @override
  State<MyTool> createState() => _MyToolState();
}

class _MyToolState extends State<MyTool> {
  @override
  void initState() {
    super.initState();
    // Subscribe to SignalK paths if needed:
    // widget.signalKService.subscribeToPaths(['some.path'], ownerId: 'my_tool');
  }

  @override
  void dispose() {
    // Unsubscribe:
    // widget.signalKService.unsubscribeFromPaths(['some.path'], ownerId: 'my_tool');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final props = widget.config.style.customProperties ?? {};
    // Read config: props['myOption'] as bool? ?? true

    return Stack(
      children: [
        // Your widget content here
        const Center(child: Text('My Tool')),

        // ToolInfoButton overlay (top-right)
        Positioned(
          top: 4,
          right: 4,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: ToolInfoButton(
              toolId: 'my_tool',
              signalKService: widget.signalKService,
              iconSize: 14,
              iconColor: Colors.white70,
            ),
          ),
        ),
      ],
    );
  }
}

class MyToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'my_tool',
      name: 'My Tool',
      description: 'Description shown in tool picker',
      category: ToolCategory.weather, // navigation, instruments, charts, weather, electrical, ais, controls, communication, system
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: false,
        minPaths: 0,  // 0 = no path selector needed
        maxPaths: 0,
        styleOptions: ['myOption'], // list of customProperties keys
      ),
      defaultWidth: 4,   // grid units
      defaultHeight: 2,
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      dataSources: const [],
      style: StyleConfig(
        customProperties: {
          'myOption': true,
        },
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return MyTool(config: config, signalKService: signalKService);
  }
}
```

## Step 2: Configurator (Optional)

Only needed if your tool has custom settings beyond path selection and color.

```dart
import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

class MyToolConfigurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'my_tool';

  @override
  Size get defaultSize => const Size(4, 2);

  // Config state
  bool myOption = true;

  @override
  void reset() { myOption = true; }

  @override
  void loadDefaults(SignalKService signalKService) { reset(); }

  @override
  void loadFromTool(Tool tool) {
    final props = tool.config.style.customProperties;
    if (props != null) {
      myOption = props['myOption'] as bool? ?? true;
    }
  }

  @override
  ToolConfig getConfig() {
    return ToolConfig(
      dataSources: const [],
      style: StyleConfig(customProperties: { 'myOption': myOption }),
    );
  }

  @override
  String? validate() => null;

  @override
  Widget buildConfigUI(BuildContext context, SignalKService signalKService) {
    return StatefulBuilder(
      builder: (context, setState) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('My Option'),
                value: myOption,
                onChanged: (v) => setState(() => myOption = v),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

## Step 3: Register

### `lib/services/tool_registry.dart`

```dart
import '../widgets/tools/my_tool.dart';
// ...
register('my_tool', MyToolBuilder());
```

### `lib/screens/tool_config/tool_configurator_factory.dart`

```dart
import 'configurators/my_tool_configurator.dart';
// In create():
case 'my_tool':
  return MyToolConfigurator();
// In getConfiguratorToolTypes():
'my_tool',
```

## Step 4: Config Screen Exclusions

`lib/screens/tool_config_screen.dart` has multiple hardcoded exclusion lists. If your tool doesn't need a standard section, add your tool ID to the relevant list(s). **All are in `tool_config_screen.dart`.**

### 1. Save button enabled (~line 622)

The Save button is disabled when `_dataSources.isEmpty` unless your tool is listed here. **If your tool has no paths, you MUST add it or Save stays greyed out.**

```dart
onPressed: _selectedToolTypeId != null && (_dataSources.isNotEmpty || _selectedToolTypeId == 'webview' || ... || _selectedToolTypeId == 'sun_moon_arc')
```

### 2. Save validation (~line 429)

Same concept — `_saveTool()` silently returns if data sources are empty unless your tool is listed. **Must match list #1.**

```dart
if (_selectedToolTypeId != 'webview' && ... && _selectedToolTypeId != 'sun_moon_arc' && _dataSources.isEmpty) return;
```

### 3. Data Sources card (~line 636)

Hides the "Configure Data Sources" card (the SignalK path picker). Add your tool if it doesn't use standard path selection.

```dart
if (_selectedToolTypeId != 'webview' && ... && _selectedToolTypeId != 'sun_moon_arc')
```

### 4. Standard style options inside `_buildStyleOptions()`

The "Configure Style" card renders both standard options AND your custom configurator. The card itself should NOT be excluded if you have a custom configurator. Instead, add your tool to the individual option exclusion lists within `_buildStyleOptions()`:

- **`excludeUnitOptions`** (~line 941): Hides the "Unit" text field
- **`excludeShowHideOptions`** (~line 1030): Hides Show Label / Show Value / Show Unit switches
- **`excludeTTLOptions`** (~line 1063): Hides the Data Staleness Threshold dropdown

```dart
const excludeUnitOptions = ['autopilot', ..., 'sun_moon_arc'];
const excludeShowHideOptions = ['autopilot', ..., 'sun_moon_arc'];
const excludeTTLOptions = ['autopilot', ..., 'sun_moon_arc'];
```

### Summary: No-path tool with custom configurator

If your tool has no SignalK paths and has its own configurator, add it to ALL of these:
1. Save button enabled list (line ~622)
2. Save validation list (line ~429)
3. Data Sources card exclusion (line ~636)
4. `excludeUnitOptions` (line ~941)
5. `excludeShowHideOptions` (line ~1030)
6. `excludeTTLOptions` (line ~1063)

Do NOT add it to the Style Config card exclusion (line ~782) — that would hide your custom configurator too.

## ToolCategory Options

| Category | Use for |
|----------|---------|
| `navigation` | Compass, autopilot, wind, anchor, position |
| `instruments` | Gauges, tanks, text displays |
| `charts` | Time-series: historical, realtime |
| `weather` | Forecasts, sun/moon, alerts |
| `electrical` | Power systems, Victron |
| `ais` | AIS, radar |
| `controls` | Switches, sliders, knobs |
| `communication` | Crew messages, intercom |
| `system` | Server admin, monitoring, clock |

## SignalK Subscription Pattern

Use owner-aware subscriptions so paths are properly ref-counted:

```dart
// Subscribe (in initState or when config changes)
signalKService.subscribeToPaths(['navigation.position'], ownerId: 'my_tool');

// Read values
final dataPoint = signalKService.getValue('navigation.position');

// Unsubscribe (in dispose)
signalKService.unsubscribeFromPaths(['navigation.position'], ownerId: 'my_tool');
```

## Unit Conversions

See `.claude/METADATA_STORE_GUIDE.md`. Never hardcode conversions — always use `MetadataStore`:

```dart
final metadata = signalKService.metadataStore.get(path);
final displayValue = metadata?.convert(rawValue);
final symbol = metadata?.symbol;
```
