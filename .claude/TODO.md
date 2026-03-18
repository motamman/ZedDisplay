# ZedDisplay TODOs

- [x] Fix screen selection tap
- [ ] Create a dashboard switcher widget
- [x] Clean up build warnings and alerts
- [ ] Clean up path filters to usable paths
- [ ] Move info box button from live widget to setup
- [ ] Cleanup no-connection messages inside widgets to one default style (single source of truth)
- [ ] Put TTL settings back into widget configs and make sure widgets respect the setting
- [ ] In the map explorer, make the first point the default for the detail tab
- [ ] Update the README with updated and missing pictures
- [ ] Create a widget-by-widget instruction manual
- [ ] Redo the device widget to be a meaningful device monitor
- [ ] Add Apple certificate signing and notarization to macOS release workflow
- [ ] Audit all widgets exposing PathSelectorDialog to verify they actually use the selected paths

## Widget Inventory — AIS Context Candidates

All 42 registered widgets. `allowsDataSources` defaults to `true` — those 27 widgets all use PathSelectorDialog via the ToolConfigScreen "Add data source" flow. To enable AIS context, wire `allowAISContext` in ToolConfigScreen based on tool type.

### Use PathSelectorDialog (`allowsDataSources: true`, default)

| # | Tool ID | Widget | AIS candidate? | Notes |
|---|---------|--------|----------------|-------|
| 1 | `radial_gauge` | Radial Gauge | Yes | Show another vessel's SOG/COG on a gauge |
| 2 | `compass` | Compass Gauge | Yes | Show another vessel's heading |
| 3 | `text_display` | Text Display | Yes | Show any AIS field as text |
| 4 | `linear_gauge` | Linear Gauge | Yes | Same as radial gauge |
| 5 | `switch` | Switch | Maybe | Could PUT to another vessel? Unlikely |
| 6 | `slider` | Slider | Maybe | Same as switch |
| 7 | `knob` | Knob | Maybe | Same as switch |
| 8 | `checkbox` | Checkbox | Maybe | Same as switch |
| 9 | `dropdown` | Dropdown | Maybe | Same as switch |
| 10 | `autopilot` | Autopilot | No | Self-vessel autopilot only |
| 11 | `autopilot_v2` | Autopilot V2 | No | Self-vessel autopilot only |
| 12 | `autopilot_simple` | Autopilot Simple | No | Self-vessel autopilot only |
| 13 | `historical_chart` | Historical Chart | No | AIS vessels have no history |
| 14 | `realtime_chart` | Realtime Chart | Maybe | Would need live AIS value streaming |
| 15 | `radial_bar_chart` | Radial Bar Chart | Maybe | Multiple data sources, mixed context gets complex |
| 16 | `polar_radar_chart` | Polar Radar Chart | No | Multi-axis, self-vessel specific |
| 17 | `ais_polar_chart` | AIS Polar Chart | No | Already AIS-aware internally |
| 18 | `wind_compass` | Wind Compass | No | Self-vessel wind data only |
| 19 | `conversion_test` | Conversion Test | No | Dev/debug tool |
| 20 | `attitude_indicator` | Attitude Indicator | No | Self-vessel attitude only |
| 21 | `gnss_status` | GNSS Status | No | Self-vessel GNSS only |
| 22 | `tanks` | Tanks | No | Self-vessel tank levels only |
| 23 | `anchor_alarm` | Anchor Alarm | No | Self-vessel position only |
| 24 | `position_display` | Position Display | Maybe | Could show another vessel's position |
| 25 | `find_home` | Find Home | No | Self-vessel nav only |
| 26 | `forecast_spinner` | Forecast Spinner | No | Weather API, no SignalK paths |
| 27 | `weatherflow_forecast` | WeatherFlow Forecast | No | Weather API, no SignalK paths |

### No PathSelectorDialog (`allowsDataSources: false`)

| # | Tool ID | Widget | Notes |
|---|---------|--------|-------|
| 28 | `victron_flow` | Victron Flow | Own configurator with own PathSelectorDialog call |
| 29 | `server_manager` | Server Manager | No data paths |
| 30 | `rpi_monitor` | RPi Monitor | System paths only |
| 31 | `system_monitor` | System Monitor | System paths only |
| 32 | `crew_messages` | Crew Messages | No data paths |
| 33 | `crew_list` | Crew List | No data paths |
| 34 | `intercom` | Intercom | No data paths |
| 35 | `file_share` | File Share | No data paths |
| 36 | `weather_api_spinner` | Weather API Spinner | External API |
| 37 | `weather_alerts` | Weather Alerts | External API |
| 38 | `clock_alarm` | Clock Alarm | No data paths |
| 39 | `device_access_manager` | Device Access Manager | No data paths |
| 40 | `user_management` | User Management | No data paths |
| 41 | `sun_moon_arc` | Sun/Moon Arc | Hardcoded astro paths |
| 42 | `historical_data_explorer` | Historical Data Explorer | Own context picker already |
