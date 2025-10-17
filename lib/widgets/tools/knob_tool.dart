import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';

/// Config-driven knob (rotary control) tool for sending numeric values to SignalK paths
class KnobTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const KnobTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<KnobTool> createState() => _KnobToolState();
}

class _KnobToolState extends State<KnobTool> {
  bool _isSending = false;
  double? _currentKnobValue;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    // Get data from first data source
    if (widget.config.dataSources.isEmpty) {
      return const Center(child: Text('No data source configured'));
    }

    final dataSource = widget.config.dataSources.first;
    final dataPoint = widget.signalKService.getValue(dataSource.path);
    final style = widget.config.style;

    // Get min/max values from style config
    final minValue = style.minValue ?? 0.0;
    final maxValue = style.maxValue ?? 100.0;

    // Get current value from SignalK or use knob value
    double currentValue;
    if (_currentKnobValue != null) {
      currentValue = _currentKnobValue!;
    } else {
      // Use converted value if available (from units-preference plugin)
      final convertedValue = widget.signalKService.getConvertedValue(dataSource.path);
      if (convertedValue != null) {
        currentValue = convertedValue;
      } else {
        currentValue = minValue;
      }
    }

    // Clamp value to range
    currentValue = currentValue.clamp(minValue, maxValue);

    // Get label from data source or style
    final label = dataSource.label ?? _getDefaultLabel(dataSource.path);

    // Parse color from hex string
    Color primaryColor = Theme.of(context).colorScheme.primary;
    if (style.primaryColor != null) {
      try {
        final colorString = style.primaryColor!.replaceAll('#', '');
        primaryColor = Color(int.parse('FF$colorString', radix: 16));
      } catch (e) {
        // Keep default color if parsing fails
      }
    }

    // Get unit
    final unit = style.unit ?? dataPoint?.symbol ?? '';

    // Get decimal places from customProperties
    final decimalPlaces = style.customProperties?['decimalPlaces'] as int? ?? 1;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (style.showLabel == true) ...[
              Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
            ],

            // Knob control
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = min(constraints.maxWidth, constraints.maxHeight) * 0.8;

                  void updateValueFromPosition(Offset localPosition) {
                    if (_isSending) return;

                    // Calculate angle from center
                    final center = Offset(size / 2, size / 2);
                    final position = localPosition - center;
                    var angle = atan2(position.dy, position.dx);

                    // Normalize angle to 0-300 degrees (240 degree range)
                    // Starting from -150 degrees (bottom-left) to 150 degrees (bottom-right)
                    const startAngle = -150.0 * pi / 180.0;
                    const endAngle = 150.0 * pi / 180.0;
                    const range = endAngle - startAngle;

                    // Adjust angle to start from bottom-left
                    angle = angle - startAngle;
                    if (angle < 0) angle += 2 * pi;
                    if (angle > range) {
                      // Clamp to range
                      if (angle < pi) {
                        angle = 0;
                      } else {
                        angle = range;
                      }
                    }

                    // Convert angle to value
                    final normalizedAngle = angle / range;
                    final newValue = minValue + (maxValue - minValue) * normalizedAngle;

                    setState(() {
                      _currentKnobValue = newValue.clamp(minValue, maxValue);
                    });
                  }

