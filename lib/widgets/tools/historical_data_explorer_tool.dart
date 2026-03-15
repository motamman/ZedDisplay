import 'dart:convert';
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
import '../../models/tool_config.dart';
import '../../models/tool_definition.dart';
import '../../models/historical_data.dart' as hist;
import '../../services/ais_favorites_service.dart';
import '../../services/signalk_service.dart';
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

  // Legend
  int _activeLegendIndex = 0;
  Set<int> _visibleLegendIndices = {0};

  // Bottom panel tabs
  late TabController _tabController;

  // Service
  HistoricalDataService? _historyService;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    widget.signalKService.addListener(_onSignalKChanged);
    _updateVesselPosition();
    _initService();
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
    _tabController.dispose();
    widget.signalKService.removeListener(_onSignalKChanged);
    super.dispose();
  }

  void _onSignalKChanged() {
    if (!mounted) return;
    _updateVesselPosition();
    // Re-init service on reconnect (new auth token, etc.)
    if (_historyService == null && widget.signalKService.isConnected) {
      _initService();
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
        // Boolean / notification / state paths don't aggregate
        if (p.contains('.notification')) return false;
        if (p.endsWith('.state')) return false;
        // Also check live cache — if value is not a num, skip
        final dp = widget.signalKService.getValue(p);
        if (dp != null && dp.value is! num) return false;
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

  /// Color for a data point based on its value relative to the series range.
  Color _pointColor(double? value, hist.ChartDataSeries series) {
    if (value == null || series.minValue == null || series.maxValue == null) {
      return Colors.blue;
    }
    final range = series.maxValue! - series.minValue!;
    if (range == 0) return Colors.blue;
    final t = ((value - series.minValue!) / range).clamp(0.0, 1.0);
    // Green (low) → Yellow (mid) → Red (high)
    return Color.lerp(
      Color.lerp(Colors.green, Colors.yellow, t * 2)!,
      Color.lerp(Colors.yellow, Colors.red, (t - 0.5).clamp(0.0, 1.0) * 2)!,
      t,
    )!;
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
    var pathFilter = '';
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
            final filteredPaths = pathFilter.isEmpty
                ? _availablePaths
                : _availablePaths
                    .where((p) =>
                        p.toLowerCase().contains(pathFilter.toLowerCase()))
                    .toList();

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
                        'Paths (${localSelected.length}/5)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        decoration: const InputDecoration(
                          hintText: 'Filter paths...',
                          isDense: true,
                          prefixIcon: Icon(Icons.search, size: 18),
                        ),
                        onChanged: (v) => setDialogState(() => pathFilter = v),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 160,
                        child: _pathsLoading
                            ? const Center(
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : filteredPaths.isEmpty
                                ? const Center(child: Text('No paths found'))
                                : ListView.builder(
                                    itemCount: filteredPaths.length,
                                    itemBuilder: (_, i) {
                                      final p = filteredPaths[i];
                                      final checked = localSelected.contains(p);
                                      return CheckboxListTile(
                                        dense: true,
                                        value: checked,
                                        title: Text(p,
                                            style:
                                                const TextStyle(fontSize: 12)),
                                        onChanged: (v) {
                                          setDialogState(() {
                                            if (v == true &&
                                                localSelected.length < 5) {
                                              localSelected.add(p);
                                            } else {
                                              localSelected.remove(p);
                                            }
                                          });
                                        },
                                      );
                                    },
                                  ),
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
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin

    return Column(
      children: [
        // Top summary bar (results only)
        if (_state == ExplorerState.results) _buildSummaryBar(),

        // Map
        Expanded(
          child: Stack(
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
          ),
        ),

        // Bottom tabbed panel (results only)
        if (_state == ExplorerState.results && _resultSeries.isNotEmpty)
          SizedBox(height: 160, child: _buildBottomPanel()),
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
          MarkerLayer(
            markers: _resultPoints.where((pt) {
              // Only show markers for visible legend indices
              if (_visibleLegendIndices.isEmpty) return false;
              return true;
            }).map((pt) {
              final isSelected = pt.index == _selectedRowIndex;
              final activeSeries =
                  _activeLegendIndex < _resultSeries.length
                      ? _resultSeries[_activeLegendIndex]
                      : _resultSeries.isNotEmpty ? _resultSeries.first : null;
              final activeValue = activeSeries != null
                  ? pt.values[activeSeries.path]
                  : null;
              final color = activeSeries != null
                  ? _pointColor(activeValue, activeSeries)
                  : Colors.blue;
              final activePath = activeSeries?.path;
              final category = activePath != null
                  ? widget.signalKService.metadataStore.get(activePath)?.category
                  : null;
              final size = isSelected ? 22.0 : 16.0;
              return Marker(
                point: pt.position,
                width: size,
                height: size,
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selectedRowIndex = pt.index);
                    _tabController.animateTo(1); // Switch to Detail tab
                  },
                  child: _markerForCategory(
                    category, activeValue, color, isSelected, size),
                ),
              );
            }).toList(),
          ),
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
          // Share
          if (_state == ExplorerState.results && _resultPoints.isNotEmpty)
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
            setState(() => _selectedRowIndex = pt.index);
            try {
              _mapController.move(pt.position, _mapController.camera.zoom);
            } catch (_) {}
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
                  width: 60,
                  child: Text(
                    _fmtTimestamp(pt.timestamp),
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w500),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          Text(
            '${_fmtDate(pt.timestamp)} ${_fmtTimestamp(pt.timestamp)}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          // Position in DDM
          Text(
            _fmtDDM(pt.position.latitude, pt.position.longitude),
            style: const TextStyle(fontSize: 11),
          ),
          const Divider(height: 8),
          // Per-path values
          ..._resultSeries.map((s) {
            final rawVal = pt.values[s.path];
            final metadata =
                widget.signalKService.metadataStore.get(s.path);
            final category = metadata?.category;
            final display = rawVal != null
                ? (metadata?.format(rawVal, decimals: 2) ??
                    rawVal.toStringAsFixed(2))
                : '--';
            final rawStr =
                rawVal != null ? rawVal.toStringAsFixed(4) : '--';

            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: _markerForCategory(
                        category, rawVal, Colors.grey, false, 14),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.path,
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey)),
                        Text(
                          '$display  (SI: $rawStr)',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
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

  Future<void> _shareAsCsv() async {
    if (_resultPoints.isEmpty) return;

    try {
      final pathHeaders = _resultSeries.map((s) {
        final metadata = widget.signalKService.metadataStore.get(s.path);
        final symbol = metadata?.symbol;
        return symbol != null ? '${s.path} ($symbol)' : s.path;
      }).toList();

      final header = ['timestamp', 'latitude', 'longitude', ...pathHeaders]
          .join(',');

      final rows = _resultPoints.map((pt) {
        final vals = _resultSeries.map((s) {
          final rawVal = pt.values[s.path];
          if (rawVal == null) return '';
          final metadata = widget.signalKService.metadataStore.get(s.path);
          return (metadata?.convert(rawVal) ?? rawVal).toStringAsFixed(4);
        }).toList();

        return [
          pt.timestamp.toUtc().toIso8601String(),
          pt.position.latitude.toStringAsFixed(6),
          pt.position.longitude.toStringAsFixed(6),
          ...vals,
        ].join(',');
      }).toList();

      final csv = [header, ...rows].join('\n');

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
    if (_resultPoints.isEmpty) return;

    try {
      final features = _resultPoints.map((pt) {
        final properties = <String, dynamic>{
          'timestamp': pt.timestamp.toUtc().toIso8601String(),
        };
        for (final s in _resultSeries) {
          final rawVal = pt.values[s.path];
          if (rawVal == null) continue;
          final metadata = widget.signalKService.metadataStore.get(s.path);
          final displayVal = metadata?.convert(rawVal) ?? rawVal;
          final symbol = metadata?.symbol;
          properties[s.path] = displayVal;
          if (symbol != null) {
            properties['${s.path}_unit'] = symbol;
          }
        }
        return {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [
              pt.position.longitude,
              pt.position.latitude,
            ],
          },
          'properties': properties,
        };
      }).toList();

      final geojson = {
        'type': 'FeatureCollection',
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
    if (_resultPoints.isEmpty) return;

    try {
      final buf = StringBuffer();
      buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
      buf.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
      buf.writeln('<Document>');
      buf.writeln('  <name>Historical Data Export</name>');

      for (final pt in _resultPoints) {
        final ts = pt.timestamp.toUtc().toIso8601String();
        final lat = pt.position.latitude;
        final lon = pt.position.longitude;

        // Build description from path values
        final descParts = <String>[];
        for (final s in _resultSeries) {
          final rawVal = pt.values[s.path];
          if (rawVal == null) continue;
          final metadata = widget.signalKService.metadataStore.get(s.path);
          final display = metadata?.format(rawVal, decimals: 2) ??
              rawVal.toStringAsFixed(2);
          descParts.add('${s.path}: $display');
        }

        buf.writeln('  <Placemark>');
        buf.writeln('    <name>$ts</name>');
        if (descParts.isNotEmpty) {
          buf.writeln(
              '    <description>${_xmlEscape(descParts.join('\n'))}</description>');
        }
        buf.writeln('    <TimeStamp><when>$ts</when></TimeStamp>');
        buf.writeln('    <Point><coordinates>$lon,$lat</coordinates></Point>');
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

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtTimestamp(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

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
