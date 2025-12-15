import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/string_extensions.dart';
import '../../utils/color_extensions.dart';
import '../../utils/conversion_utils.dart';
import '../../config/ui_constants.dart';
import 'mixins/control_tool_mixin.dart';
import 'common/control_tool_layout.dart';

/// Config-driven slider tool for sending numeric values to SignalK paths
class SliderTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const SliderTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<SliderTool> createState() => _SliderToolState();
}

class _SliderToolState extends State<SliderTool> with ControlToolMixin, AutomaticKeepAliveClientMixin {
  double? _currentSliderValue;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Get data from first data source
    if (widget.config.dataSources.isEmpty) {
      return const Center(child: Text('No data source configured'));
    }

    final dataSource = widget.config.dataSources.first;
    final style = widget.config.style;

    // Get min/max values from style config
    final minValue = style.minValue ?? 0.0;
    final maxValue = style.maxValue ?? 100.0;

    // Get current value from SignalK or use slider value
    double currentValue;
    if (_currentSliderValue != null) {
      currentValue = _currentSliderValue!;
    } else {
      // Use client-side conversions with source
      final convertedValue = ConversionUtils.getConvertedValue(
        widget.signalKService,
        dataSource.path,
        source: dataSource.source,
      );
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

    // Get unit symbol from conversion info
    final availableUnits = widget.signalKService.getAvailableUnits(dataSource.path);
    final conversionInfo = availableUnits.isNotEmpty
        ? widget.signalKService.getConversionInfo(dataSource.path, availableUnits.first)
        : null;
    final unit = style.unit ?? conversionInfo?.symbol ?? '';

    // Get decimal places from customProperties
    final decimalPlaces = style.customProperties?['decimalPlaces'] as int? ?? UIConstants.defaultDecimalPlaces;

    return ControlToolLayout(
      label: label,
      showLabel: style.showLabel == true,
      valueWidget: style.showValue == true
          ? Text(
              '${currentValue.toStringAsFixed(decimalPlaces)}${style.showUnit == true ? " $unit" : ""}',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            )
          : null,
      additionalWidgets: [
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
      ],
      controlWidget: GestureDetector(
        onHorizontalDragStart: (_) {}, // Block parent scroll
        onHorizontalDragUpdate: (_) {},
        onHorizontalDragEnd: (_) {},
        child: SfSliderTheme(
          data: SfSliderThemeData(
            activeTrackHeight: UIConstants.sliderActiveTrackHeight,
            inactiveTrackHeight: UIConstants.sliderInactiveTrackHeight,
            activeTrackColor: primaryColor,
            inactiveTrackColor: UIConstants.withLightOpacity(Colors.grey),
            thumbColor: primaryColor,
            thumbRadius: UIConstants.sliderThumbRadius,
            overlayColor: primaryColor.withValues(alpha: UIConstants.veryLightOpacity),
            overlayRadius: UIConstants.sliderOverlayRadius,
            tooltipBackgroundColor: primaryColor,
          ),
          child: SfSlider(
            value: currentValue,
            min: minValue,
            max: maxValue,
            stepSize: (maxValue - minValue) / ((maxValue - minValue) * (10 * (decimalPlaces + 1))).clamp(10, 1000),
            enableTooltip: true,
            numberFormat: NumberFormat.decimalPatternDigits(decimalDigits: decimalPlaces),
            onChanged: isSending ? null : (value) {
              setState(() {
                _currentSliderValue = value;
              });
            },
            onChangeEnd: (value) {
              final decimalPlaces = widget.config.style.customProperties?['decimalPlaces'] as int? ?? UIConstants.defaultDecimalPlaces;
              sendNumericValue(
                value: value,
                path: dataSource.path,
                signalKService: widget.signalKService,
                decimalPlaces: decimalPlaces,
                onComplete: () {
                  setState(() {
                    _currentSliderValue = null;
                  });
                },
              );
            },
          ),
        ),
      ),
      path: dataSource.path,
      isSending: isSending,
    );
  }

}

/// Builder for slider tools
class SliderToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'slider',
      name: 'Slider',
      description: 'Slider control for sending numeric values to SignalK paths',
      category: ToolCategory.controls,
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
    return SliderTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
