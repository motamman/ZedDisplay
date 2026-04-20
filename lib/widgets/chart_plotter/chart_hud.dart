import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import '../../models/path_metadata.dart';
import '../../services/signalk_service.dart';
import '../compass_gauge.dart';

/// Chart plotter HUD — text and visual modes.
///
/// Displays SOG, COG, depth, DTW, BRG, XTE with optional route controls.
/// All values are converted via MetadataStore (single source of truth).
class ChartPlotterHUD extends StatelessWidget {
  final SignalKService signalKService;
  final String hudStyle; // 'text', 'visual', 'off'
  final String hudPosition; // 'top', 'bottom'
  final List<String> paths; // [position, heading, cog, sog, depth, bearing, xte, dtw, ...]
  final bool hasActiveRoute;
  final bool canAdvance; // routePointIndex + 1 < routePointTotal
  final VoidCallback? onAdvanceWaypoint;
  final VoidCallback? onFastForward;

  const ChartPlotterHUD({
    super.key,
    required this.signalKService,
    required this.hudStyle,
    required this.hudPosition,
    required this.paths,
    this.hasActiveRoute = false,
    this.canAdvance = false,
    this.onAdvanceWaypoint,
    this.onFastForward,
  });

  // DataSource path indices — must match chart_plotter_tool.dart order
  static const _dsSog = 3;
  static const _dsCog = 2;
  static const _dsDepth = 4;
  static const _dsBearing = 5;
  static const _dsXte = 6;
  static const _dsDtw = 7;

  String _path(int index) => index < paths.length ? paths[index] : '';

  double? _numValue(String path) {
    final data = signalKService.getValue(path);
    return data?.value is num ? (data!.value as num).toDouble() : null;
  }

  /// Format the SignalK value at [path] for HUD display. Walks MetadataStore
  /// with optional [fallbackPath] and [fallbackCategory] before delegating to
  /// [MetadataFormatExtension.formatOrRaw].
  String _formatValue(
    String path, {
    int decimals = 1,
    String? fallbackCategory,
    String? fallbackPath,
  }) {
    final data = signalKService.getValue(path);
    if (data?.value == null || data!.value is! num) return '--';
    final rawValue = (data.value as num).toDouble();
    final store = signalKService.metadataStore;
    final metadata = store.get(path) ??
        (fallbackPath != null ? store.get(fallbackPath) : null) ??
        (fallbackCategory != null ? store.getByCategory(fallbackCategory) : null);
    return metadata.formatOrRaw(rawValue, decimals: decimals);
  }

  @override
  Widget build(BuildContext context) {
    if (hudStyle == 'off') return const SizedBox.shrink();
    if (hudStyle == 'visual') return _buildVisualHUD();
    return _buildTextHUD();
  }

