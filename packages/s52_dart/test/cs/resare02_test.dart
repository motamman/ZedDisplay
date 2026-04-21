import 'package:s52_dart/s52_dart.dart';
import 'package:test/test.dart';

S52Feature _f(String? restrn) => S52Feature(
      objectClass: 'RESARE',
      geometryType: S52GeometryType.area,
      attributes: {if (restrn != null) 'RESTRN': restrn},
    );

void main() {
  const options = S52Options();

  test('resare02 always prepends the dashed CHMGD outline', () {
    final out = resare02(_f(null), options);
    expect(out, hasLength(1));
    final ls = out.single as S52LineStyle;
    expect(ls.pattern, S52LinePattern.dash);
    expect(ls.width, 2);
    expect(ls.colorCode, 'CHMGD');
  });

  test('resare02 with RESTRN delegates to restrn01 after the outline', () {
    final out = resare02(_f('9'), options);
    expect(out, hasLength(2));
    expect(out[0], isA<S52LineStyle>());
    expect((out[0] as S52LineStyle).colorCode, 'CHMGD');
    expect(out[1], isA<S52Symbol>());
    expect((out[1] as S52Symbol).name, 'DRGARE51');
  });

  test('resare02 is registered under both RESARE01 and RESARE02 aliases', () {
    expect(standardCsProcedures['RESARE02'], same(resare02));
    expect(standardCsProcedures['RESARE01'], same(resare02));
  });
}
