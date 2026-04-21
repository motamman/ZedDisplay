import 'enums.dart';

/// One S-52 attribute qualifier parsed from the lookup JSON.
///
/// The raw asset stores qualifiers as `{index: "NAMEpattern"}` where
/// `NAME` is a 6-character S-57 attribute code and `pattern` is the
/// remainder — either a literal value, a comma-delimited list, the
/// wildcard `?`, the always-match blank ` `, or empty. We parse once
/// at load time and retain both the structured form and the raw
/// source for diagnostics.
class AttributeQualifier {
  const AttributeQualifier({
    required this.name,
    required this.pattern,
    required this.raw,
  });

  final String name;
  final String pattern;

  /// Original `"NAMEpattern"` string from the lookup JSON.
  final String raw;

  static final RegExp _splitPattern = RegExp(r'^([A-Za-z0-9]{6})([0-9,?]*)$');

  /// Parse a raw qualifier string like `"DRVAL1?"`, `"COLOUR1,3"`,
  /// `"CATACH1"`. Returns `null` when the input doesn't match the
  /// expected grammar (defensive — shouldn't happen for authored S-52
  /// lookup tables, but preserves information for hand-edited data).
  static AttributeQualifier? tryParse(String raw) {
    final m = _splitPattern.firstMatch(raw);
    if (m == null) return null;
    return AttributeQualifier(
      name: m.group(1)!.toUpperCase(),
      pattern: m.group(2)!,
      raw: raw,
    );
  }

  @override
  String toString() => 'AttributeQualifier($name="$pattern")';
}

/// A single row in the S-52 lookup table. Each row describes how a
/// feature of a given S-57 object class (e.g. `DEPARE`, `LIGHTS`) with a
/// given geometry type and optional attribute qualifiers should be
/// rendered — the [instruction] field contains S-52 instruction strings
/// (SY/LS/LC/AC/AP/TX/TE/CS) concatenated by `;`.
///
/// Multiple rows may share the same (name, geometryType, tableKind)
/// triple. The matcher chooses the row whose [qualifiers] are all
/// satisfied by the feature, falling back to a row with empty
/// qualifiers (the default).
class LookupRow {
  const LookupRow({
    required this.id,
    required this.name,
    required this.geometryType,
    required this.tableKind,
    required this.displayCategory,
    required this.displayPriority,
    required this.instruction,
    this.qualifiers = const [],
  });

  /// Stable numeric identifier from the generator script. Useful for
  /// debugging but not otherwise meaningful — callers should match on
  /// (name, geometryType, tableKind, qualifiers).
  final int id;

  /// 6-character S-57 object class code — `DEPARE`, `LIGHTS`, `ACHARE`.
  final String name;

  /// Geometry the row applies to.
  final S52GeometryType geometryType;

  /// Which S-52 lookup table variant this row belongs to.
  final S52LookupTableKind tableKind;

  /// Display category — used to filter rows based on user setting
  /// (base / standard / all).
  final S52DisplayCategory displayCategory;

  /// Rendering priority within the layer.
  final S52DisplayPriority displayPriority;

  /// Attribute qualifiers for matching. Empty list = the fallback row
  /// that matches whenever (name, geometryType, tableKind) agrees.
  /// Otherwise each qualifier is tested against the feature's
  /// attributes; see [LookupTable.bestMatch] for the semantics.
  final List<AttributeQualifier> qualifiers;

  /// S-52 instruction string. May contain multiple instructions joined
  /// by `;` — e.g. `"AC(DEPVS);LS(SOLD,1,DEPCN)"`. Some rows include a
  /// `CS(PROC)` instruction which the style engine dispatches to the
  /// per-feature conditional symbology procedures.
  final String instruction;

  factory LookupRow.fromJson(Map<String, dynamic> json) {
    final rawAttrs = json['attributes'] as Map<String, dynamic>? ?? const {};
    final qualifiers = <AttributeQualifier>[];
    for (final e in rawAttrs.entries) {
      final parsed = AttributeQualifier.tryParse(e.value.toString());
      if (parsed != null) qualifiers.add(parsed);
    }
    return LookupRow(
      id: json['id'] as int,
      name: (json['name'] as String).toUpperCase(),
      geometryType: S52GeometryType.fromCode(json['geometryType'] as int),
      tableKind: S52LookupTableKind.fromCode(json['lookupTable'] as int),
      displayCategory:
          S52DisplayCategory.fromCode(json['displayCategory'] as int),
      displayPriority:
          S52DisplayPriority.fromCode(json['displayPriority'] as int),
      instruction: json['instruction'] as String? ?? '',
      qualifiers: List.unmodifiable(qualifiers),
    );
  }

  @override
  String toString() =>
      'LookupRow(#$id $name/$geometryType/$tableKind cat=$displayCategory '
      'qualifiers=$qualifiers instr="$instruction")';
}

/// The full S-52 lookup table indexed by (tableKind, objectName,
/// geometryType). Building the table is an O(n) one-time walk of the
/// JSON entries that computes the start-index map used by the matcher.
///
/// The matcher is two-phase:
///   1. Use [rowsFor] to narrow rows to a single (tableKind, name,
///      geometryType) triple. This is O(1) via the start-index map
///      plus a short linear scan on the flat `rows` list.
///   2. Call [bestMatch] to pick the row whose attribute qualifiers are
///      all satisfied by the feature, preferring rows with more
///      qualifiers, falling back to the attribute-free default row.
class LookupTable {
  LookupTable({
    required List<LookupRow> rows,
    required Map<String, int> startIndex,
  })  : _rows = List.unmodifiable(rows),
        _startIndex = Map.unmodifiable(startIndex);

