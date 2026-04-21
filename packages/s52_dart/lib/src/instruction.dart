/// Line-dash pattern for an `LS(...)` instruction.
enum S52LinePattern {
  /// Continuous line.
  solid('SOLD'),

  /// Evenly-spaced dashes.
  dash('DASH'),

  /// Evenly-spaced dots.
  dott('DOTT');

  const S52LinePattern(this.code);
  final String code;

  static S52LinePattern fromCode(String code) {
    for (final v in S52LinePattern.values) {
      if (v.code == code) return v;
    }
    throw FormatException('Unknown S52LinePattern: "$code"');
  }
}

/// Typed S-52 drawing instruction. Sealed hierarchy — renderers exhaust
/// the cases with a pattern match to translate into paint primitives.
///
/// Instances are produced by [S52InstructionParser.parse]. All carry the
/// [raw] source string so renderers can log a diagnostic when an
/// instruction type is unsupported.
sealed class S52Instruction {
  const S52Instruction({required this.raw});

  /// Original instruction string, for diagnostics.
  final String raw;
}

/// `SY(NAME)` — render the symbol named [name] from the sprite atlas.
class S52Symbol extends S52Instruction {
  const S52Symbol({required this.name, required super.raw});
  final String name;

  @override
  String toString() => 'S52Symbol($name)';
}

/// `LS(PATTERN, WIDTH, COLOR)` — draw a line with the given dash
/// [pattern], [width] in pixels, and colour-table code [colorCode].
class S52LineStyle extends S52Instruction {
  const S52LineStyle({
    required this.pattern,
    required this.width,
    required this.colorCode,
    required super.raw,
  });

  final S52LinePattern pattern;
  final int width;
  final String colorCode;

  @override
  String toString() =>
      'S52LineStyle(${pattern.code},$width,$colorCode)';
}

/// `LC(NAME)` — line drawn by repeating a complex symbol pattern along
/// the geometry. The pattern itself lives in the S-52 presentation
/// library (not implemented by every renderer).
class S52LineComplex extends S52Instruction {
  const S52LineComplex({required this.patternName, required super.raw});
  final String patternName;

  @override
  String toString() => 'S52LineComplex($patternName)';
}

/// `AC(CODE[,TRANS])` — fill an area polygon with the colour-table
/// code. Optional second arg is the S-52 transparency level (0–4),
/// where 0 = opaque and each step subtracts ~25% alpha. Renderers map
/// it to paint alpha — see [transparencyAlpha].
class S52AreaColor extends S52Instruction {
  const S52AreaColor({
    required this.colorCode,
    this.transparency = 0,
    required super.raw,
  });
  final String colorCode;
  final int transparency;

  /// Resolved alpha (0–255) for [transparency], following the S-52
  /// PresLib mapping. Levels outside 0–4 clamp to opaque.
  int get transparencyAlpha {
    switch (transparency) {
      case 1: return 191; // ~75% opaque
      case 2: return 127; // ~50% opaque
      case 3: return 63;  // ~25% opaque
      case 4: return 0;   // fully transparent
      default: return 255;
    }
  }

  @override
  String toString() => transparency == 0
      ? 'S52AreaColor($colorCode)'
      : 'S52AreaColor($colorCode,$transparency)';
}

/// `AP(NAME)` — fill an area with a tiled pattern symbol.
class S52AreaPattern extends S52Instruction {
  const S52AreaPattern({required this.patternName, required super.raw});
  final String patternName;

  @override
  String toString() => 'S52AreaPattern($patternName)';
}

/// `TX(...)` — render a feature attribute as text.
///
/// The [args] list is the raw, comma-split arg list after the opcode:
/// `"OBJNAM,3,1,4,'15110',1,-1,50,CHBLK,51"` → 10 strings. The first
/// arg is the attribute name; the rest encode justification, font,
/// offset, colour, display group, etc. Renderers parse further.
class S52Text extends S52Instruction {
  const S52Text({required this.args, required super.raw});
  final List<String> args;

  /// Convenience: the attribute name whose value should be rendered.
  /// Empty string if the instruction has no args (malformed).
  String get attribute => args.isNotEmpty ? args.first : '';

  @override
  String toString() => 'S52Text($args)';
}

/// `TE(...)` — render a printf-style format string populated with
/// feature attribute values.
///
/// First arg is the quoted format string (e.g. `'%03.0lf°'`), followed
/// by one quoted attribute name per `%` placeholder, then the same
/// positioning/colour fields as `TX`. Renderers parse further.
class S52TextFormatted extends S52Instruction {
  const S52TextFormatted({required this.args, required super.raw});
  final List<String> args;

  /// The format string (typically single-quoted in the source). Empty
  /// if the instruction has no args.
  String get format => args.isNotEmpty ? args.first : '';

  @override
  String toString() => 'S52TextFormatted($args)';
}

/// Synthetic text instruction emitted by CS procedures when the value
/// to render is computed, not looked up from a feature attribute
/// (e.g. SOUNDG02's depth-unit-converted sounding label).
///
/// Renderers treat this exactly like [S52Text] / [S52TextFormatted]
/// for positioning and styling — the only difference is that the
/// string to draw is [text] directly rather than a lookup. [params]
/// is the same tail used by the attribute-backed variants (font,
/// justification, colour code, etc.).
class S52TextLiteral extends S52Instruction {
  const S52TextLiteral({
    required this.text,
    required this.params,
    required super.raw,
  });

  final String text;
  final List<String> params;

