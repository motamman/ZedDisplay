import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:math_expressions/math_expressions.dart';
import '../services/signalk_service.dart';

/// Weather field type for fallback conversions
enum WeatherFieldType {
  temperature, // K → user preference (F, C)
  speed,       // m/s → user preference (kn, mph, m/s)
  pressure,    // Pa → user preference (hPa, mbar, inHg)
  angle,       // rad → deg
  percentage,  // ratio → %
}

/// Simple conversion formula holder
class _ConversionFormula {
  final String formula;
  final String symbol;
  const _ConversionFormula(this.formula, this.symbol);
}

/// Cached unit categories from server
class UnitCategories {
  final Map<String, dynamic> categories;
  final DateTime fetchedAt;

  UnitCategories(this.categories) : fetchedAt = DateTime.now();

  bool get isStale => DateTime.now().difference(fetchedAt).inMinutes > 30;

  String? getTargetUnit(String category) {
    final cat = categories[category];
    if (cat is Map) {
      return cat['targetUnit'] as String?;
    }
    return null;
  }
}

/// Cached user unit preferences (from user login)
class UserUnitPreferences {
  final Map<String, dynamic> preset;
  final String presetName;

  UserUnitPreferences(this.preset, this.presetName);

  /// Get target unit for a category from user's preset
  String? getTargetUnit(String category) {
    final cat = preset[category];
    if (cat is Map) {
      return cat['targetUnit'] as String?;
    }
    return null;
  }
}

/// Utility for applying client-side unit conversions using formulas from SignalK server
class ConversionUtils {
  // Cache for unit categories (server-wide defaults)
  static UnitCategories? _categoriesCache;

  // Cache for user-specific preferences (when logged in with user auth)
  static UserUnitPreferences? _userPreferencesCache;

  /// Standard SI unit conversion formulas
  static const Map<String, Map<String, _ConversionFormula>> _standardConversions = {
    'temperature': {
      'F': _ConversionFormula('(value - 273.15) * 9/5 + 32', '°F'),
      'C': _ConversionFormula('value - 273.15', '°C'),
      'K': _ConversionFormula('value', 'K'),
    },
    'speed': {
      'kn': _ConversionFormula('value * 1.94384', 'kn'),
      'mph': _ConversionFormula('value * 2.23694', 'mph'),
      'm/s': _ConversionFormula('value', 'm/s'),
      'km/h': _ConversionFormula('value * 3.6', 'km/h'),
    },
    'pressure': {
      'hPa': _ConversionFormula('value / 100', 'hPa'),
      'mbar': _ConversionFormula('value / 100', 'mbar'),
      'inHg': _ConversionFormula('value * 0.0002953', 'inHg'),
      'psi': _ConversionFormula('value * 0.000145038', 'psi'),
      'Pa': _ConversionFormula('value', 'Pa'),
    },
    'angle': {
      'degree': _ConversionFormula('value * 180 / 3.14159265359', '°'),
      'deg': _ConversionFormula('value * 180 / 3.14159265359', '°'),
      'rad': _ConversionFormula('value', 'rad'),
    },
    'percentage': {
      'percent': _ConversionFormula('value * 100', '%'),
      '%': _ConversionFormula('value * 100', '%'),
      'ratio': _ConversionFormula('value', ''),
    },
  };

