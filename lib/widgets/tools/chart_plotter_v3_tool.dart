import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:s52_dart/s52_dart.dart';
import 'package:uuid/uuid.dart';

import '../../config/app_colors.dart';
import '../../config/chart_constants.dart';
import '../../models/path_metadata.dart';
import '../../models/tool_config.dart';
import '../../models/tool_definition.dart';
import '../../services/chart_download_manager.dart';
import '../../services/chart_tile_cache_service.dart';
import '../../services/chart_tile_server_service.dart';
import '../../services/cpa_alert_service.dart';
import '../../services/dashboard_service.dart';
import '../../services/find_home_target_service.dart';
import '../../services/route_arrival_monitor.dart';
import '../../services/s57_tile_manager.dart';
import '../../services/signalk_service.dart';
import '../../services/storage_service.dart';
import '../../services/tool_registry.dart';
import '../../models/weather_layer_metadata.dart';
import '../../models/weather_route_request.dart';
import '../../models/weather_route_result.dart';
import '../../services/route_planner_auth_service.dart';
import '../../utils/antimeridian.dart';
import '../../utils/track_simplifier.dart';
import '../../utils/ship_type_utils.dart' as ship_type;
import '../../services/route_planner_boats_service.dart';
import '../../services/weather_data_service.dart';
import '../../services/weather_routing_service.dart';
import '../ais_vessel_detail_sheet.dart';
import '../ais_vessel_list.dart' as ais_list;
import '../chart_plotter/chart_hud.dart';
import '../chart_plotter/chart_layer_panel.dart';
import '../chart_plotter/chart_route_panel.dart';
import '../chart_plotter/weather_data_overlays.dart';
import '../chart_plotter/weather_routing_itinerary_card.dart';
import '../chart_plotter/weather_routing_overlay.dart';
import '../chart_plotter/weather_routing_panel.dart';
import '../countdown_confirmation_overlay.dart';
import '../map_attribution.dart';

/// Three mutually-exclusive chart orientation modes. Only `free` lets
/// the user's two-finger rotation gesture spin the map; the other two
/// lock or drive rotation from code.
enum _ViewMode { northUp, headingUp, free }

/// What to do with a leftover unsaved recorded-track buffer when the user
/// starts a new recording.
enum _UnsavedTrackAction { save, discard }

/// Chart Plotter V3 — spike: proves the s52_dart → flutter_map pipeline.
///
/// Basemap: OSM raster. Overlay: one MVT tile fetched from the SignalK
/// chart proxy, decoded, fed through `S52StyleEngine`, painted via
/// `CustomPainter`. Scope: points (symbols rendered as dots) and lines
/// only. No text, no patterns, no multi-tile viewport loading.
///
/// Purpose: answer whether pure-Flutter paint driven by s52_dart output
/// is viable for real chart rendering.
class ChartPlotterV3Tool extends StatefulWidget {
  const ChartPlotterV3Tool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  final ToolConfig config;
  final SignalKService signalKService;

  @override
  State<ChartPlotterV3Tool> createState() => _ChartPlotterV3ToolState();
}

