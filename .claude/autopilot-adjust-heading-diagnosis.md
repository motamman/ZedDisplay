# Autopilot +/- (adjust heading) ignored in heading mode — diagnosis

**Date:** 2026-06-21
**Status:** Root cause located. NOT a ZedDisplay bug — it's the forked autopilot **plugin**. Not yet fixed (no edits made; awaiting go-ahead).

## Symptom
- In **heading (auto) mode**, the +/- buttons (adjust by ±1 / ±10) are **ignored by the autopilot**, even though the app shows "command successful".
- **Setting an absolute heading works fine.**
- Reported as a **regression** (used to work).
- User not aboard; cannot drive the AP for live testing.

## Verdict
**The bug is in the forked `signalk-autopilot` plugin, not in ZedDisplay.** Every stage from the app to the plugin's command dispatch was read and verified correct. The only difference between the working "set" and the broken "+/-" is **which NMEA2000 command is emitted**:

| Action | Plugin path | N2K command | Result |
|---|---|---|---|
| Set heading | `putTargetHeading` | PGN **65360** SeatalkPilotLockedHeading (wrapped in 126208 group function) | ✅ works |
| +/- adjust | `putAdjustHeading` → `changeHeadingByKey` | PGN **126720** Seatalk1 **keystroke** | ❌ EV‑1 ignores |

## Environment (verified live on the boat via `ssh inside`)
- Active autopilot (v2 API `GET /signalk/v2/api/vessels/self/autopilots`): **instance `raymarineN2K`, provider `autopilot`, isDefault** — a Raymarine EV‑1 over N2K.
- Plugin: **"Signal K autopilot" (`signalk-autopilot`) v2.6.0**, OFFICIAL, installed as a **GitHub fork** (not npm, not symlinked). Config id `autopilot`.
- **`pypilot-autopilot-provider` is INSTALLED BUT DISABLED — it is NOT the provider.** (Repeated red herring; ignore it.)
- Plugin config `~/.signalk/plugin-config-data/autopilot.json`:
  `type: raymarineN2K, enableV2API: true, enableDebug: true, enableLogging: false, deviceid: 204, converterDeviceId: 115, controlHead: false, outputEvent: seatalkOut, simradDeviceId: 3`.
- Boat **signalk-server v2.28.0**, systemd `signalk.service`, config `/home/maurice/.signalk`, started 2026‑06‑21 10:41 EDT.
- **Local fork clone of the plugin: `/Users/mauricetamman/signalk-autopilot`** (branch `fix/raymarinen2k-advance-waypoint-ttw`). This is the source to read/edit. Also a sibling `/Users/mauricetamman/signalk-autopilot-beta3`.

## The verified chain (all correct — these were ruled OUT)
1. **App send** — `lib/services/autopilot_v2_api.dart`:
   - `adjustTarget()` (L175‑183): `PUT …/autopilots/{id}/target/adjust` body `{value: ±1/±10, units: 'deg'}`.
   - `useKeystrokeStrategy` is **false** for `raymarineN2K` (only forced true for `raySTNGConv`, L18‑21). So set uses the direct `/target` endpoint (L127‑135). `_setTargetViaKeystrokes` (L139‑172) decomposes a *set* into +/- keystrokes — only used when keystroke strategy is on (not here), which is why set works and +/- doesn't.
   - `_sendCommand` (`lib/widgets/tools/autopilot_tool.dart:416`) chooses v1/v2 by `_apiVersion` — **same choice for set and adjust** (so not a v1-vs-v2 split).
2. **Server** — boat-deployed `signalk-server` 2.28.0 `/target/adjust` handler **converts `units:'deg'`→radians** exactly like `/target`: `v = value*(π/180)` then `provider.adjustTarget(v)`. (Confirmed by reading the deployed `dist/api/autopilot/index.js`; matches local `src/api/autopilot/index.ts:478‑505`.) So `adjustTarget` receives **radians** (±0.0175 / ±0.175).
3. **Fork v2 adapter** — `signalk-autopilot/src/index.ts:308‑312`:
   `adjustTarget: (value) => putAdjustHeadingPromise(Math.floor(radiansToDegrees(value)))`. The deg→rad→deg round-trip recovers **exactly ±1/±10** (verified with a node calc — `Math.floor` does NOT truncate to 0/9). `setTarget` (L297‑307) → `putTargetHeadingPromise(radiansToDegrees(value))`.
