# MIGRATION REPORT: ConversionUtils → MetadataStore

**Date:** 2026-02-28
**Status:** 14 files need migration

---

## Summary

| Priority | Count | Description |
|----------|-------|-------------|
| HIGH | 4 | Control widgets with PUT requests |
| MEDIUM | 6 | Display-only widgets |
| COMPLEX | 4 | Weather widgets with fallback logic |

---

## HIGH PRIORITY (Control widgets with PUT requests)

These need both read AND write conversion - critical to get right.

### 1. `tools/mixins/control_tool_mixin.dart`
**Lines:** 54
**Usage:** `ConversionUtils.convertToRaw()` for PUT
**Migration:**
```dart
// FROM:
final rawValue = ConversionUtils.convertToRaw(signalKService, path, roundedDisplayValue);

// TO:
final metadata = signalKService.metadataStore.get(path);
final rawValue = metadata?.convertToSI(roundedDisplayValue) ?? roundedDisplayValue;
```

### 2. `tools/slider_tool.dart`
**Lines:** 59
**Usage:** `ConversionUtils.getConvertedValue()` for display
**Migration:** Replace with `metadataStore.get(path)?.convert(rawValue)`

### 3. `tools/knob_tool.dart`
**Lines:** 57
**Usage:** `ConversionUtils.getConvertedValue()` for display
**Migration:** Replace with `metadataStore.get(path)?.convert(rawValue)`

### 4. `tools/dropdown_tool.dart`
**Lines:** 61
**Usage:** `ConversionUtils.getConvertedValue()` for display
**Migration:** Replace with `metadataStore.get(path)?.convert(rawValue)`

---

## MEDIUM PRIORITY (Display-only widgets)

### 5. `tools/text_display_tool.dart`
**Lines:** 51-52, 60
**Usage:**
- `ConversionUtils.getRawValue()`
- `ConversionUtils.getConvertedValue()`
- `ConversionUtils.formatValue()`

**Migration:** Replace all three with MetadataStore pattern

### 6. `tools/radial_bar_chart_tool.dart`
**Lines:** 60
**Usage:** `ConversionUtils.getConvertedValue()`
**Migration:** Replace with `metadataStore.get(path)?.convert(rawValue)`

### 7. `tools/tanks_tool.dart`
**Lines:** 165, 179
**Usage:**
- `ConversionUtils.getRawValue()` for level
- `ConversionUtils.getConvertedValue()` for capacity

**Migration:** Replace both with MetadataStore pattern

### 8. `tools/victron_flow_tool.dart`
**Lines:** 767, 818
**Usage:** `ConversionUtils.formatValue()` for display
**Migration:** Replace with `metadataStore.get(path)?.format(rawValue)`

### 9. `polar_radar_chart.dart`
**Lines:** 86-87, 203-204
**Usage:** `ConversionUtils.getConvertedValue()` for angle/magnitude
**Migration:** Replace with MetadataStore pattern

### 10. `tools/windsteer_demo_tool.dart`
**Lines:** 24-40
**Usage:** `signalKService.getConvertedValue()` (10 calls)
**Migration:** Replace with MetadataStore pattern for each path

---

## COMPLEX (Weather widgets with fallback logic)

These use `WeatherFieldType` fallback conversions - need special handling.

### 11. `tools/weather_api_spinner_tool.dart`
**Lines:** 67, 168, 171, 174, 321, 326
**Usage:**
- `ConversionUtils.fetchCategories()`
- `ConversionUtils.getWeatherUnitSymbol()`
- `ConversionUtils.convertValue()`
- `ConversionUtils.convertWeatherValue()`

**Note:** Uses fallback conversions for weather data without SignalK metadata

### 12. `tools/weatherflow_forecast_tool.dart`
**Lines:** 59-70, 192-200, 244-253
**Usage:** 20+ calls to `ConversionUtils.getConvertedValue()` and `evaluateFormula()`
**Note:** Heavy weather data processing - complex migration

### 13. `tools/forecast_spinner_tool.dart`
**Lines:** 149-157
**Usage:** 7 calls to `ConversionUtils.getConvertedValue()`
**Note:** Weather forecast data

### 14. `weatherflow_forecast.dart`
**Lines:** Comments only - data passed in pre-converted
**Status:** N/A - no direct ConversionUtils calls, receives converted data

---

## Migration Pattern

**For each widget, replace:**

```dart
// OLD (ConversionUtils) - DEPRECATED
import '../../utils/conversion_utils.dart';

final rawValue = ConversionUtils.getRawValue(signalKService, path);
final displayValue = ConversionUtils.getConvertedValue(signalKService, path);
final formatted = ConversionUtils.formatValue(signalKService, path, rawValue);
final siValue = ConversionUtils.convertToRaw(signalKService, path, displayValue);
```

```dart
// NEW (MetadataStore) - REQUIRED
final dataPoint = signalKService.getValue(path);
final rawValue = (dataPoint?.value as num?)?.toDouble();

final metadata = signalKService.metadataStore.get(path);
final displayValue = metadata?.convert(rawValue);
final formatted = metadata?.format(rawValue, decimals: 1);
final siValue = metadata?.convertToSI(displayValue) ?? displayValue;
```

---

## Order of Operations

1. **First:** `control_tool_mixin.dart` - used by multiple control widgets
2. **Second:** Control widgets (slider, knob, dropdown) - depend on mixin
3. **Third:** Simple display widgets (text_display, radial_bar_chart, tanks, polar_radar_chart)
4. **Fourth:** Windsteer demo
5. **Last:** Weather widgets (complex fallback logic)

---

## Open Question

Weather widgets use `ConversionUtils.convertWeatherValue()` with `WeatherFieldType` for data that may not have server metadata.

**Decision needed:**
- [ ] Keep weather fallback in ConversionUtils?
- [ ] Add fallback logic to MetadataStore?
- [ ] Create separate WeatherFallback utility?

---

## Compliant Widgets (Reference)

These 15 widgets already use MetadataStore correctly:

| Widget | File |
|--------|------|
| RPI Monitor | `tools/rpi_monitor_tool.dart` |
| AIS Polar Chart | `ais_polar_chart.dart` |
| Linear Gauge | `tools/linear_gauge_tool.dart` |
| Windsteer | `tools/windsteer_tool.dart` |
| Radial Gauge | `tools/radial_gauge_tool.dart` |
| Compass Gauge | `tools/compass_gauge_tool.dart` |
| Historical Chart | `historical_line_chart.dart` |
| Realtime Chart | `realtime_spline_chart.dart` |
| Anchor Alarm | `tools/anchor_alarm_tool.dart` |
| Attitude Indicator | `tools/attitude_indicator_tool.dart` |
| Autopilot Simple | `tools/autopilot_simple_tool.dart` |
| Autopilot V2 | `tools/autopilot_tool_v2.dart` |
| Autopilot | `tools/autopilot_tool.dart` |
| Wind Compass Tool | `tools/wind_compass_tool.dart` |
| Conversion Test | `tools/conversion_test_tool.dart` |
