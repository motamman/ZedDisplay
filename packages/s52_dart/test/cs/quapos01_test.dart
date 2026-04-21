import 'package:s52_dart/s52_dart.dart';
import 'package:test/test.dart';

S52Feature _f(
  S52GeometryType geom, {
  int? quapos,
  String? layerName,
  String objectClass = 'COALNE',
}) {
  final attrs = <String, Object?>{};
  if (quapos != null) attrs['QUAPOS'] = quapos;
  return S52Feature(
    objectClass: objectClass,
    geometryType: geom,
    attributes: attrs,
    layerName: layerName,
  );
}

void main() {
  const options = S52Options();

  group('quapos01 — point/area path', () {
    test('QUAPOS in [2, 10) → empty (inaccurate, no overlay)', () {
      expect(quapos01(_f(S52GeometryType.point, quapos: 4), options), isEmpty);
      expect(quapos01(_f(S52GeometryType.point, quapos: 9), options), isEmpty);
    });

    test('QUAPOS == 1 → LOWACC03 fallback', () {
      final out = quapos01(_f(S52GeometryType.point, quapos: 1), options);
      expect((out.single as S52Symbol).name, 'LOWACC03');
    });

    test('QUAPOS == 4 accurate → QUAPOS01', () {
      // 4 is outside [2, 10) ... wait, 4 IS in [2, 10). So this is
      // inaccurate per the "if in range, accurate=false" branch and
      // yields empty. Matches Freeboard exactly.
      expect(quapos01(_f(S52GeometryType.point, quapos: 4), options), isEmpty);
    });

    test('QUAPOS == 10 → LOWACC03 fallback (outside range, default branch)',
        () {
      final out = quapos01(_f(S52GeometryType.point, quapos: 10), options);
      expect((out.single as S52Symbol).name, 'LOWACC03');
    });

    test('QUAPOS == 11 → LOWACC03', () {
      final out = quapos01(_f(S52GeometryType.point, quapos: 11), options);
      expect((out.single as S52Symbol).name, 'LOWACC03');
    });

    test('missing QUAPOS → empty', () {
      expect(quapos01(_f(S52GeometryType.point), options), isEmpty);
    });
  });

  group('quapos01 — line path (QQUALIN01)', () {
    test('QUAPOS in [2, 10) → LC(LOWACC21 with Freeboard missing-paren raw',
        () {
      final out = quapos01(_f(S52GeometryType.line, quapos: 5), options);
      expect(out, hasLength(1));
      expect(out.single, isA<S52LineComplex>());
      expect((out.single as S52LineComplex).patternName, 'LOWACC21');
      expect(out.single.raw, 'LC(LOWACC21');
    });

    test('QUAPOS out of range → empty', () {
      expect(quapos01(_f(S52GeometryType.line, quapos: 1), options), isEmpty);
    });

    test('no QUAPOS, COALNE layer → plain solid CSTLN (bugged CONRAD branch)',
        () {
      final out = quapos01(
        _f(S52GeometryType.line, layerName: 'COALNE'),
        options,
      );
      final ls = out.single as S52LineStyle;
      expect(ls.pattern, S52LinePattern.solid);
      expect(ls.width, 1);
      expect(ls.colorCode, 'CSTLN');
    });

    test('no QUAPOS, non-COALNE line → plain solid CSTLN', () {
      final out = quapos01(
        _f(S52GeometryType.line, layerName: 'OTHER'),
        options,
      );
      expect((out.single as S52LineStyle).colorCode, 'CSTLN');
    });
  });

  group('quapos01 registration', () {
    test('standardCsProcedures registers QUAPOS01', () {
      expect(standardCsProcedures['QUAPOS01'], same(quapos01));
    });
  });
}
