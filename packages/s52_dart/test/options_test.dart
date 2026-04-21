import 'package:s52_dart/s52_dart.dart';
import 'package:test/test.dart';

void main() {
  group('S52Options', () {
    test('default values match OpenCPN presentation defaults', () {
      const o = S52Options();
      expect(o.shallowDepth, 2);
      expect(o.safetyDepth, 3);
      expect(o.deepDepth, 6);
      expect(o.graphicsStyle, S52GraphicsStyle.paper);
      expect(o.boundaries, S52Boundaries.plain);
      expect(o.colorCount, 4);
      expect(o.colorTable, S52ColorScheme.dayBright);
      expect(o.depthUnit, 'm');
      expect(o.depthConversionFactor, 1.0);
      expect(o.displayCategory, S52DisplayCategory.standard);
    });

    test('copyWith preserves unset fields', () {
      const base = S52Options(safetyDepth: 5);
      final copy = base.copyWith(deepDepth: 20);
      expect(copy.safetyDepth, 5);
      expect(copy.deepDepth, 20);
      expect(copy.shallowDepth, base.shallowDepth);
    });

    test('copyWith applies boundaries override', () {
      const base = S52Options();
      final copy = base.copyWith(boundaries: S52Boundaries.symbolised);
      expect(copy.boundaries, S52Boundaries.symbolised);
      expect(base.boundaries, S52Boundaries.plain);
    });

    test('otherLayers default contains SOUNDG, OBSTRN, UWTROC, WRECKS, DEPCNT',
        () {
      const o = S52Options();
      expect(
        o.otherLayers,
        containsAll(['SOUNDG', 'OBSTRN', 'UWTROC', 'WRECKS', 'DEPCNT']),
      );
    });
  });
}
