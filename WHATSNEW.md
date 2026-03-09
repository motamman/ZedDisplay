# What's New in v0.5.42

## Release Notes (Google Play - max 500 chars)

v0.5.42 SignalK Architecture Overhaul & Notification Dedup

IMPROVED: Single WebSocket connection with owner-tracked subscriptions, vessel identity via MMSI/URN, path discovery, and REST-based MetadataStore. Auth guard prevents unauthenticated subscriptions.

FIXED: Notification spam eliminated - stable OS notification IDs replace instead of stacking. 30s throttle for repeated alerts.

## Release Notes (App Store / TestFlight - max 4000 chars)

### SignalK Architecture Overhaul (IMPROVED)
- **Single WebSocket** - Removed separate autopilot channel; all data routes through one connection
- **Subscription Registry** - New owner-tracked subscription system (dashboard, autopilot, anchor_alarm, weather_alerts, etc.) with precise lifecycle management
- **Vessel Identity** - Subscriptions and REST calls use vessel MMSI/URN instead of hardcoded `vessels.self`
- **Path Discovery** - Available paths fetched from server and refreshed every 5 minutes
- **MetadataStore via REST** - Unit preferences populated from REST on connect; WebSocket meta deltas for runtime overrides
- **Auth Guard** - No wildcard subscriptions without valid auth token
- **Cache Dedup** - Own-vessel paths stored once (not 3x per source); source on data point field

### Notification Dedup (FIXED)
- **Stable OS IDs** - Same notification key always uses same OS notification ID, so updates replace instead of stacking in the notification tray
- **Anchor Alarm Replace** - State oscillations (alarm→normal→alarm) replace the existing notification instead of creating new ones
- **30s Throttle** - Same key+state suppressed within 30 seconds to catch reconnect-induced re-sends

### NWS Weather Alerts (IMPROVED)
- **Dashboard Filtering** - Weather notifications only shown when a weather_alerts widget is on the active dashboard
- **Expired Alert Suppression** - Inactive/expired NWS alerts no longer generate notifications

### Dashboard Subscription Sync (FIXED)
- **Live Updates** - Adding or removing widgets now immediately updates SignalK path subscriptions

---

# Previous: v0.5.41

## Release Notes (Google Play - max 500 chars)

v0.5.41 iOS Notification Fix

FIXED: Local notifications now work correctly on iOS. Anchor alarms, crew messages, CPA alerts, and other notifications are now delivered on iOS devices. Previously, iOS was silently dropping all local notifications due to a missing delegate assignment.

## Release Notes (App Store / TestFlight - max 4000 chars)

### iOS Notifications (FIXED)
- **Notifications Delivered** - Local notifications now work correctly on iOS
- **Root Cause** - AppDelegate was missing the `UNUserNotificationCenter` delegate assignment required since iOS 10
- **Affected Alerts** - Anchor alarms, crew messages, CPA collision alerts, intercom activity, and all other local notifications
- **Background Wake** - Added lifecycle handlers to prevent white screen when returning from notification-triggered background wake

---

# Previous: v0.5.40

## Release Notes (Google Play - max 500 chars)

v0.5.40 CPA Alerts & Dependency Upgrade

NEW: CPA collision alerts for AIS with configurable distance and time thresholds. AIS vessel registry for structured tracking. Compass gauge configurator. Hide stale AIS vessels.

IMPROVED: Dashboard performance with deferred widget construction. 54 dependency upgrades including flutter_local_notifications 19→21.

## Release Notes (App Store / TestFlight - max 4000 chars)

### CPA Alert System (NEW)
- **Collision Avoidance** - Configurable Closest Point of Approach alerts
- **Threshold Sliders** - Set CPA distance and TCPA time limits with persistent settings
- **Enabled by Default** - Sensible defaults for immediate protection
- **AIS Integration** - Alerts tied to AIS Polar Chart tool configuration

### AIS Improvements (IMPROVED)
- **Vessel Registry** - Dedicated AISVessel model and registry service for structured vessel tracking
- **Hide Stale Vessels** - Option to filter out vessels with outdated data
- **MetadataStore Conversions** - Unit conversions now use single source of truth
- **Improved Controls Layout** - Better organized AIS Polar Chart controls

### Compass Gauge (NEW)
- **Dedicated Configurator** - New compass-specific configurator with path filtering for heading/bearing paths

### Performance (IMPROVED)
- **Deferred Widget Construction** - Dashboard and tool config screens load faster
- **Zone Fetch Dedup** - Eliminated duplicate HTTP requests for zone data
- **Connection Stability** - Prevented simultaneous connection attempts

### Dependencies (UPDATED)
- 54 packages upgraded (minor/patch versions)
- flutter_local_notifications 19 → 21 (major version)
- flutter_webrtc 1.2.1 → 1.3.0
- Syncfusion packages 32.1 → 32.2
- iOS deployment target aligned to 16.0

