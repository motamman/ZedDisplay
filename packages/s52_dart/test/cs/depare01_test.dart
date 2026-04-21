import 'package:s52_dart/s52_dart.dart';
import 'package:test/test.dart';

S52Feature _depare(
  double? drval1,
  double? drval2, {
  String objectClass = 'DEPARE',
}) {
  final attrs = <String, Object?>{};
  if (drval1 != null) attrs['DRVAL1'] = drval1;
  if (drval2 != null) attrs['DRVAL2'] = drval2;
  return S52Feature(
    objectClass: objectClass,
    geometryType: S52GeometryType.area,
    attributes: attrs,
  );
}

List<String> _colorCodes(List<S52Instruction> out) => out
    .whereType<S52AreaColor>()
    .map((i) => i.colorCode)
    .toList(growable: false);

void main() {
  // OpenCPN / Freeboard defaults: shallow=2, safety=3, deep=6.
  const options = S52Options();

  group('getSeabed01 (4-colour palette)', () {
    test('intertidal band when drval1 < 0', () {
      // Default-negative DRVAL1 (feature missing / charted as above chart datum)
      // → DEPIT (intertidal).
      expect(
        _colorCodes(getSeabed01(-1, -0.5, options)),
        ['DEPIT'],
      );
    });

    test('very shallow band when 0..(+shallow)', () {
      expect(_colorCodes(getSeabed01(0, 0.5, options)), ['DEPVS']);
      expect(_colorCodes(getSeabed01(1.5, 1.9, options)), ['DEPVS']);
    });

    test('medium-shallow band at >= shallow (2)', () {
      expect(_colorCodes(getSeabed01(2, 2.5, options)), ['DEPMS']);
    });

    test('medium-deep band at >= safety (3)', () {
      expect(_colorCodes(getSeabed01(3, 5, options)), ['DEPMD']);
      expect(_colorCodes(getSeabed01(4.0, 5.9, options)), ['DEPMD']);
    });

    test('deep band at >= deep (6)', () {
      expect(_colorCodes(getSeabed01(6, 10, options)), ['DEPDW']);
    });

    test('boundary: drval2 == safety (not strictly greater) falls back a band',
        () {
      // Cascade uses `drval1 >= X && drval2 > X`. With drval2 exactly
      // on the safety boundary, MD is not reached — fallthrough to MS.
      expect(_colorCodes(getSeabed01(3, 3, options)), ['DEPMS']);
    });
  });

  group('getSeabed01 (2-colour palette)', () {
    const twoColor = S52Options(colorCount: 2);

    test('default is DEPIT, same as 4-colour', () {
      expect(_colorCodes(getSeabed01(-1, 0, twoColor)), ['DEPIT']);
    });

    test('DEPVS applies with positive shallow depths', () {
      expect(_colorCodes(getSeabed01(1, 2, twoColor)), ['DEPVS']);
    });

    test('deep band at safety threshold (no medium bands)', () {
      // 2-colour mode collapses MS/MD into a single jump to DEPDW.
      expect(_colorCodes(getSeabed01(3, 10, twoColor)), ['DEPDW']);
    });

    test('does not emit MS/MD bands in 2-colour mode', () {
      final out = _colorCodes(getSeabed01(2, 2.5, twoColor));
      expect(out, equals(['DEPVS']));
      expect(out, isNot(contains('DEPMS')));
    });
  });

  group('depare01 defaults for missing attrs', () {
    test('no DRVAL1 and no DRVAL2 → DEPIT (drval1=-1, drval2=-0.99)', () {
      // Freeboard's default branch: drval1 default -1, drval2 default
      // drval1+0.01 → the DEPVS check (drval1>=0) fails, so we stay at
      // DEPIT.
      final out = depare01(_depare(null, null), options);
      expect(_colorCodes(out), ['DEPIT']);
    });

    test('DRVAL1 only → drval2 defaults to drval1 + 0.01', () {
      // drval1=3, drval2=3.01 → safety test: drval1>=3 true, drval2>3 true → DEPMD.
      final out = depare01(_depare(3, null), options);
      expect(_colorCodes(out), ['DEPMD']);
    });
  });

  group('depare01 real DEPARE samples (tile fixture shapes)', () {
    test('{DRVAL1: 3.6, DRVAL2: 5.4} → DEPMD', () {
      final out = depare01(_depare(3.6, 5.4), options);
      expect(_colorCodes(out), ['DEPMD']);
      expect(out, hasLength(1));
    });

    test('{DRVAL1: 1.8, DRVAL2: 5.4} → DEPVS (drval1 below shallow)', () {
      final out = depare01(_depare(1.8, 5.4), options);
      expect(_colorCodes(out), ['DEPVS']);
    });

    test('{DRVAL1: -2.8, DRVAL2: 0} → DEPIT (both below/at datum)', () {
      final out = depare01(_depare(-2.8, 0), options);
      expect(_colorCodes(out), ['DEPIT']);
    });
  });

  group('depare01 dredged-area overlay', () {
    test('DRGARE adds AP(DRGARE01) + LS(DASH,1,CHGRF) after the band', () {
      final out = depare01(
        _depare(3, 5, objectClass: 'DRGARE'),
        options,
      );
      expect(out, hasLength(3));
      expect(out[0], isA<S52AreaColor>());
      expect(out[1], isA<S52AreaPattern>());
      expect((out[1] as S52AreaPattern).patternName, 'DRGARE01');
      expect(out[2], isA<S52LineStyle>());
      final ls = out[2] as S52LineStyle;
      expect(ls.pattern, S52LinePattern.dash);
      expect(ls.width, 1);
      expect(ls.colorCode, 'CHGRF');
    });

    test('plain DEPARE does not add the DRGARE overlay', () {
      final out = depare01(_depare(3, 5), options);
      expect(out.whereType<S52AreaPattern>(), isEmpty);
      expect(out.whereType<S52LineStyle>(), isEmpty);
    });
  });

  group('depare01 registration', () {
    test('standardCsProcedures registers DEPARE01', () {
      expect(standardCsProcedures['DEPARE01'], same(depare01));
    });
  });
}
