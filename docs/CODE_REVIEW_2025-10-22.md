# Code Review and Refactoring Plan

**Date**: 2025-10-22
**Version**: 0.2.0+3
**Reviewer**: Automated Code Analysis

## Executive Summary

This codebase is well-structured with clear separation of concerns, but suffers from significant code duplication across tool implementations. The main issues are:

- **High redundancy** in tool widget logic (10+ duplicate implementations)
- **Large files** that need refactoring (1,659 lines in tool_config_screen.dart, 1,321 in signalk_service.dart)
- **Repeated patterns** that should be abstracted into utility functions or base classes
- **Performance considerations** with zone fetching and missing const constructors

**Estimated Impact**:
- Duplicate code reduction: 40-50% reduction in tool widget code
- Performance improvement: 30-50% faster dashboard load with zone caching
- Maintainability: Major improvement after refactoring large files

---

## 1. Code Redundancy Issues

### CRITICAL: Duplicate `_getDefaultLabel()` Method

**Occurrences**: 25 copies across 10 files

**Affected Files**:
- `/lib/widgets/tools/text_display_tool.dart` (lines 105-120)
- `/lib/widgets/tools/radial_gauge_tool.dart` (lines 165-180)
- `/lib/widgets/tools/compass_gauge_tool.dart` (lines 78-93)
- `/lib/widgets/tools/slider_tool.dart` (lines 242-257)
- `/lib/widgets/tools/switch_tool.dart` (lines 190-205)
- `/lib/widgets/tools/knob_tool.dart` (lines 303-318)
- `/lib/widgets/tools/dropdown_tool.dart` (lines 264-279)
- `/lib/widgets/tools/checkbox_tool.dart` (lines 186-201)
- `/lib/widgets/tools/linear_gauge_tool.dart` (lines 625-639)

**Current Implementation**:
```dart
String _getDefaultLabel(String path) {
  final parts = path.split('.');
  if (parts.isEmpty) return path;
  final lastPart = parts.last;
  final result = lastPart.replaceAllMapped(
    RegExp(r'([A-Z])'),
    (match) => ' ${match.group(1)}',
  ).trim();
  return result.isEmpty ? lastPart : result;
}
```

**Problem**:
- 25 copies of identical code
- Changes require updating all copies
- Increases bundle size unnecessarily
- Violates DRY principle

**Solution**:
```dart
// Create: lib/utils/string_extensions.dart
extension StringExtensions on String {
  String toReadableLabel() {
    final parts = split('.');
    if (parts.isEmpty) return this;
    final lastPart = parts.last;
    final result = lastPart.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)}',
    ).trim();
    return result.isEmpty ? lastPart : result;
  }
}

// Usage in tools:
final label = dataSource.label ?? dataSource.path.toReadableLabel();
```

**Effort**: 2-4 hours
**Savings**: ~500 lines of code

---

### CRITICAL: Duplicate Color Parsing Logic

**Occurrences**: 24 copies across 18 files

**Example** (text_display_tool.dart lines 48-57):
```dart
Color textColor = Theme.of(context).colorScheme.onSurface;
if (config.style.primaryColor != null) {
  try {
    final colorString = config.style.primaryColor!.replaceAll('#', '');
    textColor = Color(int.parse('FF$colorString', radix: 16));
  } catch (e) {
    // Keep default color if parsing fails
  }
}
```

**Problem**:
- Identical color parsing logic repeated 24 times
- Same error handling in every instance
- No centralized validation

**Solution**:
```dart
// Create: lib/utils/color_extensions.dart
extension ColorParsing on String {
  Color toColor({Color? fallback}) {
    try {
      final colorString = replaceAll('#', '');
      return Color(int.parse('FF$colorString', radix: 16));
    } catch (e) {
      return fallback ?? Colors.grey;
    }
  }
}

// Usage:
final textColor = config.style.primaryColor?.toColor(
  fallback: Theme.of(context).colorScheme.onSurface
) ?? Theme.of(context).colorScheme.onSurface;
```

**Effort**: 1-2 hours
**Savings**: ~300 lines of code

