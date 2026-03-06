import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

/// Available compass display styles
enum CompassStyle {
  classic,  // Full circle with needle (default)
  arc,      // 180° arc showing heading range
  minimal,  // Clean modern with simplified markings
  marine,   // Card rotates, needle points up (traditional marine compass)
}

/// A compass widget for displaying heading/bearing
/// Now powered by Syncfusion for professional appearance
/// Supports up to 4 needles for comparing multiple headings
class CompassGauge extends StatelessWidget {
  final double heading; // Primary heading in degrees (0-360)
  final String label;
  final String? formattedValue;
  final Color primaryColor;
  final bool showTickLabels;
  final CompassStyle compassStyle;
  final bool showValue; // Show/hide the heading value display

  // Additional headings for multi-needle display (up to 3 more)
  final List<double>? additionalHeadings;
  final List<String>? additionalLabels;
  final List<Color>? additionalColors;
  final List<String>? additionalFormattedValues;

  // Active needle selection
  final int activeIndex;
  final ValueChanged<int>? onActiveIndexChanged;

  const CompassGauge({
    super.key,
    required this.heading,
    this.label = 'Heading',
    this.formattedValue,
    this.primaryColor = Colors.red,
    this.showTickLabels = false,
    this.compassStyle = CompassStyle.classic,
    this.showValue = true,
    this.additionalHeadings,
    this.additionalLabels,
    this.additionalColors,
    this.additionalFormattedValues,
    this.activeIndex = 0,
    this.onActiveIndexChanged,
  });

  bool get _hasMultipleNeedles =>
      additionalHeadings != null && additionalHeadings!.isNotEmpty;

  /// Resolve the active needle's heading value
  double get _activeHeading {
    if (activeIndex == 0 || !_hasMultipleNeedles) return heading;
    final i = activeIndex - 1;
    if (i < additionalHeadings!.length) return additionalHeadings![i];
    return heading;
  }

  /// Resolve the active needle's label
  String get _activeLabel {
    if (activeIndex == 0 || !_hasMultipleNeedles) return label;
    final i = activeIndex - 1;
    if (additionalLabels != null && i < additionalLabels!.length) {
      return additionalLabels![i];
    }
    return label;
  }

  /// Resolve the active needle's formatted value
  String? get _activeFormattedValue {
    if (activeIndex == 0 || !_hasMultipleNeedles) return formattedValue;
    final i = activeIndex - 1;
    if (additionalFormattedValues != null && i < additionalFormattedValues!.length) {
      return additionalFormattedValues![i];
    }
    return null;
  }

  /// Resolve the active needle's color
  Color get _activeColor {
    if (activeIndex == 0 || !_hasMultipleNeedles) return primaryColor;
    final i = activeIndex - 1;
    if (additionalColors != null && i < additionalColors!.length) {
      return additionalColors![i];
    }
    return primaryColor;
  }