class _ChartPlotterV3ToolState extends State<ChartPlotterV3Tool>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static const _initialCenter = LatLng(41.10, -72.80); // Long Island Sound
  static const _initialZoom = 12.0;

  /// The full set of chart-domain layers the user can toggle:
  /// every basemap, the OpenSeaMap seamark overlay, the depth
  /// overlay, and every S-57 chart published by the SignalK server's
  /// `/resources/charts` catalog. Each entry is
  /// `{type, id, enabled, opacity}`; ordering is the user's,
  /// preserved across restarts via `_persistLayerPrefs`.
  ///
  /// Render contract:
  /// - **base** entries render in list order (so multiple bases
  ///   stack — drag the one you want underneath to the front).
  /// - **overlay** entries (currently just `openseamap`) render
  ///   wherever they appear in the list, on top of any basemaps
  ///   above them.
  /// - **depth** is the route planner's GEBCO bathymetry served via
  ///   `_weatherRasterTile('/depth', ...)`.
  /// - **s57** entries are merged into a single render via the
  ///   tile manager + s52 painter (the painter filters per
  ///   `_enabledChartIds`); the merged group renders right after
  ///   the base/overlay/depth stack.
  ///
  /// Catalog reconciliation: on every catalog refresh, new s57
  /// entries are appended (default `enabled: false`) and entries
  /// for charts no longer in the catalog are dropped. The non-s57
  /// seed below is what every fresh install starts with.
  final List<Map<String, dynamic>> _layers = [
    {'type': 'base', 'id': 'carto_voyager', 'enabled': true, 'opacity': 1.0},
    {'type': 'base', 'id': 'openstreetmap', 'enabled': false, 'opacity': 1.0},
    {'type': 'base', 'id': 'carto_dark', 'enabled': false, 'opacity': 1.0},
    {'type': 'base', 'id': 'carto_light', 'enabled': false, 'opacity': 1.0},
    {'type': 'base', 'id': 'esri_ocean', 'enabled': false, 'opacity': 1.0},
    {'type': 'base', 'id': 'esri_satellite', 'enabled': false, 'opacity': 1.0},
    // OpenSeaMap seamarks. Default on — that preserves the
    // pre-refactor "Voyager + seamarks" UX where seamarks were
    // implicit. User can toggle off like any other layer.
    {'type': 'overlay', 'id': 'openseamap', 'enabled': true, 'opacity': 1.0},
    {'type': 'depth', 'id': 'depth', 'enabled': false, 'opacity': 1.0},
  ];
  // Cache the discovered chart catalog so `_pushManagerCharts` can
  // look up bounds + URL templates by chartId. Refreshed from
  // `signalKService.getResources('charts')` at mount and on every
  // layer-panel mutation. Each entry's `urlTemplate` is forwarded to
  // `ChartTileServerService` so the proxy resolves the right upstream
  // per chartId.
  List<ChartDescriptor> _chartCatalog = const [];

  /// `true` once `_refreshChartCatalog` has successfully parsed a
  /// resources/charts response from this SignalK server. Stays `true`
  /// across subsequent failures so `_onChartsCatalogChanged` can
  /// distinguish "catalog never arrived (don't reconcile yet)" from
  /// "catalog is empty (drop stale s57 rows)". Without this, a slow
  /// or failing first connect would wipe every persisted s57
  /// selection from `_layers` before the next retry could rescue
  /// them.
  bool _catalogHasLoaded = false;

  /// Mirrors `_chartsService.loading` / `lastError` semantics in the
  /// inline catalog fetch path. Drives the Charts tab's spinner /
  /// error chip.
  bool _catalogLoading = false;
  String? _catalogLastError;

  Map<String, dynamic>? _firstEnabled(String type) {
    for (final l in _layers) {
      if (l['type'] == type && (l['enabled'] as bool? ?? true)) return l;
    }
    return null;
  }

  /// Resolve a `_layers` entry to its TileLayer URL template for
  /// the basemap / overlay render path. Returns null when the entry
  /// has no public URL (s57 charts and the depth overlay route
  /// through their own machinery).
  String? _urlForChartLayer(Map<String, dynamic> layer) {
    final type = layer['type'] as String?;
    final id = layer['id'] as String?;
    if (id == null) return null;
    if (type == 'base') return baseMapUrls[id];
    if (type == 'overlay' && id == 'openseamap') return openSeaMapUrl;
    return null;
  }

  /// Widgets emitted by the unified `_layers` loop for one chart-
  /// domain layer entry. Returns an empty list for entries that have
  /// no widget at the basemap-stack level (S-57 charts render via
  /// `_S57OverlayLayer` higher in the Stack; unknown types are
  /// silently skipped).
  List<Widget> _chartLayerWidgets(Map<String, dynamic> layer) {
    final type = layer['type'] as String?;
    final opacity = (layer['opacity'] as num?)?.toDouble() ?? 1.0;
    if (type == 'base' || type == 'overlay') {
      final url = _urlForChartLayer(layer);
      if (url == null) return const [];
      return [
        Opacity(
          opacity: opacity,
          child: TileLayer(
            urlTemplate: url,
            userAgentPackageName: 'org.zennora.zed_display',
            maxZoom: 19,
          ),
        ),
      ];
    }
    if (type == 'depth') {
      if (_weatherDataService == null) return const [];
      return [
        Opacity(
          opacity: opacity,
          child: _weatherRasterTile(
              '/depth', WeatherDataService.zoomFloorDepth),
        ),
      ];
    }
    return const [];
  }

  /// Set of chart ids the user currently has toggled on. Used by the
  /// painter and tap hit-test to filter merged tile features without
  /// touching the manager — toggle is therefore instant and free of
  /// network refetches.
  Set<String> get _enabledChartIds {
    final out = <String>{};
    for (final l in _layers) {
      if (l['type'] != 's57') continue;
      if (l['enabled'] as bool? ?? true) {
        out.add(l['id'] as String);
      }
    }
    return out;
  }

  bool _isLayerEnabled(String id, {required String type}) {
    for (final l in _layers) {
      if (l['type'] == type &&
          l['id'] == id &&
          (l['enabled'] as bool? ?? true)) {
        return true;
      }
    }
    return false;
  }

  bool _anyOsmOrOpenSeaMapEnabled() =>
      _isLayerEnabled('openstreetmap', type: 'base') ||
      _isLayerEnabled('openseamap', type: 'overlay');

  // Default SignalK paths driving the HUD. Mirrors V1's
  // `_fallbackPaths` so the HUD formats values identically whether
  // the user is on V1 or V3. Index positions are part of the HUD's
  // contract (see ChartPlotterHUD's `_dsSog` et al).
  static const _fallbackPaths = [
    'navigation.position',
    'navigation.headingTrue',
    'navigation.courseOverGroundTrue',
    'navigation.speedOverGround',
    'environment.depth.belowTransducer',
    'navigation.course.calcValues.bearingTrue',
    'navigation.course.calcValues.crossTrackError',
    'navigation.course.calcValues.distance',
    'navigation.course.activeRoute',
    'navigation.courseGreatCircle.nextPoint.position',
  ];

  // HUD style + position come from the V3 configurator's HUD section.
  // Read as getters off `widget.config` so a configurator edit takes
  // effect on the next rebuild — the dashboard keys the tool by
  // toolId, not config, so State (and any cached fields) survives
  // edits.
  String get _hudStyle => _stringProp('hudStyle', 'text');
  String get _hudPosition => _stringProp('hudPosition', 'bottom');

  S52StyleEngine? _engine;
  S52ColorTable? _colorTable;
  SpriteAtlas? _spriteAtlas;
  ui.Image? _spriteImage;
  String? _loadError;
  S57TileManager? _tileManager;
  final _mapController = MapController();

  // Route state — mirrors V1's field set so ChartRouteState /
  // ChartRouteCallbacks plug in unchanged. `[lon, lat]` pairs match
  // SignalK's GeoJSON route geometry on the wire.
  String? _activeRouteHref;
  List<List<double>>? _routeCoords;
  List<String>? _waypointNames;
  int? _routePointIndex;
  int? _routePointTotal;
  bool _routeReversed = false;
  Timer? _routePollTimer;
  RouteArrivalMonitor? _arrivalMonitor;
  StreamSubscription<RouteArrivalEvent>? _arrivalSub;


  // Active nav-drawer flyout. The map-controls column on the right
  // edge has six buttons: three standalones (view-mode / snap /
  // ruler) and three group icons (AIS / Routes / Layers). Tapping a
  // group icon opens its sub-buttons in a horizontal drawer that
  // slides in to the LEFT of the column. Only one drawer is open at
  // a time; tapping the same group icon a second time (or tapping a
  // different group) collapses or swaps it. Local UI state — not
  // persisted across restarts.
  _NavDrawerKind _openDrawer = _NavDrawerKind.none;

  void _toggleNavDrawer(_NavDrawerKind which) {
    setState(() {
      _openDrawer =
          _openDrawer == which ? _NavDrawerKind.none : which;
    });
  }

  // Ruler state. Matches V1's model: two endpoints (red + blue) that
  // can each snap to the own vessel ('self') or an AIS vessel id, and
  // reposition automatically when their snap target moves.
  bool _rulerVisible = false;
  LatLng? _rulerRed;
  LatLng? _rulerBlue;
  String? _rulerRedSnap; // null | 'self' | vesselId
  String? _rulerBlueSnap;

  // AIS display toggles + periodic refresh. We pull from
  // `aisVesselRegistry` instead of subscribing because the registry
  // mutates in place — a 1s tick gives live-enough updates without a
  // listener plumbing layer we'd have to design now.
  bool _aisEnabled = true;
  bool _aisActiveOnly = false;
  bool _aisShowPaths = false;
  List<_AisRenderable> _aisVessels = const [];
  /// Vessel id of the most recently tapped AIS target. Drives the
  /// 16 px yellow ring the painter draws over the selected vessel.
  /// Persists across detail-sheet open/close — cleared when the
  /// user taps an empty area of the chart, when AIS is turned off,
  /// or when the vessel ages out of the active snapshot. Session
  /// only (not persisted to disk).
  String? _selectedAisId;

  // Own-vessel position / heading. Populated on a 1s tick from
  // SignalKService's cached values — same cadence V1 used. Kept as
  // doubles rather than LatLng so the painter can skip null-safe
  // projection on every tick.
  double? _ownLat;
  double? _ownLon;
  double? _ownHeading; // radians
  double? _ownCog; // radians
  double? _ownSog; // m/s
  /// Ticks whenever own-vessel kinematics change. The AIS list bottom
  /// sheet listens to this alongside `aisVesselRegistry` so distance /
  /// CPA / TCPA stay live as the boat moves, not just when an AIS
  /// message arrives.
  final ValueNotifier<int> _ownVesselTick = ValueNotifier<int>(0);
  Timer? _vesselTimer;
  // Follow-vessel off by default — the map recenters once on first fix
  // (see `_didInitialCenter` below) and otherwise stays where the user
  // panned it unless they explicitly opt into continuous follow.
  bool _autoFollow = false;
  /// Set once on the first GPS fix so the map centers on the device's
  /// position when the chart plotter first opens. After the initial
  /// center, further tracking is opt-in via `_autoFollow`.
  bool _didInitialCenter = false;
  int _lastVesselPushMs = 0;
  int _lastAisPushMs = 0;
  // Auto-zoom re-engages with auto-follow and disables on a user
  // pinch/scroll so the user can override without fighting us.
  bool _autoZoom = true;
  LatLng? _tapHalo;
  // Set in FlutterMap's onMapReady. Anything that touches
  // `_mapController.camera` / `.move()` must short-circuit until
  // this flips, otherwise MapController throws "You need to have
  // the FlutterMap widget rendered at least once".
  bool _mapReady = false;
  // Three view modes:
  //   - `northUp`: map locked with north at screen top; rotation
  //     gestures are disabled.
  //   - `headingUp`: map rotates to keep the bow at screen top;
  //     rotation gestures are disabled (code drives the rotation).
  //   - `free`: user can pinch-rotate the map freely; nothing forces
  //     the rotation on each tick.
  _ViewMode _viewMode = _ViewMode.northUp;

  // Vessel trail — sliding window of recent positions with timestamps
  // (epoch ms). V1 defaults to 10 minutes (chart_plotter_tool.dart:
  // 141-142) and reads the override from `customProperties.trailMinutes`.
  // Trail appends are throttled to 2 s with a 5 m movement threshold.
  final List<LatLng> _trailPoints = [];
  final List<int> _trailTimestamps = [];
  int _lastTrailPushMs = 0;

  // Track recording — a full-voyage capture, independent of the rolling
  // display trail above. While `_recordingTrack` is on, every fix is
  // appended to `_recordedTrack` (movement-thresholded, but with NO
  // time-window cutoff), then saved as a SignalK `tracks` resource when
  // the user stops. In-memory for the session — not persisted across an
  // app restart.
  bool _recordingTrack = false;
  final List<LatLng> _recordedTrack = [];

  // Hard ceiling on the voyage-recording buffer. It has no time-window cutoff,
  // so an open-ended recording grows without bound (~1 pt/s at 5 m spacing →
  // tens of thousands of points over a long passage). At the ceiling we STOP
  // appending and warn once, rather than dropping oldest points — silently
  // trimming would corrupt a track the user intends to save.
  static const int _maxRecordedTrackPoints = 20000;
  bool _recordedTrackFullWarned = false;

  int get _trailMinutes {
    final v = widget.config.style.customProperties?['trailMinutes'];
    if (v is num) return v.toInt();
    return 10;
  }

  /// S-57 object classes (e.g. `RESARE`, `SUBTLN`, `M_QUAL`) the user
  /// has chosen to hide via the configurator. Features with a matching
  /// `objectClass` are skipped in the painter so their geometry still
  /// parses and lives in the cache (for future re-enable) but nothing
  /// prints.
  Set<String> get _hiddenClasses {
    final raw = widget.config.style.customProperties?['hiddenClasses'];
    if (raw is List) {
      return raw.map((e) => e.toString()).toSet();
    }
    return const <String>{};
  }

  // ===== Weather routing =====
  //
  // Overlay is driven by [WeatherRoutingService] (ChangeNotifier, obtained
  // via Provider). Selection index and "pick end-waypoint" state live here
  // because they're UI-only: they don't belong in the service's model.
  WeatherRoutingService? _weatherRoutingService;
  int? _weatherRouteSelectedIdx;
  // Pre-compute End-pin tap state: when true and no current route, show
  // a floating "Compute route" card. Cleared automatically when a
  // result arrives or when the user dismisses it.
  bool _composePopoverOpen = false;

  // ===== Weather data overlays (wind / currents / heatmaps) =====
  //
  // One service per chart plotter so per-tool base-URL overrides are
  // honoured. The service owns its own debouncers; this widget just
  // tells it when the map camera moves and what layers are on.
  // Toggles are ephemeral (match AIS / ruler patterns elsewhere in the
  // tool) — initial state is read from customProperties.
  WeatherDataService? _weatherDataService;
  late bool _windBarbsOn = _boolProp('windBarbsOn');
  late bool _currentsOn = _boolProp('currentsOn');
  late bool _windHeatmapOn = _boolProp('windHeatmapOn');
  late bool _currentHeatmapOn = _boolProp('currentHeatmapOn');
  late bool _seaStateOn = _boolProp('seaStateOn');
  /// Significant wave height heatmap. ECMWF HRES `swh`; alpha-masked
  /// to ocean cells server-side.
  late bool _waveHeatmapOn = _boolProp('waveHeatmapOn');
  /// Total precipitation rate heatmap (mm·s⁻¹ on the wire). Joins the
  /// exclusive heatmap mutex so only one raster heatmap is on at a
  /// time. Legend converts to mm/h / in/h / cm/h via the layer-
  /// specific formatter.
  late bool _precipHeatmapOn = _boolProp('precipHeatmapOn');
  /// 2-metre air temperature heatmap (Kelvin on the wire). ECMWF HRES
  /// `2t`/`t2m`. Server returns 204 below z=5.
  late bool _temperatureHeatmapOn = _boolProp('temperatureHeatmapOn');
  /// Sea-surface skin-temperature heatmap (Kelvin on the wire). ECMWF
  /// HRES `skt`; land cells alpha-masked server-side via the OSM land
  /// polygon raster.
  late bool _sstHeatmapOn = _boolProp('sstHeatmapOn');

  /// True when at least one weather layer that varies with the
  /// reference time is on. The weather player's strip is hidden /
  /// disabled when this is false; toggling the last time-keyed layer
  /// off also resets the player state via `_maybeDeactivatePlayer`.
  bool get _hasTimeKeyedWeatherLayer =>
      _windBarbsOn ||
      _currentsOn ||
      _windHeatmapOn ||
      _currentHeatmapOn ||
      _seaStateOn ||
      _waveHeatmapOn ||
      _precipHeatmapOn ||
      _temperatureHeatmapOn ||
      _sstHeatmapOn;

  // ===== Weather player state =====
  //
  // The player strip lets the user scrub the reference time of every
  // time-keyed weather layer (wind / current / heatmaps) forward and
  // back. State is in-memory only — closing the strip resets the
  // offset to 0.
  bool _playerVisible = false;
  int _playerOffsetHours = 0;
  /// 0 = paused, +1 = forward play, -1 = reverse play.
  int _playerDirection = 0;
  Timer? _playerTimer;
  /// Wall clock of the most recent player advance. Used by the
  /// tile-aware gating below to decide whether we've waited long
  /// enough to either advance (tiles quiet, ≥ minHold) or force-
  /// advance (tiles busy, ≥ maxHold). Null while the player is
  /// paused or has never advanced.
  DateTime? _playerLastAdvance;
  /// Minimum visual cadence: the player advances no faster than one
  /// hour per second even when tiles arrive faster, so playback
  /// stays watchable.
  static const Duration _playerMinHold = Duration(seconds: 1);
  /// Maximum tile-wait per advance: if any active time-keyed layer
  /// is still loading after this much, advance anyway so a single
  /// stuck tile / dead tileserver can't deadlock playback.
  static const Duration _playerMaxHold = Duration(seconds: 5);
  /// Polling interval for the gated tick loop. Granularity for the
  /// "tiles quiet?" check between [_playerMinHold] and
  /// [_playerMaxHold].
  static const Duration _playerPollInterval = Duration(milliseconds: 200);
  /// Player range (hours). `-120` = 5 days past, `+384` = 16 days
  /// future. Matches the route planner's forecast envelope.
  static const int _playerMinOffset = -120;
  static const int _playerMaxOffset = 384;

  // Per-layer user-picked minimum zoom (overrides metadata's default).
  // Cleared on session end.
  final Map<String, int> _userMinZoom = {};

  // Per-layer "show legend on the chart itself" toggle.
  final Map<String, bool> _legendOnMap = {};

  bool _boolProp(String key) {
    final v = widget.config.style.customProperties?[key];
    return v is bool ? v : false;
  }

  String _stringProp(String key, String fallback) {
    final v = widget.config.style.customProperties?[key];
    return v is String ? v : fallback;
  }

  // Cache of the last (upstream, token, refresh) tuple we pushed into
  // `ChartTileServerService`. Used to short-circuit redundant
  // `configure(...)` calls when `_configureTileServer` is invoked from
  // multiple paths (initState / didUpdateWidget / SignalKService
  // listener) on every WS delta.
  String? _appliedTileUpstream;
  String? _appliedTileToken;
  TileFreshness? _appliedTileRefresh;

  /// Push the current `cacheRefresh` choice (and SignalK origin / token)
  /// into the shared tile server. Called from `initState`, from
  /// `didUpdateWidget` (config edits), and from a `SignalKService`
  /// listener (auth-token refresh / upstream change on the same
  /// service instance) so the proxy never stays stuck on a stale
  /// upstream or token.
  ///
  /// `'aging'` triggers a background re-fetch once a tile is 15 days
  /// old, `'stale'` holds off until 30 days. Anything else (or missing)
  /// falls back to the stricter `stale` threshold so we don't burn
  /// bandwidth refreshing tiles the user hasn't asked us to.
  void _configureTileServer() {
    try {
      final tileServer = context.read<ChartTileServerService>();
      final cacheRefreshRaw = _stringProp('cacheRefresh', 'stale');
      final refreshThreshold = cacheRefreshRaw == 'aging'
          ? TileFreshness.aging
          : TileFreshness.stale;
      final upstream = widget.signalKService.httpBaseUrl;
      final token = widget.signalKService.authToken?.token;
      if (upstream == _appliedTileUpstream &&
          token == _appliedTileToken &&
          refreshThreshold == _appliedTileRefresh) {
        return;
      }
      _appliedTileUpstream = upstream;
      _appliedTileToken = token;
      _appliedTileRefresh = refreshThreshold;
      tileServer.configure(
        upstreamBaseUrl: upstream,
        authToken: token,
        refreshThreshold: refreshThreshold,
      );
    } catch (_) {}
  }

  /// Effective minimum zoom for a weather layer, applied by `TileLayer`
  /// (raster) or `zoomFloor` (vector). Precedence:
  /// `_userMinZoom[path]` → `metadata.minZoom` → hardcoded fallback.
  int _effectiveMinZoom(String metadataPath, int fallback) {
    final user = _userMinZoom[metadataPath];
    if (user != null) return user;
    final md = _weatherDataService?.metadataFor(metadataPath);
    return md?.minZoom ?? fallback;
  }

  /// Force only one raster heatmap on at a time. Picking any one
  /// turns the others off — including precipitation. Depth and the
  /// vector layers (wind barbs, currents) are independent and
  /// unaffected; everything else listed below is in the mutex.
  void _setExclusiveHeatmap(String selected) {
    setState(() {
      _windHeatmapOn = selected == 'wind';
      _currentHeatmapOn = selected == 'current';
      _seaStateOn = selected == 'seaState';
      _waveHeatmapOn = selected == 'wave';
      _precipHeatmapOn = selected == 'precip';
      _temperatureHeatmapOn = selected == 'temperature';
      _sstHeatmapOn = selected == 'sst';
    });
    _persistLayerPrefs();
  }

  void _clearHeatmap() {
    setState(() {
      _windHeatmapOn = false;
      _currentHeatmapOn = false;
      _seaStateOn = false;
      _waveHeatmapOn = false;
      _precipHeatmapOn = false;
      _temperatureHeatmapOn = false;
      _sstHeatmapOn = false;
    });
    // If no vector layers (wind barbs / currents) were on, this just
    // killed the last time-keyed layer — drop the player state too.
    if (_maybeDeactivatePlayer()) _syncWeatherReferenceTime();
    _persistLayerPrefs();
  }

  // ---- Layer-preference persistence ----
  //
  // User-facing toggles — on/off, per-layer min zoom, per-layer on-map
  // legend — are a user preference, not a per-tool-instance config.
  // Stored in `StorageService.settings` under a single key so the
  // state survives app restarts and hot restarts.
  static const String _layerPrefsKey = 'chart_plotter_v3_layer_prefs';

  void _persistLayerPrefs() {
    try {
      final storage = context.read<StorageService>();
      final payload = jsonEncode({
        'windBarbsOn': _windBarbsOn,
        'currentsOn': _currentsOn,
        'windHeatmapOn': _windHeatmapOn,
        'currentHeatmapOn': _currentHeatmapOn,
        'seaStateOn': _seaStateOn,
        'waveHeatmapOn': _waveHeatmapOn,
        'precipHeatmapOn': _precipHeatmapOn,
        'temperatureHeatmapOn': _temperatureHeatmapOn,
        'sstHeatmapOn': _sstHeatmapOn,
        'userMinZoom': _userMinZoom,
        'legendOnMap': _legendOnMap,
        // Full chart-domain layer list (basemaps, OpenSeaMap, depth,
        // every s57 chart). Persisted in order so reorder survives,
        // and per-row enabled + opacity round-trip.
        'chartLayers': _layers,
      });
      unawaited(storage.saveSetting(_layerPrefsKey, payload));
    } catch (_) {
      // StorageService may not be available in tests/headless.
    }
  }

  void _loadLayerPrefs() {
    try {
      final storage = context.read<StorageService>();
      final raw = storage.getSetting(_layerPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return;
      setState(() {
        _windBarbsOn = (j['windBarbsOn'] as bool?) ?? _windBarbsOn;
        _currentsOn = (j['currentsOn'] as bool?) ?? _currentsOn;
        _windHeatmapOn = (j['windHeatmapOn'] as bool?) ?? _windHeatmapOn;
        _currentHeatmapOn =
            (j['currentHeatmapOn'] as bool?) ?? _currentHeatmapOn;
        _seaStateOn = (j['seaStateOn'] as bool?) ?? _seaStateOn;
        _waveHeatmapOn = (j['waveHeatmapOn'] as bool?) ?? _waveHeatmapOn;
        _precipHeatmapOn =
            (j['precipHeatmapOn'] as bool?) ?? _precipHeatmapOn;
        _temperatureHeatmapOn =
            (j['temperatureHeatmapOn'] as bool?) ?? _temperatureHeatmapOn;
        _sstHeatmapOn = (j['sstHeatmapOn'] as bool?) ?? _sstHeatmapOn;
        // Enforce the single-heatmap mutex on persisted state.
        // Pre-fix builds could have left two heatmaps on at once
        // (precipitation wasn't part of the mutex); keep the first
        // ON in canonical order and clear the rest.
        final restored = <String, bool>{
          'wind': _windHeatmapOn,
          'current': _currentHeatmapOn,
          'seaState': _seaStateOn,
          'wave': _waveHeatmapOn,
          'precip': _precipHeatmapOn,
          'temperature': _temperatureHeatmapOn,
          'sst': _sstHeatmapOn,
        };
        final firstOn = restored.entries
            .firstWhere((e) => e.value, orElse: () => const MapEntry('', false))
            .key;
        if (firstOn.isNotEmpty) {
          _windHeatmapOn = firstOn == 'wind';
          _currentHeatmapOn = firstOn == 'current';
          _seaStateOn = firstOn == 'seaState';
          _waveHeatmapOn = firstOn == 'wave';
          _precipHeatmapOn = firstOn == 'precip';
          _temperatureHeatmapOn = firstOn == 'temperature';
          _sstHeatmapOn = firstOn == 'sst';
        }
        final mz = j['userMinZoom'];
        if (mz is Map<String, dynamic>) {
          _userMinZoom.clear();
          for (final e in mz.entries) {
            final v = (e.value as num?)?.toInt();
            if (v != null) _userMinZoom[e.key] = v;
          }
        }
        final lm = j['legendOnMap'];
        if (lm is Map<String, dynamic>) {
          _legendOnMap.clear();
          for (final e in lm.entries) {
            final v = e.value as bool?;
            if (v != null) _legendOnMap[e.key] = v;
          }
        }
        final cl = j['chartLayers'];
        if (cl is List) {
          // Restore the user's layer list verbatim. Catalog
          // reconciliation runs later (`_onChartsCatalogChanged`)
          // and adds any new s57 charts / drops gone ones.
          //
          // We MERGE rather than replace: the seeded `_layers`
          // already has the basemap + overlay + depth defaults;
          // the persisted list might be missing a basemap that
          // was added in a newer build, so we add any
          // not-in-saved seeds at the end. Then we order by the
          // saved sequence + append leftovers.
          final saved = <Map<String, dynamic>>[];
          for (final entry in cl) {
            if (entry is! Map) continue;
            final id = entry['id'];
            final type = entry['type'];
            if (id is! String || type is! String) continue;
            saved.add({
              'type': type,
              'id': id,
              'enabled': entry['enabled'] as bool? ?? false,
              'opacity':
                  (entry['opacity'] as num?)?.toDouble() ?? 1.0,
            });
          }
          // Compare on `(type, id)` so a built-in row (e.g.
          // `depth` / `openstreetmap`) isn't dropped just because a
          // saved S-57 chart happens to share its `id`.
          final savedKeys = {
            for (final l in saved) '${l['type']}:${l['id']}',
          };
          final leftovers = _layers
              .where((l) => !savedKeys.contains('${l['type']}:${l['id']}'))
              .toList();
          _layers
            ..clear()
            ..addAll(saved)
            ..addAll(leftovers);
        }
      });
    } catch (_) {
      // Corrupt payload → ignore and keep defaults.
    }
  }

  bool get _weatherRoutingEnabled {
    final v = widget.config.style.customProperties?['weatherRoutingEnabled'];
    return v is bool ? v : true;
  }

  String get _routePlannerBaseUrl {
    final v = widget.config.style.customProperties?['routePlannerBaseUrl'];
    if (v is String && v.isNotEmpty) return v;
    return 'https://router.zeddisplay.com';
  }

  RouteMode get _weatherRouteDefaultMode {
    final v = widget.config.style.customProperties?['weatherRouteDefaultMode'];
    return RouteMode.fromWire(v is String ? v : null);
  }

  String? get _weatherRoutePolar {
    final v = widget.config.style.customProperties?['weatherRoutePolar'];
    return (v is String && v.isNotEmpty) ? v : null;
  }

  @override
  void initState() {
    super.initState();
    _loadEngine();
    // Token refresh / upstream change on the same SignalKService
    // instance — keep the tile proxy in sync without waiting for a
    // remount. `_configureTileServer` self-throttles on its cached
    // last-applied tuple so this is cheap on every delta.
    widget.signalKService.addListener(_configureTileServer);
    // Configure the cached tile proxy once on mount. The server itself
    // is started at app boot in main.dart; here we just tell it which
    // upstream SignalK server to proxy for and whether to refresh
    // stale tiles eagerly. Wrapped in try/catch because the service
    // might not be present in test environments.
    WidgetsBinding.instance.addPostFrameCallback((_) => _configureTileServer());
    // Poll SignalK's course API at the same cadence V1 used — 3s.
    // Cheaper than a full WS subscription and the REST endpoint is
    // authoritative for route/index/total state.
    _pollCourseAPI();
    _routePollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pollCourseAPI(),
    );
    // 1s vessel tick — fast enough that the arrow feels live, slow
    // enough that we aren't rebuilding the whole painter tree every
    // frame. V1 pushes via JS every 1s too.
    _refreshVessel();
    _vesselTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshVessel(),
    );
    // V1 subscribes the chart plotter to the AIS vessels endpoint on
    // first connect. Without this the registry stays empty and no
    // traffic ever paints, even on a server broadcasting AIS.
    _ensureAisSubscribed();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Bind to the globally provided WeatherRoutingService — subscribe
    // once per instance so we rebuild when the service notifies (status
    // transitions, new log lines, route landed). Also push the config's
    // baseUrl into the service so per-tool overrides are honoured.
    final next = Provider.of<WeatherRoutingService>(context, listen: false);
    if (!identical(next, _weatherRoutingService)) {
      _weatherRoutingService?.removeListener(_onWeatherRoutingChanged);
      _weatherRoutingService = next;
      _weatherRoutingService!.addListener(_onWeatherRoutingChanged);
    }
    _weatherRoutingService!.baseUrl = _routePlannerBaseUrl;

    // Weather data service — lazily built on first dependency pass so
    // we've got RoutePlannerAuthService from the Provider tree.
    if (_weatherDataService == null) {
      final auth = Provider.of<RoutePlannerAuthService>(context, listen: false);
      _weatherDataService = WeatherDataService(auth)
        ..baseUrl = _routePlannerBaseUrl
        ..addListener(_onWeatherDataChanged);
      // Per-tile events fire on a dedicated notifier so they don't
      // wake every overlay that listens to the main service. The
      // player's status chips and "all tiles settled" gate need them
      // though, so subscribe explicitly.
      _weatherDataService!.tileStatusNotifier
          .addListener(_onWeatherDataChanged);
      // First dependency pass — now that `context.read<StorageService>()`
      // is wired, restore the user's persisted layer preferences
      // (which toggles were on, custom min-zooms, which legends on
      // the map).
      _loadLayerPrefs();
    } else {
      _weatherDataService!.baseUrl = _routePlannerBaseUrl;
    }

    // Boats service is the global Provider instance, but its baseUrl
    // lives on the tool config (per-instance override). Push it on
    // every dependency change so the caller's /boats list comes from
    // the same router the tool is pointed at. First pass also primes
    // the boat list so the Compose tab can resolve the persisted
    // selected-boat id to a name/LOA before the picker is even opened.
    final boatsService =
        Provider.of<RoutePlannerBoatsService>(context, listen: false);
    // Both `baseUrl =` (on change) and `refreshAllBoats()` call
    // notifyListeners(); running them synchronously here would fire during
    // the build phase (didChangeDependencies) and trip "markNeedsBuild
    // called during build" on the Provider's ListenableBuilder. Defer to
    // after the current frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      boatsService.baseUrl = _routePlannerBaseUrl;
      if (boatsService.boats.isEmpty && !boatsService.loadingBoats) {
        // Full server inventory + ownership oracle. Picker reads the
        // full list; `_submit` uses ownership to pick between boat_id
        // and explicit vessel+polar overrides.
        unawaited(boatsService.refreshAllBoats());
      }
    });
  }

  void _onWeatherDataChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// Builds an XYZ `TileLayer` for one of the raster weather endpoints
  /// (`/wind-heatmap`, `/current-heatmap`, `/roughness`). The URL
  /// template carries `?t=<hour>&v=<nonce>`. `flutter_map` keys its
  /// in-widget tile cache strictly on `urlTemplate` (see
  /// `tile_layer.dart:502-514`) so bumping the nonce is the only way
  /// to force a refetch when the server's rendering changes within
  /// the same hour.
  Widget _weatherRasterTile(String path, int fallbackZoomFloor) {
    final svc = _weatherDataService!;
    final template = svc.heatmapUrlTemplate(path);
    final effectiveFloor = _effectiveMinZoom(path, fallbackZoomFloor);
    return TileLayer(
      key: ValueKey(
          '$path|${svc.cacheNonce}|$effectiveFloor'),
      urlTemplate: template,
      userAgentPackageName: 'org.zennora.zed_display',
      // `minZoom` hides the layer below the user-configurable floor;
      // `minNativeZoom` keeps flutter_map from asking for z<floor tiles
      // (server returns 204 there).
      minZoom: effectiveFloor.toDouble(),
      minNativeZoom: effectiveFloor,
      maxNativeZoom: 16,
      tileProvider: _WeatherTileProvider(
        path: path,
        service: svc,
      ),
      // Crossfade new tiles in over the previous hour's tiles so the
      // player playback reads as a smooth animation rather than a
      // flicker-then-replace step.
      tileDisplay: const TileDisplay.fadeIn(
        duration: Duration(milliseconds: 250),
      ),
    );
  }

  /// Sync the weather-data service's reference time to whatever the
  /// current selection / route / clock implies. Tile layers (raster)
  /// and the tile-aware vector overlays watch the service directly,
  /// so nothing else needs to happen here — no per-camera scheduling.
  ///
  /// Reference-time precedence: weather player offset (when the
  /// player strip is open *and* a time-keyed layer is on) → selected
  /// route waypoint's `time` (scrubbing the field to that hour) → the
  /// planned departure → now.
  void _syncWeatherReferenceTime() {
    final svc = _weatherDataService;
    if (svc == null) return;
    // Player drives the reference time only while it's actually
    // visible AND there's a time-keyed layer to play through. If the
    // last time-keyed layer was just turned off the player offset
    // becomes a stale ghost, so fall through to the regular
    // selection / departure / now precedence in that case.
    if (_playerVisible && _hasTimeKeyedWeatherLayer) {
      // Floor to the UTC hour the URL builder uses so the strip's
      // displayed time and the actually-fetched tiles agree. Without
      // this, `DateTime.now() + offset` carries minutes that the
      // strip would render as e.g. `14:39` while the map fetched the
      // `14:00` forecast.
      final unfloored =
          DateTime.now().add(Duration(hours: _playerOffsetHours));
      final utc = unfloored.toUtc();
      svc.referenceTime =
          DateTime.utc(utc.year, utc.month, utc.day, utc.hour);
      return;
    }
    DateTime? selectedTime;
    final wrResult = _weatherRoutingService?.currentResult;
    final sel = _weatherRouteSelectedIdx;
    if (wrResult != null && sel != null && wrResult.waypoints.isNotEmpty) {
      // The virtual START / END cards (sentinels -1 and
      // waypoints.length) stand in for the user's clicked point that
      // the router relocated to clear water. They don't have their
      // own forecast time on the waypoint list, so anchor them to
      // the first / last real waypoint's time.
      if (sel == -1) {
        selectedTime = wrResult.waypoints.first.time;
      } else if (sel == wrResult.waypoints.length) {
        selectedTime = wrResult.waypoints.last.time;
      } else if (sel >= 0 && sel < wrResult.waypoints.length) {
        selectedTime = wrResult.waypoints[sel].time;
      }
    }
    final dep = _weatherRoutingService?.lastRequest?.departure;
    svc.referenceTime = selectedTime ?? dep ?? DateTime.now();
  }

  // ===== Weather player handlers =====

  void _togglePlayer() {
    setState(() {
      _playerVisible = !_playerVisible;
      if (!_playerVisible) {
        // Closing the player resets the timeline to "now" and
        // hands reference-time control back to the normal
        // selection / departure / now precedence.
        _resetPlayerStateUnsafe();
      }
    });
    _syncWeatherReferenceTime();
  }

  /// Reset every piece of player state to "off". Caller is responsible
  /// for wrapping this in a `setState` (suffix `_Unsafe`).
  void _resetPlayerStateUnsafe() {
    _playerVisible = false;
    _playerDirection = 0;
    _playerOffsetHours = 0;
    _playerTimer?.cancel();
    _playerTimer = null;
    _playerLastAdvance = null;
  }

  /// If toggling a layer just turned off the last time-keyed weather
  /// layer, fully deactivate the player. Without this the
  /// `_playerVisible` flag and the player offset would survive,
  /// causing the next time-keyed layer to come back to a stale
  /// hidden hour. Returns `true` when reset happened so the caller
  /// can also re-sync the weather reference time.
  bool _maybeDeactivatePlayer() {
    if (_hasTimeKeyedWeatherLayer) return false;
    if (!_playerVisible &&
        _playerOffsetHours == 0 &&
        _playerDirection == 0 &&
        _playerTimer == null) {
      return false; // nothing to reset
    }
    setState(_resetPlayerStateUnsafe);
    return true;
  }

  /// Set the player's playback direction. Tapping the same direction
  /// that's already active pauses (toggle behaviour). Tapping the
  /// opposite direction switches without an intermediate pause.
  void _setPlayerDirection(int dir) {
    if (!_playerVisible) return;
    final next = (dir == _playerDirection) ? 0 : dir;
    setState(() {
      _playerDirection = next;
      _playerTimer?.cancel();
      _playerTimer = null;
      if (next != 0) {
        // Reset the hold clock so the very first tick honours the
        // 1 s minimum hold from the moment play started, not from
        // some leftover advance timestamp.
        _playerLastAdvance = DateTime.now();
        _scheduleNextPlayerTick();
      } else {
        _playerLastAdvance = null;
      }
    });
  }

  /// Sum of in-flight tile counts across every currently-enabled
  /// time-keyed layer. Drives the player's tile-aware gating: when
  /// any active layer still has tiles in flight, hold the next
  /// advance until the queue clears (or until the max-hold timeout
  /// fires).
  int _activeWeatherLayersInFlight() {
    final svc = _weatherDataService;
    if (svc == null) return 0;
    var total = 0;
    if (_windBarbsOn) total += svc.inFlightCount('/wind');
    if (_currentsOn) total += svc.inFlightCount('/currents');
    if (_windHeatmapOn) total += svc.inFlightCount('/wind-heatmap');
    if (_currentHeatmapOn) total += svc.inFlightCount('/current-heatmap');
    if (_seaStateOn) total += svc.inFlightCount('/roughness');
    if (_waveHeatmapOn) total += svc.inFlightCount('/wave-heatmap');
    if (_precipHeatmapOn) total += svc.inFlightCount('/precip-heatmap');
    if (_temperatureHeatmapOn) total += svc.inFlightCount('/temperature');
    if (_sstHeatmapOn) total += svc.inFlightCount('/sst');
    return total;
  }

  /// Snapshot of every currently-enabled time-keyed weather layer
  /// for the player strip's status-chip row. Order matches the
  /// canonical layer order so the strip's chip layout doesn't
  /// reshuffle on every toggle.
  List<_WeatherPlayerStripLayer> _playerLayerStatuses() {
    final svc = _weatherDataService;
    if (svc == null) return const [];
    _WeatherPlayerStripLayer entry(
      String path, {
      required IconData icon,
      required String label,
    }) {
      final inFlight = svc.inFlightCount(path);
      final lastErr = svc.tileLastError(path);
      final lastOk = svc.tileLastSuccess(path);
      // `recordTileSuccess` clears `_tileLastError`, so a non-null
      // `lastErr` always reflects the most recent fetch failing.
      final _LayerLoadStatus status;
      if (inFlight > 0) {
        status = _LayerLoadStatus.loading;
      } else if (lastErr != null) {
        status = _LayerLoadStatus.error;
      } else if (lastOk != null) {
        status = _LayerLoadStatus.loaded;
      } else {
        status = _LayerLoadStatus.idle;
      }
      return _WeatherPlayerStripLayer(
        path: path,
        label: label,
        icon: icon,
        status: status,
      );
    }

    return [
      if (_windBarbsOn)
        entry('/wind', icon: Icons.air, label: 'Wind barbs'),
      if (_currentsOn)
        entry('/currents', icon: Icons.waves, label: 'Currents'),
      if (_windHeatmapOn)
        entry('/wind-heatmap',
            icon: Icons.thermostat, label: 'Wind speed'),
      if (_currentHeatmapOn)
        entry('/current-heatmap',
            icon: Icons.water, label: 'Current speed'),
      if (_seaStateOn)
        entry('/roughness',
            icon: Icons.warning_amber, label: 'Sea state'),
      if (_waveHeatmapOn)
        entry('/wave-heatmap',
            icon: Icons.tsunami, label: 'Wave height'),
      if (_precipHeatmapOn)
        entry('/precip-heatmap', icon: Icons.umbrella, label: 'Precip'),
      if (_temperatureHeatmapOn)
        entry('/temperature',
            icon: Icons.thermostat, label: 'Air temp'),
      if (_sstHeatmapOn)
        entry('/sst',
            icon: Icons.water_drop_outlined, label: 'SST'),
    ];
  }

  /// Schedule the next gated tick. Self-rescheduling so the cadence
  /// adapts to network speed: if tiles arrive in 200 ms we poll past
  /// the 1 s minimum and advance; if tiles take 4 s we hold; if
  /// tiles never arrive we force-advance after 5 s.
  void _scheduleNextPlayerTick() {
    _playerTimer?.cancel();
    _playerTimer = null;
    if (!mounted || !_playerVisible || _playerDirection == 0) return;
    _playerTimer = Timer(_playerPollInterval, _maybeAdvancePlayerTick);
  }

  void _maybeAdvancePlayerTick() {
    if (!mounted || !_playerVisible || _playerDirection == 0) return;
    final lastAdvance = _playerLastAdvance ?? DateTime.now();
    final since = DateTime.now().difference(lastAdvance);
    final tilesBusy = _activeWeatherLayersInFlight() > 0;
    // Always honour the visual minimum cadence, even when tiles
    // landed instantly. Without this, a hot disk cache would
    // rattle through hours faster than the eye can read.
    if (since < _playerMinHold) {
      _scheduleNextPlayerTick();
      return;
    }
    // Between min and max hold: advance only when tiles are quiet.
    // After max hold: advance regardless so a stuck tile or dead
    // server can't freeze playback indefinitely.
    if (tilesBusy && since < _playerMaxHold) {
      _scheduleNextPlayerTick();
      return;
    }
    final next = _playerOffsetHours + _playerDirection;
    if (next > _playerMaxOffset || next < _playerMinOffset) {
      // Pause at either end of the forecast envelope.
      setState(() {
        _playerDirection = 0;
        _playerLastAdvance = null;
      });
      return;
    }
    setState(() => _playerOffsetHours = next);
    _playerLastAdvance = DateTime.now();
    _syncWeatherReferenceTime();
    _scheduleNextPlayerTick();
  }

  void _setPlayerOffset(int hours) {
    final clamped = hours.clamp(_playerMinOffset, _playerMaxOffset);
    if (clamped == _playerOffsetHours) return;
    setState(() => _playerOffsetHours = clamped);
    _syncWeatherReferenceTime();
  }

  void _stepPlayer(int delta) {
    if (!_playerVisible) return;
    setState(() {
      _playerDirection = 0;
      _playerTimer?.cancel();
      _playerTimer = null;
      _playerLastAdvance = null;
    });
    _setPlayerOffset(_playerOffsetHours + delta);
  }

  void _resetPlayerToNow() {
    setState(() {
      _playerOffsetHours = 0;
      _playerDirection = 0;
      _playerTimer?.cancel();
      _playerTimer = null;
      _playerLastAdvance = null;
    });
    _syncWeatherReferenceTime();
  }

  /// Single entry point for updating the selected weather-route
  /// waypoint. Clamps the index, pans the camera, and rescrubs the
  /// wind / current layers to the waypoint's forecast time. Pass
  /// `null` to clear the selection.
  void _setSelectedWaypoint(int? idx) {
    final result = _weatherRoutingService?.currentResult;
    int? clamped;
    if (idx != null && result != null && result.waypoints.isNotEmpty) {
      // Index -1 / waypoints.length address the virtual START / END
      // cards — the user's clicked point that the router relocated to
      // clear water. They only exist when that endpoint was actually
      // snapped; otherwise the clamp collapses them back into the
      // real-waypoint range. Note `waypoints.length` (not
      // `coords.length`) is the END sentinel so it can't collide with
      // a real waypoint index when the geometry is simplified.
      final s = result.summary;
      final lo = (s.startSnapDistanceM ?? 0) > 0 ? -1 : 0;
      final hi = (s.endSnapDistanceM ?? 0) > 0
          ? result.waypoints.length
          : result.waypoints.length - 1;
      clamped = idx.clamp(lo, hi);
    }
    if (_weatherRouteSelectedIdx != clamped) {
      setState(() => _weatherRouteSelectedIdx = clamped);
    }
    if (clamped != null && result != null && _mapReady) {
      final s = result.summary;
      List<double>? c;
      if (clamped == -1) {
        c = s.startOriginal;
      } else if (clamped == result.waypoints.length) {
        c = s.endOriginal;
      } else {
        // Pan to the *waypoint* position (not the simplified-geometry
        // coord at the same index, which may not align 1:1 with the
        // waypoint list).
        final wp = result.waypoints[clamped];
        c = [wp.lon, wp.lat];
      }
      if (c != null) {
        _mapController.move(LatLng(c[1], c[0]), _mapController.camera.zoom);
      }
    }
    _syncWeatherReferenceTime();
  }

  void _onWeatherRoutingChanged() {
    if (!mounted) return;
    // Drop a stale selection when the service clears its result — the
    // floating popover and the overlay both derive their visibility
    // from this flag, and nothing else nulls it.
    final hasResult =
        _weatherRoutingService?.currentResult?.isNotEmpty ?? false;
    if (!hasResult && _weatherRouteSelectedIdx != null) {
      _weatherRouteSelectedIdx = null;
    }
    // Tabula-rasa hook for panel-driven `clearAll`. The panel sits in
    // a bottom sheet and can't reach this widget's local state, so
    // when the service goes fully empty (no result, no pins, no
    // vias) we mirror that locally: drop the waypoint selection and
    // close the compose popover. Idempotent — re-firing on an
    // already-empty service is a no-op.
    final svc = _weatherRoutingService;
    if (svc != null &&
        svc.currentResult == null &&
        svc.plannedStart == null &&
        svc.plannedEnd == null &&
        svc.plannedVias.isEmpty) {
      if (_composePopoverOpen) {
        _composePopoverOpen = false;
      }
    }
    setState(() {});
    // Reference time may have shifted (new route, different departure,
    // or cleared selection) — push it into the data service. Tile
    // layers self-fetch when the hour changes.
    _syncWeatherReferenceTime();
  }

  bool _aisSubscribed = false;
  void _ensureAisSubscribed() {
    if (_aisSubscribed || !widget.signalKService.isConnected) return;
    _aisSubscribed = true;
    widget.signalKService.loadAndSubscribeAISVessels();
  }

  @override
  void didUpdateWidget(covariant ChartPlotterV3Tool oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The dashboard reuses our State across config edits (keyed by
    // toolId), so any change that affects the tile proxy — config
    // edits, or a swapped-in SignalKService instance — needs a fresh
    // push. `_configureTileServer` self-throttles on its cached
    // last-applied tuple, so calling it unconditionally is cheap.
    if (oldWidget.signalKService != widget.signalKService) {
      oldWidget.signalKService.removeListener(_configureTileServer);
      widget.signalKService.addListener(_configureTileServer);
    }
    _configureTileServer();
  }

  @override
  void dispose() {
    widget.signalKService.removeListener(_configureTileServer);
    _routePollTimer?.cancel();
    _vesselTimer?.cancel();
    _playerTimer?.cancel();
    _stopArrivalMonitor();
    widget.signalKService.metadataStore
        .removeListener(_onMetadataStoreChanged);
    _tileManager?.removeListener(_onTileManagerChanged);
    _tileManager?.dispose();
    _weatherRoutingService?.removeListener(_onWeatherRoutingChanged);
    _weatherDataService?.removeListener(_onWeatherDataChanged);
    _weatherDataService?.tileStatusNotifier
        .removeListener(_onWeatherDataChanged);
    _weatherDataService?.dispose();
    _ownVesselTick.dispose();
    super.dispose();
  }

  void _onTileManagerChanged() {
    if (mounted) setState(() {});
  }

  /// Arrival monitor wiring matches V1 (chart_plotter_tool.dart:463-494).
  /// On each arrival, V1 pops a countdown confirmation: the last
  /// waypoint just reports; intermediate waypoints offer next-waypoint
  /// auto-advance.
  void _startArrivalMonitor() {
    _stopArrivalMonitor();
    _arrivalMonitor = RouteArrivalMonitor(signalKService: widget.signalKService);
    _arrivalSub = _arrivalMonitor!.arrivalStream.listen(_onWaypointArrival);
    _arrivalMonitor!.start();
  }

  void _stopArrivalMonitor() {
    _arrivalSub?.cancel();
    _arrivalSub = null;
    _arrivalMonitor?.dispose();
    _arrivalMonitor = null;
  }

  void _onWaypointArrival(RouteArrivalEvent event) {
    if (!mounted || _routeCoords == null) return;
    if (event.isLastWaypoint) {
      showCountdownConfirmation(
        context: context,
        title: 'Final Waypoint Reached',
        action: 'End Route',
      );
    } else {
      showCountdownConfirmation(
        context: context,
        title:
            'Waypoint ${event.pointIndex + 1}/${event.pointTotal} Reached',
        action: 'Next Waypoint',
      ).then((confirmed) {
        if (confirmed == true) _advanceWaypoint();
      });
    }
  }

  Future<void> _advanceWaypoint() async {
    final idx = _routePointIndex;
    final total = _routePointTotal;
    if (idx == null || total == null) return;
    final nextIdx = idx + 1;
    if (nextIdx >= total) return;
    try {
      await widget.signalKService.setActiveRoutePointIndex(nextIdx);
      await _pollCourseAPI();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Advance failed: $e')));
      }
    }
  }

  void _refreshVessel() {
    // Piggy-back on the tick to retry subscribe; initState can run
    // before the connection comes up, in which case the first call
    // is a no-op and this finally fires on a later tick.
    _ensureAisSubscribed();

    double? getNum(String path) {
      final d = widget.signalKService.getValue(path);
      return d?.value is num ? (d!.value as num).toDouble() : null;
    }

    final posData = widget.signalKService.getValue('navigation.position');
    double? lat, lon;
    if (posData?.value is Map) {
      final pos = posData!.value as Map;
      lat = (pos['latitude'] as num?)?.toDouble();
      lon = (pos['longitude'] as num?)?.toDouble();
    }
    final heading = getNum('navigation.headingTrue');
    final cog = getNum('navigation.courseOverGroundTrue');
    final sog = getNum('navigation.speedOverGround');

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // AIS refresh is independent of own-vessel presence: a receive-
    // only chartplotter (handheld with no GPS) still wants to see
    // traffic. Only own-vessel state is gated on a valid fix below.
    // Throttled to 1 s per V1 (chart_plotter_tool.dart:307-309).
    if (_aisEnabled && mounted && nowMs - _lastAisPushMs >= 1000) {
      _lastAisPushMs = nowMs;
      setState(() {
        _refreshAisVessels();
        _refreshRulerSnaps();
      });
    }

    if (lat == null || lon == null) {
      // GPS dropped after we had a fix. Clear the cached own-ship
      // state so the AIS list / detail math don't keep computing
      // distance / CPA against a stale position. `_ownVesselTick`
      // wakes the AIS list sheet so its rows reflow immediately.
      final hadFix = _ownLat != null ||
          _ownLon != null ||
          _ownHeading != null ||
          _ownCog != null ||
          _ownSog != null;
      if (hadFix && mounted) {
        setState(() {
          _ownLat = null;
          _ownLon = null;
          _ownHeading = null;
          _ownCog = null;
          _ownSog = null;
          // A 'self'-snapped ruler endpoint is pinned to own position;
          // clearing the cached fix means it needs re-evaluation too.
          _refreshRulerSnaps();
        });
        _ownVesselTick.value++;
      }
      return;
    }
    final changed = lat != _ownLat ||
        lon != _ownLon ||
        heading != _ownHeading ||
        cog != _ownCog ||
        sog != _ownSog;
    if (!changed) return;
    // Throttle vessel state updates to V1's 500 ms cadence
    // (chart_plotter_tool.dart:297-299) so rapid WS deltas don't
    // cause setState-per-delta churn.
    if (nowMs - _lastVesselPushMs < 500) return;
    _lastVesselPushMs = nowMs;
    if (mounted) {
      setState(() {
        _ownLat = lat;
        _ownLon = lon;
        _ownHeading = heading;
        _ownCog = cog;
        _ownSog = sog;
        _appendTrailPoint(lat!, lon!);
        if (_recordingTrack) _appendRecordedPoint(lat, lon);
        _refreshRulerSnaps();
      });
      // Wake the AIS list sheet so distance / CPA / TCPA recompute
      // against the new fix without waiting for the next AIS delta.
      _ownVesselTick.value++;
    }
    if (_mapReady) {
      // One-shot initial center on the first fix. After this the user
      // can opt into continuous follow via the control-bar toggle.
      if (!_didInitialCenter) {
        _didInitialCenter = true;
        _mapController.move(LatLng(lat, lon), _mapController.camera.zoom);
      }
      // fitCamera handles centering when auto-zoom is on; only fall
      // back to a bare move when auto-zoom is disabled by the user.
      if (_autoFollow) {
        if (_autoZoom) {
          _applyAutoZoom();
        } else {
          _mapController.move(LatLng(lat, lon), _mapController.camera.zoom);
        }
      }
      if (_viewMode == _ViewMode.headingUp && heading != null) {
        final rotDeg = -heading * 180 / math.pi;
        if ((rotDeg - _mapController.camera.rotation).abs() > 0.5) {
          _mapController.rotate(rotDeg);
        }
      }
    }
  }

  /// Snapshot the AIS registry into a light-weight renderable list.
  /// Projections are computed here so the painter never touches the
  /// math in paint(). Runs inside setState — caller handles mounting.
  void _refreshAisVessels() {
    final registry = widget.signalKService.aisVesselRegistry.vessels;
    final out = <_AisRenderable>[];
    final now = DateTime.now();
    for (final v in registry.values) {
      if (!v.hasPosition) continue;
      if (_aisActiveOnly) {
        if (v.aisStatus == 'lost' || v.aisStatus == 'remove') continue;
        if (now.difference(v.lastSeen).inMinutes >= 10) continue;
      }
      final lat = v.latitude!;
      final lon = v.longitude!;
      final sog = v.sogMs ?? 0.0;
      final kind = _aisKindFor(v.navState, sog);
      out.add(_AisRenderable(
        id: v.vesselId,
        position: LatLng(lat, lon),
        // Freeboard rotates by heading when known, otherwise COG. Zero
        // is an acceptable fallback — the symbol stays upright.
        bearingRadians: v.headingTrueRad ?? v.cogRad ?? 0.0,
        name: v.name ?? '',
        color: ship_type.shipTypeColor(v.aisShipType, aisClass: v.aisClass),
        alpha: _aisFreshnessAlpha(v.aisStatus, v.lastSeen),
        stale: _aisIsStale(v.aisStatus, v.lastSeen),
        kind: kind,
        projections: _aisShowPaths
            ? _projectAhead(lat, lon, v.cogRad, sog)
            : const [],
      ));
    }
    _aisVessels = out;
    // If the selected vessel just aged out / lost position / was
    // filtered by `_aisActiveOnly`, clear the ring — there's
    // nothing under it to draw against any more.
    if (_selectedAisId != null &&
        out.every((r) => r.id != _selectedAisId)) {
      _selectedAisId = null;
    }
  }

  // Ship-type / AIS-class palette lives in `lib/utils/ship_type_utils.dart`
  // as `ship_type.shipTypeColor` — single source of truth shared with the
  // AIS polar chart widget. No inline copy here.

  double _aisFreshnessAlpha(String? status, DateTime? lastSeen) {
    if (status == 'confirmed') return 1.0;
    if (status == 'unconfirmed') return 0.5;
    if (status == 'lost' || status == 'remove') return 0.2;
    if (lastSeen == null) return 0.2;
    final ageMin = DateTime.now().difference(lastSeen).inSeconds / 60.0;
    if (ageMin < 3) return 1.0;
    if (ageMin < 10) return 0.7;
    return 0.3;
  }

  bool _aisIsStale(String? status, DateTime? lastSeen) {
    if (status == 'lost' || status == 'remove') return true;
    if (lastSeen == null) return true;
    return DateTime.now().difference(lastSeen).inMinutes >= 10;
  }

  _AisKind _aisKindFor(String? navState, double sogMs) {
    if (navState == 'moored') return _AisKind.moored;
    if (navState == 'anchored') return _AisKind.anchored;
    if (sogMs < 0.1) return _AisKind.slow;
    return _AisKind.moving;
  }

  /// Adapter for the shared AIS list: map this app's `AISVesselRegistry`
  /// entries to `AisVesselListItem`s, applying the same active-only
  /// filter the map renderer uses so the two views stay consistent.
  /// Distance + CPA / TCPA are computed here against the own vessel
  /// kinematics; rad → deg for COG / heading happens at the boundary
  /// so the row only deals in display units.
  List<ais_list.AisVesselListItem> _buildAisListItems() {
    final registry = widget.signalKService.aisVesselRegistry.vessels;
    final now = DateTime.now();
    final items = <ais_list.AisVesselListItem>[];
    for (final v in registry.values) {
      if (!v.hasPosition) continue;
      if (_aisActiveOnly) {
        if (v.aisStatus == 'lost' || v.aisStatus == 'remove') continue;
        if (now.difference(v.lastSeen).inMinutes >= 10) continue;
      }
      // Without an own-vessel fix, distance / CPA / TCPA are undefined.
      // Pass nulls through; the shared list hides the distance cell and
      // sorts the row to the bottom of Nearby. `_ownVesselTick` will
      // bump the sheet on the next fix so the row reflows naturally.
      final dist = (_ownLat != null && _ownLon != null)
          ? _haversineMeters(_ownLat!, _ownLon!, v.latitude!, v.longitude!)
          : null;
      final cpa = ais_list.computeCpa(
        ownLat: _ownLat,
        ownLon: _ownLon,
        ownCogRad: _ownCog,
        ownSogMs: _ownSog,
        otherLat: v.latitude,
        otherLon: v.longitude,
        otherCogRad: v.cogRad,
        otherSogMs: v.sogMs,
      );
      items.add(ais_list.AisVesselListItem(
        mmsi: v.vesselId,
        name: v.name,
        aisShipType: v.aisShipType,
        aisClass: v.aisClass,
        aisStatus: v.aisStatus,
        navState: v.navState,
        // Raw SI radians; the list converts + symbols via formatAngle.
        headingTrue: v.headingTrueRad,
        cog: v.cogRad,
        sogRaw: v.sogMs,
        distance: dist,
        cpa: cpa?.cpaM,
        tcpa: cpa?.tcpaS,
        timestamp: v.lastSeen,
      ));
    }
    return items;
  }

  /// Equirectangular-tangent haversine — good to a few cm at AIS
  /// ranges. Same shape used by the route planner's distance maths.
  /// Returns a `(lon, lat) → Offset` projector that mirrors the route
  /// painter's camera-copy longitude unwrap. Hit-testing on routes
  /// that cross ±180° MUST use this — a canonical projection puts the
  /// visible waypoints a world-width away from where the tap lands.
  /// `camLon` and `originPx` are captured once so the per-point
  /// projection in tight loops stays cheap. Shared by `_onMapTap`'s
  /// route-waypoint hit-test and the add-waypoint nearest-segment
  /// search.
  Offset Function(double lon, double lat) _unwrappedProjector(
      MapCamera camera) {
    final camLon = camera.center.longitude;
    final originPx = camera.pixelOrigin;
    return (lon, lat) {
      final u = unwrapLonNear([lon, lat], camLon)!;
      return camera.projectAtZoom(LatLng(u[1], u[0])) - originPx;
    };
  }

  static double _haversineMeters(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  /// Bring up the AIS vessel list as a draggable bottom sheet. Lives
  /// inside the chart plotter (rather than a separate tool) because
  /// the list is a peer to the existing AIS toggles and inherits the
  /// same `_aisActiveOnly` gate. Rebuilds the item list each time the
  /// registry notifies so a new sentence on the wire ticks the rows.
  void _openAisList(BuildContext ctx) {
    // Distance / speed / angle formatters reuse the same MetadataStore
    // category lookups the rest of the chart plotter uses — keeps
    // units consistent with the HUD and the scale bar.
    final store = widget.signalKService.metadataStore;
    final distMd = store.getByCategory('distance');
    final speedMd = store.getByCategory('speed');
    final angleMd = store.getByCategory('angle');
    String formatDistance(double meters, {int decimals = 1}) {
      if (distMd == null) return '${meters.toStringAsFixed(decimals)} m';
      final v = distMd.convert(meters);
      if (v == null) return '${meters.toStringAsFixed(decimals)} m';
      return '${v.toStringAsFixed(decimals)} ${distMd.symbol ?? 'm'}';
    }

    String formatSpeed(double ms) {
      if (speedMd == null) return '${ms.toStringAsFixed(1)} m/s';
      final v = speedMd.convert(ms);
      if (v == null) return '${ms.toStringAsFixed(1)} m/s';
      return '${v.toStringAsFixed(1)} ${speedMd.symbol ?? 'm/s'}';
    }

    // Raw SI radians in → display angle + symbol out, honouring the
    // user's angle preset. Falls back to degrees only when the preset
    // hasn't seeded angle metadata yet (degrees is the COG default).
    String formatAngle(double radians) {
      final v = angleMd?.convert(radians);
      if (v == null) return '${(radians * 180 / math.pi).toStringAsFixed(0)}°';
      return '${v.toStringAsFixed(0)}${angleMd?.symbol ?? '°'}';
    }

    CpaAlertService? cpaService;
    try {
      cpaService = ctx.read<CpaAlertService>();
    } catch (_) {
      // No CPA service in the tree — the list's chip falls back to a
      // neutral palette via the shared helper's default config.
    }

    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          // expand: false leaves the modal barrier exposed above the sheet
          // so tap-outside dismisses (default true covers the barrier).
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          minChildSize: 0.15,
          snap: true,
          snapSizes: const [0.6, 0.92],
          // Flick all the way down to dismiss (matches the other sheets);
          // without this the sheet just snaps to its min and gets stuck.
          shouldCloseOnMinExtent: true,
          builder: (_, scroll) {
            return Container(
              decoration: const BoxDecoration(
                color: AppColors.cardBackgroundDark,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  // Grab handle.
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 8, bottom: 4),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: Listenable.merge([
                        widget.signalKService.aisVesselRegistry,
                        _ownVesselTick,
                      ]),
                      builder: (_, _) => ais_list.AisVesselList(
                        vessels: _buildAisListItems(),
                        lastPositionUpdate: null,
                        cpaAlertService: cpaService,
                        colorByShipType: true,
                        formatDistance: formatDistance,
                        formatSpeed: formatSpeed,
                        formatAngle: formatAngle,
                        onTap: (vesselId) {
                          Navigator.of(sheetCtx).pop();
                          if (!mounted) return;
                          setState(() => _selectedAisId = vesselId);
                          AISVesselDetailSheet.show(
                            context,
                            signalKService: widget.signalKService,
                            vesselId: vesselId,
                            ownLat: _ownLat,
                            ownLon: _ownLon,
                            ownCogRad: _ownCog,
                            ownSogMs: _ownSog,
                          );
                        },
                        onLongPress: (vesselId, displayName) {
                          Navigator.of(sheetCtx).pop();
                          if (!mounted) return;
                          _navigateToFindHomeForVessel(
                              vesselId, displayName);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Mirror of the polar chart's `_navigateToFindHome`: hand off
  /// the vessel to the Find Home tool and switch screens. Silent
  /// no-op when the user doesn't have a Find Home tool on their
  /// dashboard.
  void _navigateToFindHomeForVessel(String vesselId, String displayName) {
    try {
      final dashService = context.read<DashboardService>();
      final findHomeScreen =
          dashService.findScreenWithToolType('find_home');
      if (findHomeScreen == null) return;
      final targetService = context.read<FindHomeTargetService>();
      targetService.setAisTarget(vesselId, displayName);
      dashService.setActiveScreen(findHomeScreen.$1);
    } catch (_) {
      // Either service missing from the Provider tree — no-op rather
      // than crashing the long-press handler.
    }
  }

  /// Great-circle projected positions at 30s / 1m / 15m / 30m.
  /// Matches V1 so the time bands on the chart read the same as the
  /// AIS detail sheet's intercept numbers.
  List<LatLng> _projectAhead(
      double lat, double lon, double? cogRad, double sogMs) {
    if (sogMs < 0.1 || cogRad == null) return const [];
    const intervals = [30.0, 60.0, 900.0, 1800.0];
    final out = <LatLng>[];
    for (final t in intervals) {
      final d = sogMs * t;
      final lat1 = lat * math.pi / 180;
      final lon1 = lon * math.pi / 180;
      final a = d / 6371000.0;
      final lat2 = math.asin(
        math.sin(lat1) * math.cos(a) +
            math.cos(lat1) * math.sin(a) * math.cos(cogRad),
      );
      final lon2 = lon1 +
          math.atan2(
            math.sin(cogRad) * math.sin(a) * math.cos(lat1),
            math.cos(a) - math.sin(lat1) * math.sin(lat2),
          );
      out.add(LatLng(lat2 * 180 / math.pi, lon2 * 180 / math.pi));
    }
    return out;
  }

  /// V1's trail rules, ported verbatim (chart_plotter_tool.dart:332-356):
  ///   • push throttle: 2 000 ms between samples
  ///   • movement threshold: <5 m (metres² < 25 via equirectangular)
  ///   • retention: trailMinutes (default 10)
  void _appendTrailPoint(double lat, double lon) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastTrailPushMs < 2000) return;
    if (_trailPoints.isNotEmpty) {
      final last = _trailPoints.last;
      final dx = (lon - last.longitude) *
          math.cos(lat * math.pi / 180) *
          111320;
      final dy = (lat - last.latitude) * 111320;
      if (dx * dx + dy * dy < 25) return; // <5m
    }
    _lastTrailPushMs = nowMs;
    _trailPoints.add(LatLng(lat, lon));
    _trailTimestamps.add(nowMs);
    final cutoff = nowMs - _trailMinutes * 60000;
    while (_trailTimestamps.isNotEmpty && _trailTimestamps.first < cutoff) {
      _trailTimestamps.removeAt(0);
      _trailPoints.removeAt(0);
    }
  }

  /// Append a fix to the voyage-recording buffer. Movement-thresholded
  /// (<5 m skipped, same planar approx as `_appendTrailPoint`) to bound
  /// the buffer on a long voyage; unlike the display trail there is no
  /// time-window cutoff, so the whole session is retained.
  void _appendRecordedPoint(double lat, double lon) {
    if (_recordedTrack.length >= _maxRecordedTrackPoints) {
      if (!_recordedTrackFullWarned) {
        _recordedTrackFullWarned = true;
        _showPlotterSnack('Track recording buffer full — save to continue');
      }
      return; // stop appending; preserve the recorded track for saving
    }
    if (_recordedTrack.isNotEmpty) {
      final last = _recordedTrack.last;
      final dx =
          (lon - last.longitude) * math.cos(lat * math.pi / 180) * 111320;
      final dy = (lat - last.latitude) * 111320;
      if (dx * dx + dy * dy < 25) return; // <5 m
    }
    _recordedTrack.add(LatLng(lat, lon));
  }

  /// Toggle voyage track recording. Starting clears the buffer and seeds
  /// it with the current fix; stopping with ≥2 points prompts to save the
  /// track as a SignalK `tracks` resource.
  Future<void> _toggleTrackRecording() async {
    if (!_recordingTrack) {
      // A non-empty buffer left over from a prior session that was never
      // saved (cancelled/failed save). Don't silently drop it — let the user
      // save it, discard it, or back out of starting a new recording.
      if (_recordedTrack.length >= 2) {
        final action = await _confirmDiscardRecordedTrack();
        if (action == null) return; // cancel — leave everything as-is
        if (action == _UnsavedTrackAction.save) {
          final saved = await _saveRecordedTrack();
          if (!saved) return; // save cancelled/failed — keep the buffer
        }
        // save-succeeded or explicit discard → fall through and start fresh
      }
      if (!mounted) return;
      setState(() {
        _recordingTrack = true;
        _recordedTrack.clear();
        _recordedTrackFullWarned = false;
        if (_ownLat != null && _ownLon != null) {
          _recordedTrack.add(LatLng(_ownLat!, _ownLon!));
        }
      });
      _showPlotterSnack('Recording track…');
      return;
    }
    setState(() => _recordingTrack = false);
    if (_recordedTrack.length < 2) {
      _showPlotterSnack('Track too short to save');
      return;
    }
    await _saveRecordedTrack();
  }

  /// Prompt the user about an unsaved recorded-track buffer left over from a
  /// previous session. Returns the chosen action, or null if cancelled.
  Future<_UnsavedTrackAction?> _confirmDiscardRecordedTrack() {
    return showDialog<_UnsavedTrackAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved track'),
        content: Text(
          'A recorded track with ${_recordedTrack.length} points has not been '
          'saved. Save it before starting a new recording, or discard it?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _UnsavedTrackAction.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _UnsavedTrackAction.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  /// Save the recorded voyage as a SignalK `tracks` resource
  /// (MultiLineString), mirroring the Historical Data Explorer's
  /// `_saveAsTrack` shape.
  /// Returns true only when the save actually succeeds. The recorded buffer is
  /// retained on cancel/failure so it can be retried (it's cleared only on a
  /// successful save, or via an explicit discard when starting a new recording).
  Future<bool> _saveRecordedTrack() async {
    final points = List<LatLng>.from(_recordedTrack);
    if (points.length < 2) return false;
    final name =
        await _promptResourceName('Save Track', 'Track ${_resourceStamp()}');
    if (name == null) return false; // cancelled — keep the buffer
    final coordinates = points.map((p) => [p.longitude, p.latitude]).toList();
    final data = {
      'feature': {
        'type': 'Feature',
        'geometry': {
          'type': 'MultiLineString',
          'coordinates': [coordinates],
        },
        'properties': {'name': name, 'description': ''},
        'id': '',
      },
    };
    bool ok = false;
    try {
      ok = await widget.signalKService
          .putResource('tracks', const Uuid().v4(), data);
    } catch (e) {
      if (kDebugMode) print('Save track error: $e');
    }
    if (!mounted) return ok;
    if (ok) {
      _recordedTrack.clear(); // saved → safe to drop the buffer
      _showPlotterSnack('Track saved: $name (${coordinates.length} pts)');
    } else {
      _showPlotterSnack('Track not saved — kept; tap Record to retry or discard');
    }
    return ok;
  }

  /// Save the current weather-router result's turn waypoints as a SignalK
  /// `routes` resource (LineString), mirroring the Historical Data
  /// Explorer's `_saveAsRoute` shape so it appears in the route manager
  /// and can be activated.
  Future<void> _saveWeatherRouteAsRoute() async {
    final result = _weatherRoutingService?.currentResult;
    if (result == null || result.waypoints.length < 2) {
      _showPlotterSnack('No weather route to save');
      return;
    }
    final name = await _promptResourceName(
        'Save as Route', 'Weather route ${_resourceStamp()}');
    if (name == null) return;
    final wps = result.waypoints;
    final coordinates = wps.map((w) => [w.lon, w.lat]).toList();
    final distM =
        trackDistanceMeters(wps.map((w) => LatLng(w.lat, w.lon)).toList());
    final data = {
      'name': name,
      'description': '',
      'distance': distM.round(),
      'feature': {
        'type': 'Feature',
        'geometry': {'type': 'LineString', 'coordinates': coordinates},
        'properties': {
          'coordinatesMeta': List.generate(
            coordinates.length,
            (i) => {'name': 'WPT ${i + 1}'},
          ),
        },
        'id': '',
      },
    };
    bool ok = false;
    try {
      ok = await widget.signalKService
          .putResource('routes', const Uuid().v4(), data);
    } catch (e) {
      if (kDebugMode) print('Save route error: $e');
    }
    if (!mounted) return;
    _showPlotterSnack(ok
        ? 'Route saved: $name (${coordinates.length} waypoints, '
            '${metersToNM(distM).toStringAsFixed(1)} NM)'
        : 'Failed to save route');
  }

  /// Prompt for a resource name with a sensible default. Returns the
  /// trimmed name, or null if cancelled / left empty.
  Future<String?> _promptResourceName(String title, String defaultName) async {
    final controller = TextEditingController(text: defaultName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return null;
    return name;
  }

  /// Local timestamp `YYYY-MM-DD HH:MM` for default resource names.
  String _resourceStamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)} '
        '${two(n.hour)}:${two(n.minute)}';
  }

  /// Brief snackbar helper for plotter resource actions.
  void _showPlotterSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _pollCourseAPI() async {
    if (!mounted) return;
    try {
      final data = await widget.signalKService.getCourseInfo();
      if (data == null) return;
      final activeRoute = data['activeRoute'] as Map<String, dynamic>?;
      if (activeRoute != null) {
        final href = activeRoute['href'] as String?;
        final newIndex = activeRoute['pointIndex'] as int?;
        final newTotal = activeRoute['pointTotal'] as int?;
        final newReversed = activeRoute['reverse'] == true;
        final hrefChanged = href != null && href != _activeRouteHref;
        if (hrefChanged) {
          _activeRouteHref = href;
          await _fetchRoute(href);
          _startArrivalMonitor();
        }
        if (mounted) {
          setState(() {
            _routePointIndex = newIndex;
            _routePointTotal = newTotal;
            _routeReversed = newReversed;
          });
        }
      } else if (_activeRouteHref != null) {
        _stopArrivalMonitor();
        if (mounted) {
          setState(() {
            _activeRouteHref = null;
            _routeCoords = null;
            _waypointNames = null;
            _routePointIndex = null;
            _routePointTotal = null;
            _routeReversed = false;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchRoute(String href) async {
    final routeId = href.split('/').last;
    final data = await widget.signalKService.getResource('routes', routeId);
    if (data == null) return;
    final feature = data['feature'] as Map?;
    final geometry = feature?['geometry'] as Map?;
    final coords = (geometry?['coordinates'] as List?)
        ?.map<List<double>>(
            (c) => [(c[0] as num).toDouble(), (c[1] as num).toDouble()])
        .toList();
    final meta = (feature?['properties'] as Map?)?['coordinatesMeta'] as List?;
    final names = meta?.map<String>((m) => (m['name'] as String?) ?? '').toList();
    if (mounted) {
      setState(() {
        _routeCoords = coords;
        _waypointNames = names;
      });
    }
  }

  String? get _activeRouteId => _activeRouteHref?.split('/').last;

  Future<void> _activateRoute(String routeId, {bool reverse = false}) async {
    try {
      await widget.signalKService.activateRoute(routeId, reverse: reverse);
      await _pollCourseAPI();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Activate failed: $e')));
      }
    }
  }

  Future<void> _reverseRoute() async {
    try {
      await widget.signalKService.reverseActiveRoute();
      await _skipToWaypoint(0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Reverse failed: $e')));
      }
    }
  }

  Future<void> _clearCourse() async {
    try {
      await widget.signalKService.clearCourse();
      await _pollCourseAPI();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Clear failed: $e')));
      }
    }
  }

  Future<void> _skipToWaypoint(int pointIndex) async {
    try {
      await widget.signalKService.setActiveRoutePointIndex(pointIndex);
      await _pollCourseAPI();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Skip failed: $e')));
      }
    }
  }

  Future<void> _saveRouteToServer() async {
    final routeId = _activeRouteId;
    if (routeId == null || _routeCoords == null) return;
    final routeData = {
      'feature': {
        'type': 'Feature',
        'geometry': {
          'type': 'LineString',
          'coordinates': _routeCoords,
        },
        'properties': {
          'coordinatesMeta':
              _waypointNames?.map((n) => {'name': n}).toList() ?? [],
        },
      },
    };
    await widget.signalKService.putResource('routes', routeId, routeData);
  }

  /// V1's tap routing priority (chart_webview.dart:1020-1138):
  ///   1. Waypoint (small — precise hit radius ~14 px)
  ///   2. AIS vessel (20 px — sprite target)
  ///   3. S-57 feature (30 px, grouped within 30 px, priority-sorted)
  /// Tap halo feedback is painted for 2 s regardless.
  void _onMapTap(TapPosition tapPosition, LatLng latLng) {
    _showTapHalo(latLng);

    final camera = _mapController.camera;
    final tapScreen = camera.latLngToScreenOffset(latLng);

    // Route hit-testing must use the SAME camera-copy longitude unwrap
    // the route painters use (`unwrapLonForCamera`). Otherwise, on a
    // route crossing ±180°, the visible waypoints (drawn in the
    // camera's world copy) sit a world-width away from where canonical
    // projection looks, making them untappable / picking the wrong
    // insert segment. (AIS / S-57 hit-tests below keep the plain
    // canonical `tapScreen` — they aren't camera-unwrapped on the
    // render side either.)
    final scrUnwrapped = _unwrappedProjector(camera);
    final tapPxU = scrUnwrapped(latLng.longitude, latLng.latitude);

    // Weather-route waypoints take priority when visible — they sit on
    // top of the SignalK route overlay in the paint stack, so the tap
    // order must match.
    final wrResult = _weatherRoutingService?.currentResult;
    if (_weatherRoutingEnabled && wrResult != null && wrResult.isNotEmpty) {
      final idx = hitTestWeatherRouteWaypoint(
        result: wrResult,
        camera: camera,
        tap: latLng,
      );
      if (idx != null) {
        _setSelectedWaypoint(idx);
        return;
      }
      // Snap pins — the green S / red E markers sit at the user's
      // clicked point (`*_original`) when the router had to relocate
      // that endpoint; tapping one selects its virtual card.
      const snapPinHitPx = 14.0;
      final s = wrResult.summary;
      bool nearLonLat(List<double>? lonLat) {
        if (lonLat == null) return false;
        final px = scrUnwrapped(lonLat[0], lonLat[1]);
        return (px - tapPxU).distanceSquared <=
            snapPinHitPx * snapPinHitPx;
      }

      if ((s.startSnapDistanceM ?? 0) > 0 && nearLonLat(s.startOriginal)) {
        _setSelectedWaypoint(-1);
        return;
      }
      if ((s.endSnapDistanceM ?? 0) > 0 && nearLonLat(s.endOriginal)) {
        _setSelectedWaypoint(wrResult.waypoints.length);
        return;
      }
    }

    final coords = _routeCoords;
    if (coords != null) {
      const hitRadius = 14.0;
      for (var i = 0; i < coords.length; i++) {
        final wp = scrUnwrapped(coords[i][0], coords[i][1]);
        if ((wp - tapPxU).distanceSquared <= hitRadius * hitRadius) {
          showWaypointEditDialog(
            context,
            index: i,
            routeCoords: coords,
            waypointNames: _waypointNames,
            onChanged: () {
              if (mounted) setState(() {});
            },
            saveRouteToServer: _saveRouteToServer,
          );
          return;
        }
      }
    }

    // AIS hit-test — if a vessel is within 20 px of the tap, mark
    // it selected (drives the persistent 16 px ring), open the
    // detail sheet, and short-circuit before chart-feature hit-
    // testing. Selection persists after the sheet closes; clears
    // when the user taps an empty area of the chart (handled below).
    if (_aisEnabled) {
      const aisHitRadius = 20.0;
      for (final v in _aisVessels) {
        final p = camera.latLngToScreenOffset(v.position);
        if ((p - tapScreen).distanceSquared <=
            aisHitRadius * aisHitRadius) {
          setState(() => _selectedAisId = v.id);
          AISVesselDetailSheet.show(
            context,
            signalKService: widget.signalKService,
            vesselId: v.id,
            ownLat: _ownLat,
            ownLon: _ownLon,
            ownCogRad: _ownCog,
            ownSogMs: _ownSog,
          );
          return;
        }
      }
    }

    // Tap landed outside any AIS vessel — clear the selection ring
    // before the chart-feature popover takes over. Without this,
    // the ring would stay around even after the user has clearly
    // moved on to a chart feature.
    if (_selectedAisId != null) {
      setState(() => _selectedAisId = null);
    }

    _showFeaturePopoverForTap(latLng, tapScreen);
  }

  /// 2-second yellow tap halo, parity with V1 (chart_webview.dart:1020-1032).
  void _showTapHalo(LatLng latLng) {
    setState(() => _tapHalo = latLng);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _tapHalo == latLng) {
        setState(() => _tapHalo = null);
      }
    });
  }

  /// Hit-test every parsed feature against the tap within a 30 px
  /// tolerance. Clickable layers are the same 31-entry list V1 uses
  /// (chart_webview.dart:1003-1015). Results are grouped by spatial
  /// proximity (30 px), each group sorted by display priority and
  /// geometry kind, then structures-before-equipment within the
  /// winning group.
  void _showFeaturePopoverForTap(LatLng tap, Offset tapScreen) {
    const hitRadiusPx = 30.0;
    const groupRadiusPx = 30.0;
    final camera = _mapController.camera;

    // Active-zoom-only hit-test. Cross-zoom retention keeps tiles at
    // z±1 in the cache as fallback fill for the painter, but tapping
    // should match what the user perceives as "the chart" — the active
    // layer on top. Iterating all retained tiles would surface every
    // feature 3× (one per retained zoom).
    final activeZ = camera.zoom.round().clamp(9, 16);
    final hits = <_TappedFeature>[];
    // Dedup signature → already-added flag. Same real-world feature can
    // appear in N adjacent tiles (MVT splits long lines / large polygons
    // at tile boundaries and re-emits the attributes per tile). Without
    // this we'd see N identical entries in the popover.
    final seenSig = <String>{};
    final tileMap = _tileManager?.tiles ?? const <S57TileKey, S57ParsedTile>{};
    final enabledChartIds = _enabledChartIds;
    for (final entry in tileMap.entries) {
      if (entry.key.z != activeZ) continue;
      for (final f in entry.value.features) {
        if (!_clickableLayers.contains(f.objectClass)) continue;
        if (!enabledChartIds.contains(f.chartId)) continue;
        // Closest point on the feature's actual geometry, not a
        // degenerate first-vertex / midpoint stand-in. Lets taps
        // anywhere along a contour line or inside a depth area
        // register against the right feature.
        final closest = _featureClosestPoint(f, tapScreen, camera);
        if (closest == null) continue;
        if ((closest - tapScreen).distanceSquared >
            hitRadiusPx * hitRadiusPx) {
          continue;
        }
        final sig = _featureSignature(f);
        if (!seenSig.add(sig)) continue;
        hits.add(_TappedFeature(
          layer: f.objectClass,
          properties: Map.of(f.attributes),
          screenPos: closest,
          displayPriority: f.displayPriority,
          kind: f.geometry.kind,
        ));
      }
    }
    if (hits.isEmpty) return;

    // Group features within `groupRadiusPx` of each other. Points only
    // — lines / areas get their own singleton groups because their
    // centroid is harder to compute and V1 doesn't group them either.
    final groups = <_TapGroup>[];
    for (final h in hits) {
      if (h.isPoint) {
        var merged = false;
        for (final g in groups) {
          if (!g.isPoint) continue;
          if ((h.screenPos - g.center).distanceSquared <=
              groupRadiusPx * groupRadiusPx) {
            g.members.add(h);
            if (h.displayPriority > g.maxPriority) {
              g.maxPriority = h.displayPriority;
            }
            merged = true;
            break;
          }
        }
        if (!merged) {
          groups.add(_TapGroup(
            center: h.screenPos,
            kind: h.kind,
            maxPriority: h.displayPriority,
            members: [h],
          ));
        }
      } else {
        groups.add(_TapGroup(
          center: h.screenPos,
          kind: h.kind,
          maxPriority: h.displayPriority,
          members: [h],
        ));
      }
    }

    // Winning group: geometry kind first (point > line > polygon),
    // priority within the same kind. Areas like RESARE have higher
    // S-52 displayPriority than buoys but cover the whole viewport, so
    // a priority-first sort lets the area swallow every tap that lands
    // anywhere inside it. Kind-first ensures the symbol the user
    // actually aimed at always wins over the background area context.
    groups.sort((a, b) {
      final ra = _kindRank(a.kind);
      final rb = _kindRank(b.kind);
      if (ra != rb) return ra.compareTo(rb);
      return b.maxPriority.compareTo(a.maxPriority);
    });
    final winner = groups.first;

    // Structures first, equipment after (LIGHTS/FOGSIG/TOPMAR etc. are
    // ancillary to the host buoy/beacon). chart_webview.dart:1115-1122.
    const equipment = {
      'LIGHTS',
      'FOGSIG',
      'TOPMAR',
      'RTPBCN',
      'RADSTA',
      'RDOSTA',
    };
    winner.members.sort((a, b) {
      final aEq = equipment.contains(a.layer) ? 1 : 0;
      final bEq = equipment.contains(b.layer) ? 1 : 0;
      if (aEq != bEq) return aEq.compareTo(bEq);
      return b.displayPriority.compareTo(a.displayPriority);
    });

    _showFeatureSheet(winner.members, tap);
  }

  /// Closest screen-space point on the feature's geometry to `tap`.
  /// Used both for hit-testing (compare distance to a radius) and as
  /// the popover group anchor. Returns null if the feature has no
  /// usable geometry.
  ///
  ///   * Point: nearest of the feature's points to the tap.
  ///   * Line: perpendicular foot on the nearest segment across all
  ///     polylines.
  ///   * Polygon: the tap itself when inside the outer ring (and not
  ///     in a hole) — distance zero. Otherwise the closest edge point.
  Offset? _featureClosestPoint(
      S57StyledFeature f, Offset tap, MapCamera camera) {
    final origin = camera.pixelOrigin;
    Offset project(LatLng p) => camera.projectAtZoom(p) - origin;
    switch (f.geometry.kind) {
      case S57GeomKind.point:
        Offset? best;
        var bestDist2 = double.infinity;
        for (final p in f.geometry.points) {
          final s = project(p);
          final d2 = (s - tap).distanceSquared;
          if (d2 < bestDist2) {
            bestDist2 = d2;
            best = s;
          }
        }
        return best;
      case S57GeomKind.line:
        Offset? best;
        var bestDist2 = double.infinity;
        for (final line in f.geometry.lines) {
          if (line.length < 2) continue;
          var prev = project(line.first);
          for (var i = 1; i < line.length; i++) {
            final curr = project(line[i]);
            final c = _closestPointOnSegment(tap, prev, curr);
            final d2 = (c - tap).distanceSquared;
            if (d2 < bestDist2) {
              bestDist2 = d2;
              best = c;
            }
            prev = curr;
          }
        }
        return best;
      case S57GeomKind.polygon:
        // Edge-proximity only — interior taps do NOT count as hits.
        // RESARE / regulation areas / large administrative polygons
        // cover most of the visible water; treating "inside polygon"
        // as a hit means every tap "hits" them and they crowd out
        // every symbol the user actually meant. Users who want area
        // info tap the visible boundary (or a contour line where the
        // area is bounded by one).
        Offset? best;
        var bestDist2 = double.infinity;
        for (final polygon in f.geometry.rings) {
          for (final ring in polygon) {
            if (ring.length < 2) continue;
            var prev = project(ring.first);
            for (var i = 1; i < ring.length; i++) {
              final curr = project(ring[i]);
              final c = _closestPointOnSegment(tap, prev, curr);
              final d2 = (c - tap).distanceSquared;
              if (d2 < bestDist2) {
                bestDist2 = d2;
                best = c;
              }
              prev = curr;
            }
          }
        }
        return best;
    }
  }

  static Offset _closestPointOnSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return a;
    var t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lenSq;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    return Offset(a.dx + t * dx, a.dy + t * dy);
  }

  /// Stable identity for a feature across tile boundaries: same
  /// real-world object emitted in N adjacent tiles always produces the
  /// same string. Built from objectClass plus the sorted attribute set,
  /// which is what the upstream MVT carries identically per tile copy.
  static String _featureSignature(S57StyledFeature f) {
    final parts = f.attributes.entries
        .where((e) => e.value != null)
        .map((e) => '${e.key}=${e.value}')
        .toList()
      ..sort();
    return '${f.objectClass}|${parts.join('|')}';
  }

  static int _kindRank(S57GeomKind k) {
    switch (k) {
      case S57GeomKind.point:
        return 0;
      case S57GeomKind.line:
        return 1;
      case S57GeomKind.polygon:
        return 2;
    }
  }

  void _showFeatureSheet(List<_TappedFeature> members, LatLng tap) {
    // Pass the PathMetadata objects straight down; the card uses
    // `metadata.format(...)` / `metadata.convert(...)` per CLAUDE.md's
    // SSOT rule. Falling back to raw SI + 'm' when no metadata is
    // registered for the category.
    final store = widget.signalKService.metadataStore;
    final depthMeta = store.getByCategory('depth');
    final heightMeta = store.getByCategory('height');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBackgroundDark,
      barrierColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      // Constrain so the map above stays tappable. Portrait keeps the
      // familiar half-screen; landscape is tight on vertical real
      // estate, so the sheet caps at 1/5 of the viewport and the
      // inner ListView takes care of scrolling.
      constraints: BoxConstraints(
        maxHeight: _popoverMaxHeight(context),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Material drag handle — Flutter wires its own
            // GestureDetector so swipe-down here flings the sheet to
            // dismiss directly.
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: 40,
                height: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.all(Radius.circular(2)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  const Icon(Icons.place, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${tap.latitude.toStringAsFixed(5)}, '
                      '${tap.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: members.length,
                itemBuilder: (_, i) => _FeatureCard(
                  member: members[i],
                  depth: depthMeta,
                  height: heightMeta,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Same 31-entry clickable layer set as V1 (chart_webview.dart:1004-1015).
  // RESARE (Restricted Area) and ACHARE (Anchorage Area) are
  // deliberately excluded. Their dashed boundaries tile the chart so
  // densely that any tap sits within hit radius of an edge, which
  // means the area sheet ends up swallowing taps the user aimed at
  // real symbols sitting nearby. Users who want area detail can zoom
  // in until the boundary is the obvious target, but that UX belongs
  // behind a future "area info" toggle, not the generic tap.
  static const _clickableLayers = {
    'LIGHTS',
    'BOYLAT', 'BOYCAR', 'BOYISD', 'BOYSAW', 'BOYSPP',
    'BCNLAT', 'BCNCAR', 'BCNISD', 'BCNSAW', 'BCNSPP', 'TOPMAR',
    'RTPBCN', 'RDOSTA', 'RADSTA', 'FOGSIG', 'LITFLT', 'LITVES',
    'OBSTRN', 'UWTROC', 'WRECKS',
    'LNDMRK', 'SLCONS', 'BRIDGE', 'OFSPLF', 'PILBOP',
    'CRANES', 'GATCON', 'MORFAC', 'BERTHS', 'HRBFAC', 'SMCFAC',
    'CBLSUB', 'CBLOHD', 'PIPSOL', 'PIPOHD',
    'CGUSTA', 'RSCSTA', 'SISTAT', 'SISTAW',
    'DISMAR', 'CURENT', 'FSHFAC', 'CONVYR',
  };

  /// Long-press inserts a waypoint after the nearest existing one.
  /// Matches V1's UX: press where you want the new point to live.
  void _onMapLongPress(TapPosition tapPosition, LatLng latLng) {
    final hasActiveRoute = _routeCoords != null && _routeCoords!.isNotEmpty;
    final weatherOn = _weatherRoutingEnabled;

    // If a computed weather route exists and the press lands near its
    // polyline, promote that point to a via — mirrors the web UI's
    // long-press at `route-planner.html:2369-2442`.
    if (weatherOn && _tryPromoteWeatherRoutePoint(latLng)) return;

    if (weatherOn && hasActiveRoute) {
      // Both pathways apply — let the user disambiguate.
      _showLongPressChooser(latLng);
      return;
    }
    if (weatherOn) {
      _dropOrMoveWeatherPin(latLng);
      return;
    }
    if (hasActiveRoute) {
      _addRouteWaypointAt(latLng);
    }
  }

  /// Hit-test the currently computed weather-route polyline for a
  /// long-press; if a vertex is within 12 px of the press, add it as a
  /// via and surface a snack. Returns true when the press was consumed
  /// so the caller doesn't fall through to other long-press behaviours.
  /// Hit radius matches the user-facing tolerance the chart already
  /// uses for the nav-route waypoint insert.
  bool _tryPromoteWeatherRoutePoint(LatLng latLng) {
    final service = _weatherRoutingService;
    final result = service?.currentResult;
    if (service == null || result == null || result.coords.isEmpty) {
      return false;
    }
    const hitRadiusSq = 12.0 * 12.0;
    final camera = _mapController.camera;
    final tapPx = camera.latLngToScreenOffset(latLng);
    var bestDistSq = double.infinity;
    int? bestIdx;
    for (var i = 0; i < result.coords.length; i++) {
      final c = result.coords[i];
      final wp = camera.latLngToScreenOffset(LatLng(c[1], c[0]));
      final d = (wp - tapPx).distanceSquared;
      if (d < bestDistSq) {
        bestDistSq = d;
        bestIdx = i;
      }
    }
    if (bestIdx == null || bestDistSq > hitRadiusSq) return false;
    final c = result.coords[bestIdx];
    service.addVia(LatLon(lat: c[1], lon: c[0]));
    _showPinSnack('Pinned via waypoint W${service.plannedVias.length}.');
    return true;
  }

  /// Long-press actions when both the SignalK active-route and the
  /// weather-routing feature want the gesture. Matches the bottom-sheet
  /// idiom used by the Routes manager so the UX is consistent.
  void _showLongPressChooser(LatLng latLng) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBackgroundDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.place, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '${latLng.latitude.toStringAsFixed(5)}, '
                    '${latLng.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontFamily: 'Menlo',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            ListTile(
              leading: const Icon(Icons.flight_takeoff,
                  color: Color(0xFFFF9800)),
              title: const Text('Weather routing pin',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text(
                _pinSubtitleFor(latLng),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _dropOrMoveWeatherPin(latLng);
              },
            ),
            ListTile(
              leading: const Icon(Icons.route, color: Colors.greenAccent),
              title: const Text('Add waypoint to active route',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(ctx).pop();
                _addRouteWaypointAt(latLng);
              },
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  String _pinSubtitleFor(LatLng latLng) {
    final s = _weatherRoutingService?.plannedStart;
    final e = _weatherRoutingService?.plannedEnd;
    if (s == null) return 'Drops the start pin here';
    if (e == null) return 'Drops the end pin here';
    return 'Moves the nearer pin here';
  }

  /// Pin-placement logic: if start is missing, place it; else if end is
  /// missing, place it; else move whichever of the two is closer on
  /// screen to the new tap. Matches the UX described by the user.
  ///
  /// Click-3+ behaviour (mirrors the route-planner web UI at
  /// `route-planner.html:2501-2509`): when both pins are placed and no
  /// route has been computed yet, promote the current End to an
  /// intermediate "via" waypoint and use the new tap as the new End.
  /// Once a route exists, fall through to nearer-pin-move so the user
  /// can still relocate either endpoint.
  void _dropOrMoveWeatherPin(LatLng latLng) {
    final service = _weatherRoutingService;
    if (service == null) return;
    final next = LatLon(lat: latLng.latitude, lon: latLng.longitude);
    if (service.plannedStart == null) {
      service.plannedStart = next;
      _showPinSnack('Start pin placed.');
      return;
    }
    if (service.plannedEnd == null) {
      service.plannedEnd = next;
      _openComposePopover();
      return;
    }
    final hasResult =
        service.currentResult != null && service.currentResult!.isNotEmpty;
    if (!hasResult) {
      // Both pins set, no compute yet → promote current End to a via,
      // make this tap the new End.
      service.addVia(service.plannedEnd!);
      service.plannedEnd = next;
      _openComposePopover();
      return;
    }
    final camera = _mapController.camera;
    final tapPx = camera.latLngToScreenOffset(latLng);
    final sPx = camera.latLngToScreenOffset(
        LatLng(service.plannedStart!.lat, service.plannedStart!.lon));
    final ePx = camera.latLngToScreenOffset(
        LatLng(service.plannedEnd!.lat, service.plannedEnd!.lon));
    final dS = (sPx - tapPx).distanceSquared;
    final dE = (ePx - tapPx).distanceSquared;
    if (dS < dE) {
      service.plannedStart = next;
      _openComposePopover();
    } else {
      service.plannedEnd = next;
      _openComposePopover();
    }
  }

  /// Surface the floating "Route" popover (Compute / Clear / Close).
  /// Triggered by Start- or End-pin tap, and by long-press placement /
  /// move of either pin once both are set. Replaces the old transient
  /// snackbar so the path to "compute route" is one tap from the chart
  /// gesture that placed the pin. Render is gated by `plannedEnd` and
  /// the absence of a computed result — see the Stack at line ~1930.
  void _openComposePopover() {
    if (!mounted) return;
    setState(() => _composePopoverOpen = true);
  }

  void _showPinSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _addRouteWaypointAt(LatLng latLng) {
    final coords = _routeCoords;
    if (coords == null || coords.isEmpty) return;
    final camera = _mapController.camera;
    // Mirror the route painter's camera-copy unwrap so the nearest
    // segment is picked correctly for a route crossing ±180° (a
    // canonical projection streaks the date-line segment across the
    // whole plane and would mis-pick the insertion point).
    final scrUnwrapped = _unwrappedProjector(camera);
    final tapScreen = scrUnwrapped(latLng.longitude, latLng.latitude);
    var nearestIdx = 0;
    var nearestDistSq = double.infinity;
    for (var i = 0; i < coords.length; i++) {
      final wp = scrUnwrapped(coords[i][0], coords[i][1]);
      final d = (wp - tapScreen).distanceSquared;
      if (d < nearestDistSq) {
        nearestDistSq = d;
        nearestIdx = i;
      }
    }
    showAddWaypointDialog(
      context,
      afterIndex: nearestIdx,
      lon: latLng.longitude,
      lat: latLng.latitude,
      routeCoords: coords,
      waypointNames: _waypointNames,
      onChanged: () {
        if (mounted) setState(() {});
      },
      saveRouteToServer: _saveRouteToServer,
    );
  }

  ChartRouteCallbacks get _routeCallbacks => ChartRouteCallbacks(
        activateRoute: _activateRoute,
        reverseRoute: _reverseRoute,
        clearCourse: _clearCourse,
        skipToWaypoint: _skipToWaypoint,
        showRouteManager: () => setState(() {}),
        saveRouteToServer: _saveRouteToServer,
      );

  Future<void> _loadEngine() async {
    try {
      final lookupsRaw =
          await rootBundle.loadString('assets/charts/s57_lookups.json');
      final colorsRaw =
          await rootBundle.loadString('assets/charts/s57_colors.json');
      final spriteJsonRaw =
          await rootBundle.loadString('assets/charts/sprite.json');
      final spritePngBytes =
          (await rootBundle.load('assets/charts/sprite.png'))
              .buffer
              .asUint8List();
      final lookups =
          LookupTable.fromJson(jsonDecode(lookupsRaw) as Map<String, dynamic>);
      final colors = S52ColorTable.fromRawMap(
        (jsonDecode(colorsRaw) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v as String)),
      );
      final sprites = SpriteAtlas.fromJson(
          jsonDecode(spriteJsonRaw) as Map<String, dynamic>);
      final spriteImage = await _decodeImage(spritePngBytes);
      if (!mounted) return;
      // Engine is constructed with default depth options (metres,
      // factor 1.0). Per CLAUDE.md the SOUNDG label rendering routes
      // through MetadataStore.format() at paint time — see
      // `_S57Painter._paintFeature` — so we deliberately don't push
      // user units into the s52_dart options here.
      final engine = S52StyleEngine(
        lookups: lookups,
        options: const S52Options(displayCategory: S52DisplayCategory.other),
        csProcedures: standardCsProcedures,
      );
      final manager = S57TileManager(
        engine: engine,
        urlBuilderForChart: _buildTileUrlForChart,
        // The proxy path injects auth itself, but the no-proxy fallback
        // talks directly to the SignalK server — that path needs the
        // bearer token or authenticated installs 401.
        headersBuilder: () {
          final token = widget.signalKService.authToken?.token;
          if (token == null || token.isEmpty) return const <String, String>{};
          return {'Authorization': 'Bearer $token'};
        },
        freshnessProbe: _probeViewportFreshness,
      );
      manager.addListener(_onTileManagerChanged);
      setState(() {
        _engine = engine;
        _colorTable = colors;
        _spriteAtlas = sprites;
        _spriteImage = spriteImage;
        _tileManager = manager;
      });
      // Manager starts with no charts. Kick off the SignalK catalog
      // fetch and seed `_layers` ∩ catalog into the manager. Safe even
      // if the fetch is empty: empty intersection means no tile fetches
      // until the catalog arrives.
      unawaited(_refreshChartCatalog());
      // Repaint when depth-unit preference changes so SOUNDG labels
      // re-format with the new metadata. The painter looks up the
      // PathMetadata fresh on every frame; we just need to trigger
      // a rebuild.
      widget.signalKService.metadataStore
          .addListener(_onMetadataStoreChanged);
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _loadError = '$e\n$st');
    }
  }

  /// Refresh the chart catalog from
  /// `signalKService.getResources('charts')` and push the per-chart
  /// upstream URL templates to the local tile-cache proxy. Does NOT
  /// modify `_layers` — the user opts into charts via the layer
  /// panel picker (matches V1 / Freeboard's model). Safe to call at
  /// mount and on every panel mutation.
  ///
  /// Each chart resource carries its own `url` field per the SignalK
  /// charts spec (`server-api/src/resourcetypes.ts:Chart`) — different
  /// provider plugins (`signalk-charts-provider-simple`,
  /// `signalk-charts`, …) register different URL templates. We capture
  /// each template into the descriptor's `urlTemplate` and hand the
  /// id→template map to the proxy so it forwards each chartId to the
  /// correct upstream.
  Future<void> _refreshChartCatalog() async {
    if (_catalogLoading) return;
    if (mounted) {
      setState(() {
        _catalogLoading = true;
      });
    }
    try {
      final raw = await widget.signalKService.getResources('charts');
      final descriptors = <ChartDescriptor>[];
      final urlTemplates = <String, String>{};
      for (final entry in raw.entries) {
        // Per-entry try so one chart with an unexpected shape (bad
        // bounds, non-numeric zoom, etc.) doesn't drop the rest of
        // the catalog from the panel.
        try {
          final id = entry.key;
          final data = entry.value;
          if (data is! Map) continue;
          final bounds = data['bounds'];
          // SignalK's chart resource bounds shape varies between
          // providers: map `{west,south,east,north}` (or `{w,s,e,n}`),
          // or a 4-element list `[w,s,e,n]`, or — per the official
          // `Chart` interface — `[[west,south],[east,north]]`. Tolerate
          // all three.
          double? w, s, e, n;
          if (bounds is Map) {
            w = (bounds['west'] as num?)?.toDouble() ??
                (bounds['w'] as num?)?.toDouble();
            s = (bounds['south'] as num?)?.toDouble() ??
                (bounds['s'] as num?)?.toDouble();
            e = (bounds['east'] as num?)?.toDouble() ??
                (bounds['e'] as num?)?.toDouble();
            n = (bounds['north'] as num?)?.toDouble() ??
                (bounds['n'] as num?)?.toDouble();
          } else if (bounds is List && bounds.length >= 4 &&
              bounds.first is num) {
            w = (bounds[0] as num?)?.toDouble();
            s = (bounds[1] as num?)?.toDouble();
            e = (bounds[2] as num?)?.toDouble();
            n = (bounds[3] as num?)?.toDouble();
          } else if (bounds is List &&
              bounds.length >= 2 &&
              bounds[0] is List &&
              bounds[1] is List) {
            // Official corner-pairs form: [[w,s],[e,n]].
            final sw = bounds[0] as List;
            final ne = bounds[1] as List;
            if (sw.length >= 2 && ne.length >= 2) {
              w = (sw[0] as num?)?.toDouble();
              s = (sw[1] as num?)?.toDouble();
              e = (ne[0] as num?)?.toDouble();
              n = (ne[1] as num?)?.toDouble();
            }
          }
          // No bounds — fall back to "world" so the manager doesn't
          // skip every tile. The user's add-picker is the gating
          // surface; once they enable a chart, we always try to fetch.
          w ??= -180.0;
          s ??= -85.0;
          e ??= 180.0;
          n ??= 85.0;
          final minZ = (data['minzoom'] as num?)?.toInt() ??
              (data['minZoom'] as num?)?.toInt() ??
              0;
          final maxZ = (data['maxzoom'] as num?)?.toInt() ??
              (data['maxZoom'] as num?)?.toInt() ??
              22;
          final urlTemplate = data['url'] as String?;
          descriptors.add(ChartDescriptor(
            id: id,
            west: w,
            south: s,
            east: e,
            north: n,
            minZoom: minZ,
            maxZoom: maxZ,
            urlTemplate: urlTemplate,
          ));
          if (urlTemplate != null && urlTemplate.isNotEmpty) {
            urlTemplates[id] = urlTemplate;
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Skipping malformed chart entry ${entry.key}: $e');
          }
        }
      }
      if (!mounted) return;
      _chartCatalog = descriptors;
      // Catalog has now successfully arrived from this server. From
      // this point on, an empty catalog is authoritative — meaning
      // `_onChartsCatalogChanged` is allowed to drop persisted s57
      // entries. Before this point, a slow / failing first connect
      // leaves persisted rows in place.
      _catalogHasLoaded = true;
      _catalogLastError = null;
      // Push URL templates to the local cache proxy so it can forward
      // each chartId to the right upstream. Best-effort: a missing
      // proxy in tests just means tile fetches fall back to direct.
      try {
        context
            .read<ChartTileServerService>()
            .setChartUpstreamTemplates(urlTemplates);
      } catch (_) {/* proxy unavailable */}
      _onChartsCatalogChanged();
    } catch (e) {
      if (mounted) {
        _catalogLastError = 'Catalog refresh failed: $e';
      }
    } finally {
      if (mounted) {
        setState(() {
          _catalogLoading = false;
        });
      }
    }
  }

  /// Reconcile `_layers` against the freshly-arrived chart catalog.
  /// Auto-appends new s57 entries (default `enabled: false` so a
  /// fresh chart arrival doesn't suddenly start fetching tiles the
  /// user didn't ask for) and drops entries for charts the catalog
  /// no longer publishes. Persists + repaints when either side moves.
  /// Always re-pushes the manager chart list so its in-memory cache
  /// matches the merged set.
  void _onChartsCatalogChanged() {
    if (!mounted) return;
    final catalogIds = {for (final c in _chartCatalog) c.id};

    var dirty = false;

    // Only treat the catalog as authoritative once we've ever seen
    // it successfully load from this SignalK server. Without this
    // guard, a slow / failing first connect leaves `_chartCatalog`
    // at the initial `const []`, and the `removeWhere` below would
    // wipe every persisted s57 selection before the next retry
    // could rescue them.
    if (_catalogHasLoaded) {
      final beforeLen = _layers.length;
      _layers.removeWhere((l) =>
          l['type'] == 's57' && !catalogIds.contains(l['id'] as String));
      if (_layers.length != beforeLen) dirty = true;

      // Identity is `(type, id)` — comparing only on `id` would let an
      // S-57 chart whose server id collides with a built-in row (e.g.
      // a chart called `depth` or `openstreetmap`) be silently
      // discarded as already-present.
      final existingKeys = {
        for (final l in _layers) '${l['type']}:${l['id']}',
      };
      for (final c in _chartCatalog) {
        if (existingKeys.contains('s57:${c.id}')) continue;
        _layers.add({
          'type': 's57',
          'id': c.id,
          'enabled': false,
          'opacity': 1.0,
        });
        dirty = true;
      }
    }

    _pushManagerCharts();
    if (dirty) {
      _persistLayerPrefs();
    }
    setState(() {});
  }

  /// Pushes the currently-wired s57 layer set to the tile manager.
  /// Sends two views: the full set (enabled + disabled) as the cache-
  /// keeper list, and the enabled subset as the active fetch list.
  /// This way toggling a chart off keeps its cached features alive so
  /// toggling it back on is instant, while still preventing wasted
  /// fetches for disabled charts.
  void _pushManagerCharts() {
    final manager = _tileManager;
    if (manager == null) return;
    final byId = {for (final c in _chartCatalog) c.id: c};
    final present = <ChartDescriptor>[];
    final active = <String>{};
    for (final l in _layers) {
      if (l['type'] != 's57') continue;
      final id = l['id'] as String;
      final desc = byId[id];
      if (desc == null) continue;
      present.add(desc);
      if (l['enabled'] as bool? ?? true) active.add(id);
    }
    manager.setCharts(present);
    manager.setActiveCharts(active);
    // Without this kick, a chart that the user just added or re-enabled
    // stays blank until they pan/zoom — `setCharts`/`setActiveCharts`
    // only update manager state, they don't fetch.
    if (_mapReady) manager.refreshNow(_mapController.camera);
  }

  /// Signature of the depth metadata we last rebuilt against — just
  /// the user-visible bits (symbol + formula). MetadataStore notifies
  /// many times during connect for paths we don't care about; without
  /// this guard, every notification triggered a full chart repaint.
  String? _lastDepthMetaSig;

  void _onMetadataStoreChanged() {
    if (!mounted) return;
    final store = widget.signalKService.metadataStore;
    final depth = store.getByCategory('depth');
    final sig = depth == null ? null : '${depth.symbol}|${depth.formula}';
    if (sig == _lastDepthMetaSig) return;
    _lastDepthMetaSig = sig;
    setState(() {});
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// URL builder for the tile manager's per-chart fan-out. Prefers
  /// the local cached proxy (cache-first, background-refresh) when
  /// the shared tile server is running. Falls back to the chart's
  /// own `urlTemplate` (captured by [_refreshChartCatalog] from the
  /// SignalK charts resource) so non-default providers work without
  /// the proxy. The legacy hardcoded `signalk-charts-provider-simple`
  /// path is the last-resort fallback for charts whose catalog entry
  /// somehow lacks a template.
  String _buildTileUrlForChart(String chartId, S57TileKey key) {
    // Most chart ids are alphanumeric (`01CGD_ENCs`) so encoding is a
    // no-op. Defensive against future ids carrying `/` `?` `#` or
    // spaces — those would otherwise either split the path or trip the
    // URL parser downstream.
    final safeId = Uri.encodeComponent(chartId);
    try {
      final server = context.read<ChartTileServerService>();
      if (server.isRunning) {
        return 'http://localhost:${server.port}/tiles/$safeId/${key.z}/${key.x}/${key.y}';
      }
    } catch (_) {}
    String? template;
    for (final c in _chartCatalog) {
      if (c.id == chartId) {
        template = c.urlTemplate;
        break;
      }
    }
    if (template != null && template.isNotEmpty) {
      final filled = template
          .replaceAll('{z}', '${key.z}')
          .replaceAll('{x}', '${key.x}')
          .replaceAll('{y}', '${key.y}');
      // Server-relative templates resolve against the SignalK base.
      // Absolute URLs come back from `Uri.resolve` unchanged.
      return Uri.parse(widget.signalKService.httpBaseUrl)
          .resolve(filled)
          .toString();
    }
    return '${widget.signalKService.httpBaseUrl}/plugins/signalk-charts-provider-simple/$safeId/${key.z}/${key.x}/${key.y}';
  }

  TileFreshness _probeViewportFreshness(
      List<(int z, int x, int y)> viewportTiles) {
    return context
        .read<ChartTileCacheService>()
        .getViewportFreshness(viewportTiles);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loadError != null) {
      return _ErrorState(error: _loadError!);
    }
    if (_engine == null ||
        _colorTable == null ||
        _spriteAtlas == null ||
        _spriteImage == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading S-52 engine …'),
          ],
        ),
      );
    }
    final s57Layer = _firstEnabled('s57');
    // Per-chart opacity from each S-57 row's slider in the layer
    // panel. The painter applies these via `saveLayer` per chart per
    // geometry pass, so adjusting any S-57 row's slider is visible.
    // The previous code wrapped the whole merged overlay in a single
    // `Opacity` keyed off the first-enabled chart, which silently
    // ignored every other row's slider.
    final s57ChartOpacities = <String, double>{
      for (final l in _layers)
        if (l['type'] == 's57' && (l['enabled'] as bool? ?? false))
          l['id'] as String: ((l['opacity'] as num?)?.toDouble() ?? 1.0),
    };

    return Container(
      color: AppColors.cardBackgroundDark,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: _initialZoom,
              // Wide pan-out for context. S-57 ENC charts
              // auto-suppress below z=8 via `_S57OverlayLayer`'s
              // `_minRenderZoom`, so the chart stays useful all the
              // way out.
              minZoom: 5,
              maxZoom: 16,
              // Panning releases auto-follow (the map stays where the
              // user dragged it); zoom gestures keep follow so the user
              // can change scale around the vessel. Re-engage via the
              // "snap to vessel" button.
              //
              // Rotation gestures are only permitted in `free` mode.
              // In `northUp` the rotation is pinned to 0; in
              // `headingUp` it's driven from the heading tick, so
              // user input would fight both.
              interactionOptions: InteractionOptions(
                flags: _interactiveFlags(),
              ),
              onMapEvent: (e) {
                // A single-finger pan/fling disengages auto-follow so the
                // map stays where the user dragged it. Programmatic moves
                // (mapController/fitCamera) and two-finger pinch zoom are
                // excluded, so zooming keeps follow engaged.
                if (e.source == MapEventSource.dragStart ||
                    e.source == MapEventSource.onDrag ||
                    e.source == MapEventSource.flingAnimationController) {
                  if (_autoFollow && mounted) {
                    setState(() => _autoFollow = false);
                  }
                }
                // User pinch/scroll zoom kills auto-zoom but leaves
                // auto-follow intact (V1 chart_webview.dart:1271-1278).
                if (e.source == MapEventSource.scrollWheel ||
                    e.source == MapEventSource.doubleTap ||
                    e.source == MapEventSource.multiFingerGestureStart ||
                    e.source == MapEventSource.onMultiFinger) {
                  if (_autoZoom && mounted) {
                    setState(() => _autoZoom = false);
                  }
                }
                _tileManager?.scheduleRefresh(_mapController.camera);
              },
              onMapReady: () {
                _mapReady = true;
                _syncWeatherReferenceTime();
                // Center on vessel immediately if we already have a
                // fix from the 1 s vessel timer (which can run before
                // the map finishes initializing). Avoids the brief
                // flash of the hardcoded `_initialCenter` (LI Sound)
                // that the camera starts on.
                if (_ownLat != null && _ownLon != null) {
                  _mapController.move(
                    LatLng(_ownLat!, _ownLon!),
                    _mapController.camera.zoom,
                  );
                }
                _tileManager?.refreshNow(_mapController.camera);
              },
              onTap: _onMapTap,
              onLongPress: _onMapLongPress,
            ),
            children: [
              // Walk `_layers` in order, emitting a TileLayer for
              // every enabled basemap, overlay, or depth row. List
              // order is paint order, so dragging a basemap above
              // another puts it on top in the chart, and dragging
              // the depth row higher composites bathymetry over
              // basemaps. OpenSeaMap is just another overlay entry —
              // no auto-pair logic; it's toggled like everything
              // else.
              for (final layer in _layers)
                if (layer['enabled'] as bool? ?? false)
                  ..._chartLayerWidgets(layer),
              if (s57Layer != null && _tileManager != null)
                _S57OverlayLayer(
                  tileCache: _tileManager!.tiles,
                  generation: _tileManager!.generation,
                  colorTable: _colorTable!,
                  spriteAtlas: _spriteAtlas!,
                  spriteImage: _spriteImage!,
                  hiddenClasses: _hiddenClasses,
                  enabledChartIds: _enabledChartIds,
                  chartOpacities: s57ChartOpacities,
                  // Category-only: SignalK depth paths vary by setup
                  // (`belowKeel` / `belowSurface` / `belowTransducer`),
                  // so we don't pin to one — `getByCategory('depth')`
                  // returns whichever depth metadata the server has
                  // registered with the user's unit preset.
                  depthMetadata: widget.signalKService.metadataStore
                      .getByCategory('depth'),
                ),
              // Weather raster tiles sit under the vector overlays +
              // route so they read as a background tint (matches web
              // UI z-order: heatmap zIndex 6 vs wind/current 7-8).
              // Each is an XYZ `TileLayer` keyed on the current hour
              // so a waypoint-time scrub swaps URL templates and
              // flutter_map refetches cleanly.
              if (_windHeatmapOn && _weatherDataService != null)
                _weatherRasterTile('/wind-heatmap',
                    WeatherDataService.zoomFloorWindHeatmap),
              if (_currentHeatmapOn && _weatherDataService != null)
                _weatherRasterTile('/current-heatmap',
                    WeatherDataService.zoomFloorCurrentHeatmap),
              if (_seaStateOn && _weatherDataService != null)
                _weatherRasterTile('/roughness',
                    WeatherDataService.zoomFloorSeaState),
              if (_waveHeatmapOn && _weatherDataService != null)
                _weatherRasterTile('/wave-heatmap',
                    WeatherDataService.zoomFloorWaveHeatmap),
              if (_precipHeatmapOn && _weatherDataService != null)
                _weatherRasterTile('/precip-heatmap',
                    WeatherDataService.zoomFloorPrecipHeatmap),
              if (_temperatureHeatmapOn && _weatherDataService != null)
                _weatherRasterTile('/temperature',
                    WeatherDataService.zoomFloorTemperature),
              if (_sstHeatmapOn && _weatherDataService != null)
                _weatherRasterTile(
                    '/sst', WeatherDataService.zoomFloorSst),
              if (_currentsOn && _weatherDataService != null)
                CurrentArrowsTileOverlay(
                  service: _weatherDataService!,
                  zoomFloor: _effectiveMinZoom(
                      '/currents', WeatherDataService.zoomFloorCurrents),
                ),
              if (_windBarbsOn && _weatherDataService != null)
                WindBarbsTileOverlay(
                  service: _weatherDataService!,
                  zoomFloor: _effectiveMinZoom(
                      '/wind', WeatherDataService.zoomFloorWindBarbs),
                ),
              if (_tapHalo != null)
                _TapHaloLayer(point: _tapHalo!),
              if (_trailPoints.length >= 2)
                _TrailOverlayLayer(
                  points: _trailPoints,
                  timestamps: _trailTimestamps,
                ),
              if (_rulerVisible &&
                  _rulerRed != null &&
                  _rulerBlue != null)
                _RulerLayer(
                  red: _rulerRed!,
                  blue: _rulerBlue!,
                  distance: _distanceMetadata(),
                ),
              // Weather route first so the selected/active route paints on
              // top of it (later children render above earlier ones).
              if (_weatherRoutingEnabled &&
                  (_weatherRoutingService?.currentResult?.isNotEmpty ?? false))
                WeatherRouteOverlayLayer(
                  result: _weatherRoutingService!.currentResult!,
                  selectedIndex: _weatherRouteSelectedIdx,
                ),
              if (_routeCoords != null)
                _RouteOverlayLayer(
                  coords: _routeCoords!,
                  activeIndex: _routePointIndex,
                  reversed: _routeReversed,
                ),
              // Approximate-mode halo around each intermediate via
              // pin. Visible only when the routing service is in
              // `approximate` precision; the ring's geographic radius
              // matches the `arrival_radius_m` slider in the panel,
              // so the user gets a live preview of the proximity
              // tolerance before pressing Compute.
              if (_weatherRoutingEnabled &&
                  _weatherRoutingService != null &&
                  _weatherRoutingService!.precision ==
                      RoutePrecision.approximate &&
                  _weatherRoutingService!.plannedVias.isNotEmpty)
                WeatherRouteApproxHaloLayer(
                  vias: [
                    for (final v in _weatherRoutingService!.plannedVias)
                      LatLng(v.lat, v.lon),
                  ],
                  radiusM: _weatherRoutingService!.arrivalRadiusM,
                ),
              if (_aisEnabled && _aisVessels.isNotEmpty)
                _AisOverlayLayer(
                  vessels: _aisVessels,
                  showPaths: _aisShowPaths,
                  selectedId: _selectedAisId,
                ),
              if (_ownLat != null && _ownLon != null)
                _OwnVesselLayer(
                  lat: _ownLat!,
                  lon: _ownLon!,
                  headingRad: _ownHeading,
                  cogRad: _ownCog,
                  sogMs: _ownSog,
                ),
              _MetadataScaleBar(distance: _distanceMetadata()),
              // DragMarkers must be the LAST FlutterMap child. Later
              // children sit on top in the Stack and get gesture
              // priority — otherwise the overlays above (route, AIS,
              // own-vessel, scale) swallow the hit test for the
              // ruler endpoints and weather-routing pins.
              if (_buildDragMarkers().isNotEmpty)
                DragMarkers(markers: _buildDragMarkers()),
              // Tile-provider attribution (OSM / OpenSeaMap usage policies
              // require visible credit). Painted in the bottom-right
              // corner — outside the drag-marker hit zones — so it stays
              // tappable without intercepting chart gestures.
              if (_anyOsmOrOpenSeaMapEnabled())
                MapAttribution(
                  osm: _isLayerEnabled('openstreetmap', type: 'base'),
                  openSeaMap:
                      _isLayerEnabled('openseamap', type: 'overlay'),
                ),
            ],
          ),
          ChartPlotterHUD(
            signalKService: widget.signalKService,
            hudStyle: _hudStyle,
            hudPosition: _hudPosition,
            paths: _fallbackPaths,
            hasActiveRoute: _routeCoords != null,
            canAdvance: _routeCoords != null &&
                _routePointIndex != null &&
                _routePointTotal != null &&
                _routePointIndex! + 1 < _routePointTotal!,
            onAdvanceWaypoint: () {
              final i = _routePointIndex;
              if (i != null) _skipToWaypoint(i + 1);
            },
          ),
          // Weather player floating strip. Sits above the on-map
          // legend stack so the slider and time label stay visible
          // even when many layers have legends pinned to the chart.
          if (_playerVisible && _hasTimeKeyedWeatherLayer)
            Positioned(
              left: 8,
              right: 8,
              bottom: _hudStyle == 'visual' ? 250 : 140,
              child: _WeatherPlayerStrip(
                offsetHours: _playerOffsetHours,
                direction: _playerDirection,
                minOffset: _playerMinOffset,
                maxOffset: _playerMaxOffset,
                referenceTime: _weatherDataService?.referenceTime ??
                    DateTime.now(),
                layers: _playerLayerStatuses(),
                onSetDirection: _setPlayerDirection,
                onStep: _stepPlayer,
                onSeek: _setPlayerOffset,
                onResetToNow: _resetPlayerToNow,
                onClose: _togglePlayer,
              ),
            ),
          // On-map legend stack — renders compact cards near the
          // bottom of the chart for every layer whose "On map" toggle
          // is on AND that's currently visible at the effective zoom.
          // Offset clears the scale bar (~y=64..92 from bottom) and
          // the freshness chip (~y=52 text / 8 none). Visual HUD
          // pushes the whole bottom block up so legends sit above it.
          if (_weatherDataService != null && _mapReady)
            Positioned(
              left: 8,
              right: 8,
              bottom: _hudStyle == 'visual' ? 210 : 100,
              child: _OnMapLegendStack(
                service: _weatherDataService!,
                entries: _onMapLegendEntries(),
                mapController: _mapController,
                initialZoom: _mapController.camera.zoom,
              ),
            ),
          // Waypoint popover sits AFTER the legend stack in Stack
          // order so it always paints on top of the legends.
          if (_weatherRoutingEnabled &&
              _weatherRouteSelectedIdx != null &&
              (_weatherRoutingService?.currentResult?.isNotEmpty ?? false))
            Positioned(
              left: 8,
              right: 8,
              bottom: _hudStyle == 'visual' ? 200 : (_hudStyle == 'text' ? 62 : 16),
              child: _WeatherWaypointPopover(
                result: _weatherRoutingService!.currentResult!,
                selectedIndex: _weatherRouteSelectedIdx!,
                onPrev: () =>
                    _setSelectedWaypoint(_weatherRouteSelectedIdx! - 1),
                onNext: () =>
                    _setSelectedWaypoint(_weatherRouteSelectedIdx! + 1),
                // -1 / waypoints.length address the START / END
                // virtual cards; `_setSelectedWaypoint` clamps them
                // back to the real-waypoint range when the
                // corresponding endpoint wasn't snapped.
                onFirst: () => _setSelectedWaypoint(-1),
                onLast: () => _setSelectedWaypoint(
                    _weatherRoutingService!.currentResult!.waypoints.length),
                onClose: () => _setSelectedWaypoint(null),
                onClearRoute: () {
                  // Tabula-rasa wipe — drops the result polyline,
                  // all pins, every via, the selection cursor, and
                  // any open compose popover. See
                  // `WeatherRoutingService.clearAll`.
                  _setSelectedWaypoint(null);
                  setState(() => _composePopoverOpen = false);
                  _weatherRoutingService?.clearAll();
                },
              ),
            ),
          // Pre-compute End-pin popover. Only renders when no route
          // exists (so it doesn't compete with the waypoint card) and
          // the user has tapped the End pin.
          if (_weatherRoutingEnabled &&
              _composePopoverOpen &&
              _weatherRoutingService != null &&
              _weatherRoutingService!.plannedEnd != null &&
              (_weatherRoutingService?.currentResult == null ||
                  _weatherRoutingService!.currentResult!.isEmpty))
            Positioned(
              left: 8,
              right: 8,
              bottom: _hudStyle == 'visual' ? 200 : (_hudStyle == 'text' ? 62 : 16),
              child: _ComposePopover(
                onCompute: () {
                  setState(() => _composePopoverOpen = false);
                  _showWeatherRoutingSheet(context, autoSubmit: true);
                },
                onClearRoute: () {
                  // Tabula-rasa wipe — drops all pins, every via,
                  // the result, the selection cursor, and closes
                  // this compose popover.
                  setState(() => _composePopoverOpen = false);
                  _setSelectedWaypoint(null);
                  _weatherRoutingService?.clearAll();
                },
                onClose: () =>
                    setState(() => _composePopoverOpen = false),
              ),
            ),
          Positioned(
            bottom: _hudStyle == 'visual' ? 190 : (_hudStyle == 'text' ? 52 : 8),
            right: 8,
            child: _FreshnessChip(
              freshness:
                  _tileManager?.viewportFreshness ?? TileFreshness.uncached,
              connected: widget.signalKService.isConnected,
            ),
          ),
          // Full-screen tap-catcher: while a nav drawer is open, a tap
          // anywhere outside the drawer/controls collapses it. flutter_map
          // consumes pointer events, so `TapRegion.onTapOutside` never sees
          // taps that land on the map — an explicit opaque barrier above the
          // map is the reliable mechanism, and it absorbs the tap so the map
          // doesn't pan/select underneath. The controls below render on top
          // of this barrier, so the drawer stays interactive.
          if (_openDrawer != _NavDrawerKind.none)
            Positioned.fill(
              // Dismiss on any pointer-down, not just a clean onTap: a
              // slightly-draggy tap makes a TapGestureRecognizer bail and the
              // drawer stays stuck open. A Listener fires on the raw pointer,
              // so any touch outside the drawer/controls collapses it. The
              // controls render above this barrier and stay interactive.
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) =>
                    setState(() => _openDrawer = _NavDrawerKind.none),
              ),
            ),
          Positioned(
            top: 8,
            right: 8,
            // The tap-catcher above handles dismiss; taps on the controls
            // themselves render above it and are unaffected.
            child: _MapControls(
                autoFollow: _autoFollow,
                viewMode: _viewMode,
                rulerVisible: _rulerVisible,
                recordingTrack: _recordingTrack,
                onToggleRecordTrack: _toggleTrackRecording,
                openDrawer: _openDrawer,
                onOpenAis: () => _toggleNavDrawer(_NavDrawerKind.ais),
                onOpenRoutes: () => _toggleNavDrawer(_NavDrawerKind.routes),
                onOpenLayers: () => _toggleNavDrawer(_NavDrawerKind.layers),
              onToggleFollow: () {
                // V1 re-engages auto-zoom whenever auto-follow turns
                // back on (chart_webview.dart:1395).
                setState(() {
                  _autoFollow = !_autoFollow;
                  if (_autoFollow) _autoZoom = true;
                });
                if (_autoFollow &&
                    _mapReady &&
                    _ownLat != null &&
                    _ownLon != null) {
                  _mapController.move(
                    LatLng(_ownLat!, _ownLon!),
                    _mapController.camera.zoom,
                  );
                }
              },
              onToggleViewMode: _toggleViewMode,
              onToggleRuler: _toggleRuler,
              // AIS sub-buttons
              aisEnabled: _aisEnabled,
              aisActiveOnly: _aisActiveOnly,
              aisShowPaths: _aisShowPaths,
              onToggleAis: () {
                setState(() {
                  _aisEnabled = !_aisEnabled;
                  if (_aisEnabled) {
                    _refreshAisVessels();
                  } else {
                    // No vessels visible → no place to anchor the
                    // selection ring.
                    _selectedAisId = null;
                  }
                });
              },
              onToggleAisActive: () {
                setState(() {
                  _aisActiveOnly = !_aisActiveOnly;
                  _refreshAisVessels();
                });
              },
              onToggleAisPaths: () {
                setState(() {
                  _aisShowPaths = !_aisShowPaths;
                  _refreshAisVessels();
                });
              },
              onOpenAisList: () => _openAisList(context),
              // Routes sub-buttons (sister has no tracker)
              onRoutes: () => _showRouteManager(context),
              weatherRoutingEnabled: _weatherRoutingEnabled,
              weatherRouteActive:
                  _weatherRoutingService?.currentResult?.isNotEmpty ?? false,
              onWeatherRouting: _weatherRoutingEnabled
                  ? () => _showWeatherRoutingSheet(context)
                  : null,
              // Layers sub-buttons
              onLayers: () => _showLayerSheet(context),
              onDownload: () => _showDownloadSheet(context),
              playerVisible: _playerVisible,
              playerAvailable: _hasTimeKeyedWeatherLayer,
              onTogglePlayer: _togglePlayer,
              ),
          ),
          if (_rulerVisible && _rulerRed != null && _rulerBlue != null)
            Positioned(
              top: 8,
              left: 8,
              child: _RulerReadout(
                signalKService: widget.signalKService,
                a: _rulerRed!,
                b: _rulerBlue!,
              ),
            ),
          // Compass rose is redundant in `northUp` (the whole chart
          // already points north). Shown in `headingUp` and `free`
          // where the chart may be at any rotation. Counter-rotates
          // against the current map rotation so its internal N arrow
          // stays aligned with true north regardless of mode.
          if (_viewMode != _ViewMode.northUp)
            Positioned(
              top: _rulerVisible ? 130 : 80,
              left: 8,
              child: Transform.rotate(
                angle: _mapReady
                    ? -_mapController.camera.rotationRad
                    : -(_ownHeading ?? 0.0),
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.6),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: CustomPaint(painter: _CompassRosePainter()),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showRouteManager(BuildContext ctx) {
    showRouteManagerSheet(
      ctx,
      signalKService: widget.signalKService,
      routeState: ChartRouteState(
        routeCoords: _routeCoords,
        waypointNames: _waypointNames,
        routePointIndex: _routePointIndex,
        routePointTotal: _routePointTotal,
        activeRouteId: _activeRouteId,
      ),
      callbacks: _routeCallbacks,
      navPaths: _fallbackPaths,
    );
  }

  void _showWeatherRoutingSheet(BuildContext ctx, {bool autoSubmit = false}) {
    showWeatherRoutingSheet(
      ctx,
      vesselPosition: (_ownLat != null && _ownLon != null)
          ? LatLon(lat: _ownLat!, lon: _ownLon!)
          : null,
      defaultMode: _weatherRouteDefaultMode,
      defaultPolar: _weatherRoutePolar,
      onFocusWaypoint: _focusWeatherRouteWaypoint,
      onFitToRoute: _fitWeatherRoute,
      onSaveAsRoute: _saveWeatherRouteAsRoute,
      autoSubmit: autoSubmit,
    );
  }

  /// Fit the chart camera to the current weather-route polyline.
  /// Called when the user taps a row in the Recent tab so they land
  /// on the route they just loaded. Auto-follow stays as-is — the
  /// next vessel tick will re-pan only if the user has it enabled,
  /// matching the existing waypoint-focus behaviour.
  void _fitWeatherRoute() {
    final result = _weatherRoutingService?.currentResult;
    if (result == null || result.coords.isEmpty || !_mapReady) return;
    double minLat = double.infinity, maxLat = -double.infinity;
    double minLon = double.infinity, maxLon = -double.infinity;
    for (final c in result.coords) {
      final lon = c[0];
      final lat = c[1];
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lon < minLon) minLon = lon;
      if (lon > maxLon) maxLon = lon;
    }
    if (!minLat.isFinite || !minLon.isFinite) return;
    final bounds = LatLngBounds(
      LatLng(minLat, minLon),
      LatLng(maxLat, maxLon),
    );
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(48),
        maxZoom: 15,
      ),
    );
  }

  /// End-pin tap handler. Only meaningful when no route is currently
  /// computed — otherwise the post-compute waypoint popover (opened
  /// via map-tap hit-test) already owns this location.
  void _onEndPinTap() {
    final svc = _weatherRoutingService;
    if (svc == null) return;
    if (svc.currentResult != null && svc.currentResult!.isNotEmpty) {
      // Route exists: don't show the compose popover. The user can
      // tap the End waypoint ring (same location) to get the waypoint
      // card, or clear the route first.
      return;
    }
    setState(() => _composePopoverOpen = !_composePopoverOpen);
  }

  /// Start-pin tap. Mirrors [_onEndPinTap] — only meaningful when an
  /// End pin exists and no route is computed, so the user has a clear
  /// "Compute" path one tap from the pin they just placed/moved.
  void _onStartPinTap() {
    final svc = _weatherRoutingService;
    if (svc == null) return;
    if (svc.plannedEnd == null) return;
    if (svc.currentResult != null && svc.currentResult!.isNotEmpty) return;
    setState(() => _composePopoverOpen = !_composePopoverOpen);
  }

  void _focusWeatherRouteWaypoint(int index) {
    _setSelectedWaypoint(index);
  }

  /// Cycle through the three view modes: `northUp` → `headingUp` →
  /// `free` → `northUp`. `northUp` snaps rotation to 0; `headingUp`
  /// leaves rotation alone here and the 1 s vessel tick applies the
  /// current heading; `free` is hands-off — whatever rotation the
  /// user sets via the two-finger gesture sticks.
  void _toggleViewMode() {
    setState(() {
      _viewMode = switch (_viewMode) {
        _ViewMode.northUp => _ViewMode.headingUp,
        _ViewMode.headingUp => _ViewMode.free,
        _ViewMode.free => _ViewMode.northUp,
      };
    });
    if (_viewMode == _ViewMode.northUp && _mapReady) {
      _mapController.rotate(0);
    }
  }

  /// Gesture flags for FlutterMap's `InteractionOptions`.
  /// All gestures stay enabled — a user pan releases auto-follow via
  /// `onMapEvent` rather than being locked out, while zoom keeps follow
  /// engaged. Only `rotate` is gated, on view mode.
  int _interactiveFlags() {
    var f = InteractiveFlag.all;
    if (_viewMode != _ViewMode.free) {
      f &= ~InteractiveFlag.rotate;
    }
    return f;
  }

  /// Toggle the ruler overlay. V1 seeds endpoints at `center ± 80px`
  /// in screen pixels (chart_webview.dart:1930-1932). We match that so
  /// the handles land where a user's thumbs would expect.
  void _toggleRuler() {
    setState(() {
      _rulerVisible = !_rulerVisible;
      if (!_rulerVisible) {
        _rulerRedSnap = null;
        _rulerBlueSnap = null;
        return;
      }
      if (_rulerRed == null || _rulerBlue == null) {
        final camera = _mapController.camera;
        final size = camera.size;
        final centerScreen = Offset(size.width / 2, size.height / 2);
        _rulerRed = camera.offsetToCrs(centerScreen - const Offset(80, 0));
        _rulerBlue = camera.offsetToCrs(centerScreen + const Offset(80, 0));
      }
    });
  }

  /// Pulled-out drag handler so snap logic can live alongside the
  /// endpoint update. Snap candidates: the own-vessel marker (20px)
  /// and any AIS vessel (20px) — matching V1's hitTolerance.
  void _onRulerDrag(String end, LatLng raw) {
    final camera = _mapController.camera;
    final rawScreen = camera.latLngToScreenOffset(raw);
    const snapRadiusSq = 20.0 * 20.0;
    LatLng snapped = raw;
    String? snapId;
    if (_ownLat != null && _ownLon != null) {
      final selfScreen =
          camera.latLngToScreenOffset(LatLng(_ownLat!, _ownLon!));
      if ((selfScreen - rawScreen).distanceSquared <= snapRadiusSq) {
        snapped = LatLng(_ownLat!, _ownLon!);
        snapId = 'self';
      }
    }
    if (snapId == null) {
      for (final v in _aisVessels) {
        final s = camera.latLngToScreenOffset(v.position);
        if ((s - rawScreen).distanceSquared <= snapRadiusSq) {
          snapped = v.position;
          snapId = v.id;
          break;
        }
      }
    }
    setState(() {
      if (end == 'red') {
        _rulerRed = snapped;
        _rulerRedSnap = snapId;
      } else {
        _rulerBlue = snapped;
        _rulerBlueSnap = snapId;
      }
    });
  }

  /// Reposition snapped ruler endpoints when their target vessel
  /// moves. Called from the vessel + AIS refresh paths.
  void _refreshRulerSnaps() {
    if (!_rulerVisible) return;
    LatLng? targetFor(String? id) {
      if (id == null) return null;
      if (id == 'self' && _ownLat != null && _ownLon != null) {
        return LatLng(_ownLat!, _ownLon!);
      }
      for (final v in _aisVessels) {
        if (v.id == id) return v.position;
      }
      return null;
    }

    final newRed = targetFor(_rulerRedSnap);
    final newBlue = targetFor(_rulerBlueSnap);
    if (newRed != null && newRed != _rulerRed) _rulerRed = newRed;
    if (newBlue != null && newBlue != _rulerBlue) _rulerBlue = newBlue;
  }

  /// Visual-only widget for the ruler endpoint. Matches V1's
  /// 12 px circle with a 2 px white stroke, centred in a 44 px hit
  /// box (the wider hit target is picked up by DragMarker's size).
  Widget _rulerHandleVisual(Color fill) {
    return Center(
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    );
  }

  /// Single drag-marker builder for everything that can be dragged on
  /// the chart (ruler endpoints, weather-routing pins). flutter_map
  /// DragMarkers must live in a single widget that is the last child
  /// of FlutterMap — otherwise overlays painted after it steal the
  /// drag gesture.
  List<DragMarker> _buildDragMarkers() {
    final markers = <DragMarker>[];
    if (_rulerVisible && _rulerRed != null && _rulerBlue != null) {
      markers.add(DragMarker(
        point: _rulerRed!,
        size: const Size(44, 44),
        rotateMarker: false,
        onDragUpdate: (details, latLng) => _onRulerDrag('red', latLng),
        builder: (_, _, _) => _rulerHandleVisual(const Color(0xCCF44336)),
      ));
      markers.add(DragMarker(
        point: _rulerBlue!,
        size: const Size(44, 44),
        rotateMarker: false,
        onDragUpdate: (details, latLng) => _onRulerDrag('blue', latLng),
        builder: (_, _, _) => _rulerHandleVisual(const Color(0xCC2196F3)),
      ));
    }
    final service = _weatherRoutingService;
    if (_weatherRoutingEnabled && service != null) {
      final s = service.plannedStart;
      if (s != null) {
        markers.add(DragMarker(
          point: LatLng(s.lat, s.lon),
          size: const Size(44, 44),
          rotateMarker: false,
          // Live-follow drag like the ruler handles. Moving the start
          // invalidates any computed result, so clear it — the user is
          // about to recompute against a different leg.
          onDragUpdate: (details, latLng) {
            service.plannedStart =
                LatLon(lat: latLng.latitude, lon: latLng.longitude);
          },
          onDragEnd: (details, latLng) {
            if (service.currentResult != null) {
              _setSelectedWaypoint(null);
              service.clearResult();
            }
          },
          onTap: (_) => _onStartPinTap(),
          builder: (_, _, _) => _weatherRoutePinVisual(
              fill: const Color(0xFF4CAF50), label: 'S'),
        ));
      }
      final e = service.plannedEnd;
      if (e != null) {
        markers.add(DragMarker(
          point: LatLng(e.lat, e.lon),
          size: const Size(44, 44),
          rotateMarker: false,
          onDragUpdate: (details, latLng) {
            service.plannedEnd =
                LatLon(lat: latLng.latitude, lon: latLng.longitude);
          },
          onDragEnd: (details, latLng) {
            if (service.currentResult != null) {
              _setSelectedWaypoint(null);
              service.clearResult();
            }
          },
          onTap: (_) => _onEndPinTap(),
          builder: (_, _, _) => _weatherRoutePinVisual(
              fill: const Color(0xFFF44336), label: 'E'),
        ));
      }
      // Intermediate "via" waypoints — orange `W{i+1}` pins. Drag clears
      // any computed result so the request can be re-submitted.
      final vias = service.plannedVias;
      for (var i = 0; i < vias.length; i++) {
        final v = vias[i];
        final viaIndex = i; // capture for closures
        markers.add(DragMarker(
          point: LatLng(v.lat, v.lon),
          size: const Size(44, 44),
          rotateMarker: false,
          onDragUpdate: (details, latLng) {
            service.moveVia(
              viaIndex,
              LatLon(lat: latLng.latitude, lon: latLng.longitude),
            );
          },
          onDragEnd: (details, latLng) {
            if (service.currentResult != null) {
              _setSelectedWaypoint(null);
              service.clearResult();
            }
          },
          builder: (_, _, _) => _weatherRoutePinVisual(
              fill: const Color(0xFFFF9800), label: 'W${viaIndex + 1}'),
        ));
      }
    }
    return markers;
  }

  Widget _weatherRoutePinVisual({required Color fill, required String label}) {
    return Center(
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            height: 1.0,
          ),
        ),
      ),
    );
  }

  /// Distance metadata (SI = metres). Consumers must use
  /// `metadata.convert(m)` and `metadata.convertToSI(display)` per
  /// the project's single-source-of-truth rule — no factor shortcuts,
  /// since they silently break for non-linear formulas (e.g. °K → °F).
  PathMetadata? _distanceMetadata() =>
      widget.signalKService.metadataStore.getByCategory('distance');

  void _showDownloadSheet(BuildContext ctx) {
    ChartDownloadManager? downloadManager;
    try {
      downloadManager = ctx.read<ChartDownloadManager>();
    } catch (_) {
      return;
    }
    final bounds = _mapController.camera.visibleBounds;
    final minLon = bounds.west;
    final minLat = bounds.south;
    final maxLon = bounds.east;
    final maxLat = bounds.north;

    var minZoom = 9;
    var maxZoom = 16;
    final nameController = TextEditingController(
      text: 'Area ${DateTime.now().toString().substring(0, 16)}',
    );

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (_, setSheetState) {
          final estimate = downloadManager!.estimateTileCount(
            minLon: minLon,
            minLat: minLat,
            maxLon: maxLon,
            maxLat: maxLat,
            minZoom: minZoom,
            maxZoom: maxZoom,
          );
          final estimatedMB = (estimate * 10 / 1024).toStringAsFixed(1);

          return Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            decoration: const BoxDecoration(
              color: AppColors.cardBackgroundDark,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[600],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text('Download Charts',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  '${minLat.toStringAsFixed(2)}°N to ${maxLat.toStringAsFixed(2)}°N, '
                  '${minLon.toStringAsFixed(2)}°E to ${maxLon.toStringAsFixed(2)}°E',
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Region name',
                    hintStyle: TextStyle(color: Colors.white38),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.green)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  const Text('Zoom: ',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 13)),
                  Expanded(
                    child: RangeSlider(
                      values: RangeValues(
                          minZoom.toDouble(), maxZoom.toDouble()),
                      min: 9,
                      max: 16,
                      divisions: 7,
                      labels: RangeLabels('$minZoom', '$maxZoom'),
                      onChanged: (v) => setSheetState(() {
                        minZoom = v.start.toInt();
                        maxZoom = v.end.toInt();
                      }),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Text('$estimate tiles (~$estimatedMB MB)',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 12),
                ListenableBuilder(
                  listenable: downloadManager,
                  builder: (context, _) {
                    final mgr = downloadManager!;
                    if (mgr.status == DownloadStatus.downloading) {
                      return Column(children: [
                        LinearProgressIndicator(value: mgr.progress),
                        const SizedBox(height: 4),
                        Text('${mgr.downloadedTiles} of ${mgr.totalTiles}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: mgr.cancel,
                          child: const Text('Cancel',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ]);
                    }
                    if (mgr.status == DownloadStatus.completed) {
                      return const Text('Download complete!',
                          style: TextStyle(
                              color: Colors.green,
                              fontSize: 14,
                              fontWeight: FontWeight.w500));
                    }
                    if (mgr.status == DownloadStatus.error) {
                      return Text(mgr.errorMessage ?? 'Download failed',
                          style: const TextStyle(
                              color: Colors.red, fontSize: 13));
                    }
                    final chartId = (_firstEnabled('s57')?['id'] as String?) ??
                        '01CGD_ENCs';
                    return Column(children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.download),
                          label: const Text('Download New'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => mgr.downloadArea(
                            minLon: minLon,
                            minLat: minLat,
                            maxLon: maxLon,
                            maxLat: maxLat,
                            minZoom: minZoom,
                            maxZoom: maxZoom,
                            baseUrl: widget.signalKService.httpBaseUrl,
                            authToken: widget.signalKService.authToken?.token,
                            regionName: nameController.text,
                            chartId: chartId,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('Flush & Re-download All'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange,
                            side: const BorderSide(color: Colors.orange),
                          ),
                          onPressed: () => mgr.downloadArea(
                            minLon: minLon,
                            minLat: minLat,
                            maxLon: maxLon,
                            maxLat: maxLat,
                            minZoom: minZoom,
                            maxZoom: maxZoom,
                            baseUrl: widget.signalKService.httpBaseUrl,
                            authToken: widget.signalKService.authToken?.token,
                            regionName: nameController.text,
                            chartId: chartId,
                            flush: true,
                          ),
                        ),
                      ),
                    ]);
                  },
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() => downloadManager?.reset());
  }

  void _showLayerSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      // DraggableScrollableSheet lets the user flick the sheet all the
      // way down to dismiss it, matching the Weather Routing sheet.
      // `shouldCloseOnMinExtent: true` pairs with a low `minChildSize`
      // so releasing past the bottom snap triggers pop().
      builder: (sheetCtx) => DraggableScrollableSheet(
        // expand: false leaves the modal barrier exposed above the sheet
        // so tap-outside dismisses (default true covers the barrier).
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        minChildSize: 0.15,
        snap: true,
        snapSizes: const [0.75, 0.92],
        shouldCloseOnMinExtent: true,
        builder: (_, scrollController) => StatefulBuilder(
          builder: (sbCtx, sbSetState) {
            // Wrapped panel `setState`: run the mutation once, then
            // rebuild both the sheet's StatefulBuilder and the
            // chart-plotter state. The previous shape called the
            // mutation closure twice (`sbSetState(fn)` + `setState(fn)`)
            // which double-applied every reorder / toggle.
            void panelSetState(VoidCallback fn) {
              fn();
              sbSetState(() {});
              if (mounted) setState(() {});
            }

            void onChartLayersChanged() {
              if (!mounted) return;
              // The picker is gone — `_layers` only contains entries
              // that were either seeded or added by the catalog
              // reconciliation. Every panel mutation is an enable /
              // opacity / reorder; no catalog refetch needed. Just
              // re-push the active s57 set and persist.
              _pushManagerCharts();
              _persistLayerPrefs();
            }

            Widget basemapsTab() {
              return _basemapsTab(
                onChartLayersChanged: onChartLayersChanged,
                panelSetState: panelSetState,
              );
            }

            Widget chartsTab() {
              return _chartsTab(
                onChartLayersChanged: onChartLayersChanged,
                panelSetState: panelSetState,
                sheetSetState: sbSetState,
              );
            }

            Widget weatherTab() {
              return _weatherTab(sheetSetState: sbSetState);
            }

            return DefaultTabController(
              length: 3,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.cardBackgroundDark,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
                    ),
                    child: Column(
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(
                                top: 8, bottom: 4),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Chart Layers',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const TabBar(
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.white54,
                          indicatorColor: Colors.white,
                          indicatorSize: TabBarIndicatorSize.label,
                          tabs: [
                            Tab(text: 'Basemaps'),
                            Tab(text: 'Charts'),
                            Tab(text: 'Weather'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              basemapsTab(),
                              chartsTab(),
                              weatherTab(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Basemaps tab: 6 raster basemaps + OpenSeaMap overlay + GEBCO
  /// depth, all backed by constants in `chart_constants.dart`. No
  /// network catalog — no refresh affordance.
  Widget _basemapsTab({
    required VoidCallback onChartLayersChanged,
    required void Function(VoidCallback) panelSetState,
  }) {
    return ListView(
      primary: false,
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      children: [
        ChartLayerPanel(
          layers: _layers,
          setState: panelSetState,
          onLayersChanged: onChartLayersChanged,
          filter: (l) =>
              l['type'] == 'base' ||
              l['type'] == 'overlay' ||
              l['type'] == 'depth',
        ),
      ],
    );
  }

  /// Charts tab: every catalog-published S-57 ENC. Header row
  /// surfaces a refresh icon (with spinner) plus, when the catalog
  /// fetch flagged a `lastError`, an error chip with Retry.
  /// Pull-to-refresh on the body re-runs `_refreshChartCatalog`.
  Widget _chartsTab({
    required VoidCallback onChartLayersChanged,
    required void Function(VoidCallback) panelSetState,
    required void Function(VoidCallback) sheetSetState,
  }) {
    final loading = _catalogLoading;
    final lastError = _catalogLastError;
    final s57Count = _layers.where((l) => l['type'] == 's57').length;

    Future<void> refresh() async {
      await _refreshChartCatalog();
      if (!mounted) return;
      sheetSetState(() {});
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'S-57 charts',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: Padding(
                      padding: EdgeInsets.all(2),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    tooltip: 'Refresh chart catalog',
                    iconSize: 20,
                    color: Colors.white70,
                    icon: const Icon(Icons.refresh),
                    onPressed: refresh,
                  ),
              ],
            ),
          ),
          if (lastError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A1A1A),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppColors.alarmRed, width: 1),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        lastError,
                        style: const TextStyle(
                            color: Color(0xFFFF8888), fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: refresh,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          if (s57Count == 0 && !loading && lastError == null)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Text(
                'No S-57 charts published. Pull to refresh.',
                style:
                    TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            )
          else
            ChartLayerPanel(
              layers: _layers,
              setState: panelSetState,
              onLayersChanged: onChartLayersChanged,
              filter: (l) => l['type'] == 's57',
            ),
        ],
      ),
    );
  }

  /// Weather tab: the existing 9 toggles, plus a unified refresh
  /// affordance that re-fetches metadata AND invalidates the tile
  /// cache (the user's "server slow" intent covers both).
  Widget _weatherTab({
    required void Function(VoidCallback) sheetSetState,
  }) {
    Future<void> refresh() async {
      final s = _weatherDataService;
      if (s == null) return;
      await s.refreshMetadata();
      await s.reloadTiles();
      if (!mounted) return;
      sheetSetState(() {});
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Weather Layers',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh weather metadata + reload tiles',
                  iconSize: 20,
                  color: Colors.white70,
                  icon: const Icon(Icons.refresh),
                  onPressed: refresh,
                ),
              ],
            ),
          ),
          // Body of the existing weather section, minus its old
          // header row (which carried the Reload-tiles button now
          // folded into the tab refresh icon above).
          _weatherLayersSection(sheetSetState),
        ],
      ),
    );
  }

  /// Weather overlay toggles (wind / currents / heatmaps / sea state).
  /// Rendered inside the layer sheet. Tile layers self-fetch when the
  /// camera moves or the reference hour flips, so a toggle is just a
  /// state flip — flipping on adds the `TileLayer` / tile-aware vector
  /// overlay to the Stack; flipping off removes it.
  Widget _weatherLayersSection(void Function(VoidCallback) sheetSetState) {
    void flip({
      required bool current,
      required void Function(bool) assign,
    }) {
      final next = !current;
      sheetSetState(() => assign(next));
      if (!mounted) return;
      setState(() => assign(next));
      // Wind barbs / currents are time-keyed too. If this flip just
      // dropped the last time-keyed layer, fully deactivate the
      // player so it doesn't come back to a stale hidden hour next
      // time the user re-enables a layer.
      if (_maybeDeactivatePlayer()) _syncWeatherReferenceTime();
      _persistLayerPrefs();
    }

    // Header row + standalone "Reload tiles" button used to live
    // here. The Weather tab now owns the section header and the
    // refresh affordance (tab refresh icon + pull-to-refresh, both
    // of which combine `refreshMetadata()` + `reloadTiles()`), so
    // this widget renders only the rows.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _weatherLayerTile(
          icon: Icons.air,
          label: 'Wind barbs',
          subtitle: 'ECMWF HRES',
          value: _windBarbsOn,
          metadataPath: '/wind',
          sheetSetState: sheetSetState,
          onChanged: () => flip(
            current: _windBarbsOn,
            assign: (v) => _windBarbsOn = v,
          ),
        ),
        _weatherLayerTile(
          icon: Icons.waves,
          label: 'Tidal currents',
          subtitle: 'NOAA STOFS-3D / NECOFS / FES2014',
          value: _currentsOn,
          metadataPath: '/currents',
          sheetSetState: sheetSetState,
          onChanged: () => flip(
            current: _currentsOn,
            assign: (v) => _currentsOn = v,
          ),
        ),
        _weatherLayerTile(
          icon: Icons.thermostat,
          label: 'Wind speed heatmap',
          subtitle: 'ECMWF HRES',
          value: _windHeatmapOn,
          metadataPath: '/wind-heatmap',
          sheetSetState: sheetSetState,
          onChanged: () {
            if (_windHeatmapOn) {
              _clearHeatmap();
            } else {
              _setExclusiveHeatmap('wind');
            }
            sheetSetState(() {});
          },
        ),
        _weatherLayerTile(
          icon: Icons.water,
          label: 'Current speed heatmap',
          subtitle: 'NOAA STOFS-3D / NECOFS / FES2014',
          value: _currentHeatmapOn,
          metadataPath: '/current-heatmap',
          sheetSetState: sheetSetState,
          onChanged: () {
            if (_currentHeatmapOn) {
              _clearHeatmap();
            } else {
              _setExclusiveHeatmap('current');
            }
            sheetSetState(() {});
          },
        ),
        _weatherLayerTile(
          icon: Icons.warning_amber,
          label: 'Sea state',
          subtitle: 'Wind × current × swell',
          value: _seaStateOn,
          metadataPath: '/roughness',
          sheetSetState: sheetSetState,
          onChanged: () {
            if (_seaStateOn) {
              _clearHeatmap();
            } else {
              _setExclusiveHeatmap('seaState');
            }
            sheetSetState(() {});
          },
        ),
        _weatherLayerTile(
          icon: Icons.tsunami,
          label: 'Wave height heatmap',
          subtitle: 'Significant wave height',
          value: _waveHeatmapOn,
          metadataPath: '/wave-heatmap',
          sheetSetState: sheetSetState,
          onChanged: () {
            if (_waveHeatmapOn) {
              _clearHeatmap();
            } else {
              _setExclusiveHeatmap('wave');
            }
            sheetSetState(() {});
          },
        ),
        _weatherLayerTile(
          icon: Icons.umbrella,
          label: 'Precipitation rate',
          subtitle: 'Total precipitation rate (mm/h)',
          value: _precipHeatmapOn,
          metadataPath: '/precip-heatmap',
          sheetSetState: sheetSetState,
          onChanged: () {
            if (_precipHeatmapOn) {
              _clearHeatmap();
            } else {
              _setExclusiveHeatmap('precip');
            }
            sheetSetState(() {});
          },
        ),
        _weatherLayerTile(
          icon: Icons.thermostat,
          label: 'Air temperature',
          subtitle: 'ECMWF HRES 2 m air temperature',
          value: _temperatureHeatmapOn,
          metadataPath: '/temperature',
          sheetSetState: sheetSetState,
          onChanged: () {
            if (_temperatureHeatmapOn) {
              _clearHeatmap();
            } else {
              _setExclusiveHeatmap('temperature');
            }
            sheetSetState(() {});
          },
        ),
        _weatherLayerTile(
          icon: Icons.water_drop_outlined,
          label: 'Sea-surface temperature',
          subtitle: 'ECMWF HRES skin temperature (ocean only)',
          value: _sstHeatmapOn,
          metadataPath: '/sst',
          sheetSetState: sheetSetState,
          onChanged: () {
            if (_sstHeatmapOn) {
              _clearHeatmap();
            } else {
              _setExclusiveHeatmap('sst');
            }
            sheetSetState(() {});
          },
        ),
      ],
    );
  }

  Widget _weatherLayerTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required VoidCallback onChanged,
    required String metadataPath,
    required void Function(VoidCallback) sheetSetState,
  }) {
    final md = _weatherDataService?.metadataFor(metadataPath);
    // MetadataStore is the single source of truth for unit conversion
    // (see CLAUDE.md). Wind / current heatmaps and vector layers both
    // deal in speed; sea state is a dimensionless index with no
    // SignalK path. Null → legend falls back to SI values verbatim.
    final pathMd = _pathMetadataForLayer(metadataPath);
    // Direct MetadataStore route for layers whose conversion can't be
    // expressed as a single multiplier (temperature, precip rate).
    // Null when the path-metadata route is sufficient.
    final fmtOverride = _legendFormatterForLayer(metadataPath);

    final fallbackFloor = _fallbackZoomFloorForLayer(metadataPath);
    final currentMinZoom = _effectiveMinZoom(metadataPath, fallbackFloor);
    final showOnMap = _legendOnMap[metadataPath] ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Card(
        color: const Color(0xFF2A2A3E),
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              dense: true,
              leading: Icon(icon,
                  size: 18, color: value ? Colors.white70 : Colors.white24),
              title: Text(label,
                  style: TextStyle(
                    color: value ? Colors.white : Colors.white38,
                    fontSize: 13,
                  )),
              subtitle: Text(subtitle,
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 11)),
              trailing: Switch(value: value, onChanged: (_) => onChanged()),
            ),
            if (value && md != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LegendBar(
                      metadata: md,
                      pathMetadata: pathMd,
                      formatter: fmtOverride?.format,
                      formatterSymbol: fmtOverride?.symbol,
                    ),
                    if (md.minZoom != null &&
                        md.maxZoom != null &&
                        md.maxZoom! > md.minZoom!) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _LayerZoomDropdown(
                          minZoom: md.minZoom!,
                          maxZoom: md.maxZoom!,
                          current: currentMinZoom.clamp(
                              md.minZoom!, md.maxZoom!),
                          onChanged: (z) {
                            setState(() => _userMinZoom[metadataPath] = z);
                            sheetSetState(() {});
                            _persistLayerPrefs();
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Flexible(child: _LayerFreshnessChip(metadata: md)),
                        const Spacer(),
                        TextButton.icon(
                          icon: Icon(
                            showOnMap ? Icons.map : Icons.map_outlined,
                            size: 16,
                          ),
                          label: Text(
                            showOnMap ? 'On map ✓' : 'On map',
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: showOnMap
                                ? Colors.white
                                : Colors.white54,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                          onPressed: () {
                            setState(() {
                              _legendOnMap[metadataPath] = !showOnMap;
                            });
                            sheetSetState(() {});
                            _persistLayerPrefs();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Snapshot of which layers want an on-map legend and the data each
  /// needs to render. Consumed by `_OnMapLegendStack`. Only includes
  /// layers the user has toggled ON *and* has flagged for map-legend
  /// display; the stack itself does the final zoom-visibility check
  /// (it needs the live `MapCamera`, which only exists inside the
  /// FlutterMap subtree).
  List<_OnMapLegendEntry> _onMapLegendEntries() {
    final out = <_OnMapLegendEntry>[];
    void consider(String path, bool layerOn) {
      if (!layerOn) return;
      if (_legendOnMap[path] != true) return;
      final md = _weatherDataService?.metadataFor(path);
      if (md == null) return;
      final pathMd = _pathMetadataForLayer(path);
      final fmtOverride = _legendFormatterForLayer(path);
      final effective = _effectiveMinZoom(
          path, _fallbackZoomFloorForLayer(path));
      out.add(_OnMapLegendEntry(
        metadata: md,
        pathMetadata: pathMd,
        formatter: fmtOverride?.format,
        formatterSymbol: fmtOverride?.symbol,
        minZoom: effective,
      ));
    }

    consider('/wind', _windBarbsOn);
    consider('/currents', _currentsOn);
    consider('/wind-heatmap', _windHeatmapOn);
    consider('/current-heatmap', _currentHeatmapOn);
    consider('/roughness', _seaStateOn);
    consider('/wave-heatmap', _waveHeatmapOn);
    consider('/precip-heatmap', _precipHeatmapOn);
    consider('/temperature', _temperatureHeatmapOn);
    consider('/sst', _sstHeatmapOn);
    consider('/depth', _firstEnabled('depth') != null);
    return out;
  }

  /// Pre-metadata zoom floor per layer. Used as the final fallback
  /// when the server hasn't populated `minzoom` (older routers).
  static int _fallbackZoomFloorForLayer(String metadataPath) {
    switch (metadataPath) {
      case '/wind':
        return WeatherDataService.zoomFloorWindBarbs;
      case '/currents':
        return WeatherDataService.zoomFloorCurrents;
      case '/wind-heatmap':
        return WeatherDataService.zoomFloorWindHeatmap;
      case '/current-heatmap':
        return WeatherDataService.zoomFloorCurrentHeatmap;
      case '/roughness':
        return WeatherDataService.zoomFloorSeaState;
      case '/wave-heatmap':
        return WeatherDataService.zoomFloorWaveHeatmap;
      case '/precip-heatmap':
        return WeatherDataService.zoomFloorPrecipHeatmap;
      case '/depth':
        return WeatherDataService.zoomFloorDepth;
      case '/temperature':
        return WeatherDataService.zoomFloorTemperature;
      case '/sst':
        return WeatherDataService.zoomFloorSst;
      default:
        return 0;
    }
  }

  /// Maps a weather-layer endpoint path to a representative SignalK
  /// path whose unit category matches. `MetadataStore.get(path)`
  /// against that path applies the user's unit preference via
  /// convert/format/symbol. Returns null for layers with no direct
  /// SignalK analogue (e.g. roughness index).
  static String? _signalKPathForLayerPath(String metadataPath) {
    switch (metadataPath) {
      case '/wind':
      case '/wind-heatmap':
        return 'environment.wind.speedTrue';
      case '/currents':
      case '/current-heatmap':
        return 'environment.current.drift';
      case '/wave-heatmap':
        return 'environment.water.waves.height';
      case '/depth':
        return 'environment.depth.belowTransducer';
      case '/precip-heatmap':
        return 'environment.outside.precipitationRate';
      case '/temperature':
        return 'environment.outside.temperature';
      case '/sst':
        return 'environment.water.temperature';
      case '/roughness':
      default:
        return null;
    }
  }

  /// Unit category per weather layer, used as the `getWithFallback`
  /// fallback key when the path-specific `PathMetadata` hasn't been
  /// populated in the store.
  static String? _signalKCategoryForLayerPath(String metadataPath) {
    switch (metadataPath) {
      case '/wind':
      case '/wind-heatmap':
      case '/currents':
      case '/current-heatmap':
        return 'speed';
      case '/wave-heatmap':
        // No `height` category on SignalK servers; wave height shares
        // the same SI unit (meters) as depth, so the depth preference
        // is the natural twin (feet of swell pairs with feet of
        // depth).
        return 'depth';
      case '/depth':
        return 'depth';
      case '/precip-heatmap':
        return 'rainfall';
      case '/temperature':
      case '/sst':
        return 'temperature';
      case '/roughness':
      default:
        return null;
    }
  }

  /// Look up `PathMetadata` for a weather layer, preferring the exact
  /// SignalK path but falling through to its category entry
  /// (`__category__.<cat>`) when the path itself isn't populated —
  /// which matches CLAUDE.md's rule that unit conversion MUST route
  /// through `MetadataStore`, even for quantities the user's vessel
  /// doesn't itself publish.
  PathMetadata? _pathMetadataForLayer(String metadataPath) {
    final path = _signalKPathForLayerPath(metadataPath);
    final category = _signalKCategoryForLayerPath(metadataPath);
    if (path == null) return null;
    final store = widget.signalKService.metadataStore;
    return store.getWithFallback(
      path,
      (_) => category,
    );
  }

  /// Build a per-layer legend formatter that calls [MetadataStore]
  /// directly for layers whose conversions don't reduce to a single
  /// multiplicative factor — temperature is affine and the
  /// precipitation rate combines a length conversion with a fixed
  /// time scale (s → h).
  ///
  /// Diverges intentionally from the OpenMeteo sister: the OpenMeteo
  /// version reaches into `ConversionService` (from `openmeteo_core`)
  /// because its `MetadataShim` deliberately doesn't synthesise
  /// affine / rate `PathMetadata`. SignalK's `MetadataStore` is
  /// server-fed, so we ask it for the published `PathMetadata`
  /// directly and lean on the server's `formula` / `symbol`. Returns
  /// `null` for layers where `pathMetadata.format(...)` is sufficient.
  ({String Function(double) format, String symbol})?
      _legendFormatterForLayer(String metadataPath) {
    final store = widget.signalKService.metadataStore;
    switch (metadataPath) {
      case '/temperature':
      case '/sst':
        // Server publishes meta on the temperature category (formula
        // performs K → °C/°F via math_expressions). When unavailable,
        // fall through to raw SI display by returning null.
        final md = store.getWithFallback(
          metadataPath == '/sst'
              ? 'environment.water.temperature'
              : 'environment.outside.temperature',
          (_) => 'temperature',
        );
        if (md == null || md.symbol == null) return null;
        final symbol = md.symbol!;
        return (
          format: (si) => md.format(si, decimals: 1),
          symbol: symbol,
        );
      case '/precip-heatmap':
        // Server emits mm/s; the rainfall PathMetadata (length
        // conversion, e.g. mm → in) handles the unit side. We pre-
        // multiply by 3600 to land at user-pref / hour. The s → h
        // factor is the only fixed scale; everything else is server
        // published.
        final md = store.getWithFallback(
          'environment.outside.precipitationRate',
          (_) => 'rainfall',
        );
        if (md == null || md.symbol == null) return null;
        final symbol = md.symbol!;
        return (
          // `md.format` would return e.g. "0.5 mm" — losing the rate
          // suffix that the legend heading promises. Convert manually
          // and re-suffix with `/h` so the tick label matches the
          // heading the user is reading off.
          format: (si) {
            final converted = md.convert(si * 3600.0);
            if (converted == null) {
              return (si * 3600.0).toStringAsFixed(1);
            }
            return '${converted.toStringAsFixed(1)} $symbol/h';
          },
          symbol: '$symbol/h',
        );
      default:
        return null;
    }
  }

  /// Distance in metres from a point to the nearest land bounding box.
  /// Uses equirectangular approximation — good enough for a zoom
  /// heuristic at sub-degree scales.
  double _nearestLandMeters(double lat, double lon) {
    final landBounds = _tileManager?.landBounds;
    if (landBounds == null || landBounds.isEmpty) return double.infinity;
    final mPerDegLat = 111320.0;
    final mPerDegLon = 111320.0 * math.cos(lat * math.pi / 180);
    var best = double.infinity;
    for (final b in landBounds) {
      final dLat = math.max(
          0.0, math.max(b.south - lat, lat - b.north));
      final dLon = math.max(
          0.0, math.max(b.west - lon, lon - b.east));
      final dx = dLon * mPerDegLon;
      final dy = dLat * mPerDegLat;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d < best) best = d;
    }
    return best;
  }

  /// V1's auto-zoom policy (chart_webview.dart:1345-1371). Only kicks
  /// in when moving (>0.3 m/s) and auto-zoom is engaged. If land is
  /// within 15 min at current speed, tightens to `nearestLand * 1.3`;
  /// otherwise a 30-min look-ahead area. Camera fit clamped to 10..16.
  void _applyAutoZoom() {
    if (!_autoFollow || !_autoZoom || !_mapReady) return;
    final sog = _ownSog ?? 0.0;
    if (sog <= 0.3) return;
    final lat = _ownLat;
    final lon = _ownLon;
    if (lat == null || lon == null) return;

    double nearestLand = double.infinity;
    if (sog > 0.5) {
      nearestLand = _nearestLandMeters(lat, lon);
    }
    final landThreshold = sog * 900; // 15 min
    double bufferDist;
    if (nearestLand < landThreshold && nearestLand.isFinite) {
      bufferDist = math.max(nearestLand * 1.3, 300);
    } else {
      bufferDist = math.max(sog * 1800, 500);
    }

    // Convert metres to lat/lon deltas so we can build a LatLngBounds.
    final dLat = bufferDist / 111320.0;
    final dLon = bufferDist / (111320.0 * math.cos(lat * math.pi / 180));
    final bounds = LatLngBounds(
      LatLng(lat - dLat, lon - dLon),
      LatLng(lat + dLat, lon + dLon),
    );
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        maxZoom: 16,
        minZoom: 10,
      ),
    );
  }

}

class _S57OverlayLayer extends StatelessWidget {
  const _S57OverlayLayer({
    required this.tileCache,
    required this.generation,
    required this.colorTable,
    required this.spriteAtlas,
    required this.spriteImage,
    this.hiddenClasses = const <String>{},
    this.enabledChartIds = const <String>{},
    this.chartOpacities = const <String, double>{},
    this.depthMetadata,
  });
  final Map<S57TileKey, S57ParsedTile> tileCache;
  final int generation;
  final S52ColorTable colorTable;
  final SpriteAtlas spriteAtlas;
  final ui.Image spriteImage;
  final Set<String> hiddenClasses;
  /// Chart ids the user currently has enabled in the layer panel.
  /// Features whose `chartId` is not in this set are skipped at paint
  /// time — toggling a chart on/off has no fetch cost because the
  /// manager keeps fetched contributions in cache regardless.
  final Set<String> enabledChartIds;

  /// Per-chart opacity (0..1) sourced from the layer panel's per-row
  /// slider. Chart ids missing from the map render at full opacity.
  /// The painter wraps each chart's features in a `saveLayer` only
  /// when opacity < 1, so the common all-opaque case stays cheap.
  final Map<String, double> chartOpacities;
  // Routed straight through to the painter so SOUNDG depth labels
  // can be formatted via MetadataStore at paint time. Null until
  // SignalK populates the unit-preference store; painter falls back
  // to raw metres in that case.
  final PathMetadata? depthMetadata;

  /// Below this zoom the S-57 overlay is suppressed entirely. Pure
  /// vector ENC content at very wide-area zooms paints as a noisy
  /// mat of tiny triangles — there's nothing useful for the user
  /// to see, and the tile manager's per-chart minZoom typically
  /// blocks fetches anyway.
  static const double _minRenderZoom = 8.0;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    if (camera.zoom < _minRenderZoom) {
      return const SizedBox.shrink();
    }
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _S57Painter(
          camera: camera,
          tiles: tileCache,
          generation: generation,
          colorTable: colorTable,
          spriteAtlas: spriteAtlas,
          spriteImage: spriteImage,
          hiddenClasses: hiddenClasses,
          enabledChartIds: enabledChartIds,
          chartOpacities: chartOpacities,
          depthMetadata: depthMetadata,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _S57Painter extends CustomPainter {
  _S57Painter({
    required this.camera,
    required this.tiles,
    required this.generation,
    required this.colorTable,
    required this.spriteAtlas,
    required this.spriteImage,
    this.hiddenClasses = const <String>{},
    this.enabledChartIds = const <String>{},
    this.chartOpacities = const <String, double>{},
    this.depthMetadata,
  });
  final MapCamera camera;
  final Map<S57TileKey, S57ParsedTile> tiles;
  // Cache-mutation counter from the manager. Compared in shouldRepaint
  // because `tiles` is a stable reference (the manager mutates in
  // place), so reference comparison alone misses evictions.
  final int generation;
  final S52ColorTable colorTable;
  final SpriteAtlas spriteAtlas;
  final ui.Image spriteImage;
  // S-57 object classes the user has hidden via the configurator.
  // Features whose `objectClass` is in this set are skipped in the
  // draw pass — the geometry still lives in the parsed tile cache.
  final Set<String> hiddenClasses;
  // Chart ids the user has enabled in the layer panel. Features whose
  // `chartId` is not in this set are skipped — toggle is instant.
  final Set<String> enabledChartIds;
  // Per-chart opacity from the layer panel. Each chart's features are
  // wrapped in a `saveLayer` with this alpha when < 1.0; missing or
  // 1.0 entries skip the layer save and paint at full opacity.
  final Map<String, double> chartOpacities;
  // PathMetadata for the user's depth unit preference. SOUNDG label
  // text is formatted through this so the chart honours the same
  // m/ft/fa preset as the rest of the app (CLAUDE.md SSOT). Null
  // when MetadataStore has no depth entry yet — painter falls back
  // to raw metres rounded to integer.
  final PathMetadata? depthMetadata;

  @override
  void paint(Canvas canvas, Size size) {
    if (tiles.isEmpty) return;
    // Canonical flutter_map layer coordinate space: pixel positions
    // relative to `camera.pixelOrigin` (the top-left of the viewport
    // at the current zoom). `MobileLayerTransformer` handles rotation
    // around this painter, so we don't touch rotation here.
    final origin = camera.pixelOrigin;
    Offset project(LatLng p) => camera.projectAtZoom(p) - origin;

    // Cross-zoom fallback ordering: tiles farther from the active zoom
    // draw first (under), active-z tiles draw last (on top). Within the
    // same z-distance, lower-z (less detail) draws under higher-z.
    // This eliminates blank gaps during zoom transitions — adjacent-z
    // tiles fill in until the active-z fetch arrives.
    final activeZ = camera.zoom.round();
    final sorted = tiles.entries.toList()
      ..sort((a, b) {
        final da = (a.key.z - activeZ).abs();
        final db = (b.key.z - activeZ).abs();
        if (da != db) return db.compareTo(da);
        return a.key.z.compareTo(b.key.z);
      });

    // Sounding declutter — reset every frame. Below z=11 the spot
    // soundings stack into an unreadable wall; we keep only one label
    // per ~40 px screen radius so the chart stays legible. At z >= 11
    // the natural density is manageable and we draw every sounding.
    // The user-facing on/off toggle that used to force this at lower
    // zooms was removed — the auto-cutoff is the only mode now.
    _drawnSoundings.clear();
    _soundingDeclutterActive = camera.zoom < 11;

    // Three passes by geometry kind — polygons (area fills + patterns)
    // on the bottom, lines in the middle, points on top. This
    // approximates S-52's priority bands (group1 areas → line symbols
    // → point symbols) without needing per-feature priority data from
    // the engine. A finer-grained priority sort lives behind a later
    // task, once the lookup row's priority is threaded through.
    //
    // Within each geometry pass, features are bucketed by `chartId`
    // so per-chart opacity from the layer panel can be applied via
    // `saveLayer` once per chart per pass. Bucket draw *order*
    // follows `enabledChartIds` (which the chart plotter builds by
    // walking `_layers` in panel order), so dragging an S-57 row in
    // the panel is what controls cross-chart z-order in overlap
    // areas. Cross-zoom ordering within each chart is preserved
    // because we walk `sorted` in cross-zoom order while filling
    // each bucket.
    for (final kind in _paintOrder) {
      final byChart = <String, List<S57StyledFeature>>{};
      for (final entry in sorted) {
        for (final f in entry.value.features) {
          if (f.geometry.kind != kind) continue;
          if (hiddenClasses.contains(f.objectClass)) continue;
          if (!enabledChartIds.contains(f.chartId)) continue;
          byChart.putIfAbsent(f.chartId, () => <S57StyledFeature>[]).add(f);
        }
      }
      // Iterate in `enabledChartIds` order (panel order, courtesy of
      // Dart's default `LinkedHashSet`), NOT `byChart.entries` order
      // (which is feature-encounter order and ignores the panel).
      for (final chartId in enabledChartIds) {
        final features = byChart[chartId];
        if (features == null || features.isEmpty) continue;
        final opacity = (chartOpacities[chartId] ?? 1.0).clamp(0.0, 1.0);
        final useLayer = opacity < 0.999;
        if (useLayer) {
          // saveLayer with an alpha-only paint stamps every draw
          // inside it through that alpha when restored.
          canvas.saveLayer(
            null,
            Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
          );
        }
        for (final f in features) {
          _paintFeature(canvas, f, project);
        }
        if (useLayer) canvas.restore();
      }
    }
  }

  // Drawn-sounding positions in screen-pixel space, populated during
  // a single paint pass. Mutated as we walk SOUNDG features to skip
  // any whose anchor sits within `_soundingMinSpacing` of an already-
  // placed label.
  final List<Offset> _drawnSoundings = [];
  bool _soundingDeclutterActive = false;
  static const double _soundingMinSpacing = 40.0;

  static const _paintOrder = [
    S57GeomKind.polygon,
    S57GeomKind.line,
    S57GeomKind.point,
  ];

  void _paintFeature(
      Canvas canvas, S57StyledFeature f, Offset Function(LatLng) project) {
    for (final instruction in f.instructions) {
      if (instruction is S52Symbol && f.geometry.kind == S57GeomKind.point) {
        final meta = spriteAtlas.lookup(instruction.name);
        if (meta == null) {
          // Symbol not in atlas — fall back to a small CHBLK dot so
          // the feature is at least locatable. Useful for catching
          // missing-sprite cases during development.
          final paint = Paint()..color = _resolve('CHBLK');
          for (final p in f.geometry.points) {
            canvas.drawCircle(project(p), 2, paint);
          }
          continue;
        }
        final srcRect = Rect.fromLTWH(
          meta.x.toDouble(),
          meta.y.toDouble(),
          meta.width.toDouble(),
          meta.height.toDouble(),
        );
        final paint = Paint()..filterQuality = FilterQuality.low;
        for (final p in f.geometry.points) {
          final s = project(p);
          final dstRect = Rect.fromLTWH(
            s.dx - meta.pivotX,
            s.dy - meta.pivotY,
            meta.width.toDouble(),
            meta.height.toDouble(),
          );
          canvas.drawImageRect(spriteImage, srcRect, dstRect, paint);
        }
      } else if (instruction is S52LineStyle) {
        // S-52 uses LS() for both polyline geometries AND polygon
        // outlines (e.g. RESARE's dashed magenta border, EXEZNE's
        // patterned edge). Walk lines for line features, walk every
        // ring for polygon features. Point features fall through —
        // both collections are empty.
        final paint = Paint()
          ..color = _resolve(instruction.colorCode)
          ..strokeWidth = instruction.width.toDouble().clamp(1, 4)
          ..style = PaintingStyle.stroke;
        final dash = _dashIntervals(instruction.pattern);
        for (final line in f.geometry.lines) {
          final path = _linePath(line, project);
          canvas.drawPath(dash == null ? path : _dashPath(path, dash), paint);
        }
        for (final polygon in f.geometry.rings) {
          for (final ring in polygon) {
            final path = _linePath(ring, project);
            canvas.drawPath(dash == null ? path : _dashPath(path, dash), paint);
          }
        }
      } else if (instruction is S52LineComplex) {
        // Same logic for complex (sprite-stamped) lines on both line
        // and polygon outlines.
        _paintLineComplex(canvas, instruction.patternName, f, project);
      } else if (instruction is S52AreaColor &&
          f.geometry.kind == S57GeomKind.polygon) {
        // S-52 AC(CODE,TRANS): TRANS is a 0–4 transparency level.
        // 4 = fully transparent → skip the draw entirely.
        if (instruction.transparency >= 4) continue;
        final base = _resolve(instruction.colorCode);
        final paint = Paint()
          ..color = base.withAlpha(instruction.transparencyAlpha)
          ..style = PaintingStyle.fill;
        for (final polygon in f.geometry.rings) {
          canvas.drawPath(_polygonPath(polygon, project), paint);
        }
      } else if (instruction is S52AreaPattern &&
          f.geometry.kind == S57GeomKind.polygon) {
        _paintAreaPattern(canvas, instruction.patternName, f, project);
      } else if (instruction is S52TextLiteral &&
          f.geometry.kind == S57GeomKind.point) {
        // Computed labels from CS procedures — currently only SOUNDG02
        // depth soundings. Kept on the canvas because soundings are
        // core navigation info; everything else (object names,
        // formatted descriptions) is suppressed below to declutter.
        //
        // For SOUNDG we re-format the depth at paint time via
        // MetadataStore (per CLAUDE.md: never do manual conversions
        // in widgets, never bake unit assumptions into a sub-library).
        // The engine's `instruction.text` is metres rounded — we
        // ignore it and read the raw DEPTH/VALSOU attribute, in
        // metres, then call `metadata.format(...)` so the user's
        // m/ft/fa preset wins. Other text literals (none today, but
        // the engine may emit them later for object names etc.) pass
        // through unchanged.
        String displayText = instruction.text;
        if (f.objectClass == 'SOUNDG') {
          final depthM = _readDepthMetres(f.attributes);
          if (depthM == null) continue;
          // Convert via MetadataStore (CLAUDE.md SSOT) but drop the
          // unit symbol — chart soundings are bare numbers; the unit
          // belongs in the chart legend, not on every sprite.
          final display = depthMetadata?.convert(depthM) ?? depthM;
          displayText = display.toStringAsFixed(0);
        }
        if (f.objectClass == 'SOUNDG' && _soundingDeclutterActive) {
          // Declutter: keep only soundings whose anchor sits at least
          // `_soundingMinSpacing` pixels from every already-placed
          // label. First-come-first-served within the current paint
          // pass; the tile sort order above already prioritises the
          // active-zoom tiles last, so their labels win ties.
          final anchors = <LatLng>[];
          for (final p in f.geometry.points) {
            final s = project(p);
            var ok = true;
            for (final q in _drawnSoundings) {
              if ((s - q).distanceSquared <
                  _soundingMinSpacing * _soundingMinSpacing) {
                ok = false;
                break;
              }
            }
            if (!ok) continue;
            _drawnSoundings.add(s);
            anchors.add(p);
          }
          if (anchors.isEmpty) continue;
          _paintText(canvas, displayText, anchors, project);
        } else {
          _paintText(canvas, displayText, f.geometry.points, project);
        }
      }
      // Suppressed — attribute-driven labels (S52Text, e.g. OBJNAM
      // buoy/light names) and printf-formatted labels (S52TextFormatted)
      // overwhelm the canvas without OL-style decluttering. Tap a
      // feature to see these in the popover.
    }
  }

  /// Stamp a sprite repeatedly along the line's polylines, rotated to
  /// match each segment direction. S-52's LC() complex lines assume a
  /// tile spacing equal to the sprite's native width; we keep it
  /// simple and do the same. Uses `PathMetric.extractPath` to walk at
  /// fixed intervals with correct tangent direction per stamp.
  void _paintLineComplex(
    Canvas canvas,
    String patternName,
    S57StyledFeature f,
    Offset Function(LatLng) project,
  ) {
    final meta = spriteAtlas.lookup(patternName);
    if (meta == null) return;
    final srcRect = Rect.fromLTWH(
      meta.x.toDouble(),
      meta.y.toDouble(),
      meta.width.toDouble(),
      meta.height.toDouble(),
    );
    final stamp = meta.width.toDouble();
    if (stamp <= 0) return;
    final paint = Paint()..filterQuality = FilterQuality.low;
    final dstSize = Size(stamp, meta.height.toDouble());

    void stampAlong(ui.Path path) {
      for (final metric in path.computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += stamp) {
          final tangent = metric.getTangentForOffset(d);
          if (tangent == null) break;
          canvas.save();
          canvas.translate(tangent.position.dx, tangent.position.dy);
          canvas.rotate(tangent.angle);
          canvas.drawImageRect(
            spriteImage,
            srcRect,
            Rect.fromLTWH(0, -dstSize.height / 2, dstSize.width, dstSize.height),
            paint,
          );
          canvas.restore();
        }
      }
    }

    for (final line in f.geometry.lines) {
      stampAlong(_linePath(line, project));
    }
    // Polygon outlines: stamp around every ring (outer + holes). S-52
    // uses LC() on areas (e.g. NAVARE51 around fairways) the same way
    // it uses LC() on linear navarea boundaries.
    for (final polygon in f.geometry.rings) {
      for (final ring in polygon) {
        stampAlong(_linePath(ring, project));
      }
    }
  }

  /// Tile a sprite across the polygon interior. Freeboard's
  /// area-pattern symbols (DRGARE51, ACHARE02, etc.) are designed to
  /// tile seamlessly at their native sprite dimensions. We clip to the
  /// polygon and draw a grid of `drawImageRect` calls over its
  /// bounding box. Crude but correct for visual parity.
  void _paintAreaPattern(
    Canvas canvas,
    String patternName,
    S57StyledFeature f,
    Offset Function(LatLng) project,
  ) {
    final meta = spriteAtlas.lookup(patternName);
    if (meta == null) return;
    final srcRect = Rect.fromLTWH(
      meta.x.toDouble(),
      meta.y.toDouble(),
      meta.width.toDouble(),
      meta.height.toDouble(),
    );
    final paint = Paint()..filterQuality = FilterQuality.low;
    for (final polygon in f.geometry.rings) {
      final path = _polygonPath(polygon, project);
      final bounds = path.getBounds();
      if (bounds.isEmpty) continue;
      canvas.save();
      canvas.clipPath(path);
      final w = meta.width.toDouble();
      final h = meta.height.toDouble();
      for (var y = bounds.top; y < bounds.bottom; y += h) {
        for (var x = bounds.left; x < bounds.right; x += w) {
          canvas.drawImageRect(
            spriteImage,
            srcRect,
            Rect.fromLTWH(x, y, w, h),
            paint,
          );
        }
      }
      canvas.restore();
    }
  }

  /// Crude text rendering. Real S-52 uses the TE/TX parameter list for
  /// font, size, colour, justification and per-character offsets.
  /// For the spike we centre the label on the feature point in CHBLK
  /// at a fixed 11pt; that's enough to verify SOUNDG depth labels are
  /// landing in roughly the right place.
  void _paintText(Canvas canvas, String text, List<LatLng> anchors,
      Offset Function(LatLng) project) {
    if (text.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: _resolve('CHBLK'),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    final half = Offset(painter.width / 2, painter.height / 2);
    for (final p in anchors) {
      painter.paint(canvas, project(p) - half);
    }
  }

  /// Map an S-52 line pattern to an on/off interval list in pixels.
  /// Returns null for SOLD (no dashing). Numbers chosen to match the
  /// visual weight of Freeboard's output — the S-52 spec allows
  /// renderer latitude here.
  List<double>? _dashIntervals(S52LinePattern pattern) {
    switch (pattern) {
      case S52LinePattern.solid:
        return null;
      case S52LinePattern.dash:
        return const [6.0, 4.0];
      case S52LinePattern.dott:
        return const [1.5, 3.0];
    }
  }

  /// Rebuild a path as a sequence of dash/gap segments along its
  /// polylines. Works by walking `PathMetric` and extracting sub-paths
  /// at each interval boundary — Flutter's stock approach for dashed
  /// strokes since the framework doesn't expose PathEffect.
  ui.Path _dashPath(ui.Path source, List<double> intervals) {
    final out = ui.Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0.0;
      var on = true;
      var i = 0;
      while (distance < metric.length) {
        final span = intervals[i % intervals.length];
        final next = distance + span;
        if (on) {
          out.addPath(
            metric.extractPath(distance, next.clamp(0, metric.length)),
            Offset.zero,
          );
        }
        distance = next;
        on = !on;
        i++;
      }
    }
    return out;
  }

  ui.Path _linePath(List<LatLng> line, Offset Function(LatLng) project) {
    final path = ui.Path();
    for (var i = 0; i < line.length; i++) {
      final s = project(line[i]);
      if (i == 0) {
        path.moveTo(s.dx, s.dy);
      } else {
        path.lineTo(s.dx, s.dy);
      }
    }
    return path;
  }

  /// Build a single Path covering a polygon and its holes. Using
  /// `PathFillType.evenOdd` lets a single draw call handle outer ring
  /// + holes correctly without separate clip operations.
  ui.Path _polygonPath(
      List<List<LatLng>> rings, Offset Function(LatLng) project) {
    final path = ui.Path()..fillType = ui.PathFillType.evenOdd;
    for (final ring in rings) {
      if (ring.isEmpty) continue;
      for (var i = 0; i < ring.length; i++) {
        final s = project(ring[i]);
        if (i == 0) {
          path.moveTo(s.dx, s.dy);
        } else {
          path.lineTo(s.dx, s.dy);
        }
      }
      path.close();
    }
    return path;
  }

  /// Resolve an S-52 colour code. Falls back to CHBLK so unknown codes
  /// still draw (visible but obviously wrong) rather than crashing.
  Color _resolve(String code) {
    final c = colorTable.lookup(code) ?? colorTable.lookup('CHBLK');
    if (c == null) return const Color(0xFF000000);
    return Color(c.toArgb32());
  }

  /// Pulls the raw depth in metres from a SOUNDG feature's attribute
  /// map. Mirrors what s52_dart's `soundg02` procedure does (DEPTH
  /// preferred, VALSOU as fallback) but stays in SI so the painter
  /// can hand it to MetadataStore for unit conversion / formatting.
  static double? _readDepthMetres(Map<String, Object?> attrs) {
    for (final key in const ['DEPTH', 'VALSOU']) {
      final raw = attrs[key];
      if (raw == null) continue;
      if (raw is num) return raw.toDouble();
      final n = num.tryParse(raw.toString());
      if (n != null) return n.toDouble();
    }
    return null;
  }

  @override
  bool shouldRepaint(covariant _S57Painter old) =>
      old.camera != camera ||
      old.generation != generation ||
      old.colorTable != colorTable ||
      old.spriteAtlas != spriteAtlas ||
      old.spriteImage != spriteImage ||
      old.depthMetadata != depthMetadata ||
      old.hiddenClasses.length != hiddenClasses.length ||
      !old.hiddenClasses.containsAll(hiddenClasses) ||
      !_orderedSetEqual(old.enabledChartIds, enabledChartIds) ||
      !_chartOpacitiesEqual(old.chartOpacities, chartOpacities);

  /// Order-sensitive compare for `enabledChartIds`. Both sets are
  /// `LinkedHashSet`s built by walking `_layers` in panel order, and
  /// the painter uses that order for cross-chart paint sequence, so
  /// a reorder with the same membership must still trigger a repaint.
  static bool _orderedSetEqual(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    final ai = a.iterator;
    final bi = b.iterator;
    while (ai.moveNext() && bi.moveNext()) {
      if (ai.current != bi.current) return false;
    }
    return true;
  }

  static bool _chartOpacitiesEqual(
      Map<String, double> a, Map<String, double> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null || other != entry.value) return false;
    }
    return true;
  }
}

/// Paints the vessel's recent track. Matches V1's gradient-faded
/// 5-segment rendering (chart_webview.dart:1220-1249). Trail divides
/// into up to 5 equal-length segments; segment alpha ramps from 0.15
/// at the oldest to 0.8 at the newest. All segments are blue
/// `rgba(33,150,243,α)` stroked at width 2 with dash 6-4.
class _TrailOverlayLayer extends StatelessWidget {
  const _TrailOverlayLayer({required this.points, required this.timestamps});
  final List<LatLng> points;
  final List<int> timestamps;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _TrailPainter(
          camera: camera,
          points: points,
          timestamps: timestamps,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _TrailPainter extends CustomPainter {
  _TrailPainter({
    required this.camera,
    required this.points,
    required this.timestamps,
  });
  final MapCamera camera;
  final List<LatLng> points;
  final List<int> timestamps;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final origin = camera.pixelOrigin;
    final screen = points
        .map((p) => camera.projectAtZoom(p) - origin)
        .toList(growable: false);

    // V1 splits the polyline into `min(n-1, 5)` chunks. Each chunk's
    // alpha = 0.15 + 0.65 * (i / (segCount - 1)) → 0.15 … 0.8.
    final segCount = math.min(screen.length - 1, 5);
    final segLen = (screen.length / segCount).floor();
    for (var s = 0; s < segCount; s++) {
      final start = s * segLen;
      final end = s == segCount - 1 ? screen.length : (s + 1) * segLen + 1;
      if (end - start < 2) continue;
      final alpha = segCount == 1
          ? 0.8
          : 0.15 + 0.65 * (s / (segCount - 1));
      final path = ui.Path()..moveTo(screen[start].dx, screen[start].dy);
      for (var i = start + 1; i < end; i++) {
        path.lineTo(screen[i].dx, screen[i].dy);
      }
      canvas.drawPath(
        _dash(path, const [6, 4]),
        Paint()
          ..color = Color.fromRGBO(33, 150, 243, alpha)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  ui.Path _dash(ui.Path source, List<double> intervals) {
    final out = ui.Path();
    for (final metric in source.computeMetrics()) {
      double d = 0;
      var on = true;
      var i = 0;
      while (d < metric.length) {
        final next = d + intervals[i % intervals.length];
        if (on) {
          out.addPath(
            metric.extractPath(d, next.clamp(0, metric.length)),
            Offset.zero,
          );
        }
        d = next;
        on = !on;
        i++;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _TrailPainter old) =>
      old.camera != camera ||
      old.points.length != points.length ||
      (points.isNotEmpty && old.points.last != points.last);
}

/// Scale bar matching V1's OpenLayers `ScaleLine` configuration
/// (chart_webview.dart:992-998):
///   `{ units: 'nautical'|'metric'|'imperial', bar: true, steps: 4,
///      text: true, minWidth: 120 }`
///
/// That renders a 4-step checkered bar (alternating black/white
/// segments with tick separators), a "0" label at the left and the
/// total value+unit label at the right. Units come from
/// MetadataStore's `distance` category via `convertToSI`/`format`
/// per the SSOT rule — no factor multiplication.
class _MetadataScaleBar extends StatelessWidget {
  const _MetadataScaleBar({required this.distance});
  final PathMetadata? distance;

  // Candidate rounded display-unit totals. First segment has length
  // total/steps, so we pick totals that divide by 4 cleanly where
  // possible. V1's OL uses an internal table; this set covers the
  // same magnitudes for metric / nautical / imperial preferences.
  static const _niceTotals = <double>[
    0.001, 0.002, 0.004, 0.01, 0.02, 0.04, 0.1, 0.2, 0.4,
    1, 2, 4, 10, 20, 40, 100, 200, 400,
    1000, 2000, 4000,
  ];

  static const _steps = 4;
  static const _minWidth = 120.0; // matches OL's `minWidth: 120`

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final center = camera.center;
    const dist = Distance();
    // px-per-metre at current zoom via a 1 km east offset.
    final eastLatLng = dist.offset(center, 1000, 90);
    final pxPerMetre =
        (camera.projectAtZoom(eastLatLng).dx -
                camera.projectAtZoom(center).dx)
            .abs() /
            1000.0;
    if (pxPerMetre <= 0) return const SizedBox.shrink();

    double displayToMetres(double display) =>
        distance?.convertToSI(display) ?? display;

    // Smallest total whose pixel width is ≥ minWidth. V1 renders the
    // first candidate that clears minWidth; if none do (extremely
    // zoomed-in), fall back to the largest available.
    double chosenDisplay = _niceTotals.last;
    double chosenMetres = displayToMetres(chosenDisplay);
    for (final t in _niceTotals) {
      final m = displayToMetres(t);
      final px = m * pxPerMetre;
      if (px >= _minWidth) {
        chosenDisplay = t;
        chosenMetres = m;
        break;
      }
    }
    final barWidthPx = chosenMetres * pxPerMetre;
    if (!barWidthPx.isFinite || barWidthPx <= 0) {
      return const SizedBox.shrink();
    }

    final decimals = chosenDisplay < 0.01
        ? 3
        : chosenDisplay < 1
            ? 2
            : 0;
    final endLabel = distance?.format(chosenMetres, decimals: decimals) ??
        '${chosenMetres.toStringAsFixed(decimals)} m';

    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 64),
        child: CustomPaint(
          size: Size(barWidthPx + 40, 28),
          painter: _StepBarPainter(
            widthPx: barWidthPx,
            steps: _steps,
            endLabel: endLabel,
          ),
        ),
      ),
    );
  }
}

/// 4-step checkered scale bar. Alternating black + white rectangles
/// with black outline and tick separators; "0" label at the left
/// end, total+unit label at the right end. Labels have a dark
/// shadow so they read against any basemap colour.
class _StepBarPainter extends CustomPainter {
  _StepBarPainter({
    required this.widthPx,
    required this.steps,
    required this.endLabel,
  });
  final double widthPx;
  final int steps;
  final String endLabel;

  @override
  void paint(Canvas canvas, Size size) {
    const barHeight = 6.0;
    final barY = size.height - 14;
    final segW = widthPx / steps;

    final outlinePaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final blackFill = Paint()..color = Colors.black;
    final whiteFill = Paint()..color = Colors.white;

    // Alternating filled segments — segment 0 black, 1 white, 2 black, 3 white.
    for (var i = 0; i < steps; i++) {
      final rect = Rect.fromLTWH(i * segW, barY, segW, barHeight);
      canvas.drawRect(rect, i.isEven ? blackFill : whiteFill);
    }
    // Outline the full bar.
    canvas.drawRect(
      Rect.fromLTWH(0, barY, widthPx, barHeight),
      outlinePaint,
    );
    // Tick marks above the bar at each segment boundary (inclusive).
    for (var i = 0; i <= steps; i++) {
      final x = i * segW;
      canvas.drawLine(
        Offset(x, barY - 4),
        Offset(x, barY),
        outlinePaint,
      );
    }

    // "0" at the left, total label at the right — both sit above the
    // bar, centred on their endpoint tick.
    _drawLabel(canvas, '0', Offset(0, barY - 4));
    _drawLabel(canvas, endLabel, Offset(widthPx, barY - 4));
  }

  void _drawLabel(Canvas canvas, String text, Offset tickTop) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          shadows: [Shadow(color: Color(0xE6000000), blurRadius: 2)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        tickTop.dx - painter.width / 2,
        tickTop.dy - painter.height - 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _StepBarPainter old) =>
      old.widthPx != widthPx ||
      old.steps != steps ||
      old.endLabel != endLabel;
}

class _TappedFeature {
  _TappedFeature({
    required this.layer,
    required this.properties,
    required this.screenPos,
    required this.displayPriority,
    required this.kind,
  });
  final String layer;
  final Map<String, Object?> properties;
  final Offset screenPos;
  final int displayPriority;
  final S57GeomKind kind;
  bool get isPoint => kind == S57GeomKind.point;
}

class _TapGroup {
  _TapGroup({
    required this.center,
    required this.kind,
    required this.maxPriority,
    required this.members,
  });
  final Offset center;
  final S57GeomKind kind;
  int maxPriority;
  final List<_TappedFeature> members;
  bool get isPoint => kind == S57GeomKind.point;
}

/// Renders one grouped feature's attributes. All formatting rules
/// are ported from V1 (chart_webview.dart:2216-2331):
///   • Depth attrs (DEPTH/VALSOU/DRVAL1/DRVAL2/VALDCO) use depth
///     metadata factor/unit — convert raw metres to user preference.
///   • Height attrs (HEIGHT/VERLEN/HORLEN/HORWID) use height metadata.
///   • SIGPER shown as seconds ("Xs" — V1 convention).
///   • VALNMR shown in nautical miles ("X NM" — S-57 stores the
///     value in NM directly per IHO spec, so no conversion needed).
///   • CONRAD / CONVIS → "Yes" / "No".
///   • COLOUR / WATLEV / CATOBS / CATWRK / BOYSHP / BCNSHP / CATLAM /
///     CATCAM / CATLIT / LITCHR / CONDTN / STATUS / RESTRN / COLPAT /
///     TOPSHP / CATSPM are code-decoded via lookup tables.
///   • Attribute order matches V1's _displayOrder; unknown keys are
///     skipped the same way V1 does.
class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.member,
    required this.depth,
    required this.height,
  });
  final _TappedFeature member;
  final PathMetadata? depth;
  final PathMetadata? height;

  static const _depthKeys = {'DEPTH', 'VALSOU', 'DRVAL1', 'DRVAL2', 'VALDCO'};
  static const _heightKeys = {'HEIGHT', 'VERLEN', 'HORLEN', 'HORWID'};

  static const _displayOrder = [
    'OBJNAM', 'NOBJNM', 'INFORM', 'NINFOM',
    'DEPTH', 'VALSOU', 'DRVAL1', 'DRVAL2', 'VALDCO',
    'CATWRK', 'CATOBS', 'WATLEV',
    'CATLAM', 'CATCAM', 'CATSPM', 'BOYSHP', 'BCNSHP', 'TOPSHP',
    'COLOUR', 'COLPAT', 'LITCHR', 'CATLIT', 'SIGPER', 'VALNMR',
    'HEIGHT', 'RESTRN', 'CONDTN', 'STATUS', 'CONRAD', 'CONVIS',
    'VERLEN', 'HORLEN', 'HORWID',
  ];

  static const _attributeLabels = <String, String>{
    'OBJNAM': 'Name', 'NOBJNM': 'Local Name',
    'INFORM': 'Information', 'NINFOM': 'Note',
    'DEPTH': 'Depth', 'VALSOU': 'Depth',
    'DRVAL1': 'Min Depth', 'DRVAL2': 'Max Depth',
    'VALDCO': 'Contour Depth',
    'CATWRK': 'Type', 'CATOBS': 'Type', 'WATLEV': 'Water Level',
    'CATLAM': 'Lateral', 'CATCAM': 'Cardinal', 'CATSPM': 'Purpose',
    'BOYSHP': 'Shape', 'BCNSHP': 'Shape', 'TOPSHP': 'Top Mark',
    'COLOUR': 'Colour', 'COLPAT': 'Pattern',
    'LITCHR': 'Character', 'CATLIT': 'Category',
    'SIGPER': 'Period', 'VALNMR': 'Range',
    'HEIGHT': 'Height', 'RESTRN': 'Restriction',
    'CONDTN': 'Condition', 'STATUS': 'Status',
    'CONRAD': 'Radar Conspicuous', 'CONVIS': 'Visually Conspicuous',
    'VERLEN': 'Vertical Clearance',
    'HORLEN': 'Length', 'HORWID': 'Width',
  };

  static const _objectClassNames = <String, String>{
    'SOUNDG': 'Sounding', 'DEPCNT': 'Depth Contour', 'DEPARE': 'Depth Area',
    'DRGARE': 'Dredged Area', 'COALNE': 'Coastline', 'LNDARE': 'Land Area',
    'BUAARE': 'Built-up Area', 'LAKARE': 'Lake', 'RIVERS': 'River',
    'CANALS': 'Canal', 'SEAARE': 'Sea Area',
    'LIGHTS': 'Light', 'BOYLAT': 'Lateral Buoy',
    'BOYCAR': 'Cardinal Buoy', 'BOYSAW': 'Safe Water Buoy',
    'BOYSPP': 'Special Purpose Buoy', 'BOYISD': 'Isolated Danger Buoy',
    'BCNLAT': 'Lateral Beacon', 'BCNCAR': 'Cardinal Beacon',
    'BCNSPP': 'Special Purpose Beacon', 'BCNSAW': 'Safe Water Beacon',
    'BCNISD': 'Isolated Danger Beacon',
    'TOPMAR': 'Topmark', 'DAYMAR': 'Daymark',
    'FOGSIG': 'Fog Signal', 'RTPBCN': 'Radar Transponder',
    'RDOSTA': 'Radio Station', 'RADSTA': 'Radar Station',
    'LITFLT': 'Light Float', 'LITVES': 'Light Vessel',
    'WRECKS': 'Wreck', 'OBSTRN': 'Obstruction', 'UWTROC': 'Underwater Rock',
    'LNDMRK': 'Landmark', 'SLCONS': 'Shoreline Construction',
    'BRIDGE': 'Bridge', 'OFSPLF': 'Offshore Platform',
    'PILBOP': 'Pilot Boarding Place', 'CRANES': 'Crane',
    'MORFAC': 'Mooring Facility', 'BERTHS': 'Berth',
    'HRBFAC': 'Harbour Facility', 'SMCFAC': 'Small Craft Facility',
    'CBLSUB': 'Submarine Cable', 'CBLOHD': 'Overhead Cable',
    'PIPSOL': 'Submarine Pipeline', 'PIPOHD': 'Overhead Pipeline',
    'CGUSTA': 'Coast Guard Station', 'RSCSTA': 'Rescue Station',
    'SISTAT': 'Signal Station', 'SISTAW': 'Storm Signal Station',
    'DISMAR': 'Distance Mark', 'CURENT': 'Current',
    'FSHFAC': 'Fishing Facility', 'ACHARE': 'Anchorage Area',
    'RESARE': 'Restricted Area', 'FAIRWY': 'Fairway',
    'TSSLPT': 'TSS Lane', 'TSSBND': 'TSS Boundary',
    'NAVLNE': 'Navigation Line', 'RECTRC': 'Recommended Track',
    'GATCON': 'Gate', 'CONVYR': 'Conveyor',
    'PRDARE': 'Production Area', 'VEGATN': 'Vegetation',
    'LNDRGN': 'Land Region', 'DMPGRD': 'Dumping Ground',
    'CBLARE': 'Cable Area', 'SPLARE': 'Sea-plane Landing Area',
  };

  static const _decodeTables = <String, Map<String, String>>{
    'COLOUR': {'1': 'White', '2': 'Black', '3': 'Red', '4': 'Green', '5': 'Blue', '6': 'Yellow', '7': 'Grey', '8': 'Brown', '9': 'Amber', '10': 'Violet', '11': 'Orange', '12': 'Magenta', '13': 'Pink'},
    'WATLEV': {'1': 'Partly submerged', '2': 'Always dry', '3': 'Always under water', '4': 'Covers and uncovers', '5': 'Awash', '6': 'Subject to flooding', '7': 'Floating'},
    'CATOBS': {'1': 'Snag/stump', '2': 'Wellhead', '3': 'Diffuser', '4': 'Crib', '5': 'Fish haven', '6': 'Foul area', '7': 'Foul ground', '8': 'Ice boom', '9': 'Ground tackle', '10': 'Boom'},
    'CATWRK': {'1': 'Non-dangerous', '2': 'Dangerous', '3': 'Distributed remains', '4': 'Mast showing', '5': 'Hull showing'},
    'BOYSHP': {'1': 'Conical (nun)', '2': 'Can (cylindrical)', '3': 'Spherical', '4': 'Pillar', '5': 'Spar', '6': 'Barrel', '7': 'Super-buoy', '8': 'Ice buoy'},
    'BCNSHP': {'1': 'Stake/pole', '2': 'Withy', '3': 'Tower', '4': 'Lattice', '5': 'Pile', '6': 'Cairn', '7': 'Buoyant'},
    'CATLAM': {'1': 'Port', '2': 'Starboard', '3': 'Preferred channel starboard', '4': 'Preferred channel port'},
    'CATCAM': {'1': 'North', '2': 'East', '3': 'South', '4': 'West'},
    'CATLIT': {'1': 'Directional', '4': 'Leading', '5': 'Aero', '6': 'Air obstruction', '7': 'Fog detector', '8': 'Flood', '9': 'Strip', '10': 'Subsidiary', '11': 'Spotlight', '12': 'Front', '13': 'Rear', '14': 'Lower', '15': 'Upper'},
    'LITCHR': {'1': 'Fixed', '2': 'Flashing', '3': 'Long flashing', '4': 'Quick flashing', '5': 'Very quick flashing', '6': 'Ultra quick flashing', '7': 'Isophase', '8': 'Occulting', '9': 'Interrupted quick', '10': 'Interrupted very quick', '11': 'Morse code', '12': 'Fixed/flashing', '25': 'Quick + long flash', '26': 'VQ + long flash', '27': 'UQ + long flash', '28': 'Alternating', '29': 'Fixed & alternating flashing'},
    'CONDTN': {'1': 'Under construction', '2': 'Ruined', '3': 'Under reclamation', '5': 'Planned'},
    'STATUS': {'1': 'Permanent', '2': 'Occasional', '3': 'Recommended', '4': 'Not in use', '5': 'Intermittent', '6': 'Reserved', '7': 'Temporary', '8': 'Private', '9': 'Mandatory', '11': 'Extinguished', '12': 'Illuminated', '13': 'Historic', '14': 'Public', '15': 'Synchronized', '16': 'Watched', '17': 'Un-watched', '18': 'Doubtful'},
    'RESTRN': {'1': 'Anchoring prohibited', '2': 'Anchoring restricted', '3': 'Fishing prohibited', '4': 'Fishing restricted', '5': 'Trawling prohibited', '6': 'Trawling restricted', '7': 'Entry prohibited', '8': 'Entry restricted', '9': 'Dredging prohibited', '10': 'Dredging restricted', '11': 'Diving prohibited', '12': 'Diving restricted', '13': 'No wake', '14': 'Area to be avoided', '27': 'Speed restricted'},
    'COLPAT': {'1': 'Horizontal stripes', '2': 'Vertical stripes', '3': 'Diagonal stripes', '4': 'Squared', '5': 'Border stripes', '6': 'Single colour'},
    'TOPSHP': {'1': 'Cone point up', '2': 'Cone point down', '3': 'Sphere', '4': 'Two spheres', '5': 'Cylinder', '6': 'Board', '7': 'X-shape', '8': 'Upright cross', '9': 'Cube point up', '10': 'Two cones point-to-point', '11': 'Two cones base-to-base', '12': 'Rhombus', '13': 'Two cones point up', '14': 'Two cones point down', '33': 'Flag'},
    'CATSPM': {'1': 'Firing danger', '2': 'Target', '3': 'Marker ship', '4': 'Degaussing range', '5': 'Barge', '6': 'Cable', '7': 'Spoil ground', '8': 'Outfall', '9': 'ODAS', '10': 'Recording', '11': 'Seaplane anchorage', '12': 'Recreation zone', '13': 'Private', '14': 'Mooring', '15': 'LANBY', '16': 'Leading', '17': 'Measured distance', '18': 'Notice', '19': 'TSS', '20': 'No anchoring', '21': 'No berthing', '22': 'No overtaking', '23': 'No two-way traffic', '24': 'Reduced wake', '25': 'Speed limit', '26': 'Stop', '27': 'Warning', '28': 'Sound ship siren', '39': 'Environmental', '45': 'AIS', '51': 'No entry'},
  };

  String _format(String key, Object? val) {
    if (val == null) return '';
    final s = val.toString();
    if (s.isEmpty) return '';
    // Depth values arrive from S-57 in metres (SI). Use
    // `metadata.format()` so the user's configured unit + precision
    // wins, with the formula applied correctly (including any offset).
    if (_depthKeys.contains(key)) {
      final n = num.tryParse(s);
      if (n == null) return s;
      return depth?.format(n.toDouble(), decimals: 1) ??
          '${n.toStringAsFixed(1)} m';
    }
    if (_heightKeys.contains(key)) {
      final n = num.tryParse(s);
      if (n == null) return s;
      return height?.format(n.toDouble(), decimals: 1) ??
          '${n.toStringAsFixed(1)} m';
    }
    // V1 hardcodes these next two. SIGPER is a signal period in
    // seconds (no alt unit in the S-57 spec) and VALNMR is nominal
    // visibility range in nautical miles per IHO S-57. Matching V1.
    if (key == 'SIGPER') return '${s}s';
    if (key == 'VALNMR') return '$s NM';
    if (key == 'CONRAD' || key == 'CONVIS') return s == '1' ? 'Yes' : 'No';
    final table = _decodeTables[key];
    if (table != null) {
      final parts = s.split(',').map((p) => table[p.trim()] ?? p.trim());
      return parts.join(', ');
    }
    return s;
  }

  /// Picks the card title: prefer a real name (OBJNAM > NOBJNM) so
  /// named objects like "New London Ledge Light" read as the primary
  /// identity; fall back to the class display name for unnamed ones.
  /// Returns `(title, keyUsedAsTitle)` so the row loop can skip the
  /// attribute it promoted.
  ({String title, String? usedKey}) _pickTitle(Map<String, Object?> props) {
    for (final key in const ['OBJNAM', 'NOBJNM']) {
      final formatted = _format(key, props[key]);
      if (formatted.isNotEmpty) return (title: formatted, usedKey: key);
    }
    return (
      title: _objectClassNames[member.layer] ?? member.layer,
      usedKey: null,
    );
  }

  Widget _propertyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final props = member.properties;
    final titlePick = _pickTitle(props);
    final rows = <Widget>[
      Text(
        titlePick.title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      const SizedBox(height: 6),
    ];
    // If the title came from a name attribute, surface the S-57
    // class as an "Object" row so the reader still knows what kind
    // of feature this is. "Object" avoids collision with CATWRK /
    // CATOBS which already use the "Type" label.
    if (titlePick.usedKey != null) {
      final className = _objectClassNames[member.layer] ?? member.layer;
      rows.add(_propertyRow('Object', className));
    }
    for (final key in _displayOrder) {
      if (key == titlePick.usedKey) continue;
      if (!props.containsKey(key)) continue;
      final display = _format(key, props[key]);
      if (display.isEmpty) continue;
      final label = _attributeLabels[key] ?? key;
      rows.add(_propertyRow(label, display));
    }
    return Card(
      color: const Color(0xFF2A2A3E),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        ),
      ),
    );
  }
}

