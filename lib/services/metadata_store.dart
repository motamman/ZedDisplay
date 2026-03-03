import 'package:flutter/foundation.dart';
import '../models/path_metadata.dart';

/// Single source of truth for all path metadata and conversion formulas.
/// Populated from WebSocket meta deltas (sendMeta=all).
///
/// This store unifies all conversion data that was previously scattered across:
/// - _displayUnitsCache (in SignalKService)
/// - _ConversionManager (legacy PathConversionData + unitpreferences)
///
/// Data flow:
/// WebSocket Meta Delta → updateFromMeta() → PathMetadata → notifyListeners()
class MetadataStore extends ChangeNotifier {
  final Map<String, PathMetadata> _metadata = {};

  /// Update metadata from WebSocket meta delta.
  /// Called when a meta entry with displayUnits is received.
  ///
  /// [path] - The SignalK path (e.g., "navigation.speedOverGround")
  /// [displayUnits] - The displayUnits object from meta:
  ///   {units: "kn", formula: "value * 1.94384", symbol: "kn", ...}
  /// [category] - Optional category if known from default-categories
  void updateFromMeta(
    String path,
    Map<String, dynamic> displayUnits, {
    String? category,
  }) {
    final existing = _metadata[path];
    final newMetadata = PathMetadata.fromDisplayUnits(
      path,
      displayUnits,
      category: category ?? existing?.category,
    );

    // Only update and notify if something changed
    if (_hasChanged(existing, newMetadata)) {
      _metadata[path] = newMetadata;
      notifyListeners();
    }
  }

  /// Update metadata with a pre-built PathMetadata object.
  void update(PathMetadata metadata) {
    final existing = _metadata[metadata.path];
    if (_hasChanged(existing, metadata)) {
      _metadata[metadata.path] = metadata;
      notifyListeners();
    }
  }

  /// Check if metadata has meaningfully changed.
  bool _hasChanged(PathMetadata? existing, PathMetadata updated) {
    if (existing == null) return true;
    return existing.formula != updated.formula ||
        existing.inverseFormula != updated.inverseFormula ||
        existing.symbol != updated.symbol ||
        existing.targetUnit != updated.targetUnit ||
        existing.category != updated.category;
  }

  /// Get metadata for a path.
  PathMetadata? get(String path) => _metadata[path];

  /// Check if metadata exists for a path.
  bool has(String path) => _metadata.containsKey(path);

  /// Get all paths with metadata.
  List<String> get paths => _metadata.keys.toList();

  /// Get all metadata entries.
  Iterable<PathMetadata> get all => _metadata.values;

  /// Get metadata count.
  int get count => _metadata.length;

  /// Check if store is empty.
  bool get isEmpty => _metadata.isEmpty;

  /// Check if store has data.
  bool get isNotEmpty => _metadata.isNotEmpty;

  /// Convert a value using the formula for a path.
  /// Returns the converted value, or the raw value if no conversion available.
  double? convert(String path, double siValue) {
    final metadata = _metadata[path];
    if (metadata == null) return siValue;
    return metadata.convert(siValue);
  }

  /// Convert a display value back to SI using the inverse formula.
  /// Returns the SI value, or the display value if no conversion available.
  double? convertToSI(String path, double displayValue) {
    final metadata = _metadata[path];
    if (metadata == null) return displayValue;
    return metadata.convertToSI(displayValue);
  }

  /// Format a value with its unit symbol.
  String format(String path, double siValue, {int decimals = 1}) {
    final metadata = _metadata[path];
    if (metadata == null) return siValue.toStringAsFixed(decimals);
    return metadata.format(siValue, decimals: decimals);
  }

  /// Get the unit symbol for a path.
  String? getSymbol(String path) => _metadata[path]?.symbol;

  /// Get the formula for a path.
  String? getFormula(String path) => _metadata[path]?.formula;

  /// Get the inverse formula for a path.
  String? getInverseFormula(String path) => _metadata[path]?.inverseFormula;

  /// Get the category for a path.
  String? getCategory(String path) => _metadata[path]?.category;

  /// Get the first metadata entry matching a category.
  /// Used for category-based conversions (e.g., distance, speed).
  PathMetadata? getByCategory(String category) {
    for (final metadata in _metadata.values) {
      if (metadata.category == category) {
        return metadata;
      }
    }
    return null;
  }

  /// Clear all metadata.
  void clear() {
    if (_metadata.isNotEmpty) {
      _metadata.clear();
      notifyListeners();
    }
  }

  /// Remove metadata for a specific path.
  void remove(String path) {
    if (_metadata.remove(path) != null) {
      notifyListeners();
    }
  }

  /// Bulk update from a map of path -> displayUnits.
  /// Used when loading from cache.
  void updateFromMap(Map<String, Map<String, dynamic>> displayUnitsMap) {
    bool changed = false;
    for (final entry in displayUnitsMap.entries) {
      final path = entry.key;
      final displayUnits = entry.value;
      final existing = _metadata[path];
      final newMetadata = PathMetadata.fromDisplayUnits(path, displayUnits);

      if (_hasChanged(existing, newMetadata)) {
        _metadata[path] = newMetadata;
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  /// Export all metadata to a map for caching.
  Map<String, Map<String, dynamic>> toMap() {
    final map = <String, Map<String, dynamic>>{};
    for (final entry in _metadata.entries) {
      map[entry.key] = entry.value.toJson();
    }
    return map;
  }

  /// Load metadata from a cached map.
  void loadFromCache(Map<String, dynamic> cached) {
    bool changed = false;
    for (final entry in cached.entries) {
      if (entry.value is Map<String, dynamic>) {
        try {
          final metadata = PathMetadata.fromJson(entry.value as Map<String, dynamic>);
          final existing = _metadata[metadata.path];
          if (_hasChanged(existing, metadata)) {
            _metadata[metadata.path] = metadata;
            changed = true;
          }
        } catch (e) {
          // Skip invalid entries
          if (kDebugMode) {
            print('MetadataStore: Error loading cached entry ${entry.key}: $e');
          }
        }
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _metadata.clear();
    super.dispose();
  }

  @override
  String toString() {
    return 'MetadataStore(${_metadata.length} paths)';
  }
}