  /// Fetch unit categories from server
  static Future<void> fetchCategories(SignalKService service) async {
    if (_categoriesCache != null && !_categoriesCache!.isStale) {
      return; // Use cached
    }

    try {
      final serverUrl = service.serverUrl;
      final useSecure = service.useSecureConnection;
      final host = serverUrl.replaceAll(RegExp(r'^wss?://|^https?://'), '').split('/').first;
      final scheme = useSecure ? 'https' : 'http';

      final url = '$scheme://$host/plugins/signalk-units-preference/categories';

      final response = await http.get(
        Uri.parse(url),
        headers: service.authToken != null
            ? {'Authorization': 'Bearer ${service.authToken!.token}'}
            : null,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic>) {
          _categoriesCache = UnitCategories(data);
          if (kDebugMode) {
            print('ConversionUtils: Loaded ${data.length} unit categories from server');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('ConversionUtils: Error fetching categories: $e');
      }
    }
  }

  /// Load user unit preferences from cached storage
  /// Call this after user login to enable user-specific conversions
  static void loadUserPreferences(SignalKService service) {
    final userPreset = service.getCachedUserUnitPreferences();
    final presetName = service.getCachedUserPresetName();

    if (userPreset != null && presetName != null) {
      _userPreferencesCache = UserUnitPreferences(userPreset, presetName);
      if (kDebugMode) {
        print('ConversionUtils: Loaded user preferences (preset: $presetName)');
      }
    } else {
      _userPreferencesCache = null;
    }
  }

  /// Clear user preferences cache (call on logout or switch to device auth)
  static void clearUserPreferences() {
    _userPreferencesCache = null;
    if (kDebugMode) {
      print('ConversionUtils: User preferences cleared');
    }
  }

  /// Check if user preferences are loaded
  static bool get hasUserPreferences => _userPreferencesCache != null;

  /// Get target unit for a category, preferring user preferences over server defaults
  static String? _getTargetUnitForCategory(String category) {
    // Priority: User preferences > Server categories > null
    if (_userPreferencesCache != null) {
      final userTarget = _userPreferencesCache!.getTargetUnit(category);
      if (userTarget != null) {
        return userTarget;
      }
    }

    if (_categoriesCache != null) {
      return _categoriesCache!.getTargetUnit(category);
    }

    return null;
  }

  /// Convert weather value using fallback conversions
  /// Uses server preferences if available, otherwise uses sensible defaults
  static double? convertWeatherValue(
    SignalKService service,
    WeatherFieldType fieldType,
    double rawValue,
  ) {
    String category;
    String defaultTarget;

    switch (fieldType) {
      case WeatherFieldType.temperature:
        category = 'temperature';
        defaultTarget = 'F';
        break;
      case WeatherFieldType.speed:
        category = 'speed';
        defaultTarget = 'kn';
        break;
      case WeatherFieldType.pressure:
        category = 'pressure';
        defaultTarget = 'hPa';
        break;
      case WeatherFieldType.angle:
        category = 'angle';
        defaultTarget = 'degree';
        break;
      case WeatherFieldType.percentage:
        category = 'percentage';
        defaultTarget = 'percent';
        break;
    }

    // Try to get user's preferred target unit (user prefs > server > default)
    String targetUnit = _getTargetUnitForCategory(category) ?? defaultTarget;

    // Get conversion formula
    final categoryConversions = _standardConversions[category];
    if (categoryConversions == null) {
      return rawValue;
    }

    final conversion = categoryConversions[targetUnit] ?? categoryConversions[defaultTarget];
    if (conversion == null) {
      return rawValue;
    }

    return evaluateFormula(conversion.formula, rawValue);
  }

  /// Get unit symbol for weather field type
  static String getWeatherUnitSymbol(WeatherFieldType fieldType) {
    String category;
    String defaultTarget;

    switch (fieldType) {
      case WeatherFieldType.temperature:
        category = 'temperature';
        defaultTarget = 'F';
        break;
      case WeatherFieldType.speed:
        category = 'speed';
        defaultTarget = 'kn';
        break;
      case WeatherFieldType.pressure:
        category = 'pressure';
        defaultTarget = 'hPa';
        break;
      case WeatherFieldType.angle:
        category = 'angle';
        defaultTarget = 'degree';
        break;
      case WeatherFieldType.percentage:
        category = 'percentage';
        defaultTarget = 'percent';
        break;
    }

    // Try to get user's preferred target unit (user prefs > server > default)
    String targetUnit = _getTargetUnitForCategory(category) ?? defaultTarget;

    // Get symbol
    final categoryConversions = _standardConversions[category];
    if (categoryConversions == null) {
      return '';
    }

    final conversion = categoryConversions[targetUnit] ?? categoryConversions[defaultTarget];
    return conversion?.symbol ?? '';
  }
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
