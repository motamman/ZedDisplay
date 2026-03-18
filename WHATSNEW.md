# What's New in v0.5.80

## Release Notes (Google Play - max 500 chars)

v0.5.80 AIS Vessel Data on Widgets

NEW: Display AIS vessel data on gauges, compasses, text displays, position, and real-time charts. Select any AIS vessel as the data source — widgets resolve data transparently from cache or registry.

NEW: Edit dialog shows vessel context and pre-selects vessel when changing paths.

IMPROVED: CI/CD workflows for Linux, macOS, and Windows. macOS entitlements for location and microphone.

## Release Notes (App Store / TestFlight - max 4000 chars)

### AIS Vessel Data on Widgets (NEW)
- **Any Widget, Any Vessel** - Radial gauges, linear gauges, compass, text display, position display, and real-time charts can now show data from AIS vessels instead of just your own boat
- **DataSource.resolve()** - Single method handles vessel context transparently — tools don't need to know whether they're showing self or AIS data
- **Registry Fallback** - When WebSocket deltas haven't arrived yet, widgets fall back to REST data from the AIS vessel registry so values appear immediately after configuration
- **Edit with Context** - Editing a data source shows the vessel name/MMSI and opens the path selector with the current vessel pre-selected
- **Source Selector** - Source lookup uses the correct vessel's REST endpoint for AIS paths
- **Non-AIS Tools Unaffected** - Windsteer, autopilot, anchor alarm, weather, and other self-vessel-only tools work exactly as before

### CI/CD & Platform Support (NEW)
- **Linux Builds** - GitHub Actions for x64 and arm64 (RPi5) with install script
- **macOS Builds** - Xcode setup, entitlements (location, microphone), TestFlight upload, install script
- **Windows Builds** - GitHub Actions for x64 releases
- **Platform Tags** - All workflows support platform-specific release tags (e.g., `v*-linux`)

### Under the Hood (IMPROVED)
- **Custom Scroll Behavior** - Enhanced touch and pointer support across all platforms
- **GitHub Actions** - Updated to latest action versions

---

# Previous: v0.5.70

## Release Notes (Google Play - max 500 chars)

v0.5.70 Timeline Playback & Chart Improvements

NEW: Historical Data Explorer timeline playback — play/pause through query results with speed controls (1x–10x), jump buttons, and scrub slider. Sparklines, map, and summary update in sync.

NEW: 1-week chart duration. Vessel context selection for historical queries. Pinch-to-zoom on live charts.

IMPROVED: Swipe-up screen selector, per-screen orientation lock, stale widget cache fix.

## Release Notes (App Store / TestFlight - max 4000 chars)

### Historical Data Explorer — Timeline Playback (NEW)
- **Transport Bar** - Compact playback controls appear at the bottom of the Detail tab when results have multiple points
- **Play/Pause** - Automatically advances through result points, updating sparkline markers, map position, and point summary
- **Forward & Reverse** - Play forward or rewind through the timeline
- **Jump ±10** - Skip forward or back 10 points at a time
- **Speed Control** - Popup menu to select 1x, 2x, 5x, or 10x playback speed
- **Scrub Slider** - Drag to jump to any position in the result set
- **Auto-Stop** - Playback stops automatically at the first or last point
- **Synced Selection** - Tapping a map marker or list row during playback continues from the new position
- **Hidden When Not Needed** - Transport bar only appears when results contain more than one point

### Chart Configurator (NEW)
- **1-Week Duration** - New time range option for historical charts with enhanced data range labels
- **Vessel Context** - Select own vessel or AIS targets when configuring historical data queries

### Real-Time Spline Chart (IMPROVED)
- **Pinch-to-Zoom** - Zoom into live chart data with cached rendering for smooth interaction
- **Simplified Rendering** - Moving average overlay removed for cleaner chart display

### Dashboard Manager (IMPROVED)
- **Swipe-Up Screen Selector** - Screen selector dots now revealed by swiping up instead of always visible
- **Per-Screen Orientations** - Dashboard layouts store allowed orientations per screen
- **Widget Cache Fix** - Tool widgets properly removed from cache on update, preventing stale state

---

# Previous: v0.5.63

## Release Notes (Google Play - max 500 chars)

v0.5.63 Historical Data Explorer & Metadata Fixes

