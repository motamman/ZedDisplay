import 'enums.dart';

/// An S-57 feature as presented to the style engine: the object class
/// name, the geometry type, and a map of attribute values.
///
/// Attribute values are held as `Object?` because the source MVT tile
/// data may deliver numeric attributes as strings (common in S-57
/// encoders) or native numbers depending on the producer. The engine
/// and CS procedures do their own typed coercion.
///
/// This class is deliberately decoupled from any tile-parsing library.
/// Consumers (the WebView bridge, a `vector_map_tiles` adapter, etc.)
/// convert their native feature representation into [S52Feature]
/// before handing it to the engine.
class S52Feature {
  const S52Feature({
    required this.objectClass,
    required this.geometryType,
    this.attributes = const {},
    this.layerName,
  });

  /// Six-character S-57 object class code (`DEPARE`, `LIGHTS`, etc.).
  /// Normally equal to the feature's MVT layer name.
  final String objectClass;

  /// Geometry type this feature's geometry represents.
  final S52GeometryType geometryType;

  /// Feature attribute map. Keys are S-57 attribute codes (`DRVAL1`,
  /// `COLOUR`, `CATLIT`, …). Values may be [String], [num], [bool],
  /// [List], or nested [Map] per the tile encoder.
  final Map<String, Object?> attributes;

  /// Optional layer name from the MVT tile. Some CS procedures (e.g.
  /// `TOPMAR01`) distinguish floating vs non-floating topmarks by
  /// looking at the parent layer (`LITFLT`, `LITVES`, `BOY*`).
  /// Defaults to [objectClass] for simple cases.
  final String? layerName;

  /// Returns [layerName] if set, else [objectClass].
  String get effectiveLayerName => layerName ?? objectClass;

  /// Read an attribute as a [String]. Missing or null values return
  /// the empty string. Non-string values are stringified via
  /// [Object.toString].
  String attrString(String key) => attributes[key]?.toString() ?? '';

  /// Read an attribute as a [double]. Accepts either a numeric value
  /// or a string containing a decimal number. Missing, null, or
  /// unparseable values return [fallback].
  double attrDouble(String key, {double fallback = 0.0}) {
    final v = attributes[key];
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  /// Read an attribute as an [int]. Accepts either a numeric value or
  /// a string containing an integer. Missing, null, or unparseable
  /// values return [fallback].
  int attrInt(String key, {int fallback = 0}) {
    final v = attributes[key];
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  /// Read a multi-value attribute (comma-delimited in S-57) as a list
  /// of trimmed tokens. For example a feature with `COLOUR="1,3"`
  /// returns `['1', '3']`. A missing attribute returns an empty list.
  List<String> attrList(String key) {
    final raw = attrString(key);
    if (raw.isEmpty) return const [];
    return raw.split(',').map((s) => s.trim()).toList(growable: false);
  }

  /// True when the attribute is present and non-empty (or numeric).
  bool hasAttr(String key) {
    final v = attributes[key];
    if (v == null) return false;
    if (v is String) return v.isNotEmpty;
    return true;
  }

  @override
  String toString() =>
      'S52Feature($objectClass/$geometryType attrs=$attributes)';
}
