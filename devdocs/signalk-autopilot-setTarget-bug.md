# Bug: signalk-autopilot plugin — `setTarget` always returns 500

**Plugin repo:** https://github.com/SignalK/signalk-autopilot
**Discovered:** 2026-03-20
**Status:** Unfixed upstream. Client-side workaround in ZedDisplay.

## Summary

The V2 API `setTarget` endpoint (`PUT /signalk/v2/api/vessels/self/autopilots/{id}/target`) always returns HTTP 500 because the plugin never populates `apData.mode`, which `setTarget` checks before dispatching the command.

## Root Cause

In `src/index.ts`, the `processAPDeltas` function processes incoming N2K delta messages and updates the plugin's internal state object `apData`. When it receives a `steering.autopilot.state` delta, it correctly updates:

- `apData.state` (e.g., "auto", "wind", "route", "standby")
- `apData.engaged` (derived from state → engaged boolean)
- `apData.target` (from target heading/wind deltas)

But it **never sets `apData.mode`**. The field remains `null` for the entire session.

The V2 API provider registers a `setTarget` handler that gates on `apData.mode`:

```typescript
setTarget: async (value, _deviceId) => {
    if (apData.mode === 'auto') {
        return autopilot.putTargetHeadingPromise(radiansToDegrees(value))
    } else if (apData.mode === 'wind') {
        return autopilot.putTargetWindPromise(radiansToDegrees(value))
    } else {
        throw new Error(`Unable to set target value! MODE = ${apData.mode}`)
    }
}
```

Since `apData.mode` is always `null`, this always throws, returning:

```json
{"state":"FAILED","statusCode":500,"message":"Unable to set target value! MODE = null"}
```

## What Works vs What Doesn't

| V2 Endpoint | Works? | Why |
|-------------|--------|-----|
| `POST .../engage` | Yes | Calls `putStatePromise()` directly, no mode check |
| `POST .../disengage` | Yes | Calls `putStatePromise('standby')` directly |
| `PUT .../state` | Yes | Calls `putStatePromise()` directly |
| `PUT .../target/adjust` | Yes | Calls `putAdjustHeadingPromise()`, no mode check |
| `PUT .../target` | **No — always 500** | Checks `apData.mode` which is always null |
| `PUT .../mode` | **No — 500** | `getMode`/`setMode` throw "Not implemented!" |

## The Design Gap: State vs Mode

The V2 Autopilot API distinguishes between:
- **state**: operational state (auto, wind, route, standby) — maps to engaged/disengaged
- **mode**: mode of operation (compass, gps, wind, etc.) — finer-grained

The Raymarine provider maps pilot modes (`AutoCompassCommanded`, `VaneWindMode`, `TrackMode`, `Standby`) to **states** only. The `modes()` method is never implemented, `apData.options.modes` stays `[]`, and `apData.mode` is never derived from the state.

## Suggested Plugin Fix

In `processAPDeltas`, after updating `apData.state`, derive mode from state:

```typescript
if (pathValue.path === state_path) {
    apData.state = isValidState(pathValue.value) ? pathValue.value : null
    const stateObj = apData.options.states.find((i) => i.name === pathValue.value)
    apData.engaged = stateObj ? stateObj.engaged : false

    // Fix: derive mode from state for V2 API setTarget compatibility
    const stateToMode: Record<string, string> = {
        'auto': 'auto',
        'wind': 'wind',
        'route': 'route'
    }
    apData.mode = stateToMode[pathValue.value] ?? null

    app.autopilotUpdate(apType, {
        state: apData.state,
        engaged: apData.engaged,
        mode: apData.mode
    })
}
```

## ZedDisplay Workaround

In `lib/services/autopilot_v2_api.dart`, `setTarget()` fetches the current target via `getAutopilotInfo()`, computes the delta to the desired heading, and uses `adjustTarget()` (which has no mode check) instead of the broken `/target` endpoint.

This workaround has one limitation: if there is no current target (autopilot just engaged, no target set yet), it falls back to the direct `/target` endpoint which will 500. In practice this rarely happens because engaging in "auto" mode sets a target from the current heading.

## Verified On

- SignalK server v2.x
- signalk-autopilot plugin (installed from npm, version on server as of 2026-03-20)
- Raymarine autopilot via STNG converter (raySTNGConv provider, device ID 115)
- All other V2 endpoints (engage, disengage, state, adjust) confirmed working
