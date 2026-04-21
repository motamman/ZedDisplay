/// S-52 palette colour. RGBA with 8-bit R/G/B and a floating-point alpha
/// in the range \[0..1\]. Immutable.
///
/// The canonical on-disk format (from the OpenCPN-derived
/// `s57_colors.json` asset) is the string `"RGBA(r, g, b, a)"`, e.g.
/// `"RGBA(163, 180, 183, 1)"`. Use [S52Color.parse] to decode.
class S52Color {
  const S52Color({
    required this.r,
    required this.g,
    required this.b,
    this.a = 1.0,
  })  : assert(r >= 0 && r <= 255, 'r out of range'),
        assert(g >= 0 && g <= 255, 'g out of range'),
        assert(b >= 0 && b <= 255, 'b out of range'),
        assert(a >= 0 && a <= 1, 'a out of range');

  final int r;
  final int g;
  final int b;
  final double a;

  static final RegExp _rgbaPattern = RegExp(
    r'^\s*RGBA\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([0-9.]+)\s*\)\s*$',
    caseSensitive: false,
  );

  /// Parse the OpenCPN `RGBA(r, g, b, a)` string form.
  ///
  /// Throws [FormatException] if the input does not match.
  static S52Color parse(String raw) {
    final m = _rgbaPattern.firstMatch(raw);
    if (m == null) {
      throw FormatException('Invalid S52 colour literal: "$raw"');
    }
    return S52Color(
      r: int.parse(m.group(1)!),
      g: int.parse(m.group(2)!),
      b: int.parse(m.group(3)!),
      a: double.parse(m.group(4)!),
    );
  }

  /// Pack to 0xAARRGGBB as a 32-bit integer. Handy for renderers that
  /// take [int] colours (Flutter's `Color` constructor, for instance).
  int toArgb32() {
    final alpha = (a.clamp(0.0, 1.0) * 255).round() & 0xff;
    return (alpha << 24) | (r << 16) | (g << 8) | b;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is S52Color &&
          other.r == r &&
          other.g == g &&
          other.b == b &&
          other.a == a;

  @override
  int get hashCode => Object.hash(r, g, b, a);

  @override
  String toString() => 'S52Color(r: $r, g: $g, b: $b, a: $a)';
}

/// Named S-52 colour table. Keys are 5-character S-52 colour codes
/// (NODTA, CHBLK, CHGRF, DEPDW, etc.). Missing keys throw on lookup.
class S52ColorTable {
  const S52ColorTable(this._colors);

  final Map<String, S52Color> _colors;

  /// Construct from a map whose values are OpenCPN `RGBA(...)` strings.
  /// Throws [FormatException] if any value fails to parse.
  factory S52ColorTable.fromRawMap(Map<String, String> raw) {
    final parsed = <String, S52Color>{};
    for (final entry in raw.entries) {
      parsed[entry.key] = S52Color.parse(entry.value);
    }
    return S52ColorTable(Map.unmodifiable(parsed));
  }

  /// Number of colours in the table.
  int get length => _colors.length;

  /// Return the colour for [code], or null if unknown.
  S52Color? lookup(String code) => _colors[code];

  /// Return the colour for [code]. Throws [StateError] if missing.
  S52Color operator [](String code) {
    final c = _colors[code];
    if (c == null) {
      throw StateError('Unknown S-52 colour code: "$code"');
    }
    return c;
  }

  /// Unmodifiable view of all code→colour entries.
  Map<String, S52Color> get all => Map.unmodifiable(_colors);
}
