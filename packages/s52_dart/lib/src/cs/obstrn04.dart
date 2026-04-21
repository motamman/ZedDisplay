import '../enums.dart';
import '../feature.dart';
import '../instruction.dart';
import '../options.dart';

S52Symbol _sy(String name) => S52Symbol(name: name, raw: 'SY($name)');

const _dotLineChblk = S52LineStyle(
  pattern: S52LinePattern.dott,
  width: 2,
  colorCode: 'CHBLK',
  raw: 'LS(DOTT,2,CHBLK)',
);

const _dashLineChblk = S52LineStyle(
  pattern: S52LinePattern.dash,
  width: 2,
  colorCode: 'CHBLK',
  raw: 'LS(DASH,2,CHBLK)',
);

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

/// Conditional symbology procedure **OBSTRN04**.
///
/// Styles an obstruction (OBSTRN) or underwater rock (UWTROC). Picks
/// a dangerous-obstruction symbol, a swept-area symbol, or a plain
/// obstruction symbol based on VALSOU (sounded depth), WATLEV (water-
/// level category), geometry, and which layer the feature lives on.
/// Mirrors Freeboard-SK's `GetCSOBSTRN04`:
///
///   * **Point**: if VALSOU is known, compare to safety. VALSOU ≤ 0 →
///     "dries" symbol (UWTROC04 / OBSTRN11). VALSOU ≤ safetyDepth →
///     generic DANGER51. Otherwise submerged symbol. If VALSOU is
///     missing, fall back to WATLEV — dries/always-underwater/submerged
///     variants.
///   * **Line**: dotted if VALSOU ≤ safety (dangerous), otherwise
///     dashed.
///   * **Area**: colour + outline depending on WATLEV — covers-and-
///     uncovers (`WATLEV 1|2`), always-underwater (`WATLEV 4`), or
///     default very-shallow.
///
/// UWTROC distinction uses the feature's object class — in this port
/// the object class name is canonical and matches the MVT layer name.
List<S52Instruction> obstrn04(S52Feature feature, S52Options options) {
  final isUwtroc = feature.objectClass == 'UWTROC';

  final valsouRaw = feature.attrString('VALSOU');
  final valsou = valsouRaw.isEmpty ? null : double.tryParse(valsouRaw);
  final watlev = feature.hasAttr('WATLEV') ? feature.attrInt('WATLEV') : 0;

  switch (feature.geometryType) {
    case S52GeometryType.point:
      if (valsou != null && !valsou.isNaN) {
        if (valsou <= 0) {
          return [_sy(isUwtroc ? 'UWTROC04' : 'OBSTRN11')];
        }
        if (valsou <= options.safetyDepth) {
          return [_sy('DANGER51')];
        }
        return [_sy(isUwtroc ? 'UWTROC03' : 'OBSTRN01')];
      }
      if (watlev == 1 || watlev == 2) {
        return [_sy(isUwtroc ? 'UWTROC04' : 'OBSTRN11')];
      }
      if (watlev == 4 || watlev == 5) {
        return [_sy(isUwtroc ? 'UWTROC03' : 'OBSTRN03')];
      }
      return [_sy(isUwtroc ? 'UWTROC03' : 'OBSTRN01')];

    case S52GeometryType.line:
      if (valsou != null &&
          !valsou.isNaN &&
          valsou <= options.safetyDepth) {
        return const [_dotLineChblk];
      }
      return const [_dashLineChblk];

    case S52GeometryType.area:
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
        _dotLineChblk,
      ];
  }
}
