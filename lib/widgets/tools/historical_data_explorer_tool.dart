import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/ais_favorite.dart';
import '../../models/saved_search_area.dart';
import '../../models/tool_config.dart';
import '../../models/tool_definition.dart';
import '../../models/historical_data.dart' as hist;
import '../../services/ais_favorites_service.dart';
import '../../models/path_metadata.dart';
import '../../services/signalk_service.dart';
import '../../services/storage_service.dart';
import '../../services/historical_data_service.dart';
import '../../services/tool_registry.dart';
import '../tool_info_button.dart';

// ---------------------------------------------------------------------------
// Builder
// ---------------------------------------------------------------------------

class HistoricalDataExplorerBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() => ToolDefinition(
        id: 'historical_data_explorer',
        name: 'Historical Explorer',
        description: 'Explore historical data by geographic area',
        category: ToolCategory.charts,
        configSchema: ConfigSchema(
          allowsDataSources: false,
          allowsStyleConfig: false,
          allowsTTL: false,
          allowsMinMax: false,
          allowsColorCustomization: false,
        ),
        defaultWidth: 4,
        defaultHeight: 3,
      );

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return HistoricalDataExplorerTool(
      config: config,
      signalKService: signalKService,
    );
  }
}

// ---------------------------------------------------------------------------
// State machine
// ---------------------------------------------------------------------------

enum ExplorerState {
  idle,
  modeSelect,
  drawingBbox,
  drawingRadius,
  queryConfig,
  loading,
  results,
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Static cache to preserve query results across widget disposal (screen lock, reconnect).
class _ExplorerStateCache {
  static final Map<String, _CachedState> _cache = {};

  static void save(String key, _CachedState state) => _cache[key] = state;
  static _CachedState? get(String key) => _cache[key];
}

class _CachedState {
  final ExplorerState state;
  final hist.HistoricalDataResponse? response;
  final List<hist.ChartDataSeries> resultSeries;
  final List<_ResultPoint> resultPoints;
  final int selectedRowIndex;
  final int activeLegendIndex;
  final Set<int> visibleLegendIndices;
  final Set<String> selectedPaths;
  final String? bboxParam;
  final String? radiusParam;
  final LatLng? drawPoint1;
  final LatLng? drawPoint2;
  final String context;
  final DateTime fromDate;
  final DateTime toDate;
  final String aggregation;
  final String smoothing;
  final LatLng? mapCenter;

  _CachedState({
    required this.state,
    this.response,
    required this.resultSeries,
    required this.resultPoints,
    required this.selectedRowIndex,
    required this.activeLegendIndex,
    required this.visibleLegendIndices,
    required this.selectedPaths,
    this.bboxParam,
    this.radiusParam,
    this.drawPoint1,
    this.drawPoint2,
    required this.context,
    required this.fromDate,
    required this.toDate,
    required this.aggregation,
    required this.smoothing,
    this.mapCenter,
  });
}

class HistoricalDataExplorerTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const HistoricalDataExplorerTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<HistoricalDataExplorerTool> createState() =>
      _HistoricalDataExplorerToolState();
}

