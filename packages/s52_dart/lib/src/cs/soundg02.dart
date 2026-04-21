import '../feature.dart';
import '../instruction.dart';
import '../options.dart';

/// Conditional symbology procedure **SOUNDG02**.
///
/// Formats a spot sounding (point depth) as a text label for
/// rendering. Mirrors Freeboard-SK's `GetCSSOUNDG02` semantics:
///
///   1. Read the depth from `DEPTH` (falling back to `VALSOU`).
///      Missing or non-numeric → no output.
///   2. Convert metres to the user's display unit by multiplying
///      through [S52Options.depthConversionFactor]. Freeboard
///      hardcodes 3.28084 for feet; the Dart port uses the
///      configured factor so consumers can support other units
///      (fathoms) by configuration alone.
///   3. Format the number:
///        - Metric units ([S52Options.depthUnit] == `'m'`):
///            * If [S52Options.currentResolution] < 5 m/pixel
///              (zoomed in) AND the depth has a fractional part,
///              emit one decimal.
///            * Otherwise emit the depth rounded to a whole number.
///        - Any other unit (feet, fathoms): always rounded to a
///          whole number — matches Freeboard for feet and is a
///          sensible default for others.
///   4. Emit a single [S52TextLiteral] with the formatted text and
///      the positioning params Freeboard passes:
///      `TX(_SOUNDG_WHOLE,1,2,2)` — params `['1', '2', '2']`.
List<S52Instruction> soundg02(S52Feature feature, S52Options options) {
  double? depthM;
  if (feature.hasAttr('DEPTH')) {
    depthM = feature.attrDouble('DEPTH');
  } else if (feature.hasAttr('VALSOU')) {
    depthM = feature.attrDouble('VALSOU');
  }
  if (depthM == null || depthM.isNaN) return const [];

  final displayDepth = depthM * options.depthConversionFactor;
  final sign = displayDepth < 0 ? '-' : '';
  final absDepth = displayDepth.abs();

  final String text;
  if (options.depthUnit == 'm') {
    final zoomedIn = options.currentResolution > 0 &&
        options.currentResolution < 5;
    if (zoomedIn) {
      final rounded = (absDepth * 10).round() / 10;
      text = sign +
          (rounded % 1 == 0
              ? rounded.toStringAsFixed(0)
              : rounded.toStringAsFixed(1));
    } else {
      text = sign + absDepth.round().toString();
    }
  } else {
    text = sign + absDepth.round().toString();
  }

  return [
    S52TextLiteral(
      text: text,
      params: const ['1', '2', '2'],
      raw: 'TX(_SOUNDG_WHOLE,1,2,2)',
    ),
  ];
}