  /// Construct from the `s57_lookups.json` asset. Shape:
  /// ```
  /// {
  ///   "lookups": [ { ...row... }, ... ],
  ///   "lookupStartIndex": { "0,ACHARE,0": 0, "0,ACHBRT,0": 2, ... }
  /// }
  /// ```
  factory LookupTable.fromJson(Map<String, dynamic> json) {
    final rawRows = json['lookups'] as List<dynamic>;
    final rows = rawRows
        .map((e) => LookupRow.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    final rawIndex = json['lookupStartIndex'] as Map<String, dynamic>;
    final index = <String, int>{
      for (final e in rawIndex.entries) e.key: e.value as int,
    };
    return LookupTable(rows: rows, startIndex: index);
  }

  final List<LookupRow> _rows;
  final Map<String, int> _startIndex;

  /// Raw count of lookup rows.
  int get length => _rows.length;

  /// Key format expected by [_startIndex]: `"tableKind,name,geometryType"`.
  static String _key(
    S52LookupTableKind tableKind,
    String name,
    S52GeometryType geom,
  ) =>
      '${tableKind.code},$name,${geom.code}';

  /// Return the contiguous slice of rows that match a given
  /// (tableKind, name, geometryType) triple. May be empty.
  ///
  /// Rows in the asset are sorted such that all rows with the same
  /// triple live in one contiguous run, so once we know the start
  /// index we can scan forward until the triple no longer matches.
  List<LookupRow> rowsFor(
    S52LookupTableKind tableKind,
    String name,
    S52GeometryType geom,
  ) {
    final start = _startIndex[_key(tableKind, name, geom)];
    if (start == null) return const [];

    final out = <LookupRow>[];
    for (var i = start; i < _rows.length; i++) {
      final r = _rows[i];
      if (r.tableKind != tableKind ||
          r.name != name ||
          r.geometryType != geom) {
        break;
      }
      out.add(r);
    }
    return out;
  }

  /// Pick the best lookup row for a feature. Mirrors Freeboard-SK's
  /// JS matcher semantics verbatim — which is what V1 ships — so that
  /// observed rendering parity holds.
  ///
  /// Algorithm:
  ///   1. Iterate rows for the (tableKind, name, geometry) triple.
  ///   2. For each row, tally how many of its qualifiers are
  ///      satisfied by the feature:
  ///        - Pattern `' '` (blank) → counts as satisfied.
  ///        - Pattern `'?'` → no-op, never counts. (Per Freeboard's
  ///          implementation this means rows containing any `?`
  ///          qualifier can never win the attribute-specific match
  ///          — those rows are unreachable in practice. Preserved
  ///          here for fidelity to V1.)
  ///        - Any other pattern → compared to feature attribute value
  ///          via [propertyCompare]; counts when equal.
  ///   3. A row only wins the attribute-specific match when every
  ///      one of its qualifiers is satisfied. Higher qualifier count
  ///      wins ties.
  ///   4. If no row wins the attribute-specific pass, fall back to
  ///      the first row with empty qualifiers.
  ///
  /// Returns null when no row — specific or fallback — is available.
  LookupRow? bestMatch(
    S52LookupTableKind tableKind,
    String name,
    S52GeometryType geom,
    Map<String, Object?> featureAttributes,
  ) {
    final rows = rowsFor(tableKind, name, geom);
    if (rows.isEmpty) return null;

    LookupRow? best;
    var bestMatchCount = -1;

    for (final row in rows) {
      if (row.qualifiers.isEmpty) continue; // fallback candidate only
      var matched = 0;
      for (final q in row.qualifiers) {
        if (q.pattern == ' ') {
          matched++;
          continue;
        }
        if (q.pattern == '?') continue; // per JS, never counts
        final actual = featureAttributes[q.name];
        if (actual == null) continue;
        if (propertyCompare(actual, q.pattern) == 0) matched++;
      }
      if (matched == row.qualifiers.length && matched > bestMatchCount) {
        best = row;
        bestMatchCount = matched;
      }
    }
    if (best != null) return best;

    // Fallback: first empty-qualifier row.
    for (final row in rows) {
      if (row.qualifiers.isEmpty) return row;
    }
    return null;
  }

  /// Three-way compare of a feature attribute value [a] against a
  /// qualifier pattern [b]. Mirrors Freeboard's `propertyCompare`:
  ///
  ///   * If `a` is a number, compare numerically against `parseInt(b)`.
  ///   * Otherwise compare as strings.
  ///   * Non-comparable (e.g. null) → non-zero (no match).
  ///
  /// Zero indicates equality; sign is arbitrary but stable for a
  /// given input. Exposed (static, pure) so engine-adjacent code can
  /// share the same semantics.
  static int propertyCompare(Object? a, String b) {
    if (a is num) {
      final bInt = int.tryParse(b);
      if (bInt == null) return -1;
      return a.toInt() - bInt;
    }
    if (a is String) return a.compareTo(b);
    return -1;
  }

  /// Unmodifiable view of all rows.
  List<LookupRow> get rows => _rows;
}
