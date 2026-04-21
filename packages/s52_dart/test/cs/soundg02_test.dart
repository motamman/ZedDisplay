import 'package:s52_dart/s52_dart.dart';
import 'package:test/test.dart';

S52Feature _sounding({double? depth, double? valsou}) {
  final attrs = <String, Object?>{};
  if (depth != null) attrs['DEPTH'] = depth;
  if (valsou != null) attrs['VALSOU'] = valsou;
  return S52Feature(
    objectClass: 'SOUNDG',
    geometryType: S52GeometryType.point,
    attributes: attrs,
  );
}

String _textOf(List<S52Instruction> out) =>
    (out.single as S52TextLiteral).text;

void main() {
  group('soundg02 attribute resolution', () {
    test('prefers DEPTH over VALSOU', () {
      const options = S52Options();
      final out = soundg02(_sounding(depth: 5.2, valsou: 99), options);
      expect(_textOf(out), '5');
    });

    test('falls back to VALSOU when DEPTH absent', () {
      const options = S52Options();
      expect(_textOf(soundg02(_sounding(valsou: 12), options)), '12');
    });

    test('no depth attribute at all → empty output', () {
      const options = S52Options();
      final f = S52Feature(
        objectClass: 'SOUNDG',
        geometryType: S52GeometryType.point,
      );
      expect(soundg02(f, options), isEmpty);
    });
  });

  group('soundg02 metric formatting', () {
    test('zoomed out (no resolution) → whole metres', () {
      const options = S52Options();
      expect(_textOf(soundg02(_sounding(depth: 3.7), options)), '4');
      expect(_textOf(soundg02(_sounding(depth: 11.2), options)), '11');
    });

    test('zoomed in (< 5 m/px) with fractional depth → one decimal', () {
      const options = S52Options(currentResolution: 2);
      expect(_textOf(soundg02(_sounding(depth: 3.7), options)), '3.7');
      expect(_textOf(soundg02(_sounding(depth: 2.1), options)), '2.1');
    });

    test('zoomed in with integer-valued depth → no trailing decimal', () {
      const options = S52Options(currentResolution: 2);
      expect(_textOf(soundg02(_sounding(depth: 3.0), options)), '3');
      expect(_textOf(soundg02(_sounding(depth: 11), options)), '11');
    });

    test('negative depths keep their sign', () {
      const options = S52Options();
      expect(_textOf(soundg02(_sounding(depth: -1.8), options)), '-2');
    });
  });

  group('soundg02 non-metric formatting', () {
    test('feet (conversionFactor 3.28084) → whole numbers', () {
      const options = S52Options(
        depthUnit: 'ft',
        depthConversionFactor: 3.28084,
      );
      // 3 m = 9.84252 ft → rounds to 10
      expect(_textOf(soundg02(_sounding(depth: 3), options)), '10');
      // 2.1 m = 6.89 ft → rounds to 7
      expect(_textOf(soundg02(_sounding(depth: 2.1), options)), '7');
    });

    test('fathoms (conversionFactor 0.5468) → whole numbers', () {
      const options = S52Options(
        depthUnit: 'fm',
        depthConversionFactor: 0.5468,
      );
      // 11 m * 0.5468 ≈ 6.01 fm → rounds to 6
      expect(_textOf(soundg02(_sounding(depth: 11), options)), '6');
    });
  });

  group('soundg02 output shape', () {
    test('emits an S52TextLiteral with Freeboard-compatible params', () {
      const options = S52Options();
      final out = soundg02(_sounding(depth: 5), options);
      expect(out.single, isA<S52TextLiteral>());
      final tl = out.single as S52TextLiteral;
      expect(tl.params, ['1', '2', '2']);
      expect(tl.raw, 'TX(_SOUNDG_WHOLE,1,2,2)');
    });
  });

  group('soundg02 registration', () {
    test('standardCsProcedures registers SOUNDG02', () {
      expect(standardCsProcedures['SOUNDG02'], same(soundg02));
    });
  });
}
