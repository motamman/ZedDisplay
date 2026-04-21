import 'package:s52_dart/s52_dart.dart';
import 'package:test/test.dart';

void main() {
  group('S52Color.parse', () {
    test('parses canonical OpenCPN format', () {
      final c = S52Color.parse('RGBA(163, 180, 183, 1)');
      expect(c.r, 163);
      expect(c.g, 180);
      expect(c.b, 183);
      expect(c.a, 1.0);
    });

    test('accepts fractional alpha', () {
      final c = S52Color.parse('RGBA(0, 0, 0, 0.5)');
      expect(c.a, 0.5);
    });

    test('is case-insensitive on the RGBA token', () {
      final c = S52Color.parse('rgba(1,2,3,1)');
      expect(c, const S52Color(r: 1, g: 2, b: 3));
    });

    test('tolerates extra whitespace', () {
      final c = S52Color.parse('  RGBA( 10 , 20 , 30 , 1 )  ');
      expect(c, const S52Color(r: 10, g: 20, b: 30));
    });

    test('rejects malformed input', () {
      expect(() => S52Color.parse('not a colour'), throwsFormatException);
      expect(() => S52Color.parse('rgb(1,2,3)'), throwsFormatException);
      expect(() => S52Color.parse(''), throwsFormatException);
    });
  });

  group('S52Color', () {
    test('equality and hashCode', () {
      expect(
        const S52Color(r: 1, g: 2, b: 3),
        equals(const S52Color(r: 1, g: 2, b: 3)),
      );
      expect(
        const S52Color(r: 1, g: 2, b: 3).hashCode,
        equals(const S52Color(r: 1, g: 2, b: 3).hashCode),
      );
      expect(
        const S52Color(r: 1, g: 2, b: 3),
        isNot(equals(const S52Color(r: 1, g: 2, b: 4))),
      );
    });

    test('toArgb32 packs channels correctly', () {
      const black = S52Color(r: 0, g: 0, b: 0);
      expect(black.toArgb32(), 0xff000000);

      const white = S52Color(r: 255, g: 255, b: 255);
      expect(white.toArgb32(), 0xffffffff);

      const half = S52Color(r: 0x12, g: 0x34, b: 0x56, a: 0.5);
      // alpha=0.5 * 255 = 127.5 rounds to 128 = 0x80
      expect(half.toArgb32(), 0x80123456);
    });

    test('rejects out-of-range channels', () {
      // ignore_for_file: prefer_const_constructors
      // Runtime assertions — must NOT be const, or the failure is a
      // compile-time error instead of the runtime throw we're testing.
      expect(
        () => S52Color(r: -1, g: 0, b: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => S52Color(r: 256, g: 0, b: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => S52Color(r: 0, g: 0, b: 0, a: 2),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('S52ColorTable', () {
    test('constructs from raw map and resolves by code', () {
      final table = S52ColorTable.fromRawMap({
        'NODTA': 'RGBA(163, 180, 183, 1)',
        'CHBLK': 'RGBA(7, 7, 7, 1)',
      });
      expect(table.length, 2);
      expect(table['NODTA'], const S52Color(r: 163, g: 180, b: 183));
      expect(table.lookup('UNKNOWN'), isNull);
    });

    test('throws on unknown operator[]', () {
      final table = S52ColorTable.fromRawMap(const {});
      expect(() => table['NOPE'], throwsStateError);
    });

    test('propagates parse errors from fromRawMap', () {
      expect(
        () => S52ColorTable.fromRawMap({'X': 'garbage'}),
        throwsFormatException,
      );
    });

    test('all is an unmodifiable view', () {
      final table = S52ColorTable.fromRawMap({
        'NODTA': 'RGBA(1, 2, 3, 1)',
      });
      expect(
        () => table.all['HACK'] = const S52Color(r: 0, g: 0, b: 0),
        throwsUnsupportedError,
      );
    });
  });
}
