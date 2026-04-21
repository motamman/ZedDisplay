import 'package:s52_dart/s52_dart.dart';
import 'package:test/test.dart';

S52Feature _f(String? restrn) => S52Feature(
      objectClass: 'RESARE',
      geometryType: S52GeometryType.area,
      attributes: {if (restrn != null) 'RESTRN': restrn},
    );

Set<String> _symbols(List<S52Instruction> out) =>
    out.whereType<S52Symbol>().map((s) => s.name).toSet();

void main() {
  const options = S52Options();

  group('restrn01 absence and empties', () {
    test('missing RESTRN → empty', () {
      expect(restrn01(_f(null), options), isEmpty);
    });

    test('empty RESTRN string → empty', () {
      expect(restrn01(_f(''), options), isEmpty);
    });
  });

  group('restrn01 single-category branches', () {
    test('RESTRN 1 → ACHRES51 (anchoring restricted)', () {
      expect(_symbols(restrn01(_f('1'), options)), {'ACHRES51'});
    });

    test('RESTRN 2 → ACHRES51 (same bucket)', () {
      expect(_symbols(restrn01(_f('2'), options)), {'ACHRES51'});
    });

    test('RESTRN 3 or 4 → FSHRES51 (fishing restricted)', () {
      expect(_symbols(restrn01(_f('3'), options)), {'FSHRES51'});
      expect(_symbols(restrn01(_f('4'), options)), {'FSHRES51'});
    });

    test('RESTRN 5 or 6 → FSHRES71', () {
      expect(_symbols(restrn01(_f('5'), options)), {'FSHRES71'});
      expect(_symbols(restrn01(_f('6'), options)), {'FSHRES71'});
    });

    test('RESTRN 7, 8, or 14 → ENTRES51 (entry restricted)', () {
      for (final v in [7, 8, 14]) {
        expect(
          _symbols(restrn01(_f('$v'), options)),
          {'ENTRES51'},
          reason: 'RESTRN=$v',
        );
      }
    });

    test('RESTRN 9 or 10 → DRGARE51 (dredging)', () {
      expect(_symbols(restrn01(_f('9'), options)), {'DRGARE51'});
      expect(_symbols(restrn01(_f('10'), options)), {'DRGARE51'});
    });

    test('RESTRN 11 or 12 → DIVPRO51 (diving)', () {
      expect(_symbols(restrn01(_f('11'), options)), {'DIVPRO51'});
      expect(_symbols(restrn01(_f('12'), options)), {'DIVPRO51'});
    });

    test('RESTRN 13 → ENTRES61', () {
      expect(_symbols(restrn01(_f('13'), options)), {'ENTRES61'});
    });

    test('RESTRN 27 → ENTRES71', () {
      expect(_symbols(restrn01(_f('27'), options)), {'ENTRES71'});
    });

    test('RESTRN with unmapped code alone → ENTRES61 fallback', () {
      expect(_symbols(restrn01(_f('99'), options)), {'ENTRES61'});
    });
  });

  group('restrn01 multi-category', () {
    test('RESTRN 1,9 → ACHRES51 + DRGARE51', () {
      expect(
        _symbols(restrn01(_f('1,9'), options)),
        {'ACHRES51', 'DRGARE51'},
      );
    });

    test('RESTRN 3,5,7 → FSHRES51 + FSHRES71 + ENTRES51', () {
      expect(
        _symbols(restrn01(_f('3,5,7'), options)),
        {'FSHRES51', 'FSHRES71', 'ENTRES51'},
      );
    });
  });

  group('restrn01 registration', () {
    test('standardCsProcedures registers RESTRN01', () {
      expect(standardCsProcedures['RESTRN01'], same(restrn01));
    });
  });
}
