import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/tool_config.dart';
import '../../models/tool_definition.dart';
import '../../models/historical_data.dart' as hist;
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
    with AutomaticKeepAliveClientMixin {
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

  // Vessel position
  LatLng? _vesselPosition;
  bool _centeredOnHomeport = false;

  // Available paths (cached)
  List<String> _availablePaths = [];
  bool _pathsLoading = false;

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

  // Service
  HistoricalDataService? _historyService;

  @override
  void initState() {
    super.initState();
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
      bbox: _bboxParam,
      radius: _radiusParam,
    );
  }

  // ---------------------------------------------------------------------------
  // Map interaction
  // ---------------------------------------------------------------------------

  void _onMapLongPress(TapPosition tapPosition, LatLng point) {
    if (_state != ExplorerState.idle) return;
    setState(() => _state = ExplorerState.modeSelect);
    _showModeSelectSheet();
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
    var localAggregation = _aggregation;
    var localSmoothing = _smoothing;
    var localSmaWindow = _smaWindow;
    var localEmaAlpha = _emaAlpha;
    var pathFilter = '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filteredPaths = pathFilter.isEmpty
                ? _availablePaths
                : _availablePaths
                    .where((p) =>
                        p.toLowerCase().contains(pathFilter.toLowerCase()))
                    .toList();

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
                                  setDialogState(() => localFrom = d);
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
                                  setDialogState(() => localTo = d);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
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
              // No-position message
              if (_vesselPosition == null && _state == ExplorerState.idle)
                _buildNoPositionOverlay(),
              // Top-right controls
              _buildOverlayControls(),
            ],
          ),
        ),

        // Bottom detail table (results only)
        if (_state == ExplorerState.results && _resultSeries.isNotEmpty)
          SizedBox(height: 120, child: _buildDetailTable()),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Map
  // ---------------------------------------------------------------------------

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _mapCenter,
        initialZoom: 12,
        minZoom: 3,
        maxZoom: 18,
        onLongPress: _onMapLongPress,
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
                color: Colors.blue.withValues(alpha: 0.15),
                borderColor: Colors.blue,
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
                color: Colors.blue.withValues(alpha: 0.15),
                borderColor: Colors.blue,
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
        // Result data point markers (color-coded by first series value)
        if (_state == ExplorerState.results && _resultPoints.isNotEmpty)
          MarkerLayer(
            markers: _resultPoints.map((pt) {
              final isSelected = pt.index == _selectedRowIndex;
              final firstSeries =
                  _resultSeries.isNotEmpty ? _resultSeries.first : null;
              final firstValue = firstSeries != null
                  ? pt.values[firstSeries.path]
                  : null;
              final color = firstSeries != null
                  ? _pointColor(firstValue, firstSeries)
                  : Colors.blue;
              return Marker(
                point: pt.position,
                width: isSelected ? 18 : 12,
                height: isSelected ? 18 : 12,
                child: GestureDetector(
                  onTap: () => setState(() => _selectedRowIndex = pt.index),
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.black54,
                        width: isSelected ? 3 : 1,
                      ),
                    ),
                  ),
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
            // Drawing point markers
            if (_drawPoint1 != null)
              Marker(
                point: _drawPoint1!,
                width: 20,
                height: 20,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            if (_drawPoint2 != null &&
                (_state == ExplorerState.drawingBbox ||
                    _state == ExplorerState.drawingRadius ||
                    _state == ExplorerState.queryConfig ||
                    _state == ExplorerState.loading ||
                    _state == ExplorerState.results))
              Marker(
                point: _drawPoint2!,
                width: 20,
                height: 20,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ],
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

  Widget _buildOverlayControls() {
    return Positioned(
      top: 8,
      right: 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Info button
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: ToolInfoButton(
              toolId: 'historical_data_explorer',
              signalKService: widget.signalKService,
              iconSize: 20,
              iconColor: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          // Homeport toggle
          if (_homeportPosition != null)
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(
                  _centeredOnHomeport ? Icons.home : Icons.home_outlined,
                  color: Colors.white,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () {
                  setState(() => _centeredOnHomeport = !_centeredOnHomeport);
                  _mapController.move(_mapCenter, _mapController.camera.zoom);
                },
              ),
            ),
          const SizedBox(height: 4),
          // Clear button (when drawing or results exist)
          if (_state != ExplorerState.idle &&
              _state != ExplorerState.modeSelect)
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.clear, color: Colors.white, size: 20),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: _clearDrawing,
              ),
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
              '$areaType | '
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
  // Results: Bottom detail table
  // ---------------------------------------------------------------------------

  Widget _buildDetailTable() {
    if (_resultPoints.isEmpty) return const SizedBox.shrink();

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            columnSpacing: 16,
            dataRowMinHeight: 24,
            dataRowMaxHeight: 28,
            headingRowHeight: 30,
            columns: [
              const DataColumn(
                  label: Text('Time', style: TextStyle(fontSize: 11))),
              const DataColumn(
                  label: Text('Position', style: TextStyle(fontSize: 11))),
              ..._resultSeries.map((s) {
                final metadata =
                    widget.signalKService.metadataStore.get(s.path);
                final symbol = metadata?.symbol;
                final short = s.path.split('.').last;
                final header = symbol != null ? '$short ($symbol)' : short;
                return DataColumn(
                    label: Text(header, style: const TextStyle(fontSize: 11)));
              }),
            ],
            rows: _resultPoints.map((pt) {
              final isSelected = pt.index == _selectedRowIndex;
              return DataRow(
                selected: isSelected,
                color: isSelected
                    ? WidgetStateProperty.all(Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.15))
                    : null,
                onSelectChanged: (_) {
                  setState(() => _selectedRowIndex = pt.index);
                  // Pan map to selected point
                  try {
                    _mapController.move(
                        pt.position, _mapController.camera.zoom);
                  } catch (_) {}
                },
                cells: [
                  DataCell(Text(_fmtTimestamp(pt.timestamp),
                      style: const TextStyle(fontSize: 10))),
                  DataCell(Text(
                      '${pt.position.latitude.toStringAsFixed(4)}, '
                      '${pt.position.longitude.toStringAsFixed(4)}',
                      style: const TextStyle(fontSize: 10))),
                  ..._resultSeries.map((s) {
                    final rawVal = pt.values[s.path];
                    if (rawVal == null) {
                      return const DataCell(
                          Text('--', style: TextStyle(fontSize: 10)));
                    }
                    final metadata =
                        widget.signalKService.metadataStore.get(s.path);
                    final display =
                        metadata?.format(rawVal, decimals: 2) ??
                            rawVal.toStringAsFixed(2);
                    return DataCell(
                        Text(display, style: const TextStyle(fontSize: 10)));
                  }),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtTimestamp(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

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