  @override
  Widget build(BuildContext context) {
    // Marine style uses a custom rotating card implementation
    if (compassStyle == CompassStyle.marine) {
      return _buildMarineCompass(context);
    }

    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  // Gauge with pointer - drawn first
                  SfRadialGauge(
                    axes: <RadialAxis>[
                      RadialAxis(
                        minimum: 0,
                        maximum: 360,
                        interval: _getInterval(),

                        // Angles based on style
                        startAngle: _getStartAngle(),
                        endAngle: _getEndAngle(),

                        // Hide axis line
                        showAxisLine: false,
                        showLastLabel: compassStyle != CompassStyle.arc,

                        // Tick configuration
                        majorTickStyle: MajorTickStyle(
                          length: _getMajorTickLength(),
                          thickness: 2,
                          color: compassStyle == CompassStyle.minimal
                              ? Colors.grey.withValues(alpha: 0.3)
                              : Colors.grey,
                        ),
                        minorTicksPerInterval: compassStyle == CompassStyle.minimal ? 0 : 2,
                        minorTickStyle: MinorTickStyle(
                          length: 6,
                          thickness: 1,
                          color: Colors.grey.withValues(alpha: 0.5),
                        ),

                        // Hide auto-generated labels - we'll use custom annotations instead
                        showLabels: false,

                        // Outer ring for visual boundary
                        ranges: _getRanges(),

                        // Heading pointer
                        pointers: _getPointers(),

                        // Compass labels with counter-rotation to stay horizontal
                        annotations: _buildCompassLabels(),
                      ),
                    ],
                  ),

                  // Center annotation with heading value - drawn last so it's on top
                  if (showValue)
                    Align(
                      alignment: Alignment.center,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 55.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (compassStyle != CompassStyle.minimal && _activeLabel.isNotEmpty)
                              Text(
                                _activeLabel,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                            if (compassStyle != CompassStyle.minimal && _activeLabel.isNotEmpty)
                              const SizedBox(height: 4),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _activeFormattedValue ?? '${_activeHeading.toStringAsFixed(0)}°',
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  _getCardinalDirection(_activeHeading),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                    color: _activeColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_hasMultipleNeedles) _buildLegendRow(),
      ],
    );
  }

  Widget _buildLegendRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          // Primary needle
          _buildLegendItem(
            index: 0,
            text: label,
            color: primaryColor,
            value: formattedValue,
          ),
          // Additional needles
          if (additionalHeadings != null)
            for (int i = 0; i < additionalHeadings!.length && i < 3; i++)
              _buildLegendItem(
                index: i + 1,
                text: additionalLabels != null && i < additionalLabels!.length
                    ? additionalLabels![i]
                    : '',
                color: additionalColors != null && i < additionalColors!.length
                    ? additionalColors![i]
                    : Colors.blue,
                value: additionalFormattedValues != null && i < additionalFormattedValues!.length
                        ? additionalFormattedValues![i]
                        : null,
              ),
        ],
      ),
    );
  }

  Widget _buildLegendItem({
    required int index,
    required String text,
    required Color color,
    String? value,
  }) {
    final isActive = index == activeIndex;
    final displayText = value != null && text.isNotEmpty
        ? '$text ($value)'
        : value ?? text;

    return GestureDetector(
      onTap: onActiveIndexChanged != null ? () => onActiveIndexChanged!(index) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? color.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 3,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              displayText,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _getStartAngle() {
    switch (compassStyle) {
      case CompassStyle.arc:
        return 180; // Bottom half
      default:
        return 270; // Top (north)
    }
  }

  double _getEndAngle() {
    switch (compassStyle) {
      case CompassStyle.arc:
        return 0; // 180 degree arc
      default:
        return 270; // Full circle
    }
  }

  double _getInterval() {
    switch (compassStyle) {
      case CompassStyle.minimal:
        return 90; // Only cardinal directions
      default:
        return 30;
    }
  }

  double _getMajorTickLength() {
    switch (compassStyle) {
      case CompassStyle.minimal:
        return 8;
      default:
        return 12;
    }
  }

  /// Build compass labels (N, S, E, W, degrees) with proper rotation
  /// Labels are counter-rotated by heading so they stay horizontal
  List<GaugeAnnotation> _buildCompassLabels() {
    final labels = <GaugeAnnotation>[];
    const int interval = 30;

    for (int i = 0; i < 360; i += interval) {
      String labelText;
      Color labelColor;
      double fontSize;

      switch (i) {
        case 0:
          labelText = 'N';
          labelColor = primaryColor;
          fontSize = 20;
          break;
        case 90:
          labelText = 'E';
          labelColor = Colors.grey;
          fontSize = 16;
          break;
        case 180:
          labelText = 'S';
          labelColor = Colors.grey;
          fontSize = 16;
          break;
        case 270:
          labelText = 'W';
          labelColor = Colors.grey;
          fontSize = 16;
          break;
        default:
          if (!showTickLabels) continue;
          labelText = '$i°';
          labelColor = Colors.grey.withValues(alpha: 0.6);
          fontSize = 14;
      }

      double labelAngle;
      if (compassStyle == CompassStyle.arc) {
        // Arc compresses 360° into 180° semicircle
        // Gauge value i maps to screen position 180 + (i/2)
        labelAngle = 180 + (i / 2);
      } else {
        // Full circle: add 270° offset to align N to top
        labelAngle = (i + 270) % 360;
      }

      labels.add(
        GaugeAnnotation(
          widget: Text(
            labelText,
            style: TextStyle(
              color: labelColor,
              fontSize: fontSize,
              fontWeight: i == 0 || i % 90 == 0 ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          angle: labelAngle,
          positionFactor: 0.80,
        ),
      );
    }

    return labels;
  }

  List<GaugeRange> _getRanges() {
    if (compassStyle == CompassStyle.minimal) {
      return [];
    }

    return [
      GaugeRange(
        startValue: 0,
        endValue: 360,
        color: Colors.grey.withValues(alpha: 0.2),
        startWidth: 2,
        endWidth: 2,
      ),
    ];
  }

  List<GaugePointer> _getPointers() {
    final pointers = <GaugePointer>[];

    // Collect all needle data: index 0 = primary, 1+ = additional
    final allNeedles = <_NeedleData>[
      _NeedleData(0, heading, primaryColor),
    ];
    if (additionalHeadings != null) {
      for (int i = 0; i < additionalHeadings!.length && i < 3; i++) {
        final color = additionalColors != null && i < additionalColors!.length
            ? additionalColors![i]
            : Colors.blue;
        allNeedles.add(_NeedleData(i + 1, additionalHeadings![i], color));
      }
    }

    // Draw non-active needles first, active needle last
    for (final needle in allNeedles) {
      if (needle.index == activeIndex) continue;
      pointers.add(_buildNeedlePointer(needle, isActive: false));
    }
    // Draw active needle on top
    final activeNeedle = allNeedles.firstWhere(
      (n) => n.index == activeIndex,
      orElse: () => allNeedles.first,
    );
    pointers.add(_buildNeedlePointer(activeNeedle, isActive: true));

    return pointers;
  }

  GaugePointer _buildNeedlePointer(_NeedleData needle, {required bool isActive}) {
    if (compassStyle == CompassStyle.minimal && isActive) {
      return MarkerPointer(
        value: needle.value,
        markerType: MarkerType.triangle,
        markerHeight: 20,
        markerWidth: 20,
        color: needle.color,
        markerOffset: -10,
      );
    }

    return NeedlePointer(
      value: needle.value,
      needleLength: isActive ? 0.7 : 0.65,
      needleStartWidth: 0,
      needleEndWidth: isActive ? 10 : 8,
      needleColor: isActive ? needle.color : needle.color.withValues(alpha: 0.8),
      knobStyle: isActive
          ? KnobStyle(
              knobRadius: 0.08,
              color: needle.color,
              borderColor: needle.color,
              borderWidth: 0.02,
            )
          : const KnobStyle(knobRadius: 0),
    );
  }

  String _getCardinalDirection(double degrees) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((degrees + 22.5) / 45).floor() % 8;
    return directions[index];
  }

  /// Build marine-style compass where card rotates
  Widget _buildMarineCompass(BuildContext context) {
    // Collect all needles for ordering
    final allNeedles = <_NeedleData>[
      _NeedleData(0, heading, primaryColor),
    ];
    if (additionalHeadings != null) {
      for (int i = 0; i < additionalHeadings!.length && i < 3; i++) {
        final color = additionalColors != null && i < additionalColors!.length
            ? additionalColors![i]
            : Colors.blue;
        allNeedles.add(_NeedleData(i + 1, additionalHeadings![i], color));
      }
    }

    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  // Rotating compass card
                  Transform.rotate(
                    angle: -heading * 3.14159265359 / 180,
                    child: SfRadialGauge(
                      axes: <RadialAxis>[
                        RadialAxis(
                          minimum: 0,
                          maximum: 360,
                          interval: 30,
                          startAngle: 270,
                          endAngle: 270,
                          showAxisLine: false,
                          showLastLabel: true,

                          majorTickStyle: const MajorTickStyle(
                            length: 12,
                            thickness: 2,
                            color: Colors.grey,
                          ),
                          minorTicksPerInterval: 2,
                          minorTickStyle: MinorTickStyle(
                            length: 6,
                            thickness: 1,
                            color: Colors.grey.withValues(alpha: 0.5),
                          ),

                          showLabels: false,

                          ranges: [
                            GaugeRange(
                              startValue: 0,
                              endValue: 360,
                              color: Colors.grey.withValues(alpha: 0.2),
                              startWidth: 2,
                              endWidth: 2,
                            ),
                          ],

                          pointers: const [],

                          annotations: _buildMarineCompassLabels(),
                        ),
                      ],
                    ),
                  ),

                  // Non-active needles first
                  for (final needle in allNeedles)
                    if (needle.index != activeIndex)
                      Transform.rotate(
                        angle: (needle.value - heading) * 3.14159265359 / 180,
                        child: Center(
                          child: CustomPaint(
                            size: const Size(200, 200),
                            painter: _MarineNeedlePainter(
                              needle.color,
                              isSecondary: true,
                            ),
                          ),
                        ),
                      ),

                  // Active needle last (on top)
                  () {
                    final active = allNeedles.firstWhere(
                      (n) => n.index == activeIndex,
                      orElse: () => allNeedles.first,
                    );
                    return Transform.rotate(
                      angle: (active.value - heading) * 3.14159265359 / 180,
                      child: Center(
                        child: CustomPaint(
                          size: const Size(200, 200),
                          painter: _MarineNeedlePainter(active.color),
                        ),
                      ),
                    );
                  }(),

                  // Center annotation with heading value (non-rotating)
                  if (showValue)
                    Align(
                      alignment: Alignment.center,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 60.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_activeLabel.isNotEmpty)
                              Text(
                                _activeLabel,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                            if (_activeLabel.isNotEmpty)
                              const SizedBox(height: 4),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _activeFormattedValue ?? '${_activeHeading.toStringAsFixed(0)}°',
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  _getCardinalDirection(_activeHeading),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                    color: _activeColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_hasMultipleNeedles) _buildLegendRow(),
      ],
    );
  }

  /// Build marine compass labels that counter-rotate to stay horizontal
  List<GaugeAnnotation> _buildMarineCompassLabels() {
    final labels = <GaugeAnnotation>[];
    const int interval = 30;

    for (int i = 0; i < 360; i += interval) {
      String labelText;
      Color labelColor;
      double fontSize;

      switch (i) {
        case 0:
          labelText = 'N';
          labelColor = primaryColor;
          fontSize = 22;
          break;
        case 90:
          labelText = 'E';
          labelColor = Colors.grey;
          fontSize = 18;
          break;
        case 180:
          labelText = 'S';
          labelColor = Colors.grey;
          fontSize = 18;
          break;
        case 270:
          labelText = 'W';
          labelColor = Colors.grey;
          fontSize = 18;
          break;
        default:
          if (!showTickLabels) continue;
          labelText = '$i°';
          labelColor = Colors.grey.withValues(alpha: 0.7);
          fontSize = 16;
      }

      labels.add(
        GaugeAnnotation(
          widget: Transform.rotate(
            angle: heading * 3.14159 / 180,
            child: Text(
              labelText,
              style: TextStyle(
                color: labelColor,
                fontSize: fontSize,
                fontWeight: i % 90 == 0 ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
          angle: i.toDouble(),
          positionFactor: 0.80,
        ),
      );
    }

    return labels;
  }
}

/// Simple data holder for needle info
class _NeedleData {
  final int index;
  final double value;
  final Color color;
  _NeedleData(this.index, this.value, this.color);
}

/// Custom painter for the fixed marine compass needle
class _MarineNeedlePainter extends CustomPainter {
  final Color color;
  final bool isSecondary;

  _MarineNeedlePainter(this.color, {this.isSecondary = false});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final northNeedleLength = radius * (isSecondary ? 0.7 : 0.8);
    final southTailLength = radius * (isSecondary ? 0.65 : 0.75);
    final needleWidth = isSecondary ? 6.0 : 8.0;

    final paint = Paint()
      ..color = isSecondary ? color.withValues(alpha: 0.8) : color
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    // Draw needle pointing up (North)
    final needlePath = Path();

    // North pointing needle
    needlePath.moveTo(center.dx, center.dy - northNeedleLength);
    needlePath.lineTo(center.dx - needleWidth, center.dy);
    needlePath.lineTo(center.dx, center.dy - 10);
    needlePath.lineTo(center.dx + needleWidth, center.dy);
    needlePath.close();

    // Draw shadow
    if (!isSecondary) {
      canvas.drawPath(needlePath, shadowPaint);
    }

    // Draw needle
    canvas.drawPath(needlePath, paint);

    // South pointing tail (darker shade for better visibility)
    final hslColor = HSLColor.fromColor(color);
    final darkerColor = hslColor.withLightness((hslColor.lightness - 0.3).clamp(0.0, 1.0)).toColor();

    final tailPaint = Paint()
      ..color = isSecondary ? darkerColor.withValues(alpha: 0.8) : darkerColor
      ..style = PaintingStyle.fill;

    final tailPath = Path();
    tailPath.moveTo(center.dx, center.dy + southTailLength);
    tailPath.lineTo(center.dx - (needleWidth * 0.75), center.dy);
    tailPath.lineTo(center.dx + (needleWidth * 0.75), center.dy);
    tailPath.close();

    canvas.drawPath(tailPath, tailPaint);

    // Draw center knob (only for primary needle)
    if (!isSecondary) {
      final knobPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawCircle(center, 10, knobPaint);

      final knobBorderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(center, 10, knobBorderPaint);
    }
  }

  @override
  bool shouldRepaint(_MarineNeedlePainter oldDelegate) {
    return color != oldDelegate.color || isSecondary != oldDelegate.isSecondary;
  }
}