                  return Center(
                    child: GestureDetector(
                      // Block parent scroll by consuming all drag gestures
                      onVerticalDragStart: (_) {},
                      onVerticalDragUpdate: (_) {},
                      onVerticalDragEnd: (_) {},
                      onHorizontalDragStart: (_) {},
                      onHorizontalDragUpdate: (_) {},
                      onHorizontalDragEnd: (_) {},
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (event) {
                          // Handle initial touch
                          setState(() => _isDragging = false);
                          updateValueFromPosition(event.localPosition);
                        },
                        onPointerMove: (event) {
                          // Handle dragging
                          if (!_isSending) {
                            setState(() => _isDragging = true);
                            updateValueFromPosition(event.localPosition);
                          }
                        },
                        onPointerUp: (event) {
                          // Send PUT on release
                          if (_currentKnobValue != null) {
                            _sendValue(_currentKnobValue!, dataSource.path);
                          }
                          setState(() => _isDragging = false);
                        },
                        onPointerCancel: (event) {
                          setState(() => _isDragging = false);
                        },
                        child: Container(
                          width: size,
                          height: size,
                          child: CustomPaint(
                            size: Size(size, size),
                            painter: _KnobPainter(
                              value: currentValue,
                              minValue: minValue,
                              maxValue: maxValue,
                              color: primaryColor,
                              decimalPlaces: decimalPlaces,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // Min/Max labels
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  minValue.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  maxValue.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Path info
            Text(
              dataSource.path,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            // Sending indicator
            if (_isSending) ...[
              const SizedBox(height: 8),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _sendValue(double value, String path) async {
    setState(() {
      _isSending = true;
    });

    try {
      // Get decimal places and round the value before sending
      final decimalPlaces = widget.config.style.customProperties?['decimalPlaces'] as int? ?? 1;
      final multiplier = pow(10, decimalPlaces).toDouble();
      final roundedValue = (value * multiplier).round() / multiplier;

      await widget.signalKService.sendPutRequest(path, roundedValue);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_getDefaultLabel(path)} set to ${roundedValue.toStringAsFixed(decimalPlaces)}'),
            duration: const Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set value: $e'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _currentKnobValue = null; // Reset to sync with server value
        });
      }
    }
  }

  /// Extract a readable label from the path
  String _getDefaultLabel(String path) {
    final parts = path.split('.');
    if (parts.isEmpty) return path;

    // Get the last part and make it readable
    final lastPart = parts.last;

    // Convert camelCase to Title Case
    final result = lastPart.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)}',
    ).trim();

    return result.isEmpty ? lastPart : result;
  }
}

/// Custom painter for the knob
class _KnobPainter extends CustomPainter {
  final double value;
  final double minValue;
  final double maxValue;
  final Color color;
  final int decimalPlaces;

  _KnobPainter({
    required this.value,
    required this.minValue,
    required this.maxValue,
    required this.color,
    this.decimalPlaces = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw outer circle (background)
    final bgPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    // Draw track arc
    const startAngle = -150.0 * pi / 180.0;
    const endAngle = 150.0 * pi / 180.0;
    const sweepAngle = endAngle - startAngle;

    final trackPaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 20),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    // Draw value arc
    final normalized = (value - minValue) / (maxValue - minValue);
    final valueSweep = sweepAngle * normalized;

    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 20),
      startAngle,
      valueSweep,
      false,
      valuePaint,
    );

    // Draw center knob
    final knobRadius = radius * 0.5;
    final knobPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, knobRadius, knobPaint);

    // Draw knob border
    final knobBorderPaint = Paint()
      ..color = Colors.grey.shade600
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, knobRadius, knobBorderPaint);

    // Draw indicator line on knob
    final indicatorAngle = startAngle + valueSweep;
    final indicatorEnd = Offset(
      center.dx + (knobRadius - 8) * cos(indicatorAngle),
      center.dy + (knobRadius - 8) * sin(indicatorAngle),
    );

    final indicatorPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(center, indicatorEnd, indicatorPaint);

    // Draw center dot
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 4, dotPaint);

    // Draw value text in the center (below the dot)
    final textSpan = TextSpan(
      text: value.toStringAsFixed(decimalPlaces),
      style: TextStyle(
        color: Colors.grey.shade800,
        fontSize: knobRadius * 0.5,
        fontWeight: FontWeight.bold,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // Position text below center
    final textOffset = Offset(
      center.dx - textPainter.width / 2,
      center.dy + 10,
    );
    textPainter.paint(canvas, textOffset);
  }

  @override
  bool shouldRepaint(_KnobPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.minValue != minValue ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.color != color ||
        oldDelegate.decimalPlaces != decimalPlaces;
  }
}

/// Builder for knob tools
class KnobToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'knob',
      name: 'Knob',
      description: 'Rotary knob control for sending numeric values to SignalK paths',
      category: ToolCategory.control,
      configSchema: ConfigSchema(
        allowsMinMax: true,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 1,
        maxPaths: 1,
        styleOptions: const [
          'minValue',
          'maxValue',
          'primaryColor',
          'showLabel',
          'showValue',
          'showUnit',
        ],
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return KnobTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