---

### HIGH: Duplicate `_sendValue()` Method in Control Tools

**Affected Files**:
- `/lib/widgets/tools/slider_tool.dart` (lines 200-240)
- `/lib/widgets/tools/knob_tool.dart` (lines 261-301)
- `/lib/widgets/tools/dropdown_tool.dart` (lines 222-262)

**Current Implementation**:
```dart
Future<void> _sendValue(double value, String path) async {
  setState(() { _isSending = true; });
  try {
    final decimalPlaces = widget.config.style.customProperties?['decimalPlaces'] as int? ?? 1;
    final multiplier = pow(10, decimalPlaces).toDouble();
    final roundedValue = (value * multiplier).round() / multiplier;
    await widget.signalKService.sendPutRequest(path, roundedValue);
    // SnackBar logic...
  } catch (e) {
    // Error handling...
  } finally {
    setState(() { _isSending = false; _currentKnobValue = null; });
  }
}
```

**Problem**:
- 3 nearly identical implementations (~200 lines total)
- Same snackbar logic, error handling, state management
- Changes to PUT request logic require 3 updates

**Solution**:
```dart
// Create: lib/widgets/tools/mixins/control_tool_mixin.dart
mixin ControlToolMixin<T extends StatefulWidget> on State<T> {
  bool _isSending = false;

  Future<void> sendNumericValue({
    required double value,
    required String path,
    required SignalKService signalKService,
    required int decimalPlaces,
    required String label,
  }) async {
    setState(() { _isSending = true; });
    try {
      final multiplier = pow(10, decimalPlaces).toDouble();
      final roundedValue = (value * multiplier).round() / multiplier;
      await signalKService.sendPutRequest(path, roundedValue);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label set to ${roundedValue.toStringAsFixed(decimalPlaces)}'),
            duration: const Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set value: $e'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() { _isSending = false; });
      }
    }
  }
}
```

**Effort**: 3-4 hours
**Savings**: ~200 lines of code

---

### HIGH: Duplicate Boolean Parsing Logic

**Affected Files**:
- `/lib/widgets/tools/switch_tool.dart` (lines 35-46)
- `/lib/widgets/tools/checkbox_tool.dart` (lines 35-46)

**Current Implementation**:
```dart
bool currentValue = false;
if (dataPoint?.value is bool) {
  currentValue = dataPoint!.value as bool;
} else if (dataPoint?.value is num) {
  currentValue = (dataPoint!.value as num) != 0;
} else if (dataPoint?.value is String) {
  final stringValue = (dataPoint!.value as String).toLowerCase();
  currentValue = stringValue == 'true' || stringValue == '1';
}
```

**Solution**:
```dart
// Add to: lib/models/signalk_data_point.dart or create utility
extension BooleanValue on SignalKDataPoint? {
  bool toBool() {
    final value = this?.value;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final str = value.toLowerCase();
      return str == 'true' || str == '1';
    }
    return false;
  }
}

// Usage:
final currentValue = dataPoint.toBool();
```

**Effort**: 1 hour
**Savings**: ~20 lines of code, improved consistency

---

### MEDIUM: Duplicate Zones Service Initialization Pattern

**Affected Files**:
- `/lib/widgets/tools/radial_gauge_tool.dart` (lines 26-92)
- `/lib/widgets/tools/linear_gauge_tool.dart` (lines 34-92)

**Problem**:
Both gauge tools implement identical zone service initialization logic (60+ lines each)