/// Shared popover height cap. In landscape the vertical real estate
/// is tight — bottom-anchored sheets and waypoint/end-pin popovers
/// should never cover more than 1/5 of the screen so the map above
/// stays usable. In portrait we keep the roomier half-screen feel.
double _popoverMaxHeight(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final landscape = size.width > size.height;
  return size.height * (landscape ? 0.2 : 0.5);
}

class _TapHaloLayer extends StatelessWidget {
  const _TapHaloLayer({required this.point});
  final LatLng point;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _TapHaloPainter(camera: camera, point: point),
        size: Size.infinite,
      ),
    );
  }
}

class _TapHaloPainter extends CustomPainter {
  _TapHaloPainter({required this.camera, required this.point});
  final MapCamera camera;
  final LatLng point;

  @override
  void paint(Canvas canvas, Size size) {
    final c = camera.projectAtZoom(point) - camera.pixelOrigin;
    canvas.drawCircle(
      c,
      30,
      Paint()
        ..color = const Color(0x1AFFFF00)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      c,
      30,
      Paint()
        ..color = const Color(0xCCFFFF00)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _TapHaloPainter old) =>
      old.camera != camera || old.point != point;
}

/// Verbatim port of V1's `_CompassRosePainter`
/// (chart_plotter_tool.dart:1440-1482). Red north arrow + label,
/// faded south arrow, E/W cardinal tick marks.
class _CompassRosePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 4;

