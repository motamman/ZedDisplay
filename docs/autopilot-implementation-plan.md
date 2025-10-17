# Autopilot Widget Implementation Plan

## Overview

The Autopilot widget is a comprehensive marine autopilot control interface that supports both SignalK V1 (legacy plugin-based) and V2 (modern REST API-based) autopilot systems. It provides full control over autopilot modes, heading adjustments, tacking maneuvers, and route navigation.

---

## Visual Design

### Main Layout

```
┌──────────────────────────────────────────────────────┐
│  HDG: 045°M    [COMPASS DIAL]     AWA: 32° S        │
│                     ╱                                │
│                   ╱                                  │
│                 ╱  N                                 │
│               ╱   │   ╲                              │
│         270°W ────┼──── E 090°                       │
│               ╲   │   ╱                              │
│                 ╲ S ╱                                │
│                   ╲                                  │
│                                                      │
│           TARGET: 045°                               │
│              COMPASS                                 │
│                                                      │
│  [=== RUDDER INDICATOR ===]                         │
│         ◄──█──►                                      │
│                                                      │
├──────────────────────────────────────────────────────┤
│ [Mode: Compass ▼]        [DISENGAGE]                │
├──────────────────────────────────────────────────────┤
│     [-10°]    [-1°]    [+1°]    [+10°]              │
├──────────────────────────────────────────────────────┤
│          [TACK PORT]    [TACK STBD]                 │
├──────────────────────────────────────────────────────┤
│  [Next WPT]     [ETA]      [DTW]      [TTW]         │
│   N45°15'W      14:30      3.2nm      0:45          │
├──────────────────────────────────────────────────────┤
│         [DODGE]         [ADV WPT]                    │
└──────────────────────────────────────────────────────┘
```

### Key Visual Components

1. **Compass Dial**
   - Rotating compass rose with N/E/S/W and 30° markings
   - Current heading displayed at top
   - Port (red) and starboard (green) arcs at top
   - Apparent wind angle indicator (AWA arrow with "A")
   - Target heading shown in center (large numbers)
   - Rudder angle indicator at bottom

2. **Control Buttons**
   - Mode selector with dropdown menu
   - Engage/Disengage button
   - Heading adjustment buttons (±1°, ±10°)
   - Tack buttons (Port/Starboard) with confirmation
   - Route navigation controls (Dodge, Advance Waypoint)

3. **Status Displays**
   - HDG (current heading) - top left
   - AWA (apparent wind angle) - top right
   - XTE (cross track error) - when in route mode
   - Route information widgets (Next WPT, ETA, DTW, TTW)

4. **Overlays**
   - Confirmation countdown (for tack/waypoint advance)
   - Error messages with warning icon
   - Success messages

---

## SignalK API Support

### V1 API (Legacy Plugin-Based)

**Endpoints:**
- Uses PUT requests to `steering.autopilot.*` paths
- Single state path: `self.steering.autopilot.state`

**Commands:**
| Command | Path | Value |
|---------|------|-------|
| Auto Mode | `self.steering.autopilot.state` | `"auto"` |
| Wind Mode | `self.steering.autopilot.state` | `"wind"` |
| Route Mode | `self.steering.autopilot.state` | `"route"` |
| Standby | `self.steering.autopilot.state` | `"standby"` |
| Adjust +1° | `self.steering.autopilot.actions.adjustHeading` | `1` |
| Adjust -1° | `self.steering.autopilot.actions.adjustHeading` | `-1` |
| Adjust +10° | `self.steering.autopilot.actions.adjustHeading` | `10` |
| Adjust -10° | `self.steering.autopilot.actions.adjustHeading` | `-10` |
| Tack Port | `self.steering.autopilot.actions.tack` | `"port"` |
| Tack Starboard | `self.steering.autopilot.actions.tack` | `"starboard"` |
| Advance Waypoint | `self.steering.autopilot.actions.advanceWaypoint` | `"1"` |

**Behavior:**
- Mode determines which commands are available
- No engage/disengage in V1 (standby = disengaged)
- Subscribe to PUT request responses for error handling

### V2 API (Modern REST-Based)

**Discovery Endpoint:**
```
GET /signalk/v2/api/vessels/self/autopilots
```