**Solution**:
```dart
// Create: lib/widgets/tools/mixins/zones_mixin.dart
mixin ZonesMixin<T extends StatefulWidget> on State<T> {
  ZonesService? zonesService;
  List<ZoneDefinition>? zones;
  bool _listenerAdded = false;

  void initializeZones(SignalKService signalKService, String path) {
    if (signalKService.isConnected) {
      _createZonesServiceAndFetch(signalKService, path);
    } else {
      signalKService.addListener(() => _onConnectionChanged(signalKService, path));
      _listenerAdded = true;
    }
  }

  void _createZonesServiceAndFetch(SignalKService signalKService, String path) {
    zonesService = ZonesService(
      serverUrl: signalKService.serverUrl,
      useSecureConnection: signalKService.useSecureConnection,
    );
    _fetchZones(path);
  }

  Future<void> _fetchZones(String path) async {
    try {
      final pathZones = await zonesService!.fetchZones(path);
      if (pathZones != null && pathZones.hasZones && mounted) {
        setState(() {
          zones = pathZones.zones;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to fetch zones: $e');
      }
    }
  }

  void _onConnectionChanged(SignalKService signalKService, String path) {
    if (signalKService.isConnected && mounted) {
      signalKService.removeListener(() => _onConnectionChanged(signalKService, path));
      _listenerAdded = false;
      _createZonesServiceAndFetch(signalKService, path);
    }
  }

  void cleanupZones(SignalKService signalKService) {
    if (_listenerAdded) {
      signalKService.removeListener(() => _onConnectionChanged(signalKService, ''));
    }
  }
}
```

**Effort**: 2-3 hours
**Savings**: ~120 lines of code

---

### MEDIUM: Similar Widget Building Patterns for Card-Based Controls

**Affected Files**:
- `/lib/widgets/tools/slider_tool.dart` (lines 82-197)
- `/lib/widgets/tools/knob_tool.dart` (lines 81-258)
- `/lib/widgets/tools/dropdown_tool.dart` (lines 97-219)
- `/lib/widgets/tools/switch_tool.dart` (lines 76-151)
- `/lib/widgets/tools/checkbox_tool.dart` (lines 76-147)

**Problem**:
All control tools use similar Card/Padding/Column structure

**Solution**:
```dart
// Create: lib/widgets/tools/common/control_tool_layout.dart
class ControlToolLayout extends StatelessWidget {
  final String? label;
  final bool showLabel;
  final Widget? valueWidget;
  final Widget controlWidget;
  final String path;
  final bool isSending;
  final Color? backgroundColor;

  const ControlToolLayout({
    super.key,
    this.label,
    this.showLabel = true,
    this.valueWidget,
    required this.controlWidget,
    required this.path,
    this.isSending = false,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showLabel && label != null) ...[
              Text(
                label!,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],
            if (valueWidget != null) ...[
              valueWidget!,
              const SizedBox(height: 12),
            ],
            controlWidget,
            const SizedBox(height: 8),
            Text(
              path,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            if (isSending) ...[
              const SizedBox(height: 8),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

**Effort**: 4-6 hours
**Savings**: ~200 lines of code, improved consistency

---

## 2. Maintainability Issues

### CRITICAL: Tool Config Screen Too Large

**File**: `/lib/screens/tool_config_screen.dart`
**Size**: 1,659 lines

**Problem**:
This file handles:
- Form state for all tool types
- UI rendering for different tool categories
- Validation logic
- Configuration persistence
- Preview rendering

**Issues**:
- Difficult to navigate and understand
- High cognitive load for developers
- Hard to test individual components
- Increased merge conflict potential
- Violates Single Responsibility Principle

**Solution**:
```
lib/screens/tool_config_screen/
  ├── tool_config_screen.dart          # Main orchestrator (~300 lines)
  ├── tool_type_selector.dart          # Tool selection UI
  ├── data_source_config.dart          # Path/source configuration
  ├── style_config_panel.dart          # Common styling options
  ├── gauge_style_config.dart          # Gauge-specific options
  ├── chart_style_config.dart          # Chart-specific options
  ├── control_style_config.dart        # Control-specific options
  └── tool_preview.dart                # Preview widget
