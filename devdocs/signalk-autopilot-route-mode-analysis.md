# signalk-autopilot: Route Mode Exhaustive Analysis

**Plugin repo:** https://github.com/SignalK/signalk-autopilot
**Analyzed:** 2026-03-28
**Version:** v2.4.1 (v2.5.0-beta.1 tagged)

## Overview

"Route" mode (Raymarine calls it "Track Mode") engages the autopilot to follow a
navigation route using cross-track error (XTE) and bearing-to-waypoint data. The
plugin only sends **mode change commands** — it does NOT generate navigation data.
APB sentences must flow separately via the `signalk-to-nmea0183` plugin.

---

## Valid Autopilot States

```typescript
// src/index.ts
states: [
  { name: 'standby', engaged: false },
  { name: 'auto',    engaged: true },
  { name: 'wind',    engaged: true },
  { name: 'route',   engaged: true }
]
```

Simrad adds `{ name: 'heading', engaged: true }`. Emulator has no route support.

---

## Route Mode Per Provider

### 1. raymarineN2K (src/raymarinen2k.ts) — Native NMEA2000, EV-1/EV-2

**Set route:** PGN 126208 Group Function Command wrapping PGN 65379 (Seatalk Pilot Mode):
```typescript
const state_modes = {
  auto:    SeatalkPilotMode16.AutoCompassCommanded,   // 0x0040
  wind:    SeatalkPilotMode16.VaneWindMode,            // 0x0100
  route:   SeatalkPilotMode16.TrackMode,               // 0x0180
  standby: SeatalkPilotMode16.Standby                  // 0x0000
}
// Sent via createNmeaGroupFunction → PGN 126208 → PGN 65379
// Target device: EV-1 course computer (default ID 204, auto-discovered)
```

**Advance waypoint:** PGN 65379 with:
```typescript
pilotMode: SeatalkPilotMode16.NoDriftCogReferencedinTrackCourseChanges  // 0x0181
```
Test confirms: `"parameter 4 = No Drift, COG referenced (In track, course changes)"`

**State verification:** Polls `steering.autopilot.state.value` up to 5x at 1s intervals.

**Adjust heading in route:** NOT ALLOWED (guard only permits auto/wind).

---

### 2. raySTNGConv (src/raystngconv.js) — SmartPilot via SeaTalk-STNG-Converter

**Set route:** Raw N2K byte string via PGN 126720 (Raymarine proprietary Seatalk1 encapsulation):
```javascript
const state_commands = {
  auto:    '...126720,...,16,3b,9f,f0,81,86,21, 01,fe, 00,00, 00,00,00,00,ff,ff,ff,ff,ff',
  standby: '...126720,...,16,3b,9f,f0,81,86,21, 02,fd, 00,00, 00,00,00,00,ff,ff,ff,ff,ff',
  route:   '...126720,...,16,3b,9f,f0,81,86,21, 03,fc, 3c,42, 00,00,00,00,ff,ff,ff,ff,ff',
  wind:    '...126720,...,16,3b,9f,f0,81,86,21, 23,dc, 00,00, 00,00,00,00,ff,ff,ff,ff,ff'
}
```

**Route command byte breakdown:**
- `3b,9f` = Raymarine manufacturer code
- `f0,81,86,21` = Seatalk1-over-N2K command envelope
- `03` = route command byte, `fc` = complement (0xFF - 0x03)
- `3c,42` = **mystery bytes** unique to route (auto/wind/standby have `00,00`)

**Default device ID:** 115 (auto-discovered by hardware version string `SeaTalk-STNG-Converter`)

**Advance waypoint:** Sends TWO PGN 126208 messages in sequence:
```javascript
// Message 1: TTW Mode — PGN 126208 → PGN 65379 (pilot mode 0x81,0x01)
const raymarine_ttw_Mode = '%s,3,126208,%s,%s,17,01,63,ff,00,f8,04,01,3b,07,03,04,04,81,01,05,ff,ff'

// Message 2: TTW Command — PGN 126208 → PGN 126720 (proprietary)
const raymarine_ttw      = '%s,3,126208,%s,%s,21,00,00,ef,01,ff,ff,ff,ff,ff,ff,04,01,3b,07,03,04,04,6c,05,1a,50'
```

