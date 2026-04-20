# MetadataStore Single-Source-of-Truth Compliance

## Context

A thorough audit in April 2026 found that `MetadataStore`, documented as the
single source of truth for all unit conversions, was not actually enforced.
Three parallel conversion authorities coexisted:

1. `lib/services/metadata_store.dart` — the intended source of truth.
2. `lib/utils/conversion_utils.dart` — LEGACY. Owned its own category cache,
   user-preferences cache, and hardcoded `_standardConversions` table (temp,
   speed, pressure, angle, percentage). Still wired into weather widgets,
   login, connection, and settings screens.
3. `SignalKService.getUnitSymbol` — read `_dataCache.internalDataMap[path].symbol`
   directly from the units-preference plugin payload, bypassing MetadataStore.

Alongside the three-SoT problem, the audit surfaced:

- Hardcoded conversion math in models (`anchor_state.dart`) and services
  (9 `@deprecated` getters on `WeatherApiForecast`).
- Hardcoded fallback conversions in widgets when metadata was null
  (`* 180 / math.pi`, `* 1852`, `'m'`-suffix assumptions).
- Hardcoded default unit symbols in widget constructor params
  (`'°F'`, `'kn'`, `'hPa'`, `'°C'`, `'kts'`, `'mm'`).
- ~8 widget-local `_formatValue` helpers all implementing the same
  `metadata?.format() ?? raw.toStringAsFixed()` pattern.
- No central `ServiceConstants` / `NavigationConstants` / `AppColors`
  despite dozens of repeated magic values.
- `PathMetadata._evaluateFormula` re-parsed the formula string on every
  call via `GrammarParser()`, with a silent `RegExp(r'value\s*\*\s*([\d.]+)')`
  fallback that only succeeded for simple multiplication.

## User Decisions (captured)

| Decision | Choice |
|---|---|
| When metadata is missing, widgets render | **raw SI value with SI symbol** (permissive policy) |
| User-preferences ownership | **Extend `SignalKService`** with `applyCachedUserPreferencesToMetadataStore()` + `hasUserPreferencesApplied` |
| CPA / anchor / other thresholds | **Migrate persistence to SI** (deferred as H2) |
| Units-preference plugin pre-converted fields | **Re-route at ingest** — pipe symbol/formula into `MetadataStore.updateFromMeta`; `DataPoint.symbol/.converted/.formatted` become dead fields |

## Plan Reference

Full phase plan and rationale: `~/.claude/plans/mellow-snacking-lerdorf.md`.

## Status

### Completed (on branch `crocus-erupt`)

