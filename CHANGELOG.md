# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
