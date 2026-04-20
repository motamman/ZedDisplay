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
  });

  group('MetadataStore.convert (legacy identity-on-missing)', () {
    test('returns identity when metadata is missing', () {
      final store = MetadataStore();
      expect(store.convert('unknown.path', 42.0), 42.0);
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
