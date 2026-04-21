import '../enums.dart';
import '../feature.dart';
import '../instruction.dart';
import '../options.dart';

const _dashedLine2px = S52LineStyle(
  pattern: S52LinePattern.dash,
  width: 2,
  colorCode: 'DEPSC',
  raw: 'LS(DASH,2,DEPSC)',
);

const _dashedLine1px = S52LineStyle(
  pattern: S52LinePattern.dash,
  width: 1,
  colorCode: 'DEPCN',
  raw: 'LS(DASH,1,DEPCN)',
);

const _solidLine2px = S52LineStyle(
  pattern: S52LinePattern.solid,
  width: 2,
  colorCode: 'DEPSC',
  raw: 'LS(SOLD,2,DEPSC)',
);

const _solidLine1px = S52LineStyle(
  pattern: S52LinePattern.solid,
  width: 1,
  colorCode: 'DEPCN',
  raw: 'LS(SOLD,1,DEPCN)',
);

/// Conditional symbology procedure **DEPCNT02**.
///
/// Styles a depth-contour line. Mirrors Freeboard-SK's
/// `GetCSDEPCNT02`, which in turn mirrors OpenCPN's s52plib:
/// https://github.com/OpenCPN/OpenCPN/blob/c2ffb36ebc.../s52cnsy.cpp#L4295
///
/// Behaviour:
///
///   1. Read the contour's depth. For a line-geometry DEPARE feature
///      (contour of a depth area), use `DRVAL1`; otherwise use
///      `VALDCO`. Missing value → depth `-1` (always below safety).
///   2. If depth < safetyDepth → thin solid `LS(SOLD,1,DEPCN)` and
///      return. Below-safety contours aren't highlighted.
///   3. Otherwise, check `QUAPOS` (quality of position): values in
///      (2, 10) indicate uncertain positioning, which is rendered
///      with a dashed pattern; other values render as solid.
///   4. If depth equals [S52Options.selectedSafeContour], render
///      thick (`width=2`, colour `DEPSC`); otherwise render thin
///      (`width=1`, colour `DEPCN`).
///
/// The QUAPOS branch in Freeboard writes no instruction at all when
/// QUAPOS is present but outside (2, 10) — the `else` in the JS runs
/// only when QUAPOS is absent. Preserved here for V1 parity.
List<S52Instruction> depcnt02(S52Feature feature, S52Options options) {
  final isDepareLine =
      feature.objectClass == 'DEPARE' && feature.geometryType == S52GeometryType.line;
  final depthAttr = isDepareLine ? 'DRVAL1' : 'VALDCO';
  final depthValue = feature.hasAttr(depthAttr)
      ? feature.attrDouble(depthAttr, fallback: 0)
      : -1;

  if (depthValue < options.safetyDepth) {
    return const [_solidLine1px];
  }

  final isSafeContour = depthValue == options.selectedSafeContour;

  if (feature.hasAttr('QUAPOS')) {
    final quapos = feature.attrDouble('QUAPOS');
    if (quapos > 2 && quapos < 10) {
      return [isSafeContour ? _dashedLine2px : _dashedLine1px];
    }
    // QUAPOS present but outside the (2, 10) range — Freeboard emits
    // nothing. Preserved for V1 parity; rare in real charts.
    return const [];
  }

  return [isSafeContour ? _solidLine2px : _solidLine1px];
}
