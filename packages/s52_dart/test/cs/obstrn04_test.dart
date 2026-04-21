import 'package:s52_dart/s52_dart.dart';
import 'package:test/test.dart';

S52Feature _obstrn(
  S52GeometryType geom, {
  String objectClass = 'OBSTRN',
  double? valsou,
  int? watlev,
}) {
  final attrs = <String, Object?>{};
  if (valsou != null) attrs['VALSOU'] = valsou;
  if (watlev != null) attrs['WATLEV'] = watlev;
  return S52Feature(
    objectClass: objectClass,
    geometryType: geom,
    attributes: attrs,
  );
}

String _symbolOf(List<S52Instruction> out) =>
    (out.whereType<S52Symbol>().single).name;

void main() {
  const options = S52Options();

  group('obstrn04 — point, VALSOU present', () {
    test('VALSOU ≤ 0 → OBSTRN11 (OBSTRN layer)', () {
      final out = obstrn04(
        _obstrn(S52GeometryType.point, valsou: 0),
        options,
      );
      expect(_symbolOf(out), 'OBSTRN11');
    });

    test('VALSOU ≤ 0 on UWTROC layer → UWTROC04', () {
      final out = obstrn04(
        _obstrn(S52GeometryType.point, objectClass: 'UWTROC', valsou: 0),
        options,
      );
      expect(_symbolOf(out), 'UWTROC04');
    });

    test('VALSOU ≤ safety (inside the danger band) → DANGER51', () {
      final out = obstrn04(
        _obstrn(S52GeometryType.point, valsou: 1.5),
        options,
      );
      expect(_symbolOf(out), 'DANGER51');
    });

    test('VALSOU == safetyDepth treated as danger', () {
      final out = obstrn04(
        _obstrn(S52GeometryType.point, valsou: 3),
        options,
      );
      expect(_symbolOf(out), 'DANGER51');
    });

    test('VALSOU > safety → OBSTRN01', () {
      final out = obstrn04(
        _obstrn(S52GeometryType.point, valsou: 10),
        options,
      );
      expect(_symbolOf(out), 'OBSTRN01');
    });

    test('VALSOU > safety on UWTROC → UWTROC03', () {
      final out = obstrn04(
        _obstrn(
          S52GeometryType.point,
          objectClass: 'UWTROC',
          valsou: 10,
        ),
        options,
      );
      expect(_symbolOf(out), 'UWTROC03');
    });
  });

  group('obstrn04 — point, no VALSOU (WATLEV branch)', () {
    test('WATLEV 1 or 2 → OBSTRN11 / UWTROC04', () {
      expect(
        _symbolOf(obstrn04(
          _obstrn(S52GeometryType.point, watlev: 1),
          options,
        )),
        'OBSTRN11',
      );
      expect(
        _symbolOf(obstrn04(
          _obstrn(S52GeometryType.point, watlev: 2),
          options,
        )),
        'OBSTRN11',
      );
      expect(
        _symbolOf(obstrn04(
          _obstrn(
            S52GeometryType.point,
            objectClass: 'UWTROC',
            watlev: 2,
          ),
          options,
        )),
        'UWTROC04',
      );
    });

    test('WATLEV 4 or 5 → OBSTRN03 / UWTROC03', () {
      expect(
        _symbolOf(obstrn04(
          _obstrn(S52GeometryType.point, watlev: 4),
          options,
        )),
        'OBSTRN03',
      );
      expect(
        _symbolOf(obstrn04(
          _obstrn(
            S52GeometryType.point,
            objectClass: 'UWTROC',
            watlev: 5,
          ),
          options,
        )),
        'UWTROC03',
      );
    });

    test('WATLEV out of mapped range (3) → default OBSTRN01 / UWTROC03', () {
      expect(
        _symbolOf(obstrn04(
          _obstrn(S52GeometryType.point, watlev: 3),
          options,
        )),
        'OBSTRN01',
      );
      expect(
        _symbolOf(obstrn04(
          _obstrn(
            S52GeometryType.point,
            objectClass: 'UWTROC',
            watlev: 3,
          ),
          options,
        )),
        'UWTROC03',
      );
    });

    test('no VALSOU, no WATLEV → default OBSTRN01', () {
      expect(
        _symbolOf(obstrn04(_obstrn(S52GeometryType.point), options)),
        'OBSTRN01',
      );
    });
  });

  group('obstrn04 — line geometry', () {
    test('VALSOU ≤ safety → dotted 2px CHBLK', () {
      final out = obstrn04(
        _obstrn(S52GeometryType.line, valsou: 2),
        options,
      );
      final ls = out.single as S52LineStyle;
      expect(ls.pattern, S52LinePattern.dott);
      expect(ls.width, 2);
      expect(ls.colorCode, 'CHBLK');
    });

    test('VALSOU > safety → dashed 2px CHBLK', () {
      final out = obstrn04(
        _obstrn(S52GeometryType.line, valsou: 10),
        options,
      );
      final ls = out.single as S52LineStyle;
      expect(ls.pattern, S52LinePattern.dash);
    });

    test('missing VALSOU → dashed (non-dangerous fallback)', () {
      final out = obstrn04(_obstrn(S52GeometryType.line), options);
      expect((out.single as S52LineStyle).pattern, S52LinePattern.dash);
    });
  });

  group('obstrn04 — area geometry', () {
    test('WATLEV 1 or 2 → CHBRN + solid 2 CSTLN', () {
      final out = obstrn04(
        _obstrn(S52GeometryType.area, watlev: 2),
        options,
      );
      expect(out, hasLength(2));
      expect((out[0] as S52AreaColor).colorCode, 'CHBRN');
      final ls = out[1] as S52LineStyle;
      expect(ls.pattern, S52LinePattern.solid);
      expect(ls.colorCode, 'CSTLN');
    });

    test('WATLEV 4 → DEPIT + dashed 2 CSTLN', () {
      final out = obstrn04(
        _obstrn(S52GeometryType.area, watlev: 4),
        options,
      );
      expect((out[0] as S52AreaColor).colorCode, 'DEPIT');
      expect((out[1] as S52LineStyle).pattern, S52LinePattern.dash);
    });

    test('WATLEV default → DEPVS + dotted 2 CHBLK', () {
      final out = obstrn04(_obstrn(S52GeometryType.area), options);
      expect((out[0] as S52AreaColor).colorCode, 'DEPVS');
      expect((out[1] as S52LineStyle).pattern, S52LinePattern.dott);
    });
  });

  group('obstrn04 registration', () {
    test('standardCsProcedures registers OBSTRN04', () {
      expect(standardCsProcedures['OBSTRN04'], same(obstrn04));
    });
  });
}