class _HistoricalDataExplorerToolState extends State<HistoricalDataExplorerTool>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  // Map
  final MapController _mapController = MapController();

  // State
  ExplorerState _state = ExplorerState.idle;

  // Drawing
  LatLng? _drawPoint1;
  LatLng? _drawPoint2;

  // Spatial query params (computed after drawing)
  String? _bboxParam;
  String? _radiusParam;

  // Drag-to-move area
  bool _isDraggingArea = false;
  LatLng? _dragStartLatLng;
  LatLng? _dragPoint1Origin;
  LatLng? _dragPoint2Origin;

  // Drag-to-resize handle
  int? _draggingHandleIndex;

  // Vessel position
  LatLng? _vesselPosition;
  bool _centeredOnHomeport = false;

  // Available paths (cached)
  List<String> _availablePaths = [];
  bool _pathsLoading = false;

  // Available contexts
  List<String> _availableContexts = ['vessels.self'];
  bool _contextsLoading = false;
  String _context = 'vessels.self';

  // Query config
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _toDate = DateTime.now();
  final Set<String> _selectedPaths = {};
  String _aggregation = 'average';
  String _smoothing = 'none';
  int _smaWindow = 5;
  double _emaAlpha = 0.3;

  // Results
  hist.HistoricalDataResponse? _response;
  List<hist.ChartDataSeries> _resultSeries = [];
  List<_ResultPoint> _resultPoints = [];
  int _selectedRowIndex = -1;

  // Playback
  Timer? _playbackTimer;
  bool _isPlaying = false;
  int _playbackDirection = 1;    // 1=forward, -1=reverse
  double _playbackSpeed = 1.0;   // 1x, 2x, 5x, 10x
  int _playbackListIndex = 0;    // index into _resultPoints list
  static const int _baseIntervalMs = 500;
  static const List<double> _speedOptions = [1.0, 2.0, 5.0, 10.0];

  // Legend
  int _activeLegendIndex = 0;
  Set<int> _visibleLegendIndices = {0};

  // Bottom panel tabs
  late TabController _tabController;

  // Service
  HistoricalDataService? _historyService;

  // Saved search areas
  static const String _cacheKey = 'historical_data_explorer';

  static const String _searchAreaResourceType = 'zeddisplay-search-areas';
  static const String _localStorageKey = 'saved_search_areas';
  List<SavedSearchArea> _savedAreas = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _restoreFromCache();
    widget.signalKService.addListener(_onSignalKChanged);
    _updateVesselPosition();
    _initService();
    _loadSavedAreas();
  }

  @override
  void didUpdateWidget(HistoricalDataExplorerTool oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signalKService != widget.signalKService) {
      oldWidget.signalKService.removeListener(_onSignalKChanged);
      widget.signalKService.addListener(_onSignalKChanged);
    }
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _saveToCache();
    _tabController.dispose();
    widget.signalKService.removeListener(_onSignalKChanged);
    super.dispose();
  }

  void _saveToCache() {
    if (_state != ExplorerState.results || _resultPoints.isEmpty) return;
    LatLng? center;
    try { center = _mapController.camera.center; } catch (_) {}
    _ExplorerStateCache.save(_cacheKey, _CachedState(
      state: _state,
      response: _response,
      resultSeries: _resultSeries,
      resultPoints: _resultPoints,
      selectedRowIndex: _selectedRowIndex,
      activeLegendIndex: _activeLegendIndex,
      visibleLegendIndices: Set.from(_visibleLegendIndices),
      selectedPaths: Set.from(_selectedPaths),
      bboxParam: _bboxParam,
      radiusParam: _radiusParam,
      drawPoint1: _drawPoint1,
      drawPoint2: _drawPoint2,
      context: _context,
      fromDate: _fromDate,
      toDate: _toDate,
      aggregation: _aggregation,
      smoothing: _smoothing,
      mapCenter: center,
    ));
  }

  void _restoreFromCache() {
    final cached = _ExplorerStateCache.get(_cacheKey);
    if (cached == null) return;
    _state = cached.state;
    _response = cached.response;
    _resultSeries = cached.resultSeries;
    _resultPoints = cached.resultPoints;
    _selectedRowIndex = cached.selectedRowIndex;
    _activeLegendIndex = cached.activeLegendIndex;
    _visibleLegendIndices = Set.from(cached.visibleLegendIndices);
    _selectedPaths..clear()..addAll(cached.selectedPaths);
    _bboxParam = cached.bboxParam;
    _radiusParam = cached.radiusParam;
    _drawPoint1 = cached.drawPoint1;
    _drawPoint2 = cached.drawPoint2;
    _context = cached.context;
    _fromDate = cached.fromDate;
    _toDate = cached.toDate;
    _aggregation = cached.aggregation;
    _smoothing = cached.smoothing;
    if (cached.mapCenter != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          try { _mapController.move(cached.mapCenter!, 14); } catch (_) {}
        }
      });
    }
  }

  void _onSignalKChanged() {
    if (!mounted) return;
    _updateVesselPosition();
    // Re-init service on reconnect (new auth token, etc.)
    if (_historyService == null && widget.signalKService.isConnected) {
      _initService();
      _loadSavedAreas(); // Reload from server on reconnect
    }
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Initialization helpers
  // ---------------------------------------------------------------------------

  void _initService() {
    if (widget.signalKService.isConnected) {
      _historyService = HistoricalDataService(
        serverUrl: widget.signalKService.serverUrl,
        useSecureConnection: widget.signalKService.useSecureConnection,
        authToken: widget.signalKService.authToken,
      );
      _fetchAvailablePaths();
    }
  }

  void _updateVesselPosition() {
    final posData = widget.signalKService.getValue('navigation.position');
    if (posData?.value is Map) {
      final pos = posData!.value as Map;
      final lat = (pos['latitude'] as num?)?.toDouble();
      final lon = (pos['longitude'] as num?)?.toDouble();
      if (lat != null && lon != null) {
        _vesselPosition = LatLng(lat, lon);
      }
    }
  }

  LatLng? get _homeportPosition {
    final props = widget.config.style.customProperties;
    if (props == null) return null;
    final lat = (props['homeportLat'] as num?)?.toDouble();
    final lon = (props['homeportLon'] as num?)?.toDouble();
    if (lat != null && lon != null) return LatLng(lat, lon);
    return null;
  }

  bool get _showSeaMap =>
      widget.config.style.customProperties?['showSeaMap'] as bool? ?? true;

  LatLng get _mapCenter {
    if (_centeredOnHomeport && _homeportPosition != null) {
      return _homeportPosition!;
    }
    return _vesselPosition ?? const LatLng(0, 0);
  }

  LatLng? get _areaCenter {
    if (_drawPoint1 == null) return null;
    if (_bboxParam != null && _drawPoint2 != null) {
      return LatLng(
        (_drawPoint1!.latitude + _drawPoint2!.latitude) / 2,
        (_drawPoint1!.longitude + _drawPoint2!.longitude) / 2,
      );
    }
    return _drawPoint1;
  }

  Future<void> _fetchAvailablePaths() async {
    if (_historyService == null || _pathsLoading) return;
    setState(() => _pathsLoading = true);
    try {
      final allPaths = await _historyService!.getAvailablePaths();
      // Keep only numeric-valued paths. Filter out position (added
      // automatically), notifications, boolean states, and object paths.
      _availablePaths = allPaths.where((p) {
        if (p == 'navigation.position') return false;
        if (p == 'navigation.attitude') return false;
        // Boolean / notification / state / command paths don't aggregate
        if (p.startsWith('commands.')) return false;
        if (p.contains('.notification')) return false;
        if (p.endsWith('.state')) return false;
        // Check live cache — if value is not numeric, skip
        final dp = widget.signalKService.getValue(p);
        if (dp != null && dp.value is! num) return false;
        // Check metadata — skip boolean/enum categories
        final meta = widget.signalKService.metadataStore.get(p);
        if (meta != null && meta.category == 'boolean') return false;
        return true;
      }).toList();
    } catch (e) {
      if (kDebugMode) print('Failed to fetch available paths: $e');
    } finally {
      if (mounted) setState(() => _pathsLoading = false);
    }
  }

  Future<void> _fetchAvailableContexts(
    DateTime from,
    DateTime to, {
    void Function(void Function())? dialogSetState,
  }) async {
    if (_historyService == null || _contextsLoading) return;
    _contextsLoading = true;
    dialogSetState?.call(() {});
    try {
      // Use spatial endpoint when bbox/radius is available, otherwise
      // fall back to time-only contexts endpoint.
      final List<String> contexts;
      if (_bboxParam != null || _radiusParam != null) {
        contexts = await _historyService!.getSpatialContexts(
          from: from,
          to: to,
          bbox: _bboxParam,
          radius: _radiusParam,
        );
      } else {
        contexts = await _historyService!.getAvailableContexts(
          from: from,
          to: to,
        );
      }
      // Ensure 'vessels.self' is always present
      if (!contexts.contains('vessels.self')) {
        contexts.insert(0, 'vessels.self');
      }
      // Remove own vessel's full URN — it duplicates 'vessels.self'
      final ownContext = widget.signalKService.vesselContext;
      if (ownContext != null) {
        contexts.remove(ownContext);
      }
      _availableContexts = contexts;
    } catch (e) {
      if (kDebugMode) print('Failed to fetch available contexts: $e');
    } finally {
      _contextsLoading = false;
      if (mounted) dialogSetState?.call(() {});
    }
  }

  /// Extract bare MMSI from a context string, or null.
  String? _extractMMSI(String ctx) {
    return RegExp(r'mmsi:(\d+)').firstMatch(ctx)?.group(1);
  }

  /// Friendly display name for a context string.
  /// If [favorites] is provided, favorite names are included.
  String _contextDisplayName(String ctx, [List<AISFavorite>? favorites]) {
    if (ctx == 'vessels.self') {
      final nameData = widget.signalKService.getValue('name');
      final name = nameData?.value is String ? nameData!.value as String : null;
      return name != null ? 'Self ($name)' : 'Self';
    }
    final mmsi = _extractMMSI(ctx);
    if (mmsi != null) {
      // Check favorites for a name
      if (favorites != null) {
        final fav = favorites.cast<AISFavorite?>().firstWhere(
            (f) => f!.mmsi == mmsi,
            orElse: () => null);
        if (fav != null) return '⭐ ${fav.name} ($mmsi)';
      }
      return 'MMSI $mmsi';
    }
    // Fallback: last segment
    final lastDot = ctx.lastIndexOf('.');
    return lastDot >= 0 ? ctx.substring(lastDot + 1) : ctx;
  }

  // ---------------------------------------------------------------------------
  // Playback
  // ---------------------------------------------------------------------------

  void _selectPointByIndex(int pointIndex, {bool panMap = true}) {
    final listIdx = _resultPoints.indexWhere((p) => p.index == pointIndex);
    if (listIdx >= 0) _playbackListIndex = listIdx;
    setState(() => _selectedRowIndex = pointIndex);
    if (panMap) {
      final pt = _resultPoints.firstWhere(
        (p) => p.index == pointIndex,
        orElse: () => _resultPoints.first,
      );
      try {
        _mapController.move(pt.position, _mapController.camera.zoom);
      } catch (_) {}
    }
  }

  void _startPlayback({int direction = 1}) {
    if (_resultPoints.isEmpty) return;
    // Sync list index from current selection
    if (_selectedRowIndex >= 0) {
      final idx = _resultPoints.indexWhere((p) => p.index == _selectedRowIndex);
      if (idx >= 0) _playbackListIndex = idx;
    } else {
      _playbackListIndex = direction == 1 ? 0 : _resultPoints.length - 1;
    }
    _playbackDirection = direction;
    _playbackTimer?.cancel();
    final intervalMs = (_baseIntervalMs / _playbackSpeed).round();
    _playbackTimer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      _onPlaybackTick,
    );
    setState(() => _isPlaying = true);
  }

  void _stopPlayback() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    setState(() => _isPlaying = false);
  }

  void _onPlaybackTick(Timer timer) {
    if (!mounted) { timer.cancel(); return; }
    final nextIdx = _playbackListIndex + _playbackDirection;
    if (nextIdx < 0 || nextIdx >= _resultPoints.length) {
      _stopPlayback();
      return;
    }
    _playbackListIndex = nextIdx;
    _selectPointByIndex(_resultPoints[nextIdx].index, panMap: false);
  }

  void _jumpPlayback(int delta) {
    if (_resultPoints.isEmpty) return;
    // Sync from current selection if needed
    if (_selectedRowIndex >= 0) {
      final idx = _resultPoints.indexWhere((p) => p.index == _selectedRowIndex);
      if (idx >= 0) _playbackListIndex = idx;
    }
    final nextIdx = (_playbackListIndex + delta).clamp(0, _resultPoints.length - 1);
    _playbackListIndex = nextIdx;
    _selectPointByIndex(_resultPoints[nextIdx].index, panMap: false);
  }

  void _setPlaybackSpeed(double speed) {
    _playbackSpeed = speed;
    if (_isPlaying) {
      _playbackTimer?.cancel();
      final intervalMs = (_baseIntervalMs / _playbackSpeed).round();
      _playbackTimer = Timer.periodic(
        Duration(milliseconds: intervalMs),
        _onPlaybackTick,
      );
    }
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Saved search areas
  // ---------------------------------------------------------------------------

  Future<void> _loadSavedAreas() async {
    // Load from local cache first
    try {
      final storageService = context.read<StorageService>();
      final cached = storageService.getSetting(_localStorageKey);
      if (cached != null) {
        final list = jsonDecode(cached) as List;
        _savedAreas = list
            .map((e) => SavedSearchArea.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      if (kDebugMode) print('Error loading saved areas from cache: $e');
    }

    // If connected, fetch from server (source of truth) and merge
    if (widget.signalKService.isConnected) {
      try {
        final resources =
            await widget.signalKService.getResources(_searchAreaResourceType);
        if (resources.isNotEmpty) {
          final serverAreas = <SavedSearchArea>[];
          for (final entry in resources.entries) {
            try {
              serverAreas.add(SavedSearchArea.fromResourceData(
                entry.key,
                entry.value as Map<String, dynamic>,
              ));
            } catch (_) {}
          }
          // Server is source of truth — merge with local-only items
          final serverIds = serverAreas.map((a) => a.id).toSet();
          final localOnly =
              _savedAreas.where((a) => !serverIds.contains(a.id)).toList();
          _savedAreas = [...serverAreas, ...localOnly];
        }
      } catch (e) {
        if (kDebugMode) print('Error loading saved areas from server: $e');
      }
    }

    // Sort by creation date (newest first)
    _savedAreas.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Persist merged list locally
    _persistLocalAreas();

    if (mounted) setState(() {});
  }

  void _persistLocalAreas() {
    try {
      final storageService = context.read<StorageService>();
      final json = jsonEncode(_savedAreas.map((a) => a.toJson()).toList());
      storageService.saveSetting(_localStorageKey, json);
    } catch (_) {}
  }

  Future<void> _saveArea(SavedSearchArea area) async {
    // Save to server
    if (widget.signalKService.isConnected) {
      await widget.signalKService.ensureResourceTypeExists(
        _searchAreaResourceType,
        description: 'ZedDisplay saved search areas',
      );
      await widget.signalKService.putResource(
        _searchAreaResourceType,
        area.id,
        area.toResourceData(),
      );
    }

    // Add to local list
    _savedAreas.insert(0, area);
    _persistLocalAreas();
    if (mounted) setState(() {});
  }

  Future<void> _deleteArea(SavedSearchArea area) async {
    // Delete from server
    if (widget.signalKService.isConnected) {
      await widget.signalKService.deleteResource(
        _searchAreaResourceType,
        area.id,
      );
    }

    // Remove from local list
    _savedAreas.removeWhere((a) => a.id == area.id);
    _persistLocalAreas();
    if (mounted) setState(() {});
  }

  void _applySavedArea(SavedSearchArea area) {
    setState(() {
      _drawPoint1 = area.drawPoint1;
      _drawPoint2 = area.drawPoint2;
      if (area.type == 'bbox') {
        _computeBboxParam();
      } else {
        _computeRadiusParam();
      }
      _state = ExplorerState.queryConfig;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showQueryConfigDialog();
    });
  }

  void _showSaveAreaDialog() {
    if (_drawPoint1 == null || _drawPoint2 == null) return;

    final nameController = TextEditingController();
    final descController = TextEditingController();
    final areaType = _bboxParam != null ? 'bbox' : 'radius';

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Save Search Area'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  hintText: 'e.g. Marina Bay',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                double? radius;
                if (areaType == 'radius') {
                  radius = const Distance()
                      .as(LengthUnit.Meter, _drawPoint1!, _drawPoint2!)
                      .roundToDouble();
                }

                final area = SavedSearchArea(
                  name: name,
                  description: descController.text.trim().isEmpty
                      ? null
                      : descController.text.trim(),
                  type: areaType,
                  point1Lat: _drawPoint1!.latitude,
                  point1Lng: _drawPoint1!.longitude,
                  point2Lat: _drawPoint2!.latitude,
                  point2Lng: _drawPoint2!.longitude,
                  radiusMeters: radius,
                );

                Navigator.pop(ctx);
                _saveArea(area);
                _showSnack('Area saved: $name');
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showSavedAreasSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.folder_open),
                          const SizedBox(width: 8),
                          Text(
                            'Saved Areas (${_savedAreas.length})',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    if (_savedAreas.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No saved areas yet.\n'
                            'Draw an area and tap the save button to save it.'),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _savedAreas.length,
                          itemBuilder: (ctx, i) {
                            final area = _savedAreas[i];
                            return Dismissible(
                              key: ValueKey(area.id),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                color: Colors.red,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 16),
                                child: const Icon(Icons.delete,
                                    color: Colors.white),
                              ),
                              onDismissed: (_) {
                                _deleteArea(area);
                                setSheetState(() {});
                              },
                              child: ListTile(
                                leading: Icon(
                                  area.type == 'bbox'
                                      ? Icons.crop_square
                                      : Icons.radio_button_unchecked,
                                ),
                                title: Text(area.name),
                                subtitle: Text(
                                  [
                                    _fmtDate(area.createdAt),
                                    if (area.description != null &&
                                        area.description!.isNotEmpty)
                                      area.description!.length > 40
                                          ? '${area.description!.substring(0, 40)}...'
                                          : area.description!,
                                  ].join(' \u2022 '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _applySavedArea(area);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Spatial param builders
  // ---------------------------------------------------------------------------

  void _computeBboxParam() {
    if (_drawPoint1 == null || _drawPoint2 == null) return;
    final c1 = _drawPoint1!;
    final c2 = _drawPoint2!;
    final west = math.min(c1.longitude, c2.longitude);
    final south = math.min(c1.latitude, c2.latitude);
    final east = math.max(c1.longitude, c2.longitude);
    final north = math.max(c1.latitude, c2.latitude);
    _bboxParam = '$west,$south,$east,$north';
    _radiusParam = null;
  }

  void _computeRadiusParam() {
    if (_drawPoint1 == null || _drawPoint2 == null) return;
    final center = _drawPoint1!;
    final edge = _drawPoint2!;
    final meters =
        const Distance().as(LengthUnit.Meter, center, edge).round();
    _radiusParam = '${center.longitude},${center.latitude},$meters';
    _bboxParam = null;
  }

  // ---------------------------------------------------------------------------
  // Query execution
  // ---------------------------------------------------------------------------

  Future<void> _executeQuery() async {
    if (_selectedPaths.isEmpty) {
      _showSnack('Select at least one path');
      return;
    }
    if (!_fromDate.isBefore(_toDate)) {
      _showSnack('Start date must be before end date');
      return;
    }
    if (_historyService == null) {
      _showSnack('Not connected to server');
      return;
    }

    setState(() {
      _state = ExplorerState.loading;

    });

    try {
      // Build path expressions — always include navigation.position
      // so the server can correlate data with vessel location
      final pathExpressions = <String>[
        'navigation.position',
        ..._selectedPaths.map((p) {
          if (_smoothing == 'none') return p;
          final param = _smoothing == 'sma' ? '$_smaWindow' : '$_emaAlpha';
          return '$p:$_aggregation:$_smoothing:$param';
        }),
      ];

      final response = await _fetchWithSpatialParams(
        paths: pathExpressions,
        from: _fromDate,
        to: _toDate,
      );

      // Ensure metadata exists for all selected paths (fetch from server if missing)
      await Future.wait(_selectedPaths.map((path) async {
        if (widget.signalKService.metadataStore.get(path) == null) {
          await widget.signalKService.fetchPathMeta(path);
        }
      }));

      // Build chart series for each user-selected path
      final series = <hist.ChartDataSeries>[];
      for (final path in _selectedPaths) {
        final s = hist.ChartDataSeries.fromHistoricalData(
          response,
          path,
          method: _aggregation,
          smoothing: _smoothing == 'none' ? null : _smoothing,
          signalKService: widget.signalKService,
        );
        if (s != null) series.add(s);
      }

      // Find position column index and extract plotted points
      final posIdx = response.values.indexWhere(
          (v) => v.path == 'navigation.position');
      final points = <_ResultPoint>[];
      if (posIdx != -1) {
        for (var i = 0; i < response.data.length; i++) {
          final row = response.data[i];
          if (posIdx >= row.values.length) continue;
          final posVal = row.values[posIdx];
          final latLng = _parsePosition(posVal);
          if (latLng == null) continue;

          // Collect converted values for each user-selected path
          final dataValues = <String, double>{};
          for (final s in series) {
            final valIdx = response.values.indexWhere((v) {
              if (v.path != s.path) return false;
              if (s.smoothing == null) return v.smoothing == null;
              return v.smoothing == s.smoothing;
            });
            if (valIdx != -1 && valIdx < row.values.length) {
              final raw = row.values[valIdx];
              if (raw is num) {
                dataValues[s.path] = raw.toDouble();
              }
            }
          }
          points.add(_ResultPoint(
            index: i,
            position: latLng,
            timestamp: row.timestamp,
            values: dataValues,
          ));
        }
      }

      if (mounted) {
        setState(() {
          _response = response;
          _resultSeries = series;
          _resultPoints = points;
          _state = ExplorerState.results;
          _selectedRowIndex = -1;
          _activeLegendIndex = 0;
          _visibleLegendIndices = {0};
        });
        _saveToCache();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = ExplorerState.idle;
        });
        _showSnack('Query failed: $e');
      }
    }
  }

  /// Fetch historical data with spatial parameters via the service.
  Future<hist.HistoricalDataResponse> _fetchWithSpatialParams({
    required List<String> paths,
    required DateTime from,
    required DateTime to,
  }) {
    return _historyService!.fetchHistoricalDataBatched(
      paths: paths,
      from: from,
      to: to,
      context: _context,
      bbox: _bboxParam,
      radius: _radiusParam,
    );
  }

  // ---------------------------------------------------------------------------
  // Map interaction
  // ---------------------------------------------------------------------------

  bool _isInsideArea(LatLng point) {
    if (_drawPoint1 == null || _drawPoint2 == null) return false;
    if (_bboxParam != null) {
      final minLat = math.min(_drawPoint1!.latitude, _drawPoint2!.latitude);
      final maxLat = math.max(_drawPoint1!.latitude, _drawPoint2!.latitude);
      final minLng = math.min(_drawPoint1!.longitude, _drawPoint2!.longitude);
      final maxLng = math.max(_drawPoint1!.longitude, _drawPoint2!.longitude);
      return point.latitude >= minLat &&
          point.latitude <= maxLat &&
          point.longitude >= minLng &&
          point.longitude <= maxLng;
    }
    if (_radiusParam != null) {
      final dist = const Distance().as(
          LengthUnit.Meter, _drawPoint1!, point);
      final edgeDist = const Distance().as(
          LengthUnit.Meter, _drawPoint1!, _drawPoint2!);
      return dist <= edgeDist;
    }
    return false;
  }

  void _onAreaDragStart(LongPressStartDetails details) {
    if (!mounted) return;
    final latLng = _mapController.camera
        .screenOffsetToLatLng(details.localPosition);

    // Check if the long-press started on a handle → resize mode
    final handleHit = _hitTestHandle(details.localPosition);
    if (handleHit >= 0) {
      setState(() {
        _draggingHandleIndex = handleHit;
        _dragPoint1Origin = _drawPoint1;
        _dragPoint2Origin = _drawPoint2;
      });
      return;
    }

    // Otherwise, move-area mode
    if (!_isInsideArea(latLng)) return;
    setState(() {
      _isDraggingArea = true;
      _dragStartLatLng = latLng;
      _dragPoint1Origin = _drawPoint1;
      _dragPoint2Origin = _drawPoint2;
    });
  }

  void _onAreaDragUpdate(LongPressMoveUpdateDetails details) {
    if (!mounted) return;

    // Handle resize mode
    if (_draggingHandleIndex != null) {
      if (_drawPoint1 == null || _drawPoint2 == null) return;
      final latLng = _mapController.camera
          .screenOffsetToLatLng(details.localPosition);
      final index = _draggingHandleIndex!;
      setState(() {
        if (_bboxParam != null) {
          switch (index) {
            case 0:
              _drawPoint1 = LatLng(latLng.latitude, latLng.longitude);
              break;
            case 1:
              _drawPoint1 = LatLng(latLng.latitude, _drawPoint1!.longitude);
              _drawPoint2 = LatLng(_drawPoint2!.latitude, latLng.longitude);
              break;
            case 2:
              _drawPoint2 = LatLng(latLng.latitude, latLng.longitude);
              break;
            case 3:
              _drawPoint1 = LatLng(_drawPoint1!.latitude, latLng.longitude);
              _drawPoint2 = LatLng(latLng.latitude, _drawPoint2!.longitude);
              break;
          }
        } else if (_radiusParam != null) {
          if (index == 0) {
            final dLat = latLng.latitude - _drawPoint1!.latitude;
            final dLng = latLng.longitude - _drawPoint1!.longitude;
            _drawPoint1 = latLng;
            _drawPoint2 = LatLng(
              _drawPoint2!.latitude + dLat,
              _drawPoint2!.longitude + dLng,
            );
          } else {
            _drawPoint2 = latLng;
          }
        }
      });
      return;
    }

    // Move-area mode
    if (!_isDraggingArea || _dragStartLatLng == null) return;
    final current = _mapController.camera
        .screenOffsetToLatLng(details.localPosition);
    final dLat = current.latitude - _dragStartLatLng!.latitude;
    final dLng = current.longitude - _dragStartLatLng!.longitude;
    setState(() {
      _drawPoint1 = LatLng(
        _dragPoint1Origin!.latitude + dLat,
        _dragPoint1Origin!.longitude + dLng,
      );
      _drawPoint2 = LatLng(
        _dragPoint2Origin!.latitude + dLat,
        _dragPoint2Origin!.longitude + dLng,
      );
    });
  }

  void _onAreaDragEnd(LongPressEndDetails details) {
    if (!mounted) return;
    if (!_isDraggingArea && _draggingHandleIndex == null) return;
    // Recompute spatial param from new positions
    if (_bboxParam != null) {
      _computeBboxParam();
    } else if (_radiusParam != null) {
      _computeRadiusParam();
    }
    setState(() {
      _isDraggingArea = false;
      _draggingHandleIndex = null;
      _dragStartLatLng = null;
      _dragPoint1Origin = null;
      _dragPoint2Origin = null;
    });
    if (_selectedPaths.isNotEmpty) {
      _executeQuery();
    }
  }

  void _onAreaDragCancel() {
    if (!mounted) return;
    if (!_isDraggingArea && _draggingHandleIndex == null) return;
    setState(() {
      _drawPoint1 = _dragPoint1Origin;
      _drawPoint2 = _dragPoint2Origin;
      _isDraggingArea = false;
      _draggingHandleIndex = null;
      _dragStartLatLng = null;
      _dragPoint1Origin = null;
      _dragPoint2Origin = null;
    });
  }

  // ---------------------------------------------------------------------------
  // Handle hit-testing for resize
  // ---------------------------------------------------------------------------

  static const double _handleHitRadius = 24.0;

  int _hitTestHandle(Offset screenPos) {
    final positions = _handlePositions();
    for (int i = 0; i < positions.length; i++) {
      final screen = _mapController.camera.latLngToScreenOffset(positions[i]);
      if ((screen - screenPos).distance <= _handleHitRadius) return i;
    }
    return -1;
  }

  List<LatLng> _handlePositions() {
    if (_drawPoint1 == null || _drawPoint2 == null) return [];
    if (_bboxParam != null) {
      return _bboxCorners(_drawPoint1!, _drawPoint2!);
    } else if (_radiusParam != null) {
      return [_drawPoint1!, _drawPoint2!];
    }
    return [];
  }

  void _showModeSelectSheet() {
    showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.crop_square),
              title: const Text('Bounding Box'),
              subtitle: const Text('Tap two corners to define a rectangle'),
              onTap: () => Navigator.pop(ctx, 'bbox'),
            ),
            ListTile(
              leading: const Icon(Icons.radio_button_unchecked),
              title: const Text('Radius'),
              subtitle: const Text('Tap center then edge to define a circle'),
              onTap: () => Navigator.pop(ctx, 'radius'),
            ),
            if (_savedAreas.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Saved Areas'),
                subtitle: Text('${_savedAreas.length} saved'),
                onTap: () => Navigator.pop(ctx, 'saved'),
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    ).then((value) {
      if (!mounted) return;
      if (value == 'bbox') {
        setState(() {
          _state = ExplorerState.drawingBbox;
          _drawPoint1 = null;
          _drawPoint2 = null;
        });
      } else if (value == 'radius') {
        setState(() {
          _state = ExplorerState.drawingRadius;
          _drawPoint1 = null;
          _drawPoint2 = null;
        });
      } else if (value == 'saved') {
        setState(() => _state = ExplorerState.idle);
        _showSavedAreasSheet();
      } else {
        setState(() => _state = ExplorerState.idle);
      }
    });
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (_state == ExplorerState.drawingBbox) {
      _handleDrawingTap(point, isBbox: true);
    } else if (_state == ExplorerState.drawingRadius) {
      _handleDrawingTap(point, isBbox: false);
    }
  }

  void _handleDrawingTap(LatLng point, {required bool isBbox}) {
    if (_drawPoint1 == null) {
      setState(() => _drawPoint1 = point);
    } else {
      setState(() {
        _drawPoint2 = point;
        if (isBbox) {
          _computeBboxParam();
        } else {
          _computeRadiusParam();
        }
        _state = ExplorerState.queryConfig;
      });
      // Show the config dialog after frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showQueryConfigDialog();
      });
    }
  }

  /// Parse position value from history API row.
  /// Handles {latitude, longitude} object or [lon, lat] GeoJSON array.
  LatLng? _parsePosition(dynamic val) {
    if (val is Map) {
      final lat = (val['latitude'] as num?)?.toDouble();
      final lon = (val['longitude'] as num?)?.toDouble();
      if (lat != null && lon != null) return LatLng(lat, lon);
    } else if (val is List && val.length >= 2) {
      // GeoJSON: [longitude, latitude]
      final lon = (val[0] as num?)?.toDouble();
      final lat = (val[1] as num?)?.toDouble();
      if (lat != null && lon != null) return LatLng(lat, lon);
    }
    return null;
  }

  void _clearDrawing() {
    setState(() {
      _state = ExplorerState.idle;
      _drawPoint1 = null;
      _drawPoint2 = null;
      _bboxParam = null;
      _radiusParam = null;
      _response = null;
      _resultSeries = [];
      _resultPoints = [];
      _selectedRowIndex = -1;
    });
  }

  // ---------------------------------------------------------------------------
  // Query config dialog
  // ---------------------------------------------------------------------------

  void _showQueryConfigDialog() {
    // Local state for dialog
    var localFrom = _fromDate;
    var localTo = _toDate;
    final localSelected = Set<String>.from(_selectedPaths);
    var localContext = _context;
    var localAggregation = _aggregation;
    var localSmoothing = _smoothing;
    var localSmaWindow = _smaWindow;
    var localEmaAlpha = _emaAlpha;
    var contextFilter = '';
    var lookupOtherVessels = _context != 'vessels.self';

    // Will be set once StatefulBuilder is built
    void Function(void Function())? dialogSetState;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            // Capture for async context fetch; kick off on first build only if enabled
            if (dialogSetState == null) {
              dialogSetState = setDialogState;
              if (lookupOtherVessels) {
                _fetchAvailableContexts(localFrom, localTo,
                    dialogSetState: setDialogState);
              }
            }
            dialogSetState = setDialogState;

            // Re-fetch contexts when dates change
            void onDatesChanged() {
              if (!lookupOtherVessels) return;
              // Reset context if it was a vessel-specific one that may
              // not exist in the new date range
              if (localContext != 'vessels.self') {
                localContext = 'vessels.self';
              }
              _fetchAvailableContexts(localFrom, localTo,
                  dialogSetState: setDialogState);
            }

            return AlertDialog(
              title: const Text('Query Configuration'),
              content: SizedBox(
                width: math.min(MediaQuery.of(ctx).size.width * 0.9, 480),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // -- Date range --
                      const Text('Date Range',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: Text(_fmtDate(localFrom),
                                  style: const TextStyle(fontSize: 12)),
                              onPressed: () async {
                                final d = await showDatePicker(
                                  context: ctx,
                                  initialDate: localFrom,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now(),
                                );
                                if (d != null) {
                                  setDialogState(() {
                                    localFrom = d;
                                    onDatesChanged();
                                  });
                                }
                              },
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('to'),
                          ),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: Text(_fmtDate(localTo),
                                  style: const TextStyle(fontSize: 12)),
                              onPressed: () async {
                                final d = await showDatePicker(
                                  context: ctx,
                                  initialDate: localTo,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now(),
                                );
                                if (d != null) {
                                  setDialogState(() {
                                    localTo = d;
                                    onDatesChanged();
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // -- Context --
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          lookupOtherVessels
                              ? 'Vessel: ${_contextDisplayName(localContext)}'
                              : 'Look up other vessels',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        value: lookupOtherVessels,
                        onChanged: (v) {
                          setDialogState(() {
                            lookupOtherVessels = v ?? false;
                            if (lookupOtherVessels) {
                              _fetchAvailableContexts(localFrom, localTo,
                                  dialogSetState: setDialogState);
                            } else {
                              localContext = 'vessels.self';
                            }
                          });
                        },
                      ),
                      if (lookupOtherVessels) ...[
                        if (_contextsLoading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                                SizedBox(width: 8),
                                Text('Loading vessels in area…',
                                    style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          )
                        else ...[
                          TextField(
                            decoration: const InputDecoration(
                              hintText: 'Filter MMSI…',
                              isDense: true,
                              prefixIcon: Icon(Icons.search, size: 18),
                            ),
                            onChanged: (v) =>
                                setDialogState(() => contextFilter = v),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: 120,
                            child: () {
                              final favService =
                                  context.read<AISFavoritesService>();
                              final favs = favService.favorites;
                              final favMMSIs =
                                  favs.map((f) => f.mmsi).toSet();

                              final nonSelf = _availableContexts
                                  .where((c) => c != 'vessels.self')
                                  .toList();

                              // Sort: favorites first, then the rest
                              final favContexts = nonSelf
                                  .where((c) {
                                    final m = _extractMMSI(c);
                                    return m != null && favMMSIs.contains(m);
                                  })
                                  .toList();
                              final otherContexts = nonSelf
                                  .where((c) => !favContexts.contains(c))
                                  .toList();
                              final allContexts = [
                                ...favContexts,
                                ...otherContexts,
                              ];

                              final filtered = contextFilter.isEmpty
                                  ? allContexts
                                  : allContexts.where((c) {
                                      final label =
                                          _contextDisplayName(c, favs)
                                              .toLowerCase();
                                      final raw = c.toLowerCase();
                                      final q = contextFilter.toLowerCase();
                                      return label.contains(q) ||
                                          raw.contains(q);
                                    }).toList();
                              if (filtered.isEmpty) {
                                return const Center(
                                    child: Text('No vessels found in area',
                                        style: TextStyle(fontSize: 11)));
                              }
                              return RadioGroup<String>(
                                groupValue: localContext,
                                onChanged: (v) {
                                  if (v != null) {
                                    setDialogState(() => localContext = v);
                                  }
                                },
                                child: ListView.builder(
                                  itemCount: filtered.length,
                                  itemBuilder: (_, i) {
                                    final c = filtered[i];
                                    return RadioListTile<String>(
                                      dense: true,
                                      value: c,
                                      title: Text(
                                          _contextDisplayName(c, favs),
                                          style:
                                              const TextStyle(fontSize: 12)),
                                    );
                                  },
                                ),
                              );
                            }(),
                          ),
                        ],
                      ],
                      const SizedBox(height: 12),

                      // -- Path selection --
                      Text(
                        'Paths (${localSelected.length}/3)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      // Selected path chips
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: localSelected.map((p) => Tooltip(
                          message: p,
                          child: Chip(
                            label: Text(p.split('.').last,
                                style: const TextStyle(fontSize: 11)),
                            deleteIcon: const Icon(Icons.close, size: 14),
                            onDeleted: () =>
                                setDialogState(() => localSelected.remove(p)),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        )).toList(),
                      ),
                      const SizedBox(height: 4),
                      if (localSelected.length < 3)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.add, size: 16),
                          label: Text(
                            _pathsLoading ? 'Loading paths...' : 'Add Path',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed: _pathsLoading
                              ? null
                              : () async {
                                  final result =
                                      await _showHistoricalPathPicker(
                                          ctx, localSelected);
                                  if (result != null) {
                                    setDialogState(
                                        () => localSelected.add(result));
                                  }
                                },
                        ),
                      const SizedBox(height: 12),

                      // -- Aggregation --
                      const Text('Aggregation',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      DropdownButton<String>(
                        value: localAggregation,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                              value: 'average', child: Text('Average')),
                          DropdownMenuItem(value: 'min', child: Text('Min')),
                          DropdownMenuItem(value: 'max', child: Text('Max')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setDialogState(() => localAggregation = v);
                          }
                        },
                      ),
                      const SizedBox(height: 12),

                      // -- Smoothing --
                      const Text('Smoothing',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      DropdownButton<String>(
                        value: localSmoothing,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'none', child: Text('None')),
                          DropdownMenuItem(value: 'sma', child: Text('SMA')),
                          DropdownMenuItem(value: 'ema', child: Text('EMA')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setDialogState(() => localSmoothing = v);
                          }
                        },
                      ),
                      if (localSmoothing == 'sma') ...[
                        const SizedBox(height: 4),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Window size',
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                          controller: TextEditingController(
                              text: localSmaWindow.toString()),
                          onChanged: (v) {
                            final parsed = int.tryParse(v);
                            if (parsed != null && parsed > 0) {
                              localSmaWindow = parsed;
                            }
                          },
                        ),
                      ],
                      if (localSmoothing == 'ema') ...[
                        const SizedBox(height: 4),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Alpha (0-1)',
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          controller: TextEditingController(
                              text: localEmaAlpha.toString()),
                          onChanged: (v) {
                            final parsed = double.tryParse(v);
                            if (parsed != null && parsed > 0 && parsed <= 1) {
                              localEmaAlpha = parsed;
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() => _state = ExplorerState.idle);
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: localSelected.isEmpty
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          setState(() {
                            _context = localContext;
                            _fromDate = localFrom;
                            _toDate = localTo;
                            _selectedPaths
                              ..clear()
                              ..addAll(localSelected);
                            _aggregation = localAggregation;
                            _smoothing = localSmoothing;
                            _smaWindow = localSmaWindow;
                            _emaAlpha = localEmaAlpha;
                          });
                          _executeQuery();
                        },
                  child: const Text('Query'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Historical path picker (full-screen bottom sheet)
  // ---------------------------------------------------------------------------

  Future<String?> _showHistoricalPathPicker(
      BuildContext ctx, Set<String> alreadySelected) {
    return showModalBottomSheet<String>(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        var searchQuery = '';
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) {
            return StatefulBuilder(
              builder: (_, setSheetState) {
                final filtered = _availablePaths.where((p) {
                  if (searchQuery.isEmpty) return true;
                  return p.toLowerCase().contains(searchQuery.toLowerCase());
                }).toList();

                return Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
                  ),
                  child: Column(
                  children: [
                    // Drag handle
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Container(
                        width: 32,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(sheetCtx)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Title
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Select Path',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(sheetCtx),
                          ),
                        ],
                      ),
                    ),
                    // Search field
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Filter paths...',
                          prefixIcon: Icon(Icons.search, size: 20),
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) =>
                            setSheetState(() => searchQuery = v),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Path count
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${filtered.length} paths',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(sheetCtx)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Path list
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final path = filtered[i];
                          final isSelected = alreadySelected.contains(path);
                          return ListTile(
                            dense: true,
                            title: Text(path,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isSelected
                                      ? Theme.of(sheetCtx)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.4)
                                      : null,
                                )),
                            trailing: isSelected
                                ? Icon(Icons.check,
                                    size: 18,
                                    color: Theme.of(sheetCtx)
                                        .colorScheme
                                        .primary)
                                : null,
                            onTap: isSelected
                                ? null
                                : () => Navigator.pop(sheetCtx, path),
                          );
                        },
                      ),
                    ),
                  ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin

    final hasResults =
        _state == ExplorerState.results && _resultSeries.isNotEmpty;

    final mapStack = Stack(
      children: [
        _buildMap(),
        // Drawing instruction overlay
        if (_state == ExplorerState.drawingBbox ||
            _state == ExplorerState.drawingRadius)
          _buildDrawingInstructions(),
        // Loading overlay
        if (_state == ExplorerState.loading) _buildLoadingOverlay(),
        // Dragging area overlay
        if (_isDraggingArea || _draggingHandleIndex != null)
          _buildDraggingOverlay(),
        // No-position message
        if (_vesselPosition == null && _state == ExplorerState.idle)
          _buildNoPositionOverlay(),
        // Top-right controls
        _buildOverlayControls(),
        // Legend overlay at bottom-left
        if (_state == ExplorerState.results && _resultSeries.isNotEmpty)
          _buildLegend(),
      ],
    );

    final isWide = MediaQuery.of(context).size.width >= 600;

    if (hasResults && isWide) {
      // Landscape: summary bar on top, then map left | panel right
      return Column(
        children: [
          if (_state == ExplorerState.results) _buildSummaryBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: mapStack),
                const SizedBox(width: 4),
                Expanded(flex: 2, child: _buildBottomPanel()),
              ],
            ),
          ),
        ],
      );
    }

    // Portrait / no results: stacked layout
    return Column(
      children: [
        if (_state == ExplorerState.results) _buildSummaryBar(),
        if (hasResults) ...[
          Expanded(child: mapStack),
          Expanded(child: _buildBottomPanel()),
        ] else
          Expanded(child: mapStack),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Map
  // ---------------------------------------------------------------------------

  Widget _buildMap() {
    final canDrag = _state == ExplorerState.queryConfig ||
        _state == ExplorerState.results;

    final isDragging = _isDraggingArea || _draggingHandleIndex != null;

    return Stack(
      children: [
        // Wrap in IgnorePointer during drag to suppress map pan/fling
        // without changing MapOptions (which would deactivate the widget).
        IgnorePointer(
          ignoring: isDragging,
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _mapCenter,
              initialZoom: 12,
              minZoom: 3,
              maxZoom: 18,
              onLongPress: _state == ExplorerState.idle
                  ? (_, _) {
                      if (!mounted) return;
                      setState(() => _state = ExplorerState.modeSelect);
                      _showModeSelectSheet();
                    }
                  : null,
              onTap: _onMapTap,
            ),
      children: [
        // Base map
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.zennora.signalk',
        ),
        // OpenSeaMap overlay
        if (_showSeaMap)
          TileLayer(
            urlTemplate:
                'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.zennora.signalk',
          ),
        // Bbox rectangle
        if (_drawPoint1 != null &&
            _drawPoint2 != null &&
            (_state == ExplorerState.drawingBbox ||
                _state == ExplorerState.queryConfig ||
                _state == ExplorerState.loading ||
                _state == ExplorerState.results) &&
            _bboxParam != null)
          PolygonLayer(
            polygons: [
              Polygon(
                points: _bboxCorners(_drawPoint1!, _drawPoint2!),
                color: Colors.deepPurple.withValues(alpha: 0.1),
                borderColor: Colors.deepPurple,
                borderStrokeWidth: 2,
              ),
            ],
          ),
        // Radius circle
        if (_drawPoint1 != null &&
            _drawPoint2 != null &&
            (_state == ExplorerState.drawingRadius ||
                _state == ExplorerState.queryConfig ||
                _state == ExplorerState.loading ||
                _state == ExplorerState.results) &&
            _radiusParam != null)
          CircleLayer(
            circles: [
              CircleMarker(
                point: _drawPoint1!,
                radius: const Distance()
                    .as(LengthUnit.Meter, _drawPoint1!, _drawPoint2!),
                useRadiusInMeter: true,
                color: Colors.deepPurple.withValues(alpha: 0.1),
                borderColor: Colors.deepPurple,
                borderStrokeWidth: 2,
              ),
            ],
          ),
        // Result track polyline
        if (_state == ExplorerState.results && _resultPoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _resultPoints.map((p) => p.position).toList(),
                color: Colors.blue.withValues(alpha: 0.5),
                strokeWidth: 2,
              ),
            ],
          ),
        // Result data point markers (color-coded by active legend series)
        if (_state == ExplorerState.results && _resultPoints.isNotEmpty)
          Builder(builder: (context) {
            final valueRange = _activeValueRange();
            // Sort so selected point is last (renders on top)
            final sortedPoints = List<_ResultPoint>.from(_resultPoints)
              ..sort((a, b) => a.index == _selectedRowIndex ? 1 : b.index == _selectedRowIndex ? -1 : 0);
            return MarkerLayer(
            markers: sortedPoints.where((pt) {
              // Only show markers for visible legend indices
              if (_visibleLegendIndices.isEmpty) return false;
              // Hide points with no data for the active path
              final activePath = _activeLegendIndex < _resultSeries.length
                  ? _resultSeries[_activeLegendIndex].path
                  : _resultSeries.isNotEmpty ? _resultSeries.first.path : null;
              if (activePath != null && pt.values[activePath] == null) return false;
              return true;
            }).map((pt) {
              final isSelected = pt.index == _selectedRowIndex;
              final activeSeries =
                  _activeLegendIndex < _resultSeries.length
                      ? _resultSeries[_activeLegendIndex]
                      : _resultSeries.isNotEmpty ? _resultSeries.first : null;
              final color = _legendColor(_activeLegendIndex);
              final activePath = activeSeries?.path;
              final category = activePath != null
                  ? widget.signalKService.metadataStore.get(activePath)?.category
                  : null;
              final isAngle = category == 'angle' || category == 'direction';
              final rawSiValue = activePath != null
                  ? pt.values[activePath]
                  : null;

              const double minSize = 12.0;
              const double maxSize = 28.0;
              double baseSize = minSize;
              if (valueRange != null && rawSiValue != null) {
                final (lo, hi) = valueRange;
                final span = hi - lo;
                if (span > 0) {
                  final t = ((rawSiValue - lo) / span).clamp(0.0, 1.0);
                  baseSize = minSize + t * (maxSize - minSize);
                } else {
                  baseSize = (minSize + maxSize) / 2;
                }
              }
              final size = baseSize;
              final markerColor = isSelected ? Colors.yellow : color;

              Widget markerChild;
              if (isAngle) {
                markerChild = Transform.rotate(
                  angle: rawSiValue ?? 0,
                  child: Icon(
                    Icons.navigation,
                    color: markerColor,
                    size: size,
                    shadows: [
                      Shadow(
                        color: isSelected ? Colors.black : Colors.black54,
                        blurRadius: isSelected ? 4.0 : 2.0,
                      ),
                    ],
                  ),
                );
              } else {
                markerChild = Container(
                  decoration: BoxDecoration(
                    color: markerColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.black : Colors.black54,
                      width: isSelected ? 3.0 : 1.5,
                    ),
                    boxShadow: isSelected
                        ? [BoxShadow(
                            color: Colors.yellow.withValues(alpha: 0.5),
                            blurRadius: 6,
                            spreadRadius: 2,
                          )]
                        : null,
                  ),
                );
              }

              return Marker(
                point: pt.position,
                width: size,
                height: size,
                child: GestureDetector(
                  onTap: () {
                    _selectPointByIndex(pt.index, panMap: false);
                    _tabController.animateTo(1); // Switch to Detail tab
                  },
                  child: markerChild,
                ),
              );
            }).toList(),
          );
          }),
        // Markers (vessel + drawing points)
        MarkerLayer(
          markers: [
            // Vessel position
            if (_vesselPosition != null)
              Marker(
                point: _vesselPosition!,
                width: 28,
                height: 28,
                child: const Icon(Icons.navigation,
                    color: Colors.green, size: 24),
              ),
            // Drawing point handles (diamond shape)
            ..._buildHandleMarkers(),
          ],
        ),
      ],
    ),
        ), // IgnorePointer
        // Drag-to-move overlay (above the map, only when area is drawn)
        if (canDrag)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPressStart: _onAreaDragStart,
              onLongPressMoveUpdate: _onAreaDragUpdate,
              onLongPressEnd: _onAreaDragEnd,
              onLongPressCancel: _onAreaDragCancel,
            ),
          ),
      ],
    );
  }

  List<Marker> _buildHandleMarkers() {
    if (_drawPoint1 == null) return [];
    // During drawing, show only the points placed so far
    if (_state == ExplorerState.drawingBbox ||
        _state == ExplorerState.drawingRadius) {
      final markers = <Marker>[_diamondMarker(_drawPoint1!)];
      if (_drawPoint2 != null) markers.add(_diamondMarker(_drawPoint2!));
      return markers;
    }
    // In queryConfig/loading/results, show all handle positions
    if (_drawPoint2 == null) return [];
    return _handlePositions().map((p) => _diamondMarker(p)).toList();
  }

  Marker _diamondMarker(LatLng point) {
    return Marker(
      point: point,
      width: 32,
      height: 32,
      child: Center(
        child: Transform.rotate(
          angle: 0.785398,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.deepPurple,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ),
    );
  }

  List<LatLng> _bboxCorners(LatLng c1, LatLng c2) {
    return [
      LatLng(c1.latitude, c1.longitude),
      LatLng(c1.latitude, c2.longitude),
      LatLng(c2.latitude, c2.longitude),
      LatLng(c2.latitude, c1.longitude),
    ];
  }

  // ---------------------------------------------------------------------------
  // Map helpers
  // ---------------------------------------------------------------------------

  void _zoomToArea() {
    if (_drawPoint1 == null || _drawPoint2 == null) return;

    LatLngBounds bounds;
    if (_radiusParam != null) {
      // Radius mode: _drawPoint1 is center, _drawPoint2 is edge point.
      // Compute bounding box from center ± radius.
      final center = _drawPoint1!;
      final radiusM = const Distance()
          .as(LengthUnit.Meter, center, _drawPoint2!);
      // Approximate degree offsets for the radius
      final dLat = radiusM / 111320.0;
      final dLng = radiusM /
          (111320.0 * math.cos(center.latitude * math.pi / 180.0));
      bounds = LatLngBounds(
        LatLng(center.latitude - dLat, center.longitude - dLng),
        LatLng(center.latitude + dLat, center.longitude + dLng),
      );
    } else {
      // Bbox mode: two opposite corners
      bounds = LatLngBounds(
        LatLng(
          math.min(_drawPoint1!.latitude, _drawPoint2!.latitude),
          math.min(_drawPoint1!.longitude, _drawPoint2!.longitude),
        ),
        LatLng(
          math.max(_drawPoint1!.latitude, _drawPoint2!.latitude),
          math.max(_drawPoint1!.longitude, _drawPoint2!.longitude),
        ),
      );
    }
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(40)),
    );
  }

  /// Returns (min, max) for the active legend path across all result points.
  (double, double)? _activeValueRange() {
    if (_resultSeries.isEmpty || _resultPoints.isEmpty) return null;
    final series = _activeLegendIndex < _resultSeries.length
        ? _resultSeries[_activeLegendIndex]
        : _resultSeries.first;
    double? lo, hi;
    for (final pt in _resultPoints) {
      final v = pt.values[series.path];
      if (v == null || v.isNaN) continue;
      lo = lo == null ? v : math.min(lo, v);
      hi = hi == null ? v : math.max(hi, v);
    }
    if (lo == null || hi == null) return null;
    return (lo, hi);
  }

  // ---------------------------------------------------------------------------
  // Overlays
  // ---------------------------------------------------------------------------

  Widget _buildOverlayButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(6),
      elevation: 2,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Icon(icon, color: color ?? Colors.black87, size: 18),
        ),
      ),
    );
  }

  Widget _buildOverlayControls() {
    return Positioned(
      top: 8,
      right: 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Zoom in
          _buildOverlayButton(
            icon: Icons.add,
            onPressed: () => _mapController.move(
              _mapController.camera.center,
              _mapController.camera.zoom + 1,
            ),
          ),
          const SizedBox(height: 4),
          // Zoom out
          _buildOverlayButton(
            icon: Icons.remove,
            onPressed: () => _mapController.move(
              _mapController.camera.center,
              _mapController.camera.zoom - 1,
            ),
          ),
          const SizedBox(height: 4),
          // Zoom to area
          if (_drawPoint1 != null && _drawPoint2 != null)
            _buildOverlayButton(
              icon: Icons.fit_screen,
              onPressed: _zoomToArea,
            ),
          if (_drawPoint1 != null && _drawPoint2 != null)
            const SizedBox(height: 4),
          // Info button
          Material(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(6),
            elevation: 2,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: ToolInfoButton(
                  toolId: 'historical_data_explorer',
                  signalKService: widget.signalKService,
                  iconSize: 18,
                  iconColor: Colors.black87,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Homeport toggle
          if (_homeportPosition != null)
            _buildOverlayButton(
              icon: _centeredOnHomeport ? Icons.home : Icons.home_outlined,
              onPressed: () {
                setState(() => _centeredOnHomeport = !_centeredOnHomeport);
                _mapController.move(_mapCenter, _mapController.camera.zoom);
              },
            ),
          const SizedBox(height: 4),
          // Recenter on drawn area
          if (_areaCenter != null &&
              (_state == ExplorerState.results ||
               _state == ExplorerState.queryConfig))
            _buildOverlayButton(
              icon: Icons.center_focus_strong,
              onPressed: () {
                final center = _areaCenter;
                if (center != null) {
                  _mapController.move(center, _mapController.camera.zoom);
                }
              },
            ),
          const SizedBox(height: 4),
          // Save area
          if (_drawPoint1 != null &&
              _drawPoint2 != null &&
              (_state == ExplorerState.queryConfig ||
               _state == ExplorerState.results))
            _buildOverlayButton(
              icon: Icons.save_outlined,
              onPressed: _showSaveAreaDialog,
            ),
          const SizedBox(height: 4),
          // Share
          if (_state == ExplorerState.results &&
              _response != null &&
              _response!.data.isNotEmpty)
            _buildOverlayButton(
              icon: Icons.share,
              onPressed: _showShareFormatPicker,
            ),
          const SizedBox(height: 4),
          // Clear
          if (_state != ExplorerState.idle &&
              _state != ExplorerState.modeSelect)
            _buildOverlayButton(
              icon: Icons.clear,
              color: Colors.red,
              onPressed: _clearDrawing,
            ),
        ],
      ),
    );
  }

  Widget _buildDrawingInstructions() {
    final isRadius = _state == ExplorerState.drawingRadius;
    final tapNum = _drawPoint1 == null ? 1 : 2;
    String text;
    if (isRadius) {
      text = tapNum == 1
          ? 'Tap to place center point'
          : 'Tap to set radius edge';
    } else {
      text = tapNum == 1
          ? 'Tap to place first corner'
          : 'Tap to place second corner';
    }

    return Positioned(
      top: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    );
  }

  Widget _buildDraggingOverlay() {
    final text = _draggingHandleIndex != null
        ? 'Resizing area\u2026 release to re-query'
        : 'Dragging area\u2026 release to re-query';
    return Positioned(
      top: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.deepPurple.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.3),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Querying historical data...',
                style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildNoPositionOverlay() {
    return Positioned(
      bottom: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text('No vessel position — map centered at 0,0',
            style: TextStyle(color: Colors.white, fontSize: 11)),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Results: Top summary bar
  // ---------------------------------------------------------------------------

  Widget _buildSummaryBar() {
    final range = _response?.range;
    final areaType = _bboxParam != null ? 'Bbox' : 'Radius';
    final pathCount = _resultSeries.length;
    final contextLabel = _contextDisplayName(_context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Query info
            Text(
              '$contextLabel | $areaType | '
              '${range != null ? _fmtDate(range.from) : '?'} - '
              '${range != null ? _fmtDate(range.to) : '?'} | '
              '$pathCount path${pathCount != 1 ? 's' : ''}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 12),
            // Per-path aggregate stats
            ..._resultSeries.map((s) {
              final metadata =
                  widget.signalKService.metadataStore.get(s.path);
              final symbol = metadata?.symbol ?? '';
              final minFmt = s.minValue?.toStringAsFixed(1) ?? '--';
              final maxFmt = s.maxValue?.toStringAsFixed(1) ?? '--';
              final avg = s.points.isEmpty
                  ? '--'
                  : (s.points.map((p) => p.value).reduce((a, b) => a + b) /
                          s.points.length)
                      .toStringAsFixed(1);
              final shortPath = s.path.split('.').last;
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  '$shortPath: $minFmt/$avg/$maxFmt $symbol',
                  style: const TextStyle(fontSize: 10),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Legend
  // ---------------------------------------------------------------------------

  Widget _buildLegend() {
    return Positioned(
      bottom: 8,
      left: 8,
      right: 56, // Leave room for overlay controls on the right
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_resultSeries.length, (i) {
              final s = _resultSeries[i];
              final isActive = i == _activeLegendIndex;
              final isVisible = _visibleLegendIndices.contains(i);
              final metadata =
                  widget.signalKService.metadataStore.get(s.path);
              final shortName = s.path.split('.').last;
              final color = isVisible
                  ? _legendColor(i)
                  : Colors.grey;
              final category = metadata?.category;

              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isVisible && !isActive) {
                        // Make this the active legend
                        _activeLegendIndex = i;
                      } else if (isVisible && isActive) {
                        // Toggle off
                        _visibleLegendIndices.remove(i);
                        if (_activeLegendIndex == i &&
                            _visibleLegendIndices.isNotEmpty) {
                          _activeLegendIndex =
                              _visibleLegendIndices.first;
                        }
                      } else {
                        // Toggle on and make active
                        _visibleLegendIndices.add(i);
                        _activeLegendIndex = i;
                      }
                    });
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: isActive
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: isActive
                          ? Border.all(color: Colors.white54, width: 1)
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: _markerForCategory(
                              category, null, color, false, 14),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          shortName,
                          style: TextStyle(
                            color: isVisible ? Colors.white : Colors.grey,
                            fontSize: 10,
                            fontWeight:
                                isActive ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Color _legendColor(int index) {
    const colors = [
      Colors.blue,
      Colors.orange,
      Colors.green,
      Colors.purple,
      Colors.cyan,
    ];
    return colors[index % colors.length];
  }

  // ---------------------------------------------------------------------------
  // Category-aware marker icons
  // ---------------------------------------------------------------------------

  Widget _markerForCategory(
      String? category, double? rawSiValue, Color color, bool isSelected,
      double size) {
    final borderColor = isSelected ? Colors.white : Colors.black54;
    final borderWidth = isSelected ? 3.0 : 1.0;

    switch (category) {
      case 'angle':
      case 'direction':
        // Chevron rotated by the raw SI value (radians)
        return Transform.rotate(
          angle: rawSiValue ?? 0,
          child: Icon(Icons.navigation, color: color, size: size),
        );
      case 'speed':
        return Icon(Icons.speed, color: color, size: size);
      case 'distance':
      case 'length':
        return Icon(Icons.straighten, color: color, size: size);
      case 'depth':
        return Icon(Icons.vertical_align_bottom, color: color, size: size);
      case 'temperature':
        return Icon(Icons.thermostat, color: color, size: size);
      case 'pressure':
        return Icon(Icons.compress, color: color, size: size);
      default:
        // Filled circle (original behavior)
        return Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: borderWidth),
          ),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Results: Bottom tabbed panel
  // ---------------------------------------------------------------------------

  Widget _buildBottomPanel() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelStyle: const TextStyle(fontSize: 11),
            tabs: const [
              Tab(text: 'All Points'),
              Tab(text: 'Detail'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAllPointsTab(),
                _buildDetailTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllPointsTab() {
    if (_resultPoints.isEmpty) {
      return const Center(
          child: Text('No data points', style: TextStyle(fontSize: 11)));
    }

    return ListView.builder(
      itemCount: _resultPoints.length,
      padding: const EdgeInsets.symmetric(vertical: 2),
      itemBuilder: (ctx, i) {
        final pt = _resultPoints[i];
        final isSelected = pt.index == _selectedRowIndex;

        return InkWell(
          onTap: () {
            _selectPointByIndex(pt.index);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: isSelected
                ? Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.15)
                : null,
            child: Row(
              children: [
                // Timestamp
                SizedBox(
                  width: 80,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _fmtDate(pt.timestamp),
                        style: const TextStyle(
                            fontSize: 9, color: Colors.grey),
                      ),
                      Text(
                        _fmtAmPm(pt.timestamp),
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                // Position
                SizedBox(
                  width: 90,
                  child: Text(
                    _fmtDDM(pt.position.latitude, pt.position.longitude),
                    style: const TextStyle(fontSize: 9),
                  ),
                ),
                // Values
                Expanded(
                  child: Row(
                    children: _resultSeries.map((s) {
                      final rawVal = pt.values[s.path];
                      final metadata =
                          widget.signalKService.metadataStore.get(s.path);
                      final category = metadata?.category;
                      final display = rawVal != null
                          ? (metadata?.format(rawVal, decimals: 1) ??
                              rawVal.toStringAsFixed(1))
                          : '--';
                      return Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 10,
                              height: 10,
                              child: _markerForCategory(
                                  category, rawVal, Colors.grey, false, 10),
                            ),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                display,
                                style: const TextStyle(fontSize: 10),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailTab() {
    if (_selectedRowIndex < 0) {
      return const Center(
        child: Text(
          'Tap a point on the map or list',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
      );
    }

    final pt = _resultPoints.firstWhere(
      (p) => p.index == _selectedRowIndex,
      orElse: () => _resultPoints.first,
    );

    // Build sparkline cards explicitly
    final sparklineCards = <Widget>[];
    for (var idx = 0; idx < _resultSeries.length; idx++) {
      final s = _resultSeries[idx];
      final markerIndex = s.points.indexWhere(
          (p) => p.timestamp == pt.timestamp);
      final seriesColor = _legendColor(idx);
      final metadata =
          widget.signalKService.metadataStore.get(s.path);
      final rawVal = pt.values[s.path];
      final display = rawVal != null
          ? (metadata?.format(rawVal, decimals: 1) ??
              rawVal.toStringAsFixed(1))
          : null;
      sparklineCards.add(
        GestureDetector(
          onDoubleTap: () => _showExpandedSparkline(s, seriesColor, metadata),
          child: Container(
          key: ValueKey('sparkline_$idx'),
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: seriesColor.withValues(alpha: 0.08),
            border: Border.all(color: seriesColor.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(s.path.split('.').last,
                      style: TextStyle(fontSize: 9, color: seriesColor)),
                  const Spacer(),
                  Text(
                    '${s.minValue?.toStringAsFixed(1) ?? '--'} – ${s.maxValue?.toStringAsFixed(1) ?? '--'}'
                    ' ${metadata?.symbol ?? ''}',
                    style: TextStyle(fontSize: 8, color: seriesColor.withValues(alpha: 0.6)),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 50,
                width: double.infinity,
                child: CustomPaint(
                  painter: _SparklinePainter(
                    values: s.points.map((p) => p.value).toList(),
                    markerIndex: markerIndex >= 0 ? markerIndex : null,
                    markerLabel: display,
                    lineColor: seriesColor,
                  ),
                ),
              ),
              if (s.points.length >= 2)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _fmtCompact(s.points.first.timestamp),
                        style: TextStyle(fontSize: 7, color: seriesColor.withValues(alpha: 0.5)),
                      ),
                      Text(
                        _fmtCompact(s.points.last.timestamp),
                        style: TextStyle(fontSize: 7, color: seriesColor.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              // Date
              Text(
                _fmtDate(pt.timestamp),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              // AM/PM time
              Text(
                _fmtAmPm(pt.timestamp),
                style: const TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 2),
              // Position in DDM
              Text(
                _fmtDDM(pt.position.latitude, pt.position.longitude),
                style: const TextStyle(fontSize: 11),
              ),
              const Divider(height: 8),
              // Sparkline cards
              ...sparklineCards,
            ],
          ),
        ),
        if (_resultPoints.length > 1) _buildPlaybackControls(),
      ],
    );
  }

  Widget _buildPlaybackControls() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Slider
          SizedBox(
            height: 24,
            child: Slider(
              value: _playbackListIndex.toDouble().clamp(0, (_resultPoints.length - 1).toDouble()),
              min: 0,
              max: (_resultPoints.length - 1).toDouble(),
              onChanged: (v) {
                final idx = v.round();
                _playbackListIndex = idx;
                _selectPointByIndex(_resultPoints[idx].index);
              },
            ),
          ),
          // Transport buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Jump -10
              IconButton(
                icon: const Icon(Icons.skip_previous),
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Jump back 10',
                onPressed: () => _jumpPlayback(-10),
              ),
              const SizedBox(width: 4),
              // Reverse
              IconButton(
                icon: const Icon(Icons.fast_rewind),
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Reverse',
                onPressed: () {
                  if (_isPlaying && _playbackDirection == -1) {
                    _stopPlayback();
                  } else {
                    _startPlayback(direction: -1);
                  }
                },
              ),
              const SizedBox(width: 4),
              // Play/Pause
              IconButton(
                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                iconSize: 22,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: _isPlaying ? 'Pause' : 'Play',
                onPressed: () {
                  if (_isPlaying) {
                    _stopPlayback();
                  } else {
                    _startPlayback(direction: _playbackDirection);
                  }
                },
              ),
              const SizedBox(width: 4),
              // Forward
              IconButton(
                icon: const Icon(Icons.fast_forward),
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Forward',
                onPressed: () {
                  if (_isPlaying && _playbackDirection == 1) {
                    _stopPlayback();
                  } else {
                    _startPlayback(direction: 1);
                  }
                },
              ),
              const SizedBox(width: 4),
              // Jump +10
              IconButton(
                icon: const Icon(Icons.skip_next),
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Jump forward 10',
                onPressed: () => _jumpPlayback(10),
              ),
              const SizedBox(width: 8),
              // Speed popup
              PopupMenuButton<double>(
                initialValue: _playbackSpeed,
                onSelected: _setPlaybackSpeed,
                tooltip: 'Playback speed',
                padding: EdgeInsets.zero,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_playbackSpeed == _playbackSpeed.roundToDouble() ? _playbackSpeed.toInt() : _playbackSpeed}x',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                itemBuilder: (_) => _speedOptions
                    .map((s) => PopupMenuItem(
                          value: s,
                          child: Text('${s == s.roundToDouble() ? s.toInt() : s}x'),
                        ))
                    .toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Expanded sparkline modal
  // ---------------------------------------------------------------------------

  void _showExpandedSparkline(
    hist.ChartDataSeries series,
    Color seriesColor,
    PathMetadata? metadata,
  ) {
    final values = series.points.map((p) => p.value).toList();
    final minLabel = metadata?.format(series.minValue?.toDouble() ?? 0, decimals: 1)
        ?? series.minValue?.toStringAsFixed(1) ?? '--';
    final maxLabel = metadata?.format(series.maxValue?.toDouble() ?? 0, decimals: 1)
        ?? series.maxValue?.toStringAsFixed(1) ?? '--';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Text(
                      series.label ?? series.path.split('.').last,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: seriesColor,
                      ),
                    ),
                  ),
                  Text(
                    '$minLabel – $maxLabel',
                    style: TextStyle(fontSize: 11, color: seriesColor.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                series.path,
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              // Chart
              SizedBox(
                height: 200,
                width: double.infinity,
                child: CustomPaint(
                  painter: _SparklinePainter(
                    values: values,
                    lineColor: seriesColor,
                  ),
                ),
              ),
              // Date range
              if (series.points.length >= 2)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _fmtCompact(series.points.first.timestamp),
                        style: TextStyle(fontSize: 9, color: seriesColor.withValues(alpha: 0.5)),
                      ),
                      Text(
                        '${series.points.length} points',
                        style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                      ),
                      Text(
                        _fmtCompact(series.points.last.timestamp),
                        style: TextStyle(fontSize: 9, color: seriesColor.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Export & Share
  // ---------------------------------------------------------------------------

  void _showShareFormatPicker() {
    showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('CSV'),
              subtitle: const Text('Comma-separated values'),
              onTap: () => Navigator.pop(ctx, 'csv'),
            ),
            ListTile(
              leading: const Icon(Icons.map),
              title: const Text('GeoJSON'),
              subtitle: const Text('Geographic features for GIS tools'),
              onTap: () => Navigator.pop(ctx, 'geojson'),
            ),
            ListTile(
              leading: const Icon(Icons.place),
              title: const Text('KML'),
              subtitle: const Text('Google Earth / Google Maps'),
              onTap: () => Navigator.pop(ctx, 'kml'),
            ),
          ],
        ),
      ),
    ).then((format) {
      if (format == 'csv') {
        _shareAsCsv();
      } else if (format == 'geojson') {
        _shareAsGeoJson();
      } else if (format == 'kml') {
        _shareAsKml();
      }
    });
  }

  /// Build column-index lookup for export iteration.
  Map<String, int> _buildExportColIndices() {
    final colIndices = <String, int>{};
    for (final s in _resultSeries) {
      final idx = _response!.values.indexWhere((v) {
        if (v.path != s.path) return false;
        if (s.smoothing == null) return v.smoothing == null;
        return v.smoothing == s.smoothing;
      });
      if (idx != -1) colIndices[s.path] = idx;
    }
    return colIndices;
  }

  /// Build metadata comment lines for export headers.
  List<String> _buildExportMetadataLines() {
    final lines = <String>[];
    lines.add('# context: $_context');
    if (_bboxParam != null) {
      lines.add('# area: bbox $_bboxParam');
    } else if (_radiusParam != null) {
      lines.add('# area: radius $_radiusParam');
    }
    lines.add('# aggregation: $_aggregation');
    if (_smoothing != 'none') {
      final param = _smoothing == 'sma'
          ? '$_smoothing($_smaWindow)'
          : '$_smoothing($_emaAlpha)';
      lines.add('# smoothing: $param');
    }
    if (_response != null) {
      lines.add('# from: ${_response!.range.from.toUtc().toIso8601String()}');
      lines.add('# to: ${_response!.range.to.toUtc().toIso8601String()}');
    }
    return lines;
  }

  Future<void> _shareAsCsv() async {
    if (_response == null || _response!.data.isEmpty) return;

    try {
      final colIndices = _buildExportColIndices();
      final posIdx = _response!.values
          .indexWhere((v) => v.path == 'navigation.position');

      final pathHeaders = _resultSeries.map((s) {
        final metadata = widget.signalKService.metadataStore.get(s.path);
        final symbol = metadata?.symbol;
        return symbol != null ? '${s.path} ($symbol)' : s.path;
      }).toList();

      final metaLines = _buildExportMetadataLines();
      final header = ['timestamp', 'latitude', 'longitude', ...pathHeaders]
          .join(',');

      final rows = _response!.data.map((row) {
        // Position
        String lat = '';
        String lon = '';
        if (posIdx != -1 && posIdx < row.values.length) {
          final latLng = _parsePosition(row.values[posIdx]);
          if (latLng != null) {
            lat = latLng.latitude.toStringAsFixed(6);
            lon = latLng.longitude.toStringAsFixed(6);
          }
        }

        // Path values
        final vals = _resultSeries.map((s) {
          final idx = colIndices[s.path];
          if (idx == null || idx >= row.values.length) return '';
          final raw = row.values[idx];
          if (raw is! num) return '';
          final metadata = widget.signalKService.metadataStore.get(s.path);
          return (metadata?.convert(raw.toDouble()) ?? raw).toStringAsFixed(4);
        }).toList();

        return [
          row.timestamp.toUtc().toIso8601String(),
          lat,
          lon,
          ...vals,
        ].join(',');
      }).toList();

      final csv = [...metaLines, header, ...rows].join('\n');

      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/explorer_data.csv');
      await file.writeAsString(csv);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Historical Data Export',
        ),
      );
    } catch (e) {
      _showSnack('Failed to share: $e');
    }
  }

  Future<void> _shareAsGeoJson() async {
    if (_response == null || _response!.data.isEmpty) return;

    try {
      final colIndices = _buildExportColIndices();
      final posIdx = _response!.values
          .indexWhere((v) => v.path == 'navigation.position');

      final features = <Map<String, dynamic>>[];

      // Search area feature
      if (_drawPoint1 != null) {
        if (_bboxParam != null && _drawPoint2 != null) {
          final p1 = _drawPoint1!;
          final p2 = _drawPoint2!;
          features.add({
            'type': 'Feature',
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [
                  [p1.longitude, p1.latitude],
                  [p2.longitude, p1.latitude],
                  [p2.longitude, p2.latitude],
                  [p1.longitude, p2.latitude],
                  [p1.longitude, p1.latitude],
                ]
              ],
            },
            'properties': {
              'role': 'searchArea',
              'areaType': 'bbox',
            },
          });
        } else if (_radiusParam != null) {
          final parts = _radiusParam!.split(',');
          final radiusM =
              parts.length >= 3 ? double.tryParse(parts[2]) : null;
          features.add({
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [
                _drawPoint1!.longitude,
                _drawPoint1!.latitude,
              ],
            },
            'properties': {
              'role': 'searchArea',
              'areaType': 'radius',
              // ignore: use_null_aware_elements
              if (radiusM != null) 'radiusMeters': radiusM,
            },
          });
        }
      }

      // Data features from full response
      for (final row in _response!.data) {
        final properties = <String, dynamic>{
          'timestamp': row.timestamp.toUtc().toIso8601String(),
        };

        for (final s in _resultSeries) {
          final idx = colIndices[s.path];
          if (idx == null || idx >= row.values.length) continue;
          final raw = row.values[idx];
          if (raw is! num) continue;
          final metadata = widget.signalKService.metadataStore.get(s.path);
          final displayVal =
              metadata?.convert(raw.toDouble()) ?? raw.toDouble();
          final symbol = metadata?.symbol;
          properties[s.path] = displayVal;
          if (symbol != null) {
            properties['${s.path}_unit'] = symbol;
          }
        }

        // Position (may be null → null geometry, valid per GeoJSON spec)
        Map<String, dynamic>? geometry;
        if (posIdx != -1 && posIdx < row.values.length) {
          final latLng = _parsePosition(row.values[posIdx]);
          if (latLng != null) {
            geometry = {
              'type': 'Point',
              'coordinates': [latLng.longitude, latLng.latitude],
            };
          }
        }

        features.add({
          'type': 'Feature',
          'geometry': geometry,
          'properties': properties,
        });
      }

      // Top-level metadata
      final metaProps = <String, dynamic>{
        'context': _context,
        if (_bboxParam != null) 'areaType': 'bbox',
        if (_bboxParam != null) 'bbox': _bboxParam,
        if (_radiusParam != null) 'areaType': 'radius',
        if (_radiusParam != null) 'radius': _radiusParam,
        'aggregation': _aggregation,
        if (_smoothing != 'none') 'smoothing': _smoothing,
        'from': _response!.range.from.toUtc().toIso8601String(),
        'to': _response!.range.to.toUtc().toIso8601String(),
      };

      final geojson = {
        'type': 'FeatureCollection',
        'properties': metaProps,
        'features': features,
      };

      final jsonStr = const JsonEncoder.withIndent('  ').convert(geojson);

      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/explorer_data.geojson');
      await file.writeAsString(jsonStr);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Historical Data Export',
        ),
      );
    } catch (e) {
      _showSnack('Failed to share: $e');
    }
  }

  Future<void> _shareAsKml() async {
    if (_response == null || _response!.data.isEmpty) return;

    try {
      final colIndices = _buildExportColIndices();
      final posIdx = _response!.values
          .indexWhere((v) => v.path == 'navigation.position');

      final buf = StringBuffer();
      buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
      buf.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
      buf.writeln('<Document>');
      buf.writeln('  <name>Historical Data Export</name>');

      // Document-level metadata
      final metaParts = <String>['Context: $_context'];
      if (_bboxParam != null) metaParts.add('Area: bbox $_bboxParam');
      if (_radiusParam != null) metaParts.add('Area: radius $_radiusParam');
      metaParts.add('Aggregation: $_aggregation');
      if (_smoothing != 'none') {
        final param = _smoothing == 'sma'
            ? '$_smoothing($_smaWindow)'
            : '$_smoothing($_emaAlpha)';
        metaParts.add('Smoothing: $param');
      }
      if (_response != null) {
        metaParts.add(
            'From: ${_response!.range.from.toUtc().toIso8601String()}');
        metaParts.add('To: ${_response!.range.to.toUtc().toIso8601String()}');
      }
      buf.writeln(
          '  <description>${_xmlEscape(metaParts.join('\n'))}</description>');

      // Search area style
      buf.writeln('  <Style id="searchArea">');
      buf.writeln('    <PolyStyle>');
      buf.writeln('      <color>4000ff00</color>');
      buf.writeln('    </PolyStyle>');
      buf.writeln('    <LineStyle>');
      buf.writeln('      <color>ff00ff00</color>');
      buf.writeln('      <width>2</width>');
      buf.writeln('    </LineStyle>');
      buf.writeln('  </Style>');

      // Search area placemark
      if (_drawPoint1 != null) {
        if (_bboxParam != null && _drawPoint2 != null) {
          final p1 = _drawPoint1!;
          final p2 = _drawPoint2!;
          buf.writeln('  <Placemark>');
          buf.writeln('    <name>Search Area</name>');
          buf.writeln('    <styleUrl>#searchArea</styleUrl>');
          buf.writeln('    <Polygon>');
          buf.writeln('      <outerBoundaryIs><LinearRing><coordinates>');
          buf.writeln(
              '        ${p1.longitude},${p1.latitude} ${p2.longitude},${p1.latitude} ${p2.longitude},${p2.latitude} ${p1.longitude},${p2.latitude} ${p1.longitude},${p1.latitude}');
          buf.writeln('      </coordinates></LinearRing></outerBoundaryIs>');
          buf.writeln('    </Polygon>');
          buf.writeln('  </Placemark>');
        } else if (_radiusParam != null) {
          final parts = _radiusParam!.split(',');
          final radiusM =
              parts.length >= 3 ? parts[2] : 'unknown';
          buf.writeln('  <Placemark>');
          buf.writeln('    <name>Search Area Center</name>');
          buf.writeln(
              '    <description>Radius: ${_xmlEscape(radiusM)} meters</description>');
          buf.writeln(
              '    <Point><coordinates>${_drawPoint1!.longitude},${_drawPoint1!.latitude}</coordinates></Point>');
          buf.writeln('  </Placemark>');
        }
      }

      // Data placemarks from full response
      for (final row in _response!.data) {
        // Position required for KML placemarks
        LatLng? latLng;
        if (posIdx != -1 && posIdx < row.values.length) {
          latLng = _parsePosition(row.values[posIdx]);
        }
        if (latLng == null) continue; // KML requires coordinates

        final ts = row.timestamp.toUtc().toIso8601String();

        buf.writeln('  <Placemark>');
        buf.writeln('    <name>$ts</name>');
        buf.writeln('    <TimeStamp><when>$ts</when></TimeStamp>');
        buf.writeln(
            '    <Point><coordinates>${latLng.longitude},${latLng.latitude}</coordinates></Point>');

        // ExtendedData with all values
        buf.writeln('    <ExtendedData>');
        for (final s in _resultSeries) {
          final idx = colIndices[s.path];
          if (idx == null || idx >= row.values.length) continue;
          final raw = row.values[idx];
          if (raw is! num) continue;
          final metadata = widget.signalKService.metadataStore.get(s.path);
          final display = metadata?.format(raw.toDouble(), decimals: 2) ??
              raw.toStringAsFixed(2);
          buf.writeln(
              '      <Data name="${_xmlEscape(s.path)}"><value>${_xmlEscape(display)}</value></Data>');
        }
        buf.writeln('    </ExtendedData>');
        buf.writeln('  </Placemark>');
      }

      buf.writeln('</Document>');
      buf.writeln('</kml>');

      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/explorer_data.kml');
      await file.writeAsString(buf.toString());

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Historical Data Export',
        ),
      );
    } catch (e) {
      _showSnack('Failed to share: $e');
    }
  }

  String _xmlEscape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _fmtCompact(DateTime d) {
    final mon = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final hour = d.hour;
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final ampm = hour < 12 ? 'AM' : 'PM';
    return '$mon/$day $displayHour:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtAmPm(DateTime d) {
    final hour = d.hour;
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final ampm = hour < 12 ? 'AM' : 'PM';
    return '$displayHour:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  /// Format lat/lon in Degrees Decimal Minutes (DDM) format.
  String _fmtDDM(double lat, double lon) {
    String toDDM(double value, String pos, String neg) {
      final dir = value >= 0 ? pos : neg;
      final abs = value.abs();
      final deg = abs.truncate();
      final min = (abs - deg) * 60;
      return '$deg°${min.toStringAsFixed(3)}\'$dir';
    }
    return '${toDDM(lat, 'N', 'S')} ${toDDM(lon, 'E', 'W')}';
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }
}

// ---------------------------------------------------------------------------
// Data class for a plotted result point
// ---------------------------------------------------------------------------

class _ResultPoint {
  final int index;         // Row index in the original response
  final LatLng position;
  final DateTime timestamp;
  final Map<String, double> values; // path → raw SI value

  const _ResultPoint({
    required this.index,
    required this.position,
    required this.timestamp,
    required this.values,
  });
}

// ---------------------------------------------------------------------------
// Sparkline widget with marker for Detail tab
// ---------------------------------------------------------------------------

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final int? markerIndex;
  final String? markerLabel;
  final Color lineColor;

  _SparklinePainter({
    required this.values,
    this.markerIndex,
    this.markerLabel,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;

    // Filter out NaN/Infinity for min/max calculation
    final finiteValues = values.where((v) => v.isFinite).toList();
    if (finiteValues.length < 2) return;

    final minVal = finiteValues.reduce(math.min);
    final maxVal = finiteValues.reduce(math.max);
    final range = maxVal - minVal;
    final topPad = 12.0; // space for marker label
    final drawHeight = size.height - topPad;

    double normalize(double v) {
      if (!v.isFinite) return topPad + drawHeight / 2;
      if (range == 0) return drawHeight / 2 + topPad;
      return topPad + drawHeight - ((v - minVal) / range) * drawHeight;
    }

    final stepX = size.width / (values.length - 1);

    // Draw line
    final linePaint = Paint()
      ..color = lineColor.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final linePath = ui.Path();
    linePath.moveTo(0, normalize(values[0]));
    for (var i = 1; i < values.length; i++) {
      linePath.lineTo(i * stepX, normalize(values[i]));
    }
    canvas.drawPath(linePath, linePaint);

    // Draw marker
    if (markerIndex != null && markerIndex! >= 0 && markerIndex! < values.length) {
      final mx = markerIndex! * stepX;
      final my = normalize(values[markerIndex!]);

      // Vertical line
      final vLinePaint = Paint()
        ..color = lineColor.withValues(alpha: 0.3)
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(mx, topPad), Offset(mx, size.height), vLinePaint);

      // Dot
      final dotPaint = Paint()
        ..color = lineColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(mx, my), 3.5, dotPaint);

      // Label
      if (markerLabel != null) {
        final tp = TextPainter(
          text: TextSpan(
            text: markerLabel!,
            style: TextStyle(fontSize: 9, color: lineColor, fontWeight: FontWeight.w600),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        // Position label above dot, clamped to canvas bounds
        var labelX = mx - tp.width / 2;
        if (labelX < 0) labelX = 0;
        if (labelX + tp.width > size.width) labelX = size.width - tp.width;
        tp.paint(canvas, Offset(labelX, 0));
      }
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.markerIndex != markerIndex ||
      old.markerLabel != markerLabel ||
      old.lineColor != lineColor ||
      old.values.length != values.length;
}
