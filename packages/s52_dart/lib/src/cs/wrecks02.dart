import '../enums.dart';
import '../feature.dart';
import '../instruction.dart';
import '../options.dart';

S52Symbol _sy(String name) => S52Symbol(name: name, raw: 'SY($name)');

const _solidLineCstln = S52LineStyle(
  pattern: S52LinePattern.solid,
  width: 2,
  colorCode: 'CSTLN',
  raw: 'LS(SOLD,2,CSTLN)',
);

const _dashLineCstln = S52LineStyle(
  pattern: S52LinePattern.dash,
  width: 2,
  colorCode: 'CSTLN',
  raw: 'LS(DASH,2,CSTLN)',
);

const _dottLineCstln = S52LineStyle(
  pattern: S52LinePattern.dott,
  width: 2,
  colorCode: 'CSTLN',
  raw: 'LS(DOTT,2,CSTLN)',
);

/// Conditional symbology procedure **WRECKS02**.
///
/// Styles a wreck feature (WRECKS). Mirrors Freeboard-SK's
/// `GetCSWRECKS02`:
///
///   * **Point**: if VALSOU is known, use the danger threshold
///     (VALSOU ≤ 0 → dries; ≤ safety → DANGER51; > safety →
///     submerged). If VALSOU is missing, use CATWRK (1 = non-
///     dangerous → WRECKS05; 2 = dangerous → WRECKS01) with a
///     WATLEV fallback.
///   * **Area**: colour + outline keyed on WATLEV (covers-and-
///     uncovers → CHBRN/solid; always-underwater → DEPIT/dashed;
///     default → DEPVS/dotted).
List<S52Instruction> wrecks02(S52Feature feature, S52Options options) {
  final valsouRaw = feature.attrString('VALSOU');
  final valsou = valsouRaw.isEmpty ? null : double.tryParse(valsouRaw);
  final watlev = feature.hasAttr('WATLEV') ? feature.attrInt('WATLEV') : 0;
  final catwrk = feature.hasAttr('CATWRK') ? feature.attrInt('CATWRK') : 0;

  if (feature.geometryType == S52GeometryType.point) {
    if (valsou != null && !valsou.isNaN) {
      if (valsou <= 0) return [_sy('WRECKS01')];
      if (valsou <= options.safetyDepth) return [_sy('DANGER51')];
      return [_sy('WRECKS05')];
    }
    if (catwrk == 1) return [_sy('WRECKS05')];
    if (catwrk == 2) return [_sy('WRECKS01')];
    if (watlev == 1 || watlev == 2 || watlev == 3) {
      return [_sy('WRECKS01')];
    }
    if (watlev == 4 || watlev == 5) return [_sy('WRECKS05')];
    return [_sy('WRECKS01')];
  }

  // Line geometry wrecks are uncommon but treated as polygon in the
  // upstream — Freeboard's JS falls through to the polygon branch for
  // every non-Point geometry. Preserved for parity.
  if (watlev == 1 || watlev == 2) {
    return const [
      S52AreaColor(colorCode: 'CHBRN', raw: 'AC(CHBRN)'),
      _solidLineCstln,
    ];
  }
  if (watlev == 4) {
    return const [
      S52AreaColor(colorCode: 'DEPIT', raw: 'AC(DEPIT)'),
      _dashLineCstln,
    ];
  }
  return const [
    S52AreaColor(colorCode: 'DEPVS', raw: 'AC(DEPVS)'),
    _dottLineCstln,
  ];
}
