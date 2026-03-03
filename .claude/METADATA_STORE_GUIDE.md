# MetadataStore: Single Source of Truth for Unit Conversions

**READ THIS BEFORE working with unit conversions, symbols, or formatting values.**

## Overview

`MetadataStore` is the single source of truth for all path metadata and unit conversions in ZedDisplay. It is populated from SignalK WebSocket meta deltas (`sendMeta=all`).

## Key Files

| File | Purpose |
|------|---------|
| `lib/models/path_metadata.dart` | `PathMetadata` model with convert/format methods |
| `lib/services/metadata_store.dart` | Store that holds all path metadata |
| `lib/services/signalk_service.dart` | Exposes `metadataStore` getter |

## Data Flow

```
SignalK Server (unit preferences)
       ↓
WebSocket Meta Delta (sendMeta=all)
       ↓
SignalKService._handleMessage()
       ↓
_metadataStore.updateFromMeta(path, displayUnits)
       ↓
PathMetadata created with: formula, symbol, targetUnit
       ↓
Widgets use metadataStore.get(path) for conversions
```

## Usage Patterns

### Get Converted Value (SI → Display)
```dart
// Get raw SI value from data point
final dataPoint = signalKService.getValue(path);
final rawValue = dataPoint?.value is num
    ? (dataPoint!.value as num).toDouble()
    : null;

// Convert using MetadataStore
final metadata = signalKService.metadataStore.get(path);
final displayValue = rawValue != null ? metadata?.convert(rawValue) : null;
```

### Get Unit Symbol
```dart
final symbol = signalKService.metadataStore.get(path)?.symbol;
// Returns: "°F", "kn", "°", "hPa", etc.
```

### Format Value with Symbol
```dart
final metadata = signalKService.metadataStore.get(path);
final formatted = rawValue != null ? metadata?.format(rawValue, decimals: 1) : null;
// Returns: "74.7 °F", "12.5 kn", etc.
```

### Convert Display → SI (for PUT requests)
```dart
final metadata = signalKService.metadataStore.get(path);
final siValue = metadata?.convertToSI(displayValue);
await signalKService.putValue(path, siValue);
```

## DO NOT

1. **DO NOT hardcode unit symbols** - Always get from `metadata?.symbol`
2. **DO NOT hardcode conversion formulas** - Always use `metadata?.convert()`
3. **DO NOT use ConversionUtils for new code** - Use MetadataStore instead
4. **DO NOT assume units** - If metadata is null, show raw value or "--"

## Fallback Handling

When `metadataStore.get(path)` returns `null`:
- The server hasn't sent metadata for this path
- Show raw SI value with appropriate fallback unit, OR
- Show "--" or "No data"

```dart
final metadata = signalKService.metadataStore.get(path);
if (metadata != null) {
  return metadata.format(rawValue);
} else {
  // Fallback: raw value with SI unit hint
  return '${rawValue.toStringAsFixed(1)} (SI)';
}
```

## Debugging

Use the **Conversion Test Tool** to inspect metadata for any path:
- Shows: symbol, formula, raw value, converted value
- Red card = no metadata from server

If units are wrong:
1. Check SignalK Server → Settings → Unit Preferences
2. Ensure the server preference matches what you expect
3. The client displays EXACTLY what the server sends

## Common Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| Wrong unit symbol | Server configured for different unit | Change SignalK unit preferences |
| No conversion | No metadata for path | Check sendMeta=all is working |
| Stale units | Cached old metadata | Disconnect/reconnect to refresh |
