# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.94+67] - 2026-03-22

### Added
- **Autopilot V2 API — Full SignalK V2 Support**: Autopilot widgets now use the SignalK V2 Autopilot API with automatic instance discovery. V2 detection with V1 fallback. Fixes 405 errors on autopilot state changes.
- **Autopilot — raySTNGConv Keystroke Strategy**: For SeaTalk-STNG converter setups, absolute heading changes are decomposed into +1/-1/+10/-10 keystroke commands since the converter can't translate PGN 126208 heading commands.
- **Autopilot — Banana Button Hit Areas**: Fixed overlapping tap areas on compass heading adjustment buttons. All four buttons (-10, -1, +1, +10) now respond correctly using ClipPath hit testing.
- **Autopilot — Compass Drag Stability**: Target heading drag now freezes the reference heading at drag start, preventing the selector from jumping as the boat turns mid-drag.
- **Historical Data Explorer — Save as Waypoint**: Tap any data point, save its position as a SignalK waypoint via the Resources API. Available in FreeboardSK and other clients.
- **Historical Data Explorer — Save as Track**: Save query results as a SignalK track resource (MultiLineString GeoJSON). One button in the overlay toolbar.
- **Historical Data Explorer — Save as Route**: Save query results as a navigable SignalK route with Ramer-Douglas-Peucker simplification. Adjustable detail slider shows point reduction preview before saving.
- **Historical Data Explorer — Default Dot Markers**: Points with no data for the active legend path now show as small grey dots instead of being hidden.
- **Diagnostic Service — Widget Inventory**: Diagnostic snapshots now include the active tool types on the current dashboard for correlating widget configurations with resource usage.
- **Server Switch — Clean Startup**: Switching servers now navigates through the splash screen for a clean connection lifecycle, ensuring all widgets initialize with fresh data.

### Changed
- **Autopilot V2 API — `units: "deg"` for Heading Commands**: Heading values sent with `units: "deg"` field, matching Kip/FreeboardSK convention. Eliminates fragile radian round-trip conversions.
- **Autopilot V2 API — `/state` not `/mode`**: Mode changes use the `/state` endpoint (auto, wind, route, standby) which is what the server actually supports.
- **httpBaseUrl — Single Source of Truth**: Added `httpBaseUrl` getter to SignalKService. Autopilot, dodge service, and other REST callers use it instead of scattered protocol/URL construction.

### Fixed
- **Alert Message Accumulation**: CPA and anchor alerts now use stable deterministic IDs (`alert-cpa-{vesselId}`, `alert-anchor`, `alert-checkin`). Server PUT overwrites instead of creating new files.
- **Deleted Message Resurrection**: Tombstone set (`_deletedIds`) prevents deleted messages from being re-added via WS delta cache or server re-fetch. Cache eviction via `removeCachedValue()`.
- **Server-Side Message Cleanup**: `_pruneOldMessages()` now deletes expired messages from the SignalK server, not just locally. Alert messages pruned after 60 minutes.
- **Autopilot V2 Discovery Parsing**: Fixed instance parsing — server returns instances at top level, not nested under `autopilots` key.
- **Historical Data Service — Server Switch**: Service now detects server URL changes and reinitializes instead of querying the old server.

## [0.5.93+66] - 2026-03-20

### Changed
- **Crew Messaging — Real-Time Delivery via WebSocket**: Replaced 15-second polling with WebSocket push for crew messages. Messages now arrive within ~1 second instead of 0–15s. Resources API still used for persistence and startup hydration; WS deltas handle instant delivery. Path namespace changed from `messages.*` to `crew.messages.*` for consistency with crew status paths.

### Fixed
- **CPA Alert Service — setState() During Build**: CPA alert evaluations triggered `notifyListeners()` during widget build phase, causing Flutter "setState() or markNeedsBuild() called during build" errors. Replaced direct `notifyListeners()` with coalesced `Future.microtask()` that defers notification to after the synchronous call stack completes.

## [0.5.92+65] - 2026-03-20

### Fixed
- **Wakelock D-Bus Crash (Linux)**: `_onConnectionChanged()` fired on every `notifyListeners()` — not just connection state changes — causing hundreds of redundant `WakelockPlus.enable()`/`.disable()` and `foregroundService.start()`/`.stop()` calls per minute. On Linux, this exhausted the D-Bus pending replies limit and crashed the app. Added `_wasConnectedForServices` transition guard so wakelock and foreground service only fire on actual connect/disconnect transitions. Reduces unnecessary platform channel overhead on all platforms.
- **Dashboard Tools Not Updating**: Tool widgets (wind compass, text display, gauges, etc.) were cached via `_toolWidgetCache.putIfAbsent`, so `StatelessWidget.build()` was only called once — subsequent SignalK data updates never reached the widgets. Removed the widget instance cache; `_DeferredToolWidget` and `_KeepAlivePage` already handle staggered mounting and page persistence.

## [0.5.91+64] - 2026-03-20

### Fixed
- **Crew Status — Cross-Device Sync**: Crew status changes (e.g., "On Watch") now propagate between devices logged into the same account. Previously, polling skipped the user's own resource, so remote status changes were never read. Heartbeat timer offset by 15 seconds from poll to prevent stale local data overwriting newer server state.

## [0.5.90+63] - 2026-03-20

### Added
- **System Monitor — SignalK Connection Health**: Tracks connection state with uptime counter; shows DiagnosticService metrics (cache sizes, subscription counts, WS message rates)
- **System Monitor — App Memory Y-Axis**: Dual Y-axis on the memory chart — left axis for system memory, right axis for app memory with improved label styling
- **AIS Favorites — Server Sync**: Favorites now sync across devices via SignalK Resources API (`zeddisplay-favorites` resource type)
  - `lastModifiedAt` field on AISFavorite for conflict resolution (last-write-wins)
  - Background polling (60s) pulls remote changes; mutations push immediately
  - Works alongside existing local persistence — offline edits sync on reconnect
- **Version Display**: Settings screen shows app version and build number via `package_info_plus`
- **Historical Data Explorer — Days-Back Mode**: New "lookback" time mode with quick presets (1d, 3d, 7d, 14d, 30d) as an alternative to the date range picker
- **Saved Search Areas — Explicit Draw Points**: `SavedSearchArea` model now stores explicit draw points for more precise area recreation

### Changed
- **SignalK Service — Earlier Vessel Context**: Vessel identity (`_vesselContext`, `_selfMMSI`) is now resolved before `notifyListeners()` during connect, so listeners that trigger subscriptions or process cached deltas see correct vessel routing from the start
- **Historical Line Chart — Local Time**: Date range labels and chart X-axis data points now display in local time instead of UTC
- **Text Display — String Value Support**: Text display tool now correctly renders string values (e.g., vessel name, state text) as-is, instead of attempting numeric conversion; layout wrapped in `SingleChildScrollView` to prevent overflow
- **Dashboard Manager — Screen Selector**: Simplified screen selector dots with tap-to-reveal/tap-to-open behavior replacing the previous multi-layer animated opacity approach; screen management actions row now horizontally scrollable on narrow screens
- **DiagnosticService — Public Getters**: Added public getters for improved data access by System Monitor tool

### Removed
- **Windsteer Gauge — Unregistered**: Windsteer and Windsteer Demo tools removed from tool registry. Early prototype (Oct 2025) fully superseded by Wind Compass tool. Files kept with deprecation headers for reference.

### Infrastructure
- **macOS TestFlight Pipeline**: Complete overhaul of macOS release workflow for App Store Connect
  - Installer certificate (`.p12`) imported alongside app signing certificate
  - Apple WWDR intermediate CA imported for full certificate trust chain
  - Provisioning profile saved with UUID filename (required by Xcode)
  - TestFlight upload via `xcrun altool` replacing `apple-actions/upload-testflight-build`
  - Diagnostic steps for signing identities, profile details, and archive bundle ID
  - Bundle identifiers aligned across project and workflow
  - `LSApplicationCategoryType` added to macOS Info.plist
- **CI/CD — Manual Triggers**: All release workflows (Android, iOS, Linux, macOS, Windows) now support `workflow_dispatch` for manual execution from GitHub Actions UI

## [0.5.86+55] - 2026-03-19

### Added
- **Historical Chart — Vessel Context**: Historical charts can now query data for specific vessel contexts (own vessel or AIS targets), with data sources grouped by context for streamlined API calls
- **Historical Chart — Context in Path Selector**: Path selector dialog prioritizes favorited historical contexts and shows improved layout for context selection
- **CPA Alert Integration**: CPA alert service now integrated with AIS polar chart tool, with display state management for alert visibility
- **TTL Data Freshness**: All gauge and display tools now support TTL (time-to-live) checks — stale data is visually indicated instead of silently showing outdated values
- **Edit Mode — Tool Info Button**: Blue info button added to the edit mode overlay toolbar (next to gear icon) for quick access to tool documentation without leaving the dashboard

