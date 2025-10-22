import 'dart:math';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/string_extensions.dart';
import '../../utils/color_extensions.dart';

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
    final dataPoint = widget.signalKService.getValue(dataSource.path, source: dataSource.source);
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
    final label = dataSource.label ?? dataSource.path.toReadableLabel();

    // Parse color from hex string
    final primaryColor = style.primaryColor?.toColor(
      fallback: Theme.of(context).colorScheme.primary
    ) ?? Theme.of(context).colorScheme.primary;

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

            // Syncfusion Radial Gauge as Knob control
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = min(constraints.maxWidth, constraints.maxHeight);

                  return Center(
                    child: SizedBox(
                      width: size * 0.9,
                      height: size * 0.9,
                      child: SfRadialGauge(
                        axes: <RadialAxis>[
                          RadialAxis(
                            minimum: minValue,
                            maximum: maxValue,
                            startAngle: 150,
                            endAngle: 30,
                            showLabels: false,
                            showTicks: true,
                            minorTicksPerInterval: 0,
                            majorTickStyle: MajorTickStyle(
                              length: 8,
                              thickness: 2,
                              color: Colors.grey[400],
                            ),
                            axisLineStyle: AxisLineStyle(
                              thickness: 0.15,
                              thicknessUnit: GaugeSizeUnit.factor,
                              color: Colors.grey[300],
                            ),
                            pointers: <GaugePointer>[
                              // Range arc showing filled portion
                              RangePointer(
                                value: currentValue,
                                width: 0.15,
                                sizeUnit: GaugeSizeUnit.factor,
                                color: primaryColor,
                                enableAnimation: false,
                              ),
                              // Marker pointer for interaction
                              MarkerPointer(
                                value: currentValue,
                                markerType: MarkerType.circle,
                                markerHeight: 24,
                                markerWidth: 24,
                                color: primaryColor,
                                borderWidth: 3,
                                borderColor: Colors.white,
                                elevation: 4,
                                enableDragging: !_isSending,
                                enableAnimation: false,
                                onValueChanged: (newValue) {
                                  if (!_isSending) {
                                    setState(() {
                                      _currentKnobValue = newValue;
                                    });
                                  }
                                },
                                onValueChangeEnd: (newValue) {
                                  if (!_isSending) {
                                    _sendValue(newValue, dataSource.path);
                                  }
                                },
                              ),
                              // Needle pointer from center
                              NeedlePointer(
                                value: currentValue,
                                needleLength: 0.6,
                                needleStartWidth: 1,
                                needleEndWidth: 4,
                                needleColor: primaryColor,
                                knobStyle: KnobStyle(
                                  knobRadius: 0.08,
                                  sizeUnit: GaugeSizeUnit.factor,
                                  color: primaryColor,
                                  borderColor: Colors.white,
                                  borderWidth: 0.02,
                                ),
                                enableAnimation: false,
                              ),
                            ],
                            annotations: <GaugeAnnotation>[
                              // Value display in center
                              GaugeAnnotation(
                                widget: Container(
                                  child: Text(
                                    currentValue.toStringAsFixed(decimalPlaces),
                                    style: TextStyle(
                                      fontSize: size * 0.08,
                                      fontWeight: FontWeight.bold,
                                      color: primaryColor,
                                    ),
                                  ),
                                ),
                                angle: 90,
                                positionFactor: 0.7,
                              ),
                            ],
                          ),
                        ],
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
            content: Text('${path.toReadableLabel()} set to ${roundedValue.toStringAsFixed(decimalPlaces)}'),
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
