import '../enums.dart';
import '../feature.dart';
import '../instruction.dart';
import '../options.dart';

S52Symbol _sy(String name) => S52Symbol(name: name, raw: 'SY($name)');

/// Helper: line-geometry branch of QUAPOS01. Mirrors Freeboard-SK's
/// `GetCSQQUALIN01`. Preserves two Freeboard quirks verbatim:
///
///   1. Emits `LC(LOWACC21` with a missing closing paren (the
///      literal from the JS source). The raw field preserves the
///      literal for diagnostics.
///   2. The CONRAD branch for COALNE is effectively dead: the JS
///      guards `if (featureProperties['CONRAD'])` but then assigns
///      `quapos = parseFloat(CONRAD)` and `bquapos = true` instead
///      of `conrad` / `bconrad`, so `bconrad` stays false and the
///      block falls through to the plain-solid branch.
List<S52Instruction> _qqualin01(S52Feature feature, S52Options options) {
  if (feature.hasAttr('QUAPOS')) {
    final quapos = feature.attrDouble('QUAPOS');
    if (quapos >= 2 && quapos < 10) {
      return const [
        S52LineComplex(patternName: 'LOWACC21', raw: 'LC(LOWACC21'),
      ];
    }
    return const [];
  }
  if (feature.effectiveLayerName == 'COALNE') {
    // The CONRAD cascade is unreachable in Freeboard due to the
    // documented copy-paste bug. Both active and intended branches
    // collapse to the same plain solid line, so V1 parity holds.
    return const [
      S52LineStyle(
        pattern: S52LinePattern.solid,
        width: 1,
        colorCode: 'CSTLN',
        raw: 'LS(SOLD,1,CSTLN)',
      ),
    ];
  }
  return const [
    S52LineStyle(
      pattern: S52LinePattern.solid,
      width: 1,
      colorCode: 'CSTLN',
      raw: 'LS(SOLD,1,CSTLN)',
    ),
  ];
}

/// Helper: point-geometry branch of QUAPOS01. Mirrors Freeboard-SK's
/// `GetCSQQUAPNT01`.
///
/// When QUAPOS is in \[2, 10) the feature is "inaccurate" and
/// nothing is drawn (Freeboard's `accurate = false` branch falls out
/// of the switch without pushing). When QUAPOS is outside that
/// range (accurate), pick a symbol from:
///
///   * 4           → `SY(QUAPOS01)`
///   * 5           → `SY(QUAPOS02)`
///   * 7 or 8      → `SY(QUAPOS03)`
///   * any other   → `SY(LOWACC03)`
///
/// When QUAPOS is absent → nothing drawn.
List<S52Instruction> _qquapnt01(S52Feature feature, S52Options options) {
  if (!feature.hasAttr('QUAPOS')) return const [];
  final quapos = feature.attrInt('QUAPOS');
  if (quapos >= 2 && quapos < 10) return const [];
  switch (quapos) {
    case 4:
      return [_sy('QUAPOS01')];
    case 5:
      return [_sy('QUAPOS02')];
    case 7:
    case 8:
      return [_sy('QUAPOS03')];
    default:
      return [_sy('LOWACC03')];
  }
}

/// Conditional symbology procedure **QUAPOS01**.
///
/// Positional-quality annotations. Dispatches to the line or point
/// helper based on geometry. Mirrors Freeboard-SK's `GetCSQUAPOS01`.
List<S52Instruction> quapos01(S52Feature feature, S52Options options) {
  if (feature.geometryType == S52GeometryType.line) {
    return _qqualin01(feature, options);
  }
  return _qquapnt01(feature, options);
}
