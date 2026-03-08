# SignalK Architecture Overhaul

## Context

Diagnostic service revealed ~700MB RSS on Pixel 10 Pro XL within 30 seconds of connecting.

Root causes:
- 3 WebSocket connections per device (data, autopilot, notifications) — should be 1
- 6,100 cache entries for 2,038 paths (3x duplication per path)
- Wildcard `*` subscription when unauthenticated — receives all 2,067 paths
- Metadata populated via WebSocket instead of REST — chicken-and-egg with subscriptions
- `vessels.self` used everywhere instead of MMSI
- No path catalog — no way to browse available paths without subscribing

## Implementation Order

| Stage | Phase | Risk | Key Verification |
|-------|-------|------|-----------------|
| 1 | Auth Guard (A3) | Low | No wildcard sub without auth |
| 2 | Data Cache Dedup (D1) | Medium | `latestData.length` drops ~3x |
| 3 | Vessel Identity (A2) | Low | Subscriptions use MMSI URN |
| 4 | Path Discovery (B2) | Low | `availablePaths` populated on connect |
| 5 | MetadataStore via REST (C1) | Medium | MetadataStore filled without WS meta |
| 6 | Subscription Registry (B1) | Medium | Central registry tracks all owners |
| 7 | Single WebSocket (A1) | High | Server shows 1 WS per device |

## Phase 1: Auth Guard (A3)

Remove wildcard `*` subscription fallback when unauthenticated.

**Changes in `signalk_service.dart`:**
- `_sendSubscription()`: Remove lines 521-533 (wildcard fallback)
- Guard `_updateSubscription()` to skip if no auth token
- Guard `_sendSubscription()` to only subscribe if authenticated

## Phase 2: Data Cache Dedup (D1)

Store each own-vessel path once instead of 3 times.

**Changes in `signalk_service.dart`:**
- `_handleMessage()`: Remove context-path storage (line 700-701) and source-path storage (line 704-706)
- Add `source` field to `SignalKDataPoint`
- Update `_DataCacheManager.getValue(source:)` to check `dataPoint.source` field

## Phase 3: Vessel Identity (A2)

Use MMSI/URN instead of `vessels.self`.

**Changes in `signalk_service.dart`:**
- Store vessel URN from `getVesselSelfId()` as `_vesselUrn`
- Use in `_updateSubscription()` context
- Use in REST URL construction

## Phase 4: Path Discovery (B2)

Fetch available paths via `GET /skServer/availablePaths`.

**Changes in `signalk_service.dart`:**
- Add `_availablePaths` list, fetch on connect
- Add `getAvailablePathsList()` method using the lightweight endpoint
- Update `path_selector.dart` to use new method

## Phase 5: MetadataStore via REST (C1)

Populate MetadataStore from REST endpoints instead of WebSocket meta.

**Changes:**
- `_ConversionManager.fetchConversions()`: populate MetadataStore directly
- `metadata_store.dart`: add `populateFromPreset()` method
- Remove `sendMeta=all` from WS URL

## Phase 6: Subscription Registry (B1)

Central registry for path subscriptions with owner tracking.

**Changes:**
- New `PathSubscriptionRegistry` class
- Replace `_activePaths` Set with registry
- All subscription callers register with owner ID

## Phase 7: Single WebSocket (A1)

Merge 3 WebSocket connections into 1.

**Changes:**
- Remove `_autopilotChannel` and `_notificationChannel`
- Route autopilot subscriptions to main channel
- Route notification messages in `_handleMessage()`

## Files Modified

| File | Phases |
|------|--------|
| `lib/services/signalk_service.dart` | All |
| `lib/services/metadata_store.dart` | 5 |
| `lib/models/signalk_data.dart` | 2 |
| `lib/services/dashboard_service.dart` | 6 |
| `lib/services/anchor_alarm_service.dart` | 6 |
| `lib/widgets/tools/weather_alerts_tool.dart` | 6 |
| `lib/widgets/tools/weather_api_spinner_tool.dart` | 6 |
| `lib/widgets/tools/autopilot_*.dart` | 6, 7 |
| `lib/widgets/config/path_selector.dart` | 4 |
