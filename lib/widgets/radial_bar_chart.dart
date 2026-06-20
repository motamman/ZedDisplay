import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

/// A single concentric ring in a [RadialBarChart].
class RadialBarSegment {
  final String label;
  final double value; // display units (already converted from SI)
  final double minValue;
  final double maxValue;
  final String valueText; // pre-formatted, e.g. "33 gallon" or "96%"
  final Color color;
  final bool hasData; // false when the path is stale/missing

  const RadialBarSegment({
    required this.label,
    required this.value,
    required this.minValue,
    required this.maxValue,
    required this.valueText,
    required this.color,
    this.hasData = true,
  });
}

/// A radial bar chart that displays multiple data sources as concentric rings.
///
/// Built on [SfRadialGauge] (a gauge, not a chart) so rings have consistent
/// widths/gaps, values animate in place instead of flashing, and ticks/labels
/// are available — matching the polish of the other gauge widgets.
class RadialBarChart extends StatelessWidget {
  final List<RadialBarSegment> segments;
  final String? title;

  /// Show the value annotation at the top of each ring.
  final bool showValues;

  /// Show the legend (ring name + colour swatch) below the rings.
  final bool showLegend;

  /// Show tick marks and labels on the outermost ring.
  final bool showTicks;

  /// Number of major divisions when [showTicks] is enabled.
  final int divisions;

  /// Radius of the hollow centre, 0.0 (no hole) to ~0.8.
  final double innerRadius;

  /// Gap between rings, expressed in radius-factor units.
  final double gap;

