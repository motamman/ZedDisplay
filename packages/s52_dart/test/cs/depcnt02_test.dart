import 'package:s52_dart/s52_dart.dart';
import 'package:test/test.dart';

S52Feature _depcnt({
  double? valdco,
  double? drval1,
  double? quapos,
  S52GeometryType geometry = S52GeometryType.line,
  String objectClass = 'DEPCNT',
}) {
  final attrs = <String, Object?>{};
  if (valdco != null) attrs['VALDCO'] = valdco;
  if (drval1 != null) attrs['DRVAL1'] = drval1;
  if (quapos != null) attrs['QUAPOS'] = quapos;
  return S52Feature(
    objectClass: objectClass,
    geometryType: geometry,
    attributes: attrs,
  );
}

S52LineStyle _ls(List<S52Instruction> out) => out.single as S52LineStyle;

void main() {
  const options = S52Options();

  group('depcnt02 — below safety depth', () {
    test('VALDCO < safety → thin solid DEPCN', () {
      final out = depcnt02(_depcnt(valdco: 1.5), options);
      final ls = _ls(out);
      expect(ls.pattern, S52LinePattern.solid);
      expect(ls.width, 1);
      expect(ls.colorCode, 'DEPCN');
    });

    test('no depth attribute at all also counts as below safety', () {
      final out = depcnt02(_depcnt(), options);
      final ls = _ls(out);
      expect(ls.colorCode, 'DEPCN');
    });
  });

  group('depcnt02 — at or above safety depth, no QUAPOS', () {
    test('non-safety contour → thin solid DEPCN', () {
      final out = depcnt02(_depcnt(valdco: 5), options);
      final ls = _ls(out);
      expect(ls.pattern, S52LinePattern.solid);
      expect(ls.width, 1);
      expect(ls.colorCode, 'DEPCN');
    });

    test('VALDCO == selectedSafeContour → bold solid DEPSC', () {
      final safe = options.copyWith(selectedSafeContour: 5);
      final out = depcnt02(_depcnt(valdco: 5), safe);
      final ls = _ls(out);
      expect(ls.pattern, S52LinePattern.solid);
      expect(ls.width, 2);
      expect(ls.colorCode, 'DEPSC');
    });
  });

  group('depcnt02 — QUAPOS branching', () {
    test('QUAPOS in (2, 10) with non-safety depth → thin dashed DEPCN', () {
      final out = depcnt02(_depcnt(valdco: 5, quapos: 5), options);
      final ls = _ls(out);
      expect(ls.pattern, S52LinePattern.dash);
      expect(ls.width, 1);
      expect(ls.colorCode, 'DEPCN');
    });

    test('QUAPOS in (2, 10) at safety contour → bold dashed DEPSC', () {
      final safe = options.copyWith(selectedSafeContour: 5);
      final out = depcnt02(_depcnt(valdco: 5, quapos: 5), safe);
      final ls = _ls(out);
      expect(ls.pattern, S52LinePattern.dash);
      expect(ls.width, 2);
      expect(ls.colorCode, 'DEPSC');
    });

    test('QUAPOS out of range (exactly 2) → empty (V1 parity quirk)', () {
      final out = depcnt02(_depcnt(valdco: 5, quapos: 2), options);
      expect(out, isEmpty);
    });

    test('QUAPOS out of range (10+) → empty', () {
      final out = depcnt02(_depcnt(valdco: 5, quapos: 10), options);
      expect(out, isEmpty);
    });
  });

  group('depcnt02 — DEPARE line special case', () {
    test('DEPARE line-geometry feature uses DRVAL1 instead of VALDCO', () {
      // VALDCO ignored; DRVAL1=7 > safety → thin solid at non-safety.
      final out = depcnt02(
        _depcnt(
          drval1: 7,
          valdco: 0.1,
          objectClass: 'DEPARE',
          geometry: S52GeometryType.line,
        ),
        options,
      );
      final ls = _ls(out);
      expect(ls.colorCode, 'DEPCN');
      expect(ls.width, 1);
    });

    test('DEPARE polygon feature falls through to VALDCO', () {
      // Polygon-geometry DEPARE uses VALDCO like any other contour;
      // but there's no VALDCO here, so we treat as below safety.
      final out = depcnt02(
        _depcnt(
          drval1: 7,
          objectClass: 'DEPARE',
          geometry: S52GeometryType.area,
        ),
        options,
      );
      expect(_ls(out).colorCode, 'DEPCN');
    });
  });

  group('depcnt02 registration', () {
    test('standardCsProcedures registers DEPCNT02', () {
      expect(standardCsProcedures['DEPCNT02'], same(depcnt02));
    });
  });
}