**No state verification:** Returns `SUCCESS_RES` immediately without confirming AP changed mode.

**Adjust heading in route:** NOT ALLOWED (guard only permits auto/wind).

---

### 3. raymarineST (src/raymarinest.js) — Seatalk 1 Direct

**Set route:** Seatalk1 datagram via `$STALK` + `$PSMDST`:
```
$STALK,86,11,03,FC*xx
$PSMDST,86,11,03,FC*xx
```

**Seatalk1 datagram 86 command reference:**

| Command     | Bytes       | Complement |
|-------------|-------------|------------|
| Auto        | `86,11,01`  | `FE`       |
| Standby     | `86,11,02`  | `FD`       |
| Route/Track | `86,11,03`  | `FC`       |
| Wind        | `86,11,23`  | `DC`       |
| +1°         | `86,11,07`  | `F8`       |
| -1°         | `86,11,05`  | `FA`       |
| +10°        | `86,11,08`  | `F7`       |
| -10°        | `86,11,06`  | `F9`       |
| Tack port   | `86,11,21`  | `DE`       |
| Tack stbd   | `86,11,22`  | `DD`       |

**Advance waypoint:** NOT IMPLEMENTED. Also has a bug: checks `state !== 'track'` but system uses `'route'`.

**Adjust heading in route:** UNIQUELY ALLOWED (auto, standby, OR route).

---

### 4. Simrad (src/simrad.ts) — NAC-3

**Set route:** PGN 130850 `SimnetCommandApNav`

**Advance waypoint:** NOT SUPPORTED.

**Adjust heading in route:** NOT ALLOWED.

---

## State Reading (How Route Is Detected)

**PGN 65379 → state** (raymarineN2K, parsed by `n2k-signalk/raymarine/65379.js`):
- `"Track Mode"` string → `"route"`
- `"No Drift, COG referenced..."` → `"route"`
- Numeric: mode=128 or 129, subMode=1 → `"route"`

**PGN 126720 → state** (STNG converter, parsed by `n2k-signalk/raymarine/126720.ts`):
- `SeatalkPilotMode.Track` (0x4A) with subMode=0 → `"route"`

**PGN 126720 SeatalkPilotMode (8-bit, STNG converter):**

| Mode    | Hex    | Decimal |
|---------|--------|---------|
| Standby | `0x40` | 64      |
| Auto    | `0x42` | 66      |
| Wind    | `0x46` | 70      |
| Track   | `0x4A` | 74      |

**PGN 126720 SeatalkKeystroke enum:**

| Key         | Value | Description        |
|-------------|-------|--------------------|
| Auto        | 1     | Enter Auto mode    |
| Standby     | 2     | Enter Standby      |
| Wind        | 3     | Enter Wind mode    |
| +1          | 7     | +1 degree          |
| +10         | 8     | +10 degrees        |
| -1          | 5     | -1 degree          |
| -10         | 6     | -10 degrees        |
| Tack port   | 33    | -1 and -10         |
| Tack stbd   | 34    | +1 and +10         |
| **Track**   | **35**| Enter Track mode   |

---

## PGN Summary Table

| PGN        | Name                          | Route Usage                                           |
|------------|-------------------------------|-------------------------------------------------------|
| **65360**  | Seatalk Pilot Locked Heading  | Set target heading (Raymarine)                        |
| **65379**  | Seatalk Pilot Mode            | Set AP state; advance WP (Raymarine N2K)              |
| **65384**  | Seatalk Pilot Keep-Alive      | Control head heartbeat (raymarineN2K only)            |
| **126208** | NMEA Group Function           | Wrapper for commanding PGNs 65379 & 65360             |
| **126720** | Raymarine Proprietary          | Seatalk1-over-N2K for STNG converter state commands   |
| **130850** | SimNet Command                | All Simrad AP commands                                |

