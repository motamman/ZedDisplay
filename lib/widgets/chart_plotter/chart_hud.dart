import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import '../../models/path_metadata.dart';
import '../../models/zone_data.dart';
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
    // Self-update on every SignalK delta — the same way the ZonesMixin gauges
    // do — so every HUD value (depth especially) refreshes in real time
    // rather than only when the chart plotter rebuilds (which is gated on
    // vessel motion). Only this HUD subtree repaints; the map keeps its own
    // throttle, so there's no added map-render cost.
    return ListenableBuilder(
      listenable: signalKService,
      builder: (context, _) =>
          hudStyle == 'visual' ? _buildVisualHUD() : _buildTextHUD(),
    );
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
    // Depth danger colour + alarm bands come from the server-defined zones
    // (MetadataStore), evaluated against the RAW SI value — not hardcoded
    // thresholds. No zones defined → neutral colour, no invented levels.
    final dptZone = _activeZone(dptRaw, dptMeta?.zones);
    final dptColor = dptZone != null
        ? _zoneFillColor(ZoneState.fromString(dptZone.state))
        : Colors.cyan;
    final dptBands = _zoneBands(dptMeta, maxValue: 30);

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

    // XTE — keep the raw SI value for the bar geometry; the MetadataStore
    // handles the display label only (see _miniXteBar).
    final xteRaw = _numValue(_path(_dsXte));
    final xteMeta = store.get(_path(_dsXte)) ?? store.getByCategory('distance');
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
                      color: dptColor,
                      zoneBands: dptBands,
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
                  Flexible(child: _miniXteBar(xteRaw ?? 0, xteFmt, dtwRaw)),
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

  /// The most-severe zone (from MetadataStore) whose SI range contains the
  /// raw SI [value]. Null when there are no zones or none match — callers
  /// fall back to a neutral colour rather than inventing thresholds.
  static PathZone? _activeZone(double? value, List<PathZone>? zones) {
    if (value == null || zones == null || zones.isEmpty) return null;
    PathZone? best;
    var bestRank = -1;
    for (final z in zones) {
      final aboveLower = z.lower == null || value >= z.lower!;
      final belowUpper = z.upper == null || value <= z.upper!;
      if (aboveLower && belowUpper) {
        final rank = _zoneSeverity(z.state);
        if (rank > bestRank) {
          bestRank = rank;
          best = z;
        }
      }
    }
    return best;
  }

  static int _zoneSeverity(String state) {
    switch (ZoneState.fromString(state)) {
      case ZoneState.emergency:
        return 5;
      case ZoneState.alarm:
        return 4;
      case ZoneState.warn:
        return 3;
      case ZoneState.alert:
        return 2;
      case ZoneState.nominal:
        return 1;
      case ZoneState.normal:
        return 0;
    }
  }

  /// Solid colour for the value-fill arc, by zone state.
  static Color _zoneFillColor(ZoneState state) {
    switch (state) {
      case ZoneState.emergency:
        return Colors.red.shade900;
      case ZoneState.alarm:
        return Colors.red;
      case ZoneState.warn:
        return Colors.orange;
      case ZoneState.alert:
        return Colors.yellow.shade700;
      case ZoneState.nominal:
        return Colors.blue;
      case ZoneState.normal:
        return Colors.cyan;
    }
  }

  /// Translucent band colour, by zone state. Mirrors the radial/linear
  /// gauges' `_getZoneColor` so the HUD reads consistently with them.
  static Color _zoneBandColor(ZoneState state) {
    switch (state) {
      case ZoneState.nominal:
        return Colors.blue.withValues(alpha: 0.5);
      case ZoneState.alert:
        return Colors.yellow.shade600.withValues(alpha: 0.6);
      case ZoneState.warn:
        return Colors.orange.withValues(alpha: 0.6);
      case ZoneState.alarm:
        return Colors.red.withValues(alpha: 0.6);
      case ZoneState.emergency:
        return Colors.red.shade900.withValues(alpha: 0.6);
      case ZoneState.normal:
        return Colors.grey.withValues(alpha: 0.5);
    }
  }

  /// Convert a path's SI zones into display-unit gauge bands, clamped later
  /// to the axis. Open-ended bounds map to 0 / [maxValue]. Empty when the
  /// path has no zones.
  static List<({double start, double end, Color color})> _zoneBands(
    PathMetadata? meta, {
    required double maxValue,
  }) {
    final zones = meta?.zones;
    if (meta == null || zones == null) return const [];
    final bands = <({double start, double end, Color color})>[];
    for (final z in zones) {
      final lo = z.lower != null ? (meta.convert(z.lower!) ?? z.lower!) : 0.0;
      final hi =
          z.upper != null ? (meta.convert(z.upper!) ?? z.upper!) : maxValue;
      if (hi <= lo) continue;
      bands.add((
        start: lo,
        end: hi,
        color: _zoneBandColor(ZoneState.fromString(z.state)),
      ));
    }
    return bands;
  }

  static Widget _miniArcGauge({
    required String label,
    required double value,
    required double maxValue,
    required String formattedValue,
    required Color color,
    List<({double start, double end, Color color})>? zoneBands,
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
            // Server-defined alarm zones (MetadataStore), drawn as bands so
            // the warning levels are the same source the gauges use.
            if (zoneBands != null)
              for (final b in zoneBands)
                GaugeRange(
                  startValue: b.start.clamp(0.0, maxValue),
                  endValue: b.end.clamp(0.0, maxValue),
                  color: b.color,
                  startWidth: 8, endWidth: 8,
                ),
            // Value fill last so it paints over the bands up to current value.
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

  /// Cross-track-error bar. All geometry and colour thresholds are computed
  /// in raw SI metres: XTE and DTW are the same physical quantity, so the bar
  /// is "XTE as a fraction of distance-to-waypoint" and is unit-independent.
  /// Only the marker label ([xteFmt]) uses the MetadataStore-formatted value.
  static Widget _miniXteBar(double xteMeters, String xteFmt, double? dtwMeters) {
    final dtw = (dtwMeters ?? 1000).abs();
    final maxXte = (dtw * 0.25).clamp(10.0, 500.0);
    final clamped = xteMeters.clamp(-maxXte, maxXte);
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
