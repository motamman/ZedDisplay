# Windsteer Widget - Completion Plan

## Executive Summary

The Windsteer widget is **70% complete** with all visual rendering implemented but **missing critical features** for production use:
- ❌ **Smooth animations** (dial jumps instead of rotating smoothly)
- ❌ **Multi-path configuration UI** (can only configure 1 path, need 12)
- ❌ **Wind sector historical tracking** (visual rendering exists, but no data tracking algorithm)
- ❌ **Epsilon gating** (causes flickering from noisy sensor data)
- ❌ **Configuration UI** (can't adjust layline angle or toggle features)

**Current working solution:** `Windsteer (Auto)` tool with hardcoded paths - works immediately but not customizable.

---

## Current Implementation Status

### ✅ What's Complete (Visual Layer)

**File**: `lib/widgets/windsteer_gauge.dart`

| Feature | Status | Details |
|---------|--------|---------|
| Compass dial | ✅ Complete | Rotating dial with N/E/S/W labels, 10° tick marks |
| Port/starboard arcs | ✅ Complete | Red (port) and green (starboard) at top |
| AWA indicator | ✅ Complete | Blue arrow with "A" label |
| TWA indicator | ✅ Complete | Green arrow with "T" label |
| Wind speed displays | ✅ Complete | AWS (top-left), TWS (top-right) with formatted units |
| COG indicator | ✅ Complete | Orange diamond showing course over ground |
| Waypoint indicator | ✅ Complete | Purple circle showing bearing to waypoint |
| Drift/Set indicator | ✅ Complete | Cyan arrow showing current direction |
| Laylines | ✅ Complete | Dashed lines showing optimal sailing angles |
| Wind sectors | ✅ Complete | Shaded wedges (visual rendering only) |
| Boat icon | ✅ Complete | Center boat outline with centerline |
| Heading display | ✅ Complete | Top center with rounded background |
| Drift speed display | ✅ Complete | Center text showing current speed |

### ⚠️ What's Partial (Tool Integration)

**Files**:
- `lib/widgets/tools/windsteer_tool.dart` - Full tool (cannot be configured)
- `lib/widgets/tools/windsteer_demo_tool.dart` - Auto tool (works now)

| Feature | Status | Details |
|---------|--------|---------|
| Windsteer (Auto) tool | ✅ Working | Hardcoded paths, zero config, works immediately |
| Full Windsteer tool | ⚠️ Partial | Implementation exists but can't configure 12 paths |
| Style configuration | ⚠️ Partial | Colors work, but windsteer-specific options in customProperties |

### ❌ What's Missing (Critical Features)

| Feature | Priority | Impact |
|---------|----------|--------|
| Smooth animations | 🔴 Critical | Widget looks janky without smooth rotation |
| Multi-path config UI | 🔴 Critical | Can't configure full windsteer tool |
| Epsilon gating | 🔴 Critical | Causes flickering, wastes battery |
| Wind sector tracking | 🟠 Important | Wind sectors won't work without historical data |
| Configuration UI | 🟠 Important | Can't adjust layline angle or toggle features |
| Paint caching | 🟡 Nice to have | Performance optimization |
| WindsteerConfig model | 🟡 Nice to have | Better structure than customProperties |

---

## Missing Feature Details

### 1. Smooth Animations ❌ (Critical)

**Current Behavior:**
- Compass dial **jumps** to new heading instantly
- Indicators **snap** to new positions
- Looks choppy and unprofessional

**Expected Behavior (from Kip):**
- 900ms smooth rotation animation
- `easeInOut` curve for natural motion
- Shortest-path interpolation for angles (e.g., 359° to 1° goes +2° not -358°)
- AnimatedBuilder to avoid full widget rebuilds

**Implementation Needed:**

```dart
// File: lib/widgets/tools/windsteer_tool.dart (needs refactor to StatefulWidget)

class WindsteerTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  @override
  State<WindsteerTool> createState() => _WindsteerToolState();
}

class _WindsteerToolState extends State<WindsteerTool>
    with SingleTickerProviderStateMixin {

  // Animation controller
  late AnimationController _rotationController;

  // Current animated values
  double _currentHeading = 0.0;
  double _targetHeading = 0.0;
  double _currentAWA = 0.0;
  double _targetAWA = 0.0;

  // Animation constants
  static const Duration ANIM_DURATION = Duration(milliseconds: 900);
  static const Curve ANIM_CURVE = Curves.easeInOut;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: ANIM_DURATION,
    );
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  void _updateHeading(double newHeading) {
    setState(() {
      _currentHeading = _targetHeading;
      _targetHeading = newHeading;
    });

    // Animate to new heading
    _rotationController.forward(from: 0);
  }

  double _interpolateAngle(double t) {
    // Shortest path interpolation
    double delta = _targetHeading - _currentHeading;

    // Normalize delta to -180 to +180 range
    while (delta > 180) delta -= 360;
    while (delta < -180) delta += 360;

    return _currentHeading + (delta * t);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _rotationController,
      builder: (context, child) {
        final t = ANIM_CURVE.transform(_rotationController.value);
        final animatedHeading = _interpolateAngle(t);

        return WindsteerGauge(
          heading: animatedHeading,
          // ... other properties
        );
      },
    );
  }
}
```

**Files to Modify:**
- `lib/widgets/tools/windsteer_tool.dart` - Convert to StatefulWidget with animations
- `lib/widgets/tools/windsteer_demo_tool.dart` - Add animation support

**Effort**: 4-6 hours
**Lines of Code**: +150-200

---

### 2. Epsilon Gating ❌ (Critical)

**Problem:**
Every tiny sensor update triggers a repaint, even if the change is < 0.1°. This causes:
- Visual flickering
- Unnecessary CPU usage
- Battery drain
- Jittery indicators

**Solution:**
Only update if change exceeds threshold (epsilon):

```dart
class _WindsteerToolState extends State<WindsteerTool> {
  // Epsilon thresholds
  static const double DEG_EPSILON = 1.0;      // 1 degree
  static const double SPEED_EPSILON = 0.1;    // 0.1 knots

  // Previous values
  double _prevHeading = 0.0;
  double _prevAWS = 0.0;

  void _onHeadingUpdate(double newHeading) {
    if (_angleDelta(_prevHeading, newHeading) >= DEG_EPSILON) {
      _updateHeading(newHeading);
      _prevHeading = newHeading;
    }
  }

  void _onSpeedUpdate(double newSpeed) {
    if ((newSpeed - _prevAWS).abs() >= SPEED_EPSILON) {
      setState(() => _apparentWindSpeed = newSpeed);
      _prevAWS = newSpeed;
    }
  }

  double _angleDelta(double from, double to) {
    double delta = (to - from + 540) % 360 - 180;
    return delta.abs();
  }
}
```

**Files to Modify:**
- `lib/widgets/tools/windsteer_tool.dart`
- `lib/widgets/tools/windsteer_demo_tool.dart`

**Effort**: 2-3 hours
**Lines of Code**: +80-100

---

### 3. Wind Sector Historical Tracking Algorithm ❌ (Important)

**Current State:**
- Wind sectors **render** correctly (visual wedges)
- But NO algorithm to track historical wind data
- Expects paths 9-11 to provide pre-computed min/mid/max (won't exist on most servers)

**Expected Behavior:**
- Track TWA samples over time window (5 seconds default)
- Calculate min/mid/max angles from recent samples
- Use efficient O(1) algorithm (monotonic deques)
- Handle angle wrapping (359° to 1° transition)

**Kip Algorithm (TypeScript → Dart):**

```dart
// File: lib/services/wind_sector_tracker.dart (NEW FILE)

import 'dart:collection';

class WindSample {
  final DateTime timestamp;
  final double angle;        // Unwrapped angle
  final int index;          // Sample index

  WindSample(this.timestamp, this.angle, this.index);
}

class WindMinMax {
  final int index;
  final double value;

  WindMinMax(this.index, this.value);
}

class SectorAngles {
  final double min;
  final double mid;
  final double max;

  SectorAngles({
    required this.min,
    required this.mid,
    required this.max,
  });
}

class WindSectorTracker {
  final Duration windowDuration;

  final List<WindSample> _samples = [];
  final Queue<WindMinMax> _minDeque = Queue();  // Monotonic increasing
  final Queue<WindMinMax> _maxDeque = Queue();  // Monotonic decreasing

  int _sampleIndex = 0;
  double _unwrapOffset = 0.0;  // For angle continuity
  double? _lastAngle;

  WindSectorTracker({this.windowDuration = const Duration(seconds: 5)});

  /// Add a new wind angle sample
  void addSample(double angle) {
    // Unwrap angle to continuous domain
    final unwrapped = _unwrapAngle(angle);

    // Add to samples
    final sample = WindSample(DateTime.now(), unwrapped, _sampleIndex++);
    _samples.add(sample);

    // Update min deque (maintain increasing values)
    while (_minDeque.isNotEmpty && _minDeque.last.value >= unwrapped) {
      _minDeque.removeLast();
    }
    _minDeque.add(WindMinMax(_sampleIndex - 1, unwrapped));

    // Update max deque (maintain decreasing values)
    while (_maxDeque.isNotEmpty && _maxDeque.last.value <= unwrapped) {
      _maxDeque.removeLast();
    }
    _maxDeque.add(WindMinMax(_sampleIndex - 1, unwrapped));
  }

  /// Unwrap angle to continuous domain (no 0/360 jumps)
  double _unwrapAngle(double angle) {
    if (_lastAngle == null) {
      _lastAngle = angle;
      return angle;
    }

    final delta = angle - _lastAngle!;

    // Detect wraparound
    if (delta > 180) {
      _unwrapOffset -= 360;
    } else if (delta < -180) {
      _unwrapOffset += 360;
    }

    _lastAngle = angle;
    return angle + _unwrapOffset;
  }

  /// Remove samples older than window
  void cleanup() {
    final cutoff = DateTime.now().subtract(windowDuration);

    while (_samples.isNotEmpty && _samples.first.timestamp.isBefore(cutoff)) {
      final removed = _samples.removeAt(0);

      // Clean up deques if they reference removed sample
      if (_minDeque.isNotEmpty && _minDeque.first.index == removed.index) {
        _minDeque.removeFirst();
      }
      if (_maxDeque.isNotEmpty && _maxDeque.first.index == removed.index) {
        _maxDeque.removeFirst();
      }
    }
  }

  /// Get current sector angles
  SectorAngles? get current {
    if (_minDeque.isEmpty || _maxDeque.isEmpty) return null;

    final min = _normalizeAngle(_minDeque.first.value);
    final max = _normalizeAngle(_maxDeque.first.value);
    final mid = _normalizeAngle((_minDeque.first.value + _maxDeque.first.value) / 2);

    return SectorAngles(min: min, mid: mid, max: max);
  }

  /// Normalize angle back to 0-360 range
  double _normalizeAngle(double angle) {
    double normalized = angle % 360;
    if (normalized < 0) normalized += 360;
    return normalized;
  }

  /// Clear all samples
  void clear() {
    _samples.clear();
    _minDeque.clear();
    _maxDeque.clear();
    _sampleIndex = 0;
    _unwrapOffset = 0.0;
    _lastAngle = null;
  }
}
```

**Integration with Windsteer Tool:**

```dart
class _WindsteerToolState extends State<WindsteerTool> {
  WindSectorTracker? _sectorTracker;
  Timer? _cleanupTimer;

  @override
  void initState() {
    super.initState();

    // Create tracker if wind sectors enabled
    if (widget.config.style.customProperties?['showWindSectors'] == true) {
      final windowSeconds = widget.config.style.customProperties?['windSectorWindowSeconds'] ?? 5;
      _sectorTracker = WindSectorTracker(
        windowDuration: Duration(seconds: windowSeconds),
      );

      // Start cleanup timer (runs every 1 second)
      _cleanupTimer = Timer.periodic(Duration(seconds: 1), (_) {
        _sectorTracker?.cleanup();
      });
    }
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    super.dispose();
  }

  void _onTrueWindAngleUpdate(double twa) {
    _sectorTracker?.addSample(twa);

    // Get current sector angles
    final sector = _sectorTracker?.current;
    if (sector != null) {
      setState(() {
        _trueWindMinHistoric = sector.min;
        _trueWindMidHistoric = sector.mid;
        _trueWindMaxHistoric = sector.max;
      });
    }
  }
}
```

**Files to Create:**
- `lib/services/wind_sector_tracker.dart` (NEW)

**Files to Modify:**
- `lib/widgets/tools/windsteer_tool.dart`
- `lib/widgets/tools/windsteer_demo_tool.dart`

**Effort**: 6-8 hours
**Lines of Code**: +300-400

---

### 4. Multi-Path Configuration UI ❌ (Critical)

**Problem:**
Current `tool_config_screen.dart` only supports configuring **1 data path**. Windsteer needs **up to 12 paths**:
1. Heading (required)
2. AWA
3. TWA
4. AWS
5. TWS
6. COG
7. Waypoint bearing
8. Drift set
9. Drift flow
10-12. Historical wind (if not using tracker)

**Solution:**
Create a multi-path configuration screen.

**File to Create**: `lib/screens/multi_path_config_screen.dart`

```dart
import 'package:flutter/material.dart';
import '../models/tool_config.dart';

class MultiPathConfigScreen extends StatefulWidget {
  final String toolTypeId;
  final int maxPaths;
  final List<DataSource> initialSources;

  const MultiPathConfigScreen({
    super.key,
    required this.toolTypeId,
    required this.maxPaths,
    this.initialSources = const [],
  });

  @override
  State<MultiPathConfigScreen> createState() => _MultiPathConfigScreenState();
}

class _MultiPathConfigScreenState extends State<MultiPathConfigScreen> {
  late List<DataSource?> _dataSources;

  @override
  void initState() {
    super.initState();
    _dataSources = List.filled(widget.maxPaths, null);

    // Load initial sources
    for (int i = 0; i < widget.initialSources.length && i < widget.maxPaths; i++) {
      _dataSources[i] = widget.initialSources[i];
    }
  }

  void _addPath(int index) async {
    // Open path selector dialog
    final path = await _showPathSelector();
    if (path != null) {
      setState(() {
        _dataSources[index] = DataSource(path: path);
      });
    }
  }

  void _removePath(int index) {
    setState(() {
      _dataSources[index] = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Configure ${widget.toolTypeId} Paths'),
        actions: [
          TextButton.icon(
            icon: Icon(Icons.check),
            label: Text('Save'),
            onPressed: () {
              // Return configured paths
              final configured = _dataSources
                  .where((ds) => ds != null)
                  .cast<DataSource>()
                  .toList();
              Navigator.pop(context, configured);
            },
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          Text(
            'Data Paths',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SizedBox(height: 16),

          // Path slot 0 (required)
          _buildPathSlot(0, 'Heading', required: true),
          _buildPathSlot(1, 'Apparent Wind Angle'),
          _buildPathSlot(2, 'True Wind Angle'),
          _buildPathSlot(3, 'Apparent Wind Speed'),
          _buildPathSlot(4, 'True Wind Speed'),
          _buildPathSlot(5, 'Course Over Ground'),
          _buildPathSlot(6, 'Waypoint Bearing'),
          _buildPathSlot(7, 'Drift Set'),
          _buildPathSlot(8, 'Drift Flow'),

          // Show remaining slots as expandable
          if (widget.maxPaths > 9)
            ExpansionTile(
              title: Text('Additional Paths'),
              children: [
                for (int i = 9; i < widget.maxPaths; i++)
                  _buildPathSlot(i, 'Path ${i + 1}'),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPathSlot(int index, String label, {bool required = false}) {
    final source = _dataSources[index];

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(
          source != null ? Icons.check_circle : Icons.radio_button_unchecked,
          color: source != null ? Colors.green : Colors.grey,
        ),
        title: Text('${index + 1}. $label ${required ? "(Required)" : ""}'),
        subtitle: source != null
            ? Text(source.path, style: TextStyle(fontSize: 12))
            : Text('Not configured', style: TextStyle(color: Colors.grey)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (source != null)
              IconButton(
                icon: Icon(Icons.edit, size: 20),
                onPressed: () => _addPath(index),
              ),
            if (source == null)
              IconButton(
                icon: Icon(Icons.add, size: 20),
                onPressed: () => _addPath(index),
              ),
            if (source != null && !required)
              IconButton(
                icon: Icon(Icons.close, size: 20),
                onPressed: () => _removePath(index),
              ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showPathSelector() async {
    // Show path selection dialog
    // (Use existing PathSelectorDialog)
    return null; // Placeholder
  }
}
```

**Integration with Tool Config Screen:**

```dart
// In tool_config_screen.dart

// Replace single path selector with:
if (definition.configSchema.allowsMultiplePaths &&
    definition.configSchema.maxPaths > 1) {
  // Show multi-path button
  ListTile(
    leading: Icon(Icons.route),
    title: Text('Data Paths (${_dataSources.length} configured)'),
    trailing: Icon(Icons.edit),
    onTap: () async {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MultiPathConfigScreen(
            toolTypeId: _selectedToolTypeId!,
            maxPaths: definition.configSchema.maxPaths,
            initialSources: _dataSources,
          ),
        ),
      );
      if (result != null) {
        setState(() => _dataSources = result);
      }
    },
  ),
}
```

**Files to Create:**
- `lib/screens/multi_path_config_screen.dart`

**Files to Modify:**
- `lib/screens/tool_config_screen.dart`

**Effort**: 8-10 hours
**Lines of Code**: +400-500

---

### 5. Windsteer-Specific Configuration UI ❌ (Important)

**Current State:**
- Can configure colors
- Can't configure layline angle (stuck at 45°)
- Can't toggle wind sectors on/off
- Can't set wind sector time window
- No UI for feature toggles

**Solution:**
Add windsteer-specific settings panel to `tool_config_screen.dart`:

```dart
// In tool_config_screen.dart

// Add state variables
double _laylineAngle = 45.0;
bool _showLaylines = true;
bool _showWindSectors = false;
int _windSectorWindow = 5;
bool _showCOG = false;
bool _showWaypoint = false;
bool _showDrift = false;

// In build() method, add after style configuration:

if (_selectedToolTypeId == 'windsteer')
  Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Windsteer Settings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: 16),

          // Laylines
          SwitchListTile(
            title: Text('Show Laylines'),
            subtitle: Text('Close-hauled sailing lines'),
            value: _showLaylines,
            onChanged: (v) => setState(() => _showLaylines = v),
          ),

          if (_showLaylines)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Layline Angle: ${_laylineAngle.round()}°'),
                  Slider(
                    value: _laylineAngle,
                    min: 30,
                    max: 60,
                    divisions: 30,
                    label: '${_laylineAngle.round()}°',
                    onChanged: (v) => setState(() => _laylineAngle = v),
                  ),
                  Text(
                    'Adjust based on boat performance',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),

          Divider(),

          // Wind Sectors
          SwitchListTile(
            title: Text('Show Wind Sectors'),
            subtitle: Text('Historical wind shift range'),
            value: _showWindSectors,
            onChanged: (v) => setState(() => _showWindSectors = v),
          ),

          if (_showWindSectors)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonFormField<int>(
                decoration: InputDecoration(
                  labelText: 'Time Window',
                  border: OutlineInputBorder(),
                ),
                value: _windSectorWindow,
                items: [
                  DropdownMenuItem(value: 3, child: Text('3 seconds')),
                  DropdownMenuItem(value: 5, child: Text('5 seconds')),
                  DropdownMenuItem(value: 10, child: Text('10 seconds')),
                  DropdownMenuItem(value: 30, child: Text('30 seconds')),
                ],
                onChanged: (v) => setState(() => _windSectorWindow = v!),
              ),
            ),

          Divider(),

          // Navigation indicators
          Text('Navigation Indicators', style: Theme.of(context).textTheme.titleSmall),
          SwitchListTile(
            title: Text('Course Over Ground'),
            value: _showCOG,
            onChanged: (v) => setState(() => _showCOG = v),
          ),
          SwitchListTile(
            title: Text('Waypoint Bearing'),
            value: _showWaypoint,
            onChanged: (v) => setState(() => _showWaypoint = v),
          ),
          SwitchListTile(
            title: Text('Current/Drift'),
            value: _showDrift,
            onChanged: (v) => setState(() => _showDrift = v),
          ),
        ],
      ),
    ),
  ),
```

**Save configuration to customProperties:**

```dart
// In _saveTool() method:

if (_selectedToolTypeId == 'windsteer') {
  customProperties = {
    'laylineAngle': _laylineAngle,
    'showLaylines': _showLaylines,
    'showWindSectors': _showWindSectors,
    'windSectorWindowSeconds': _windSectorWindow,
    'showCOG': _showCOG,
    'showWaypoint': _showWaypoint,
    'showDrift': _showDrift,
  };
}
```

**Files to Modify:**
- `lib/screens/tool_config_screen.dart`

**Effort**: 3-4 hours
**Lines of Code**: +150-200

---

### 6. Performance Optimizations ❌ (Nice to Have)

**Paint Object Caching:**

```dart
// In windsteer_gauge.dart

class _WindsteerPainter extends CustomPainter {
  // Cache paint objects (create once, reuse)
  static final Paint _compassRingPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 20;

  static final Paint _portArcPaint = Paint()
    ..color = Colors.red
    ..style = PaintingStyle.stroke
    ..strokeWidth = 15
    ..strokeCap = StrokeCap.round;

  static final Paint _stbdArcPaint = Paint()
    ..color = Colors.green
    ..style = PaintingStyle.stroke
    ..strokeWidth = 15
    ..strokeCap = StrokeCap.round;

  // ... rest of painter
}
```

**TextPainter Caching:**

```dart
class _WindsteerPainter extends CustomPainter {
  // Cache text painters
  final Map<String, TextPainter> _textCache = {};

  TextPainter _getTextPainter(String text, TextStyle style) {
    final key = '$text-${style.fontSize}-${style.color}';
    if (_textCache.containsKey(key)) {
      return _textCache[key]!;
    }

    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    _textCache[key] = painter;
    return painter;
  }
}
```

**Files to Modify:**
- `lib/widgets/windsteer_gauge.dart`

**Effort**: 2-3 hours
**Lines of Code**: +50-80

---

### 7. WindsteerConfig Model ❌ (Nice to Have)

**Current State:**
- Configuration scattered across `StyleConfig.customProperties` (unstructured map)
- No defaults or validation
- Hard to maintain

**Better Solution:**

```dart
// File: lib/models/windsteer_config.dart (NEW FILE)

import 'package:json_annotation/json_annotation.dart';

part 'windsteer_config.g.dart';

@JsonSerializable()
class WindsteerConfig {
  // Feature toggles
  final bool showLaylines;
  final bool showWindSectors;
  final bool showCOG;
  final bool showWaypoint;
  final bool showDrift;
  final bool showAWS;
  final bool showTWS;
  final bool showTrueWind;

  // Layline settings
  final double laylineAngle;  // 30-60°

  // Wind sector settings
  final int windSectorWindowSeconds;  // 3-30s

  // Style
  final String? primaryColor;
  final String? secondaryColor;

  const WindsteerConfig({
    this.showLaylines = true,
    this.showWindSectors = true,
    this.showCOG = false,
    this.showWaypoint = false,
    this.showDrift = false,
    this.showAWS = true,
    this.showTWS = true,
    this.showTrueWind = true,
    this.laylineAngle = 45.0,
    this.windSectorWindowSeconds = 5,
    this.primaryColor,
    this.secondaryColor,
  });

  factory WindsteerConfig.fromJson(Map<String, dynamic> json) =>
      _$WindsteerConfigFromJson(json);

  Map<String, dynamic> toJson() => _$WindsteerConfigToJson(this);

  WindsteerConfig copyWith({
    bool? showLaylines,
    bool? showWindSectors,
    bool? showCOG,
    bool? showWaypoint,
    bool? showDrift,
    bool? showAWS,
    bool? showTWS,
    bool? showTrueWind,
    double? laylineAngle,
    int? windSectorWindowSeconds,
    String? primaryColor,
    String? secondaryColor,
  }) {
    return WindsteerConfig(
      showLaylines: showLaylines ?? this.showLaylines,
      showWindSectors: showWindSectors ?? this.showWindSectors,
      showCOG: showCOG ?? this.showCOG,
      showWaypoint: showWaypoint ?? this.showWaypoint,
      showDrift: showDrift ?? this.showDrift,
      showAWS: showAWS ?? this.showAWS,
      showTWS: showTWS ?? this.showTWS,
      showTrueWind: showTrueWind ?? this.showTrueWind,
      laylineAngle: laylineAngle ?? this.laylineAngle,
      windSectorWindowSeconds: windSectorWindowSeconds ?? this.windSectorWindowSeconds,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
    );
  }
}
```

**Files to Create:**
- `lib/models/windsteer_config.dart`

**Files to Modify:**
- `lib/widgets/tools/windsteer_tool.dart` - Use WindsteerConfig instead of customProperties

**Effort**: 2-3 hours
**Lines of Code**: +120-150

---

## Implementation Roadmap

### Phase 1: Critical Fixes (Production-Ready) - ~2 weeks

**Goal:** Make the windsteer tool usable and professional-looking

**Tasks:**
1. ✅ **Smooth Animations** (4-6 hours)
   - Convert windsteer_tool to StatefulWidget
   - Add AnimationController
   - Implement shortest-path angle interpolation
   - Use AnimatedBuilder for efficient rebuilds

2. ✅ **Epsilon Gating** (2-3 hours)
   - Add threshold constants
   - Implement angle delta function
   - Gate updates in data subscription handlers

3. ✅ **Multi-Path Configuration UI** (8-10 hours)
   - Create MultiPathConfigScreen
   - Update tool_config_screen.dart
   - Test with windsteer tool

**Deliverable:** Smooth, professional windsteer tool that can be configured through UI

**Effort:** ~14-19 hours

---

### Phase 2: Advanced Features - ~1 week

**Goal:** Complete tactical sailing features

**Tasks:**
4. ✅ **Wind Sector Tracking** (6-8 hours)
   - Create WindSectorTracker service
   - Implement monotonic deque algorithm
   - Add angle unwrapping logic
   - Integrate with windsteer tool
   - Add cleanup timer

5. ✅ **Windsteer Configuration UI** (3-4 hours)
   - Add windsteer-specific settings panel
   - Layline angle slider
   - Wind sector time window dropdown
   - Feature toggle switches

**Deliverable:** Full-featured tactical sailing compass with wind sectors

**Effort:** ~9-12 hours

---

### Phase 3: Polish & Optimization - ~3 days

**Goal:** Performance and code quality improvements

**Tasks:**
6. ✅ **Paint Caching** (2-3 hours)
   - Cache Paint objects
   - Cache TextPainter instances
   - Optimize shouldRepaint

7. ✅ **WindsteerConfig Model** (2-3 hours)
   - Create structured config model
   - Add JSON serialization
   - Replace customProperties usage

8. ✅ **Testing** (2-3 hours)
   - Test all features with real SignalK data
   - Verify animations are smooth
   - Check performance (60fps target)
   - Test landscape overflow fix still works

**Deliverable:** Optimized, production-ready windsteer widget

**Effort:** ~6-9 hours

---

## Total Effort Estimate

| Phase | Effort | Calendar Time |
|-------|--------|---------------|
| Phase 1 (Critical) | 14-19 hours | 2 weeks |
| Phase 2 (Advanced) | 9-12 hours | 1 week |
| Phase 3 (Polish) | 6-9 hours | 3 days |
| **Total** | **29-40 hours** | **3-4 weeks** |

---

## Priority Matrix

### Must Have (MVP)
1. 🔴 Smooth animations - Without this, looks unprofessional
2. 🔴 Epsilon gating - Prevents flickering
3. 🔴 Multi-path config UI - Can't configure tool otherwise

### Should Have (Enhanced)
4. 🟠 Wind sector tracking - Makes wind sectors actually work
5. 🟠 Configuration UI - Adjust layline angle, toggles

### Nice to Have (Polish)
6. 🟡 Paint caching - Performance boost
7. 🟡 WindsteerConfig model - Code quality

---

## Testing Checklist

### Visual Tests
- [ ] Compass dial rotates smoothly (not jerky)
- [ ] AWA arrow animates to new positions
- [ ] Wind sectors appear and update correctly
- [ ] Laylines adjust when AWA changes
- [ ] All indicators visible when data available
- [ ] Works in portrait and landscape
- [ ] No overflow errors

### Functional Tests
- [ ] Can configure all 12 data paths
- [ ] Layline angle slider works (30-60°)
- [ ] Wind sector window changes take effect
- [ ] Feature toggles hide/show indicators
- [ ] Epsilon gating prevents flickering
- [ ] Wind sector tracker handles angle wrapping correctly

### Performance Tests
- [ ] Maintains 60fps during animations
- [ ] No jank when switching data sources
- [ ] Wind sector tracking doesn't cause lag
- [ ] Memory usage stays stable over time

### Integration Tests
- [ ] Works with real SignalK server
- [ ] Handles missing data paths gracefully
- [ ] Saves/loads configuration correctly
- [ ] Windsteer (Auto) still works

---

## Files Summary

### Files to Create:
1. `lib/services/wind_sector_tracker.dart` - Wind sector algorithm
2. `lib/screens/multi_path_config_screen.dart` - Multi-path UI
3. `lib/models/windsteer_config.dart` - Structured config model

### Files to Modify:
1. `lib/widgets/tools/windsteer_tool.dart` - Add animations, epsilon gating, wind sector integration
2. `lib/widgets/tools/windsteer_demo_tool.dart` - Add animations, epsilon gating
3. `lib/screens/tool_config_screen.dart` - Add windsteer settings, multi-path support
4. `lib/widgets/windsteer_gauge.dart` - Add paint caching

### Files Complete (No Changes Needed):
1. `lib/widgets/windsteer_gauge.dart` - Visual rendering (done)
2. `lib/models/tool_config.dart` - Config model (supports customProperties)
3. `lib/services/tool_registry.dart` - Tool registration (done)

---

## Current Working Solution

While implementing the above features, users can use:

**Windsteer (Auto)** - Available now in tool menu
- Zero configuration
- Auto-detects standard SignalK paths
- Shows all available indicators
- Limitations:
  - No animations (yet)
  - Hardcoded paths
  - Can't customize layline angle
  - No wind sectors (no historical tracking)

---

## References

- **Original Plan**: `docs/windsteer_widget_plan.md`
- **Implementation Status**: `docs/windsteer-implementation.md`
- **Kip Source**: `/Users/mauricetamman/Documents/zennora/signalk/Kip/src/app/widgets/svg-windsteer/`

---

**Status**: Ready for Phase 1 implementation
**Last Updated**: 2025-10-15
**Document**: Completion Plan
