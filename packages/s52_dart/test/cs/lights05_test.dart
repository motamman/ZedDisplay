import 'package:s52_dart/s52_dart.dart';
import 'package:test/test.dart';

S52Feature _light(String colour) => S52Feature(
      objectClass: 'LIGHTS',
      geometryType: S52GeometryType.point,
      attributes: {'COLOUR': colour},
    );

String _symbolOf(List<S52Instruction> out) =>
    (out.single as S52Symbol).name;

void main() {
  const options = S52Options();

  group('lights05 — single-value COLOUR', () {
    test('red (3) → LIGHTS11', () {
      expect(_symbolOf(lights05(_light('3'), options)), 'LIGHTS11');
    });

    test('green (4) → LIGHTS12', () {
      expect(_symbolOf(lights05(_light('4'), options)), 'LIGHTS12');
    });

    test('white (1) → LIGHTS13', () {
      expect(_symbolOf(lights05(_light('1'), options)), 'LIGHTS13');
    });

    test('yellow (6) → LIGHTS13', () {
      expect(_symbolOf(lights05(_light('6'), options)), 'LIGHTS13');
    });

    test('orange (13) → LIGHTS13', () {
      expect(_symbolOf(lights05(_light('13'), options)), 'LIGHTS13');
    });

    test('unmapped colour → empty', () {
      expect(lights05(_light('2'), options), isEmpty);
      expect(lights05(_light('99'), options), isEmpty);
    });
  });

  group('lights05 — two-value COLOUR', () {
    test('white+red (1,3) → LIGHTS11', () {
      expect(_symbolOf(lights05(_light('1,3'), options)), 'LIGHTS11');
      expect(_symbolOf(lights05(_light('3,1'), options)), 'LIGHTS11');
    });

    test('white+green (1,4) → LIGHTS12', () {
      expect(_symbolOf(lights05(_light('1,4'), options)), 'LIGHTS12');
      expect(_symbolOf(lights05(_light('4,1'), options)), 'LIGHTS12');
    });

    test('unmapped pair → empty', () {
      expect(lights05(_light('3,4'), options), isEmpty);
      expect(lights05(_light('6,13'), options), isEmpty);
    });
  });

  group('lights05 — edge cases', () {
    test('three or more COLOUR values → empty', () {
      // Freeboard only handles length-1 and length-2 cases; triples
      // fall through to the "no instruction" branch. Preserved for
      // V1 parity even if the IHO spec has guidance for sectored
      // lights with 3+ colours.
      expect(lights05(_light('1,3,4'), options), isEmpty);
    });

    test('missing COLOUR attribute → empty', () {
      const f = S52Feature(
        objectClass: 'LIGHTS',
        geometryType: S52GeometryType.point,
      );
      expect(lights05(f, options), isEmpty);
    });

    test('empty COLOUR string → empty', () {
      expect(lights05(_light(''), options), isEmpty);
    });

    test('emitted instruction carries raw field for diagnostics', () {
      final out = lights05(_light('3'), options);
      expect(out.single.raw, 'SY(LIGHTS11)');
    });
  });

  group('standardCsProcedures', () {
    test('registers LIGHTS05', () {
      expect(standardCsProcedures['LIGHTS05'], same(lights05));
    });

    test('plugs into the engine end-to-end', () {
      // Build a minimal lookup table that routes LIGHTS points
      // through CS(LIGHTS05).
      final lookups = LookupTable.fromJson(<String, dynamic>{
        'lookups': [
          {
            'id': 1,
            'name': 'LIGHTS',
            'geometryType': 0,
            'lookupTable': 0,
            'instruction': 'CS(LIGHTS05)',
            'attributes': <String, dynamic>{},
            'displayPriority': 4,
            'displayCategory': 2,
          },
        ],
        'lookupStartIndex': {'0,LIGHTS,0': 0},
      });
      final engine = S52StyleEngine(
        lookups: lookups,
        options: const S52Options(
          graphicsStyle: S52GraphicsStyle.simplified,
          displayCategory: S52DisplayCategory.other,
        ),
        csProcedures: standardCsProcedures,
      );
      final out = engine.styleFeature(_light('3'));
      expect(out, hasLength(1));
      expect((out.single as S52Symbol).name, 'LIGHTS11');
    });
  });
}
