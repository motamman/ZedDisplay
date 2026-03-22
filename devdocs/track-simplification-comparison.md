# Track Simplification: ZedDisplay vs OpenCPN

## ZedDisplay: Course-Delta Algorithm

Keeps a waypoint whenever the cumulative heading change exceeds a threshold. Slider controls heading threshold (2°–45°).

**Algorithm:**
1. Always keep first and last point
2. Walk points, compute bearing between consecutive segments
3. When heading change exceeds threshold → keep that point
4. Also keep any point beyond max leg distance (2 NM default)

**Strengths:**
- Never cuts corners — follows the actual turn
- Safe in narrow channels and near hazards
- Intuitive parameter: "how sharp a turn gets a waypoint"

**Weaknesses:**
- More waypoints on gentle curves than RDP
- No collinearity back-check to remove redundant points on straight segments

## OpenCPN: Ramer-Douglas-Peucker (RDP)

Finds the point with maximum cross-track error (XTE) from the line connecting endpoints. If XTE exceeds tolerance, recurses on both sub-segments.

**Source:** `model/src/track.cpp` — `DouglasPeuckerReducer`, `Simplify`, `RouteFromTrack`

**User parameter:** Maximum allowed error in meters (5, 10, 20, 50, 100m for post-hoc reduce; `g_TrackDeltaDistance` = 0.10 NM for track-to-route conversion)

**Additional features:**
- Max leg length constraint (6x planning speed distance) in track-to-route conversion
- Collinearity back-check with distance-adaptive tolerance during live recording
- "Prominent" waypoints forced on long legs (> 4x planning speed distance)
- `m_allowedMaxAngle = 10` is defined but **never used** — heading change is not part of the algorithm

**Strengths:**
- Fewer waypoints for the same shape fidelity
- Well-understood algorithm with decades of use
- Efficient point reduction on straight segments

**Weaknesses:**
- Can cut corners at loose tolerances — simplified line may route through hazards
- Single parameter (XTE) doesn't directly express "preserve turns"
- At 100m tolerance, a tight turn in a narrow channel could be simplified away

## Comparison Table

| Aspect | ZedDisplay (Course-Delta) | OpenCPN (RDP) |
|--------|--------------------------|---------------|
| Algorithm | Heading change threshold | Cross-track error |
| Parameter | Degrees (2°–45°) | Meters (5–100m) |
| Turn handling | Explicit — waypoint at every course change | Implicit — high XTE preserves turns |
| Corner cutting | Never | Possible at loose tolerances |
| Max leg length | 2 NM default | 6x planning speed |
| Waypoint naming | "WPT 1", "WPT 2", etc. | None |
| Collinearity check | No | Yes (live recording only) |
| Safety in narrows | High | Tolerance-dependent |

## Why Course-Delta for ZedDisplay

The primary use case is converting recorded tracks into follow-able routes. Users sail through channels, around headlands, and near shoals. RDP's corner-cutting behavior creates routes that may cross hazards the vessel carefully avoided. Course-delta preserves every significant course change, ensuring the simplified route stays on waters the vessel actually transited.

The trade-off (more waypoints on gentle curves) is acceptable — a few extra waypoints is far better than a route through a reef.

## OpenCPN Source References

| File | Purpose |
|------|---------|
| `model/src/track.cpp` | `DouglasPeuckerReducer`, `Simplify`, `RouteFromTrack`, `AddPointNow`, `GetXTE` |
| `model/include/model/track.h` | Declarations, precision members |
| `gui/src/routemanagerdialog.cpp` | Reduce Data dialog UI |
| `libs/geoprim/src/LOD_reduce.cpp` | Chart geometry RDP variants |
| `model/src/config_vars.cpp` | `g_TrackDeltaDistance` default (0.10 NM) |
