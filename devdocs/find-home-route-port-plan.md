# Plan: Port Autopilot Route Navigation into FindHome

## Context

FindHome has an ILS runway display that shows bearing, deviation, distance. Currently it only targets a home position or AIS vessel. The autopilot tool has full route navigation — state control, heading adjustment, advance waypoint, tack/gybe/dodge, route data display (XTE, bearing, distance, ETA, next waypoint).

Port the autopilot's route functionality into FindHome so the ILS runway becomes a full route navigation instrument with autopilot control.

## What Gets Ported

From the autopilot tool (`autopilot_tool_v2.dart`) into FindHome:

### Data
- Subscribe to `navigation.course.calcValues.*` paths (bearing, distance, timeToGo, ETA)
- Subscribe to `navigation.courseGreatCircle.nextPoint.position`
- Subscribe to `navigation.course.calcValues.crossTrackError`
- Read autopilot state, target heading, engaged status

### Autopilot Control
- API detection (V1/V2) — reuse `AutopilotApiDetector` + `AutopilotV2Api`
- Engage/disengage
- Mode switching (standby/auto/wind/route)
- Set target heading
- Adjust heading ±1°/±10°
- Advance waypoint (with countdown confirmation)
- Tack/gybe
- Dodge (V2 API)

### Display (mapped to ILS runway)
- Route bearing → runway centerline (deviation = XTE)
- Distance to waypoint → distance display
- ETA/TTW → info overlay
- Next waypoint position → info overlay
- Autopilot state/mode → status indicator
- Target heading vs current heading → deviation needle

## New Mode in FindHome

Add a **ROUTE** mode toggle alongside existing TRACK and DODGE buttons. When active:

1. **Runway source switches** from bearing-to-home → route bearing from `navigation.course.calcValues.bearingTrue`
2. **Deviation switches** from COG-vs-bearing → cross-track error (XTE) mapped to runway lateral offset
3. **Distance switches** from distance-to-home → distance to next waypoint
4. **Autopilot controls appear** — the same controls as the autopilot tool: ±1/±10 buttons, mode selector, engage/disengage, advance waypoint

## Files to Modify

| File | Changes |
|------|---------|
| `lib/widgets/tools/find_home_tool.dart` | Add route mode state, subscribe to route paths, AP API integration, AP control methods, UI controls overlay |
| `lib/services/dodge_autopilot_service.dart` | May reuse for AP detection/state management, or create new service |

## Files to Reference (port from)

| File | What to port |
|------|-------------|
| `lib/widgets/tools/autopilot_tool_v2.dart` | AP control methods, route data subscription, V1/V2 command sending |
| `lib/services/autopilot_v2_api.dart` | V2 API client (already exists, just wire it) |
| `lib/services/autopilot_api_detector.dart` | API detection (already exists, just wire it) |
| `lib/widgets/autopilot_widget_v2.dart` | UI patterns for ±1/±10 buttons, mode menu, engage button |

## Implementation Approach

### Phase 1: Route data into the runway
- Add `_routeMode` boolean
- When active, subscribe to route calcValues paths
- Map route bearing → runway bearing, XTE → deviation, distance → distance display
- Show route info (next WPT, DTW, TTW, ETA) in overlay

### Phase 2: Autopilot control
- Add AP detection + V2 API setup (same pattern as `DodgeAutopilotService.detectAutopilot()`)
- Add state tracking: `_apState`, `_apEngaged`, `_apTarget`
- Add control methods: engage, disengage, setState, setTarget, adjustHeading, advanceWaypoint, tack, gybe, dodge
- Wire V1/V2 command sending (same `_sendCommand` pattern from autopilot_tool_v2)

### Phase 3: UI controls
- ROUTE button in the button row
- When route mode active: show AP state indicator, ±1/±10 arc buttons (or simplified controls), mode menu, engage/disengage, advance waypoint
- Adapt the existing runway painter to show XTE-based deviation

## Verification

1. `flutter analyze` — no warnings
2. Activate route on SignalK server
3. Open FindHome → tap ROUTE → verify runway shows route bearing/XTE
4. Verify AP controls work: engage route, adjust heading, advance waypoint
5. Verify existing modes (home, track, dodge) still work unchanged
