import 'package:flutter/material.dart';
import 'package:math_expressions/math_expressions.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';

/// Simple test tool to display conversion data from SignalK
/// Uses STANDARD SignalK WebSocket: ws://[server]/signalk/v1/stream
class ConversionTestTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const ConversionTestTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<ConversionTestTool> createState() => _ConversionTestToolState();
}

class _ConversionTestToolState extends State<ConversionTestTool> {
  /// Default paths for new conversion test tools (kept for reference)
  // static const List<String> defaultPaths = [
  //   'navigation.position',
  //   'navigation.headingTrue',
  //   'navigation.headingMagnetic',
  //   'environment.wind.directionTrue',
  //   'environment.wind.angleApparent',
  //   'environment.wind.speedTrue',
  //   'environment.wind.speedApparent',
  //   'navigation.speedOverGround',
  //   'navigation.courseOverGroundTrue',
  //   'navigation.courseGreatCircle.nextPoint.bearingTrue',
  //   'navigation.courseGreatCircle.nextPoint.distance',
  // ];

  /// Evaluate a math formula with a given value
  /// Formula example: "value * 1.94384" or "(value - 273.15) * 9/5 + 32"
  double? _evaluateFormula(String formula, double rawValue) {
    try {
      // Replace 'value' with the actual number in the formula
      final formulaWithValue = formula.replaceAll('value', rawValue.toString());

      // Parse and evaluate the expression
      Parser parser = Parser();
      Expression exp = parser.parse(formulaWithValue);

      // Create context (empty since we already substituted the value)
      ContextModel cm = ContextModel();

      // Evaluate
      double result = exp.evaluate(EvaluationType.REAL, cm);
      return result;
    } catch (e) {
      // If evaluation fails, return null
      return null;
    }
  }

  @override
  void initState() {
    super.initState();

    // Subscribe to paths using STANDARD SignalK WebSocket ONLY
    // Path: ws://[server]/signalk/v1/stream
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final paths = widget.config.dataSources.map((ds) => ds.path).toList();
      if (paths.isNotEmpty) {
        widget.signalKService.subscribeToAutopilotPaths(paths);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.signalKService.isConnected) {
      return const Center(
        child: Text(
          'Not connected',
          style: TextStyle(fontSize: 12),
        ),
      );
    }

    if (widget.config.dataSources.isEmpty) {
      return const Center(
        child: Text(
          'No paths configured',
          style: TextStyle(fontSize: 12),
        ),
      );
    }

    return ListView.builder(
      itemCount: widget.config.dataSources.length,
      itemBuilder: (context, index) {
        final path = widget.config.dataSources[index].path;
        final dataPoint = widget.signalKService.getValue(path);
        final baseUnit = widget.signalKService.getBaseUnit(path);
        final availableUnits = widget.signalKService.getAvailableUnits(path);
        final category = widget.signalKService.getCategory(path);

        // Get the first available target unit (if any)
        final targetUnit = availableUnits.isNotEmpty ? availableUnits.first : null;
        final conversionInfo = targetUnit != null
            ? widget.signalKService.getConversionInfo(path, targetUnit)
            : null;

        // Calculate converted value using the formula
        double? calculatedValue;
        if (conversionInfo != null && dataPoint?.value is num) {
          final rawValue = (dataPoint!.value as num).toDouble();
          calculatedValue = _evaluateFormula(conversionInfo.formula, rawValue);
        }

        return Card(
          margin: const EdgeInsets.all(4.0),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  path,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                _buildRow('Category', category),
                _buildRow('Base Unit', baseUnit ?? 'N/A'),
                _buildRow('Target Unit', targetUnit ?? 'N/A'),
                const Divider(height: 8),
                _buildRow('Raw Value', dataPoint?.value?.toString() ?? '---'),
                _buildRow('Value Type', dataPoint?.value?.runtimeType.toString() ?? '---'),
                _buildRow('Calculated', calculatedValue != null
                    ? '${calculatedValue.toStringAsFixed(4)} ${conversionInfo?.symbol ?? ''}'
                    : '---'),
                const Divider(height: 8),
                _buildRow('From Plugin', dataPoint?.converted?.toString() ?? '---'),
                _buildRow('Formatted', dataPoint?.formatted ?? '---'),
                if (conversionInfo != null) ...[
                  const Divider(height: 8),
                  _buildRow('Formula', conversionInfo.formula),
                  _buildRow('Symbol', conversionInfo.symbol),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.0),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Builder for conversion test tool
class ConversionTestToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'conversion_test',
      name: 'Conversion Test',
      description: 'Test tool to display conversion data from standard SignalK stream',
      category: ToolCategory.system,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: true,
        minPaths: 1,
        maxPaths: 20,
        styleOptions: const [],
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return ConversionTestTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
