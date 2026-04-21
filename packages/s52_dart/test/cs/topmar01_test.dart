import 'package:s52_dart/s52_dart.dart';
import 'package:test/test.dart';

S52Feature _topmark({
  int? topshp,
  String? layerName,
}) {
  final attrs = <String, Object?>{};
  if (topshp != null) attrs['TOPSHP'] = topshp;
  return S52Feature(
    objectClass: 'TOPMAR',
    geometryType: S52GeometryType.point,
    attributes: attrs,
    layerName: layerName,
  );
}

String _symbolOf(List<S52Instruction> out) =>
    (out.single as S52Symbol).name;

void main() {
  const options = S52Options();

  group('topmar01 — missing TOPSHP', () {
    test('no TOPSHP → QUESMRK1 regardless of layer', () {
      expect(_symbolOf(topmar01(_topmark(), options)), 'QUESMRK1');
      expect(
        _symbolOf(topmar01(_topmark(layerName: 'BOYLAT'), options)),
        'QUESMRK1',
      );
    });
  });

  group('topmar01 — floating parent (LITFLT / LITVES / BOY*)', () {
    test('LITFLT + TOPSHP 1 → TOPMAR02', () {
      expect(
        _symbolOf(
          topmar01(_topmark(topshp: 1, layerName: 'LITFLT'), options),
        ),
        'TOPMAR02',
      );
    });

    test('LITVES + TOPSHP 7 → TOPMAR65', () {
      expect(
        _symbolOf(
          topmar01(_topmark(topshp: 7, layerName: 'LITVES'), options),
        ),
        'TOPMAR65',
      );
    });

    test('BOYLAT + TOPSHP 17 → TMARDEF2 (explicit mapping)', () {
      expect(
        _symbolOf(
          topmar01(_topmark(topshp: 17, layerName: 'BOYLAT'), options),
        ),
        'TMARDEF2',
      );
    });

    test('BOYISD + TOPSHP 33 → TMARDEF2', () {
      expect(
        _symbolOf(
          topmar01(_topmark(topshp: 33, layerName: 'BOYISD'), options),
        ),
        'TMARDEF2',
      );
    });

    test('floating + unknown TOPSHP → TMARDEF2 fallback', () {
      expect(
        _symbolOf(
          topmar01(_topmark(topshp: 99, layerName: 'BOYSPP'), options),
        ),
        'TMARDEF2',
      );
    });

    test('spot checks across the floating table', () {
      const cases = {
        2: 'TOPMAR04',
        3: 'TOPMAR10',
        4: 'TOPMAR12',
        5: 'TOPMAR13',
        9: 'TOPMAR16',
        13: 'TOPMAR05',
        24: 'TOPMAR02',
        31: 'TOPMAR14',
      };
      for (final e in cases.entries) {
        final out = topmar01(
          _topmark(topshp: e.key, layerName: 'BOYLAT'),
          options,
        );
        expect(_symbolOf(out), e.value, reason: 'TOPSHP=${e.key}');
      }
    });
  });

  group('topmar01 — fixed parent (non-floating)', () {
    test('BCNLAT + TOPSHP 1 → TOPMAR22', () {
      expect(
        _symbolOf(
          topmar01(_topmark(topshp: 1, layerName: 'BCNLAT'), options),
        ),
        'TOPMAR22',
      );
    });

    test('DAYMAR + TOPSHP 15 → TOPMAR88 (fixed-only entry)', () {
      expect(
        _symbolOf(
          topmar01(_topmark(topshp: 15, layerName: 'DAYMAR'), options),
        ),
        'TOPMAR88',
      );
    });

    test('fixed + TOPSHP 17 → TMARDEF1', () {
      expect(
        _symbolOf(
          topmar01(_topmark(topshp: 17, layerName: 'BCNCAR'), options),
        ),
        'TMARDEF1',
      );
    });

    test('fixed + unknown TOPSHP → TMARDEF1 fallback', () {
      expect(
        _symbolOf(
          topmar01(_topmark(topshp: 99, layerName: 'BCNLAT'), options),
        ),
        'TMARDEF1',
      );
    });

    test('no layerName at all uses objectClass (TOPMAR) → fixed path', () {
      // objectClass "TOPMAR" doesn't start with "BOY", so floating=false.
      expect(
        _symbolOf(topmar01(_topmark(topshp: 1), options)),
        'TOPMAR22',
      );
    });
  });

  group('topmar01 — output shape', () {
    test('always emits exactly one S52Symbol', () {
      final out = topmar01(
        _topmark(topshp: 5, layerName: 'BOYLAT'),
        options,
      );
      expect(out, hasLength(1));
      expect(out.single, isA<S52Symbol>());
    });

    test('raw field round-trips through the symbol name', () {
      final out = topmar01(
        _topmark(topshp: 6, layerName: 'BOYLAT'),
        options,
      );
      expect(out.single.raw, 'SY(TOPMAR14)');
    });
  });

  group('topmar01 registration', () {
    test('standardCsProcedures registers TOPMAR01', () {
      expect(standardCsProcedures['TOPMAR01'], same(topmar01));
    });
  });
}
