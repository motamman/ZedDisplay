# SignalK Unit Conversions Guide

## Overview

ZedDisplay uses **client-side unit conversions** to display SignalK data in your preferred units. Instead of relying on server-side plugins, the app fetches conversion formulas from your SignalK server and applies them locally.

## How It Works

### Architecture

1. **SignalK Server** provides:
   - Raw data in SI units via WebSocket (`ws://server/signalk/v1/stream`)
   - Conversion formulas via REST API (`/signalk/v1/conversions`)

2. **ZedDisplay** handles:
   - Fetching conversion formulas on connection
   - Applying formulas client-side using math expression evaluation
   - Displaying converted values with appropriate symbols

### Data Flow

```
SignalK Server (radians)
    ↓ WebSocket
ZedDisplay receives: 1.5708 radians
    ↓ Apply formula: value * 57.2957795
ZedDisplay displays: 90.0°
```

## Conversion Format

Conversions are defined in JSON format on the SignalK server at `/signalk/v1/conversions`:

```json
{
  "navigation.courseOverGroundTrue": {
    "baseUnit": "rad",
    "category": "angle",
    "conversions": {
      "deg": {
        "formula": "value * 57.2957795",
        "inverseFormula": "value / 57.2957795",
        "symbol": "°",
        "description": "Degrees"
      }
    }
  }
}
```

### Conversion Properties

| Property | Description | Required |
|----------|-------------|----------|
| `baseUnit` | SI unit (rad, m/s, K, etc.) | Yes |
| `category` | Type (angle, speed, temperature, etc.) | Yes |
| `conversions` | Map of target units to conversion info | Yes |
| `formula` | Math expression to convert from base unit | Yes |
| `inverseFormula` | Math expression to convert back to base unit | Yes |
| `symbol` | Display symbol (°, kn, °C, etc.) | Yes |
| `description` | Human-readable description | Optional |

### Formula Syntax

Formulas use standard math expressions with the variable `value`:

- `value * 57.2957795` - Radians to degrees
- `value * 1.94384` - m/s to knots
- `(value - 273.15)` - Kelvin to Celsius
- `(value - 273.15) * 9/5 + 32` - Kelvin to Fahrenheit

Supported operations: `+`, `-`, `*`, `/`, `()`, standard math functions

## Common Conversions

### Angle (radians → degrees)

```json
{
  "navigation.headingTrue": {
    "baseUnit": "rad",
    "category": "angle",
    "conversions": {
      "deg": {
        "formula": "value * 57.2957795",
        "inverseFormula": "value / 57.2957795",
        "symbol": "°"
      }
    }
  }
}
```

**Apply to:**
- `navigation.headingTrue`
- `navigation.headingMagnetic`
- `navigation.courseOverGroundTrue`
- `environment.wind.directionTrue`
- `environment.wind.angleApparent`

### Speed (m/s → knots)

```json
{
  "navigation.speedOverGround": {
    "baseUnit": "m/s",
    "category": "speed",
    "conversions": {
      "kn": {
        "formula": "value * 1.94384",
        "inverseFormula": "value / 1.94384",
        "symbol": "kn"
      }
    }
  }
}
```

**Apply to:**
- `navigation.speedOverGround`
- `navigation.speedThroughWater`
- `environment.wind.speedTrue`
- `environment.wind.speedApparent`

### Distance (meters → nautical miles)

```json
{
  "navigation.courseGreatCircle.nextPoint.distance": {
    "baseUnit": "m",
    "category": "distance",
    "conversions": {
      "nm": {
        "formula": "value / 1852",
        "inverseFormula": "value * 1852",
        "symbol": "nm"
      }
    }
  }
}
```

### Temperature (Kelvin → Celsius)

```json
{
  "environment.outside.temperature": {
    "baseUnit": "K",
    "category": "temperature",
    "conversions": {
      "C": {
        "formula": "value - 273.15",
        "inverseFormula": "value + 273.15",
        "symbol": "°C"
      }
    }
  }
}
```

## Adding Conversions to SignalK Server

### Method 1: Via Plugin (Recommended)

If you have the **@signalk/units-conversion** plugin installed:

1. Open SignalK Server Admin → Server → Plugin Config
2. Find "Units Conversion" plugin
3. Add your conversions in the configuration
4. Restart the server

### Method 2: Manual Configuration

Add conversions directly to your SignalK server configuration:

1. Edit `~/.signalk/defaults.json` or your vessel settings file
2. Add conversions under the appropriate path:

```json
{
  "conversions": {
    "navigation.courseOverGroundTrue": {
      "baseUnit": "rad",
      "category": "angle",
      "conversions": {
        "deg": {
          "formula": "value * 57.2957795",
          "inverseFormula": "value / 57.2957795",
          "symbol": "°"
        }
      }
    }
  }
}
```

3. Restart SignalK server
4. Verify at: `http://your-server:3000/signalk/v1/conversions`