Returns available autopilot instances and default provider.

**Instance Endpoint:**
```
GET /signalk/v2/api/vessels/self/autopilots/{instanceId}
```

Returns capabilities and current state:
```json
{
  "options": {
    "modes": ["compass", "gps", "wind", "true wind", "nav"],
    "states": ["engaged", "disengaged"]
  },
  "state": "engaged",
  "mode": "compass",
  "target": 185.5,
  "engaged": true
}
```

**Control Endpoints:**

| Operation | Method | Endpoint |
|-----------|--------|----------|
| Engage | POST | `/autopilots/{id}/engage` |
| Disengage | POST | `/autopilots/{id}/disengage` |
| Set Mode | PUT | `/autopilots/{id}/mode` |
| Set Target | PUT | `/autopilots/{id}/target` |
| Adjust Heading | PUT | `/autopilots/{id}/target/adjust` |
| Tack | POST | `/autopilots/{id}/tack/{direction}` |
| Gybe | POST | `/autopilots/{id}/gybe/{direction}` |
| Dodge | POST/DELETE | `/autopilots/{id}/dodge` |
| Advance Waypoint | PUT | `/vessels/self/navigation/course/activeRoute/nextPoint` |

**Request Bodies:**

```javascript
// Set Mode
{ "value": "compass" }

// Set Target
{ "value": 185.5, "units": "deg" }

// Adjust Heading
{ "value": +10, "units": "deg" }

// Tack (direction in URL)
POST /autopilots/pypilot/tack/port

// Dodge (toggle via POST/DELETE)
POST /autopilots/pypilot/dodge    // Activate
DELETE /autopilots/pypilot/dodge  // Deactivate
```

**Response Format:**
```json
{
  "status": "success",
  "message": "optional message",
  "data": {}
}
```

---

## Data Paths

### Required SignalK Paths

| Path | Description | Units | Required |
|------|-------------|-------|----------|
| `steering.autopilot.state` | Autopilot state (V1/V2) | string | ✅ |
| `steering.autopilot.mode` | Current mode | string | ✅ |
| `steering.autopilot.engaged` | Engaged status (V2) | boolean | V2 only |
| `steering.autopilot.target.headingMagnetic` | Target heading | radians → deg | ✅ |
| `navigation.headingMagnetic` or `headingTrue` | Current heading | radians → deg | ✅ |
| `steering.rudderAngle` | Rudder position | radians → deg | ✅ |

### Optional Paths (For Enhanced Features)

| Path | Description | Used For |
|------|-------------|----------|
| `steering.autopilot.target.windAngleApparent` | Target AWA | Wind mode display |
| `environment.wind.angleApparent` | Current AWA | Wind mode display |
| `environment.wind.angleTrueWater` | True wind angle | Wind mode |
| `navigation.course.calcValues.crossTrackError` | XTE | Route mode display |
| `navigation.course.calcValues.bearingTrue` | Course bearing | Route mode |
| `navigation.course.calcValues.bearingMagnetic` | Course bearing mag | Route mode |
| `navigation.courseGreatCircle.nextPoint.position` | Next waypoint | Route display |
| `navigation.course.calcValues.distance` | Distance to waypoint | Route display |
| `navigation.course.calcValues.timeToGo` | Time to waypoint | Route display |
| `navigation.course.calcValues.estimatedTimeOfArrival` | ETA | Route display |

---

## Feature Breakdown

### 1. Compass Dial Display

**Components:**
- **Fixed Dial**: Background circle with port/starboard arcs
- **Rotating Dial**: Compass rose with degree markings (rotates with heading)
- **Triangle Marker**: Fixed north indicator at top
- **AWA Indicator**: Arrow showing apparent wind angle (when in wind mode)
- **Target Heading**: Large numbers in center
- **Mode Label**: Text showing current mode
- **Heading Annotation**: "M" (magnetic) or "T" (true)

**Flutter Implementation:**
```dart
class AutopilotCompassGauge extends StatelessWidget {
  final double heading;              // Current heading
  final double targetHeading;        // Autopilot target
  final double? apparentWindAngle;   // For wind mode
  final double? crossTrackError;     // For route mode
  final double rudderAngle;          // Rudder position
  final String mode;                 // Current mode
  final bool headingTrue;            // Mag vs True

  // CustomPaint with _CompassPainter
}
```