### Changed
- **Widget Empty States**: All 42 tool widgets now use a unified `WidgetEmptyState` component for "no data source configured" and "no connection" messages, replacing inconsistent per-widget message styles
- **Tool Info Button Relocated**: Info button removed from all 42 tool widget overlays (was obscuring content) and moved to the edit mode toolbar
- **Historical Data Explorer — Default Selection**: Detail tab now auto-selects the first data point after a query completes, instead of showing "Tap a point on the map or list"
- **Historical Chart — Series Visibility**: Refactored series visibility handling in historical and real-time charts for more reliable state management and rendering
- **Historical Chart — Legend Colors**: Improved legend series index mapping and color assignment for multi-series charts
- **Path Selector Dialog**: Available paths endpoint now supports optional context and date range filters for more relevant path listings

### Fixed
- **RPi Monitor**: Fixed tool never receiving WebSocket data — was missing subscription to `environment.rpi.*` paths due to `subscribe=none` configuration
- **Historical Chart — Connection Handling**: Improved connection state handling and UI messages when server is disconnected

## [0.5.80+53] - 2026-03-18

### Added
- **AIS Vessel Data Resolution**: Tool widgets can now display data from AIS vessels, not just self
  - `DataSource.resolve()` method transparently handles vessel context — tools call one method for both self and AIS data
  - `DataSource.isFresh()` method for TTL checks with vessel-aware resolution
  - Flat cache lookup with automatic fallback to AIS vessel registry (REST data available before WS deltas arrive)
  - Supported tools: Radial Gauge, Linear Gauge, Compass Gauge, Text Display, Position Display, Real-Time Chart
- **Edit Dialog — AIS Vessel Context**: Editing a data source now shows vessel context and allows changing vessel selection
  - Vessel name/MMSI displayed below path when an AIS vessel is selected
  - Path selector opens with current vessel pre-selected via `initialVesselContext`
  - Source selector passes vessel context for correct REST lookups
- **PathSelectorDialog — `initialVesselContext`**: Pre-selects the vessel in the context picker when editing an existing AIS data source
- **SourceSelectorDialog — `vesselContext`**: Passes vessel ID to `getSourcesForPath()` for correct REST endpoint
- **`getSourcesForPath()` — `vesselId` parameter**: REST source lookup uses the specified vessel instead of always using self

### Changed
- **Tool Data Resolution**: All AIS-aware tools now use `DataSource.resolve()` instead of direct `signalKService.getValue(path)` calls
  - `base_tool.dart`: `getDataPoint()` uses `dataSource.resolve()`
  - `radial_gauge_tool.dart`: `_getRawValue()` takes `DataSource` instead of `String path`
  - `linear_gauge_tool.dart`: `_getRawValue()` takes `DataSource`, TTL uses `dataSource.isFresh()`
  - `compass_gauge_tool.dart`: `_getRawValue()` takes `DataSource`, multi-needle loop updated
  - `text_display_tool.dart`: Data point lookup uses `dataSource.resolve()`
  - `position_display_tool.dart`: Uses `_primaryDataSource` getter with `resolve()` fallback to default path
  - `realtime_spline_chart.dart`: Timer-driven data sampling uses `dataSource.resolve()`
- **Non-AIS tools unchanged**: Windsteer, autopilot, charts, weather, etc. continue calling `getValue(path)` directly

### Infrastructure (0.5.72–0.5.75)
- **CI/CD — Linux Builds**: GitHub Actions workflow for Linux x64 and arm64 (RPi5) with install script
- **CI/CD — macOS Builds**: Workflow with Xcode setup, entitlements (location, microphone), TestFlight upload, and install script
- **CI/CD — Windows Builds**: GitHub Actions workflow for Windows x64 releases
- **CI/CD — Platform Tag Filters**: All release workflows support platform-specific tags (e.g., `v*-linux`)
- **macOS Entitlements**: Location and microphone access for macOS builds
- **Custom Scroll Behavior**: MaterialApp configured for enhanced touch and pointer support
- **GitHub Actions**: Updated to latest action versions across all workflows

## [0.5.71+48] - 2026-03-17

### Added
- **CI/CD — Linux Builds**: GitHub Actions workflow for Linux x64 and arm64 (RPi5) releases
- **CI/CD — Windows Builds**: GitHub Actions workflow for Windows x64 releases
- **CI/CD — macOS Builds**: GitHub Actions workflow for macOS releases

### Changed
- **CI/CD — Platform Tag Filters**: All release workflows now support platform-specific tags (e.g., `v*-linux`, `v*-windows`, `v*-macos`) and skip unrelated builds

### Fixed
- **Build Warnings**: Cleaned up all `flutter analyze` warnings — removed unused methods, redundant null assertions, and minor style issues

## [0.5.70+47] - 2026-03-17

### Added
- **Historical Data Explorer — Timeline Playback**: Transport bar on the Detail tab plays through query results automatically
  - Play/pause, forward/reverse, and jump ±10 point buttons
  - Adjustable speed (1x, 2x, 5x, 10x) via popup menu
  - Slider scrubs to any position in the result set
  - Sparkline markers, map position, and summary update in sync
  - Auto-stops at boundaries; hidden for single-point results
- **Chart Configurator — 1-Week Duration**: Added 1-week option to chart time range selector with enhanced data range labels
- **Chart Configurator — Vessel Context**: Select vessel context (own vessel or AIS targets) for historical data queries
- **Real-Time Spline Chart — Zooming**: Pinch-to-zoom on live spline charts with cached data for smooth interaction

### Changed
- **Dashboard Manager — Swipe-Up Screen Selector**: Refactored screen layout to reveal screen selector dots via swipe-up gesture instead of always-visible dots
- **Dashboard Layouts — Allowed Orientations**: Dashboard layouts and setups now store allowed orientations per screen with update support
- **Historical Line Chart**: Improved initial zoom factor for better default view
- **Dashboard Manager**: Tool widgets removed from cache on update to prevent stale state

### Removed
- **Real-Time Spline Chart**: Removed moving average data handling (simplified chart rendering)

## [0.5.63+46] - 2026-03-16

### Added
- **Historical Data Explorer**: New spatial/temporal query tool for signalk-parquet historical data
  - Interactive map with bbox and radius area selection via draw-to-select or drag-to-resize handles
  - Query multiple SignalK paths with configurable aggregation (average, min, max) and smoothing (SMA/EMA)
  - Color-coded result markers on the map with value-proportional sizing (12–28px scaled to data range)
  - Markers filtered by active legend — points with no data for the selected path are hidden
  - Per-point detail view with sparkline charts for each queried path, showing date range and min/max
  - Double-tap any sparkline to open an expanded chart modal with full date range and point count
  - Save/reload named search areas; share results as CSV or JSON
  - Map/Detail/Table tab views with swipe navigation
  - Zoom in/out buttons, zoom-to-fit area (handles both bbox and radius geometry), homeport and recenter buttons
  - State cached across screen switches, reconnects, and page swipes via `KeepAlivePage`
  - Requires signalk-parquet plugin with spatial query support (bbox, radius parameters)
- **On-Demand Path Metadata Fetch**: `fetchPathMeta()` retrieves metadata from `/signalk/v1/api/vessels/{vesselURN}/{path}/meta` when MetadataStore has no entry for a path
  - Works for own vessel and AIS targets via optional vesselId parameter
  - Results cached in MetadataStore and persisted to local storage
  - Historical Data Explorer automatically fetches metadata before building series
- **MetadataStore Category Fallback**: `get()` now falls back to category-level metadata (e.g., temperature, speed) when no path-specific entry exists
  - Resolves missing conversions for paths like `environment.outside.tempest.observations.airTemperature`
  - Category lookup wired at startup (cache restore) and after REST preset load
- **Widget Caching**: `KeepAlivePage` wrapper in Dashboard Manager preserves tool widget state across page swipes
  - Tools no longer rebuild when swiping between dashboard pages
  - Reduces unnecessary network requests and improves perceived performance

### Changed
- **Tool Config Screen Flags**: New schema flags to disable data source editing, unit selection, visibility toggles, and TTL settings per tool
  - `disableDataSources`, `disableUnitSelection`, `disableVisibilityToggles`, `disableTtl` flags
  - ConfigSchema Flags Guide added to developer documentation