  @override
  String toString() => 'S52TextLiteral("$text",$params)';
}

/// `CS(PROCEDURE)` — dispatch a conditional-symbology procedure.
/// The engine replaces this instruction with the procedure's output.
class S52ConditionalSymbology extends S52Instruction {
  const S52ConditionalSymbology({
    required this.procedureName,
    required super.raw,
  });
  final String procedureName;

  @override
  String toString() => 'S52ConditionalSymbology($procedureName)';
}

/// A well-formed `XX(...)` instruction whose opcode is not one of the
/// recognised eight. Preserved for diagnostics rather than dropped, so
/// renderers can log or warn rather than crash.
class S52UnknownInstruction extends S52Instruction {
  const S52UnknownInstruction({
    required this.opcode,
    required this.args,
    required super.raw,
  });

  final String opcode;
  final String args;

  @override
  String toString() => 'S52UnknownInstruction($opcode,$args)';
}

/// Stateless parser for S-52 instruction strings.
///
/// Instruction strings appear in lookup rows (e.g.
/// `"AC(DEPVS);CS(DEPARE01)"`) and in CS-procedure outputs. The parser
/// accepts:
///
///   * Multiple semicolon-separated instructions in a single input.
///   * A malformed input with a missing closing paren — one such entry
///     (`LC(LOWACC21`) exists in the upstream Freeboard source, and
///     silently skipping it would lose a hazard. We accept and warn.
///   * Empty / whitespace-only input → empty output list.
class S52InstructionParser {
  S52InstructionParser._();

  static final RegExp _opcodePattern =
      RegExp(r'^\s*([A-Z]{2})\((.*?)\)?\s*$');

  /// Parse a whole instruction string into a list of typed instructions.
  /// Empty strings (including the artefact of a trailing `;`) are
  /// silently skipped; malformed non-empty chunks become
  /// [S52UnknownInstruction] entries tagged with opcode `??`.
  static List<S52Instruction> parse(String input) {
    if (input.trim().isEmpty) return const [];
    final out = <S52Instruction>[];
    for (final chunk in input.split(';')) {
      if (chunk.trim().isEmpty) continue;
      out.add(_parseChunk(chunk));
    }
    return List.unmodifiable(out);
  }

  static S52Instruction _parseChunk(String chunk) {
    final m = _opcodePattern.firstMatch(chunk);
    if (m == null) {
      return S52UnknownInstruction(opcode: '??', args: chunk, raw: chunk);
    }
    final opcode = m.group(1)!;
    final args = m.group(2)!;

    switch (opcode) {
      case 'SY':
        return S52Symbol(name: args.trim(), raw: chunk);
      case 'LS':
        return _parseLineStyle(args, chunk);
      case 'LC':
        return S52LineComplex(patternName: args.trim(), raw: chunk);
      case 'AC':
        return _parseAreaColor(args, chunk);
      case 'AP':
        return S52AreaPattern(patternName: args.trim(), raw: chunk);
      case 'TX':
        return S52Text(args: _splitArgs(args), raw: chunk);
      case 'TE':
        return S52TextFormatted(args: _splitArgs(args), raw: chunk);
      case 'CS':
        return S52ConditionalSymbology(
          procedureName: args.trim(),
          raw: chunk,
        );
      default:
        return S52UnknownInstruction(opcode: opcode, args: args, raw: chunk);
    }
  }

  static S52Instruction _parseAreaColor(String args, String raw) {
    final parts = args.split(',').map((e) => e.trim()).toList();
    if (parts.isEmpty || parts[0].isEmpty) {
      return S52UnknownInstruction(opcode: 'AC', args: args, raw: raw);
    }
    final colorCode = parts[0];
    int trans = 0;
    if (parts.length >= 2) {
      trans = int.tryParse(parts[1]) ?? 0;
    }
    return S52AreaColor(
      colorCode: colorCode,
      transparency: trans,
      raw: raw,
    );
  }

  static S52Instruction _parseLineStyle(String args, String raw) {
    final parts = args.split(',').map((e) => e.trim()).toList();
    if (parts.length < 3) {
      return S52UnknownInstruction(opcode: 'LS', args: args, raw: raw);
    }
    final S52LinePattern pattern;
    try {
      pattern = S52LinePattern.fromCode(parts[0]);
    } on FormatException {
      return S52UnknownInstruction(opcode: 'LS', args: args, raw: raw);
    }
    final width = int.tryParse(parts[1]);
    if (width == null) {
      return S52UnknownInstruction(opcode: 'LS', args: args, raw: raw);
    }
    return S52LineStyle(
      pattern: pattern,
      width: width,
      colorCode: parts[2],
      raw: raw,
    );
  }

  /// Split an args string on commas, but respect single-quoted strings
  /// so quoted commas inside a printf format don't split the arg list.
  ///
  /// Input:  `"'%03.0lf°','CATHAF',3,1"` →
  /// Output: `['%03.0lf°', 'CATHAF', '3', '1']` (quotes stripped).
  static List<String> _splitArgs(String raw) {
    final out = <String>[];
    final buf = StringBuffer();
    var inQuote = false;
    for (var i = 0; i < raw.length; i++) {
      final c = raw[i];
      if (c == "'") {
        inQuote = !inQuote;
        continue;
      }
      if (c == ',' && !inQuote) {
        out.add(buf.toString().trim());
        buf.clear();
        continue;
      }
      buf.write(c);
    }
    if (buf.isNotEmpty) out.add(buf.toString().trim());
    return List.unmodifiable(out);
  }
}