---

# Previous: v0.5.28

## Release Notes (Google Play - max 500 chars)

v0.5.27 Chart Smoothing & Dual Axes

NEW: Historical charts now support SMA/EMA smoothing with configurable parameters. Dual Y-axis support when charting different unit types together.

IMPROVED: Smoothed series match realtime chart styling. Legend tap hides both raw and smoothed data together.

FIXED: EMA smoothing with decimal alpha values (e.g., 0.1) now works correctly.

## Release Notes (App Store / TestFlight - max 4000 chars)

### Chart Smoothing Configuration (NEW)
- **Smoothing Types** - Choose SMA (Simple Moving Average) or EMA (Exponential Moving Average)
- **Dynamic Parameters** - SMA uses integer window (5, 10, 20), EMA uses decimal alpha (0.1, 0.3)
- **Automatic Pairing** - Smoothed series automatically displayed alongside raw data

### Historical Chart Improvements (IMPROVED)
- **Consistent Styling** - Smoothed series now match realtime chart appearance
  - Same color as parent series with 60% opacity
  - Dashed line pattern matching realtime chart
  - Hidden from legend to reduce clutter
- **Legend Toggling** - Tapping legend hides both raw and smoothed series together
- **Dual Y-Axis** - Charts support two Y-axes when data sources have different units
  - Automatic axis assignment based on unit categories
  - Secondary axis on right side with dashed grid lines
- **Smart Duration Labels** - X-axis labels adapt to chart duration
  - Short: "10:30 AM", Medium: "10 AM", Long: "Mon 10 AM"

### Bug Fixes (FIXED)
- **EMA Alpha Values** - Fixed crash when using EMA with decimal alpha (e.g., 0.1)
- **History API** - Removed invalid parameter from API requests

---

# Previous: v0.5.26

## Release Notes (Google Play - max 500 chars)

v0.5.26 Server Manager Webapps

NEW: Webapps now show icons and open in-app. Tap any webapp in Server Manager to launch it in a built-in browser with your SignalK authentication - no need to log in again.

FIXED: Removed debug logging spam from unit conversion system.

## Release Notes (App Store / TestFlight - max 4000 chars)

### Server Manager Webapps (NEW)
- **Webapp Icons** - Each webapp now displays its icon in the Server Manager list
- **In-App Browser** - Tapping a webapp opens it in a built-in WebView instead of external browser
- **Auth Pass-Through** - Your SignalK authentication token is automatically passed to webapps
- **Display Names** - Shows webapp display name (from package.json) instead of package name

### Code Cleanup (FIXED)
- Removed verbose debug logging from unit conversion system

---

# Previous: v0.5.25

## Release Notes (Google Play - max 500 chars)

v0.5.25 Channel Subscriptions

NEW: Subscribe/unsubscribe from intercom audio channels. Tap channel icons in Crew List to toggle. Emergency channel (CH16) always on. Captains and First Mates can manage any crew member's subscriptions.

IMPROVED: Tools now default to full grid size. Tools without config can be placed directly.

## Release Notes (App Store / TestFlight - max 4000 chars)

### Channel Subscriptions (NEW)
- **Per-User Subscriptions** - Each crew member can choose which audio channels to receive
- **Crew List Icons** - Channel subscription status shown as icons next to each crew member
- **Toggle Subscriptions** - Tap channel icons to subscribe/unsubscribe from channels
- **Emergency Always On** - CH16 (Emergency) cannot be disabled - always subscribed
- **Admin Control** - Captains and First Mates can manage any crew member's subscriptions
- **Persistence** - Subscriptions saved locally and persist across app restarts
- **User Management** - Admins can also edit subscriptions in User Management Tool

### Tool Placement Improvements (IMPROVED)
- **Default Full Grid** - New tools default to 8x8 size for simpler initial placement
- **Direct Placement** - Tools without required configuration skip config dialog and place directly

---

# Previous: v0.5.24

## Release Notes (Google Play - max 500 chars)

v0.5.24 Anchor Widget Layout

IMPROVED: Anchor alarm widget now uses responsive layout. On wider screens (≥600px), map and controls display side-by-side. On narrow screens, they stack vertically. Controls no longer overlay the map - each gets 50% of the widget area.

## Release Notes (App Store / TestFlight - max 4000 chars)

### Anchor Widget Responsive Layout (IMPROVED)
- **Wide Mode** - Map and controls side-by-side on screens ≥600px wide
- **Narrow Mode** - Map and controls stacked vertically on smaller screens
- **Space Sharing** - Each section gets 50% of widget area (no more overlay)
- **Scrollable Controls** - Control panel scrolls when space is limited
- **Adaptive View Controls** - Buttons positioned appropriately for each layout