- **Reconnection Logic**: Exponential backoff for reconnection attempts with background probing
  - Reconnect status displayed in connection overlay
  - Background probe detects server availability without full reconnect cycle

## [0.5.62+45] - 2026-03-14

### Added
- **Wind Compass Slot Definitions**: Fixed-slot configuration for wind compass data sources
  - 10 named slots (Heading True/Magnetic, Wind Direction/Angle/Speed, SOG, COG, Waypoint Bearing/Distance) replace free-form add/delete
  - Slot mode prevents accidental index corruption from add/delete operations
  - Clear button for optional slots; path editing via PathSelectorDialog
- **Path Editing in Data Source Dialog**: All tools can now change the SignalK path of an existing data source (not just source and label)
- **Dodge Autopilot Service**: Pre-dodge state management saves and restores autopilot heading; completion checks auto-disengage dodge mode
- **Raymarine Settings UI**: Hull type selector and auto-turn speed configuration in autopilot settings

### Changed
- **Tool Config Screen**: Slot-mode tools hide Add/Delete buttons and Custom Label field; role labels shown as list item titles
- **Wind Compass Defaults**: Removed redundant DataSource labels (slot roleLabel provides the display name)

## [0.5.60+42] - 2026-03-12

### Added
- **Find Home — Dodge Mode**: Intercept-geometry course guidance for passing safely behind (or ahead of) a moving AIS vessel
  - `DodgeUtils` calculates course-to-steer using quadratic intercept solution with configurable safe distance (default 300 m)
  - Stern pass (default) or bow pass toggle — bow pass includes safety checks (t > 60 s, course change < 90°)
  - Runway painter shows target vessel chevron at apex, color-coded track lines, and BOW/STERN labels
  - Haptic and audio feedback steers to dodge course instead of bearing-to-target
  - DODGE button appears automatically when AIS target has COG/SOG (is moving)
  - Configurable `dodgeDistance` in tool config (stored in SI meters)
- **Sun/Moon Arc Tool**: New celestial display showing sun and moon arc paths with rise/set times, current positions, and twilight phases
  - Date/time formatting utility for localized display
  - Excluded from data source and options configurators (self-contained tool)
- **5 Themed Dashboard Layouts**: Pre-built dashboards covering all 39 widget types
  - **Sailing**: Wind instruments, polar charts, autopilot, attitude indicator, realtime charts
  - **Weather Station**: Forecast spinners, weather alerts, sun/moon arc, environmental gauges
  - **Passage**: Navigation, AIS, anchor watch, GNSS status, autopilot simple
  - **Boat Systems**: Power flow, tanks, RPi monitor, server management, webview, diagnostics
  - **Controls**: Knob, slider, switch, checkbox, dropdown, gauges, text displays
- **Bundled Dashboard Assets**: Default dashboard now ships with the app for first-time setup
- **Widget Creation Guide**: Comprehensive developer documentation for creating new dashboard tools

### Changed
- **AIS Polar Chart**: Added vessel lookup service configuration for enhanced vessel identification
- **AIS Data Handling**: Max range filtering to improve performance with distant vessels
- **Admin Menu**: Sync bundled setups button changed from PopupMenuButton to IconButton for cleaner UI
- **Dashboard Loading**: Optimized to avoid redundant setup service retrieval

### Fixed
- **Expression Evaluation**: Refactored ConversionUtils to use GrammarParser and ContextModel for more reliable formula parsing
- **CPA Alert Service**: Refactored evaluation logic for consistency; AIS Polar Chart labels updated to use const for performance

## [0.5.51+41] - 2026-03-12

### Added
- **Find Home — AIS Vessel Targeting**: Select any AIS vessel as the Find Home target directly from the AIS Tracker vessel detail sheet
  - FindHomeTargetService bridges AIS Tracker → Find Home via a one-shot ChangeNotifier signal
  - Find Home persists the selected vessel ID and name across widget rebuilds
  - Real-time position tracking of the targeted AIS vessel as home destination
  - Find Home configurator shows active AIS target with clear button
- **Find Home — Track Mode Waiting State**: Track mode now shows "Waiting for vessel position..." with a sailing icon instead of the misleading "Acquiring device GPS..." message
- **Diagnostics Feature Toggle**: Diagnostics can now be enabled/disabled from Settings without restarting the app

### Fixed
- **Find Home — GPS Acquisition Hang**: After screen switch, widget could get stuck on "Acquiring device GPS..." because `getLastKnownPosition()` returned null and the stream hadn't started yet. Now falls back to `getCurrentPosition()` to eliminate the async gap
- **Find Home — Wrong Waiting State in Track Mode**: Track mode doesn't use device GPS, so showing "Acquiring GPS" was incorrect. Now displays the appropriate waiting message per mode
- **Find Home — AIS Target Name Visibility**: When waiting for GPS in AIS mode, the selected vessel name is now shown so the user knows their selection wasn't lost

### Changed
- **Compass Gauge**: Removed 'arc' style option from CompassGauge and related configurator
- **Tool Config Screen**: Renamed 'Add Data Source' button label to 'Add Path' for clarity
- **AIS Tracker / Find Home Info**: Updated tool_info.yaml with cross-widget integration notes and hardware requirements (AIS receiver)

## [0.5.50+40] - 2026-03-11

### Added
- **AIS Vessel Favorites**: Mark vessels of interest and get notified when they appear in AIS range
  - Heart icon on each vessel in the Nearby list to toggle favorite
  - Favorites tab in the vessel list overlay (Nearby | Favorites) with live distance/SOG for in-range vessels
  - Manual add dialog for vessels not currently visible (MMSI + name + notes)
  - Detection snackbar with "VIEW" action to jump to vessel on chart — fires once per encounter, resets when vessel leaves range
  - Service-layer detection via AlertCoordinator — works even when AIS chart is off-screen or app is backgrounded
  - Favorites persisted locally via StorageService
- **Find Home Tool**: Navigate back to a saved home position using device GPS
  - Haptic feedback (configurable vibration patterns) with wrong-way detection
  - Audio alert sound selection (bell, foghorn, chimes)
  - Configurable feedback intervals
  - Distance display with proper unit formatting via MetadataStore
- **AlertCoordinator**: Centralized alert delivery gateway for all subsystems
  - Subsystems keep domain logic, delegate delivery to coordinator
  - Enforces master toggle, per-level filters, and per-subsystem crew broadcast preferences
  - Severity-based audio preemption (only one audio at a time, higher severity wins)
  - Overlay suppression — snackbars suppressed when subsystem has an overlay visible
  - Snackbar delivery deferred while app is backgrounded to prevent jank on resume
- **Notification Navigation**: Tap-to-navigate from system notifications to relevant tools
- **Mooring Buoy Icon**: New SVG icon for mooring buoy AIS vessel type

### Enhanced
- **Reconnection Logic**: Lightweight reconnect preserves cached data (MetadataStore, subscriptions, vessel registry) during short dropouts instead of full teardown/rebuild
- **App Lifecycle Hardening**: Background/resume stability improvements — AlertCoordinator tracks foreground state, diagnostic service pauses/resumes with lifecycle
- **Anchor Alarm**: Control locking mechanism prevents accidental changes; alarm sound stops on notification tap/dismiss; proper check-in alert acknowledgment
- **AIS Polar Chart**: Auto-highlight newly alerted CPA vessels; improved CPA/TCPA display logic
- **Historical Line Chart**: 3-state series visibility (visible, hidden, muted) with improved legend item rendering
- **Crew Notifications**: Per-subsystem crew broadcast toggles in settings; message deletion support
- **Diagnostics**: Cache size metrics for MetadataStore, subscription registry, and vessel registry; app version tracking via package_info_plus
- **iOS Configuration**: Updated AppDelegate for implicit engine support; scene manifest in Info.plist; AnchorAlarmService disposal checks

### Fixed
- **Anchor Alarm Notifications**: Tap handling now properly acknowledges alerts and silences alarms for non-check-in notifications
- **Default Categories**: Refactored default categories handling in SignalK service for more reliable unit conversion fallbacks

## [0.5.42+39] - 2026-03-08

