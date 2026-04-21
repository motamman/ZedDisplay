/// Metadata for a single S-52 symbol in the sprite sheet. Describes
/// where the symbol lives inside the atlas PNG and where the anchor
/// point (pivot) is relative to the symbol's bitmap.
class SpriteMeta {
  const SpriteMeta({
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.pixelRatio = 1,
    this.sdf = false,
    this.pivotX = 0,
    this.pivotY = 0,
    this.originX = 0,
    this.originY = 0,
  });

  /// S-52 symbol name (e.g. `ACHARE02`, `LIGHTS13`).
  final String name;

  /// X offset of the symbol's top-left within the sprite sheet (pixels).
  final int x;

  /// Y offset of the symbol's top-left within the sprite sheet (pixels).
  final int y;

  /// Symbol width in pixels.
  final int width;

  /// Symbol height in pixels.
  final int height;

  /// Pixel density of the sprite sheet. Almost always 1 for OpenCPN
  /// day-symbols; kept for forward compatibility with @2x/@3x packs.
  final int pixelRatio;

  /// Signed-distance-field flag. SDF symbols can be resized smoothly;
  /// non-SDF are rendered at their native size.
  final bool sdf;

  /// Anchor X (pixels from the symbol's top-left) — the point that
  /// aligns with the feature's geographic coordinate.
  final int pivotX;

  /// Anchor Y (pixels from the symbol's top-left).
  final int pivotY;

  /// Origin X offset used by S-52 composite symbols; typically zero.
  final int originX;

  /// Origin Y offset used by S-52 composite symbols; typically zero.
  final int originY;

  factory SpriteMeta.fromJson(String name, Map<String, dynamic> json) {
    return SpriteMeta(
      name: name,
      x: json['x'] as int,
      y: json['y'] as int,
      width: json['width'] as int,
      height: json['height'] as int,
      pixelRatio: (json['pixelRatio'] as num?)?.toInt() ?? 1,
      sdf: json['sdf'] as bool? ?? false,
      pivotX: (json['pivotX'] as num?)?.toInt() ?? 0,
      pivotY: (json['pivotY'] as num?)?.toInt() ?? 0,
      originX: (json['originX'] as num?)?.toInt() ?? 0,
      originY: (json['originY'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() =>
      'SpriteMeta($name, rect=$x,$y ${width}x$height, pivot=$pivotX,$pivotY)';
}

/// Atlas of S-52 symbols. Keys are symbol names; values are the
/// metadata blocks describing each symbol's position in the sprite
/// sheet PNG.
///
/// The atlas is pure metadata — no pixels live here. Consumers hold
/// the actual sprite sheet (a single PNG) and use this atlas to decide
/// which sub-rectangle of the PNG to blit when a symbol is referenced
/// by an `SY(NAME)` S-52 instruction.
class SpriteAtlas {
  const SpriteAtlas(this._byName);

  final Map<String, SpriteMeta> _byName;

  /// Construct from the raw JSON layout used by `assets/charts/sprite.json`.
  /// Shape: `{ "ACHARE02": { "x": ..., "y": ..., ... }, ... }`.
  factory SpriteAtlas.fromJson(Map<String, dynamic> json) {
    final entries = <String, SpriteMeta>{};
    for (final e in json.entries) {
      final meta = e.value as Map<String, dynamic>;
      entries[e.key] = SpriteMeta.fromJson(e.key, meta);
    }
    return SpriteAtlas(Map.unmodifiable(entries));
  }

  /// Total number of symbols.
  int get length => _byName.length;

  /// Return the symbol metadata for [name], or null if unknown.
  SpriteMeta? lookup(String name) => _byName[name];

  /// All symbol names currently in the atlas.
  Iterable<String> get names => _byName.keys;

  /// Unmodifiable view of the full atlas.
  Map<String, SpriteMeta> get all => Map.unmodifiable(_byName);
}