    final northPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    final northPath = ui.Path()
      ..moveTo(center.dx, center.dy - r)
      ..lineTo(center.dx - 5, center.dy - 2)
      ..lineTo(center.dx + 5, center.dy - 2)
      ..close();
    canvas.drawPath(northPath, northPaint);

    final southPaint = Paint()
      ..color = Colors.white54
      ..style = PaintingStyle.fill;
    final southPath = ui.Path()
      ..moveTo(center.dx, center.dy + r)
      ..lineTo(center.dx - 5, center.dy + 2)
      ..lineTo(center.dx + 5, center.dy + 2)
      ..close();
    canvas.drawPath(southPath, southPaint);

    final tickPaint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(center.dx + r, center.dy),
        Offset(center.dx + r - 6, center.dy), tickPaint);
    canvas.drawLine(Offset(center.dx - r, center.dy),
        Offset(center.dx - r + 6, center.dy), tickPaint);

    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'N',
        style: TextStyle(
          color: Colors.red,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - r + 10),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

enum _AisKind { moving, slow, moored, anchored }

/// Compact, painter-friendly snapshot of an AIS vessel. Only the
/// fields the painter actually reads are kept so the per-frame hot
/// loop stays cheap.
class _AisRenderable {
  const _AisRenderable({
    required this.id,
    required this.position,
    required this.bearingRadians,
    required this.name,
    required this.color,
    required this.alpha,
    required this.stale,
    required this.kind,
    required this.projections,
  });
  final String id;
  final LatLng position;
  final double bearingRadians;
  final String name;
  final Color color;
  final double alpha;
  final bool stale;
  final _AisKind kind;
  final List<LatLng> projections;
}