### 2. Rudder Indicator

**Visual:**
```
Port ◄──────█──────► Starboard
     │              │
   -35°     0°    +35°
```

**Features:**
- Horizontal bar with center mark
- Filled rectangle showing rudder position
- Red (port) when left, green (starboard) when right
- Scale markings at -35°, 0°, +35°

**Flutter Implementation:**
```dart
class RudderIndicator extends StatelessWidget {
  final double rudderAngle;  // -35° to +35°
  final bool invertRudder;   // Config option

  // Horizontal bar with animated fill
}
```

### 3. Mode Selector

**Dropdown Menu:**
- Shows current mode with down arrow
- Tapping opens overlay menu
- Menu items:
  - Current mode has checkmark ✓
  - Available modes are enabled
  - Unavailable modes are grayed out
  - "Close" button at bottom

**V1 Mode Transitions:**
```
Standby → Auto, Wind
Auto → Wind, Route
Wind → Auto
Route → Auto
```

**V2 Modes (PyPilot Example):**
- Compass
- GPS
- Wind
- True Wind
- Navigation

**Flutter Implementation:**
```dart
void _showModeMenu() {
  showModalBottomSheet(
    context: context,
    builder: (context) => ModeMenuSheet(
      currentMode: mode,
      availableModes: apiVersion == 'v2'
        ? capabilities.modes
        : ['auto', 'wind', 'route'],
      onModeSelected: (mode) => _setMode(mode),
    ),
  );
}
```

### 4. Heading Adjustment Buttons

**Layout:**
```
[-10°]  [-1°]  [+1°]  [+10°]
```

**Behavior:**
- Disabled when autopilot not engaged
- Visible in: Auto, Compass, GPS, Wind, True Wind modes
- Hidden in: Standby, Route modes (unless dodge active)
- In dodge mode: Adjusts dodge offset instead of target heading

**Button Design:**
- SVG arrow icons pointing left/right
- Degree value text below arrow
- Material button style
- Active state highlighting

### 5. Tack Buttons

**Layout:**
```
[TACK PORT]  [TACK STARBOARD]
```

**Confirmation Flow:**
1. User taps tack button
2. Countdown overlay appears: "Repeat [Tack Port] key to confirm"
3. 5-second countdown (5, 4, 3, 2, 1)
4. User must tap same button again within 5 seconds
5. Tack executed or countdown expires

**Behavior:**
- Visible in: Auto, Compass, GPS, Wind, True Wind modes
- Hidden in: Standby, Route modes
- Disabled when not engaged
- V1: PUT to `actions.tack` with "port" or "starboard"
- V2: POST to `/tack/port` or `/tack/starboard`

### 6. Route Navigation Controls

**Route Info Widgets:**
Display when mode = "route" or "nav":
- **Next WPT**: Lat/lon of next waypoint
- **ETA**: Estimated time of arrival
- **DTW**: Distance to waypoint (nm)
- **TTW**: Time to waypoint (HH:MM:SS)

**Dodge Button (V2 Only):**
- Toggle button (POST = on, DELETE = off)
- Active state: Filled icon with highlight
- When dodge active:
  - Heading adjustment buttons adjust dodge offset
  - Route widgets hidden
  - Advance Waypoint disabled

**Advance Waypoint:**
- Button to skip to next waypoint in route
- Requires confirmation (like tack)
- V1: PUT to `actions.advanceWaypoint`
- V2: PUT to `/navigation/course/activeRoute/nextPoint`

### 7. Engage/Disengage Control

**V1 Behavior:**
- Standby mode = disengaged
- Setting any other mode = engaged
- Button switches between current mode and standby

**V2 Behavior:**
- Separate engaged/disengaged state
- POST to `/engage` or `/disengage`
- Button label: "Engage" when disengaged, "Disengage" when engaged
- Button color: Green (engage), Red (disengage)

### 8. Error Handling & Messages

**Error Overlay:**
```
┌────────────────────────┐
│    ⚠️ WARNING           │
│                        │
│  500 - Connection Lost │
│  Server Message: ...   │
└────────────────────────┘
```

