/// Integer-valued S-52 enums. Numeric values match the integers stored in
/// the lookup-table JSON assets; these values are wire-format, not
/// implementation details — changing them would break already-compiled
/// asset bundles.
library;

/// Geometry class for an S-57 feature.
enum S52GeometryType {
  point(0),
  line(1),
  area(2);

  const S52GeometryType(this.code);
  final int code;

  static S52GeometryType fromCode(int code) {
    for (final v in S52GeometryType.values) {
      if (v.code == code) return v;
    }
    throw ArgumentError.value(code, 'code', 'Unknown S52GeometryType');
  }
}

/// IHO S-52 display category. Used to decide whether a feature should be
/// drawn based on the user's selected display setting (base / standard /
/// all). DISPLAYBASE is the minimum safety-critical set and must always
/// render.
enum S52DisplayCategory {
  displayBase(0),
  standard(1),
  other(2),
  marinersStandard(3),
  marinersOther(4),
  dispCatNum(5);

  const S52DisplayCategory(this.code);
  final int code;

  static S52DisplayCategory fromCode(int code) {
    for (final v in S52DisplayCategory.values) {
      if (v.code == code) return v;
    }
    throw ArgumentError.value(code, 'code', 'Unknown S52DisplayCategory');
  }
}

/// IHO S-52 display priority. Lower priority renders first (underneath).
/// The values follow the IHO S-52 presentation library groupings.
enum S52DisplayPriority {
  /// No-data fill area pattern.
  noData(0),

  /// S-57 group 1 filled areas.
  group1(1),

  /// Superimposed areas.
  area1(2),

  /// Superimposed areas (water features).
  area2(3),

  /// Point symbols and land features.
  symbolPoint(4),

  /// Line symbols and restricted areas.
  symbolLine(5),

  /// Area symbols and traffic areas.
  symbolArea(6),

  /// Routeing lines.
  routeing(7),

  /// Hazards.
  hazards(8),

  /// VRM, EBL, own ship (mariner overlays).
  mariners(9);

  const S52DisplayPriority(this.code);
  final int code;

  static S52DisplayPriority fromCode(int code) {
    for (final v in S52DisplayPriority.values) {
      if (v.code == code) return v;
    }
    throw ArgumentError.value(code, 'code', 'Unknown S52DisplayPriority');
  }
}

/// IHO S-52 lookup table variant. Each S-57 object class has multiple
/// lookup tables for the presentation library; the active one depends
/// on user settings (simplified vs paper symbols, plain vs symbolised
/// boundaries).
enum S52LookupTableKind {
  simplified(0),
  paperChart(1),
  lines(2),
  plainBoundaries(3),
  symbolisedBoundaries(4);

  const S52LookupTableKind(this.code);
  final int code;

  static S52LookupTableKind fromCode(int code) {
    for (final v in S52LookupTableKind.values) {
      if (v.code == code) return v;
    }
    throw ArgumentError.value(code, 'code', 'Unknown S52LookupTableKind');
  }
}