### Added
- **SignalK Architecture Overhaul**: Major rewrite of SignalK service internals for reliability and efficiency
  - **Single WebSocket**: Removed separate autopilot WebSocket channel; all data (navigation, autopilot, notifications) routes through one connection
  - **Path Subscription Registry**: New `PathSubscriptionRegistry` with owner-tracked subscriptions (dashboard, autopilot, anchor_alarm, weather_alerts, weather_spinner, notifications)
  - **Vessel Identity**: Subscriptions and REST calls now use vessel MMSI/URN via `_vesselContext` / `_vesselRestPath` instead of hardcoded `vessels.self`
  - **Path Discovery**: `_availablePaths` populated from `GET /skServer/availablePaths`, refreshed every 5 minutes
  - **MetadataStore via REST**: `populateFromPreset()` fills MetadataStore from REST unit preferences on connect; WebSocket meta deltas kept for runtime overrides
  - **Auth Guard**: WebSocket subscriptions blocked without valid auth token (no more wildcard `*` subscriptions leaking)
  - **Cache Dedup**: Own-vessel paths stored once in cache (not 3x per source); source label stored on `SignalKDataPoint.source` field
- **NWS Weather Alert Filtering**: Weather notifications only shown when a weather_alerts widget is on the active dashboard; expired/inactive alerts suppressed
- **Diagnostic Service**: Memory leak investigation tooling with periodic logging of cache sizes, subscription counts, and WebSocket message rates

### Fixed
- **Notification Spam**: Eliminated duplicate notifications from SignalK server
  - System (OS) notifications now use stable IDs per notification key — same alert replaces instead of stacking
  - Anchor alarm notifications use stable IDs per alarm type — state oscillations (alarm→normal→alarm) replace instead of stacking
  - Added 30-second temporal throttle for same key+state combinations to catch reconnect-induced re-sends
- **Dashboard Subscription Sync**: Dashboard service now updates SignalK subscriptions when layout changes, ensuring paths are added/removed as widgets are added/removed

### Enhanced
- **Subscription Management**: `subscribeToPaths()` / `unsubscribeFromPaths()` now accept owner IDs, enabling precise lifecycle management — when a widget is removed, only its paths are unsubscribed (shared paths with other owners remain)

## [0.5.41+38] - 2026-03-08

### Fixed
- **iOS Notifications**: Fixed local notifications not being delivered on iOS
  - Added `UNUserNotificationCenter` delegate assignment in AppDelegate (required for iOS 10+)
  - Added foreground lifecycle handlers to prevent white screen after notification-triggered background wake
  - Matches working implementation from sister app ZedDisplay-OpenMeteo

## [0.5.40+37] - 2026-03-08

### Added
- **CPA Alert System**: Configurable Closest Point of Approach alerts for AIS collision avoidance
  - CPA distance and TCPA time threshold sliders with persistence
  - Enabled by default with sensible defaults
  - Integrated into AIS Polar Chart tool configuration
  - CPA calculation utility functions for bearing/distance math
- **AIS Vessel Registry**: Dedicated AISVessel model and AISVesselRegistry service for structured vessel management
- **Compass Gauge Configurator**: New dedicated configurator with path filtering for compass-specific SignalK paths
- **Hide Stale Vessels**: AIS Polar Chart option to hide vessels with outdated data

### Enhanced
- **AIS Polar Chart**: Improved controls layout, stale vessel filtering, and MetadataStore-based unit conversions
- **Dashboard Performance**: Deferred heavy widget construction in dashboard and tool configuration screens
- **Zone Fetch Performance**: Deduplicated zone fetch requests in ZonesCacheService; deferred HTTP requests in ZonesMixin
- **Connection Stability**: Prevented multiple simultaneous connection attempts in SignalKService
- **Historical Data Parsing**: Improved resource management and data parsing in services
- **Tool Configuration**: Tools now store their own toolId in customProperties for self-reference; improved save logic

### Dependencies
- **Major dependency upgrade**: 54 packages updated (minor/patch)
  - Syncfusion Flutter packages 32.1.19 → 32.2.8
  - audioplayers 6.5.1 → 6.6.0, file_picker 10.3.7 → 10.3.10
  - flutter_foreground_task 9.1.0 → 9.2.1, video_player 2.10.1 → 2.11.0
  - json_annotation 4.9.0 → 4.11.0, json_serializable 6.11.3 → 6.13.0
  - build_runner 2.10.4 → 2.12.2
  - flutter_webrtc 1.2.1 → 1.3.0
- **flutter_local_notifications**: 19.5.0 → 21.0.0 (major version upgrade)
  - Migrated all API calls to named parameters (initialize, show, cancel)
- **iOS Deployment Target**: Aligned project.pbxproj to 16.0 (matching Podfile)

### Fixed
- **Code Consistency**: Cleanup pass on comments, widget styles, and variable initializations

## [0.5.28+35] - 2026-03-06

### Added
- **Tool Info Buttons**: Added info buttons across tools (forecast spinner, attitude indicator, intercom, crew list, and more) for in-app help

### Enhanced
- **AIS Polar Chart**: Color vessels by ship type and show projected positions
- **AIS Vessel Details**: Interactive highlights with AIS status display; non-blocking overlay rises from bottom of entire widget, covering vessel list in all layouts
- **Autopilot Mode Selector**: Refactored to use DraggableScrollableSheet for improved usability
- **Autopilot Tool Config**: Updated excluded options for cleaner configuration screen
- **Compass Gauge**: Refactored to StatefulWidget with improved state management and color generation
- **Wind Compass**: Separated AWA display logic with improved layout
- **Tool Info Buttons**: Reduced background opacity and adjusted layout for improved visibility

### Fixed
- **AIS Polar Chart**: Tapping a vessel no longer forces map mode — details shown without switching view
- **AIS Vessel Details**: Overlay now covers full widget area in stacked and side-by-side layouts

## [0.5.27+35] - 2026-03-05

### Added
- **Chart Smoothing Configuration**: Historical chart configurator now supports smoothing type selection
  - Choose between SMA (Simple Moving Average) or EMA (Exponential Moving Average)
  - Dynamic window parameter: integer for SMA (e.g., 5, 10, 20), decimal alpha for EMA (e.g., 0.1, 0.3)
  - Smoothed series automatically paired with raw data series

### Enhanced
- **Historical Chart Styling**: Smoothed series now match realtime chart styling
  - Same color as parent series with 60% opacity
  - Dashed line pattern `[5, 5]` matching realtime chart
  - Hidden from legend (reduces clutter)
  - Legend tap toggles both raw and smoothed series together
- **Dual Y-Axis Support**: Charts now support dual Y-axes when data sources have different base units
  - Automatic axis assignment based on unit categories (e.g., speed vs temperature)
  - Secondary axis displayed on right side with dashed grid lines
- **Duration Formatting**: Chart X-axis labels adapt to duration
  - Short durations (15m-2h): Show time with minutes (10:30 AM)
  - Medium durations (6h-1d): Show hour only (10 AM)
  - Long durations (2d): Show day and hour (Mon 10 AM)

### Fixed
- **EMA Smoothing**: Fixed type error when using EMA with decimal alpha values (e.g., 0.1)
  - Changed `window` field from `int?` to `num?` to support both SMA (integer) and EMA (decimal)
- **History API**: Removed invalid `convertUnits` parameter from API requests

## [0.5.26+35] - 2026-02-26

### Added
- **Server Manager Webapp Icons**: Webapps now display their icons in the Server Manager list
- **In-App Webapp Browser**: Tapping a webapp opens it in a built-in WebView instead of external browser
  - Authentication token automatically passed via cookie for seamless login
  - Shows webapp display name in app bar
  - Includes loading indicator and refresh button

### Fixed
- **Debug Logging**: Removed verbose unit conversion debug prints from console output

## [0.5.25+34] - 2026-02-24

### Added
- **Channel Subscriptions**: Users can now subscribe/unsubscribe from intercom audio channels
  - Toggle channel subscriptions in the Crew List (icons shown next to each crew member)
  - Emergency channel (CH16) is always subscribed - cannot be disabled
  - Captains and First Mates can manage any crew member's subscriptions
  - Regular crew can only manage their own subscriptions
  - Subscriptions persist across app restarts
  - Admins can also manage subscriptions via User Management Tool

### Changed
- **Default Tool Size**: New tools now default to full grid size (8x8) for simpler placement
- **Direct Tool Placement**: Tools without required configuration can now be placed directly without opening config dialog first

## [0.5.24+33] - 2026-02-24

### Changed
- **Anchor Widget Responsive Layout**: Redesigned anchor alarm widget with adaptive layout
  - Wide mode (≥600px): Map and controls side-by-side (50%/50% split)
  - Narrow mode (<600px): Map and controls stacked vertically (50%/50% split)
  - Controls no longer overlay the map - they share space properly
  - Added SingleChildScrollView to control panel for overflow handling
  - View controls positioned appropriately for each layout mode

## [0.5.23+32] - 2026-02-24

