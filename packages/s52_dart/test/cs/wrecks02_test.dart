import 'package:s52_dart/s52_dart.dart';
import 'package:test/test.dart';

S52Feature _wreck(
  S52GeometryType geom, {
  double? valsou,
  int? watlev,
  int? catwrk,
}) {
  final attrs = <String, Object?>{};
  if (valsou != null) attrs['VALSOU'] = valsou;
  if (watlev != null) attrs['WATLEV'] = watlev;
  if (catwrk != null) attrs['CATWRK'] = catwrk;
  return S52Feature(
    objectClass: 'WRECKS',
    geometryType: geom,
    attributes: attrs,
  );
}

String _symbolOf(List<S52Instruction> out) =>
    (out.whereType<S52Symbol>().single).name;

void main() {
  const options = S52Options();

  group('wrecks02 — point with VALSOU', () {
    test('VALSOU ≤ 0 → WRECKS01', () {
      expect(
        _symbolOf(wrecks02(_wreck(S52GeometryType.point, valsou: 0), options)),
        'WRECKS01',
      );
    });

    test('VALSOU in danger band → DANGER51', () {
      expect(
        _symbolOf(
          wrecks02(_wreck(S52GeometryType.point, valsou: 2), options),
        ),
        'DANGER51',
      );
    });

    test('VALSOU > safety → WRECKS05', () {
      expect(
        _symbolOf(wrecks02(_wreck(S52GeometryType.point, valsou: 10), options)),
        'WRECKS05',
      );
    });
  });

  group('wrecks02 — point with no VALSOU (CATWRK / WATLEV)', () {
    test('CATWRK 1 (non-dangerous) → WRECKS05', () {
      expect(
        _symbolOf(wrecks02(_wreck(S52GeometryType.point, catwrk: 1), options)),
        'WRECKS05',
      );
    });

    test('CATWRK 2 (dangerous) → WRECKS01', () {
      expect(
        _symbolOf(wrecks02(_wreck(S52GeometryType.point, catwrk: 2), options)),
        'WRECKS01',
      );
    });

    test('CATWRK missing, WATLEV 1/2/3 → WRECKS01', () {
      for (final w in [1, 2, 3]) {
        expect(
          _symbolOf(
            wrecks02(_wreck(S52GeometryType.point, watlev: w), options),
          ),
          'WRECKS01',
          reason: 'WATLEV=$w',
        );
      }
    });

    test('CATWRK missing, WATLEV 4/5 → WRECKS05', () {
      for (final w in [4, 5]) {
        expect(
          _symbolOf(
            wrecks02(_wreck(S52GeometryType.point, watlev: w), options),
          ),
          'WRECKS05',
          reason: 'WATLEV=$w',
        );
      }
    });

    test('no attrs at all → WRECKS01 (default dangerous)', () {
      expect(
        _symbolOf(wrecks02(_wreck(S52GeometryType.point), options)),
        'WRECKS01',
      );
    });
  });

  group('wrecks02 — area geometry', () {
    test('WATLEV 1/2 → CHBRN + solid 2 CSTLN', () {
      final out = wrecks02(_wreck(S52GeometryType.area, watlev: 2), options);
      expect(out, hasLength(2));
      expect((out[0] as S52AreaColor).colorCode, 'CHBRN');
      expect((out[1] as S52LineStyle).pattern, S52LinePattern.solid);
    });

    test('WATLEV 4 → DEPIT + dashed 2 CSTLN', () {
      final out = wrecks02(_wreck(S52GeometryType.area, watlev: 4), options);
      expect((out[0] as S52AreaColor).colorCode, 'DEPIT');
      expect((out[1] as S52LineStyle).pattern, S52LinePattern.dash);
    });

    test('WATLEV default → DEPVS + dotted 2 CSTLN', () {
      final out = wrecks02(_wreck(S52GeometryType.area), options);
      expect((out[0] as S52AreaColor).colorCode, 'DEPVS');
      expect((out[1] as S52LineStyle).pattern, S52LinePattern.dott);
    });
  });

  group('wrecks02 — fixture examples', () {
    test('dangerous wreck from tile: CATWRK=2, WATLEV=3 → WRECKS01', () {
      // Matches fixture: {'CATWRK': 2, 'QUASOU': '2', 'WATLEV': 3}
      final out = wrecks02(
        _wreck(S52GeometryType.point, catwrk: 2, watlev: 3),
        options,
      );
      expect(_symbolOf(out), 'WRECKS01');
    });

    test('distant wreck from tile: CATWRK=5, WATLEV=2 → WRECKS01', () {
      // Matches fixture: {'CATWRK': 5, 'WATLEV': 2}. CATWRK 5 doesn't
      // match the 1/2 branches, so WATLEV takes over: 2 → WRECKS01.
      final out = wrecks02(
        _wreck(S52GeometryType.point, catwrk: 5, watlev: 2),
        options,
      );
      expect(_symbolOf(out), 'WRECKS01');
    });
  });

  group('wrecks02 registration', () {
    test('standardCsProcedures registers WRECKS02', () {
      expect(standardCsProcedures['WRECKS02'], same(wrecks02));
    });
  });
}
