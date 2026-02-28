# ZedDisplay +SignalK - Project Guidelines

## Project Overview
ZedDisplay +SignalK is a Flutter marine dashboard app that connects to SignalK servers for boat instrumentation data. Sister app: ZedDisplay-OpenMeteo (more mature, reference for patterns).

## Required Reading

**BEFORE working with unit conversions or metadata:**
Read `.claude/METADATA_STORE_GUIDE.md` - the definitive guide to using MetadataStore as the single source of truth.

## Unit Conversion Rules

**Core Principle: SignalK uses SI units - NEVER hardcode conversions in widgets**

**Single Source of Truth: `MetadataStore`** - populated from WebSocket meta deltas.

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
// CORRECT: Use MetadataStore
final dataPoint = signalKService.getValue(path);
final rawValue = (dataPoint?.value as num?)?.toDouble();

final metadata = signalKService.metadataStore.get(path);
final displayValue = metadata?.convert(rawValue);
final formatted = metadata?.format(rawValue, decimals: 1); // "12.5 kn"
final symbol = metadata?.symbol; // "kn"

// WRONG: Never do manual conversions in widgets!
final degrees = radians * 180 / pi;  // BAD!
final fahrenheit = (kelvin - 273.15) * 9/5 + 32;  // BAD!

// WRONG: Do not use ConversionUtils (LEGACY)
final value = ConversionUtils.getConvertedValue(...);  // BAD - DEPRECATED!
```

### Required Pattern for PUT Requests

```dart
// Convert display value back to SI before sending
final metadata = signalKService.metadataStore.get(path);
final siValue = metadata?.convertToSI(displayValue) ?? displayValue;
await signalKService.putValue(path, siValue);
```

### Fallback When No Metadata

```dart
final metadata = signalKService.metadataStore.get(path);
if (metadata != null) {
  return metadata.format(rawValue);
} else {
  // No metadata from server - show raw SI value
  return rawValue.toStringAsFixed(1);
}
```

### Key Files Reference

| File | Purpose |
|------|---------|
| `lib/models/path_metadata.dart` | `PathMetadata` model with convert/format methods |
| `lib/services/metadata_store.dart` | Store holding all path metadata |
| `lib/services/signalk_service.dart` | Exposes `metadataStore` getter |

### DEPRECATED - Do Not Use

| File | Status |
|------|--------|
| `lib/utils/conversion_utils.dart` | **LEGACY** - Do not use for new code. Migrate existing uses to MetadataStore. |

## Rules for Future Sessions

### DO
- Use `signalKService.metadataStore.get(path)` for ALL unit conversions
- Use `metadata?.convert(rawValue)` for SI → display conversion
- Use `metadata?.convertToSI(displayValue)` for display → SI (PUT requests)
- Use `metadata?.format(rawValue)` for formatted string with symbol
- Use `metadata?.symbol` for unit symbol
- Handle null metadata gracefully (show raw value or "--")

### DON'T
- Hardcode conversion formulas in widget code
- Use ConversionUtils (LEGACY - migrate to MetadataStore)
- Assume specific units - always check server preferences
- Forget inverse conversion for PUT requests