### Fixed
- **Anchor Widget Unit Display**: Fixed unit conversion for anchor alarm paths (maxRadius, currentRadius, rodeLength)
  - Anchor-alarm plugin sends `displayUnits: {category: "length", explicit: true}` without formula
  - Added `getConversionForCategory()` to look up conversion from category directly
  - Handles identity conversion (m→m) when user's preferred unit matches SI unit
  - Values now display with proper unit symbols (e.g., "29 m" instead of "29.0")

## [0.5.22+31] - 2026-02-24

### Fixed
- **iOS App Icons**: Enabled iOS icon generation to match Android branded icons
  - Updated `flutter_launcher_icons` config: `ios: false` → `ios: true`
  - Added `remove_alpha_ios: true` for App Store compliance (no transparency)
  - Generated all 22 iOS icon sizes in AppIcon.appiconset

## [0.5.21+30] - 2026-02-24

### Fixed
- **Server Load Reduction**: Reduced aggressive polling that was causing SignalK server issues
  - MessagingService: Increased poll interval from 5s to 15s (67% reduction)
  - CrewService: Increased poll interval from 15s to 30s (50% reduction)
  - UserManagementTool: Increased poll interval from 10s to 30s
  - DeviceAccessManagerTool: Increased poll interval from 10s to 30s
- **401 Auth Spam**: Admin tools (User Management, Device Access) now skip polling when no valid auth token
  - Prevents thousands of failed requests per day to security endpoints
  - Tools still render but won't spam server with unauthorized requests
- **Connection Lost Overlay**: Prevented "Connection Lost" overlay from flashing during reconnect attempts
  - Overlay now only shows after connection is truly lost, not during brief reconnection cycles

### Changed
- **Code Cleanup**: Removed debug print statements from various services and utilities

## [0.5.20+29] - 2026-02-23

### Fixed
- **Crew Presence Detection**: Fixed bug where crew members appeared offline even when connected
  - Presence was stored using URL-encoded resource ID (e.g., `user%3Arima`) but looked up by canonical ID (`user:rima`)
  - Now uses canonical ID consistently for both storage and lookup
  - Crew members should correctly show as online when connected to the same SignalK server

### Added
- **iOS Background Audio**: Added `UIBackgroundModes` for voice intercom
  - `audio` mode allows audio playback when app is backgrounded
  - `voip` mode keeps voice calls alive when switching apps or locking screen

## [Unreleased]

### Added
- **GitHub Actions CI/CD**: Automated app store deployment workflows
  - `release.yml` - Android build and Google Play upload (internal track, draft)
  - `ios-release.yml` - iOS build and TestFlight upload
  - Triggered by git tags (`v*.*.*`, `v*.*.*-android`, `v*.*.*-ios`)
  - Retry logic for flaky Gradle downloads
  - Automatic GitHub Release creation with APK/AAB/IPA artifacts
- **Release Notes Templates**: Store-compliant release notes
  - `WHATSNEW.md` - Primary release notes (Google Play 500 char / App Store 4000 char sections)
  - `distribution/whatsnew/` - Auto-extracted Google Play notes
- **iOS Export Configuration**: `ios/ExportOptions.plist` for App Store builds

### Changed
- **Autopilot Widget**: Responsive layout for wide screens
  - Wide layout (>=600px): Controls panel appears to the right of compass
  - Narrow layout (<600px): Controls stacked below compass (existing behavior)
  - Extracted `_buildCompassArea()` and `_buildControlsPanel()` for cleaner code
- **iOS Deployment Target**: Updated from iOS 13.0 to iOS 16.0
  - Podfile updated with dSYM generation for crash reporting
  - Enforced minimum deployment target across all pods

### Documentation
- **README.md**: Added missing tool documentation
  - Windsteer Gauge (B&G/Kip-style wind analysis)
  - User Management (SignalK user administration)
  - Device Access Manager (device permissions)
  - WebView (embedded web content)
  - Enhanced AIS Polar Chart description (dual views, CPA/TCPA, OpenSeaMap)
  - Enhanced Anchor Alarm description (vessel length, fudge factor, depth)
  - Updated Autopilot V2 with responsive layout info

## [0.5.6+23] - 2025-12-16

### Changed
- **Custom Resource Types**: Migrated from `notes` resource type to dedicated custom resource types
  - `zeddisplay-messages` for crew messaging
  - `zeddisplay-crew` for crew profiles and presence
  - `zeddisplay-files` for file sharing metadata
  - `zeddisplay-channels` for intercom channels
  - `zeddisplay-alarms` for shared alarms
  - **Privacy improvement**: Other apps reading `notes` will no longer see ZedDisplay data
  - **Auto-creation**: Resource types are automatically created on first connection via resources-provider plugin API
  - Requires authenticated connection with admin rights

### Fixed
- **Auth Token Storage**: Fixed issue where multiple connections to same IP address shared the same token
  - Tokens now stored by connection ID instead of server URL
  - Each connection maintains its own authentication state
- **Connection Deletion**: Deleting a connection now also removes its associated auth token

## [0.5.5+22] - 2025-12-16

### Added
- **Autopilot V2 Tool**: Redesigned circular autopilot with nested controls
  - Banana-shaped heading adjustment buttons (+1, -1, +10, -10) arced around inner circle
  - Mode selector (Compass, Wind, Route) with engage/standby toggle
  - Tack/Gybe banana buttons in Wind mode positioned by turn direction (port side = turn left, starboard = turn right)
  - Advance Waypoint banana button at top in Route mode
  - Dodge button in center circle for Route mode
  - Draggable target heading arrow with long-press activation
  - Incremental command queue with acknowledgment tracking (3-second timeout fallback)
  - Visual feedback with ghost marker and arc showing heading change during drag
  - Rudder indicator shown when space permits (not just portrait mode)
  - Responsive portrait/landscape layouts using LayoutBuilder
  - Buttons disabled/shadowed when autopilot not engaged
- **Crew Deletion**: Crew members can now be removed from the server
  - Captain can remove any crew member
  - Any user can remove themselves
  - "Delete My Profile" button in profile edit screen
  - Red trash icon for captains in crew list
  - Confirmation dialogs before deletion
  - Clears both server (SignalK Resources API) and local storage

### Fixed
- **Tool Configuration Screen**: Tool type selection and grid size now hidden when editing existing tools
  - Previously showed full tool list even when editing, causing confusion
  - Grid size selector also hidden during edit (size set during initial placement)
- **Connection/Registration Screens**: Fixed horizontal and vertical centering
  - Screens now properly centered on all device sizes
- **Deprecation Warnings**: Replaced all `.withOpacity()` calls with `.withValues(alpha:)`
  - Updated across server_manager_tool.dart and other files
- **Unused Code Cleanup**: Removed unused methods, fields, and imports
  - Removed `_buildProviderStatsSection`, `_buildPluginsSection`, `_buildWebappsSection` from server_manager_tool
  - Removed `_availableInstances`, `_v2Info` from autopilot_tool
  - Removed `_buildCrewList` from crew_list_tool
  - Removed `_buildMessagesList` from crew_messages_tool
  - Removed unused `dart:ui` import from victron_flow_tool
  - Fixed `must_call_super` warning in weather_api_service

### Dependencies
- Updated Syncfusion Flutter Gauges from 27.x to 28.x (major version)
- Minor package updates via `flutter pub upgrade`

### Technical
- Power Flow visualization now uses orthogonal routing for flow lines
- Flow lines replaced moving balls with meteor sprite animation

## [0.5.2+18] - 2025-12-15

### Added
- **Anchor Alarm Tool**: Comprehensive anchor watch with visual monitoring
  - Real-time map display showing anchor position, current position, and swing radius
  - One-tap "Drop Anchor" with rode length auto-calculated from GPS-from-bow distance + 10%
  - Configurable alarm radius with visual circle overlay on map
  - Rode length adjustment via slider (5-100m)
  - Real-time distance from anchor display
  - Alarm triggers when vessel exceeds set radius from anchor point
  - "Raise Anchor" button to clear and reset
  - Integrates with SignalK anchor alarm plugin
  - Dedicated configurator for all anchor alarm settings
- **Position Display Tool**: Current vessel position display
  - Latitude/longitude display with configurable format options
  - Large, readable display optimized for cockpit use
  - Dedicated configurator for position display settings
