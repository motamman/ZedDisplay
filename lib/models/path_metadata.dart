import 'package:math_expressions/math_expressions.dart';

/// A SignalK zone — a value range with an alarm state.
class PathZone {
  final double? lower;
  final double? upper;
  final String state; // nominal, normal, alert, warn, alarm, emergency
  final String message;

  const PathZone({this.lower, this.upper, required this.state, this.message = ''});

  factory PathZone.fromJson(Map<String, dynamic> json) => PathZone(
        lower: (json['lower'] as num?)?.toDouble(),
        upper: (json['upper'] as num?)?.toDouble(),
        state: json['state'] as String? ?? 'nominal',
        message: json['message'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'lower': lower,
        'upper': upper,
        'state': state,
        'message': message,
      };
}

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
  final List<PathZone>? zones;  // Alarm zones (from server meta)
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
    this.zones,
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  /// Create from WebSocket meta displayUnits object.
  /// Expected format: {units: "kn", formula: "value * 1.94384", symbol: "kn", ...}
  factory PathMetadata.fromDisplayUnits(
    String path,
    Map<String, dynamic> displayUnits, {
    String? category,
    List<PathZone>? zones,
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
      zones: zones,
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
    List<PathZone>? zones,
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
      zones: zones ?? this.zones,
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

  /// Process-wide cache of compiled formula expressions.
  ///
  /// Keyed by the formula string so many [PathMetadata] instances that share
  /// a formula (e.g. every speed path using `value * 1.94384`) share one
  /// compiled expression. A `null` entry marks a formula that failed to
  /// parse, preventing repeated attempts.
  static final Map<String, Expression?> _formulaCache = {};

  /// Shared variable bound by [_evaluateFormula]. The compiled expression
  /// references this variable; evaluation binds a numeric value to it via
  /// the context model, avoiding the old "string-replace then re-parse"
  /// cost on every call.
  static final Variable _valueVar = Variable('value');

  /// Evaluate a formula string with a given value.
  ///
  /// Compiles on first use (shared via [_formulaCache]); on subsequent
  /// calls reuses the cached [Expression]. On parse failure, caches `null`
  /// and throws so [convert]/[convertToSI] can return `null` to the caller.
  double _evaluateFormula(String formula, double value) {
    Expression? compiled;
    if (_formulaCache.containsKey(formula)) {
      compiled = _formulaCache[formula];
    } else {
      try {
        compiled = GrammarParser().parse(formula);
      } catch (_) {
        compiled = null;
      }
      _formulaCache[formula] = compiled;
    }

    if (compiled == null) {
      throw FormatException('Unparseable formula: $formula');
    }

    final cm = ContextModel()..bindVariable(_valueVar, Number(value));
    return RealEvaluator(cm).evaluate(compiled).toDouble();
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
      if (zones != null) 'zones': zones!.map((z) => z.toJson()).toList(),
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
      zones: (json['zones'] as List?)
          ?.map((z) => PathZone.fromJson(z as Map<String, dynamic>))
          .toList(),
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

/// Null-safe formatting that encodes the app-wide "permissive" fallback
/// policy: when metadata is missing, render the raw SI value with a
/// best-guess SI suffix; when the value itself is null, render the
/// placeholder. This collapses ~8 duplicated `_formatValue` helpers
/// scattered across tool widgets.
///
/// Behavior:
///
/// | metadata | siValue | output                                         |
/// |----------|---------|------------------------------------------------|
/// | null     | null    | [placeholder] (default: "--")                  |
/// | null     | x       | `x.toStringAsFixed(decimals) [siSuffix]`       |
/// | non-null | null    | [placeholder]                                  |
/// | non-null | x       | `metadata.format(x, decimals: decimals)`       |
///
/// [siSuffix] lets the caller hint the SI unit (e.g. "rad", "m/s", "m")
/// to render alongside the raw value when metadata is missing. When
/// omitted, no unit suffix is rendered — only the raw number.
extension MetadataFormatExtension on PathMetadata? {
  String formatOrRaw(
    double? siValue, {
    int decimals = 1,
    String? siSuffix,
    String placeholder = '--',
  }) {
    if (siValue == null) return placeholder;
    final self = this;
    if (self != null) return self.format(siValue, decimals: decimals);

    final suffix = siSuffix ?? '';
    if (suffix.isEmpty) return siValue.toStringAsFixed(decimals);
    return '${siValue.toStringAsFixed(decimals)} $suffix';
  }
}
