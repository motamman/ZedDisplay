# Windsteer Widget Implementation Plan

## Overview

A sophisticated sailing compass/wind indicator widget that combines multiple navigation data points into a single integrated display. Inspired by and based on the kip project's windsteer widget.

## What the Windsteer Widget Is

An advanced sailing navigation tool that displays:

- **Rotating Compass Dial** - Shows heading with cardinal directions (N/E/S/W) and degree markings
- **Boat Icon** - Fixed center showing port/starboard sides
- **Wind Indicators** - Both apparent and true wind angle/speed
- **Course Over Ground (COG)** - Diamond indicator showing actual track
- **Waypoint Bearing** - Circle indicator showing direction to next waypoint
- **Laylines** - Dashed lines showing optimal sailing angles (port/starboard tacks)
- **Wind Sectors** - Shaded areas showing historical wind direction range
- **Drift/Current** - Arrow showing current set and drift speed

## Visual Design Specifications

- **Canvas Size**: 1000x1000 logical pixels (scales to widget size)
- **Center Point**: (500, 500)
- **Compass Radius**: 350-450 pixels
- **Smooth Animations**: 900ms default duration using Flutter AnimationController
- **Color Scheme**:
  - Port indicators: Red/pink tones
  - Starboard indicators: Green tones
  - Wind: Blue tones
  - Course/waypoint: Yellow/orange tones

## Data Requirements

### SignalK Paths

#### Required Paths:
```dart
'navigation.headingTrue'              // Boat's true heading
'environment.wind.angleApparent'      // Apparent wind angle (AWA)
'environment.wind.speedApparent'      // Apparent wind speed (AWS)
```

#### Optional Paths:
```dart
'navigation.courseOverGroundTrue'                     // COG
'environment.wind.angleTrueWater'                    // True wind angle (TWA)
'environment.wind.speedTrue'                         // True wind speed (TWS)
'navigation.courseGreatCircle.nextPoint.bearingTrue' // Waypoint bearing
'environment.current.setTrue'                        // Current direction
'environment.current.drift'                          // Current speed
```

## Architecture

### File Structure

```
lib/
├── widgets/
│   ├── tools/
│   │   └── windsteer_tool.dart          # Tool wrapper (StatefulWidget)
│   └── windsteer_widget.dart            # Core widget
├── painters/
│   └── windsteer_painter.dart           # CustomPainter for rendering
└── models/
    └── windsteer_config.dart            # Configuration model (optional)
```

### Component Hierarchy

```
WindsteerTool (StatefulWidget)
├── Handles data subscriptions
├── Manages state (heading, wind, etc.)
├── Wind sector tracking
└── WindsteerWidget (StatelessWidget)
    └── CustomPaint
        └── WindsteerPainter (CustomPainter)
            ├── Background layer (fixed)
            ├── Rotating dial layer
            ├── Wind indicators
            ├── Navigation indicators
            ├── Laylines
            ├── Wind sectors
            └── Text overlays
```

## Implementation Phases

### Phase 1: Core Widget Structure (Foundation)

**Goal**: Basic structure and data flow

**Tasks**:
1. Create `windsteer_tool.dart` wrapper
   - Subscribe to SignalK paths
   - Handle data updates with epsilon thresholds
   - Manage AnimationController for rotations
2. Create `windsteer_painter.dart` CustomPainter
   - Setup canvas coordinate system (1000x1000)
   - Implement center point (500, 500)
3. Register tool in ToolRegistry
   - Add `WindsteerBuilder` class
   - Define tool metadata

**Deliverable**: Empty widget that subscribes to heading data

---

### Phase 2: Rendering Components (Visual Elements)

#### 2.1 - Fixed Background Layer

**Components**:
- Compass ring outer circle
- Degree tick marks (every 5°, bold every 30°)
- Cardinal directions (N/E/S/W) - bold, large font
- Intermediate degree labels (30, 60, 90, 120, etc.)
- Port/starboard gradient boat hull outline

**Painting Order**:
1. Background circle
2. Degree ticks
3. Degree labels
4. Cardinal letters
5. Boat hull

