import '../feature.dart';
import '../instruction.dart';
import '../options.dart';

/// Symbol map used when the parent feature floats (buoys, light
/// vessel, lighted float). Keyed by `TOPSHP` (S-57 topmark shape code
/// 1-33). Entries and defaults match Freeboard-SK's `GetCSTOPMAR01`.
const Map<int, String> _floatingTopmarks = {
  1: 'TOPMAR02',
  2: 'TOPMAR04',
  3: 'TOPMAR10',
  4: 'TOPMAR12',
  5: 'TOPMAR13',
  6: 'TOPMAR14',
  7: 'TOPMAR65',
  8: 'TOPMAR17',
  9: 'TOPMAR16',
  10: 'TOPMAR08',
  11: 'TOPMAR07',
  12: 'TOPMAR14',
  13: 'TOPMAR05',
  14: 'TOPMAR06',
  17: 'TMARDEF2',
  18: 'TOPMAR10',
  19: 'TOPMAR13',
  20: 'TOPMAR14',
  21: 'TOPMAR13',
  22: 'TOPMAR14',
  23: 'TOPMAR14',
  24: 'TOPMAR02',
  25: 'TOPMAR04',
  26: 'TOPMAR10',
  27: 'TOPMAR17',
  28: 'TOPMAR18',
  29: 'TOPMAR02',
  30: 'TOPMAR17',
  31: 'TOPMAR14',
  32: 'TOPMAR10',
  33: 'TMARDEF2',
};

/// Symbol map used when the parent feature is fixed (beacons,
/// daymarks). Keyed by `TOPSHP`.
const Map<int, String> _fixedTopmarks = {
  1: 'TOPMAR22',
  2: 'TOPMAR24',
  3: 'TOPMAR30',
  4: 'TOPMAR32',
  5: 'TOPMAR33',
  6: 'TOPMAR34',
  7: 'TOPMAR85',
  8: 'TOPMAR86',
  9: 'TOPMAR36',
  10: 'TOPMAR28',
  11: 'TOPMAR27',
  12: 'TOPMAR14',
  13: 'TOPMAR25',
  14: 'TOPMAR26',
  15: 'TOPMAR88',
  16: 'TOPMAR87',
  17: 'TMARDEF1',
  18: 'TOPMAR30',
  19: 'TOPMAR33',
  20: 'TOPMAR34',
  21: 'TOPMAR33',
  22: 'TOPMAR34',
  23: 'TOPMAR34',
  24: 'TOPMAR22',
  25: 'TOPMAR24',
  26: 'TOPMAR30',
  27: 'TOPMAR86',
  28: 'TOPMAR89',
  29: 'TOPMAR22',
  30: 'TOPMAR86',
  31: 'TOPMAR14',
  32: 'TOPMAR30',
  33: 'TMARDEF1',
};

/// Conditional symbology procedure **TOPMAR01**.
///
/// Selects a topmark symbol for a buoy/beacon top decoration. The
/// choice depends on whether the parent feature is floating (buoy or
/// light float) or fixed (beacon or daymark), and on the `TOPSHP`
/// attribute code. Mirrors Freeboard-SK's `GetCSTOPMAR01` verbatim.
///
///   * **Missing TOPSHP** → `SY(QUESMRK1)` (question-mark placeholder).
///   * **Floating parent** (layer `LITFLT`, `LITVES`, or starting
///     with `BOY`) → [_floatingTopmarks] lookup; default `TMARDEF2`.
///   * **Fixed parent** → [_fixedTopmarks] lookup; default `TMARDEF1`.
List<S52Instruction> topmar01(S52Feature feature, S52Options options) {
  if (!feature.hasAttr('TOPSHP')) {
    return const [
      S52Symbol(name: 'QUESMRK1', raw: 'SY(QUESMRK1)'),
    ];
  }

  final layer = feature.effectiveLayerName;
  final floating = layer == 'LITFLT' || layer == 'LITVES' || layer.startsWith('BOY');
  final topshp = feature.attrInt('TOPSHP');
  final table = floating ? _floatingTopmarks : _fixedTopmarks;
  final fallback = floating ? 'TMARDEF2' : 'TMARDEF1';
  final name = table[topshp] ?? fallback;
  return [S52Symbol(name: name, raw: 'SY($name)')];
}