NEW: Historical Data Explorer — query signalk-parquet data by area (bbox/radius) and time range. Draw search areas on the map, view results as color-coded markers with value-proportional sizing, sparklines, and exportable tables.

IMPROVED: Widget state cached across page swipes. Metadata auto-fetched from server for paths missing conversions. Exponential backoff reconnection.

## Release Notes (App Store / TestFlight - max 4000 chars)

### Historical Data Explorer (NEW)
- **Spatial Queries** - Draw a bounding box or radius on the interactive map to define your search area
- **Drag-to-Resize** - Adjust area corners or radius edge after drawing; handles appear on the selection
- **Multi-Path Queries** - Select multiple SignalK paths with aggregation (average, min, max) and optional SMA/EMA smoothing
- **Map Visualization** - Result points plotted as color-coded markers with value-proportional sizing (smallest=lowest value, largest=highest)
- **Smart Filtering** - Points with no data for the active legend path are hidden from the map
- **Legend Switching** - Tap legend series to change the active path; markers resize and recolor instantly
- **Sparkline Detail** - Per-point detail view shows sparkline charts for each queried path with date range and min/max values
- **Expanded View** - Double-tap any sparkline to open a full-size chart modal with point count
- **Map Controls** - Zoom in/out, zoom-to-fit area (bbox and radius), homeport, recenter buttons
- **Save Areas** - Name and save search areas for quick reuse; reload from a saved area list
- **Export** - Share results as CSV or JSON
- **Tabbed Views** - Map, Detail, and Table tabs with swipe navigation
- **Persistent State** - Query results and map position cached across page swipes, screen lock, and reconnects
- **Requires** - signalk-parquet plugin with spatial query support on your SignalK server

### On-Demand Metadata (NEW)
- **Auto-Fetch** - Paths missing unit metadata (e.g., `environment.outside.tempest.observations.airTemperature`) are automatically fetched from the server's REST API
- **Vessel URN** - Uses `/signalk/v1/api/vessels/{vesselURN}/{path}/meta` so it works for own vessel and AIS targets
- **Category Fallback** - MetadataStore now falls back to category-level conversions (temperature, speed, etc.) when no path-specific metadata exists
- **Cached** - Fetched metadata persisted locally for instant display on restart

### Widget Caching (IMPROVED)
- **KeepAlivePage** - Dashboard tools preserve their state when swiping between pages
- **No Rebuild** - Tools no longer tear down and rebuild when navigating away and back
- **Less Network** - Reduces redundant SignalK requests from widget reconstruction

### Reconnection (IMPROVED)
- **Exponential Backoff** - Reconnect attempts use increasing delays instead of fixed intervals
- **Background Probing** - Lightweight server checks detect availability without full reconnect cycle
- **Status Display** - Connection overlay shows reconnection attempt count and next retry time

### Config Screen Flags (IMPROVED)
- **Per-Tool Flags** - New schema flags (`disableDataSources`, `disableUnitSelection`, `disableVisibilityToggles`, `disableTtl`) let tool builders hide irrelevant config sections
- **Cleaner Config** - Tools that don't need unit selection or TTL settings no longer show those options

---

# Previous: v0.5.62

## Release Notes (Google Play - max 500 chars)

v0.5.62 Wind Compass Slots, Dodge Autopilot & Raymarine

NEW: Wind compass config uses fixed named slots — no more index corruption from add/delete. All tools now support path editing in the data source dialog.

NEW: Dodge mode saves/restores autopilot heading and auto-disengages on completion. Raymarine hull type and auto-turn settings.

## Release Notes (App Store / TestFlight - max 4000 chars)

### Wind Compass Slot Definitions (NEW)
- **Named Slots** - 10 fixed slots (Heading True/Magnetic, Wind Direction True, Wind Angle Apparent, Wind Speed True/Apparent, SOG, COG, Waypoint Bearing, Waypoint Distance)
- **No More Index Corruption** - Add/delete buttons hidden; slots can be cleared or have their path changed
- **Path Editing** - Tap edit on any slot to change its SignalK path via the path selector
- **Role Labels** - Each slot shows its role name as the title, path as subtitle

### Path Editing in Edit Dialog (NEW)
- **All Tools** - Every tool's edit data source dialog now includes a Path tile to change the SignalK path
- **Path Selector** - Opens the full path browser to pick a new path

