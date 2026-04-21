import 'enums.dart';
import 'feature.dart';
import 'instruction.dart';
import 'lookup.dart';
import 'options.dart';

/// Signature for a conditional-symbology procedure.
///
/// CS procedures are pure functions that take a feature plus the
/// current engine options and return a list of typed S-52
/// instructions. Returning typed instructions (rather than raw
/// `'AC(DEPVS)'` strings) lets a procedure emit synthetic variants
/// such as [S52TextLiteral] for computed values (see SOUNDG02),
/// which have no string-grammar representation.
typedef S52CsProcedure = List<S52Instruction> Function(
  S52Feature feature,
  S52Options options,
);

/// Top-level S-52 style engine. Given a feature, picks the right
/// lookup row, parses its instruction string, expands any `CS(PROC)`
/// instructions via the registered procedure map, and returns a flat
/// list of terminal (non-CS) instructions ready to be rendered.
///
/// The engine is stateless and safe to share across threads/isolates.
class S52StyleEngine {
  const S52StyleEngine({
    required this.lookups,
    required this.options,
    this.csProcedures = const {},
  });

  final LookupTable lookups;
  final S52Options options;

  /// Map from CS procedure name (e.g. `'LIGHTS05'`) to its Dart
  /// implementation. Procedures are contributed in Phase 3 of the
  /// port; the engine works without them but logs unknowns via
  /// [S52UnknownInstruction] entries instead of dropping.
  final Map<String, S52CsProcedure> csProcedures;

  /// Style a single feature. Returns an empty list when:
  ///   * the feature's object class has no lookup rows matching its
  ///     geometry, or
  ///   * the matching row's display category is above the active
  ///     filter ([S52Options.displayCategory]).
  ///
  /// Otherwise returns a flat list of terminal instructions (no
  /// `S52ConditionalSymbology` entries). `CS(PROC)` references in the
  /// lookup instruction string are replaced inline with the parsed
  /// output of [csProcedures]`[PROC]`; references to procedures not
  /// registered in [csProcedures] are preserved as
  /// [S52UnknownInstruction] with opcode `'CS-MISSING'` so callers
  /// can audit gaps.
  List<S52Instruction> styleFeature(S52Feature feature) {
    final row = _resolveRow(feature);
    if (row == null) return const [];
    if (!_displayCategoryAllows(row.displayCategory)) return const [];

    final parsed = S52InstructionParser.parse(row.instruction);
    return _expandCs(parsed, feature);
  }

  /// Finds the best lookup row for the feature given the current
  /// options' graphics-style / boundaries setting, which drives which
  /// [S52LookupTableKind] to consult.
  LookupRow? _resolveRow(S52Feature feature) {
    final kind = preferredTableKind(feature.geometryType);
    return lookups.bestMatch(
      kind,
      feature.objectClass,
      feature.geometryType,
      feature.attributes,
    );
  }

  /// Picks the lookup-table variant appropriate for the current
  /// options, per IHO S-52 §5.3. Points follow the graphics-style
  /// setting; lines are always `LINES`; areas follow the boundaries
  /// setting. Public so external callers that need to re-query the
  /// same row (e.g. a tile manager computing popover priority) use
  /// the exact kind the engine used for styling.
  S52LookupTableKind preferredTableKind(S52GeometryType geom) {
    switch (geom) {
      case S52GeometryType.point:
        return options.graphicsStyle == S52GraphicsStyle.paper
            ? S52LookupTableKind.paperChart
            : S52LookupTableKind.simplified;
      case S52GeometryType.line:
        return S52LookupTableKind.lines;
      case S52GeometryType.area:
        return options.boundaries == S52Boundaries.plain
            ? S52LookupTableKind.plainBoundaries
            : S52LookupTableKind.symbolisedBoundaries;
    }
  }

  /// STANDARD allows DISPLAYBASE+STANDARD. OTHER allows all three.
  /// DISPLAYBASE allows only DISPLAYBASE. Mariner categories pass
  /// through the corresponding standard category (base behaviour of
  /// the OpenCPN reference implementation).
  bool _displayCategoryAllows(S52DisplayCategory rowCategory) {
    // Translate mariner variants to their non-mariner equivalents for
    // the purpose of filtering — the distinction only matters when
    // layering mariner annotations over chart data.
    S52DisplayCategory effective(S52DisplayCategory c) {
      switch (c) {
        case S52DisplayCategory.marinersStandard:
          return S52DisplayCategory.standard;
        case S52DisplayCategory.marinersOther:
          return S52DisplayCategory.other;
        case S52DisplayCategory.dispCatNum:
          return S52DisplayCategory.other;
        case S52DisplayCategory.displayBase:
        case S52DisplayCategory.standard:
        case S52DisplayCategory.other:
          return c;
      }
    }

    final row = effective(rowCategory);
    final active = effective(options.displayCategory);
    switch (active) {
      case S52DisplayCategory.displayBase:
        return row == S52DisplayCategory.displayBase;
      case S52DisplayCategory.standard:
        return row == S52DisplayCategory.displayBase ||
            row == S52DisplayCategory.standard;
      case S52DisplayCategory.other:
        return true;
      case S52DisplayCategory.marinersStandard:
      case S52DisplayCategory.marinersOther:
      case S52DisplayCategory.dispCatNum:
        // Already normalised above, unreachable.
        return true;
    }
  }

  /// Walk the parsed instruction list; when we hit a CS() instruction
  /// that maps to a registered procedure, invoke it and splice its
  /// returned typed instructions in place. Unmapped CS references
  /// become `S52UnknownInstruction(opcode: 'CS-MISSING')`.
  List<S52Instruction> _expandCs(
    List<S52Instruction> input,
    S52Feature feature,
  ) {
    final out = <S52Instruction>[];
    for (final instr in input) {
      if (instr is S52ConditionalSymbology) {
        final proc = csProcedures[instr.procedureName];
        if (proc == null) {
          out.add(
            S52UnknownInstruction(
              opcode: 'CS-MISSING',
              args: instr.procedureName,
              raw: instr.raw,
            ),
          );
          continue;
        }
        // CS output is not allowed to recurse into further CS calls
        // in the IHO spec; if a procedure emits another
        // [S52ConditionalSymbology] that would be a bug. We preserve
        // the instruction as-is rather than silently dropping or
        // infinitely recursing, so diagnostics surface the bug.
        out.addAll(proc(feature, options));
      } else {
        out.add(instr);
      }
    }
    return List.unmodifiable(out);
  }
}