4. **Fork promise wrapper** — `src/actionPromise.ts`: `toActionPromise` resolves immediately on a synchronous non‑PENDING result (L67‑73). `putAdjustHeading` returns `SUCCESS_RES` synchronously **after** emitting the keystroke, so the wrapper is fine; v1 and v2 both emit the same keystroke.
5. **Fork command dispatch** — `src/raymarinen2k.ts`:
   - `putAdjustHeading` (L383‑409): exact `switch` on `1/-1/10/-10` → `changeHeadingByKey(app, deviceid, '+1'…)` → `sendN2k(...)`; anything else → `FAILURE`.
   - `changeHeadingByKey` (L575‑590): `return [ new PGN_126720_Seatalk1Keystroke({device:33, key: st_keys[key].key, keyinverted: st_keys[key].inverted}, deviceid) ]`.
   - `sendN2k` (L544‑555): PGN objects → `app.emit('nmea2000JsonOut', msg)`.
   - **Working set** `putTargetHeading` (L303‑322): `createNmeaGroupFunction(GroupFunction.Command, new PGN_65360_SeatalkPilotLockedHeading({targetHeadingMagnetic: degsToRad(value)}), …)`.

## Ruled out (explicitly)
- **Units / value mapping** — app, server, and fork all consistent; +/- arrives as the correct ±1/±10. (The earlier "send radians not degrees" theory was based on a *wrong plugin assumption* and is incorrect for server 2.28.0.)
- **v1 vs v2 API** — same `_apiVersion` for set and adjust; promise wrapper emits the keystroke correctly on both. Not the cause.
- **ZedDisplay app** — sends the +/- correctly. No app change needed for this bug.

## Prime regression suspect
The TypeScript conversion (`5c6709b feat: convert to typescript`) replaced the **old hand-crafted raw keystroke command** with the `@canboat/ts-pgns` `PGN_126720_Seatalk1Keystroke`. The old command is still present **commented out** at `raymarinen2k.ts:589`, and its byte template is at L85:
`key_command = "%s,7,126720,%s,%s,22,3b,9f,f0,81,86,21,%s,ff,ff,ff,ff,ff,c1,c2,cd,66,80,d3,42,b1,c8"` with `keys_code: {"+1":"07,f8","+10":"08,f7","-1":"05,fa","-10":"06,f9"}`.
The generated 126720 frame likely does **not** reproduce these exact bytes (esp. the trailing `c1 c2 cd 66 80 d3 42 b1 c8`), so the EV‑1 ignores it. **Not byte-confirmed** — the actual wire bytes are produced by canboatjs on the boat at emit time, and we couldn't capture them (see below).

## Why we couldn't get a log capture
- `signalk.service` writes **~1 line per session** to journald — SignalK's plugin debug (`changeHeadingByKey`, `n2k_msg`) is **not** reaching journald, even with `enableDebug:true`.
- journald appears **volatile**; an **afternoon server restart** wiped the morning's logs (8am–noon window had 1 line). So the morning evidence is gone.
- To capture the emitted keystroke frame: point SignalK debug at a log (DEBUG namespace for `signalk-autopilot` / the autopilot API, or wire `enableDebug` to a file), **engage the AP (safety call — owner only)**, press +/-, read the `n2k_msg`/`nmea2000JsonOut` frame, compare to the old `key_command` bytes.

## Fix options (PLUGIN-side, in `/Users/mauricetamman/signalk-autopilot`)
- **A — Sidestep the keystroke (recommended, robust):** make adjust compute `current target ± delta` and SET it via the **working PGN 65360 locked-heading** path (`putTargetHeading`) instead of emitting a 126720 keystroke. Reuses the proven command; no dependency on getting the SeaTalk keystroke frame exactly right. Notes: `putTargetHeading` requires state `auto`; current target is available as `apData.target` in `index.ts`. (Adjust in `wind` mode would still need its own handling.)
- **B — Fix the keystroke frame:** capture the emitted bytes (above), then correct the `PGN_126720_Seatalk1Keystroke` construction (or restore the raw `key_command`) so it matches the known-working bytes.

## Guardrails
- Do **not** edit the forked plugin or send any command to the autopilot without the owner's explicit go-ahead.
- Boat access is `ssh inside`. Avoid `grep` over `node_modules` (false positives, e.g. pypilot) — use the live API / config files / `awk` instead.

## Key files
- App: `lib/services/autopilot_v2_api.dart`, `lib/widgets/tools/autopilot_tool.dart`
- Fork: `/Users/mauricetamman/signalk-autopilot/src/{index.ts, raymarinen2k.ts, actionPromise.ts}`
- Server API (reference): `/Users/mauricetamman/signalk-server/src/api/autopilot/index.ts`
