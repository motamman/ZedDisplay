# Windsteer Tool Implementation Plan

## Overview

The Windsteer tool is a comprehensive marine navigation display that shows heading, wind angles, course information, and navigation data on a rotating compass dial. It's designed to mirror the functionality of the Kip SignalK dashboard windsteer widget.

---

## Current Status

### ✅ What's Complete

1. **Windsteer Gauge Widget** (`lib/widgets/windsteer_gauge.dart`)
   - Rotating compass dial with N/E/S/W labels
   - Apparent wind angle (AWA) indicator - blue arrow with "A"
   - True wind angle (TWA) indicator - green arrow with "T"
   - Close-hauled laylines (dashed lines showing optimal sailing angles)
   - Course over ground (COG) indicator - orange diamond
   - Drift/set indicator - cyan arrow showing current direction
   - Waypoint bearing indicator - purple circle with line
   - Wind speed displays (AWS/TWS) in corners
   - Wind sector visualization for historical wind shifts
   - Port/starboard arc indicators (red/green)
   - Boat icon in center

2. **Windsteer Demo Tool** (`lib/widgets/tools/windsteer_demo_tool.dart`)
   - **WORKING NOW** - Auto-detects standard SignalK paths
   - Requires no configuration
   - Automatically subscribes to common wind/navigation paths
   - **This is the tool you should use right now**

### ❌ What's NOT Working

1. **Multi-Path Configuration UI**
   - Current tool config screen (`lib/screens/tool_config_screen.dart`) only supports **ONE** data path
   - Windsteer needs up to **12** data paths for full functionality
   - No UI exists to add/remove/reorder multiple paths
   - No way to configure which features to enable based on available paths

2. **Full Windsteer Tool** (`lib/widgets/tools/windsteer_tool.dart`)
   - Implementation exists but **cannot be configured** through the UI
   - Would require multi-path configuration screen to work

3. **Style Configuration for Advanced Features**
   - No UI for configuring windsteer-specific options like:
     - Layline angle (default: 45°)
     - Show/hide individual indicators
     - Wind sector settings
   - These options are defined in the model but not accessible in UI

---

## How It SHOULD Work

### User Experience Flow

#### Step 1: Add Windsteer Tool
1. User taps **"Add Tool"** button
2. Selects **"Windsteer"** from tool type list
3. Sees a **multi-path configuration screen** (NOT BUILT YET)

#### Step 2: Configure Data Paths
The configuration screen should show:

```
┌─────────────────────────────────────┐
│ Configure Windsteer Tool            │
├─────────────────────────────────────┤
│ Data Paths:                         │
│                                     │
│ ✓ 1. Heading (REQUIRED)            │
│   └─ navigation.headingMagnetic     │
│   [Change] [×]                      │
│                                     │
│ ✓ 2. Apparent Wind Angle           │
│   └─ environment.wind.angleApparent │
│   [Change] [×]                      │
│                                     │
│ ✓ 3. True Wind Angle               │
│   └─ environment.wind.angleTrueWater│
│   [Change] [×]                      │
│                                     │
│ ○ 4. Apparent Wind Speed           │
│   └─ Not configured                 │
│   [Add Path]                        │
│                                     │
│ ○ 5. True Wind Speed               │
│   └─ Not configured                 │
│   [Add Path]                        │
│                                     │
│ ○ 6. Course Over Ground            │
│   └─ Not configured                 │
│   [Add Path]                        │
│                                     │
│ [+ Add More Paths]                 │
│                                     │
├─────────────────────────────────────┤
│ Display Options:                    │
│                                     │
│ ☑ Show Laylines                    │
│ ☑ Show True Wind                   │
│ ☐ Show COG Indicator               │
│ ☑ Show AWS Display                 │
│ ☑ Show TWS Display                 │
│ ☐ Show Drift/Set                   │
│ ☐ Show Waypoint Bearing            │
│ ☐ Show Wind Sectors                │
│                                     │
│ Layline Angle: [45°] ────○────     │
│                                     │
├─────────────────────────────────────┤
│ Colors:                             │
│                                     │
│ Apparent Wind: [🔵 Blue   ]        │
│ True Wind:     [🟢 Green  ]        │
│                                     │
├─────────────────────────────────────┤
│            [Cancel] [Save]          │
└─────────────────────────────────────┘
```

