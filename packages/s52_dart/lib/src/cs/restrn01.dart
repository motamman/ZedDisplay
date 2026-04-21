import '../feature.dart';
import '../instruction.dart';
import '../options.dart';

S52Symbol _sy(String name) => S52Symbol(name: name, raw: 'SY($name)');

/// Conditional symbology procedure **RESTRN01**.
///
/// Adds an overlay symbol describing the category of restricted area
/// from the multi-value `RESTRN` attribute (comma-separated S-57
/// integer codes). Mirrors Freeboard-SK's `GetCSRESTRN01`:
///
///   * Missing RESTRN                             → empty.
///   * RESTRN contains 1 or 2                     → `SY(ACHRES51)`
///   * RESTRN contains 3 or 4                     → `SY(FSHRES51)`
///   * RESTRN contains 5 or 6                     → `SY(FSHRES71)`
///   * RESTRN contains 7, 8 or 14                 → `SY(ENTRES51)`
///   * RESTRN contains 9 or 10                    → `SY(DRGARE51)`
///   * RESTRN contains 11 or 12                   → `SY(DIVPRO51)`
///   * RESTRN contains 13                         → `SY(ENTRES61)`
///   * RESTRN contains 27                         → `SY(ENTRES71)`
///   * If none of the above matched but RESTRN present → fallback
///     `SY(ENTRES61)`.
///
/// Multiple branches can fire if the RESTRN list covers several
/// categories — that's faithful to Freeboard.
List<S52Instruction> restrn01(S52Feature feature, S52Options options) {
  if (!feature.hasAttr('RESTRN')) return const [];

  final parts = feature.attrList('RESTRN');
  if (parts.isEmpty) return const [];
  final codes = <int>{};
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n != null) codes.add(n);
  }

  final out = <S52Instruction>[];
  if (codes.contains(1) || codes.contains(2)) out.add(_sy('ACHRES51'));
  if (codes.contains(3) || codes.contains(4)) out.add(_sy('FSHRES51'));
  if (codes.contains(5) || codes.contains(6)) out.add(_sy('FSHRES71'));
  if (codes.contains(7) || codes.contains(8) || codes.contains(14)) {
    out.add(_sy('ENTRES51'));
  }
  if (codes.contains(9) || codes.contains(10)) out.add(_sy('DRGARE51'));
  if (codes.contains(11) || codes.contains(12)) out.add(_sy('DIVPRO51'));
  if (codes.contains(13)) out.add(_sy('ENTRES61'));
  if (codes.contains(27)) out.add(_sy('ENTRES71'));

  if (out.isEmpty) out.add(_sy('ENTRES61'));
  return out;
}
