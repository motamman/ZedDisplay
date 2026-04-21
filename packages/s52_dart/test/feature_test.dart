import 'package:s52_dart/s52_dart.dart';
import 'package:test/test.dart';

void main() {
  group('S52Feature', () {
    test('attrString returns empty on missing', () {
      const f = S52Feature(
        objectClass: 'DEPARE',
        geometryType: S52GeometryType.area,
      );
      expect(f.attrString('DRVAL1'), '');
    });

    test('attrString stringifies numeric values', () {
      const f = S52Feature(
        objectClass: 'DEPARE',
        geometryType: S52GeometryType.area,
        attributes: {'DRVAL1': 2.5},
      );
      expect(f.attrString('DRVAL1'), '2.5');
    });

    test('attrDouble parses stringified numerics', () {
      const f = S52Feature(
        objectClass: 'DEPARE',
        geometryType: S52GeometryType.area,
        attributes: {'DRVAL1': '2.5'},
      );
      expect(f.attrDouble('DRVAL1'), 2.5);
    });

    test('attrDouble returns fallback on missing', () {
      const f = S52Feature(
        objectClass: 'DEPARE',
        geometryType: S52GeometryType.area,
      );
      expect(f.attrDouble('DRVAL1', fallback: -1), -1);
    });

    test('attrDouble returns fallback on unparseable string', () {
      const f = S52Feature(
        objectClass: 'DEPARE',
        geometryType: S52GeometryType.area,
        attributes: {'DRVAL1': 'unknown'},
      );
      expect(f.attrDouble('DRVAL1', fallback: 0), 0);
    });

    test('attrInt handles int, num, and string inputs', () {
      const intF = S52Feature(
        objectClass: 'X',
        geometryType: S52GeometryType.point,
        attributes: {'K': 42},
      );
      expect(intF.attrInt('K'), 42);

      const doubleF = S52Feature(
        objectClass: 'X',
        geometryType: S52GeometryType.point,
        attributes: {'K': 42.9},
      );
      expect(doubleF.attrInt('K'), 42);

      const stringF = S52Feature(
        objectClass: 'X',
        geometryType: S52GeometryType.point,
        attributes: {'K': '42'},
      );
      expect(stringF.attrInt('K'), 42);
    });

    test('attrList splits on comma and trims', () {
      const f = S52Feature(
        objectClass: 'LIGHTS',
        geometryType: S52GeometryType.point,
        attributes: {'COLOUR': '1, 3, 11'},
      );
      expect(f.attrList('COLOUR'), ['1', '3', '11']);
    });

    test('attrList returns empty on missing', () {
      const f = S52Feature(
        objectClass: 'LIGHTS',
        geometryType: S52GeometryType.point,
      );
      expect(f.attrList('COLOUR'), isEmpty);
    });

    test('hasAttr true only when present and non-empty', () {
      const empty = S52Feature(
        objectClass: 'X',
        geometryType: S52GeometryType.point,
        attributes: {'A': ''},
      );
      expect(empty.hasAttr('A'), isFalse);

      const present = S52Feature(
        objectClass: 'X',
        geometryType: S52GeometryType.point,
        attributes: {'A': 'yes'},
      );
      expect(present.hasAttr('A'), isTrue);

      const zero = S52Feature(
        objectClass: 'X',
        geometryType: S52GeometryType.point,
        attributes: {'A': 0},
      );
      expect(zero.hasAttr('A'), isTrue);
    });

    test('effectiveLayerName prefers layerName over objectClass', () {
      const withLayer = S52Feature(
        objectClass: 'TOPMAR',
        geometryType: S52GeometryType.point,
        layerName: 'LITFLT',
      );
      expect(withLayer.effectiveLayerName, 'LITFLT');

      const noLayer = S52Feature(
        objectClass: 'TOPMAR',
        geometryType: S52GeometryType.point,
      );
      expect(noLayer.effectiveLayerName, 'TOPMAR');
    });
  });
}