```

**Effort**: 1-2 days
**Impact**: Major maintainability improvement

---

### CRITICAL: SignalK Service Too Large

**File**: `/lib/services/signalk_service.dart`
**Size**: 1,321 lines

**Problem**:
Handles too many responsibilities:
- WebSocket connection management (primary + notification channels)
- Authentication
- Subscription management
- Data parsing and caching
- PUT requests
- REST API calls
- AIS vessel data extraction
- Notification handling
- Reconnection logic

**Issues**:
- God object anti-pattern
- Hard to unit test
- Difficult to modify without breaking things
- Mixed abstraction levels

**Solution**:
```
lib/services/signalk/
  ├── signalk_service.dart             # Main orchestrator (~150 lines)
  ├── connection_manager.dart          # WebSocket lifecycle
  ├── subscription_manager.dart        # Path subscriptions
  ├── data_parser.dart                 # Message parsing
  ├── data_cache.dart                  # Latest values storage
  ├── auth_manager.dart                # Authentication
  ├── put_request_service.dart         # PUT operations
  ├── notification_service.dart        # Notifications (already separate)
  └── ais_service.dart                 # AIS vessel data
```

**Effort**: 3-5 days
**Impact**: Better testability, easier to maintain

---

### HIGH: Missing Abstractions for Tool Implementations

**Problem**:
All tools implement similar patterns but share no common base:
- Data source retrieval
- Config access
- Error handling
- Empty state rendering

**Current State**: 18 tool files with 90% similar structure but no inheritance or composition

**Solution**:
```dart
// Create: lib/widgets/tools/base/base_tool.dart
abstract class BaseTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const BaseTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  // Common helpers
  DataSource? get primaryDataSource =>
    config.dataSources.isNotEmpty ? config.dataSources.first : null;

  String getLabel(String path) =>
    primaryDataSource?.label ?? path.toReadableLabel();

  Color getPrimaryColor(BuildContext context) =>
    config.style.primaryColor?.toColor(
      fallback: Theme.of(context).colorScheme.primary
    ) ?? Theme.of(context).colorScheme.primary;

  @override
  Widget build(BuildContext context) {
    if (config.dataSources.isEmpty) {
      return const Center(child: Text('No data source configured'));
    }
    return buildTool(context);
  }

  Widget buildTool(BuildContext context);
}
```

**Effort**: 2-3 days
**Impact**: Reduces future duplication, cleaner code

---

### HIGH: Tight Coupling to SignalKService

**Problem**:
All tools directly depend on concrete `SignalKService` class rather than an interface

**Issues**:
- Hard to mock for testing
- Can't swap implementations
- Circular dependencies possible
- Tight coupling to implementation details

**Solution**:
```dart
// Create: lib/services/interfaces/data_service.dart
abstract class DataService {
  SignalKDataPoint? getValue(String path, {String? source});
  double? getConvertedValue(String path);
  String? getUnitSymbol(String path);
  bool isDataFresh(String path, {String? source, int? ttlSeconds});
  Future<void> sendPutRequest(String path, dynamic value);
}

// SignalKService implements DataService
class SignalKService extends ChangeNotifier implements DataService {
  // ...
}
```

**Effort**: 1 day
**Impact**: Better testability, cleaner architecture

---

### MEDIUM: Hard-coded Values Should Be Constants

**Examples**:

`/lib/widgets/tools/autopilot_tool.dart` (lines 52-55):
```dart
static const Duration _fastPollingInterval = Duration(seconds: 5);
static const Duration _slowPollingInterval = Duration(seconds: 30);
static const Duration _fastPollingDuration = Duration(seconds: 30);
static const Duration _optimisticUpdateWindow = Duration(seconds: 3);
```

Color opacity values scattered throughout:
```dart
.withValues(alpha: 0.7)  // text_display_tool.dart:74
.withValues(alpha: 0.5)  // switch_tool.dart:113
.withValues(alpha: 0.3)  // slider_tool.dart:147
```

**Problem**: Magic numbers and durations without context or centralized configuration

**Solution**:
```dart
// Create: lib/config/ui_constants.dart
class UIConstants {
  // Opacity levels
  static const double subtleOpacity = 0.7;
  static const double mediumOpacity = 0.5;
  static const double lightOpacity = 0.3;

  // Polling intervals
  static const Duration fastPolling = Duration(seconds: 5);
  static const Duration slowPolling = Duration(seconds: 30);

  // Timeouts
  static const Duration dataStaleTimeout = Duration(seconds: 30);
  static const Duration optimisticUpdateWindow = Duration(seconds: 3);

