# ZedDisplay +SignalK - Project Guidelines

## Project Overview
ZedDisplay +SignalK is a Flutter marine dashboard app that connects to SignalK servers for boat instrumentation data. Sister app: ZedDisplay-OpenMeteo (more mature, reference for patterns).

## Unit Conversion Rules

**Core Principle: SignalK uses SI units - NEVER hardcode conversions in widgets**

### SignalK Base Units

| Data Type | SignalK Base Unit | Example Display Units |
|-----------|-------------------|----------------------|
| Angles | radians | degrees (°) |
| Speed | m/s | knots (kn), mph, km/h |
| Temperature | Kelvin | °F, °C |
| Pressure | Pascals | hPa, mbar, inHg, psi |
| Distance | meters | nm, feet, miles |
| Percentage | ratio (0-1) | percent (0-100%) |

### Required Pattern for Display Values

```dart
// CORRECT: Use ConversionUtils
final rawValue = ConversionUtils.getRawValue(signalKService, path);
final displayValue = ConversionUtils.getConvertedValue(signalKService, path);
final formatted = ConversionUtils.formatValue(signalKService, path, rawValue);

// For weather/fallback conversions (when no server metadata):
final converted = ConversionUtils.convertWeatherValue(
  service, WeatherFieldType.temperature, rawValue);
final symbol = ConversionUtils.getWeatherUnitSymbol(WeatherFieldType.temperature);

// WRONG: Never do manual conversions in widgets!
final degrees = radians * 180 / pi;  // BAD!
final fahrenheit = (kelvin - 273.15) * 9/5 + 32;  // BAD!
```

### Required Pattern for PUT Requests

```dart
// Convert display value back to SI before sending
final siValue = ConversionUtils.convertToRaw(signalKService, path, displayValue);
await signalKService.putValue(path, siValue);
```

### Key Files Reference

- `lib/utils/conversion_utils.dart` - All conversion methods, formula evaluation
- `lib/services/signalk_service.dart` - Server connection, `getAvailableUnits()`, `getConversionInfo()`
- `lib/models/signalk_data.dart` - SignalKDataPoint model

### ConversionUtils Methods

| Method | Purpose |
|--------|---------|
| `getRawValue(service, path)` | Get SI value from SignalK stream |
| `getConvertedValue(service, path)` | Get display value (converted) |
| `convertValue(service, path, rawValue)` | Convert raw SI to display units |
| `formatValue(service, path, rawValue)` | Get formatted string with unit symbol |
| `convertToRaw(service, path, displayValue)` | Inverse conversion for PUT requests |
| `convertWeatherValue(service, fieldType, rawValue)` | Fallback conversion using `WeatherFieldType` |
| `getWeatherUnitSymbol(fieldType)` | Get unit symbol for weather fields |
| `fetchCategories(service)` | Load server unit preferences (cached 30 min) |

## Rules for Future Sessions

### DO
- Use `ConversionUtils` methods for ALL unit conversions
- Get unit symbols from server metadata via `getConversionInfo()`
- Support both server-provided and fallback conversions
- Use `WeatherFieldType` enum for weather data without SignalK metadata
- Use `convertToRaw()` for inverse conversion when sending PUT requests

### DON'T
- Hardcode conversion formulas in widget code
- Assume specific units - always check server preferences
- Forget inverse conversion for PUT requests
- Duplicate conversion logic that exists in ConversionUtils
