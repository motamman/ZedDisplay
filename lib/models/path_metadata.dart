import 'package:math_expressions/math_expressions.dart';

/// Single source of truth for path metadata and conversion formulas.
/// Populated from WebSocket meta deltas (sendMeta=all).
class PathMetadata {
  final String path;
  final String? baseUnit;       // SI unit (e.g., "m/s", "K", "rad")
  final String? targetUnit;     // Display unit (e.g., "kn", "°C", "°")
  final String? category;       // Unit category (e.g., "speed", "temperature")
  final String? formula;        // SI → display (e.g., "value * 1.94384")
  final String? inverseFormula; // display → SI (e.g., "value * 0.514444")
  final String? symbol;         // Display symbol (e.g., "kn", "°C")
  final String? displayFormat;  // Format string (e.g., "0.0")
  final DateTime lastUpdated;

  PathMetadata({
    required this.path,
    this.baseUnit,
    this.targetUnit,
    this.category,
    this.formula,
    this.inverseFormula,
    this.symbol,
    this.displayFormat,
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  /// Create from WebSocket meta displayUnits object.
  /// Expected format: {units: "kn", formula: "value * 1.94384", symbol: "kn", ...}
  factory PathMetadata.fromDisplayUnits(
    String path,
    Map<String, dynamic> displayUnits, {
    String? category,
  }) {
    // targetUnit: try 'units' first, fall back to 'symbol' (WebSocket meta uses symbol)
    final targetUnit = displayUnits['units'] as String? ??
        displayUnits['symbol'] as String?;

    return PathMetadata(
      path: path,
      baseUnit: displayUnits['baseUnit'] as String?,
      targetUnit: targetUnit,
      category: category ?? displayUnits['category'] as String?,
      formula: displayUnits['formula'] as String?,
      inverseFormula: displayUnits['inverseFormula'] as String?,
      symbol: displayUnits['symbol'] as String?,
      displayFormat: displayUnits['displayFormat'] as String?,
    );
  }

  /// Create a copy with updated fields.
  PathMetadata copyWith({
    String? baseUnit,
    String? targetUnit,
    String? category,
    String? formula,
    String? inverseFormula,
    String? symbol,
    String? displayFormat,
  }) {
    return PathMetadata(
      path: path,
      baseUnit: baseUnit ?? this.baseUnit,
      targetUnit: targetUnit ?? this.targetUnit,
      category: category ?? this.category,
      formula: formula ?? this.formula,
      inverseFormula: inverseFormula ?? this.inverseFormula,
      symbol: symbol ?? this.symbol,
      displayFormat: displayFormat ?? this.displayFormat,
    );
  }

  /// Check if this metadata has conversion information.
  bool get hasConversion => formula != null && formula!.isNotEmpty;

  /// Check if this is an identity conversion (no actual conversion needed).
  bool get isIdentity => formula == null || formula == 'value' || formula!.isEmpty;

  /// Apply formula to convert SI value to display value.
  /// Returns null if conversion fails.
  double? convert(double siValue) {
    if (formula == null || formula!.isEmpty) return siValue;
    if (formula == 'value') return siValue;

    try {
      return _evaluateFormula(formula!, siValue);
    } catch (e) {
      return null;
    }
  }

  /// Apply inverse formula to convert display value back to SI.
  /// Returns null if conversion fails.
  double? convertToSI(double displayValue) {
    if (inverseFormula == null || inverseFormula!.isEmpty) return displayValue;
    if (inverseFormula == 'value') return displayValue;

    try {
      return _evaluateFormula(inverseFormula!, displayValue);
    } catch (e) {
      return null;
    }
  }

  /// Convert and format with symbol.
  /// Returns formatted string like "10.5 kn" or the converted value if no symbol.
  String format(double siValue, {int decimals = 1}) {
    final converted = convert(siValue);
    if (converted == null) return siValue.toStringAsFixed(decimals);

    final valueStr = converted.toStringAsFixed(decimals);
    if (symbol != null && symbol!.isNotEmpty) {
      return '$valueStr $symbol';
    }
    return valueStr;
  }

  /// Evaluate a formula string with a given value.
  /// Supports math expressions like "value * 1.94384" or "(value - 273.15) * 9/5 + 32"
  double _evaluateFormula(String formula, double value) {
    try {
      // Replace 'value' with the actual numeric value
      final expression = formula.replaceAll('value', value.toString());

      // Parse and evaluate
      final parser = Parser();
      final exp = parser.parse(expression);
      final cm = ContextModel();
      return exp.evaluate(EvaluationType.REAL, cm);
    } catch (e) {
      // If parsing fails, try simple multiplication pattern
      final match = RegExp(r'value\s*\*\s*([\d.]+)').firstMatch(formula);
      if (match != null) {
        final factor = double.tryParse(match.group(1)!);
        if (factor != null) return value * factor;
      }
      rethrow;
    }
  }

  /// Serialize to JSON for caching.
  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'baseUnit': baseUnit,
      'targetUnit': targetUnit,
      'category': category,
      'formula': formula,
      'inverseFormula': inverseFormula,
      'symbol': symbol,
      'displayFormat': displayFormat,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  /// Deserialize from JSON cache.
  factory PathMetadata.fromJson(Map<String, dynamic> json) {
    return PathMetadata(
      path: json['path'] as String,
      baseUnit: json['baseUnit'] as String?,
      targetUnit: json['targetUnit'] as String?,
      category: json['category'] as String?,
      formula: json['formula'] as String?,
      inverseFormula: json['inverseFormula'] as String?,
      symbol: json['symbol'] as String?,
      displayFormat: json['displayFormat'] as String?,
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.tryParse(json['lastUpdated'] as String)
          : null,
    );
  }

  @override
  String toString() {
    return 'PathMetadata(path: $path, category: $category, '
        'formula: $formula, symbol: $symbol)';
  }
}
