import 'package:s52_dart/s52_dart.dart';
import 'package:test/test.dart';

void main() {
  group('SpriteMeta.fromJson', () {
    test('parses a full entry matching the asset shape', () {
      final meta = SpriteMeta.fromJson('ACHARE02', {
        'x': 10,
        'y': 10,
        'width': 13,
        'height': 16,
        'pixelRatio': 1,
        'sdf': false,
        'pivotX': 6,
        'pivotY': 8,
        'originX': 0,
        'originY': 0,
      });
      expect(meta.name, 'ACHARE02');
      expect(meta.x, 10);
      expect(meta.y, 10);
      expect(meta.width, 13);
      expect(meta.height, 16);
      expect(meta.pivotX, 6);
      expect(meta.pivotY, 8);
      expect(meta.pixelRatio, 1);
      expect(meta.sdf, isFalse);
    });

    test('applies sensible defaults for optional fields', () {
      final meta = SpriteMeta.fromJson('X', {
        'x': 0,
        'y': 0,
        'width': 1,
        'height': 1,
      });
      expect(meta.pixelRatio, 1);
      expect(meta.sdf, isFalse);
      expect(meta.pivotX, 0);
      expect(meta.pivotY, 0);
      expect(meta.originX, 0);
      expect(meta.originY, 0);
    });

    test('handles num-as-int coercion (pixelRatio as double)', () {
      final meta = SpriteMeta.fromJson('X', {
        'x': 0,
        'y': 0,
        'width': 1,
        'height': 1,
        'pixelRatio': 2.0,
      });
      expect(meta.pixelRatio, 2);
    });
  });

  group('SpriteAtlas', () {
    test('constructs from the asset JSON layout', () {
      final atlas = SpriteAtlas.fromJson({
        'ACHARE02': {
          'x': 10,
          'y': 10,
          'width': 13,
          'height': 16,
          'pivotX': 6,
          'pivotY': 8,
        },
        'LIGHTS13': {
          'x': 100,
          'y': 200,
          'width': 11,
          'height': 11,
          'pivotX': 5,
          'pivotY': 5,
        },
      });
      expect(atlas.length, 2);
      expect(atlas.lookup('ACHARE02')?.pivotX, 6);
      expect(atlas.lookup('LIGHTS13')?.x, 100);
      expect(atlas.lookup('UNKNOWN'), isNull);
      expect(atlas.names.toSet(), {'ACHARE02', 'LIGHTS13'});
    });

    test('is an unmodifiable view', () {
      final atlas = SpriteAtlas.fromJson({});
      expect(
        () => atlas.all['X'] = const SpriteMeta(
          name: 'X',
          x: 0,
          y: 0,
          width: 1,
          height: 1,
        ),
        throwsUnsupportedError,
      );
    });
  });
}