class _AisOverlayLayer extends StatelessWidget {
  const _AisOverlayLayer({
    required this.vessels,
    required this.showPaths,
    required this.selectedId,
  });
  final List<_AisRenderable> vessels;
  final bool showPaths;
  /// Vessel id of the most recently tapped target. The painter draws
  /// a 16 px yellow ring around the matching vessel; null = no ring.
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _AisPainter(
          camera: camera,
          vessels: vessels,
          showPaths: showPaths,
          selectedId: selectedId,
          // V1 hides labels below zoom 13 where the map is too zoomed
          // out for names to be readable anyway; mirror that here.
          showNames: camera.zoom >= 13,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _AisPainter extends CustomPainter {
  _AisPainter({
    required this.camera,
    required this.vessels,
    required this.showPaths,
    required this.showNames,
    required this.selectedId,
  });
  final MapCamera camera;
  final List<_AisRenderable> vessels;
  final bool showPaths;
  final bool showNames;
  final String? selectedId;

  /// Standard size for every vessel icon glyph (Material Icons
  /// rendered via TextPainter — same trick the anchor case has used
  /// since the V3 chart plotter shipped). 32 pt matches the AIS
  /// polar chart widget's default vessel size (`ais_polar_chart.dart`
  /// `iconSize = 32.0`) so the two surfaces read as the same
  /// vessel-symbol language.
  static const double _iconSize = 32.0;

  /// Selection-ring radius. The ring sits outside the icon glyph so
  /// the colour silhouette stays visible underneath. Sized so the
  /// 32 pt icon's bounding box (~26 px wide) clears the inner edge
  /// with a small margin.
  static const double _selectionRingRadius = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = camera.pixelOrigin;
    for (final v in vessels) {
      if (showPaths && v.projections.isNotEmpty) {
        _paintProjections(canvas, v, origin);
      }
      final center = camera.projectAtZoom(v.position) - origin;
      // Selection ring goes underneath the icon so the icon's
      // colour silhouette reads against a yellow halo, not on top
      // of one. Drawn first; icon overpaints the central area.
      if (selectedId != null && v.id == selectedId) {
        _paintSelectionRing(canvas, center);
      }
      // Polar chart rotates every vessel icon by heading regardless
      // of motion state (`ais_polar_chart.dart:1998-1999`). Match
      // that — `Icons.circle` is rotation-invariant, anchor and the
      // buoy rotate just like the moving navigation arrow does.
      switch (v.kind) {
        case _AisKind.moving:
          _paintIcon(canvas, v, center, Icons.navigation, rotate: true);
          break;
        case _AisKind.slow:
          _paintIcon(canvas, v, center, Icons.circle, rotate: true);
          break;
        case _AisKind.moored:
          // Mooring buoy keeps its custom painter — the polar chart
          // widget overrides the icon with the same SVG silhouette
          // (`ais_polar_chart.dart:_mooringBuoySvg`), so this path
          // matches that visual without dragging in `flutter_svg`.
          _paintMoored(canvas, v, center, rotate: true);
          break;
        case _AisKind.anchored:
          _paintIcon(canvas, v, center, Icons.anchor, rotate: true);
          break;
      }
      // Polar chart hides the stale × on the highlighted vessel
      // (`ais_polar_chart.dart:2023`: `stale && !isHighlighted ? …`).
      // Match — the selection ring is enough signal on its own.
      final isSelected = selectedId != null && v.id == selectedId;
      if (v.stale && !isSelected) _paintStaleX(canvas, center);
      if (showNames && v.name.isNotEmpty) {
        _paintName(canvas, v, center);
      }
    }
  }

  void _paintProjections(Canvas canvas, _AisRenderable v, Offset origin) {
    final start = camera.projectAtZoom(v.position) - origin;
    final dashPath = ui.Path()..moveTo(start.dx, start.dy);
    for (final p in v.projections) {
      final s = camera.projectAtZoom(p) - origin;
      dashPath.lineTo(s.dx, s.dy);
    }
    final dashed = _dashOne(dashPath, const [4, 4]);
    final lineColor = v.color.withValues(alpha: v.alpha * 0.6);
    canvas.drawPath(
      dashed,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Dot sizes match the polar chart map view's
    // `projectionDotSizes = [6.0, 10.0, 16.0, 22.0]`
    // (`ais_polar_chart.dart:2044`) for 30s, 1m, 15m, 30m.
    const dotR = [6.0, 10.0, 16.0, 22.0];
    final dotFill = Paint()..color = v.color.withValues(alpha: v.alpha * 0.7);
    final dotStroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (var i = 0; i < v.projections.length; i++) {
      final p = camera.projectAtZoom(v.projections[i]) - origin;
      final r = i < dotR.length ? dotR[i] : 4.0;
      canvas.drawCircle(p, r, dotFill);
      canvas.drawCircle(p, r, dotStroke);
    }
  }

  // Reuses the outer-painter dash helper's idea in one place.
  ui.Path _dashOne(ui.Path source, List<double> intervals) {
    final out = ui.Path();
    for (final metric in source.computeMetrics()) {
      double d = 0;
      var on = true;
      var i = 0;
      while (d < metric.length) {
        final span = intervals[i % intervals.length];
        final next = d + span;
        if (on) {
          out.addPath(
            metric.extractPath(d, next.clamp(0, metric.length)),
            Offset.zero,
          );
        }
        d = next;
        on = !on;
        i++;
      }
    }
    return out;
  }

  /// Render a Material Icon glyph centred on the vessel position.
  /// `rotate: true` rotates by `v.bearingRadians` (used for
  /// `Icons.navigation` on moving vessels); other states draw
  /// upright. A subtle drop shadow keeps the silhouette legible
  /// against busy chart backgrounds.
  void _paintIcon(
    Canvas canvas,
    _AisRenderable v,
    Offset center,
    IconData icon, {
    bool rotate = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: _iconSize,
          color: v.color.withValues(alpha: v.alpha),
          // Match polar chart map-view: `Shadow(black, blurRadius: 3)`
          // (`ais_polar_chart.dart:2008-2012`).
          shadows: const [
            Shadow(color: Colors.black, blurRadius: 3),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    final dx = -painter.width / 2;
    final dy = -painter.height / 2;
    if (rotate) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(v.bearingRadians);
      painter.paint(canvas, Offset(dx, dy));
      canvas.restore();
    } else {
      painter.paint(canvas, Offset(center.dx + dx, center.dy + dy));
    }
  }

  /// Yellow ring around the most-recently-tapped vessel. Drawn under
  /// the icon glyph so the icon's colour stays readable.
  void _paintSelectionRing(Canvas canvas, Offset center) {
    canvas.drawCircle(
      center,
      _selectionRingRadius,
      Paint()
        ..color = const Color(0xFFFFEB3B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    // Thin black inner edge so the yellow reads against light chart
    // backgrounds (white seamarks, snow, etc.).
    canvas.drawCircle(
      center,
      _selectionRingRadius - 1.5,
      Paint()
        ..color = const Color(0x66000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _paintMoored(
    Canvas canvas,
    _AisRenderable v,
    Offset center, {
    bool rotate = false,
  }) {
    // Mooring buoy — exact visual match to the AIS polar chart
    // widget's `_mooringBuoySvg` (`ais_polar_chart.dart:955-960`):
    //   - r=45 disk in the 100×100 viewBox → 14 px radius at 32 pt
    //     icon size, leaving 2 px breathing room for the strokes
    //   - TYPE_COLOR fill (the vessel's ship-type colour, alpha-aged)
    //   - Horizontal #1565C0 band centred on the disk, clipped to it
    //     (band y=38 height=24 in the 100-unit viewBox → ±0.24 r
    //     about the centre, height 0.48 r)
    //   - Two concentric strokes: outer #888 at 1.5 px, inner #666
    //     at 1 px. The SVG draws both circles at the same radius;
    //     in our painter the order is fill → band → outer stroke →
    //     inner stroke, matching the SVG's source order.
    // `rotate` rotates the band by the vessel heading so the buoy
    // matches the polar chart's blanket-rotate-everything behaviour.
    const r = 14.0;
    final disk = Paint()..color = v.color.withValues(alpha: v.alpha);
    final band = Paint()..color = const Color(0xFF1565C0);
    final outerStroke = Paint()
      ..color = const Color(0xFF888888)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final innerStroke = Paint()
      ..color = const Color(0xFF666666)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (rotate) canvas.rotate(v.bearingRadians);
    canvas.drawCircle(Offset.zero, r, disk);
    canvas.save();
    canvas.clipPath(
        ui.Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r)));
    canvas.drawRect(
      const Rect.fromLTWH(-r, -r * 0.24, r * 2, r * 0.48),
      band,
    );
    canvas.restore();
    canvas.drawCircle(Offset.zero, r, outerStroke);
    canvas.drawCircle(Offset.zero, r, innerStroke);
    canvas.restore();
  }

  void _paintStaleX(Canvas canvas, Offset center) {
    // Stale overlay — exact match to the polar chart widget's
    // `Icon(Icons.close, color: Colors.red, size: iconSize * 0.8)`
    // (`ais_polar_chart.dart:1684, 2028`). Material's close glyph
    // is a clean × that overlays the vessel icon without obscuring
    // the silhouette beneath.
    const icon = Icons.close;
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: _iconSize * 0.8,
          color: Colors.red,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  void _paintName(Canvas canvas, _AisRenderable v, Offset center) {
    final painter = TextPainter(
      text: TextSpan(
        text: v.name,
        style: TextStyle(
          color: v.color.withValues(alpha: math.max(v.alpha, 0.8)),
          fontSize: 11,
          fontWeight: FontWeight.w500,
          shadows: const [
            Shadow(color: Color(0x80000000), blurRadius: 2),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - 18 - painter.height),
    );
  }

  @override
  bool shouldRepaint(covariant _AisPainter old) =>
      old.camera != camera ||
      old.vessels != vessels ||
      old.showPaths != showPaths ||
      old.showNames != showNames ||
      old.selectedId != selectedId;
}


/// Full-fidelity ruler renderer. Matches V1's on-map output:
///   • Dashed red half-line (red → midpoint), `rgba(244,67,54,0.7)` w3 dash 8-4
///   • Dashed blue half-line (midpoint → blue), `rgba(33,150,243,0.7)`
///   • Perpendicular tick marks at "nice" intervals (3-10 per ruler)
///   • Red bearing label at red endpoint (red→blue angle, offsetY -18)
///   • Blue bearing label at blue endpoint (blue→red angle)
///   • White distance label at midpoint (offsetY +16) with unit symbol
class _RulerLayer extends StatelessWidget {
  const _RulerLayer({
    required this.red,
    required this.blue,
    required this.distance,
  });
  final LatLng red;
  final LatLng blue;
  final PathMetadata? distance;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _RulerPainter(
          camera: camera,
          red: red,
          blue: blue,
          distance: distance,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.camera,
    required this.red,
    required this.blue,
    required this.distance,
  });
  final MapCamera camera;
  final LatLng red;
  final LatLng blue;
  final PathMetadata? distance;

  // "Nice" display-unit step table. Mirrors chart_webview.dart:1814.
  static const _niceCandidates = [
    0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5,
    1.0, 2.0, 5.0, 10.0, 25.0, 50.0, 100.0, 250.0, 500.0,
  ];

  double _niceInterval(double totalDisplay) {
    for (final c in _niceCandidates) {
      final ticks = totalDisplay / c;
      if (ticks >= 3 && ticks <= 10) return c;
    }
    return totalDisplay / 5;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final origin = camera.pixelOrigin;
    final pRed = camera.projectAtZoom(red) - origin;
    final pBlue = camera.projectAtZoom(blue) - origin;
    final mid = Offset(
      (pRed.dx + pBlue.dx) / 2,
      (pRed.dy + pBlue.dy) / 2,
    );

    // Half-lines (dashed). V1 uses lineDash [8, 4] on stroke 3.
    const redLineColor = Color(0xB3F44336); // alpha 0.7
    const blueLineColor = Color(0xB32196F3);
    final redPath = ui.Path()
      ..moveTo(pRed.dx, pRed.dy)
      ..lineTo(mid.dx, mid.dy);
    final bluePath = ui.Path()
      ..moveTo(mid.dx, mid.dy)
      ..lineTo(pBlue.dx, pBlue.dy);
    final dashed = [8.0, 4.0];
    canvas.drawPath(
      _dashPath(redPath, dashed),
      Paint()
        ..color = redLineColor
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      _dashPath(bluePath, dashed),
      Paint()
        ..color = blueLineColor
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );

    // Distance + bearings in WGS84 via haversine / great circle.
    final distM = _haversine(red, blue);
    final bearingRB = _bearing(red, blue);
    final bearingBR = _bearing(blue, red);
    // Display value via MetadataStore.convert — never assume a linear
    // factor, because formulas may include offsets.
    final distDisplay = distance?.convert(distM) ?? distM;

    // Tick marks — perpendicular 16px (8 each side), up to 20 ticks.
    final dx = pBlue.dx - pRed.dx;
    final dy = pBlue.dy - pRed.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len > 0 && distDisplay > 0) {
      final dirX = dx / len;
      final dirY = dy / len;
      final perpX = -dirY;
      final perpY = dirX;
      const tickHalf = 8.0;
      final interval = _niceInterval(distDisplay);
      final tickCount = (distDisplay / interval).floor();
      final blackPaint = Paint()
        ..color = const Color(0x99000000)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      final whitePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      for (var i = 1; i <= tickCount && i <= 20; i++) {
        final frac = (interval * i) / distDisplay;
        if (frac >= 1) break;
        final tx = pRed.dx + dx * frac;
        final ty = pRed.dy + dy * frac;
        final from = Offset(tx + perpX * tickHalf, ty + perpY * tickHalf);
        final to = Offset(tx - perpX * tickHalf, ty - perpY * tickHalf);
        canvas.drawLine(from, to, blackPaint);
        canvas.drawLine(from, to, whitePaint);
      }
    }

    // Bearing labels at endpoints, offsetY -18 (above the marker).
    final bearingStyle = const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      shadows: [Shadow(color: Color(0xCC000000), blurRadius: 3)],
    );
    _drawLabel(
      canvas,
      pRed.translate(0, -18),
      '${bearingRB.toStringAsFixed(1)}°',
      bearingStyle.copyWith(color: const Color(0xFFF44336)),
    );
    _drawLabel(
      canvas,
      pBlue.translate(0, -18),
      '${bearingBR.toStringAsFixed(1)}°',
      bearingStyle.copyWith(color: const Color(0xFF2196F3)),
    );

    // Distance label at midpoint, offsetY +16 (below the centre).
    // Precision varies with magnitude (V1 chart_webview.dart:1873).
    final decimals = distDisplay < 1 ? 3 : (distDisplay < 10 ? 2 : 1);
    final distLabel = distance?.format(distM, decimals: decimals) ??
        '${distM.toStringAsFixed(decimals)} m';
    _drawLabel(
      canvas,
      mid.translate(0, 16),
      distLabel,
      const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        shadows: [Shadow(color: Color(0xCC000000), blurRadius: 3)],
      ),
    );
  }

  void _drawLabel(Canvas canvas, Offset anchor, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(
      canvas,
      Offset(anchor.dx - painter.width / 2, anchor.dy - painter.height / 2),
    );
  }

  ui.Path _dashPath(ui.Path source, List<double> intervals) {
    final out = ui.Path();
    for (final metric in source.computeMetrics()) {
      double d = 0;
      var on = true;
      var i = 0;
      while (d < metric.length) {
        final next = d + intervals[i % intervals.length];
        if (on) {
          out.addPath(
            metric.extractPath(d, next.clamp(0, metric.length)),
            Offset.zero,
          );
        }
        d = next;
        on = !on;
        i++;
      }
    }
    return out;
  }

  double _haversine(LatLng a, LatLng b) {
    const r = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(h)));
  }

  double _bearing(LatLng from, LatLng to) {
    final la1 = from.latitude * math.pi / 180;
    final la2 = to.latitude * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(la2);
    final x = math.cos(la1) * math.sin(la2) -
        math.sin(la1) * math.cos(la2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.camera != camera ||
      old.red != red ||
      old.blue != blue ||
      old.distance != distance;
}

/// Ruler info panel — matches V1's top-left overlay
/// (chart_plotter_tool.dart:1311-1360). Layout: red painted dot +
/// bearing Red→Blue on row one, blue dot + Blue→Red on row two,
/// distance with unit symbol on row three (bold 15 px). Distance
/// precision: <1 → 3 decimals, <10 → 2 decimals, else 1 decimal.
class _RulerReadout extends StatelessWidget {
  const _RulerReadout({
    required this.signalKService,
    required this.a,
    required this.b,
  });
  final SignalKService signalKService;
  final LatLng a;
  final LatLng b;

  @override
  Widget build(BuildContext context) {
    final distM = _haversine(a, b);
    final bearingRed = _bearing(a, b); // red → blue
    final bearingBlue = _bearing(b, a); // blue → red
    final distMeta =
        signalKService.metadataStore.getByCategory('distance');
    final dist = distMeta?.convert(distM) ?? distM;
    final distSym = distMeta?.symbol ?? 'm';
    final distStr = dist < 1
        ? dist.toStringAsFixed(3)
        : (dist < 10 ? dist.toStringAsFixed(2) : dist.toStringAsFixed(1));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${bearingRed.toStringAsFixed(1)}°',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ]),
          const SizedBox(height: 2),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${bearingBlue.toStringAsFixed(1)}°',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            '$distStr $distSym',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  double _haversine(LatLng a, LatLng b) {
    const r = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(h)));
  }

  double _bearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final deg = math.atan2(y, x) * 180 / math.pi;
    return (deg + 360) % 360;
  }
}

/// Paints the own vessel. Matches V1's composition (chart_webview.dart:
/// 1285-1324): solid-blue heading line out 800 m, dashed-orange COG
/// vector sized to a 3-minute projection, and the chevron marker at
/// `#2196f3` × 0.9 alpha with a white outline, scaled 1.6×.
class _OwnVesselLayer extends StatelessWidget {
  const _OwnVesselLayer({
    required this.lat,
    required this.lon,
    required this.headingRad,
    required this.cogRad,
    required this.sogMs,
  });
  final double lat;
  final double lon;
  final double? headingRad;
  final double? cogRad;
  final double? sogMs;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _OwnVesselPainter(
          camera: camera,
          position: LatLng(lat, lon),
          headingRad: headingRad,
          cogRad: cogRad,
          sogMs: sogMs,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _OwnVesselPainter extends CustomPainter {
  _OwnVesselPainter({
    required this.camera,
    required this.position,
    required this.headingRad,
    required this.cogRad,
    required this.sogMs,
  });
  final MapCamera camera;
  final LatLng position;
  final double? headingRad;
  final double? cogRad;
  final double? sogMs;

  // Exact SVG path from V1's `vesselSvgSrc` (chart_webview.dart:1152),
  // recentred to (0,0) so rotate/scale pivot about the chevron midpoint.
  //   Source: M 8 1 L 2 19 L 5.5 16.5 L 8 21 L 10.5 16.5 L 14 19 Z
  //   (translated by -8, -12 → in painter-local space)
  static final _chevronPath = ui.Path()
    ..moveTo(0, -11)
    ..lineTo(-6, 7)
    ..lineTo(-2.5, 4.5)
    ..lineTo(0, 9)
    ..lineTo(2.5, 4.5)
    ..lineTo(6, 7)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final origin = camera.pixelOrigin;
    final center = camera.projectAtZoom(position) - origin;

    // Heading line — solid blue, great-circle forward-projected 800 m.
    if (headingRad != null) {
      final end = _forward(position, headingRad!, 800);
      final pe = camera.projectAtZoom(end) - origin;
      canvas.drawLine(
        center,
        pe,
        Paint()
          ..color = const Color(0xB32196F3) // 0.7 alpha
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }

    // COG vector — dashed orange, length = max(sog*180, 200) m so
    // the arrow reaches a 3-minute lookahead or stays visible at rest.
    if (cogRad != null && sogMs != null && sogMs! > 0.1) {
      final len = math.max(sogMs! * 180.0, 200.0);
      final end = _forward(position, cogRad!, len);
      final pe = camera.projectAtZoom(end) - origin;
      final path = ui.Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(pe.dx, pe.dy);
      canvas.drawPath(
        _dashed(path, const [8, 4]),
        Paint()
          ..color = const Color(0xCCFF9800) // 0.8 alpha
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }

    // Chevron marker — blue fill, white outline, scale 1.6× like V1.
    final rotation = headingRad ?? cogRad ?? 0.0;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.scale(1.6);
    canvas.drawPath(
      _chevronPath,
      Paint()..color = const Color(0xE62196F3), // 0.9 alpha
    );
    canvas.drawPath(
      _chevronPath,
      Paint()
        ..color = const Color(0xE6FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    canvas.restore();
  }

  /// Great-circle forward projection — lat/lon + bearing (rad) + distance (m)
  /// → new lat/lon. Same maths the AIS painter uses.
  LatLng _forward(LatLng start, double bearingRad, double distM) {
    final lat1 = start.latitude * math.pi / 180;
    final lon1 = start.longitude * math.pi / 180;
    final a = distM / 6371000.0;
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(a) +
          math.cos(lat1) * math.sin(a) * math.cos(bearingRad),
    );
    final lon2 = lon1 +
        math.atan2(
          math.sin(bearingRad) * math.sin(a) * math.cos(lat1),
          math.cos(a) - math.sin(lat1) * math.sin(lat2),
        );
    return LatLng(lat2 * 180 / math.pi, lon2 * 180 / math.pi);
  }

  ui.Path _dashed(ui.Path source, List<double> intervals) {
    final out = ui.Path();
    for (final metric in source.computeMetrics()) {
      double d = 0;
      var on = true;
      var i = 0;
      while (d < metric.length) {
        final next = d + intervals[i % intervals.length];
        if (on) {
          out.addPath(
            metric.extractPath(d, next.clamp(0, metric.length)),
            Offset.zero,
          );
        }
        d = next;
        on = !on;
        i++;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _OwnVesselPainter old) =>
      old.camera != camera ||
      old.position != position ||
      old.headingRad != headingRad ||
      old.cogRad != cogRad ||
      old.sogMs != sogMs;
}

/// Paints the active route. Base polyline magenta at 0.6 alpha width 3; a
/// bright active-leg overlay (prev → next waypoint) at 0.95 alpha width 5;
/// waypoint markers point along the route direction. Past/future waypoints are
/// small magenta triangles (alpha 0.3 past / 0.7 future); the active (next)
/// waypoint is the `Icons.navigation` chevron — the same glyph AIS moving
/// vessels use — at 2/3 the AIS icon size. Magenta sits outside the
/// weather-route palette so the route reads clearly over weather legs.
/// `reversed` inverts what counts as past vs future.
class _RouteOverlayLayer extends StatelessWidget {
  const _RouteOverlayLayer({
    required this.coords,
    required this.activeIndex,
    required this.reversed,
  });
  final List<List<double>> coords;
  final int? activeIndex;
  final bool reversed;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _RoutePainter(
          camera: camera,
          coords: coords,
          activeIndex: activeIndex,
          reversed: reversed,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({
    required this.camera,
    required this.coords,
    required this.activeIndex,
    required this.reversed,
  });
  final MapCamera camera;
  final List<List<double>> coords;
  final int? activeIndex;
  final bool reversed;

  @override
  void paint(Canvas canvas, Size size) {
    if (coords.length < 2) return;
    final origin = camera.pixelOrigin;
    Offset project(List<double> lonLat) =>
        camera.projectAtZoom(LatLng(lonLat[1], lonLat[0])) - origin;

    // Unwrap longitudes to the camera's world copy so a date-line
    // route neither streaks across the map nor vanishes on one side
    // of ±180 when panned (flutter_map repeats the world; a custom
    // painter must place geometry in the visible copy itself).
    final uCoords =
        unwrapLonForCamera(coords, camera.center.longitude);
    final points =
        uCoords.map(project).toList(growable: false);

    // Base polyline — faded green. `uCoords` is path-continuous so a
    // plain connected `lineTo` is both streak-free and renders in the
    // visible world copy.
    final basePath = ui.Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 1; i < points.length; i++) {
      basePath.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(
      basePath,
      Paint()
        ..color = const Color(0x99E91E63) // magenta, 0.6 alpha
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );

    // Active leg overlay (prev → active waypoint). Direction-aware so
    // reversed routes highlight the correct segment.
    final ai = activeIndex;
    if (ai != null) {
      final prevIdx = reversed ? ai + 1 : ai - 1;
      if (prevIdx >= 0 &&
          prevIdx < points.length &&
          ai >= 0 &&
          ai < points.length) {
        // `points` is from the camera-unwrapped coords, so the
        // highlighted active leg is continuous across ±180 too.
        canvas.drawLine(
          points[prevIdx],
          points[ai],
          Paint()
            ..color = const Color(0xF2E91E63) // magenta, 0.95 alpha
            ..strokeWidth = 5
            ..style = PaintingStyle.stroke,
        );
      }
    }

    // Waypoint markers — direction by next leg (or previous in reverse).
    // The ACTIVE (next) waypoint gets a magenta `Icons.navigation` chevron — the
    // same glyph AIS moving vessels use — at 2/3 the AIS icon size, pointing
    // along the route. All other waypoints keep small equilateral triangles.
    for (var i = 0; i < points.length; i++) {
      final isNext = i == ai;
      final isPast = ai != null && (reversed ? i > ai : i < ai);
      final alpha = isPast ? 0.3 : (isNext ? 0.95 : 0.7);
      // Rotation = atan2(dx, dy) of the next-step vector. dy is
      // world-up in screen coords here (flutter_map projects y-down),
      // but V1's OpenLayers uses the same convention relative to the
      // camera transform applied by MobileLayerTransformer, so the
      // same formula reproduces the pointing angle.
      int toIdx;
      if (reversed) {
        toIdx = i > 0 ? i - 1 : i;
      } else {
        toIdx = i < points.length - 1 ? i + 1 : i;
      }
      final dx = points[toIdx].dx - points[i].dx;
      final dy = points[toIdx].dy - points[i].dy;
      final rot = (dx == 0 && dy == 0) ? 0.0 : math.atan2(dx, -dy);

      if (isNext) {
        // 2/3 of the AIS vessel icon size (`_AisPainter._iconSize == 32`).
        _drawActiveChevron(canvas, points[i], rot, 32.0 * 2 / 3);
        continue;
      }

      final path = _triangle(7.0);
      canvas.save();
      canvas.translate(points[i].dx, points[i].dy);
      canvas.rotate(rot);
      canvas.drawPath(
        path,
        Paint()
          ..color =
              Color.fromRGBO(233, 30, 99, alpha), // magenta #E91E63
      );
      canvas.restore();
    }
  }

  /// Active-waypoint marker: the magenta `Icons.navigation` chevron (the same
  /// glyph AIS moving vessels use in `_AisPainter`), centred on [at] and
  /// rotated [rot] to point along the route. Drop shadow but no white outline,
  /// matching the AIS vessel look.
  void _drawActiveChevron(Canvas canvas, Offset at, double rot, double sizePt) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.navigation.codePoint),
        style: TextStyle(
          fontFamily: Icons.navigation.fontFamily,
          package: Icons.navigation.fontPackage,
          fontSize: sizePt,
          // Magenta — deliberately outside the weather-route palette
          // (green/red/amber/blue/cyan/orange) so the active waypoint reads
          // clearly against the route and weather legs. 0.95 alpha.
          color: const Color(0xF2E91E63),
          shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(rot);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  /// Equilateral triangle pointing up (bow along +y is toward the
  /// next waypoint before rotation; V1 uses OpenLayers RegularShape
  /// with points=3 which is the same equilateral).
  ui.Path _triangle(double radius) {
    final path = ui.Path();
    for (var i = 0; i < 3; i++) {
      final theta = -math.pi / 2 + i * 2 * math.pi / 3;
      final x = radius * math.cos(theta);
      final y = radius * math.sin(theta);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) =>
      old.camera != camera ||
      old.coords != coords ||
      old.activeIndex != activeIndex ||
      old.reversed != reversed;
}

/// Identifier for the currently-open nav-drawer flyout. Sister-app
/// shape — no tracker drawer entry. `_NavDrawerKind.none` collapses
/// the drawer entirely.
enum _NavDrawerKind { none, ais, routes, layers }

/// `Material 3` IconButton renders inside a 48 px tappable square
/// regardless of icon size, so this is the actual painted height of
/// each `IconButton(size: 20)` in the nav column. The drawer-side
/// column uses this same constant for its slot heights so the active
/// drawer pill sits exactly at the right column's matching row.
const double _navRowHeight = 48.0;

/// The right-edge map controls. Right side is a single rounded pill
/// of six `IconButton`s — that pill never reflows when a drawer
/// opens, so existing buttons can't wobble. Left side is a column of
/// six row slots: inactive slots are zero-width spacers, the active
/// group's slot expands into a [_DrawerPill]. The drawer butts
/// directly against the nav's left edge so the two read as a single
/// L-shape rather than two pills.
/// Number of nav-pill buttons rendered ABOVE the AIS/Routes/Layers drawer
/// group (view-mode, follow, ruler, record). The drawer column pads with this
/// many blank spacer slots so each flyout lines up with its trigger button.
/// Single source of truth — update this if the leading nav buttons change.
const int _navButtonsBeforeDrawers = 4;

class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.autoFollow,
    required this.viewMode,
    required this.rulerVisible,
    required this.recordingTrack,
    required this.onToggleRecordTrack,
    required this.openDrawer,
    required this.onToggleFollow,
    required this.onToggleViewMode,
    required this.onToggleRuler,
    required this.onOpenAis,
    required this.onOpenRoutes,
    required this.onOpenLayers,
    // AIS sub-buttons
    required this.aisEnabled,
    required this.aisActiveOnly,
    required this.aisShowPaths,
    required this.onToggleAis,
    required this.onToggleAisActive,
    required this.onToggleAisPaths,
    required this.onOpenAisList,
    // Routes sub-buttons (sister has no tracker)
    required this.onRoutes,
    required this.weatherRoutingEnabled,
    required this.weatherRouteActive,
    required this.onWeatherRouting,
    // Layers sub-buttons
    required this.onLayers,
    required this.onDownload,
    required this.playerVisible,
    required this.playerAvailable,
    required this.onTogglePlayer,
  });

  final bool autoFollow;
  final _ViewMode viewMode;
  final bool rulerVisible;
  final bool recordingTrack;
  final VoidCallback onToggleRecordTrack;

  /// Which group's drawer is currently open. Drives the highlight
  /// fill on the matching group icon AND which row in the drawer
  /// column renders an actual flyout.
  final _NavDrawerKind openDrawer;

  final VoidCallback onToggleFollow;
  final VoidCallback onToggleViewMode;
  final VoidCallback onToggleRuler;
  final VoidCallback onOpenAis;
  final VoidCallback onOpenRoutes;
  final VoidCallback onOpenLayers;

  // AIS
  final bool aisEnabled;
  final bool aisActiveOnly;
  final bool aisShowPaths;
  final VoidCallback onToggleAis;
  final VoidCallback onToggleAisActive;
  final VoidCallback onToggleAisPaths;
  final VoidCallback onOpenAisList;

  // Routes
  final VoidCallback onRoutes;
  final bool weatherRoutingEnabled;
  final bool weatherRouteActive;
  final VoidCallback? onWeatherRouting;

  // Layers
  final VoidCallback onLayers;
  final VoidCallback onDownload;
  final bool playerVisible;
  final bool playerAvailable;
  final VoidCallback onTogglePlayer;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ===== Drawer column (left) =====
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // One empty spacer per nav-pill button ABOVE the AIS button so each
            // flyout aligns with its trigger. Generated from a single source
            // (_navButtonsBeforeDrawers) so adding/removing a leading nav button
            // is a one-constant change — no silent misalignment.
            ...List.generate(
              _navButtonsBeforeDrawers,
              (_) => const _DrawerSlot(active: false, child: SizedBox.shrink()),
            ),
            _DrawerSlot(
              active: openDrawer == _NavDrawerKind.ais,
              child: _AisDrawerRow(
                aisEnabled: aisEnabled,
                aisActiveOnly: aisActiveOnly,
                aisShowPaths: aisShowPaths,
                onToggleAis: onToggleAis,
                onToggleAisActive: onToggleAisActive,
                onToggleAisPaths: onToggleAisPaths,
                onOpenAisList: onOpenAisList,
              ),
            ),
            _DrawerSlot(
              active: openDrawer == _NavDrawerKind.routes,
              child: _RoutesDrawerRow(
                onRoutes: onRoutes,
                weatherRoutingEnabled: weatherRoutingEnabled,
                weatherRouteActive: weatherRouteActive,
                onWeatherRouting: onWeatherRouting,
              ),
            ),
            _DrawerSlot(
              active: openDrawer == _NavDrawerKind.layers,
              child: _LayersDrawerRow(
                onLayers: onLayers,
                onDownload: onDownload,
                playerVisible: playerVisible,
                playerAvailable: playerAvailable,
                onTogglePlayer: onTogglePlayer,
              ),
            ),
          ],
        ),
        // ===== Nav column (right) — single fixed pill =====
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NavIconButton(
                icon: switch (viewMode) {
                  _ViewMode.northUp => Icons.navigation_outlined,
                  _ViewMode.headingUp => Icons.navigation,
                  _ViewMode.free => Icons.threesixty,
                },
                tooltip: switch (viewMode) {
                  _ViewMode.northUp => 'North-up (tap for heading-up)',
                  _ViewMode.headingUp => 'Heading-up (tap for free)',
                  _ViewMode.free => 'Free rotation (tap for north-up)',
                },
                onPressed: onToggleViewMode,
              ),
              _NavIconButton(
                icon: autoFollow
                    ? Icons.my_location
                    : Icons.location_searching,
                tooltip: autoFollow
                    ? 'Snap to vessel (on)'
                    : 'Snap to vessel (off)',
                onPressed: onToggleFollow,
              ),
              _NavIconButton(
                icon: rulerVisible
                    ? Icons.straighten
                    : Icons.straighten_outlined,
                tooltip: rulerVisible ? 'Hide ruler' : 'Show ruler',
                onPressed: onToggleRuler,
              ),
              _NavIconButton(
                icon: recordingTrack
                    ? Icons.stop_circle
                    : Icons.fiber_manual_record,
                tooltip: recordingTrack
                    ? 'Stop & save track'
                    : 'Record track',
                // Red fill while recording so it's obvious a capture is
                // running; stop prompts to save the voyage as a track.
                backgroundColor: recordingTrack ? Colors.red : null,
                onPressed: onToggleRecordTrack,
              ),
              _NavIconButton(
                icon: Icons.sailing,
                tooltip: 'AIS',
                // Green when AIS is on, red when off — gives the
                // group icon a status-at-a-glance role independent
                // of whether the drawer is open. (No `highlight`
                // here; the fill colour wins anyway.)
                backgroundColor: aisEnabled ? Colors.green : Colors.red,
                onPressed: onOpenAis,
              ),
              _NavIconButton(
                icon: Icons.route,
                tooltip: 'Routes',
                highlight: openDrawer == _NavDrawerKind.routes,
                onPressed: onOpenRoutes,
              ),
              _NavIconButton(
                icon: Icons.layers,
                tooltip: 'Layers',
                highlight: openDrawer == _NavDrawerKind.layers,
                onPressed: onOpenLayers,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavIconButton extends StatelessWidget {
  const _NavIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.highlight = false,
    this.backgroundColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool highlight;

  /// Explicit background tint. Takes precedence over [highlight]'s
  /// default white-alpha overlay. Used by the AIS controls to signal
  /// on/off state via green/red on both the vertical nav button and
  /// the drawer's own AIS-toggle button.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      icon: Icon(icon, color: Colors.white, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
    );
    final fill = backgroundColor ??
        (highlight ? Colors.white.withValues(alpha: 0.18) : null);
    if (fill == null) return button;
    return SizedBox(
      width: _navRowHeight,
      height: _navRowHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          button,
        ],
      ),
    );
  }
}

class _DrawerSlot extends StatelessWidget {
  const _DrawerSlot({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _navRowHeight,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: Alignment.centerRight,
        child: active
            ? _DrawerPill(child: child)
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _DrawerPill extends StatelessWidget {
  const _DrawerPill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(6),
          bottomLeft: Radius.circular(6),
        ),
      ),
      child: child,
    );
  }
}

class _AisDrawerRow extends StatelessWidget {
  const _AisDrawerRow({
    required this.aisEnabled,
    required this.aisActiveOnly,
    required this.aisShowPaths,
    required this.onToggleAis,
    required this.onToggleAisActive,
    required this.onToggleAisPaths,
    required this.onOpenAisList,
  });

  final bool aisEnabled;
  final bool aisActiveOnly;
  final bool aisShowPaths;
  final VoidCallback onToggleAis;
  final VoidCallback onToggleAisActive;
  final VoidCallback onToggleAisPaths;
  final VoidCallback onOpenAisList;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // AIS on/off — matches the vertical-nav AIS button's tint so
        // the user has the same green/red status cue inside the
        // drawer. Tapping here turns AIS off (and the conditional
        // below hides the filter / paths / list buttons).
        _NavIconButton(
          icon: aisEnabled ? Icons.sailing : Icons.sailing_outlined,
          tooltip: aisEnabled ? 'AIS on' : 'AIS off',
          backgroundColor: aisEnabled ? Colors.green : Colors.red,
          onPressed: onToggleAis,
        ),
        if (aisEnabled) ...[
          IconButton(
            icon: Icon(
              aisActiveOnly
                  ? Icons.filter_alt
                  : Icons.filter_alt_outlined,
              color: Colors.white,
              size: 20,
            ),
            tooltip: aisActiveOnly ? 'Active only' : 'All vessels',
            onPressed: onToggleAisActive,
          ),
          IconButton(
            icon: Icon(
              aisShowPaths ? Icons.timeline : Icons.linear_scale,
              color: Colors.white,
              size: 20,
            ),
            tooltip:
                aisShowPaths ? 'Hide projections' : 'Show projections',
            onPressed: onToggleAisPaths,
          ),
          IconButton(
            icon: const Icon(
              Icons.list_alt,
              color: Colors.white,
              size: 20,
            ),
            tooltip: 'AIS list',
            onPressed: onOpenAisList,
          ),
        ],
      ],
    );
  }
}

