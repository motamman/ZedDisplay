# ZedDisplay TODOs

- [x] Fix screen selection tap
- [ ] Create a dashboard switcher widget
- [x] Clean up build warnings and alerts
- [x] Clean up path filters to usable paths
- [x] Move info box button from live widget to setup
- [x] Cleanup no-connection messages inside widgets to one default style (single source of truth)
- [x] Put TTL settings back into widget configs and make sure widgets respect the setting
- [x] In the map explorer, make the first point the default for the detail tab
- [ ] Update the README with updated and missing pictures
- [ ] Create a widget-by-widget instruction manual
- [x] Redo the device widget to be a meaningful device monitor
- [x] Add Apple certificate signing and notarization to macOS release workflow
- [ ] Audit all widgets exposing PathSelectorDialog to verify they actually use the selected paths
- [x] Investigate Windsteer Gauge — decided to remove (deprecated, superseded by Wind Compass). Files kept with deprecation headers.
- [x] Make vessel favorites sync across devices (follow the user, not the device)
- [x] Fix the macOS install to TestFlight
- [ ] Clean up and create a standard suite of dashboards for each form factor:
  - Small phone, large phone, small tablet, tablet
  - Each with: Navigation, System Controls, Weather & Conditions, Analysis & Data
- [x] Simplify the date picker in Map Explorer to a single calendar; add a "days back" option
- [x] Check why ais favorites are not syncing with devices
- [x] Remove light/dark toggle from menu
- [x] Add "What's New" markdown modal as a menu item
- [ ] Re-examine the entire messaging and notification system
- [ ] Message deletion semantics: deleting a message locally also deletes from Resources API — should this propagate to other devices? Should there be a "delete for me" vs "delete for everyone" distinction? What about the WS delta cache?
- [x] Finish refactoring for single source of truth for base URL (`httpBaseUrl` on SignalKService) — migrate remaining scattered `$protocol://$_serverUrl` constructions in SignalKService internal REST calls

## Widget Inventory — AIS Context Status

### AIS-Aware (implemented in v0.5.80 via `DataSource.resolve()`)

| Tool ID | Widget | Notes |
|---------|--------|-------|
| `radial_gauge` | Radial Gauge | Show another vessel's SOG/COG on a gauge |
| `linear_gauge` | Linear Gauge | Same as radial, with TTL via `isFresh()` |
| `compass` | Compass Gauge | Show another vessel's heading, multi-needle supported |
| `text_display` | Text Display | Show any AIS field as text, including object values |
| `position_display` | Position Display | Show another vessel's lat/lon |
| `realtime_chart` | Realtime Chart | Chart live AIS values, multi-series supported |

### Not AIS-aware (by design)

| Tool ID | Widget | Reason |
|---------|--------|--------|
| `switch` | Switch | PUT to another vessel not meaningful |
| `slider` | Slider | Same |
| `knob` | Knob | Same |
| `checkbox` | Checkbox | Same |
| `dropdown` | Dropdown | Same |
| `autopilot` | Autopilot | Self-vessel autopilot only |
| `autopilot_v2` | Autopilot V2 | Self-vessel autopilot only |
| `autopilot_simple` | Autopilot Simple | Self-vessel autopilot only |
| `historical_chart` | Historical Chart | AIS vessels have no parquet history |
| `radial_bar_chart` | Radial Bar Chart | Mixed context per ring gets complex |
| `polar_radar_chart` | Polar Radar Chart | Self-vessel specific |
| `ais_polar_chart` | AIS Polar Chart | Already AIS-aware internally |
| `wind_compass` | Wind Compass | Self-vessel wind data only |
| `windsteer` | Windsteer Gauge | Self-vessel wind data only |
| `conversion_test` | Conversion Test | Dev/debug tool |
| `attitude_indicator` | Attitude Indicator | Self-vessel attitude only |
| `gnss_status` | GNSS Status | Self-vessel GNSS only |
| `tanks` | Tanks | Self-vessel tank levels only |
| `anchor_alarm` | Anchor Alarm | Self-vessel position only |
| `find_home` | Find Home | Self-vessel nav only |
| `forecast_spinner` | Forecast Spinner | Weather API, no SignalK paths |
| `weatherflow_forecast` | WeatherFlow Forecast | Weather API, no SignalK paths |
| `victron_flow` | Victron Flow | Own configurator, self-vessel only |
| `server_manager` | Server Manager | No data paths |
| `rpi_monitor` | RPi Monitor | System paths only |
| `system_monitor` | System Monitor | System paths only |
| `crew_messages` | Crew Messages | No data paths |
| `crew_list` | Crew List | No data paths |
| `intercom` | Intercom | No data paths |
| `file_share` | File Share | No data paths |
| `weather_api_spinner` | Weather API Spinner | External API |
| `weather_alerts` | Weather Alerts | External API |
| `clock_alarm` | Clock Alarm | No data paths |
| `device_access_manager` | Device Access Manager | No data paths |
| `user_management` | User Management | No data paths |
| `sun_moon_arc` | Sun/Moon Arc | Hardcoded astro paths |
| `historical_data_explorer` | Historical Data Explorer | Own context picker already |
| `webview` | WebView | No data paths |
