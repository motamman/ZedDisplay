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
  static String formatValue(
    SignalKService service,
    String path,
    double rawValue, {
    int decimalPlaces = 1,
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

    // Format with symbol
    final symbol = conversionInfo.symbol;
    return '${converted.toStringAsFixed(decimalPlaces)} $symbol';
  }

  /// Get converted value from a data point
  /// Applies THE conversion formula for this path
  static double? getConvertedValue(
    SignalKService service,
    String path,
  ) {
    final dataPoint = service.getValue(path);
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
  static double? getRawValue(
    SignalKService service,
    String path,
  ) {
    final dataPoint = service.getValue(path);
    if (dataPoint == null) return null;

    // Standard stream: value IS the raw SI value
    if (dataPoint.value is num) {
      return (dataPoint.value as num).toDouble();
    }

    return null;
  }
}