**Types of Messages:**
1. **Confirmation Countdown**: Tack/waypoint advance
2. **Error Messages**: API failures, command errors
3. **Success Messages**: Command acknowledged
4. **Persistent Errors**: Not configured, offline

**Display Duration:**
- Confirmation: 5 seconds
- Errors: 6 seconds
- Success: 3 seconds
- Persistent: Until resolved

---

## Configuration

### Widget Configuration Structure

```dart
class AutopilotConfig {
  // API Configuration (must be detected/configured)
  final String? apiVersion;        // 'v1' or 'v2'
  final String? instanceId;        // V2 instance ID (e.g., 'pypilot')
  final String? pluginId;          // V2 plugin ID
  final List<String>? modes;       // Available modes from V2 discovery

  // Display Options
  final bool invertRudder;         // Invert rudder display
  final bool headingDirectionTrue; // Use true vs magnetic heading
  final bool courseDirectionTrue;  // Use true vs magnetic course

  // Confirmation
  final int confirmationSeconds;   // Countdown duration (default: 5)
}
```

### Configuration Flow

1. **API Detection**:
   ```
   User adds autopilot widget
   ↓
   Check if V2 API available:
     GET /signalk/v2/api/vessels/self/autopilots
   ↓
   If 200: Use V2, show instance selector
   If 404: Use V1
   ↓
   Save configuration
   ```

2. **V2 Instance Selection**:
   - Fetch available instances
   - Display list with provider names
   - Mark default instance
   - User selects instance
   - Fetch capabilities for selected instance

3. **Path Configuration**:
   - Automatically subscribe to required paths
   - Optional: Allow user to override heading source

---

## Implementation Phases

### Phase 1: Core Compass Display ✓
**Goal**: Display heading and target with rotating compass

**Components:**
- [ ] `AutopilotCompassGauge` - CustomPainter compass dial
- [ ] Rotating compass rose with markings
- [ ] Target heading display in center
- [ ] Current heading display at top
- [ ] Port/starboard arc indicators

**Data Paths:**
- `navigation.headingMagnetic`
- `steering.autopilot.target.headingMagnetic`

**Deliverable**: Static compass that shows heading and target

---

### Phase 2: Rudder Indicator & Mode Display
**Goal**: Add rudder position and mode information

**Components:**
- [ ] `RudderIndicator` widget
- [ ] Mode label on compass
- [ ] State subscription for mode and rudder

**Data Paths:**
- `steering.rudderAngle`
- `steering.autopilot.mode`
- `steering.autopilot.state`

**Deliverable**: Compass with rudder and mode display

---

### Phase 3: V1 API Command Support
**Goal**: Basic autopilot control with V1 API

**Components:**
- [ ] Mode selector button with menu
- [ ] Heading adjustment buttons (±1°, ±10°)
- [ ] V1 PUT request implementation
- [ ] Command response handling

**Features:**
- Switch modes (Auto, Wind, Route, Standby)
- Adjust heading in auto mode
- Error message display

**Deliverable**: Working V1 autopilot control

---

### Phase 4: Tack & Confirmation System
**Goal**: Add tacking with confirmation flow

**Components:**
- [ ] Tack buttons (Port/Starboard)
- [ ] Confirmation overlay with countdown
- [ ] Timer management
- [ ] Tack command execution

**Deliverable**: Safe tacking with confirmation

---

### Phase 5: V2 API Support
**Goal**: Modern REST API implementation

**Components:**
- [ ] API discovery endpoint
- [ ] Instance selection UI
- [ ] Capability detection
- [ ] V2 REST command methods (POST/PUT/DELETE)
- [ ] Engage/Disengage control

**Features:**
- Auto-detect API version
- V2 mode support (Compass, GPS, Wind, True Wind, Nav)
- Proper engage/disengage

**Deliverable**: Full V2 API support

---

### Phase 6: Route Navigation Features
**Goal**: Complete route following support

**Components:**
- [ ] Route info widget integration
  - Next Waypoint position display
  - ETA datetime display
  - Distance to waypoint
  - Time to waypoint
- [ ] Advance Waypoint button with confirmation
- [ ] Cross-track error display on compass
- [ ] Dodge mode (V2 only)