| Phase | Scope | Key files |
|---|---|---|
| A | `MetadataStore.tryConvert` / `tryConvertToSI` + `MetadataFormatExtension.formatOrRaw` on `PathMetadata?` | `lib/services/metadata_store.dart`, `lib/models/path_metadata.dart` |
| B | Compile formulas once via static cache; delete regex fallback | `lib/models/path_metadata.dart` |
| C | Delete 9 `@deprecated` hardcoded-formula getters on `WeatherApiForecast` (zero external callers) | `lib/services/weather_api_service.dart` |
| D | Re-route plugin symbols through `MetadataStore.updateFromMeta` at ingest. Rewrite `getUnitSymbol`, `getFormattedValue`, `getConvertedValue` as MetadataStore delegations. Added `_rawSIValueForPath` helper. Frame-drop guard: skip `updateFromMeta` when the store already has the symbol | `lib/services/signalk_service.dart` |
| E | Migrate weather forecast widgets off `ConversionUtils`. `forecast_spinner_tool` (9 calls), `weatherflow_forecast_tool` (18 calls including `evaluateFormula`), `weather_api_spinner_tool` (collapsed `WeatherFieldType` enum + `_convertWithFallback` into a single `_convertApi` using MetadataStore's category-level fallback) | `lib/widgets/tools/forecast_spinner_tool.dart`, `lib/widgets/tools/weatherflow_forecast_tool.dart`, `lib/widgets/tools/weather_api_spinner_tool.dart` |
| F | `SignalKService` gains `applyCachedUserPreferencesToMetadataStore()` / `clearUserPreferencesFromMetadataStore()` / `hasUserPreferencesApplied`. All 4 screens (`splash`, `user_login`, `connection`, `settings`) migrated. Logout now correctly resets MetadataStore to server defaults (pre-change, ConversionUtils cleared its orphaned cache but MetadataStore kept the user preset) | `lib/services/signalk_service.dart`, `lib/screens/{splash,user_login,connection,settings}_screen.dart` |
| G | **Delete `lib/utils/conversion_utils.dart` entirely.** Prune dead `SignalKDataPoint` fields (`symbol`, `converted`, `formatted`, `hasConvertedValue` getter). Keep `.original` (still load-bearing for ~20 widgets). Remove dead `_DataCacheManager.getConvertedValue`. Scrub `CLAUDE.md` + `METADATA_STORE_GUIDE.md` | `lib/utils/conversion_utils.dart` (deleted), `lib/models/signalk_data.dart`, `lib/services/signalk_service.dart`, `.claude/CLAUDE.md`, `.claude/METADATA_STORE_GUIDE.md` |
| H1 | Widget fallback cleanup. Replaced hardcoded `* 180 / math.pi` fallbacks with `formatOrRaw` extension. Deleted `AnchorState.bearingDegrees` getter (zero readers). Anchor-alarm bearing now normalises modulo the correct period (360° or 2π rad) based on metadata symbol rather than assuming degrees | `lib/widgets/tools/anchor_alarm_tool.dart`, `lib/widgets/tools/find_home_tool.dart`, `lib/widgets/ais_vessel_detail_sheet.dart`, `lib/models/anchor_state.dart` |
| I | Hardcoded unit-symbol defaults removed from forecast widget chrome public APIs. Constructor params are `String?` (nullable, no defaults). Internal interpolation null-coalesces to empty | `lib/widgets/forecast_spinner.dart`, `lib/widgets/weatherflow_forecast.dart`, `lib/widgets/tools/forecast_spinner_tool.dart`, `lib/widgets/tools/weatherflow_forecast_tool.dart` |
| J | Dedupe `_formatValue` across 7 tool widgets. Each helper now delegates to `MetadataFormatExtension.formatOrRaw`; no duplicate `metadata?.format() ?? raw.toStringAsFixed()` logic | `lib/widgets/tools/wind_compass_tool.dart`, `windsteer_tool.dart`, `compass_gauge_tool.dart`, `radial_gauge_tool.dart`, `linear_gauge_tool.dart`, `rpi_monitor_tool.dart`, `lib/widgets/chart_plotter/chart_hud.dart` |
| K | `lib/config/service_constants.dart` introduced (`httpTimeout`, `shortHttpTimeout`, `longHttpTimeout`, `veryLongHttpTimeout`, debounce/UX-delay slots). 40 `.timeout(...)` call sites migrated across `signalk_service` (30), `auth_service` (4), `user_management_tool` (4), `device_access_manager_tool` (4), `weather_api_service` (1), `weather_api_spinner_configurator` (1). Post-migration grep confirms zero `.timeout(const Duration(...))` hits in `lib/` | `lib/config/service_constants.dart` (new), plus 6 migration sites |

### Deferred

- **H2 — CPA / anchor threshold persistence migration to SI.** Config schema
  change plus one-way data migration. Risk of destroying user config. Needs
  dry-run logging and a per-device version tag before shipping. Live bug
  today: `ais_polar_chart_tool.dart:63` falls back to `displayValue * 1852.0`
  when no distance metadata exists, i.e. assumes NM is the persisted unit.

### Remaining

| Phase | Scope | Risk | Size |
|---|---|---|---|
| L | `NavigationConstants` module (meters/nm, compass constants) | Low | S |
| M | `AppColors` semantic palette | Low | M |
| N | Kill inline `* 180/pi` / `* pi/180` (classify trig vs display; migrate to `AngleUtils` where internal, MetadataStore where display-facing) | Medium | L |
| O | Dedupe private `_formatTime` / `_formatTimeSince` (10 sites) into `DateTimeFormatter` | Low | M |
| A2 | Flip `MetadataStore.convert` / `convertToSI` to return `null` on missing metadata (strict contract). Final compliance gate. Safe only after Phases B–J land and all consumers use `formatOrRaw` for permissive rendering | Low (at this stage) | S |

## Verification State

- `flutter analyze lib/` — clean aside from 2 pre-existing `curly_braces_in_flow_control_structures` infos in `autopilot_v2_api.dart` (unrelated).
- `flutter test test/models/ test/services/` — 31/31 pass. Tests cover `PathMetadata.convert/convertToSI/format`, the `formatOrRaw` extension, parenthesised temperature formulas (K→F), `MetadataStore.updateFromMeta` merge semantics, `tryConvert`/`tryConvertToSI`, category fallback, clear notifications.
- Pre-existing `test/widget_test.dart` failures (missing chart-service args) are untouched by this work — unrelated.

## Known Open Bug

**Weather Spinner (API) renders in SI/raw units.** After the Phase E2
migration, `_convertApi` falls back to raw SI when `MetadataStore` has no
entry for the provider-specific forecast paths (`environment.outside.<provider>.forecast.hourly.*`).
Root cause candidates:

1. REST `populateFromPreset` may not cover those provider-scoped paths
   (their categories aren't in the default-categories map).
2. `_getConversionPath` may be building paths MetadataStore never learns
   about (the plugin only sends data for subscribed paths, which may not
   include the forecast tree).

Tracked in `.claude/TODO.md`. Fix plan: verify REST coverage on `brain`
server, then either extend `categoryLookup` to recognise these patterns
or explicitly subscribe to an observations path so `sendMeta=all` populates
the category.

## Architecture After This Work

- One conversion authority: `MetadataStore`.
- One null-rendering contract: `MetadataFormatExtension.formatOrRaw`,
  permissive (raw SI + SI suffix) per user decision.
- Plugin-delivered conversion data flows through `MetadataStore.updateFromMeta`
  at WebSocket ingest (`signalk_service.dart:_handleMessage`).
- REST `populateFromPreset` fills MetadataStore on connect.
- User-preset application and revert routed through `SignalKService`
  public API (`applyCachedUserPreferencesToMetadataStore` /
  `clearUserPreferencesFromMetadataStore` / `hasUserPreferencesApplied`).
- Service-layer timeouts centralised in `lib/config/service_constants.dart`;
  UI-layer durations stay in `lib/config/ui_constants.dart`.

## Critical Files

- `lib/services/metadata_store.dart`
- `lib/models/path_metadata.dart`
- `lib/services/signalk_service.dart`
- `lib/models/signalk_data.dart`
- `lib/services/weather_api_service.dart`
- `lib/config/service_constants.dart` (new)
- `test/models/path_metadata_test.dart` (new)
- `test/services/metadata_store_test.dart` (new)