class _RoutesDrawerRow extends StatelessWidget {
  const _RoutesDrawerRow({
    required this.onRoutes,
    required this.weatherRoutingEnabled,
    required this.weatherRouteActive,
    required this.onWeatherRouting,
  });

  final VoidCallback onRoutes;
  final bool weatherRoutingEnabled;
  final bool weatherRouteActive;
  final VoidCallback? onWeatherRouting;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.route, color: Colors.white, size: 20),
          tooltip: 'Routes',
          onPressed: onRoutes,
        ),
        if (weatherRoutingEnabled)
          IconButton(
            icon: Icon(
              Icons.flight_takeoff,
              color: weatherRouteActive
                  ? const Color(0xFFFF9800)
                  : Colors.white,
              size: 20,
            ),
            tooltip: 'Weather routing',
            onPressed: onWeatherRouting,
          ),
      ],
    );
  }
}

class _LayersDrawerRow extends StatelessWidget {
  const _LayersDrawerRow({
    required this.onLayers,
    required this.onDownload,
    required this.playerVisible,
    required this.playerAvailable,
    required this.onTogglePlayer,
  });

  final VoidCallback onLayers;
  final VoidCallback onDownload;
  final bool playerVisible;
  final bool playerAvailable;
  final VoidCallback onTogglePlayer;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.layers, color: Colors.white, size: 20),
          tooltip: 'Chart layers',
          onPressed: onLayers,
        ),
        IconButton(
          icon: Icon(
            Icons.play_circle_outline,
            color: !playerAvailable
                ? Colors.white24
                : (playerVisible
                    ? const Color(0xFFFF9800)
                    : Colors.white),
            size: 20,
          ),
          tooltip: !playerAvailable
              ? 'Weather player (turn on a weather layer)'
              : (playerVisible
                  ? 'Hide weather player'
                  : 'Show weather player'),
          onPressed: playerAvailable ? onTogglePlayer : null,
        ),
        IconButton(
          icon: const Icon(Icons.download, color: Colors.white, size: 20),
          tooltip: 'Download charts',
          onPressed: onDownload,
        ),
      ],
    );
  }
}