**Data Paths:**
- `navigation.courseGreatCircle.nextPoint.position`
- `navigation.course.calcValues.*`

**Deliverable**: Full route navigation support

---

### Phase 7: Wind Mode Enhancements
**Goal**: Apparent wind angle visualization

**Components:**
- [ ] AWA indicator arrow on compass
- [ ] Target AWA display
- [ ] Wind angle adjustment buttons

**Data Paths:**
- `environment.wind.angleApparent`
- `steering.autopilot.target.windAngleApparent`

**Deliverable**: Complete wind mode support

---

### Phase 8: Configuration & Polish
**Goal**: User configuration and refinements

**Components:**
- [ ] Autopilot setup wizard
- [ ] API version selection
- [ ] Instance/plugin configuration
- [ ] Display preferences
- [ ] Error state improvements
- [ ] Animation polish

**Deliverable**: Production-ready autopilot widget

---

## Technical Architecture

### File Structure

```
lib/
├── models/
│   ├── autopilot_config.dart         # Configuration model
│   ├── autopilot_state.dart          # State model
│   └── autopilot_v2_api.dart         # V2 API interfaces
├── services/
│   ├── autopilot_service.dart        # Command execution & state
│   └── signalk_autopilot_api.dart    # API wrapper (V1/V2)
├── widgets/
│   ├── autopilot_compass.dart        # Compass dial
│   ├── autopilot_controls.dart       # Button grid
│   ├── rudder_indicator.dart         # Rudder bar
│   ├── autopilot_mode_menu.dart      # Mode selector
│   └── confirmation_overlay.dart     # Countdown overlay
└── screens/
    └── autopilot_config_screen.dart  # Setup wizard
```

### State Management

**Using Flutter Provider + Signals pattern:**

```dart
class AutopilotService extends ChangeNotifier {
  // State signals
  final ValueNotifier<String?> mode = ValueNotifier(null);
  final ValueNotifier<bool> engaged = ValueNotifier(false);
  final ValueNotifier<double> targetHeading = ValueNotifier(0);
  final ValueNotifier<double> currentHeading = ValueNotifier(0);
  final ValueNotifier<double> rudderAngle = ValueNotifier(0);

  // API version
  String? apiVersion; // 'v1' or 'v2'

  // V2 endpoints
  String? instanceId;
  Map<String, String>? endpoints;

  // Commands
  Future<void> setMode(String mode);
  Future<void> adjustHeading(int degrees);
  Future<void> tack(String direction);
  Future<void> engage();
  Future<void> disengage();

  // V2 specific
  Future<void> setAbsoluteTarget(double heading);
  Future<void> toggleDodge();
  Future<void> advanceWaypoint();
}
```

### API Abstraction

```dart
abstract class AutopilotApi {
  Future<void> setMode(String mode);
  Future<void> adjustHeading(int degrees);
  Future<void> tack(String direction);
}

class AutopilotV1Api implements AutopilotApi {
  final SignalKService signalK;

  @override
  Future<void> setMode(String mode) {
    return signalK.sendPutRequest(
      'self.steering.autopilot.state',
      mode,
    );
  }

  @override
  Future<void> adjustHeading(int degrees) {
    return signalK.sendPutRequest(
      'self.steering.autopilot.actions.adjustHeading',
      degrees,
    );
  }
}

class AutopilotV2Api implements AutopilotApi {
  final HttpClient http;
  final String instanceId;
  final Map<String, String> endpoints;

  @override
  Future<void> setMode(String mode) async {
    final response = await http.put(
      endpoints['mode']!,
      body: {'value': mode},
    );
    _handleResponse(response);
  }

  @override
  Future<void> adjustHeading(int degrees) async {
    final response = await http.put(
      endpoints['adjustHeading']!,
      body: {'value': degrees, 'units': 'deg'},
    );
    _handleResponse(response);
  }

  Future<void> engage() async {
    final response = await http.post(endpoints['engage']!);
    _handleResponse(response);
  }
}
```

---

## UI/UX Considerations

### Button States

| State | Visual | Behavior |
|-------|--------|----------|
| Enabled | Full color, shadow | Tappable |
| Disabled | Gray, no shadow | No interaction |
| Active | Highlighted border | Current selection |
| Pressed | Darker shade | Touch feedback |