## How ZedDisplay Uses Conversions

### On Connection

```dart
// 1. Connect to WebSocket
await connect('your-server:3000');

// 2. Fetch conversions
await fetchConversions();  // GET /signalk/v1/conversions

// 3. Subscribe to data paths
subscribeToAutopilotPaths(['navigation.headingTrue']);
```

### Converting Values

```dart
// Get raw value (radians)
final headingRadians = ConversionUtils.getRawValue(service, 'navigation.headingTrue');
// Returns: 1.5708

// Get converted value (degrees)
final headingDegrees = ConversionUtils.getConvertedValue(service, 'navigation.headingTrue');
// Returns: 90.0

// Get formatted string
final formatted = ConversionUtils.formatValue(service, 'navigation.headingTrue', rawValue);
// Returns: "90.0 °"
```

### For Multi-Vessel Data (AIS)

When converting AIS vessel data, use the **path without vessel context**:

```dart
// ❌ WRONG - includes vessel context
_convertValueForPath('vessels.urn:mrn:imo:mmsi:123456.navigation.courseOverGroundTrue', rawCog);

// ✅ CORRECT - path only
_convertValueForPath('navigation.courseOverGroundTrue', rawCog);
```

Conversions are stored by path, not by full vessel context.

## Troubleshooting

### Values Still in Radians/SI Units

**Problem:** Display shows values like `1.5708` instead of `90.0`

**Causes:**
1. Conversion not defined on server
2. Wrong path used for lookup
3. Conversion formula error

**Solutions:**
1. Check `/signalk/v1/conversions` endpoint
2. Verify path matches exactly (case-sensitive)
3. Test formula manually: `1.5708 * 57.2957795 = 90.0`

### Conversion Not Found

**Problem:** `getAvailableUnits(path)` returns empty array

**Causes:**
1. Path not in conversions data
2. Server hasn't reloaded configuration
3. Wrong path format

**Solutions:**
1. Add conversion to server config
2. Restart SignalK server
3. Check exact path in SignalK data browser

### Formula Evaluation Error

**Problem:** Converted value is `null`

**Causes:**
1. Invalid formula syntax
2. Division by zero
3. Unsupported math function

**Solutions:**
1. Test formula with known values
2. Check for edge cases (zero, null, negative)
3. Use supported operations only

## Best Practices

### 1. Define Conversions for All Display Paths

Add conversions for every path you display in ZedDisplay:

```json
{
  "navigation.headingTrue": { ... },
  "navigation.courseOverGroundTrue": { ... },
  "navigation.speedOverGround": { ... },
  "environment.wind.speedTrue": { ... },
  "environment.wind.angleApparent": { ... }
}
```

### 2. Use Inverse Formulas

Always provide inverse formulas for bidirectional conversion:

```json
{
  "formula": "value * 1.94384",           // m/s → kn
  "inverseFormula": "value / 1.94384"    // kn → m/s
}
```

### 3. Keep Raw Values for Calculations

When using values for calculations (rotation, math), use raw SI values:

```dart
// For rotation - use radians
final headingRadians = ConversionUtils.getRawValue(service, 'navigation.headingTrue');
transform.rotate(headingRadians);

// For display - use converted
final headingDegrees = ConversionUtils.getConvertedValue(service, 'navigation.headingTrue');
text.show('$headingDegrees°');
```

### 4. Test All Conversions

After adding conversions, verify each one:

```bash
# Fetch conversions
curl http://localhost:3000/signalk/v1/conversions | jq

# Check a specific path
curl http://localhost:3000/signalk/v1/conversions | jq '.["navigation.headingTrue"]'
```

### 5. Document Custom Conversions

If using non-standard conversions, document them:

```json
{
  "environment.custom.windChill": {
    "baseUnit": "K",
    "category": "temperature",
    "conversions": {
      "C": {
        "formula": "(value - 273.15)",
        "inverseFormula": "(value + 273.15)",
        "symbol": "°C",
        "description": "Wind chill temperature in Celsius"
      }
    }
  }
}
```

## Reference: Standard SignalK Units

| Category | Base Unit | Symbol | Common Conversions |
|----------|-----------|--------|-------------------|
| Angle | Radians (rad) | rad | deg (°) |
| Speed | Meters/second (m/s) | m/s | kn, km/h, mph |
| Distance | Meters (m) | m | nm, km, mi |
| Temperature | Kelvin (K) | K | °C, °F |
| Pressure | Pascals (Pa) | Pa | hPa, bar, psi |
| Volume | Cubic meters (m³) | m³ | L, gal |
| Length | Meters (m) | m | ft, in |

## Additional Resources

- [SignalK Specification](https://signalk.org/specification/)
- [Math Expressions Dart Package](https://pub.dev/packages/math_expressions)
- [ZedDisplay Conversion Utils Source](../../lib/utils/conversion_utils.dart)

---

**Last Updated:** October 2025
**ZedDisplay Version:** 0.2.5+
