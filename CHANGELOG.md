# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