---

## V1 vs V2 API: Route Mode

| Feature              | V1 (PUT handlers)                          | V2 (AutopilotProvider REST)                              |
|----------------------|-------------------------------------------|----------------------------------------------------------|
| Set route state      | PUT `steering.autopilot.state` → works    | `/v2/.../setState` → works                               |
| Set target in route  | PUT target heading → works                | `setTarget()` → **BROKEN** (apData.mode bug, PR #63)    |
| Adjust heading       | PUT adjustHeading → works (per provider)  | `adjustTarget()` → **BROKEN** (same bug)                 |
| Advance waypoint     | PUT advanceWaypoint → works (N2K, STNG)   | **Not exposed** in V2 API                                |
| Engage (re-engage)   | N/A                                       | Uses `lastState` — re-engages to route if that was last  |

**Conclusion:** V2 API is unusable for route operations beyond mode changes. V1 PUT is required.

---

## GUI Route Mode Behavior (Plugin Web UI)

From `public-src/js/signalk-autopilot.js`:
```javascript
// When already in route mode, pressing route button = advance waypoint
if ((cmd === 'route') && (pilotStatus === 'route') && (actionToBeConfirmed === '')) {
  confirmAdvanceWaypoint(cmd);
  return null;
}
```
Shows confirmation dialog: "Repeat key TRACK to confirm Advance Waypoint" with 5s countdown.

---

## Prerequisites for Route Mode

**Mandatory:** The `signalk-to-nmea0183` plugin must be configured with APB output enabled.

```
Chartplotter/SignalK Route → signalk-to-nmea0183 (APB sentences) → NMEA bus → Autopilot
                                                                      ↑
signalk-autopilot plugin only sends MODE CHANGE commands ─────────────┘
```

Without APB (cross-track error, bearing to waypoint) flowing, the pilot head shows **"NO DATA"** (confirmed Issue #30).

---

## Reported Issues

| Issue | Status | Summary |
|-------|--------|---------|
| **#63** | OPEN | V2 API `setTarget` always 500 — `apData.mode` never populated |
| **#61** | OPEN | Target heading not applied via REST API |
| **#37** | OPEN | Docs say heading in degrees but V2 API expects radians |
| **#30** | OPEN | ST1 route/track gives "NO DATA". Maintainer: *"track mode was never fully implemented"* for ST1 |
| **#27** | OPEN | SPX autopilots use different commands than EV-1 |
| **#22** | OPEN | STNG converter mode changes don't work for some hardware combos |
| **#36** | OPEN | ShipModul Miniplex 3 needs `$PSMDST,C,` prefix format |
| **#21** | OPEN | "No Pilot" — state not read back via ShipModul |

### Bug: raymarineST `putAdvanceWaypoint` checks wrong state string
```javascript
if (state !== 'track') {  // BUG: should be 'route'
```
No practical impact since advance WP is unimplemented for ST1 anyway.

### Bug: STNG converter no state verification
Unlike `raymarineN2K` which polls for confirmation, `raySTNGConv` returns `SUCCESS_RES`
immediately. Mode change may silently fail.

### Bug: Emulator has no route state
Only supports standby/auto/wind — cannot test route mode in emulator.

---

## Provider Comparison Matrix

| Feature                    | raymarineN2K | raySTNGConv  | raymarineST    | simrad       |
|----------------------------|-------------|--------------|----------------|--------------|
| Set route mode             | PGN 65379   | PGN 126720   | `$STALK,86,11,03,FC` | PGN 130850 |
| Advance waypoint           | PGN 65379 NoDrift | 2x PGN 126208 | NOT IMPLEMENTED | NOT SUPPORTED |
| Adjust heading in route    | NO          | NO           | YES            | NO           |
| State verification         | Yes (5x poll) | No         | No             | Yes (5x poll) |
| Default device ID          | 204 (EV-1) | 115 (converter) | N/A (serial) | 3            |
| Prerequisites              | APB on bus  | APB on bus   | APB + ST1 nav datagrams | Active route on plotter |