/// Floating itinerary card that pops up when a weather-route
/// waypoint is selected. Lets the user step through the route
/// (first / prev / next / last) so the wind and current overlays
/// scrub to each waypoint's forecast time. Reuses
/// [WeatherRoutingItineraryCard] verbatim for the body so the visual
/// language stays in sync with the Result tab.
class _WeatherWaypointPopover extends StatelessWidget {
  const _WeatherWaypointPopover({
    required this.result,
    required this.selectedIndex,
    required this.onPrev,
    required this.onNext,
    required this.onFirst,
    required this.onLast,
    required this.onClose,
    required this.onClearRoute,
  });

  final WeatherRouteResult result;
  final int selectedIndex;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onFirst;
  final VoidCallback onLast;
  final VoidCallback onClose;
  final VoidCallback onClearRoute;

  @override
  Widget build(BuildContext context) {
    final s = result.summary;
    // When the router had to move the user's clicked start/end away
    // from the geometry endpoint, the user's original point gets its
    // own card in the sequence — index -1 for START, index
    // waypoints.length for END — navigable like any other waypoint.
    // The END sentinel is `waypoints.length` (not `coords.length`)
    // because a simplified geometry can have fewer coords than
    // waypoints, and we don't want the sentinel to collide with a
    // real waypoint index.
    final startVirtual = (s.startSnapDistanceM ?? 0) > 0 &&
        s.startOriginal != null &&
        result.waypoints.isNotEmpty;
    final endVirtual = (s.endSnapDistanceM ?? 0) > 0 &&
        s.endOriginal != null &&
        result.waypoints.isNotEmpty;
    final firstIdx = startVirtual ? -1 : 0;
    // Navigation range is the *waypoint* index range, not the geometry
    // (`coords`) range — the popover renders waypoint data, so when
    // simplified geometries have extra coords we don't want phantom
    // pages that all clamp back to the same final waypoint.
    final lastIdx = endVirtual
        ? result.waypoints.length
        : result.waypoints.length - 1;
    final totalCards = lastIdx - firstIdx + 1;
    final displayPos = (selectedIndex - firstIdx).clamp(0, totalCards - 1);
    final atFirst = selectedIndex <= firstIdx;
    final atLast = selectedIndex >= lastIdx;

    final WeatherRouteWaypoint waypoint;
    final WeatherRouteWaypoint? next;
    final WeatherRouteLegKind kind;
    final double? snapAdjustmentM;
    if (startVirtual && selectedIndex == -1) {
      final base = result.waypoints.first;
      waypoint =
          base.copyWith(lon: s.startOriginal![0], lat: s.startOriginal![1]);
      next = base;
      kind = legKindAt(result.waypoints, 0);
      snapAdjustmentM = s.startSnapDistanceM;
    } else if (endVirtual && selectedIndex == result.waypoints.length) {
      final base = result.waypoints.last;
      waypoint = base.copyWith(lon: s.endOriginal![0], lat: s.endOriginal![1]);
      next = null;
      kind = WeatherRouteLegKind.arrival;
      snapAdjustmentM = s.endSnapDistanceM;
    } else {
      // Guard against selection pointing past the waypoints list
      // (coords and waypoints can differ by one or two entries on
      // simplified geometries).
      final wpIdx = selectedIndex.clamp(0, result.waypoints.length - 1);
      waypoint = result.waypoints[wpIdx];
      next = wpIdx + 1 < result.waypoints.length
          ? result.waypoints[wpIdx + 1]
          : null;
      kind = legKindAt(result.waypoints, wpIdx);
      snapAdjustmentM = null;
    }

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: _popoverMaxHeight(context)),
        child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardBackgroundDark,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x88000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
          border: Border.all(color: const Color(0xFF2A2A44)),
        ),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header — nav buttons.
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'First waypoint',
                    icon: const Icon(Icons.first_page,
                        color: Colors.white70, size: 22),
                    onPressed: atFirst ? null : onFirst,
                  ),
                  IconButton(
                    tooltip: 'Previous waypoint',
                    icon: const Icon(Icons.chevron_left,
                        color: Colors.white70, size: 24),
                    onPressed: atFirst ? null : onPrev,
                  ),
                  Expanded(
                    child: Text(
                      'Waypoint ${displayPos + 1} of $totalCards',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontFamily: 'Menlo',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next waypoint',
                    icon: const Icon(Icons.chevron_right,
                        color: Colors.white70, size: 24),
                    onPressed: atLast ? null : onNext,
                  ),
                  IconButton(
                    tooltip: 'Last waypoint',
                    icon: const Icon(Icons.last_page,
                        color: Colors.white70, size: 22),
                    onPressed: atLast ? null : onLast,
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close,
                        color: Colors.white54, size: 20),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: WeatherRoutingItineraryCard(
                index: displayPos,
                waypoint: waypoint,
                next: next,
                kind: kind,
                selected: true,
                onTap: () {},
                // Non-null only on the virtual START / END cards —
                // the ones standing in for the user's clicked point
                // that the router moved to clear water.
                snapAdjustmentM: snapAdjustmentM,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onClearRoute,
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent, size: 16),
                      label: const Text(
                        'Clear route',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          ),
        ),
        ),
      ),
    );
  }
}

