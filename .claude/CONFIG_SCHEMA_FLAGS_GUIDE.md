# ConfigSchema Flags Guide

How each tool declares which config screen sections it supports, using boolean flags on `ConfigSchema` in `lib/models/tool_definition.dart`.

## The Flags

| Flag | Default | Controls |
|------|---------|----------|
| `allowsDataSources` | `true` | "Configure Data Sources" card (SignalK path picker) + save button/validation |
| `allowsStyleConfig` | `true` | "Configure Style" card (wraps unit, color, toggles, TTL, and custom configurator) |
| `allowsUnitSelection` | `true` | "Unit" text field inside style card |
| `allowsSecondaryColor` | `false` | Secondary color picker (only shown when `allowsColorCustomization` is also true) |
| `allowsVisibilityToggles` | `true` | Show Label / Show Value / Show Unit switches |
| `allowsTTL` | `true` | "Data Staleness Threshold" dropdown |

Pre-existing flags that work the same way:

| Flag | Default | Controls |
|------|---------|----------|
| `allowsMinMax` | `true` | Min/Max value fields |
| `allowsColorCustomization` | `true` | Primary color picker (and gate for secondary color) |

## Where They're Read

All flags are checked in `lib/screens/tool_config_screen.dart`:

- `allowsDataSources` — controls the data sources card visibility, save button enablement, and save validation
- `allowsStyleConfig` — controls the entire style card visibility
- `allowsUnitSelection`, `allowsSecondaryColor`, `allowsVisibilityToggles`, `allowsTTL` — checked inside `_buildStyleOptions()` on the `schema` variable

## How to Set Flags

Set flags in your tool builder's `getDefinition()` method, on the `ConfigSchema` constructor:

```dart
class MyToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'my_tool',
      name: 'My Tool',
      description: 'Does something',
      category: ToolCategory.instruments,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 1,
        maxPaths: 1,
        // Flags — only set the ones that differ from defaults
        allowsDataSources: false,   // no path picker
        allowsUnitSelection: false, // no unit field
        allowsTTL: false,           // no staleness dropdown
        allowsSecondaryColor: true, // show secondary color picker
      ),
    );
  }
}
```

Only set flags that differ from their defaults. Most tools use all defaults and need no flags at all.

## Common Patterns

### Standard data tool (gauge, chart, text display)

No flags needed — all defaults are correct.

### System tool with no data, no style, no TTL

Tools like `server_manager`, `crew_messages`, `crew_list`, `intercom`, `file_share`:

```dart
ConfigSchema(
  allowsDataSources: false,
  allowsStyleConfig: false,
  allowsTTL: false,
)
```

### Complex tool with own configurator (autopilot, wind compass, tanks)

These have custom configurators for style but don't use the standard unit/toggles/TTL fields:

```dart
ConfigSchema(
  allowsUnitSelection: false,
  allowsVisibilityToggles: false,
  allowsTTL: false,
)
```

Keep `allowsStyleConfig: true` (the default) — setting it to `false` would hide the entire style card including your custom configurator.

### Tool with secondary color (switch, checkbox, windsteer)

```dart
ConfigSchema(
  allowsColorCustomization: true,  // required — gates the color section
  allowsSecondaryColor: true,      // adds secondary color picker
)
```

### Self-contained tool with no config at all

Tools like `rpi_monitor`, `system_monitor`:

```dart
ConfigSchema(
  allowsDataSources: false,
  allowsStyleConfig: false,
)
```

## Important Notes

- All 6 flags are `@JsonKey(includeFromJson: false, includeToJson: false)` — they are code-only and never serialized. Saved tool configs are unaffected.
- `allowsSecondaryColor` only takes effect when `allowsColorCustomization` is also `true`.
- Setting `allowsStyleConfig: false` hides the entire style card — including any custom configurator rendered inside it. Only set this for tools with zero style configuration.
- When `allowsDataSources: false`, the save button and save validation automatically allow saving without data sources.

## Current Flag Assignments

| Tool ID | DataSources | StyleConfig | UnitSelection | SecondaryColor | VisibilityToggles | TTL | MinMax |
|---------|:-----------:|:-----------:|:-------------:|:--------------:|:-----------------:|:---:|:------:|
| *standard instruments* | * | * | * | | * | * | * |
| text_display | * | * | * | | * | | |
| dropdown | * | * | * | | * | | * |
| knob | * | * | * | | * | | * |
| slider | * | * | * | | * | | * |
| radial_gauge | * | * | * | | * | | * |
| server_manager | | | * | | * | | |
| crew_messages | | | * | | * | | |
| crew_list | | | * | | * | | |
| intercom | | | * | | * | | |
| file_share | | | * | | * | | |
| device_access_manager | | | | | | | |
| system_monitor | | | * | | * | * | |
| rpi_monitor | | | * | | * | * | |
| conversion_test | * | | * | | * | * | |
| weather_alerts | | | * | | * | * | |
| webview | | * | | | | | |
| clock_alarm | | * | | | | | |
| weather_api_spinner | | * | | | | | |
| weatherflow_forecast | * | * | | | | | |
| victron_flow | | * | | | | | |
| sun_moon_arc | | * | | | | | |
| autopilot | * | * | | * | | | |
| autopilot_v2 | * | * | | | | | |
| autopilot_simple | * | * | | | | | |
| wind_compass | * | * | | * | | | |
| anchor_alarm | * | * | | | | | |
| position_display | * | * | | | | | |
| tanks | * | * | | | | * | |
| find_home | * | * | | | | | |
| switch | * | * | | * | | | |
| checkbox | * | * | | * | | | |
| windsteer | * | * | | * | | | |
| forecast_spinner | * | * | | | | | |
| ais_polar_chart | * | * | | | | | |
| gnss_status | * | * | | | | | |
| polar_radar_chart | * | * | | | | | |
| realtime_chart | * | * | | | | | |
| historical_chart | * | * | | | | | |
| attitude_indicator | * | * | | | | | |
| radial_bar_chart | * | * | | | | | |
| compass_gauge | * | * | | | | | |

`*` = feature enabled, blank = disabled
