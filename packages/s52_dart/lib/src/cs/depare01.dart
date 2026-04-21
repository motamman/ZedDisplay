import '../feature.dart';
import '../instruction.dart';
import '../options.dart';

/// Helper used by [depare01]. Picks the depth-band area colour for a
/// depth range `[drval1, drval2)`. Mirrors Freeboard-SK's
/// `GetSeabed01` implementation verbatim — which in turn mirrors
/// OpenCPN's `s52plib`. Reference:
/// https://github.com/OpenCPN/OpenCPN/blob/c2ffb36ebc.../s52cnsy.cpp#L5597
///
/// Behaviour is driven by [S52Options.colorCount] (2-band vs 4-band
/// seabed palettes) and the shallow/safety/deep thresholds. Exported
/// as part of the public API because renderers sometimes need to
/// call it directly when rendering non-DEPARE features that
/// semantically match a depth band (e.g. a custom survey layer).
List<S52Instruction> getSeabed01(
  double drval1,
  double drval2,
  S52Options options,
) {
  S52AreaColor color(String code, String raw) =>
      S52AreaColor(colorCode: code, raw: raw);

  var out = <S52Instruction>[color('DEPIT', 'AC(DEPIT)')];

  if (drval1 >= 0 && drval2 > 0) {
    out = [color('DEPVS', 'AC(DEPVS)')];
  }

  if (options.colorCount == 2) {
    if (drval1 >= options.safetyDepth && drval2 > options.safetyDepth) {
      out = [color('DEPDW', 'AC(DEPDW)')];
    }
  } else {
    if (drval1 >= options.shallowDepth && drval2 > options.shallowDepth) {
      out = [color('DEPMS', 'AC(DEPMS)')];
    }
    if (drval1 >= options.safetyDepth && drval2 > options.safetyDepth) {
      out = [color('DEPMD', 'AC(DEPMD)')];
    }
    if (drval1 >= options.deepDepth && drval2 > options.deepDepth) {
      out = [color('DEPDW', 'AC(DEPDW)')];
    }
  }
  return out;
}

/// Conditional symbology procedure **DEPARE01**.
///
/// Fills a depth-area polygon with the appropriate seabed band
/// colour, with an extra pattern + dashed outline for dredged areas
/// (DRGARE). Mirrors Freeboard-SK's `getCSDEPARE01`.
///
/// Behaviour:
///
///   1. Read DRVAL1 (fallback -1) and DRVAL2 (fallback `drval1 + 0.01`).
///      Fallbacks match Freeboard exactly — they guarantee an
///      ordered, finite range even when the tile feature lacks one
///      or both attributes.
///   2. Run [getSeabed01] to select the base area colour.
///   3. If the feature is a dredged area (object class `DRGARE`,
///      S-57 OBJL 46), append `AP(DRGARE01)` (hatched fill pattern)
///      and `LS(DASH,1,CHGRF)` (dashed grey outline).
///
/// The DRGARE branch relies on the feature's object class name
/// rather than the integer OBJL code — in this port the layer name
/// is canonical and OBJL is dropped from fixtures as a redundant
/// housekeeping field.
List<S52Instruction> depare01(S52Feature feature, S52Options options) {
  var drval1 = -1.0;
  final dv1 = double.tryParse(feature.attrString('DRVAL1'));
  if (dv1 != null && !dv1.isNaN) drval1 = dv1;

  var drval2 = drval1 + 0.01;
  final dv2 = double.tryParse(feature.attrString('DRVAL2'));
  if (dv2 != null && !dv2.isNaN) drval2 = dv2;

  final out = List<S52Instruction>.from(getSeabed01(drval1, drval2, options));

  if (feature.objectClass == 'DRGARE') {
    out.add(const S52AreaPattern(
      patternName: 'DRGARE01',
      raw: 'AP(DRGARE01)',
    ));
    out.add(const S52LineStyle(
      pattern: S52LinePattern.dash,
      width: 1,
      colorCode: 'CHGRF',
      raw: 'LS(DASH,1,CHGRF)',
    ));
  }
  return out;
}