  // UI spacing
  static const double cardElevation = 2.0;
  static const EdgeInsets cardPadding = EdgeInsets.all(16.0);
}
```

**Effort**: 2-3 hours
**Impact**: Better maintainability, easier to adjust UI

---

### MEDIUM: Inconsistent Error Handling

**Problem**: Some tools silently catch errors, others print to console, some show snackbars

**Examples**:

`radial_gauge_tool.dart` (lines 73-78):
```dart
} catch (e) {
  // Silently fail - zones are optional
  if (kDebugMode) {
    print('Failed to fetch zones for radial gauge: $e');
  }
}
```

`slider_tool.dart` (lines 222-231):
```dart
} catch (e) {
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Failed to set value: $e'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.red,
      ),
    );
  }
}
```

**Solution**:
```dart
// Create: lib/utils/error_handler.dart
class ErrorHandler {
  static void handleToolError(
    BuildContext context,
    String message,
    dynamic error, {
    bool showSnackBar = true,
    bool logToConsole = true,
  }) {
    if (kDebugMode && logToConsole) {
      print('Tool Error: $message - $error');
    }

    if (showSnackBar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  static void handleOptionalError(
    String message,
    dynamic error, {
    bool logToConsole = true,
  }) {
    if (kDebugMode && logToConsole) {
      print('Optional Feature Error: $message - $error');
    }
  }
}
```

**Effort**: 2-3 hours
**Impact**: Consistent error handling across app

---

## 3. Performance Concerns

### CRITICAL: Zone Fetching on Every Tool Instance

**Location**:
- `/lib/widgets/tools/radial_gauge_tool.dart` (lines 59-79)
- `/lib/widgets/tools/linear_gauge_tool.dart` (lines 67-86)

**Problem**:
Each gauge tool creates its own `ZonesService` and fetches zones independently. No caching between tool instances.

**Issues**:
- Multiple HTTP requests for same zone data
- No caching between tool instances
- Wasted bandwidth and server load
- Slower dashboard load times

**Solution**:
```dart
// Create: lib/services/zones_cache_service.dart
class ZonesCacheService extends ChangeNotifier {
  final Map<String, List<ZoneDefinition>> _cache = {};
  final ZonesService _zonesService;

  ZonesCacheService({
    required String serverUrl,
    required bool useSecureConnection,
  }) : _zonesService = ZonesService(
          serverUrl: serverUrl,
          useSecureConnection: useSecureConnection,
        );

  Future<List<ZoneDefinition>?> getZones(String path) async {
    // Return cached if available
    if (_cache.containsKey(path)) {
      return _cache[path];
    }

    // Fetch from server
    try {
      final zones = await _zonesService.fetchZones(path);
      if (zones != null && zones.hasZones) {
        _cache[path] = zones.zones;
        notifyListeners();
      }
      return _cache[path];
    } catch (e) {
      if (kDebugMode) {
        print('Failed to fetch zones for $path: $e');
      }
      return null;
    }
  }

  void clearCache() {
    _cache.clear();
    notifyListeners();
  }

  void clearPath(String path) {
    _cache.remove(path);
    notifyListeners();
  }
}
```

**Effort**: 2-3 hours
**Impact**: 30-50% faster dashboard load, reduced server load

---

### HIGH: Unnecessary Widget Rebuilds

**Location**: `/lib/widgets/tools/text_display_tool.dart` (entire widget)

**Problem**:
TextDisplayTool is a StatelessWidget that rebuilds on every parent rebuild, even though it listens to signalKService which already has change notification.

**Current Implementation**:
```dart
class TextDisplayTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  @override
  Widget build(BuildContext context) {
    final dataPoint = signalKService.getValue(dataSource.path, source: dataSource.source);
    // ... rebuilds entire widget tree on any parent change
  }
}
```

**Issues**:
- Rebuilds on every parent change even if data unchanged
- No caching of computed values
- Expensive operations in build method

**Solution**:
```dart
class TextDisplayTool extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Selector<SignalKService, SignalKDataPoint?>(
      selector: (_, service) => service.getValue(
        dataSource.path,
        source: dataSource.source
      ),
      builder: (context, dataPoint, child) {
        // Only rebuilds when this specific dataPoint changes
        return _buildDisplay(context, dataPoint);
      },
    );
  }
}
```

**Effort**: 1-2 days (apply to all tools)
**Impact**: Reduced CPU usage, smoother animations

---

### HIGH: Missing Const Constructors

**Problem**:
Many widgets that could be const are not marked as such.

**Examples**:
- Tool widgets don't use const constructors
- Static child widgets aren't const
- Frequently used widgets like Card, Padding not const where possible

**Solution**:
Add const constructors where possible:
```dart
const RadialGaugeTool({
  super.key,
  required this.config,
  required this.signalKService,
});