---

# Previous: v0.5.23

## Release Notes (Google Play - max 500 chars)

v0.5.23 Anchor Widget Fix

FIXED: Anchor alarm widget now displays values with proper unit symbols. Previously showed raw numbers without units (e.g., "29.0" instead of "29 m").

The anchor-alarm plugin uses a different metadata format that wasn't being handled correctly.

## Release Notes (App Store / TestFlight - max 4000 chars)

### Anchor Widget Unit Display (FIXED)
- **Unit Symbols** - Anchor values (distance, alarm radius, rode length) now show with proper units
- **Root Cause** - Anchor-alarm plugin sends `explicit: true` in displayUnits, skipping formula expansion
- **Solution** - Added category-based conversion lookup when formula not provided
- **Identity Handling** - Correctly handles when user's preferred unit matches SI unit (m→m)

---

# Previous: v0.5.22

## Release Notes (Google Play - max 500 chars)

v0.5.22 iOS App Icons

FIXED: iOS app now uses custom branded icons matching Android. Previously iOS was using generic Flutter default icons.

## Release Notes (App Store / TestFlight - max 4000 chars)

### iOS App Icons (FIXED)
- **Branded Icons** - iOS app now displays custom ZedDisplay icons matching Android
- **App Store Ready** - Alpha channel removed for App Store compliance
- **All Sizes** - Generated all 22 required iOS icon sizes

---

# Previous: v0.5.21

## Release Notes (Google Play - max 500 chars)

v0.5.21 Server Load & Connection Fixes

FIXED: Reduced aggressive polling causing SignalK server issues. Polling intervals increased for messaging (5s→15s), crew presence (15s→30s), admin tools (10s→30s). Admin tools skip polling without valid auth token.

FIXED: "Connection Lost" overlay no longer flashes during reconnect attempts.

## Release Notes (App Store / TestFlight - max 4000 chars)

### Server Load Reduction (FIXED)
- **Polling Intervals** - Reduced server load by increasing poll intervals
  - Messaging: 5s → 15s (67% fewer requests)
  - Crew presence: 15s → 30s (50% fewer requests)
  - Admin tools: 10s → 30s (67% fewer requests)
- **Auth Spam** - User Management and Device Access tools now skip polling when no valid auth token, eliminating thousands of failed 401 requests per day
- **Race Conditions** - Reduced probability of concurrent read/write collisions on SignalK resources

### Connection Overlay (FIXED)
- **No More Flashing** - "Connection Lost" overlay no longer flashes during brief reconnect cycles
- **Smoother UX** - Overlay only appears when connection is truly lost

---

# Previous: v0.5.20

## Release Notes (Google Play - max 500 chars)

v0.5.20 Crew Presence Fix

FIXED: Crew members now correctly show as online when connected to the same SignalK server. Previously, other crew appeared offline even when messaging worked.

The bug was caused by a key mismatch between URL-encoded and canonical user IDs in presence tracking.

## Release Notes (App Store / TestFlight - max 4000 chars)

### Crew Presence (FIXED)
- **Online Status** - Crew members now correctly appear online when connected
- **Root Cause** - Presence was stored with URL-encoded keys (`user%3Arima`) but looked up with canonical IDs (`user:rima`)
- **Impact** - Direct voice calls and online indicators now work correctly
- **Messaging** - Text messaging was unaffected (used different lookup path)

### iOS Background Audio (NEW)
- **Background Modes** - Voice calls now continue when app is backgrounded
- **VoIP Support** - Calls stay connected when switching apps or locking screen

---

# Previous: v0.5.6

## Release Notes (Google Play - max 500 chars)

v0.5.5 Autopilot V2 Tool

NEW: Redesigned circular autopilot with nested controls. Banana-shaped heading adjustment buttons, mode selector, tack/gybe buttons, and draggable target heading.

NEW: Crew members can now be removed from the server. Captain can remove any crew, users can remove themselves.

IMPROVED: Responsive portrait/landscape layouts.

## Release Notes (App Store / TestFlight - max 4000 chars)

### Autopilot V2 Tool (NEW)
- **Circular Design** - Redesigned autopilot with nested controls
- **Banana Buttons** - Heading adjustment buttons (+1, -1, +10, -10) arced around inner circle
- **Mode Selector** - Compass, Wind, Route modes with engage/standby toggle
- **Tack/Gybe** - Wind mode buttons positioned by turn direction
- **Advance Waypoint** - Route mode button at top
- **Dodge Mode** - Center circle button for Route mode
- **Draggable Target** - Long-press to drag target heading with visual feedback
- **Command Queue** - Incremental commands with acknowledgment tracking

### Crew Deletion (NEW)
- Captain can remove any crew member
- Any user can remove themselves
- Confirmation dialogs before deletion
- Clears both server and local storage

---
