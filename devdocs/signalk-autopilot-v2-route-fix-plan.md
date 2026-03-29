# Plan: Fix V2 Route Mode in signalk-autopilot Fork

**Fork:** `/Users/mauricetamman/Documents/zennora/signalk/signalk-autopilot`
**Branch:** `fix/setTarget-mode` (already has PR #63 mode fix)
**Date:** 2026-03-28
**Reference:** `signalk-autopilot-route-mode-analysis.md` (exhaustive PGN/provider research)

---

## Problem Statement

The signalk-autopilot V2 API has three broken/missing route operations:

| V2 API Method | Status | Root Cause |
|---------------|--------|------------|
| `setTarget` | BROKEN | Was checking `apData.mode` (null). **FIXED in fork** — fallback to `apData.state` |
| `adjustTarget` | PARTIALLY BROKEN | Works mechanically, but per-provider guards block it in route mode (only auto/wind allowed on N2K/STNG). This is correct behavior — route target comes from APB, not manual input |
| `courseNextPoint` | NOT IMPLEMENTED | Throws "Not implemented!" — but the V1 `putAdvanceWaypoint` already works |
| `courseCurrentPoint` | NOT IMPLEMENTED | Throws "Not implemented!" — should engage route mode (steer to current destination) |
| `getMode`/`setMode` | NOT IMPLEMENTED | Throws — Raymarine conflates state and mode; `apData.mode` mirrors `apData.state` |
| `dodge` | NOT IMPLEMENTED | Throws — Raymarine-specific; low priority |
| `gybe` | NOT IMPLEMENTED | Throws — could reuse tack with different keystroke |
| `options.actions` | EMPTY | Never populated — clients can't discover what's available |

---

## What's Already Fixed (Commit 7f40f72)

1. `apData.mode = apData.state` in `processAPDeltas` (line 395)
2. `setTarget` fallback: `const mode = apData.mode ?? apData.state` (line 298)
3. `engage()` eagerly sets `apData.state` and `apData.mode` before `putStatePromise` (lines 313-316)

---

## Remaining Fixes

### Fix 1: Wire `courseNextPoint` to existing `putAdvanceWaypoint`

The V1 handler already works for raymarineN2K and raySTNGConv. The V2 method just needs to call it.

**File:** `src/index.ts`, lines 333-335

```typescript
// BEFORE:
courseNextPoint: async (_deviceId: string): Promise<void> => {
  throw new Error('Not implemented!')
}

// AFTER:
courseNextPoint: async (_deviceId: string): Promise<void> => {
  const state = app.getSelfPath(state_path)
  if (state !== 'route') {
    throw new Error('Autopilot not in route/track mode')
  }
  return new Promise<void>((resolve, reject) => {
    const result = autopilot.putAdvanceWaypoint(
      'vessels.self', advance, 1, undefined
    )
    if (result.state === 'COMPLETED') {
      resolve()
    } else {
      reject(new Error(result.message || 'Advance waypoint failed'))
    }
  })
}
```

### Fix 2: Wire `courseCurrentPoint` to engage route mode

Per the API spec: *"The intended result of this action is that the autopilot device be engaged in the appropriate mode to steer to the active waypoint/position."*

```typescript
// BEFORE:
courseCurrentPoint: async (_deviceId: string): Promise<void> => {
  throw new Error('Not implemented!')
}

// AFTER:
courseCurrentPoint: async (_deviceId: string): Promise<void> => {
  return autopilot.putStatePromise('route')
}
```

### Fix 3: Implement `getMode`/`setMode` (mirror state)

Raymarine doesn't separate state from mode. The API requires these methods. Mirror state.

```typescript
// BEFORE:
getMode: async (_deviceId) => {
  throw new Error('Not implemented!')
},
setMode: async (_mode, _deviceId) => {
  throw new Error('Not implemented!')
},

// AFTER:
getMode: async (_deviceId) => {
  return apData.mode
},
setMode: async (mode, _deviceId) => {
  // Raymarine conflates mode and state — setting mode sets state
  if (isValidState(mode)) {
    return autopilot.putStatePromise(mode)
  } else {
    throw new Error(`${mode} is not a valid mode value!`)
  }
},
```

### Fix 4: Populate `options.actions` dynamically

The `AutopilotActionDef` interface has `available: boolean` that should reflect current state.

**In `processAPDeltas`**, after updating state (around line 406):

```typescript
// Update available actions based on current state
apData.options.actions = [
  {
    id: 'tack' as const,
    name: 'Tack',
    available: apData.state === 'wind' || apData.state === 'auto'
  },
  {
    id: 'gybe' as const,
    name: 'Gybe',
    available: false  // not implemented
  },
  {
    id: 'courseNextPoint' as const,
    name: 'Advance Waypoint',
    available: apData.state === 'route'
  },
  {
    id: 'courseCurrentPoint' as const,
    name: 'Steer to Waypoint',
    available: apData.state !== 'route'  // available when NOT already in route
  },
  {
    id: 'dodge' as const,
    name: 'Dodge',
    available: false  // not implemented
  }
]
app.autopilotUpdate(apType, { actions: apData.options.actions })
```

### Fix 5: Add `putAdvanceWaypointPromise` to Autopilot interface

The `Autopilot` interface (line 101-106) has `putAdvanceWaypoint` but the Promise version is commented out (line 125). For `courseNextPoint` to work cleanly, uncomment and implement it.

**File:** `src/index.ts`, line 125:
```typescript
// Uncomment:
putAdvanceWaypointPromise(value: any): Promise<void>
```

Then implement it in each provider the same way `putStatePromise` etc. are implemented (wrapping the callback-style method in a Promise). Actually — looking at the code, the `putXxxPromise` methods are likely generated by a helper. Check how `putStatePromise` is created and replicate for `putAdvanceWaypoint`.

**Alternative (simpler):** Keep `courseNextPoint` using the callback-style `putAdvanceWaypoint` as shown in Fix 1. This avoids touching every provider file.

---

## What NOT to Fix (Out of Scope)

| Item | Why Skip |
|------|----------|
| `adjustTarget` in route mode | Correct behavior — route target comes from APB/XTE, not manual heading. The provider guards (auto/wind only) are intentional |
| `dodge` | Raymarine-specific, undocumented PGN sequences, low priority |
| `gybe` | Similar to tack but different keystroke — implement later |
| Navigation data generation (PGN 129283/129284/129285) | This is the chartplotter's job, not the AP plugin. signalk-to-nmea0183 with APB enabled handles this |
| raymarineST `putAdvanceWaypoint` 'track' vs 'route' bug | ST1 advance WP is unimplemented anyway |
| Emulator route support | Nice-to-have for testing, not blocking |

---

## Files to Modify

| File | Changes |
|------|---------|
| `src/index.ts` | Fix 1-5: wire courseNextPoint/courseCurrentPoint, implement getMode/setMode, populate actions, optionally add putAdvanceWaypointPromise |

Only ONE file needs changes. All provider files (raymarinen2k.ts, raystngconv.js, etc.) remain untouched — the V1 `putAdvanceWaypoint` handlers already work.

---

## Impact on ZedDisplay

Once these fixes are deployed to the SignalK server:

1. **`courseNextPoint`** — ZedDisplay's `_handleAdvanceWaypoint` can use V2 API: `POST /autopilots/{id}/courseNextPoint` instead of V1 PUT
2. **`courseCurrentPoint`** — New capability: one-tap "steer to waypoint" button
3. **`options.actions`** — ZedDisplay can dynamically show/hide buttons based on `available` flag
4. **`getMode`/`setMode`** — ZedDisplay's V2 API calls won't throw

The V1 fallback in ZedDisplay (`_mode.toLowerCase() != 'route'` guard in `_sendCommand`) remains as a safety net for servers running the upstream unfixed plugin.

---

## Verification

1. `npm run build` — TypeScript compiles without errors
2. `npm test` — existing tests pass (putAdvanceWaypoint tests already assert correct behavior)
3. Manual: activate route on SignalK, call `POST /signalk/v2/api/vessels/self/autopilots/{id}/courseNextPoint`, verify PGN sent
4. Manual: call `GET /signalk/v2/api/vessels/self/autopilots/{id}` — verify `options.actions` populated with `available` flags

---

## End-to-End Route Mode Checklist

For route mode to work at all (regardless of V1 vs V2), this full chain must be in place:

```
┌─────────────────────┐     ┌──────────────────────┐     ┌──────────────┐
│ Route Source         │────▶│ signalk-to-nmea0183  │────▶│ Autopilot    │
│ (OpenCPN / SignalK   │     │ APB + XTE + RMB      │     │ (EV-1/STNG)  │
│  Course API / MFD)   │     │ sentences enabled     │     │              │
└─────────────────────┘     └──────────────────────┘     └──────────────┘
                                                                ▲
┌─────────────────────┐                                         │
│ signalk-autopilot   │─── setState('route') / courseNextPoint ─┘
│ (mode commands only) │
└─────────────────────┘
```

**Prerequisites on the SignalK server:**
- [ ] `signalk-to-nmea0183` plugin installed and configured
- [ ] APB sentence output **enabled** in signalk-to-nmea0183
- [ ] A route/destination active in the SignalK Course API OR an external chartplotter providing nav data
- [ ] signalk-autopilot configured with correct autopilot type and device ID