  const RadialBarChart({
    super.key,
    required this.segments,
    this.title,
    this.showValues = true,
    this.showLegend = true,
    this.showTicks = false,
    this.divisions = 10,
    this.innerRadius = 0.35,
    this.gap = 0.04,
  });

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.donut_large, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('No data available'),
          ],
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor = Colors.grey.withValues(alpha: isDark ? 0.25 : 0.18);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null && title!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 12, right: 16, bottom: 4),
            child: Text(
              title!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
        Expanded(
          child: AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Only build the gauge once we have a real, finite size.
                // On the first layout pass (and during off-screen / edit-mode
                // transitions) this square can collapse to 0 or be handed an
                // unbounded constraint; syncfusion then paints its rings,
                // ticks and labels against a degenerate radius and throws
                // "RangeError (length): ... range is empty: 0" on every frame.
                // Skipping the build until the size is sane lets it rebuild
                // cleanly when a proper layout arrives (e.g. on leaving edit
                // mode), which is exactly when the crash clears.
                final side = constraints.biggest.shortestSide;
                if (!side.isFinite || side < 1.0) {
                  return const SizedBox.shrink();
                }
                return SfRadialGauge(
                  axes: _buildAxes(isDark, trackColor, side / 2),
                );
              },
            ),
          ),
        ),
        if (showLegend && segments.length > 1)
          _buildLegend(context, isDark),
      ],
    );
  }

  /// Font size for the numeric scale labels; shared by the label style and by
  /// the measurement that reserves outside-label space.
  static const double _labelFontSize = 9;

  /// Format a value the way the gauge prints axis labels (drop a trailing .0).
  String _labelText(double v) {
    final r = v.roundToDouble();
    return v == r ? r.toStringAsFixed(0) : v.toString();
  }

  /// Measure a label at the axis font so we can reserve exactly the radial
  /// space syncfusion consumes for an outside label.
  Size _measureLabel(String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: _labelFontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.size;
  }

  List<RadialAxis> _buildAxes(bool isDark, Color trackColor, double radiusPx) {
    final n = segments.length;
    const labelOffsetPx = 3.0;

    // Outside ticks use a uniform PIXEL length so every ring reserves the same
    // inward space (getAxisOffset, radial_axis_widget.dart:1823) and the rings
    // stay evenly spaced. A factor length would scale per ring and reserve
    // unequal space.
    final tickPx = (gap * 0.6 * radiusPx).clamp(0.0, radiusPx).toDouble();

    // Only the outer ring shows labels; syncfusion reserves
    // `max(labelW, labelH) / 2 + labelOffset` of inward space for them -- a
    // PIXEL amount. Measure the real label at the live size and convert to a
    // radius fraction rather than guessing a constant.
    double labelCompFactor = 0;
    if (showTicks && segments.isNotEmpty) {
      final seg0 = segments.first;
      final m1 = _measureLabel(_labelText(seg0.minValue));
      final m2 = _measureLabel(_labelText(seg0.maxValue));
      final maxSide = [m1.width, m1.height, m2.width, m2.height]
          .reduce((a, b) => a > b ? a : b);
      labelCompFactor = (maxSide / 2 + labelOffsetPx) / radiusPx;
    }

    // Reserve the outer margin (only when ticks show) from the measured label +
    // tick length -- never a hard-coded fraction -- so it tracks font, widget
    // size, path count and gap.
    final outerEdge = showTicks
        ? (1.0 - (tickPx / radiusPx) - labelCompFactor - 0.02)
            .clamp(innerRadius + 0.1, 0.99)
            .toDouble()
        : 1.0;

    // Equal radial band per ring within [innerRadius, outerEdge].
    final band = (outerEdge - innerRadius) / n;
    final bandWidth = (band - gap).clamp(0.02, band);

    final axes = <RadialAxis>[];
    for (int i = 0; i < n; i++) {
      final seg = segments[i];
      // Outermost ring first (i == 0). The outer ring's outside labels reserve
      // extra inward space the inner rings don't, so re-add exactly that
      // (measured) amount to keep it aligned with the evenly-spaced inner rings.
      final radiusFactor =
          (outerEdge - (i * band)) + (i == 0 ? labelCompFactor : 0.0);

      // Syncfusion computes factor thickness as `factor * (gaugeRadius *
      // radiusFactor)`, so a constant factor renders thinner on inner rings.
      // Divide by radiusFactor to keep the actual stroke width identical
      // across all rings (clamped to the legal 0..1 factor range).
      final ringThickness = (bandWidth / radiusFactor).clamp(0.02, 1.0);

      final clampedValue = seg.value.clamp(seg.minValue, seg.maxValue);

      // Guard the interval: a zero/degenerate range (min == max) or
      // divisions <= 0 yields interval 0, which makes syncfusion generate an
      // empty label list and crash with a RangeError every paint.
      final range = seg.maxValue - seg.minValue;
      final safeDivisions = divisions > 0 ? divisions : 1;
      final interval = range > 0 ? range / safeDivisions : 1.0;

      axes.add(
        RadialAxis(
          minimum: seg.minValue,
          maximum: seg.maxValue,
          startAngle: 270, // full 360° ring starting at the top
          endAngle: 270,
          radiusFactor: radiusFactor,
          showAxisLine: true,
          // Tick marks on the outside edge of every ring; the numeric scale
          // labels (numbers) only on the outermost ring's outside.
          showTicks: showTicks,
          showLabels: showTicks && i == 0,
          ticksPosition: ElementsPosition.outside,
          labelsPosition: ElementsPosition.outside,
          tickOffset: 0,
          labelOffset: labelOffsetPx,
          offsetUnit: GaugeSizeUnit.logicalPixel,
          interval: interval,
          axisLineStyle: AxisLineStyle(
            thickness: ringThickness,
            thicknessUnit: GaugeSizeUnit.factor,
            cornerStyle: CornerStyle.bothCurve,
            color: trackColor,
          ),
          majorTickStyle: MajorTickStyle(
            length: tickPx,
            lengthUnit: GaugeSizeUnit.logicalPixel,
            thickness: 1.5,
            color: Colors.grey.withValues(alpha: 0.6),
          ),
          minorTicksPerInterval: 1,
          minorTickStyle: MinorTickStyle(
            length: tickPx * 0.5,
            lengthUnit: GaugeSizeUnit.logicalPixel,
            thickness: 1.0,
            color: Colors.grey.withValues(alpha: 0.5),
          ),
          axisLabelStyle: GaugeTextStyle(
            color: Colors.grey.withValues(alpha: 0.8),
            fontSize: _labelFontSize,
          ),
          // Always render the pointer, even with no data, so the pointers
          // list never toggles between empty and non-empty across rebuilds.
          // Syncfusion latches `_hasPointers` only in initState and creates
          // its per-pointer animation controllers once; if the list starts
          // empty (no data yet) and later gains an animated pointer, the
          // controller list stays empty and build() indexes it
          // (radial_axis.dart:1069) -> RangeError on every frame. A stable
          // length avoids that. No data -> transparent (invisible) pointer.
          pointers: <GaugePointer>[
            RangePointer(
              value: clampedValue,
              width: ringThickness,
              sizeUnit: GaugeSizeUnit.factor,
              cornerStyle: CornerStyle.bothCurve,
              color: seg.hasData ? seg.color : Colors.transparent,
              enableAnimation: true,
              animationType: AnimationType.ease,
              animationDuration: 600,
            ),
          ],
          annotations: (showValues && seg.hasData)
              ? <GaugeAnnotation>[
                  GaugeAnnotation(
                    angle: 270,
                    positionFactor: 1.0,
                    widget: _ValueChip(text: seg.valueText, isDark: isDark),
                  ),
                ]
              : null,
        ),
      );
    }
    return axes;
  }

  Widget _buildLegend(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 4,
        children: [
          for (final seg in segments)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: seg.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  seg.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Plain value label rendered at the top of a ring's arc (no background box).
class _ValueChip extends StatelessWidget {
  final String text;
  final bool isDark;

  const _ValueChip({required this.text, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
