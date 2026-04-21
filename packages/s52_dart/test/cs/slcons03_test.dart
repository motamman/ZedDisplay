import 'package:s52_dart/s52_dart.dart';
import 'package:test/test.dart';

S52Feature _slcons(
  S52GeometryType geom, {
  double? quapos,
  int? condtn,
  int? catslc,
  int? watlev,
}) {
  final attrs = <String, Object?>{};
  if (quapos != null) attrs['QUAPOS'] = quapos;
  if (condtn != null) attrs['CONDTN'] = condtn;
  if (catslc != null) attrs['CATSLC'] = catslc;
  if (watlev != null) attrs['WATLEV'] = watlev;
  return S52Feature(
    objectClass: 'SLCONS',
    geometryType: geom,
    attributes: attrs,
  );
}

void main() {
  const options = S52Options();

  group('slcons03 — point', () {
    test('QUAPOS in [2, 10) → SY(LOWACC01)', () {
      final out = slcons03(_slcons(S52GeometryType.point, quapos: 5), options);
      expect((out.single as S52Symbol).name, 'LOWACC01');
    });

    test('QUAPOS at 2 is included (lower bound inclusive)', () {
      final out = slcons03(_slcons(S52GeometryType.point, quapos: 2), options);
      expect(out, hasLength(1));
    });

    test('QUAPOS at 10 excluded (upper bound exclusive)', () {
      final out = slcons03(_slcons(S52GeometryType.point, quapos: 10), options);
      expect(out, isEmpty);
    });

    test('no QUAPOS → empty', () {
      final out = slcons03(_slcons(S52GeometryType.point), options);
      expect(out, isEmpty);
    });
  });

  group('slcons03 — polygon always prepends AP(CROSSX01', () {
    test('polygon + QUAPOS in range → pattern + LC', () {
      final out = slcons03(_slcons(S52GeometryType.area, quapos: 4), options);
      expect(out, hasLength(2));
      expect(out[0], isA<S52AreaPattern>());
      expect((out[0] as S52AreaPattern).patternName, 'CROSSX01');
      // Raw string preserves the missing-paren Freeboard literal.
      expect((out[0] as S52AreaPattern).raw, 'AP(CROSSX01');
      expect(out[1], isA<S52LineComplex>());
    });

    test('line without QUAPOS gets no pattern, just the fallback line', () {
      final out = slcons03(_slcons(S52GeometryType.line), options);
      expect(out, hasLength(1));
      expect(out.single, isA<S52LineStyle>());
    });
  });

  group('slcons03 — QUAPOS-gated line style (non-point)', () {
    test('QUAPOS in [2, 10) on line → LC(LOWACC01)', () {
      final out = slcons03(_slcons(S52GeometryType.line, quapos: 4), options);
      expect(out.single, isA<S52LineComplex>());
      expect((out.single as S52LineComplex).patternName, 'LOWACC01');
    });
  });

  group('slcons03 — fallback cascade (no QUAPOS in range)', () {
    test('CATSLC 6 / 15 / 16 → solid 4px CSTLN', () {
      for (final c in [6, 15, 16]) {
        final out = slcons03(
          _slcons(S52GeometryType.line, catslc: c),
          options,
        );
        final ls = out.single as S52LineStyle;
        expect(ls.pattern, S52LinePattern.solid, reason: 'CATSLC=$c');
        expect(ls.width, 4, reason: 'CATSLC=$c');
        expect(ls.colorCode, 'CSTLN', reason: 'CATSLC=$c');
      }
    });

    test('WATLEV 2 → solid 2px CSTLN', () {
      final out = slcons03(_slcons(S52GeometryType.line, watlev: 2), options);
      final ls = out.single as S52LineStyle;
      expect(ls.pattern, S52LinePattern.solid);
      expect(ls.width, 2);
    });

    test('WATLEV 3 or 4 → dashed 2px CSTLN', () {
      for (final w in [3, 4]) {
        final out = slcons03(
          _slcons(S52GeometryType.line, watlev: w),
          options,
        );
        expect(
          (out.single as S52LineStyle).pattern,
          S52LinePattern.dash,
          reason: 'WATLEV=$w',
        );
      }
    });

    test('no relevant attrs → default solid 2px CSTLN', () {
      final out = slcons03(_slcons(S52GeometryType.line), options);
      final ls = out.single as S52LineStyle;
      expect(ls.pattern, S52LinePattern.solid);
      expect(ls.width, 2);
    });
  });

  group('slcons03 — fixture shapes', () {
    test('fixture SLCONS line with CATSLC=4, WATLEV=2 → solid 2px CSTLN', () {
      // Real tile: {'CATSLC': 4, 'WATLEV': 2}. CATSLC=4 doesn't match
      // the 6/15/16 branch, so WATLEV=2 wins → solid 2px.
      final out = slcons03(
        _slcons(S52GeometryType.line, catslc: 4, watlev: 2),
        options,
      );
      final ls = out.single as S52LineStyle;
      expect(ls.width, 2);
      expect(ls.pattern, S52LinePattern.solid);
    });

    test('fixture SLCONS point with CATSLC=12, WATLEV=2 (no QUAPOS) → empty',
        () {
      final out = slcons03(
        _slcons(S52GeometryType.point, catslc: 12, watlev: 2),
        options,
      );
      expect(out, isEmpty);
    });
  });

  group('slcons03 registration', () {
    test('standardCsProcedures registers SLCONS03', () {
      expect(standardCsProcedures['SLCONS03'], same(slcons03));
    });
  });
}