#### Step 3: Using the Tool
Once configured, the windsteer displays:
- **Always visible**: Heading, compass dial, boat icon
- **Visible if configured**: Wind arrows, speeds, COG, waypoints, etc.
- **Real-time updates**: All indicators update as data changes
- **Responsive**: Works in portrait and landscape

---

## Data Paths Reference

### Required Path (Minimum 1)
| # | Path | Description | Default |
|---|------|-------------|---------|
| 0 | `navigation.headingMagnetic` or `navigation.headingTrue` | Boat heading in degrees | **REQUIRED** |

### Optional Paths
| # | Path | Description | Shows |
|---|------|-------------|-------|
| 1 | `environment.wind.angleApparent` | AWA in degrees | Blue "A" arrow |
| 2 | `environment.wind.angleTrueWater` | TWA in degrees | Green "T" arrow |
| 3 | `environment.wind.speedApparent` | AWS | Top-left corner speed |
| 4 | `environment.wind.speedTrue` | TWS | Top-right corner speed |
| 5 | `navigation.courseOverGroundTrue` | COG in degrees | Orange diamond |
| 6 | `navigation.course.nextPoint.bearingTrue` | Next waypoint bearing | Purple circle |
| 7 | `environment.current.setTrue` | Current direction (degrees) | Cyan arrow direction |
| 8 | `environment.current.drift` | Current speed | Center text + arrow |
| 9 | *(custom)* | Historical TWA minimum | Wind sector left edge |
| 10 | *(custom)* | Historical TWA mid/avg | Wind sector center |
| 11 | *(custom)* | Historical TWA maximum | Wind sector right edge |

### Path Behavior
- **If path is not configured**: That indicator doesn't show (graceful degradation)
- **If path is configured but no data**: Indicator shows but may display "---" or 0
- **Multiple sources**: User can select specific data source for each path

---

## Technical Implementation Needed

### 1. Multi-Path Configuration Screen

**File to Create**: `lib/screens/multi_path_config_screen.dart`

**Features:**
```dart
class MultiPathConfigScreen extends StatefulWidget {
  final Tool? existingTool;
  final String toolTypeId; // e.g., 'windsteer'
  final int maxPaths; // From ToolDefinition.configSchema

  // Manages:
  // - List<DataSource> _dataSources
  // - Adding/removing paths
  // - Reordering paths (drag-and-drop?)
  // - Path labels and source selection per path
}
```

**UI Components:**
- `ReorderableListView` of data sources
- "Add Path" button (up to maxPaths)
- Path selector dialog for each slot
- Source selector for each path
- Custom label input per path
- Delete button per path

### 2. Tool-Specific Style Configuration

**File to Modify**: `lib/screens/tool_config_screen.dart`

Add windsteer-specific options when `_selectedToolTypeId == 'windsteer'`:

```dart
// Windsteer-specific configuration
if (_selectedToolTypeId == 'windsteer')
  Card(
    child: Column(
      children: [
        // Layline angle slider
        Slider(
          value: _laylineAngle,
          min: 30,
          max: 60,
          divisions: 30,
          label: '${_laylineAngle.round()}°',
          onChanged: (value) => setState(() => _laylineAngle = value),
        ),

        // Show/hide toggles
        SwitchListTile(
          title: Text('Show Laylines'),
          value: _showLaylines,
          onChanged: (value) => setState(() => _showLaylines = value),
        ),

        SwitchListTile(
          title: Text('Show True Wind'),
          value: _showTrueWind,
          onChanged: (value) => setState(() => _showTrueWind = value),
        ),

        // ... more toggles for COG, drift, waypoint, sectors
      ],
    ),
  ),
```

### 3. Updated ToolConfig Model

**Already implemented** in `lib/models/tool_config.dart`:

```dart
class StyleConfig {
  // Windsteer options
  final double? laylineAngle;
  final bool? showLaylines;
  final bool? showTrueWind;
  final bool? showCOG;
  final bool? showAWS;
  final bool? showTWS;

  // Could also use customProperties for:
  // - showDrift
  // - showWaypoint
  // - showWindSectors
}
```

### 4. Tool Definition Updates

**Already defined** in `lib/widgets/tools/windsteer_tool.dart`:

```dart
ConfigSchema(
  allowsMultiplePaths: true,
  minPaths: 1,      // At least heading
  maxPaths: 12,     // All optional features
  styleOptions: [
    'laylineAngle',
    'showLaylines',
    'showTrueWind',
    // etc...
  ],
)
```

---

## Temporary Workaround: Windsteer (Auto)

### How It Works Now