// Use const for static children
const Center(child: Text('No data source configured'))
const SizedBox(height: 8)
const EdgeInsets.all(16.0)
```

**Effort**: 2-3 hours (code review + updates)
**Impact**: Reduced widget tree rebuilds, lower memory usage

---

### MEDIUM: Expensive Operations in Build Method

**Location**: `/lib/widgets/tools/dropdown_tool.dart` (lines 65-73)

**Problem**:
Generating dropdown values in every build:
```dart
@override
Widget build(BuildContext context) {
  final List<double> dropdownValues = [];
  for (double value = minValue; value <= maxValue; value += stepSize) {
    dropdownValues.add(value);
  }
  if (dropdownValues.last < maxValue) {
    dropdownValues.add(maxValue);
  }
  // ...
}
```

**Issues**:
- Loop executes on every rebuild
- List allocation every frame
- Unnecessary GC pressure

**Solution**:
```dart
class _DropdownToolState extends State<DropdownTool> {
  List<double>? _cachedDropdownValues;
  double? _cachedMin;
  double? _cachedMax;
  double? _cachedStep;

  List<double> _getDropdownValues() {
    final min = widget.config.style.minValue ?? 0.0;
    final max = widget.config.style.maxValue ?? 100.0;
    final step = widget.config.style.customProperties?['stepSize'] as double?
      ?? ((max - min) / 10);

    // Return cached if unchanged
    if (_cachedDropdownValues != null &&
        _cachedMin == min &&
        _cachedMax == max &&
        _cachedStep == step) {
      return _cachedDropdownValues!;
    }

    // Generate new values
    final values = <double>[];
    for (double value = min; value <= max; value += step) {
      values.add(value);
    }
    if (values.last < max) values.add(max);

    _cachedDropdownValues = values;
    _cachedMin = min;
    _cachedMax = max;
    _cachedStep = step;

    return values;
  }
}
```

**Effort**: 1-2 hours
**Impact**: Reduced frame drops on complex dashboards

---

### MEDIUM: Potential Memory Leaks

**Location**: `/lib/widgets/tools/radial_gauge_tool.dart` (lines 82-85)

**Problem**:
Listener cleanup in dispose not guaranteed to execute correctly:
```dart
@override
void dispose() {
  widget.signalKService.removeListener(_onSignalKConnectionChanged);
  super.dispose();
}
```

If `_onSignalKConnectionChanged` was never added, calling removeListener is harmless but shows inconsistent state tracking.

**Solution**:
```dart
bool _listenerAdded = false;

void _initializeZonesService() {
  if (widget.signalKService.isConnected) {
    _createZonesServiceAndFetch();
  } else {
    widget.signalKService.addListener(_onSignalKConnectionChanged);
    _listenerAdded = true;
  }
}