/// Pre-compute floating card shown when the user taps a Start or End
/// pin with no route yet computed. Offers a direct "Compute route"
/// action and a "Clear route" escape hatch that mirrors the
/// post-compute waypoint popover.
class _ComposePopover extends StatelessWidget {
  const _ComposePopover({
    required this.onCompute,
    required this.onClearRoute,
    required this.onClose,
  });

  final VoidCallback onCompute;
  final VoidCallback onClearRoute;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: _popoverMaxHeight(context)),
        child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardBackgroundDark,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x88000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
          border: Border.all(color: const Color(0xFF2A2A44)),
        ),
        child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.play_arrow,
                      color: AppColors.infoBlue, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Route',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close,
                        color: Colors.white54, size: 20),
                    onPressed: onClose,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onCompute,
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Compute route'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.infoBlue,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: onClearRoute,
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent, size: 16),
                      label: const Text(
                        'Clear',
                        style: TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
        ),
      ),
    );
  }
}

class _FreshnessChip extends StatelessWidget {
  const _FreshnessChip({required this.freshness, required this.connected});
  final TileFreshness freshness;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final color = switch (freshness) {
      TileFreshness.fresh => Colors.green,
      TileFreshness.aging => Colors.yellow,
      TileFreshness.stale => Colors.orange,
      TileFreshness.uncached => connected ? Colors.red : Colors.grey,
    };
    final label = switch (freshness) {
      TileFreshness.fresh => 'Fresh',
      TileFreshness.aging => '15d+',
      TileFreshness.stale => '30d+',
      TileFreshness.uncached => connected ? 'No cache' : 'Offline',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }
}

/// Colour-ramp strip shown under each enabled weather-layer toggle.
///
/// The gradient is painted using the server's legend stop colours
/// positioned by their SI value within `[valueMin, valueMax]`. Tick
/// labels beneath the bar are built through `MetadataStore` so the
/// text respects the user's unit preference (m/s → kt by default) —
/// per CLAUDE.md's "MetadataStore is the single source of truth for
/// conversions" rule. When `pathMetadata` is null (offline, no
/// matching SignalK path, e.g. roughness index) we fall through to
/// the server's SI values verbatim.
class _LegendBar extends StatelessWidget {
  const _LegendBar({
    required this.metadata,
    required this.pathMetadata,
    this.formatter,
    this.formatterSymbol,
  });

  final WeatherLayerMetadata metadata;
  final PathMetadata? pathMetadata;

  /// Optional override — when non-null, the legend hands SI values to
  /// this closure instead of going through [pathMetadata]'s formula.
  /// Used for layers whose conversions can't be expressed as a single
  /// multiplicative factor (temperature, precipitation rate); the
  /// closure routes through MetadataStore (server-fed PathMetadata)
  /// plus any non-unit scale the layer needs (e.g. seconds → hours
  /// for the precip rate).
  final String Function(double siValue)? formatter;

  /// User-preferred unit symbol shown in the legend heading when
  /// [formatter] is in play. Sourced from MetadataStore (server-fed
  /// `PathMetadata.symbol`) so the heading and tick labels agree on
  /// units.
  final String? formatterSymbol;

  // The server labels unitless scales (e.g. roughness index) as
  // "dimensionless". That word reads as noise next to the number, so
  // we treat it the same as no unit and drop it from heading + ticks.
  static bool _isUnitless(String? s) {
    if (s == null) return true;
    final t = s.trim();
    return t.isEmpty || t.toLowerCase() == 'dimensionless';
  }

  String _formatValue(double siValue) {
    final fmt = formatter;
    if (fmt != null) return fmt(siValue);
    if (pathMetadata != null && !_isUnitless(pathMetadata!.symbol)) {
      return pathMetadata!.format(siValue, decimals: 1);
    }
    final v = siValue.toStringAsFixed(1);
    final units = metadata.valueUnits;
    return _isUnitless(units) ? v : '$v $units';
  }

  String _legendHeading() {
    final serverTitle = metadata.legendTitle;
    // When a `formatter` is in play, its symbol came from MetadataStore
    // and is the source of truth. Otherwise fall back to the
    // path-metadata symbol, then to the server's SI tag.
    final symbol =
        formatterSymbol ?? pathMetadata?.symbol ?? metadata.valueUnits;
    final cleaned =
        serverTitle.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();
    if (_isUnitless(symbol)) return cleaned;
    return '$cleaned ($symbol)';
  }

  @override
  Widget build(BuildContext context) {
    final stops = metadata.stops;
    if (stops.length < 2) return const SizedBox.shrink();
    final minValue = metadata.valueMin ?? stops.first.value;
    final maxValue = metadata.valueMax ?? stops.last.value;
    final span = (maxValue - minValue).abs();
    final colors = stops.map((s) => s.color).toList(growable: false);
    final stopsNorm = stops
        .map((s) =>
            span == 0 ? 0.0 : ((s.value - minValue) / span).clamp(0.0, 1.0))
        .toList(growable: false);

    // Pick up to three tick labels: first, mid, last.
    final midIdx = stops.length ~/ 2;
    final ticks = <LegendStop>[
      stops.first,
      if (stops.length >= 3) stops[midIdx],
      stops.last,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_legendHeading(),
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 4),
        Container(
          height: 12,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            gradient: LinearGradient(
              colors: colors,
              stops: stopsNorm,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: ticks
              .map(
                (s) => Text(
                  _formatValue(s.value),
                  style: const TextStyle(
                      color: Colors.white54,
                      fontFamily: 'Menlo',
                      fontSize: 10),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

/// Per-layer freshness pill, shaped like `_FreshnessChip` so the two
/// read as the same visual language. Uses `last_update` when the
/// server provides it; otherwise falls back to `server_time` as the
/// age baseline, or to a grey chip with the `refresh_cadence` string
/// when neither timestamp is available.
class _LayerFreshnessChip extends StatelessWidget {
  const _LayerFreshnessChip({required this.metadata});

  final WeatherLayerMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final anchor = metadata.lastUpdate ?? metadata.serverTime;

    final Color dotColor;
    final String label;
    if (metadata.lastUpdate == null) {
      // No explicit update timestamp — show the cadence string.
      dotColor = Colors.grey;
      label = metadata.refreshCadence != null &&
              metadata.refreshCadence!.isNotEmpty
          ? 'Cadence: ${_truncate(metadata.refreshCadence!, 40)}'
          : 'No update time';
    } else {
      final age = now.difference(anchor!);
      if (age.inMinutes < 60) {
        dotColor = Colors.green;
        label = 'Fresh';
      } else if (age.inHours < 6) {
        dotColor = Colors.yellow;
        label = '${age.inHours} h';
      } else if (age.inHours < 24) {
        dotColor = Colors.orange;
        label = '${age.inHours} h';
      } else {
        dotColor = Colors.red;
        label = 'Stale (${age.inDays} d)';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 10)),
          ),
        ],
      ),
    );
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';
}

/// One entry in the on-map legend stack. Snapshot of the data each
/// `_LegendBar` needs; captured outside the FlutterMap subtree so the
/// stack widget can live under `MapCamera.of(context)` without
/// touching plotter state.
class _OnMapLegendEntry {
  const _OnMapLegendEntry({
    required this.metadata,
    required this.pathMetadata,
    required this.formatter,
    required this.formatterSymbol,
    required this.minZoom,
  });
  final WeatherLayerMetadata metadata;
  final PathMetadata? pathMetadata;
  final String Function(double)? formatter;
  final String? formatterSymbol;
  final int minZoom;
}

/// Vertically-stacked legends painted directly on the chart, above
/// the HUD. Lives outside the `FlutterMap` subtree, so it subscribes
/// to the `MapController`'s event stream itself to rebuild when the
/// camera zoom crosses a layer's minimum-zoom threshold.
class _OnMapLegendStack extends StatefulWidget {
  const _OnMapLegendStack({
    required this.service,
    required this.entries,
    required this.mapController,
    required this.initialZoom,
  });

  final WeatherDataService service;
  final List<_OnMapLegendEntry> entries;
  final MapController mapController;
  final double initialZoom;

  @override
  State<_OnMapLegendStack> createState() => _OnMapLegendStackState();
}

class _OnMapLegendStackState extends State<_OnMapLegendStack> {
  late double _zoom = widget.initialZoom;
  StreamSubscription<MapEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.mapController.mapEventStream.listen((e) {
      final z = e.camera.zoom;
      if (z != _zoom && mounted) {
        setState(() => _zoom = z);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _OnMapLegendStack old) {
    super.didUpdateWidget(old);
    if (old.mapController != widget.mapController) {
      _sub?.cancel();
      _sub = widget.mapController.mapEventStream.listen((e) {
        final z = e.camera.zoom;
        if (z != _zoom && mounted) {
          setState(() => _zoom = z);
        }
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) return const SizedBox.shrink();
    final visible = widget.entries
        .where((e) => _zoom >= e.minZoom)
        .toList(growable: false);
    if (visible.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: _LegendBar(
                  metadata: e.metadata,
                  pathMetadata: e.pathMetadata,
                  formatter: e.formatter,
                  formatterSymbol: e.formatterSymbol,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact dropdown for picking the minimum zoom at which a weather
/// layer appears. Range + default come from the server's metadata
/// (`minzoom` / `maxzoom`). Styled to match the dark card surface.
class _LayerZoomDropdown extends StatelessWidget {
  const _LayerZoomDropdown({
    required this.minZoom,
    required this.maxZoom,
    required this.current,
    required this.onChanged,
  });

  final int minZoom;
  final int maxZoom;
  final int current;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: current,
          isDense: true,
          dropdownColor: const Color(0xFF2A2A3E),
          iconSize: 16,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
          items: [
            for (var z = minZoom; z <= maxZoom; z++)
              DropdownMenuItem(
                value: z,
                child: Text('z ≥ $z'),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// Floating player strip pinned over the chart. Owns no state — its
/// fields come from the chart plotter and every interaction goes back
/// out through callbacks. Visible only when the player toggle is on
/// AND at least one time-keyed weather layer is active.
class _WeatherPlayerStrip extends StatelessWidget {
  const _WeatherPlayerStrip({
    required this.offsetHours,
    required this.direction,
    required this.minOffset,
    required this.maxOffset,
    required this.referenceTime,
    required this.layers,
    required this.onSetDirection,
    required this.onStep,
    required this.onSeek,
    required this.onResetToNow,
    required this.onClose,
  });

  final int offsetHours;
  /// 0 = paused, +1 = forward play, -1 = reverse play.
  final int direction;
  final int minOffset;
  final int maxOffset;
  final DateTime referenceTime;
  /// One entry per currently-enabled time-keyed weather layer, in
  /// canonical order. Drives the per-layer status chip row between
  /// the time label and the slider.
  final List<_WeatherPlayerStripLayer> layers;
  final ValueChanged<int> onSetDirection;
  final ValueChanged<int> onStep;
  final ValueChanged<int> onSeek;
  final VoidCallback onResetToNow;
  final VoidCallback onClose;

  static const Color _accent = Color(0xFFFF9800);

  @override
  Widget build(BuildContext context) {
    final local = referenceTime.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final dayLabel = _shortWeekday(local.weekday);
    final timeLabel = '$dayLabel ${two(local.hour)}:${two(local.minute)}';
    final offsetLabel = offsetHours == 0
        ? 'now'
        : (offsetHours > 0 ? '+${offsetHours}h' : '${offsetHours}h');
    final atMin = offsetHours <= minOffset;
    final atMax = offsetHours >= maxOffset;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontFamily: 'Menlo'),
                    children: [
                      TextSpan(
                        text: timeLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const TextSpan(text: '  '),
                      TextSpan(
                        text: offsetLabel,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.replay,
                    color: Colors.white70, size: 18),
                tooltip: 'Reset to now',
                onPressed: onResetToNow,
                constraints:
                    const BoxConstraints.tightFor(width: 32, height: 28),
                padding: EdgeInsets.zero,
              ),
              IconButton(
                icon: const Icon(Icons.close,
                    color: Colors.white70, size: 18),
                tooltip: 'Close player',
                onPressed: onClose,
                constraints:
                    const BoxConstraints.tightFor(width: 32, height: 28),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          // Row 1.5: per-layer status chips. Each active time-keyed
          // layer gets its own chip showing layer icon + label +
          // status (spinner / check / cross). Wraps so wide
          // configurations don't overflow the strip.
          if (layers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 2),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final l in layers) _layerChip(l),
                ],
              ),
            ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: _accent,
              inactiveTrackColor: Colors.white24,
              thumbColor: _accent,
            ),
            child: Slider(
              value:
                  offsetHours.clamp(minOffset, maxOffset).toDouble(),
              min: minOffset.toDouble(),
              max: maxOffset.toDouble(),
              divisions: maxOffset - minOffset,
              onChanged: (v) => onSeek(v.round()),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _transportButton(
                icon: Icons.skip_previous,
                tooltip: 'Step back 1 hour',
                tinted: false,
                enabled: !atMin,
                onPressed: () => onStep(-1),
              ),
              _transportButton(
                icon: direction == -1 ? Icons.pause : Icons.play_arrow,
                flipHorizontal: direction != -1,
                tooltip: direction == -1 ? 'Pause' : 'Play backward',
                tinted: direction == -1,
                enabled: !atMin,
                onPressed: () => onSetDirection(-1),
              ),
              _transportButton(
                icon: direction == 1 ? Icons.pause : Icons.play_arrow,
                tooltip: direction == 1 ? 'Pause' : 'Play forward',
                tinted: direction == 1,
                enabled: !atMax,
                onPressed: () => onSetDirection(1),
              ),
              _transportButton(
                icon: Icons.skip_next,
                tooltip: 'Step forward 1 hour',
                tinted: false,
                enabled: !atMax,
                onPressed: () => onStep(1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _layerChip(_WeatherPlayerStripLayer l) {
    final (statusWidget, statusColor) = switch (l.status) {
      _LayerLoadStatus.loading => (
          const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation(Colors.white70),
            ),
          ),
          Colors.white70,
        ),
      _LayerLoadStatus.loaded => (
          const Icon(Icons.check, size: 12, color: Color(0xFF88DD88)),
          const Color(0xFF88DD88),
        ),
      _LayerLoadStatus.error => (
          const Icon(Icons.error_outline,
              size: 12, color: Color(0xFFFF8888)),
          const Color(0xFFFF8888),
        ),
      _LayerLoadStatus.idle => (
          const Icon(Icons.hourglass_empty,
              size: 12, color: Colors.white38),
          Colors.white38,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(l.icon, size: 11, color: statusColor),
          const SizedBox(width: 4),
          Text(
            l.label,
            style: TextStyle(color: statusColor, fontSize: 10),
          ),
          const SizedBox(width: 4),
          statusWidget,
        ],
      ),
    );
  }

  Widget _transportButton({
    required IconData icon,
    required String tooltip,
    required bool tinted,
    required bool enabled,
    required VoidCallback onPressed,
    bool flipHorizontal = false,
  }) {
    final color =
        !enabled ? Colors.white24 : (tinted ? _accent : Colors.white);
    final iconWidget = Icon(icon, color: color, size: 24);
    return IconButton(
      icon: flipHorizontal
          ? Transform.flip(flipX: true, child: iconWidget)
          : iconWidget,
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      constraints: const BoxConstraints.tightFor(width: 40, height: 36),
      padding: EdgeInsets.zero,
    );
  }

  static String _shortWeekday(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Mon';
      case DateTime.tuesday:
        return 'Tue';
      case DateTime.wednesday:
        return 'Wed';
      case DateTime.thursday:
        return 'Thu';
      case DateTime.friday:
        return 'Fri';
      case DateTime.saturday:
        return 'Sat';
      case DateTime.sunday:
        return 'Sun';
    }
    return '';
  }
}

/// One layer's worth of state for the player strip's chip row.
/// Snapshot taken at build time on the chart plotter side and
/// passed in via [_WeatherPlayerStrip.layers] so the strip itself
/// stays a `StatelessWidget`.
class _WeatherPlayerStripLayer {
  const _WeatherPlayerStripLayer({
    required this.path,
    required this.label,
    required this.icon,
    required this.status,
  });
  final String path;
  final String label;
  final IconData icon;
  final _LayerLoadStatus status;
}

enum _LayerLoadStatus {
  /// Tiles are in flight for this layer — at least one outstanding
  /// fetch hasn't yet resolved (success or error).
  loading,

  /// The most recent fetch succeeded; nothing in flight.
  loaded,

  /// The most recent fetch errored; nothing in flight.
  error,

  /// No fetch has been observed yet for this layer (just enabled,
  /// hasn't entered the viewport, or the cache was just wiped).
  idle,
}

/// `NetworkTileProvider` subclass that pipes per-tile load events
/// into `WeatherDataService` so the chart plotter's player can hold
/// playback while tiles are still in flight, and per-layer status
/// chips can show loading / loaded / failed state.
///
/// `getImage` is called by `flutter_map` once per tile coordinate;
/// the returned `ImageProvider` is the standard `NetworkImage` from
/// the superclass. We resolve it ourselves with a one-shot
/// `ImageStreamListener` that decrements the in-flight counter on
/// either `onImage` or `onError`, then return the unmodified
/// provider so flutter_map renders normally. The double resolve is
/// a no-op in practice — `ImageProvider`'s cache key is identical,
/// so the second resolve hits the same in-flight stream.
class _WeatherTileProvider extends NetworkTileProvider {
  _WeatherTileProvider({
    required this.path,
    required this.service,
  })  : generation = service.cacheNonce,
        super(headers: service.authHeaders);

  final String path;
  final WeatherDataService service;

  /// Captured at construction so a tile resolve that lands after
  /// `reloadTiles()` (which bumps `cacheNonce` and clears the status
  /// maps) is dropped on the floor in the service's `recordTile*`
  /// guards instead of leaking a stale "loaded" or "errored" chip
  /// into the player's gating.
  final int generation;

  @override
  ImageProvider getImage(TileCoordinates coords, TileLayer options) {
    final inner = super.getImage(coords, options);
    service.recordTileStart(path, generation: generation);
    final stream = inner.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (image, sync) {
        service.recordTileSuccess(path, generation: generation);
        stream.removeListener(listener);
      },
      onError: (error, stack) {
        service.recordTileError(path, error, generation: generation);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return inner;
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.cardBackgroundDark,
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chart Plotter failed to initialise',
              style: TextStyle(
                color: AppColors.alarmRed,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChartPlotterV3Builder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'chart_plotter_v3',
      name: 'Chart Plotter',
      description:
          'Interactive chart plotter with S-57 charts, AIS, route, and '
          'nav data. Native-paint pipeline: OSM basemap via flutter_map '
          'plus S-57 overlay rendered by s52_dart through a Flutter '
          'CustomPainter.',
      category: ToolCategory.navigation,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
        styleOptions: const [],
        allowsUnitSelection: false,
        allowsVisibilityToggles: false,
        allowsTTL: false,
        // No SignalK paths to configure — the chart plotter pulls its
        // own-vessel and route data from fixed well-known paths via
        // SignalKService. Hides the "Configure Data Sources" section in
        // the config screen.
        allowsDataSources: false,
      ),
      defaultWidth: 6,
      defaultHeight: 6,
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: const [],
      style: StyleConfig(customProperties: const {}),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return ChartPlotterV3Tool(
      config: config,
      signalKService: signalKService,
    );
  }
}