- **Power Flow Tool**: Visual power flow diagram with animated energy flows
  - Real-time visualization of power sources, battery, inverter, and loads
  - Animated flow lines with bright moving balls showing power direction
  - Flow speed indicates current/power level using logarithmic scale
  - Staggered ball animations so lines from same origin don't sync
  - **Fully customizable sources**: Add, remove, rename, reorder power sources
  - **Fully customizable loads**: Add, remove, rename, reorder power loads
  - Default sources: Shore, Solar, Alternator (easily add Generator, Wind, etc.)
  - Default loads: AC Loads, DC Loads (easily add specific circuits)
  - Icon picker with 14+ icons for each source/load
  - Drag-and-drop reordering in configurator
  - Name editor dialog opens automatically when adding new items
  - Battery section: SOC, voltage, current, power, time remaining, temperature
  - Inverter/charger state display
  - Configurable base color theme with full color picker
  - Each component has configurable SignalK paths for current, voltage, power, frequency, state

### Enhanced
- **Tool Configuration Screen**: Improved config merging for tool-specific configurators
  - Configurator style values (primaryColor, minValue, maxValue, etc.) now properly override defaults
  - Fixed issue where configurator's color picker selection wasn't being saved
- **Unit Field Exclusion**: Added anchor_alarm, position_display, and victron_flow to tools that hide the Unit field
  - Cleaner configuration UI for tools that don't need unit settings

### Technical
- Added new tool category: Electrical Tools
- Power Flow uses customProperties for flexible source/load configuration
- Logarithmic speed scaling for visible flow differences at all current levels
- Phase-offset animation system prevents synchronized ball movement

## [0.5.1+17] - 2025-12-14

### Added
- **Clock/Alarm Tool**: Smart clock with customizable faces and alarm management
  - 5 clock face styles using one_clock library: analog, digital, minimal, nautical, modern
  - Multiple alarm support with full CRUD (create, read, update, delete)
  - 5 alarm sound options: ding, fog horn, ship bell, whistle, chimes (local assets)
  - Alarms persist via SignalK resources API (notes with `zeddisplay-alarms` group)
  - Multi-device synchronization: alarms sync across all connected devices
  - Dual dismiss modes: "Dismiss Here" (local only) or "Dismiss All" (synced via SignalK)
  - 12h/24h time format toggle with AM/PM selector in alarm editor
  - Snooze options: 1, 5, 9, 15, 30 minutes
  - Long-press clock face to open alarm management panel
  - System notifications with action buttons (Snooze, Dismiss Here, Dismiss All)
  - Complementary color second hand (opposite hue on color wheel)

### Dependencies
- Added `one_clock: ^2.0.2` for clock face widgets
- Added `audioplayers: ^6.1.0` for alarm sound playback

## [0.5.0+16] - 2025-12-13

### Added
- **Tanks Tool**: New tool for displaying up to 5 tank levels
  - Visual tank level indicators with fill percentage
  - Color-coded tank types (diesel, freshWater, blackWater, wasteWater, liveWell, lubrication, ballast, gas)
  - Auto-detection of tank type from SignalK path
  - Optional capacity display
  - Custom labels per tank
- **Weather API Spinner Tool**: Generic weather forecast using SignalK Weather API
  - Works with any provider implementing `/signalk/v2/api/weather/forecasts/point`
  - Supports Meteoblue, Open-Meteo, WeatherFlow/Tempest, and other providers
  - Spinner-style hourly forecast display
  - Provider name displayed in header
  - Automatic unit conversions based on provider
- **Weather Icons**: Added new weather icons for enhanced forecast display
  - Lightning, moon phases, pressure, raindrop, thermometer icons
  - BAS Weather Icons integration
  - Meteoblue weather icons
- **Sun/Moon Times**: Tomorrow's sunrise, sunset, moonrise, and moonset times in WeatherFlow forecast
- **Long Description Support**: Weather API and dashboard layout now support detailed descriptions

### Enhanced
- **Control Tools Source Selection**: Control tools (slider, knob, dropdown, switch, checkbox) can now display values from specific SignalK sources
  - Configure a data source to read from a specific source (e.g., "whatif-helper")
  - Useful for displaying values from specific sensors or plugins
- **PUT Request Inverse Conversion**: Control tools now properly convert display values back to raw SI values
  - Uses inverse formulas from SignalK unit conversion system
  - Example: Display shows 70%, PUT sends 0.70 (raw ratio)
  - Fixes issue where converted values were being sent directly
- **Forecast Provider Display**: Weather forecast tools now show the data provider name

### Fixed
- **Control Tool PUT Values**: Fixed issue where slider/knob/dropdown sent display values instead of raw values
  - Added `convertToRaw()` method using inverse formulas
  - All numeric control tools now send correct SI values
- **Source Parameter in PUT**: Removed incorrect source parameter from PUT requests
  - SignalK source field identifies the sender, not the target
  - Control tools now write as the app's source identity

### Technical
- **Device ID Source Identification**: SignalK service includes device ID for write source identification
- **Linux Compatibility**: Updated IntercomService and NotificationService for Linux platform support
- **Conversion Utilities**: Added `convertToRaw()` for inverse unit conversions

## [0.4.7+15] - 2025-12-07

### Added
- **Intercom Activity Notifications**: Get notified when crew members transmit on intercom channels
  - Tap notification to open intercom screen on that channel
  - Emergency channel notifications highlighted in red
  - Works even when not actively monitoring the channel
- **Dashboard Sharing via Crew File Share**: Share dashboards directly with crew
  - "Share with Crew" option added to dashboard share menu
  - Crew members can import shared dashboards with one tap
  - Import dialog with "Import Only" or "Import & Switch" options
- **Forward Cabin Intercom Channel**: Added new default channel for forward cabin communication

### Changed
- **Intercom Channel Renaming**: Updated default channels for typical boat layout
  - Bridge → Helm (command and navigation)
  - Deck → Salon (main living area)
  - Engine → Aft Cabin (aft cabin)
  - Added Forward Cabin channel

### Fixed
- **Shared File Data Embedding**: Fixed bug where small embedded files weren't downloading
  - `toNoteResource()` was incorrectly stripping data from all files
  - Now only removes embedded data when `downloadUrl` is present (large files)
  - Small files (< 100KB) now properly include base64 data in SignalK resources

### Dependencies
- **Major Updates**: Upgraded key dependencies to latest versions
  - `flutter_webrtc`: 0.12.12 → 1.2.1 (major WebRTC improvements)
  - `device_info_plus`: 11.x → 12.3.0
  - `permission_handler`: 11.x → 12.0.1
  - `battery_plus`: 6.2.1 → 7.0.0
  - `flutter_foreground_task`: 8.17.0 → 9.1.0
- **Minor Updates**:
  - `flutter_local_notifications`: 19.2.1 → 19.5.0
  - `webview_flutter`: 4.10.0 → 4.11.2
  - `file_picker`: 10.1.4 → 10.3.7
  - `flutter_map`: 8.0.3 → 8.2.2
  - `video_player`: 2.9.5 → 2.10.1

## [0.4.0+9] - 2025-10-29

### Major Code Refactoring & Cleanup
- **Comprehensive Code Review**: Completed major cleanup reducing codebase by ~5,000 lines (14%)
  - Eliminated 2,765 lines of dead code (_old.dart files)
  - Removed 1,349 lines of deprecated template system
  - Refactored tool_config_screen.dart from 2,170 lines to 1,300 lines (40% reduction)
  - Cleaned up 138 lines from dashboard_manager_screen.dart
  - Achieved 0 errors, 0 warnings compilation status

### Architecture Improvements
- **SignalK Service Refactoring**: Split monolithic service into organized managers
  - Created `_DataCacheManager` with TTL-based cache pruning (fixes unbounded memory growth)
  - Created `_ConversionManager` for unit conversion handling
  - Created `_NotificationManager` for notification processing
  - Created `_AISManager` for AIS vessel tracking with automatic stale data pruning
  - Service now 2,057 lines, well-organized with clear separation of concerns
  - Added cache invalidation callbacks for proper view updates

- **Tool Configuration System Refactoring**: Implemented Strategy pattern for tool-specific configuration
  - Created `BaseToolConfigurator` abstract class (36 lines)
  - Created `ToolConfiguratorFactory` for configurator instantiation (85 lines)
  - Implemented 7 specialized configurators totaling 1,482 lines:
    - `ChartConfigurator` for historical_chart and realtime_chart (290 lines)
    - `GaugeConfigurator` for radial_gauge and linear_gauge (207 lines)
    - `CompassConfigurator` for wind_compass and autopilot (269 lines)
    - `PolarChartConfigurator` for polar_radar_chart and ais_polar_chart (187 lines)
    - `ControlConfigurator` for slider, knob, dropdown, switch, button (168 lines)
    - `SystemConfigurator` for conversion_test, rpi_monitor, server_manager (152 lines)
    - `WebViewConfigurator` for webview (209 lines)
  - Each tool type now has isolated, maintainable configuration logic
  - Easy to extend with new tool types