### Dodge Autopilot (NEW)
- **Pre-Dodge State** - Saves current autopilot heading before engaging dodge mode
- **Auto-Restore** - Restores original heading when dodge completes
- **Completion Checks** - Automatically disengages dodge mode when maneuver is complete

### Raymarine Settings (NEW)
- **Hull Type** - Select hull type for autopilot calculations
- **Auto-Turn Speed** - Configure turn rate for autopilot heading changes

---

# Previous: v0.5.60

## Release Notes (Google Play - max 500 chars)

v0.5.60 Dodge Mode, Sun/Moon Arc & Themed Dashboards

NEW: Find Home Dodge Mode — intercept geometry calculates course to pass safely behind (or ahead of) a moving AIS vessel. Sun/Moon Arc tool shows celestial positions and twilight phases.

NEW: 5 themed dashboards covering all 39 widgets. Pick one from Settings → Dashboards.

IMPROVED: AIS max range filtering, vessel lookup, faster dashboard loading.

## Release Notes (App Store / TestFlight - max 4000 chars)

### Find Home — Dodge Mode (NEW)
- **Intercept Geometry** - Calculates course-to-steer to pass safely behind (or ahead of) a moving AIS vessel
- **Stern/Bow Pass** - Toggle between passing astern (default, safer) or ahead with safety checks
- **Safe Distance** - Configurable clearance distance (default 300m) stored in tool config
- **Runway Display** - Target vessel chevron at apex, color-coded track lines (cyan=stern, orange=bow), BOW/STERN labels
- **Haptic Guidance** - Feedback steers to dodge course; wrong-way alerts if deviating > 90°
- **Auto-Detect** - DODGE button appears when AIS target has COG/SOG (is moving); hidden for stationary targets
- **Bow Pass Safety** - Warns when bow pass requires > 90° course change or < 60s to apex

### Sun/Moon Arc Tool (NEW)
- **Celestial Display** - Visual arc showing sun and moon paths across the sky
- **Rise/Set Times** - Sunrise, sunset, moonrise, and moonset with localized formatting
- **Current Position** - Real-time sun and moon position on the arc
- **Twilight Phases** - Civil, nautical, and astronomical twilight indicated
- **Self-Contained** - No data source configuration needed; uses vessel position from SignalK

### 5 Themed Dashboard Layouts (NEW)
- **Sailing** - Wind instruments (windsteer, polar radar), autopilot V2, attitude indicator, realtime charts, position display
- **Weather Station** - All three forecast spinners, weather alerts, sun/moon arc, clock/alarm, historical charts, environmental gauges
- **Passage** - Navigation compass, AIS tracker, find home, autopilot simple, GNSS status, anchor alarm, compass
- **Boat Systems** - Victron power flow, tanks, RPi monitor, system monitor, server & device management, user management, webview, conversion test
- **Controls** - Knob, slider, switch, checkbox, dropdown, radial & linear gauges, text displays, clock & sun/moon arc
- All 39 widget types used at least once across the 5 dashboards
- Select from Settings → Dashboard Setups

### AIS Improvements (IMPROVED)
- **Vessel Lookup** - AIS Polar Chart now configures vessel lookup service for better vessel identification
- **Max Range Filtering** - Distant vessels beyond configured range are filtered for better performance

### Under the Hood (IMPROVED)
- **Dashboard Loading** - Faster startup by avoiding redundant setup service retrieval
- **Expression Evaluation** - ConversionUtils refactored to use GrammarParser for reliable formula parsing
- **Admin Menu** - Cleaner sync bundled setups button (IconButton instead of PopupMenuButton)

---

# Previous: v0.5.51

## Release Notes (Google Play - max 500 chars)

v0.5.51 AIS Vessel Targeting for Find Home

NEW: Select any AIS vessel as the Find Home target — tap a vessel in AIS Tracker to track it. Find Home follows the vessel's live position as your destination.

FIXED: Find Home no longer hangs on "Acquiring device GPS..." after screen switch. Track mode shows correct waiting state.

CHANGED: Compass Gauge 'arc' style removed. 'Add Data Source' renamed to 'Add Path'.

## Release Notes (App Store / TestFlight - max 4000 chars)