@override
void dispose() {
  if (_listenerAdded) {
    widget.signalKService.removeListener(_onSignalKConnectionChanged);
  }
  super.dispose();
}
```

**Effort**: 1 hour
**Impact**: Prevents potential memory leaks

---

## Implementation Priority

### Phase 1: Quick Wins (Week 1)
**Estimated Time**: 8-12 hours

1. ✅ **Create String Extensions** (`lib/utils/string_extensions.dart`)
   - Extract `_getDefaultLabel()` method
   - Update all 10 tool files to use extension
   - **Savings**: ~500 lines

2. ✅ **Create Color Extensions** (`lib/utils/color_extensions.dart`)
   - Extract color parsing logic
   - Update all 18 tool files
   - **Savings**: ~300 lines

3. ✅ **Create Boolean Extension** (`lib/utils/data_extensions.dart`)
   - Extract boolean parsing
   - Update switch and checkbox tools
   - **Savings**: ~20 lines

4. ✅ **Implement Zone Caching Service** (`lib/services/zones_cache_service.dart`)
   - Create centralized zone cache
   - Update radial and linear gauge tools
   - **Impact**: 30-50% faster dashboard load

### Phase 2: Control Tool Refactoring (Week 2)
**Estimated Time**: 12-16 hours

5. ✅ **Create Control Tool Mixin** (`lib/widgets/tools/mixins/control_tool_mixin.dart`)
   - Extract `_sendValue()` method
   - Update slider, knob, dropdown tools
   - **Savings**: ~200 lines

6. ✅ **Create Control Tool Layout** (`lib/widgets/tools/common/control_tool_layout.dart`)
   - Extract common Card/Column structure
   - Update all 5 control tools
   - **Savings**: ~200 lines

7. ✅ **Create Zones Mixin** (`lib/widgets/tools/mixins/zones_mixin.dart`)
   - Extract zone initialization logic
   - Update radial and linear gauge tools
   - **Savings**: ~120 lines

### Phase 3: Base Abstractions (Week 3)
**Estimated Time**: 16-24 hours

8. ✅ **Create Base Tool Class** (`lib/widgets/tools/base/base_tool.dart`)
   - Define common interface
   - Add helper methods
   - Begin migrating tools

9. ✅ **Create DataService Interface** (`lib/services/interfaces/data_service.dart`)
   - Extract interface from SignalKService
   - Update SignalKService to implement interface
   - Prepare for better testing

10. ✅ **Create UI Constants** (`lib/config/ui_constants.dart`)
    - Centralize magic numbers
    - Update all tools to use constants

### Phase 4: Large File Refactoring (Week 4-5)
**Estimated Time**: 3-5 days

11. ✅ **Split tool_config_screen.dart**
    - Create directory structure
    - Extract sections to separate files
    - Test thoroughly

12. ✅ **Refactor SignalKService**
    - Create service directory
    - Split into focused services
    - Maintain backward compatibility
    - Update all consumers

### Phase 5: Performance Optimization (Week 6)
**Estimated Time**: 8-12 hours

13. ✅ **Implement Selector Pattern**
    - Update all display tools
    - Add targeted rebuilds
    - Measure performance improvement

14. ✅ **Add Const Constructors**
    - Review all widgets
    - Add const where possible
    - Update call sites

15. ✅ **Memoize Expensive Computations**
    - Identify expensive operations in build
    - Add caching where appropriate
    - Test for correctness

### Phase 6: Error Handling & Testing (Ongoing)
**Estimated Time**: 8-12 hours

16. ✅ **Create Error Handler Utility** (`lib/utils/error_handler.dart`)
    - Centralize error handling
    - Update all tools
    - Consistent user feedback

17. ✅ **Add Memory Leak Prevention**
    - Review all dispose methods
    - Add state tracking for listeners
    - Ensure proper cleanup

---

## Metrics & Success Criteria

### Before Refactoring
- **Total Dart Files**: 90
- **Duplicate `_getDefaultLabel()` methods**: 25 occurrences (10 files)
- **Duplicate color parsing**: 24 occurrences (18 files)
- **Largest file**: tool_config_screen.dart (1,659 lines)
- **Second largest**: signalk_service.dart (1,321 lines)
- **Estimated duplicate code**: ~800-1000 lines

### After Refactoring (Target)
- **Code reduction**: 40-50% in tool widgets (~800 lines saved)
- **Largest file**: <500 lines (broken into modules)
- **Test coverage**: >80% for core services
- **Dashboard load time**: 30-50% improvement
- **Build warnings**: 0
- **Maintainability index**: Improved from current baseline

### Ongoing Metrics to Track
- Lines of code per file (target: <500)
- Cyclomatic complexity (target: <10 per method)
- Code duplication percentage (target: <3%)
- Test coverage (target: >80%)
- Build time
- Dashboard render time

---

## Testing Strategy

### Unit Tests
- String extensions (`toReadableLabel()`, `toColor()`)
- Boolean conversion extension
- Control tool mixin (`sendNumericValue()`)
- Zone cache service
- Base tool helper methods

### Integration Tests
- Tool rendering with mocked data service
- Zone fetching and caching
- Control tool value sending
- Error handling flows

### Widget Tests
- All tool widgets with various configurations
- Tool config screen sections
- Control tool layout

### Performance Tests
- Dashboard load time (before/after zone caching)
- Widget rebuild count (before/after Selector)
- Memory usage (before/after const constructors)

---

## Risk Mitigation

### High Risk Items
1. **SignalKService Refactoring**
   - Risk: Breaking existing functionality
   - Mitigation: Thorough testing, maintain backward compatibility, gradual migration

2. **tool_config_screen.dart Split**
   - Risk: Breaking configuration flow
   - Mitigation: Comprehensive widget tests, user acceptance testing

### Medium Risk Items
3. **Base Tool Class Migration**
   - Risk: Regression in tool behavior
   - Mitigation: Migrate one tool at a time, test each thoroughly

4. **Selector Pattern Implementation**
   - Risk: Incorrect rebuild behavior
   - Mitigation: Visual testing, performance monitoring

### Low Risk Items
5. **Utility Function Extraction**
   - Risk: Minimal, pure functions
   - Mitigation: Unit tests

6. **Const Constructor Addition**
   - Risk: Minimal
   - Mitigation: Compiler checks, manual testing

---

## Notes for Implementation

### Best Practices to Follow
- Create feature branch for each phase
- Write tests before refactoring (where possible)
- Commit small, atomic changes
- Update documentation as you go
- Run full test suite after each phase
- Get code review before merging

### Files to Create
```
lib/
├── utils/
│   ├── string_extensions.dart
│   ├── color_extensions.dart
│   ├── data_extensions.dart
│   └── error_handler.dart
├── config/
│   └── ui_constants.dart
├── services/
│   ├── interfaces/
│   │   └── data_service.dart
│   ├── zones_cache_service.dart
│   └── signalk/
│       ├── connection_manager.dart
│       ├── subscription_manager.dart
│       ├── data_parser.dart
│       ├── data_cache.dart
│       ├── auth_manager.dart
│       ├── put_request_service.dart
│       └── ais_service.dart
├── widgets/tools/
│   ├── base/
│   │   └── base_tool.dart
│   ├── mixins/
│   │   ├── control_tool_mixin.dart
│   │   └── zones_mixin.dart
│   └── common/
│       └── control_tool_layout.dart
└── screens/tool_config_screen/
    ├── tool_config_screen.dart
    ├── tool_type_selector.dart
    ├── data_source_config.dart
    ├── style_config_panel.dart
    ├── gauge_style_config.dart
    ├── chart_style_config.dart
    ├── control_style_config.dart
    └── tool_preview.dart
```

### Dependencies to Add (if needed)
- None required for basic refactoring
- Consider `flutter_test` utilities for better testing
- Consider `mockito` for mocking DataService interface

---

## Conclusion

This refactoring plan addresses the three main categories of issues:

1. **Code Redundancy**: Removes ~800-1000 lines of duplicate code through utility functions, mixins, and base classes

2. **Maintainability**: Breaks down large files into manageable modules, creates clear abstractions, and establishes consistent patterns

3. **Performance**: Implements caching, reduces unnecessary rebuilds, and optimizes expensive operations

**Total Estimated Effort**: 6-8 weeks part-time or 3-4 weeks full-time

**Expected Benefits**:
- 40-50% code reduction in tool widgets
- 30-50% faster dashboard load times
- Significantly improved maintainability
- Better test coverage
- Easier to add new tools
- More consistent user experience

The plan is structured in phases to allow for incremental progress and validation. Each phase delivers tangible value and can be merged independently.