### New Utilities
- **AngleUtils** (`lib/utils/angle_utils.dart`): Centralized angle normalization and manipulation
  - Eliminated duplicate angle normalization code across 7 files
  - Provides `normalize()`, `difference()`, `interpolate()`, and `toRadians()/toDegrees()`
  - Reduced code duplication and improved consistency

- **CompassZoneBuilder** (`lib/utils/compass_zone_builder.dart`): Shared zone rendering for compass widgets
  - Extracted common zone building logic from wind_compass and autopilot widgets
  - Provides consistent visual styling across all compass-based tools
  - Simplified maintenance of compass visualizations

### Performance & Memory Improvements
- **Memory Management**: Fixed unbounded data growth issues
  - AIS data now pruned after 10 minutes of inactivity
  - General data pruned after 15 minutes for non-subscribed paths
  - Automatic cleanup runs every 5 minutes
  - Own vessel data and actively subscribed paths never pruned

- **Map Performance**: Replaced `Map.unmodifiable()` with `UnmodifiableMapView`
  - Zero-copy view creation instead of full map copying
  - Significant performance improvement in hot paths
  - Proper cache invalidation when data is pruned

### User Experience Improvements
- **Simplified Tool Addition**: Removed unnecessary menu click
  - "+" button now opens tool configuration directly (was: + → menu → Create Tool)
  - One-click access to tool creation instead of two

- **Improved Connection Management**: Enhanced connection and reconnection flows
  - Cloud icon (when disconnected) now navigates directly to Settings
  - Added "Other Connections" button on Connection Screen
  - Saved connections list auto-expands when navigating from connection buttons
  - Clicking saved connection now navigates to Dashboard (not back to Connection Screen)
  - Fixed navigation stack to prevent returning to Connection Screen after connecting

- **Auto-Placement**: Tools now auto-place on dashboard after configuration
  - Smart positioning: centers new tools or finds next available spot
  - Automatic collision detection for both portrait and landscape
  - Removed 158 lines of drag-and-drop placement overlay code
  - Users can still move/resize in edit mode if needed

### Documentation
- **Developer Guide**: Created comprehensive tool creation guide
  - 911-line guide in `docs/public/creating-new-tools-guide.md`
  - Documents new Strategy pattern for tool configurators
  - Includes 3 complete examples (simple display, multi-source, control)
  - Step-by-step instructions with code samples
  - Best practices, testing checklist, and troubleshooting

- **Code Review Documentation**: Updated comprehensive code review
  - Documents all completed refactoring phases
  - Before/after metrics for all improvements
  - Production-ready status confirmation

### Code Quality
- **Warnings Cleanup**: Eliminated all 8 compiler warnings
  - Fixed unused `_pruneStaleData` with proper cache callback integration
  - Removed unused variables and methods across multiple files
  - Clean compilation: 0 errors, 0 warnings, 30 info suggestions

- **Dead Code Removal**: Deleted obsolete code throughout codebase
  - Removed all `*_old.dart` backup files (2,765 lines)
  - Removed deprecated template system (1,349 lines)
  - Cleaned up unused wind shift calculation methods
  - Removed redundant placement mode code

### Technical Improvements
- Improved code maintainability with Strategy pattern
- Better separation of concerns in service layer
- Enhanced testability with isolated configurators
- Consistent error handling throughout
- Foundation for easier future tool development
- Extensible architecture for adding new tool types

## [0.3.1+8] - 2025-10-26

### Dependencies
- **Major Updates**: Upgraded key dependencies to latest versions
  - `flutter_map`: 7.0.2 → 8.2.2
    - Added built-in tile caching for faster map loading
    - Improved performance and package size reduction (3MB → 900KB)
    - Enhanced multi-world support and anti-meridian handling
  - `math_expressions`: 2.6.0 → 3.1.0
    - Updated to new `RealEvaluator` API for type-safe expression evaluation
    - Enhanced parser with mathematical constants support
  - `build_runner`: 2.10.0 → 2.10.1
- **Code Updates**: Updated `conversion_utils.dart` to use new math_expressions v3.x API
  - Migrated from deprecated `evaluate()` to `RealEvaluator().evaluate()`
  - Maintained full backward compatibility for all unit conversion functionality

### Added
- **Multi-Needle Compass Support**: Compass gauge now supports up to 4 needles for comparing multiple headings
  - Compare heading, COG, autopilot target, or any other directional data on one display
  - Color-coded needles with legend at bottom
  - Secondary needles slightly shorter and semi-transparent for visual hierarchy
  - Works with all compass styles (classic, arc, minimal, marine)
- **Server Status Tool**: Real-time SignalK server monitoring and management dashboard
  - Live server statistics display (uptime, delta rate, connected clients, available paths)
  - Per-provider statistics with individual delta rates and counts
  - Plugin management with interactive enable/disable controls (tap to toggle)
  - Webapp listing with version information
  - One-tap server restart functionality with confirmation dialog
  - Auto-updating statistics every 5 seconds via WebSocket `serverevents=all` subscription
  - Full authentication support for all server operations
  - Scrollable plugin and webapp lists to accommodate any number of installed items
  - Color-coded plugin status indicators (green = enabled, grey = disabled)
  - New "System" tool category for server management tools
- **RPi Monitor Tool**: Raspberry Pi system health monitoring dashboard
  - Overall CPU utilization display with progress bar
  - Per-core CPU utilization cards (up to 4 cores)
  - CPU and GPU temperature monitoring with color-coded warnings
    - Green: < 60°C
    - Orange: 60-75°C
    - Red: > 75°C
  - Memory and storage utilization displays (if available)
  - System uptime display with formatted output
  - Integrates with signalk-rpi-monitor and signalk-rpi-uptime plugins
  - Monitors paths: `environment.rpi.cpu.*`, `environment.rpi.gpu.temperature`, `environment.rpi.uptime`
  - Automatic temperature conversion from Kelvin to Celsius

### Enhanced
- **Compass Gauge**: Major improvements to rendering and usability
  - Custom compass labels that stay horizontal (no upside-down text)
  - Better label positioning with configurable degree labels
  - Removed "rose" style (redundant with classic style)
  - Improved marine compass with counter-rotating labels that always stay readable
  - Multi-needle support for comparing up to 4 headings simultaneously
