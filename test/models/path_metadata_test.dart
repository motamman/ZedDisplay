import 'package:flutter_test/flutter_test.dart';
import 'package:zed_display/models/path_metadata.dart';

void main() {
  group('PathMetadata.convert', () {
    test('returns identity for null formula', () {
      final m = PathMetadata(path: 'x');
      expect(m.convert(42.0), 42.0);
    });

    test('returns identity for "value" formula', () {
      final m = PathMetadata(path: 'x', formula: 'value');
      expect(m.convert(42.0), 42.0);
    });

    test('applies simple multiply formula', () {
      final m = PathMetadata(path: 'x', formula: 'value * 1.94384');
      expect(m.convert(1.0)!, closeTo(1.94384, 1e-9));
    });

    test('applies parenthesized temperature formula (K->F)', () {
      final m = PathMetadata(
        path: 'x',
        formula: '(value - 273.15) * 9/5 + 32',
      );
      final f = m.convert(273.15);
      expect(f, isNotNull);
      expect(f!, closeTo(32.0, 1e-6));
    });

    test('applies K->C formula', () {
      final m = PathMetadata(path: 'x', formula: 'value - 273.15');
      expect(m.convert(300.0)!, closeTo(26.85, 1e-6));
    });

    test('returns null on broken formula', () {
      final m = PathMetadata(path: 'x', formula: 'not a formula !!!');
      expect(m.convert(42.0), isNull);
    });
  });

  group('PathMetadata.convertToSI', () {
    test('applies inverse formula', () {
      final m = PathMetadata(
        path: 'x',
        inverseFormula: 'value * 0.514444',
      );
      expect(m.convertToSI(1.0)!, closeTo(0.514444, 1e-9));
    });

    test('identity when inverseFormula is null', () {
      final m = PathMetadata(path: 'x');
      expect(m.convertToSI(10.0), 10.0);
    });
  });

  group('PathMetadata.format', () {
    test('formats with symbol when present', () {
      final m = PathMetadata(
        path: 'x',
        formula: 'value * 1.94384',
        symbol: 'kn',
      );
      expect(m.format(1.0), '1.9 kn');
    });

    test('formats without symbol when missing', () {
      final m = PathMetadata(path: 'x', formula: 'value');
      expect(m.format(1.2345, decimals: 2), '1.23');
    });
  });

  group('MetadataFormatExtension.formatOrRaw', () {
    test('null metadata + null value -> placeholder', () {
      const PathMetadata? meta = null;
      expect(meta.formatOrRaw(null), '--');
    });

    test('null metadata + value + siSuffix -> raw + suffix', () {
      const PathMetadata? meta = null;
      expect(
        meta.formatOrRaw(0.45, decimals: 2, siSuffix: 'rad'),
        '0.45 rad',
      );
    });

    test('null metadata + value + no suffix -> raw only', () {
      const PathMetadata? meta = null;
      expect(meta.formatOrRaw(0.45, decimals: 2), '0.45');
    });

    test('non-null metadata + null value -> placeholder', () {
      final meta = PathMetadata(
        path: 'x',
        formula: 'value * 1.94384',
        symbol: 'kn',
      );
      expect(meta.formatOrRaw(null), '--');
    });

    test('non-null metadata + value -> delegates to format', () {
      final meta = PathMetadata(
        path: 'x',
        formula: 'value * 1.94384',
        symbol: 'kn',
      );
      expect(meta.formatOrRaw(1.0), '1.9 kn');
    });

    test('custom placeholder', () {
      const PathMetadata? meta = null;
      expect(meta.formatOrRaw(null, placeholder: 'N/A'), 'N/A');
    });
  });

  group('PathMetadata.fromDisplayUnits', () {
    test('reads targetUnit from units then symbol', () {
      final m1 = PathMetadata.fromDisplayUnits('p', {'units': 'kn'});
      expect(m1.targetUnit, 'kn');

      final m2 = PathMetadata.fromDisplayUnits('p', {'symbol': '°C'});
      expect(m2.targetUnit, '°C');
    });
  });

  group('PathMetadata.toJson/fromJson roundtrip', () {
    test('roundtrips core fields', () {
      final original = PathMetadata(
        path: 'navigation.speedOverGround',
        baseUnit: 'm/s',
        targetUnit: 'kn',
        category: 'speed',
        formula: 'value * 1.94384',
        inverseFormula: 'value * 0.514444',
        symbol: 'kn',
      );
      final roundtripped = PathMetadata.fromJson(original.toJson());
      expect(roundtripped.path, original.path);
      expect(roundtripped.formula, original.formula);
      expect(roundtripped.inverseFormula, original.inverseFormula);
      expect(roundtripped.symbol, original.symbol);
      expect(roundtripped.category, original.category);
    });
  });
}
