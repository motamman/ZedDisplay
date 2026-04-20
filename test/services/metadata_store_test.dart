import 'package:flutter_test/flutter_test.dart';
import 'package:zed_display/models/path_metadata.dart';
import 'package:zed_display/services/metadata_store.dart';

void main() {
  group('MetadataStore.updateFromMeta', () {
    test('adds a new entry', () {
      final store = MetadataStore();
      store.updateFromMeta('navigation.speedOverGround', {
        'units': 'kn',
        'formula': 'value * 1.94384',
        'inverseFormula': 'value * 0.514444',
        'symbol': 'kn',
      });
      final meta = store.get('navigation.speedOverGround');
      expect(meta, isNotNull);
      expect(meta!.symbol, 'kn');
      expect(meta.formula, 'value * 1.94384');
    });

    test('preserves existing formula when incoming has none', () {
      final store = MetadataStore();
      store.updateFromMeta('p', {
        'formula': 'value * 1.94384',
        'symbol': 'kn',
      });
      // A second delta that only carries category should NOT clobber formula.
      store.updateFromMeta('p', {'category': 'speed'});
      final meta = store.get('p');
      expect(meta!.formula, 'value * 1.94384');
      expect(meta.category, 'speed');
    });

    test('field-by-field merge propagates symbol updates even when '
        'existing has a formula', () {
      final store = MetadataStore();
      store.updateFromMeta('p', {
        'formula': 'value * 1.94384',
        'inverseFormula': 'value * 0.514444',
        'symbol': 'kn',
        'category': 'speed',
      });
      // A later delta with just a symbol change must update symbol but
      // preserve formula / inverseFormula / category.
      store.updateFromMeta('p', {'symbol': 'm/s'});
      final meta = store.get('p')!;
      expect(meta.symbol, 'm/s');
      expect(meta.formula, 'value * 1.94384');
      expect(meta.inverseFormula, 'value * 0.514444');
      expect(meta.category, 'speed');
    });
  });

  group('MetadataStore.updateSymbol', () {
    test('creates a minimal entry when path is unknown', () {
      final store = MetadataStore();
      store.updateSymbol('unknown.path', 'kn');
      final meta = store.get('unknown.path');
      expect(meta, isNotNull);
      expect(meta!.symbol, 'kn');
      expect(meta.targetUnit, isNull,
          reason: 'plugin symbol must not leak into targetUnit');
      expect(meta.formula, isNull);
    });

    test('updates only symbol, preserving formula and targetUnit', () {
      final store = MetadataStore();
      store.updateFromMeta('p', {
        'units': 'fahrenheit',
        'symbol': '°F',
        'formula': '(value - 273.15) * 9/5 + 32',
      });
      store.updateSymbol('p', '°F');
      final meta = store.get('p')!;
      expect(meta.symbol, '°F');
      expect(meta.targetUnit, 'fahrenheit',
          reason: 'canonical unit id must not be overwritten by symbol');
      expect(meta.formula, '(value - 273.15) * 9/5 + 32');
    });

    test('is a no-op when symbol is unchanged', () {
      final store = MetadataStore();
      store.updateSymbol('p', 'kn');
      int notified = 0;
      store.addListener(() => notified++);
      store.updateSymbol('p', 'kn');
      expect(notified, 0);
    });
  });

  group('MetadataStore.convert (strict null-on-missing)', () {
    test('returns null when metadata is missing', () {
      final store = MetadataStore();
      expect(store.convert('unknown.path', 42.0), isNull);
    });

    test('applies formula when metadata exists', () {
      final store = MetadataStore();
      store.updateFromMeta('p', {'formula': 'value * 2'});
      expect(store.convert('p', 5.0), 10.0);
    });
  });

  group('MetadataStore.tryConvert (strict null-on-missing)', () {
    test('returns null when metadata is missing', () {
      final store = MetadataStore();
      expect(store.tryConvert('unknown.path', 42.0), isNull);
    });

    test('applies formula when metadata exists', () {
      final store = MetadataStore();
      store.updateFromMeta('p', {'formula': 'value * 1.94384'});
      expect(store.tryConvert('p', 1.0)!, closeTo(1.94384, 1e-9));
    });
  });

  group('MetadataStore.tryConvertToSI', () {
    test('returns null when metadata is missing', () {
      final store = MetadataStore();
      expect(store.tryConvertToSI('unknown.path', 42.0), isNull);
    });

    test('applies inverse formula when metadata exists', () {
      final store = MetadataStore();
      store.updateFromMeta('p', {'inverseFormula': 'value * 0.514444'});
      expect(store.tryConvertToSI('p', 1.0)!, closeTo(0.514444, 1e-9));
    });
  });

  group('MetadataStore.format', () {
    test('returns raw string when metadata missing', () {
      final store = MetadataStore();
      expect(store.format('unknown.path', 1.234, decimals: 2), '1.23');
    });

    test('delegates to PathMetadata.format when present', () {
      final store = MetadataStore();
      store.updateFromMeta('p', {
        'formula': 'value * 1.94384',
        'symbol': 'kn',
      });
      expect(store.format('p', 1.0), '1.9 kn');
    });
  });

  group('MetadataStore.getByCategory', () {
    test('returns first metadata for a category', () {
      final store = MetadataStore();
      store.update(PathMetadata(
        path: 'navigation.speedOverGround',
        category: 'speed',
        formula: 'value * 1.94384',
        symbol: 'kn',
      ));
      final meta = store.getByCategory('speed');
      expect(meta, isNotNull);
      expect(meta!.symbol, 'kn');
    });

    test('returns null when no path has the category', () {
      final store = MetadataStore();
      expect(store.getByCategory('nonexistent'), isNull);
    });
  });

  group('MetadataStore.clear', () {
    test('empties the store and notifies listeners', () {
      final store = MetadataStore();
      store.update(PathMetadata(path: 'p', formula: 'value'));
      expect(store.isNotEmpty, isTrue);

      int notified = 0;
      store.addListener(() => notified++);

      store.clear();
      expect(store.isEmpty, isTrue);
      expect(notified, 1);
    });
  });
}
