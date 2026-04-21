import '../enums.dart';
import '../feature.dart';
import '../instruction.dart';
import '../options.dart';

/// Conditional symbology procedure **SLCONS03**.
///
/// Styles shoreline-construction features (SLCONS) — breakwaters,
/// piers, dams, pontoons, etc. Mirrors Freeboard-SK's `GetCSSLCONS03`
/// verbatim, including two historical quirks that V1 ships:
///
///   1. The area-geometry branch emits `AP(CROSSX01` with a missing
///      closing paren. Freeboard's JS literal is the same — the
///      instruction is typed here as a proper [S52AreaPattern] but
///      the `raw` diagnostic string preserves the missing paren for
///      traceability.
///   2. Inside the non-QUAPOS / non-point path, the outer guard
///      `if (featureProperties['QUAPOS'])` is a copy-paste bug — it
///      should read `CONDTN`. Preserved for V1 parity: the CONDTN
///      branch only fires when the feature has *both* QUAPOS and
///      CONDTN set. Documented so a future fidelity pass can find it.
///
/// Behaviour:
///
///   * **Point** + QUAPOS in \[2, 10) → `SY(LOWACC01)`.
///   * **Line / Polygon** with QUAPOS in \[2, 10) → `LC(LOWACC01)`.
///   * **Polygon** additionally prepends `AP(CROSSX01` (hatched fill).
///   * Otherwise falls through a CONDTN / CATSLC / WATLEV cascade to
///     pick an appropriate line style.
List<S52Instruction> slcons03(S52Feature feature, S52Options options) {
  final hasQuapos = feature.hasAttr('QUAPOS');
  final quapos = hasQuapos ? feature.attrDouble('QUAPOS') : 0.0;

  if (feature.geometryType == S52GeometryType.point) {
    if (hasQuapos && quapos >= 2 && quapos < 10) {
      return const [
        S52Symbol(name: 'LOWACC01', raw: 'SY(LOWACC01)'),
      ];
    }
    return const [];
  }

  final out = <S52Instruction>[];
  if (feature.geometryType == S52GeometryType.area) {
    out.add(const S52AreaPattern(
      patternName: 'CROSSX01',
      // Raw preserves Freeboard's missing-paren literal for diagnostics.
      raw: 'AP(CROSSX01',
    ));
  }

  if (hasQuapos && quapos >= 2 && quapos < 10) {
    out.add(const S52LineComplex(
      patternName: 'LOWACC01',
      raw: 'LC(LOWACC01)',
    ));
    return out;
  }

  // Freeboard parity quirk: the CONDTN branch is gated by a stale
  // `QUAPOS` check (copy-paste bug in the source). Preserved so V1
  // and V2 render the same feature set.
  final legacyCondtnGate = feature.hasAttr('QUAPOS');
  if (legacyCondtnGate && feature.hasAttr('CONDTN')) {
    final condtn = feature.attrInt('CONDTN');
    if (condtn == 1 || condtn == 2) {
      out.add(const S52LineStyle(
        pattern: S52LinePattern.dash,
        width: 1,
        colorCode: 'CSTLN',
        raw: 'LS(DASH,1,CSTLN)',
      ));
      return out;
    }
  }

  if (feature.hasAttr('CATSLC')) {
    final catslc = feature.attrInt('CATSLC');
    if (catslc == 6 || catslc == 15 || catslc == 16) {
      out.add(const S52LineStyle(
        pattern: S52LinePattern.solid,
        width: 4,
        colorCode: 'CSTLN',
        raw: 'LS(SOLD,4,CSTLN)',
      ));
      return out;
    }
  }

  if (feature.hasAttr('WATLEV')) {
    final watlev = feature.attrInt('WATLEV');
    if (watlev == 2) {
      out.add(const S52LineStyle(
        pattern: S52LinePattern.solid,
        width: 2,
        colorCode: 'CSTLN',
        raw: 'LS(SOLD,2,CSTLN)',
      ));
      return out;
    }
    if (watlev == 3 || watlev == 4) {
      out.add(const S52LineStyle(
        pattern: S52LinePattern.dash,
        width: 2,
        colorCode: 'CSTLN',
        raw: 'LS(DASH,2,CSTLN)',
      ));
      return out;
    }
  }

  out.add(const S52LineStyle(
    pattern: S52LinePattern.solid,
    width: 2,
    colorCode: 'CSTLN',
    raw: 'LS(SOLD,2,CSTLN)',
  ));
  return out;
}
