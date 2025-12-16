import 'package:math_expressions/math_expressions.dart';
import '../services/signalk_service.dart';

/// Utility for applying client-side unit conversions using formulas from SignalK server
class ConversionUtils {
  /// Evaluate a math formula with a given value
  /// Formula example: "value * 1.94384" or "(value - 273.15) * 9/5 + 32"
  static double? evaluateFormula(String formula, double rawValue) {
    try {
      // Replace 'value' with the actual number in the formula
      final formulaWithValue = formula.replaceAll('value', rawValue.toString());

      // Parse and evaluate the expression
      Parser parser = Parser();
      Expression exp = parser.parse(formulaWithValue);

      // Evaluate using new RealEvaluator API (math_expressions v3.x)
      // RealEvaluator.evaluate() takes only Expression, returns num
      num result = RealEvaluator().evaluate(exp);
      return result.toDouble();
    } catch (e) {
      // If evaluation fails, return null
      return null;
    }
  }

  /// Convert a raw value using THE conversion formula for this path
  /// Returns converted value, or raw value if no conversion available
  static double? convertValue(
    SignalKService service,
    String path,
    double rawValue,
  ) {
    // Get available units for this path
    final availableUnits = service.getAvailableUnits(path);
    if (availableUnits.isEmpty) {
      // No conversion available, return raw value
      return rawValue;
    }

    // Get THE conversion for this path (there's only one)
    final unit = availableUnits.first;
    final conversionInfo = service.getConversionInfo(path, unit);
    if (conversionInfo == null) {
      return rawValue;
    }

    // Apply the formula
    return evaluateFormula(conversionInfo.formula, rawValue);
  }

  /// Format a value with unit symbol using THE conversion for this path
  /// Returns a formatted string like "12.6 kn" or "45.2°"
  /// Set [includeUnit] to false to return just the numeric value without unit
  static String formatValue(
    SignalKService service,
    String path,
    double rawValue, {
    int decimalPlaces = 1,
    bool includeUnit = true,
  }) {
    // Get available units
    final availableUnits = service.getAvailableUnits(path);
    if (availableUnits.isEmpty) {
      // No conversion available, format raw value
      return rawValue.toStringAsFixed(decimalPlaces);
    }

    // Get THE conversion for this path
    final unit = availableUnits.first;
    final conversionInfo = service.getConversionInfo(path, unit);
    if (conversionInfo == null) {
      return rawValue.toStringAsFixed(decimalPlaces);
    }

    // Convert value
    final converted = evaluateFormula(conversionInfo.formula, rawValue);
    if (converted == null) {
      return rawValue.toStringAsFixed(decimalPlaces);
    }

    // Format with symbol (if requested)
    if (includeUnit) {
      final symbol = conversionInfo.symbol;
      return '${converted.toStringAsFixed(decimalPlaces)} $symbol';
    }
    return converted.toStringAsFixed(decimalPlaces);
  }

  /// Get converted value from a data point
  /// Applies THE conversion formula for this path
  /// If [source] is specified, gets value from that specific source
  static double? getConvertedValue(
    SignalKService service,
    String path, {
    String? source,
  }) {
    final dataPoint = service.getValue(path, source: source);
    if (dataPoint == null) return null;

    // Get raw value and apply conversion
    if (dataPoint.value is num) {
      final rawValue = (dataPoint.value as num).toDouble();
      return convertValue(service, path, rawValue);
    }

    return null;
  }

  /// Get raw SI value from standard SignalK stream
  /// With standard stream, dataPoint.value IS the raw SI value
  /// If [source] is specified, gets value from that specific source
  static double? getRawValue(
    SignalKService service,
    String path, {
    String? source,
  }) {
    final dataPoint = service.getValue(path, source: source);
    if (dataPoint == null) return null;

    // Standard stream: value IS the raw SI value
    if (dataPoint.value is num) {
      return (dataPoint.value as num).toDouble();
    }

    return null;
  }

  /// Convert a display value back to raw SI value using inverse formula
  /// Used when sending PUT requests - converts user-entered display value
  /// back to the raw value that SignalK expects
  static double convertToRaw(
    SignalKService service,
    String path,
    double displayValue,
  ) {
    // Get available units for this path
    final availableUnits = service.getAvailableUnits(path);
    if (availableUnits.isEmpty) {
      // No conversion available, return as-is
      return displayValue;
    }

    // Get THE conversion for this path
    final unit = availableUnits.first;
    final conversionInfo = service.getConversionInfo(path, unit);
    if (conversionInfo == null) {
      return displayValue;
    }

    // Apply the inverse formula
    final rawValue = evaluateFormula(conversionInfo.inverseFormula, displayValue);
    return rawValue ?? displayValue;
  }
}