  Widget _buildTextHUD() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: hudPosition == 'bottom' ? 0 : null,
      top: hudPosition == 'top' ? 0 : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _hudItem('SOG', _formatValue(_path(_dsSog), fallbackCategory: 'speed')),
            _hudItem('COG', _formatValue(_path(_dsCog), decimals: 0, fallbackCategory: 'angle')),
            _hudItem('DPT', _formatValue(_path(_dsDepth), decimals: 1, fallbackCategory: 'depth')),
            _hudItem('DTW', _formatValue(_path(_dsDtw), decimals: 1, fallbackCategory: 'distance')),
            _hudItem('BRG', _formatValue(_path(_dsBearing), decimals: 0, fallbackPath: _path(_dsCog), fallbackCategory: 'angle')),
            _hudItem('XTE', _formatValue(_path(_dsXte), decimals: 1, fallbackCategory: 'distance')),
            if (canAdvance) ...[
              GestureDetector(
                onTap: onAdvanceWaypoint,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.skip_next, color: Colors.white70, size: 24),
                ),
              ),
              GestureDetector(
                onTap: onFastForward,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.fast_forward, color: Colors.white70, size: 24),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVisualHUD() {
    final store = signalKService.metadataStore;

    // SOG
    final sogRaw = _numValue(_path(_dsSog));
    final sogMeta = store.get(_path(_dsSog)) ?? store.getByCategory('speed');
    final sogVal = sogMeta?.convert(sogRaw ?? 0) ?? sogRaw ?? 0;
    final sogFmt = sogRaw != null ? (sogMeta?.format(sogRaw, decimals: 1) ?? sogRaw.toStringAsFixed(1)) : '--';

    // DPT
    final dptRaw = _numValue(_path(_dsDepth));
    final dptMeta = store.get(_path(_dsDepth)) ?? store.getByCategory('depth');
    final dptVal = dptMeta?.convert(dptRaw ?? 0) ?? dptRaw ?? 0;
    final dptFmt = dptRaw != null ? (dptMeta?.format(dptRaw, decimals: 1) ?? dptRaw.toStringAsFixed(1)) : '--';

    // COG
    final cogRaw = _numValue(_path(_dsCog));
    final cogMeta = store.get(_path(_dsCog)) ?? store.getByCategory('angle');
    final cogDeg = cogMeta?.convert(cogRaw ?? 0) ?? cogRaw ?? 0;
    final cogFmt = cogRaw != null ? (cogMeta?.format(cogRaw, decimals: 0) ?? cogRaw.toStringAsFixed(2)) : '--';

    // BRG
    final brgRaw = _numValue(_path(_dsBearing));
    final brgMeta = store.get(_path(_dsBearing)) ?? cogMeta;
    final brgDeg = brgMeta?.convert(brgRaw ?? 0) ?? brgRaw ?? 0;

    // DTW (raw SI meters for XTE scaling)
    final dtwRaw = _numValue(_path(_dsDtw));

    // XTE
    final xteRaw = _numValue(_path(_dsXte));
    final xteMeta = store.get(_path(_dsXte)) ?? store.getByCategory('distance');
    final xteVal = xteMeta?.convert(xteRaw ?? 0) ?? xteRaw ?? 0;
    final xteFmt = xteRaw != null ? (xteMeta?.format(xteRaw, decimals: 1) ?? xteRaw.toStringAsFixed(1)) : '--';

    return Positioned(
      left: 0,
      right: 0,
      bottom: hudPosition == 'bottom' ? 0 : null,
      top: hudPosition == 'top' ? 0 : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.75)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top row: SOG gauge, compass, DPT gauge
            SizedBox(
              height: 135,
              child: Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: _miniArcGauge(
                      label: 'SOG',
                      value: sogVal.toDouble(),
                      maxValue: 20,
                      formattedValue: sogFmt,
                      color: Colors.cyan,
                    ),
                  ),
                  Expanded(
                    child: _miniCompass(
                      cogDeg: cogDeg.toDouble(),
                      brgDeg: brgRaw != null ? brgDeg.toDouble() : null,
                      cogFmt: cogFmt,
                      brgFmt: brgRaw != null ? '${brgDeg.toStringAsFixed(0)}°' : null,
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: _miniArcGauge(
                      label: 'Depth',
                      value: dptVal.toDouble(),
                      maxValue: 30,
                      formattedValue: dptFmt,
                      color: _depthColor(dptVal.toDouble()),
                      zones: dptMeta?.zones,
                    ),
                  ),
                ],
              ),
            ),
            // Bottom row: DTW, XTE, route controls
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _hudItem('DTW', _formatValue(_path(_dsDtw), decimals: 1, fallbackCategory: 'distance')),
                  Flexible(child: _miniXteBar(xteVal.toDouble(), xteFmt, xteMeta?.symbol ?? 'm', dtwRaw)),
                  if (canAdvance) ...[
                    GestureDetector(
                      onTap: onAdvanceWaypoint,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.skip_next, color: Colors.white70, size: 20),
                      ),
                    ),
                    GestureDetector(
                      onTap: onFastForward,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.fast_forward, color: Colors.white70, size: 20),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _depthColor(double depth) {
    if (depth < 2) return Colors.red;
    if (depth < 5) return Colors.orange;
    return Colors.cyan;
  }

  static Widget _miniArcGauge({
    required String label,
    required double value,
    required double maxValue,
    required String formattedValue,
    required Color color,
    List<dynamic>? zones,
  }) {
    final clamped = value.clamp(0.0, maxValue);
    return SfRadialGauge(
      axes: [
        RadialAxis(
          minimum: 0,
          maximum: maxValue,
          startAngle: 135,
          endAngle: 45,
          showAxisLine: false,
          showLabels: false,
          majorTickStyle: MajorTickStyle(
            length: 4, thickness: 1,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          minorTicksPerInterval: 0,
          interval: maxValue / 5,
          ranges: [
            GaugeRange(
              startValue: 0, endValue: maxValue,
              color: Colors.white.withValues(alpha: 0.1),
              startWidth: 8, endWidth: 8,
            ),
            GaugeRange(
              startValue: 0, endValue: clamped,
              color: color,
              startWidth: 8, endWidth: 8,
            ),
          ],
          annotations: [
            GaugeAnnotation(
              widget: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9)),
                  Text(formattedValue,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
              angle: 90,
              positionFactor: 0.0,
            ),
          ],
        ),
      ],
    );
  }

  static Widget _miniCompass({
    required double cogDeg,
    double? brgDeg,
    required String cogFmt,
    String? brgFmt,
  }) {
    return CompassGauge(
      heading: cogDeg,
      label: 'COG',
      formattedValue: cogFmt,
      primaryColor: Colors.cyan,
      compassStyle: CompassStyle.marine,
      showTickLabels: false,
      showValue: true,
      additionalHeadings: brgDeg != null ? [brgDeg] : null,
      additionalLabels: brgDeg != null ? ['BRG'] : null,
      additionalColors: brgDeg != null ? [Colors.green] : null,
      additionalFormattedValues: brgFmt != null ? [brgFmt] : null,
    );
  }

  static Widget _miniXteBar(double xteValue, String xteFmt, String unit, double? dtwMeters) {
    final dtw = (dtwMeters ?? 1000).abs();
    final maxXte = (dtw * 0.25).clamp(10.0, 500.0);
    final clamped = xteValue.clamp(-maxXte, maxXte);
    final barColor = clamped.abs() < dtw * 0.05
        ? Colors.green
        : (clamped.abs() < dtw * 0.15 ? Colors.orange : Colors.red);
    final startVal = clamped >= 0 ? 0.0 : clamped;
    final endVal = clamped >= 0 ? clamped : 0.0;

    return SizedBox(
      height: 30,
      child: SfLinearGauge(
        minimum: -maxXte,
        maximum: maxXte,
        showTicks: false,
        showLabels: false,
        axisTrackStyle: LinearAxisTrackStyle(
          thickness: 12,
          edgeStyle: LinearEdgeStyle.bothCurve,
          color: Colors.white.withValues(alpha: 0.1),
        ),
        ranges: [
          LinearGaugeRange(
            startValue: startVal,
            endValue: endVal,
            color: barColor,
            startWidth: 12,
            endWidth: 12,
            position: LinearElementPosition.cross,
          ),
        ],
        markerPointers: [
          LinearWidgetPointer(
            value: 0,
            position: LinearElementPosition.cross,
            child: Container(width: 2, height: 16, color: Colors.white.withValues(alpha: 0.5)),
          ),
          LinearWidgetPointer(
            value: clamped,
            position: LinearElementPosition.outside,
            offset: 2,
            child: Text(xteFmt,
              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  static Widget _hudItem(String label, String value) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
      Text(value,
        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
    ],
  );
}
