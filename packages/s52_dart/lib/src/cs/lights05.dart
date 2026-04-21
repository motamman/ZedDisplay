import '../feature.dart';
import '../instruction.dart';
import '../options.dart';

/// Conditional symbology procedure **LIGHTS05**.
///
/// Selects the appropriate light symbol based on the feature's
/// `COLOUR` attribute (S-57 multi-value integer codes — 1=white,
/// 3=red, 4=green, 6=yellow, 13=orange per IHO S-57). Matches
/// Freeboard-SK's `GetCSLIGHTS05` implementation verbatim:
///
///   * COLOUR=3 (red)                           → `SY(LIGHTS11)`
///   * COLOUR=4 (green)                         → `SY(LIGHTS12)`
///   * COLOUR=1 / 6 / 13 (white/yellow/orange)  → `SY(LIGHTS13)`
///   * COLOUR contains both 1 & 3               → `SY(LIGHTS11)`
///   * COLOUR contains both 1 & 4               → `SY(LIGHTS12)`
///   * anything else                            → no instruction
///
/// In S-57, `COLOUR` may be a single value (`"3"`) or a comma-
/// delimited list (`"1,3"`). Tile encoders deliver it as a string
/// either way; [S52Feature.attrList] handles the split.
List<S52Instruction> lights05(S52Feature feature, S52Options options) {
  final colours = feature.attrList('COLOUR');
  if (colours.isEmpty) return const [];

  String? symbolName;
  if (colours.length == 1) {
    switch (colours.single) {
      case '3':
        symbolName = 'LIGHTS11';
      case '4':
        symbolName = 'LIGHTS12';
      case '1':
      case '6':
      case '13':
        symbolName = 'LIGHTS13';
    }
  } else if (colours.length == 2) {
    final set = colours.toSet();
    if (set.contains('1') && set.contains('3')) {
      symbolName = 'LIGHTS11';
    } else if (set.contains('1') && set.contains('4')) {
      symbolName = 'LIGHTS12';
    }
  }

  if (symbolName == null) return const [];
  return [S52Symbol(name: symbolName, raw: 'SY($symbolName)')];
}