### Find Home — AIS Vessel Targeting (NEW)
- **Select from AIS Tracker** - Tap any vessel in the AIS Tracker detail sheet to set it as the Find Home target
- **Live Position Tracking** - Find Home follows the targeted vessel's real-time AIS position as your destination
- **Persistent Selection** - Target vessel survives screen switches and widget rebuilds
- **Clear Target** - Configurator shows active AIS target with a clear button to revert to manual position
- **Requires** - AIS Tracker widget mounted on any screen, plus an AIS receiver (or AIS data source) feeding your SignalK server

### Find Home — Bug Fixes (FIXED)
- **GPS Acquisition Hang** - No longer gets stuck on "Acquiring device GPS..." after switching screens. Falls back to `getCurrentPosition()` when no cached position is available
- **Track Mode Waiting State** - Track mode now shows "Waiting for vessel position..." instead of the misleading "Acquiring device GPS..." message (track mode uses SignalK, not device GPS)
- **AIS Target Visibility** - Selected vessel name now shown during GPS acquisition so you know your selection wasn't lost

### Compass Gauge (CHANGED)
- **Arc Style Removed** - The 'arc' display style has been removed from compass gauge options

### UI (CHANGED)
- **Add Path** - 'Add Data Source' button in tool configurators renamed to 'Add Path' for clarity

### Diagnostics (NEW)
- **Feature Toggle** - Diagnostics can now be enabled/disabled from Settings without restarting

---

# Previous: v0.5.50

## Release Notes (Google Play - max 500 chars)

v0.5.50 AIS Favorites, Find Home & Alert Coordinator

NEW: AIS Vessel Favorites - mark vessels of interest and get notified when they enter AIS range, even when the chart is off-screen. Find Home tool navigates back to saved position with haptic/audio feedback.

IMPROVED: AlertCoordinator centralizes all alert delivery. Lightweight reconnect preserves cached data. Anchor alarm control locking.

## Release Notes (App Store / TestFlight - max 4000 chars)

### AIS Vessel Favorites (NEW)
- **Heart Icon** - Tap to favorite any vessel in the Nearby list
- **Favorites Tab** - New tab in vessel list shows all favorites with live distance/SOG when in range
- **Manual Add** - Add vessels by MMSI + name + notes for boats not currently visible
- **Detection Alerts** - Snackbar with "VIEW" action when a favorited vessel appears in AIS range
- **Background Detection** - Works even when AIS chart is off-screen or app is backgrounded (via AlertCoordinator)
- **Once Per Encounter** - Alert fires once when vessel arrives; resets when vessel leaves range and returns
- **Persistent** - Favorites saved locally and survive app restarts

### Find Home Tool (NEW)
- **Device GPS Navigation** - Navigate back to a saved home position
- **Haptic Feedback** - Configurable vibration patterns for directional guidance
- **Wrong-Way Detection** - Audio and vibration alerts when heading away from home
- **Alert Sounds** - Choose from bell, foghorn, or chimes
- **Configurable Intervals** - Set feedback frequency for navigation updates

### AlertCoordinator (NEW)
- **Centralized Delivery** - All subsystems (anchor alarm, CPA, AIS favorites, weather, clock) route alerts through one gateway
- **Filter Enforcement** - Master toggle, per-level filters, and per-subsystem crew broadcast preferences applied centrally
- **Audio Preemption** - Only one alarm sound at a time; higher severity wins
- **Smart Suppression** - Snackbars suppressed when subsystem overlay is visible or app is backgrounded

### Reconnection & Stability (IMPROVED)
- **Lightweight Reconnect** - Short dropouts preserve cached MetadataStore, subscriptions, and vessel registry instead of full teardown
- **Lifecycle Hardening** - AlertCoordinator tracks foreground state; diagnostics pause/resume with app lifecycle
- **Anchor Alarm** - Control locking prevents accidental changes; tap notification to silence alarm

### AIS & Charts (IMPROVED)
- **Auto-Highlight** - Newly alerted CPA vessels automatically highlighted on chart
- **Mooring Buoy** - New SVG icon for mooring buoy vessel type
- **Historical Chart** - 3-state series visibility (visible, hidden, muted) with improved legend rendering

### Notifications (IMPROVED)
- **Tap-to-Navigate** - System notifications now navigate to the relevant tool when tapped
- **Crew Preferences** - Per-subsystem crew broadcast toggles in settings
- **Message Deletion** - Crew messages can now be deleted

---

# Previous: v0.5.42

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
