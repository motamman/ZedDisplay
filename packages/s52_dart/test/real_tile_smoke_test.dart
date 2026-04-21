import 'package:s52_dart/s52_dart.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// Smoke-level regression test driven by real tile fixtures. Its job
/// is not to assert specific rendering outputs — the CS procedures
/// aren't ported yet — but to prove end-to-end that:
///
///   1. The production `s57_lookups.json` loads into [LookupTable].
///   2. Every fixture feature can be fed to the engine without
///      throwing.
///   3. The engine resolves a meaningful number of features against
///      the production lookups (catches regressions where a field
///      rename or enum-code mismatch silently drops everything).
///   4. The instruction opcodes emitted by the engine are a subset
///      of the eight recognised ones (plus the synthetic CS-MISSING).
void main() {
  late LookupTable lookups;
  late List<S52Feature> fixtures;

  setUpAll(() {
    lookups = FixtureLoader.loadLookups();
    fixtures = FixtureLoader.loadAllFixtureFeatures();
  });

  test('production lookup table parses', () {
    expect(lookups.length, greaterThan(100));
  });

  test('fixture corpus is non-trivially large', () {
    expect(fixtures.length, greaterThanOrEqualTo(50));
    // Must hit most of the CS-relevant object classes.
    final classes = fixtures.map((f) => f.objectClass).toSet();
    expect(classes, containsAll(<String>{
      'DEPARE',
      'DEPCNT',
      'SOUNDG',
      'LIGHTS',
      'OBSTRN',
      'WRECKS',
      'BOYLAT',
      'COALNE',
      'SLCONS',
    }));
  });

  test('engine styles every fixture feature without throwing', () {
    final engine = S52StyleEngine(
      lookups: lookups,
      options: const S52Options(
        displayCategory: S52DisplayCategory.other,
      ),
    );
    for (final feature in fixtures) {
      expect(
        () => engine.styleFeature(feature),
        returnsNormally,
        reason: feature.toString(),
      );
    }
  });

  test('a meaningful fraction of fixtures resolve to instructions', () {
    final engine = S52StyleEngine(
      lookups: lookups,
      options: const S52Options(
        displayCategory: S52DisplayCategory.other,
      ),
    );
    var withOutput = 0;
    for (final feature in fixtures) {
      if (engine.styleFeature(feature).isNotEmpty) withOutput++;
    }
    // Empirical threshold — with all 76 fixtures across 21 layers we
    // expect the vast majority to produce at least one instruction.
    // If this drops, it almost certainly means the lookup-table
    // resolver regressed.
    expect(
      withOutput / fixtures.length,
      greaterThan(0.7),
      reason: 'Only $withOutput of ${fixtures.length} fixtures produced '
          'instructions — suspect lookup resolution regression.',
    );
  });

  test('all emitted instructions are in the recognised opcode set', () {
    final engine = S52StyleEngine(
      lookups: lookups,
      options: const S52Options(
        displayCategory: S52DisplayCategory.other,
      ),
    );
    final expectedOpcodes = <Type>{
      S52Symbol,
      S52LineStyle,
      S52LineComplex,
      S52AreaColor,
      S52AreaPattern,
      S52Text,
      S52TextFormatted,
      S52TextLiteral,
      S52UnknownInstruction, // CS-MISSING today, Unknown for malformed
    };
    for (final feature in fixtures) {
      for (final instruction in engine.styleFeature(feature)) {
        expect(
          expectedOpcodes,
          contains(instruction.runtimeType),
          reason: 'Unexpected instruction type ${instruction.runtimeType} '
              'from ${feature.objectClass}: ${instruction.raw}',
        );
      }
    }
  });

  test('full pipeline with standardCsProcedures resolves real features', () {
    // With every CS procedure registered, the engine should produce
    // terminal instructions (no CS-MISSING) for every layer that has
    // a lookup row. This is the regression baseline for the full
    // port — a drop in resolved-fixture count means a CS procedure
    // or lookup-resolution pass regressed.
    final engine = S52StyleEngine(
      lookups: lookups,
      options: const S52Options(
        displayCategory: S52DisplayCategory.other,
      ),
      csProcedures: standardCsProcedures,
    );
    var withOutput = 0;
    for (final feature in fixtures) {
      final out = engine.styleFeature(feature);
      if (out.isNotEmpty) withOutput++;
    }
    expect(
      withOutput / fixtures.length,
      greaterThan(0.7),
      reason: 'Only $withOutput of ${fixtures.length} fixtures produced '
          'instructions.',
    );
  });

  test('DEPARE features with DEPARE01 registered produce seabed colour', () {
    // Regression baseline for the specific procedure: with DEPARE01
    // registered, real DEPARE fixtures must produce an S52AreaColor
    // from the seabed palette (one of DEPIT / DEPVS / DEPMS / DEPMD
    // / DEPDW).
    const seabedPalette = {'DEPIT', 'DEPVS', 'DEPMS', 'DEPMD', 'DEPDW'};
    final engine = S52StyleEngine(
      lookups: lookups,
      options: const S52Options(
        displayCategory: S52DisplayCategory.other,
      ),
      csProcedures: standardCsProcedures,
    );
    final depare = fixtures.where((f) => f.objectClass == 'DEPARE').toList();
    expect(depare, isNotEmpty);
    for (final f in depare) {
      final out = engine.styleFeature(f);
      final areaColors = out.whereType<S52AreaColor>().toList();
      expect(
        areaColors,
        isNotEmpty,
        reason: '${f.attributes} produced no area colour',
      );
      for (final c in areaColors) {
        expect(
          seabedPalette,
          contains(c.colorCode),
          reason: 'Non-palette colour ${c.colorCode} for ${f.attributes}',
        );
      }
    }
  });

  test(
    'DEPARE features hit the CS(DEPARE01) fallback row; without '
    'a registered procedure they surface as CS-MISSING diagnostics',
    () {
      // Production DEPARE rows: id=39 has qualifiers DRVAL1? / DRVAL2?
      // which (per JS-parity matcher semantics) can never win the
      // specific pass. The fallback id=40 is `CS(DEPARE01)`. Without a
      // registered DEPARE01 procedure we get exactly one CS-MISSING
      // entry per feature — this locks in the contract the CS-phase
      // will plug into.
      final engine = S52StyleEngine(
        lookups: lookups,
        options: const S52Options(
          displayCategory: S52DisplayCategory.other,
        ),
      );
      final depare = fixtures.where((f) => f.objectClass == 'DEPARE').toList();
      expect(depare, isNotEmpty);
      for (final f in depare) {
        final out = engine.styleFeature(f);
        expect(out, hasLength(1), reason: f.toString());
        expect(out.single, isA<S52UnknownInstruction>());
        expect(
          (out.single as S52UnknownInstruction).opcode,
          'CS-MISSING',
          reason: f.toString(),
        );
        expect(
          (out.single as S52UnknownInstruction).args,
          'DEPARE01',
          reason: f.toString(),
        );
      }
    },
  );
}
