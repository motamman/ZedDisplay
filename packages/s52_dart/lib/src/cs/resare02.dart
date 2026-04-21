import '../feature.dart';
import '../instruction.dart';
import '../options.dart';
import 'restrn01.dart';

/// Conditional symbology procedure **RESARE02**.
///
/// Styles a restricted area. Mirrors Freeboard-SK's `GetCSRESARE02`:
/// emit a dashed magenta outline, then delegate to [restrn01] for
/// the per-category overlay symbol.
///
/// Registered for both `RESARE01` and `RESARE02` names because
/// Freeboard's evalCS dispatch aliases both to the same handler.
List<S52Instruction> resare02(S52Feature feature, S52Options options) {
  return <S52Instruction>[
    const S52LineStyle(
      pattern: S52LinePattern.dash,
      width: 2,
      colorCode: 'CHMGD',
      raw: 'LS(DASH,2,CHMGD)',
    ),
    ...restrn01(feature, options),
  ];
}