#### 2.2 - Rotating Compass Dial

**Behavior**:
- Rotates opposite to heading (so boat appears stationary)
- Contains all degree markings and text
- Smooth animation using AnimationController

**Implementation**:
```dart
canvas.save();
canvas.translate(centerX, centerY);
canvas.rotate(-headingRadians);
// Draw all compass elements
canvas.restore();
```

#### 2.3 - Wind Indicators

**Apparent Wind (AWA)**:
- Large arrow pointing to apparent wind angle
- Boat-relative (doesn't rotate with compass)
- Letter "A" in center of arrow
- Color: Blue (primary wind color)

**True Wind (TWA)**:
- Smaller arrow for true wind
- Absolute bearing (rotates counter to dial)
- Letter "T" in center of arrow
- Color: Lighter blue

**Speed Displays**:
- AWS (top-left corner): `"12.5 kn"`
- TWS (top-right corner): `"10.2 kn"`
- Bold font, 60-70px size
- Unit label below in smaller font

#### 2.4 - Navigation Indicators

**Course Over Ground (COG)**:
- Diamond/rhombus shape
- Shows actual ground track
- Color: Orange
- Rotates within dial coordinate system

**Waypoint Bearing**:
- Circle with dot pattern
- Shows direction to next waypoint
- Color: Yellow
- Only visible when waypoint is active

**Heading Display**:
- Fixed at top center
- Large bold numbers with degree symbol
- Background rounded rectangle
- Example: `"087°"`

---

### Phase 3: Advanced Features (Tactical Sailing)

#### 3.1 - Laylines (Close-Hauled Lines)

**Purpose**: Show optimal sailing angles for beating to windward

**Configuration**:
- `laylineEnable`: bool (default: true)
- `laylineAngle`: double (degrees, default: 40°)

**Rendering**:
- Two dashed lines extending from center to edge
- Port layline: AWA - laylineAngle
- Starboard layline: AWA + laylineAngle
- Dashed pattern: 40px dash, 20px gap
- Opacity: 60%

**Coordinate System**:
- Boat-relative positioning
- Rotates passively with dial
- Uses dial-local space for geometry

#### 3.2 - Wind Sectors (Historical Wind Range)

**Purpose**: Visualize wind shift range over recent time window

**Algorithm**:
```dart
class WindSectorTracker {
  List<WindSample> samples = [];      // {timestamp, angle, index}
  Deque<WindMinMax> minDeque = [];    // Monotonic increasing
  Deque<WindMinMax> maxDeque = [];    // Monotonic decreasing

  void addSample(double angle) {
    // 1. Unwrap angle to continuous domain
    double unwrapped = unwrapAngle(angle);

    // 2. Add to samples with timestamp
    samples.add(WindSample(DateTime.now(), unwrapped, sampleIndex++));

    // 3. Update min deque (maintain increasing values)
    while (minDeque.isNotEmpty && minDeque.last.value >= unwrapped) {
      minDeque.removeLast();
    }
    minDeque.add(WindMinMax(sampleIndex, unwrapped));

    // 4. Update max deque (maintain decreasing values)
    while (maxDeque.isNotEmpty && maxDeque.last.value <= unwrapped) {
      maxDeque.removeLast();
    }
    maxDeque.add(WindMinMax(sampleIndex, unwrapped));
  }

  void cleanup(Duration window) {
    // Remove samples older than window
    final cutoff = DateTime.now().subtract(window);
    while (samples.isNotEmpty && samples.first.timestamp.isBefore(cutoff)) {
      final removed = samples.removeAt(0);
      if (minDeque.first.index == removed.index) minDeque.removeFirst();
      if (maxDeque.first.index == removed.index) maxDeque.removeFirst();
    }
  }

  SectorAngles get current => SectorAngles(
    min: normalizeAngle(minDeque.first.value),
    mid: normalizeAngle((minDeque.first.value + maxDeque.first.value) / 2),
    max: normalizeAngle(maxDeque.first.value),
  );
}
```

**Configuration**:
- `windSectorEnable`: bool (default: true)
- `windSectorWindowSeconds`: int (default: 5 seconds)

**Rendering**:
- Two shaded wedge areas (port/starboard)
- Port: from min to mid (left side)
- Starboard: from mid to max (right side)
- Fill opacity: 50%
- Colors: Port = red tint, Starboard = green tint
- Offset by layline angle

**Performance**:
- O(1) amortized insertion
- O(1) min/max query
- Cleanup runs every 1 second
- Only redraws on value change (epsilon gating)

#### 3.3 - Current/Drift Indicator

**Components**:
- Arrow showing current set direction
- Numerical display of drift speed in center
- Gradient fade from opaque to transparent

**Data**:
- `environment.current.setTrue`: Direction (degrees)
- `environment.current.drift`: Speed (m/s converted to knots)

**Rendering**:
- Arrow rotates with dial (absolute bearing)
- Arrow length scales with drift speed
- Speed displayed in center: `"0.8 kn"`
- Gradient fill using LinearGradient

---

### Phase 4: Configuration & Integration (Tool System)

#### 4.1 - Tool Configuration

**Configuration Schema**:
```dart
class WindsteerConfig {
  // Feature enables
  bool laylineEnable;
  bool windSectorEnable;
  bool courseOverGroundEnable;
  bool waypointEnable;
  bool driftEnable;
  bool awsEnable;
  bool twsEnable;
  bool twaEnable;

  // Layline settings
  double laylineAngle;           // degrees (20-60, default: 40)

  // Wind sector settings
  int windSectorWindowSeconds;   // seconds (3-30, default: 5)

  // Style
  Color? primaryColor;
  double fontSize;
}
```

**Default Values**:
```dart
defaultConfig = WindsteerConfig(
  laylineEnable: true,
  laylineAngle: 40.0,
  windSectorEnable: true,
  windSectorWindowSeconds: 5,
  courseOverGroundEnable: true,
  waypointEnable: true,
  driftEnable: true,
  awsEnable: true,
  twsEnable: true,
  twaEnable: true,
  fontSize: 1.0,
);
```

#### 4.2 - Tool Registry Integration

**Register Tool**:
```dart
// In lib/services/tool_registry.dart
void registerDefaults() {
  // ... existing tools
  register('windsteer', WindsteerBuilder());
}
```

**Tool Builder**:
```dart
class WindsteerBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'windsteer',
      name: 'Wind & Compass',
      description: 'Sailing compass with wind indicators, laylines, and tactical data',
      category: ToolCategory.navigation,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: true,
        minPaths: 3,    // heading, AWA, AWS
        maxPaths: 9,    // all optional paths
        styleOptions: ['primaryColor', 'fontSize'],
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return WindsteerTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
```

#### 4.3 - Configuration Screen

**Custom Settings Panel** (in tool_config_screen.dart):
```dart
if (_selectedToolTypeId == 'windsteer')
  Card(
    child: Column(
      children: [
        Text('Windsteer Settings', style: titleMedium),

        // Feature toggles
        SwitchListTile(
          title: Text('Show Laylines'),
          value: _windsteerLaylineEnable,
          onChanged: (v) => setState(() => _windsteerLaylineEnable = v),
        ),

        // Layline angle slider
        if (_windsteerLaylineEnable)
          ListTile(
            title: Text('Layline Angle: ${_windsteerLaylineAngle.toInt()}°'),
            subtitle: Slider(
              min: 20,
              max: 60,
              divisions: 8,
              value: _windsteerLaylineAngle,
              onChanged: (v) => setState(() => _windsteerLaylineAngle = v),
            ),
          ),

        // Wind sector settings
        SwitchListTile(
          title: Text('Show Wind Sectors'),
          value: _windsteerWindSectorEnable,
          onChanged: (v) => setState(() => _windsteerWindSectorEnable = v),
        ),

        if (_windsteerWindSectorEnable)
          DropdownButtonFormField<int>(
            decoration: InputDecoration(labelText: 'Sector Time Window'),
            value: _windsteerSectorWindow,
            items: [
              DropdownMenuItem(value: 3, child: Text('3 seconds')),
              DropdownMenuItem(value: 5, child: Text('5 seconds')),
              DropdownMenuItem(value: 10, child: Text('10 seconds')),
              DropdownMenuItem(value: 30, child: Text('30 seconds')),
            ],
            onChanged: (v) => setState(() => _windsteerSectorWindow = v!),
          ),

        // Other feature toggles
        SwitchListTile(
          title: Text('Show Course Over Ground'),
          value: _windsteerCOGEnable,
          onChanged: (v) => setState(() => _windsteerCOGEnable = v),
        ),

        SwitchListTile(
          title: Text('Show Waypoint Bearing'),
          value: _windsteerWaypointEnable,
          onChanged: (v) => setState(() => _windsteerWaypointEnable = v),
        ),

        SwitchListTile(
          title: Text('Show Current/Drift'),
          value: _windsteerDriftEnable,
          onChanged: (v) => setState(() => _windsteerDriftEnable = v),
        ),

        Divider(),

        Text('Wind Displays'),

        SwitchListTile(
          title: Text('Show Apparent Wind Speed'),
          value: _windsteerAWSEnable,
          onChanged: (v) => setState(() => _windsteerAWSEnable = v),
        ),

        SwitchListTile(
          title: Text('Show True Wind Speed'),
          value: _windsteerTWSEnable,
          onChanged: (v) => setState(() => _windsteerTWSEnable = v),
        ),

        SwitchListTile(
          title: Text('Show True Wind Angle'),
          value: _windsteerTWAEnable,
          onChanged: (v) => setState(() => _windsteerTWAEnable = v),
        ),
      ],
    ),
  ),
```

---

### Phase 5: Performance Optimizations (Smooth Operation)

#### 5.1 - Update Throttling

**Epsilon Thresholds**:
```dart
static const double DEG_EPSILON = 1.0;      // degrees
static const double SPEED_EPSILON = 0.1;    // knots

void updateHeading(double newHeading) {
  if (_angleDelta(_currentHeading, newHeading) >= DEG_EPSILON) {
    setState(() => _currentHeading = newHeading);
  }
}

void updateWindSpeed(double newSpeed) {
  if ((_currentSpeed - newSpeed).abs() >= SPEED_EPSILON) {
    setState(() => _currentSpeed = newSpeed);
  }
}

double _angleDelta(double from, double to) {
  final delta = ((to - from + 540) % 360) - 180;
  return delta.abs();
}
```

**Animation Strategy**:
- Use single AnimationController per rotating element
- Duration: 900ms with easeInOut curve
- Cancel-and-replace if new update arrives during animation
- Use `AnimatedBuilder` to avoid full widget rebuilds

#### 5.2 - Wind Sector Performance

**Data Structure**:
- Fixed-size circular buffer for samples (max 1000 samples)
- Monotonic deques for O(1) min/max tracking
- Unwrapped angle domain to avoid discontinuities

**Update Strategy**:
- Add samples immediately (no throttling)
- Run cleanup every 1 second using Timer
- Only trigger repaint if sector values change > epsilon

**Memory Management**:
- Auto-cleanup samples older than 2x window duration
- Limit max samples to prevent unbounded growth

#### 5.3 - Canvas Optimization

**CustomPainter Best Practices**:
```dart
class WindsteerPainter extends CustomPainter {
  // Cache Paint objects
  final Paint _compassPaint = Paint()..style = PaintingStyle.stroke;
  final Paint _windPaint = Paint()..color = Colors.blue;

  @override
  bool shouldRepaint(WindsteerPainter oldDelegate) {
    // Only repaint if values changed
    return heading != oldDelegate.heading ||
           windAngle != oldDelegate.windAngle ||
           windSpeed != oldDelegate.windSpeed;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Use canvas.save()/restore() for transformations
    // Cache complex paths (TextPainter for labels)
    // Avoid creating new objects in paint()
  }
}
```

**Layer Optimization**:
- Static elements (compass ring): Paint once, cache
- Dynamic elements (indicators): Repaint only on change
- Text rendering: Use TextPainter cache

---

## Implementation Priority

### Minimum Viable Product (MVP)
**Goal**: Basic functional compass with wind indication

**Features**:
1. ✅ Compass dial with heading display
2. ✅ Rotating dial animation
3. ✅ AWA arrow indicator
4. ✅ AWS numerical display

**Estimated Effort**: 200-300 lines, 4-6 hours

**Deliverable**: Working compass tool showing heading and apparent wind

---

### Enhanced Version
**Goal**: Add tactical sailing features

**Features**:
5. ✅ TWA arrow + TWS display
6. ✅ COG indicator
7. ✅ Laylines (dashed tack lines)

**Estimated Effort**: +300-400 lines, 6-8 hours

**Deliverable**: Tactical compass with laylines for upwind sailing

---

### Full Featured
**Goal**: Complete advanced sailing instrument

**Features**:
8. ✅ Waypoint bearing indicator
9. ✅ Wind sectors (historical range)
10. ✅ Current/drift display

**Estimated Effort**: +400-600 lines, 8-12 hours

**Deliverable**: Professional-grade sailing compass with all features

---

## Technical Challenges & Solutions

| Challenge | Solution |
|-----------|----------|
| **Smooth rotation animations** | Use `AnimationController` with `Tween<double>` and shortest-path interpolation for angles |
| **0/360° angle wrapping** | Unwrap angles to continuous domain (-∞ to +∞), normalize only for display |
| **Performance with many paths** | Epsilon gating for updates, throttle repaints, use CustomPainter efficiently |
| **Wind sector calculation** | Monotonic deque algorithm for O(1) min/max (adapted from kip) |
| **Layline geometry** | Precompute in dial-local coordinate space, rotate passively with dial |
| **Text rendering** | Cache TextPainter instances, only recreate when text changes |
| **Responsive sizing** | Use relative coordinates (0-1000), scale canvas to widget size |
| **Memory management** | Limit wind sector samples, auto-cleanup old data |

---

## Testing Strategy

### Unit Tests
- Angle normalization functions
- Wind sector algorithm (add, remove, min/max)
- Epsilon gating logic
- Configuration serialization

### Widget Tests
- Widget renders without data
- Widget updates on data changes
- Animation completion
- Configuration toggles

### Integration Tests
- Full tool lifecycle
- SignalK data subscription
- State persistence
- Performance under load

---

## Future Enhancements

### Potential Additions:
1. **Polar Performance**: Overlay boat polar diagram
2. **Target Wind Angle**: Show optimal VMG angle
3. **Heel Angle**: Visual indicator of boat heel
4. **Race Start Timer**: Countdown integration
5. **Sail Configuration**: Visual sail plan indicator
6. **Performance Analytics**: Historical performance tracking
7. **Customizable Colors**: Full theme support
8. **Multiple Boat Views**: Show other vessels from AIS

### Configuration Additions:
- Color themes (day/night/red/custom)
- Font size scaling
- Animation speed control
- Data timeout handling
- Unit preferences per data type

---

## References

### Source Material:
- **Kip Project**: https://github.com/mxtommy/Kip
- **Windsteer Widget**: `/src/app/widgets/widget-windsteer/`
- **SVG Component**: `/src/app/widgets/svg-windsteer/`

### SignalK Documentation:
- **Navigation Paths**: https://signalk.org/specification/latest/doc/vesselsBranch.html#vesselsregexpnavigation
- **Environment Paths**: https://signalk.org/specification/latest/doc/vesselsBranch.html#vesselsregexpenvironment

### Flutter Documentation:
- **CustomPainter**: https://api.flutter.dev/flutter/rendering/CustomPainter-class.html
- **AnimationController**: https://api.flutter.dev/flutter/animation/AnimationController-class.html
- **Canvas API**: https://api.flutter.dev/flutter/dart-ui/Canvas-class.html

---

## Notes

- This widget is complex and feature-rich. Start with MVP and iterate.
- Performance is critical for smooth sailing experience at 60fps.
- The wind sector algorithm is sophisticated - consider copying kip's approach directly.
- Test with real SignalK data for accurate behavior.
- Consider accessibility: color blind modes, high contrast options.

---

**Status**: Ready for implementation
**Last Updated**: 2025-10-14
**Author**: Claude Code