### Responsive Layout

**Portrait Mode:**
```
┌─────────────────┐
│    Compass      │
│     (Large)     │
├─────────────────┤
│  Mode | Engage  │
├─────────────────┤
│ -10 -1 +1 +10  │
├─────────────────┤
│  Tack  | Tack   │
│  Port  | Stbd   │
└─────────────────┘
```

**Landscape Mode:**
```
┌────────────┬───────────────┐
│            │  Mode |Engage │
│  Compass   ├───────────────┤
│  (Large)   │ -10 -1 +1 +10│
│            ├───────────────┤
│            │ Tack  | Tack  │
└────────────┴───────────────┘
```

### Accessibility

- **VoiceOver**: All buttons labeled
- **Haptic Feedback**: On button press
- **Confirmation**: Double-tap for critical actions
- **Error Announcements**: Via screen reader

---

## Testing Checklist

### V1 API Testing
- [ ] Connect to V1 autopilot
- [ ] Switch modes (Auto, Wind, Route, Standby)
- [ ] Adjust heading in auto mode
- [ ] Tack port with confirmation
- [ ] Tack starboard with confirmation
- [ ] Advance waypoint in route mode
- [ ] Handle command errors
- [ ] Handle connection loss

### V2 API Testing
- [ ] Discover autopilot instances
- [ ] Select instance
- [ ] Engage/disengage
- [ ] Switch modes (Compass, GPS, Wind, etc.)
- [ ] Adjust heading
- [ ] Tack with confirmation
- [ ] Activate/deactivate dodge mode
- [ ] Adjust heading while in dodge
- [ ] Advance waypoint
- [ ] Handle REST API errors

### UI Testing
- [ ] Compass rotates smoothly
- [ ] Rudder indicator animates
- [ ] Mode menu opens/closes
- [ ] Confirmation countdown works
- [ ] Error overlay displays correctly
- [ ] Portrait layout
- [ ] Landscape layout
- [ ] Button states (enabled/disabled)
- [ ] Touch targets adequate size

---

## Known Limitations & Future Enhancements

### Current Limitations
1. **No multi-autopilot support**: Only one autopilot at a time
2. **No gybe support**: Only tacking implemented
3. **No performance data**: No SOG, VMG, etc.
4. **No autopilot tuning**: No PID settings
5. **No alarm support**: No autopilot alarms

### Future Enhancements
1. **Advanced target setting**: Tap compass to set heading
2. **Performance dashboard**: Add SOG, VMG, set/drift
3. **Gybe support**: Add gybe buttons for downwind
4. **Autopilot status**: Show pilot health, alarms
5. **Multiple instances**: Support multiple autopilots
6. **Custom modes**: Plugin-specific modes
7. **Gesture control**: Swipe to adjust heading
8. **Voice control**: "Autopilot, turn 10 degrees port"

---

## Summary

This autopilot widget is a **complex, feature-rich control interface** that requires:

### ✅ Completed (from Kip)
- Full V1 and V2 API support
- Comprehensive mode management
- Tacking with confirmation
- Route navigation integration
- Error handling and user feedback
- Dodge mode (V2)
- Visual compass with rudder indicator

### 🔨 To Build
- Flutter CustomPainter compass dial
- Button grid layout
- State management service
- API abstraction layer
- Configuration wizard
- All UI components

### 📊 Complexity: **HIGH**
- Multiple API versions
- Complex state management
- Safety-critical confirmations
- Rich visual interface
- Many data paths
- Error handling requirements

### ⏱️ Estimated Effort
- Phase 1-2: 2-3 days (compass visual)
- Phase 3-4: 3-4 days (V1 API + tacking)
- Phase 5: 2-3 days (V2 API)
- Phase 6-7: 3-4 days (route + wind features)
- Phase 8: 2-3 days (config + polish)
- **Total: 12-17 days** for complete implementation

### 🎯 Priority Features (MVP)
1. Compass dial with heading display
2. Mode selector
3. Engage/Disengage
4. Heading adjustment buttons
5. V2 API support (V1 optional)
6. Basic error handling

Start with MVP, then add tacking, route navigation, and advanced features incrementally.