**File**: `lib/widgets/tools/windsteer_demo_tool.dart`

This is a **simplified version** that:
1. ✅ Requires **zero configuration**
2. ✅ Automatically tries common SignalK paths
3. ✅ Shows whatever data is available
4. ✅ Works immediately

**To use:**
1. Add Tool → Select "Windsteer (Auto)"
2. No path configuration needed
3. Click Save
4. Done!

**Limitations:**
- Uses hardcoded path names (won't work with non-standard paths)
- Can't customize which paths to use
- Limited style options
- Can't change data sources
- No wind sectors (requires historical data paths)

---

## Migration Path

### Phase 1: Current State (NOW)
- Use **"Windsteer (Auto)"** for immediate functionality
- Manually configure style options (colors, laylines, etc.)
- Accept hardcoded path limitations

### Phase 2: Multi-Path UI (NEEDS BUILDING)
- Build `MultiPathConfigScreen`
- Integrate with tool config flow
- Allow path selection for all 12 slots
- Enable full windsteer customization

### Phase 3: Advanced Features (FUTURE)
- Historical wind data tracking (for wind sectors)
- Path auto-discovery and suggestions
- Template configurations (e.g., "Racing Setup", "Cruising Setup")
- Export/import windsteer configurations

---

## Example Configurations

### Minimal Setup (Heading Only)
```
Paths:
  0: navigation.headingMagnetic

Result:
  - Rotating compass dial
  - No wind indicators
  - No additional features
```

### Basic Wind Setup
```
Paths:
  0: navigation.headingMagnetic
  1: environment.wind.angleApparent
  3: environment.wind.speedApparent

Result:
  - Compass dial with heading
  - Blue AWA arrow
  - AWS speed display (top-left)
  - Optional laylines
```

### Full Racing Setup
```
Paths:
  0: navigation.headingMagnetic
  1: environment.wind.angleApparent
  2: environment.wind.angleTrueWater
  3: environment.wind.speedApparent
  4: environment.wind.speedTrue
  5: navigation.courseOverGroundTrue
  6: navigation.course.nextPoint.bearingTrue
  7: environment.current.setTrue
  8: environment.current.drift

Options:
  - Laylines: ON (45°)
  - True Wind: ON
  - COG: ON
  - Waypoint: ON
  - Drift: ON

Result:
  - Full tactical display
  - All wind indicators
  - Course and waypoint info
  - Current visualization
```

---

## Questions and Considerations

### Q: Why not just use the auto-detection version?
**A:** Because:
- Users may have non-standard path names
- Some servers provide multiple sources (GPS, NMEA, calculated)
- Users may want to disable certain features even if data exists
- Advanced users want full control

### Q: Is there a simpler way?
**A:** Possible alternatives:
1. **Smart defaults with overrides** - Auto-detect paths but allow customization
2. **Template system** - Pre-configured setups users can choose from
3. **Progressive disclosure** - Start simple, reveal advanced options as needed

### Q: What about other multi-path tools?
**A:** This same system could support:
- **Multi-line charts** - Show multiple data series
- **Comparison displays** - Port vs starboard tank levels
- **Calculated displays** - Speed/heading/wind triangle
- **Any tool needing 2+ data sources**

---

## Visual Mockup

```
 Top Row: [AWS: 12.3 kn]           [TWS: 15.8 kn]

              ┌────────────────┐
              │   045°         │  ← Heading display
              └────────────────┘

              N ◄─── Purple waypoint
         330° │ 030°  ↑ marker
      W ──────┼────── E
         210° │ 150°
              S

        Blue AWA arrow (large) ↑
        Green TWA arrow (small) ↗
        Orange COG diamond ◆
        Cyan drift arrow →

        Dashed laylines from center /  \

        [Boat icon in center]
        ⛵

        Red port arc at top-left
        Green starboard arc at top-right

 Center:  1.2 kn  ← Drift speed
```

---

## Summary

**Current State:**
- ✅ Widget fully implemented
- ✅ Demo version works now
- ❌ Full configuration UI missing
- ❌ Multi-path support missing

**To Use Today:**
- Use "Windsteer (Auto)" tool
- Accept hardcoded paths
- Limited customization

**To Make It Complete:**
- Build multi-path configuration screen
- Add windsteer-specific style UI
- Test with real SignalK data
- Document path requirements

**Priority:**
Multi-path configuration UI is the critical missing piece. Without it, users can't customize the windsteer tool or use it with non-standard SignalK paths.