- **Text Display Tool**: Smart formatting for latitude and longitude
  - Auto-detects lat/long fields by property name (contains 'lat' or 'lon')
  - Formats as degrees, minutes, seconds with hemisphere (e.g., "37° 46' 29.64" N")
  - Works with any numeric property containing 'lat' or 'lon' in the key
  - Support for displaying object values (Map) with property breakdown
- **Wind Compass**: Added fade effect to no-go zone based on point of sail
  - No-go zone opacity decreases as apparent wind angle increases
  - Full opacity when close-hauled (AWA < 60°)
  - Linear fade when reaching (AWA 60-120°)
  - Very faint when running downwind (AWA > 120°)
- **Autopilot Tool**: Improved fading behavior
  - Faded opacity increased from 10% to 20% for better visibility
  - Double-tap to disengage now works anywhere on the screen, including over buttons
- **Android File Sharing**: Enhanced dashboard file import
  - ZedDisplay now properly opens .zedjson files shared from file managers
  - Automatic navigation to Setup Management screen after import
  - Proper intent handling via content:// URIs

### Fixed
- **Client-Side Unit Conversions**: All widgets now use ConversionUtils for unit conversions
  - Fixed polar radar chart, radial bar chart, and real-time chart conversions
  - Fixed historical chart distance conversions
  - All internal values stored in SI units (meters, radians)
  - Conversions applied only at display time
- **AIS Distance Conversions**: Now uses `/signalk/v1/categories` endpoint for consistent distance units
- **Tool Configuration UI**: Simplified data source addition from 3 dialogs to 2 dialogs
- **Dashboard File Import**: Fixed Android intent handling for .zedjson files

### Refactoring & Code Quality
- **Major Code Refactoring**: Eliminated ~1,130 lines of duplicate code across three phases
  - Phase 1: Created utility extensions for string formatting, color parsing, and data conversion
  - Phase 2: Implemented mixins and shared layouts for control tools and gauge tools
  - Phase 3: Established base abstractions and centralized UI constants
- **String Extensions** (`lib/utils/string_extensions.dart`):
  - Centralized path-to-label conversion logic
  - Removed 25 duplicate `_getDefaultLabel()` methods across 10 tool files
  - Saved ~120 lines of duplicate code
- **Color Extensions** (`lib/utils/color_extensions.dart`):
  - Centralized hex color parsing with fallback support
  - Removed 24 duplicate color parsing blocks across 17 tool files
  - Achieved 67% code reduction in color parsing logic (~88 lines saved)
- **Data Extensions** (`lib/utils/data_extensions.dart`):
  - Centralized boolean value conversion for SignalKDataPoint
  - Handles bool, numeric, and string-based boolean values
  - Updated switch and checkbox tools to use shared logic
- **Zones Cache Service** (`lib/services/zones_cache_service.dart`):
  - Centralized zone caching to prevent duplicate HTTP requests
  - Multiple gauge tools now share cached zone data
  - Expected 30-50% improvement in dashboard load times
  - Integrated into SignalKService for automatic availability
- **Control Tool Mixin** (`lib/widgets/tools/mixins/control_tool_mixin.dart`):
  - Shared numeric value sending logic for slider, knob, and dropdown tools
  - Eliminated ~93 lines of duplicate `_sendValue()` methods
  - Consistent error handling and SnackBar feedback
- **Control Tool Layout** (`lib/widgets/tools/common/control_tool_layout.dart`):
  - Reusable layout widget for all control tools (slider, knob, dropdown, switch, checkbox)
  - Eliminated ~215 lines of duplicate Card/Padding/Column boilerplate
  - Consistent structure: label, value display, control widget, path, sending indicator
- **Zones Mixin** (`lib/widgets/tools/mixins/zones_mixin.dart`):
  - Shared zone fetching logic for radial and linear gauge tools
  - Eliminated ~58 lines of duplicate zone initialization code
  - Automatic connection state handling and cleanup
- **Base Tool Class** (`lib/widgets/tools/base/base_tool.dart`):
  - Abstract base class providing common functionality for all tools
  - Helpers for data source access, label generation, and color parsing
  - Consistent empty state handling
  - Foundation for future tool development
- **Data Service Interface** (`lib/services/interfaces/data_service.dart`):
  - Clean abstraction for data access
  - SignalKService now implements DataService interface
  - Improved testability (can mock the interface)
  - Better separation of concerns
- **UI Constants** (`lib/config/ui_constants.dart`):
  - Centralized all magic numbers and hardcoded values
  - Eliminated 24 magic numbers across 5 tool files
  - Constants for: opacity levels, polling intervals, timeouts, UI spacing, font sizes, animation durations
  - Helper methods for common opacity operations
- **Updated Tools**: Refactored 12 tool files to use new utilities and patterns
  - Radial gauge, linear gauge, slider, knob, dropdown, switch, checkbox, text display, compass, autopilot, and others
  - Consistent patterns and reduced duplication throughout

### Performance Improvements
- Zone data now cached and shared between gauge tools (30-50% faster dashboard loads)
- Reduced widget rebuilds through better state management
- Eliminated redundant HTTP requests for zone definitions

### Technical Improvements
- Improved code maintainability with centralized utilities
- Better testability through interface-based design
- Consistent error handling across control tools
- Reduced cognitive load with named constants instead of magic numbers
- Foundation for easier future tool development

## [0.2.0+4] - 2025-10-22

### Fixed
- **Critical Bug Fix**: Tools now correctly added to the intended screen
  - Fixed issue where realtime charts and other tools were being placed on wrong dashboard screen
  - Root cause: `DashboardService.addPlacementToActiveScreen()` was using current active screen instead of placement's screenId
  - Updated `dashboard_service.dart:210` to use `placement.screenId` to find correct screen
  - Affects: All tool types when adding to multi-screen dashboards

## [0.2.0+3] - 2025-10-22

### Added
- **Checkbox Tool**: New config-driven checkbox widget for boolean SignalK paths
  - Interactive checkbox for toggling boolean values (e.g., switches, alarms)
  - Full color customization for checked/unchecked states
  - State management with real-time updates
- **Wind Compass Tool**: Comprehensive wind direction and speed display
  - True wind and apparent wind visualization
  - No-go zone indicator for sailing optimization
  - Vessel shadow for enhanced orientation
  - Wind mode support showing wind indicators
  - Absolute wind direction calculations for compass display
  - Custom painters for professional visualization
- **AIS Polar Chart**: Display AIS targets on polar radar
  - Real-time vessel tracking
  - Distance and bearing visualization
- **Polar Radar Chart**: Advanced polar coordinate visualization
  - Customizable angle and magnitude labels
  - Tool-specific default sizing
  - Enhanced color customization options
  - Zone handling for sectors and regions
- **Historical Data Support**: Enhanced time-series data handling
  - Support for historical paths in path selector
  - Real-time chart tool updates using widget state
  - Auto-refresh capability for historical chart tool
- **Dashboard Management Improvements**:
  - Confirmation dialog before tool removal
  - Improved action button layout
  - Better organization of dashboard controls

### Enhanced
- **Autopilot Tool**: Major improvements for wind sailing modes
  - Calculate and display absolute wind directions
  - Show wind indicators in wind steering mode
  - Updated widget parameters for better configuration
- **Setup Service**: Improved initialization and auto-save
  - Auto-save active setup on dashboard changes
  - Initialize default setup on first launch
  - Create new blank dashboard automatically
  - Enhanced dashboard persistence when adding tools
- **Notification System**: Better user feedback
  - Updated app label for clarity
  - Improved notification display format
  - Group summary for multiple active notifications

### Fixed
- Code refactoring for better maintainability:
  - Removed unnecessary null safety operators
  - Updated color opacity methods from deprecated `withOpacity()` to `withValues(alpha:)`
  - Improved code readability in DashboardService and WindCompass

### Changed
- Removed windsteer tools from tool registry (replaced by enhanced Autopilot Tool)
- Updated widget tests to initialize additional services
- Updated app launch verification in tests

## [0.2.0] - Previous release

### Added
- **SignalK Units Preference Integration**: Full integration with signalk-units-preference plugin
  - Connect to `/plugins/signalk-units-preference/stream` for pre-converted values
  - Support for formatted values with unit symbols (e.g., "10.0 kn", "75°F")
  - New helper methods: `getFormattedValue()`, `getConvertedValue()`, `getUnitSymbol()`
- SignalK API methods for path and source discovery:
  - `getVesselSelfId()` - Fetch vessel UUID/MMSI from server
  - `getAvailablePaths()` - Fetch complete vessel data tree
  - `extractPathsFromTree()` - Extract all available data paths
  - `getSourcesForPath()` - Fetch available sources for a specific path
- Debug UI buttons on dashboard to test path discovery APIs
- Network client permission to macOS entitlements for SignalK connectivity
- Implementation plan document (IMPLEMENTATION_PLAN.md) for plugin-based dashboard system

### Fixed
- Added missing INTERNET and ACCESS_NETWORK_STATE permissions to Android manifest
- Replaced deprecated `withOpacity()` calls with `withValues(alpha:)` in compass_gauge.dart (3 instances)
- Replaced deprecated `withOpacity()` calls with `withValues(alpha:)` in radial_gauge.dart (2 instances)
- Changed `strokeWidth` to `const` in radial_gauge.dart for better performance
- Fixed source data parsing to handle SignalK `values` object format

### Changed
- **Removed all manual unit conversions** from dashboard (no more hardcoded * 1.94384, * 180 / 3.14159)
- **Server-side unit conversion**: App now respects user's unit preferences configured in SignalK
- Dashboard now uses pre-converted values and unit symbols from server
- Updated `SignalKDataPoint` model to support converted value format
- Updated code to eliminate all Flutter analyzer warnings (now passing with 0 issues)
- Default connection settings now use `192.168.1.88:3000` with secure connection disabled

## [0.1.0] - 2025-10-14

### Added
- Initial release
- Real-time SignalK WebSocket connection with endpoint discovery
- Custom radial gauges for displaying numeric marine data
- Compass gauge for heading display
- Dashboard displaying:
  - Speed Over Ground (SOG)
  - Speed Through Water (STW)
  - Heading (True)
  - Wind Speed (Apparent)
  - Depth Below Transducer
  - Battery Voltage
- Connection management screen with secure/non-secure options
- Dark mode support (system theme based)
- Unit conversions (m/s to knots, radians to degrees)
- Debug info panel showing data point statistics

### Technical Details
- Flutter SDK 3.0.0+
- Provider pattern for state management
- WebSocket-based real-time data streaming
- Custom CustomPainter widgets for gauges
- Material Design 3 UI
