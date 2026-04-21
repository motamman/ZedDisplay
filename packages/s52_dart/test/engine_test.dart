import 'package:s52_dart/s52_dart.dart';
import 'package:test/test.dart';

/// Build a minimal [LookupTable] matching the asset shape, covering
/// the cases the engine tests exercise:
///
///   * ACHARE point in SIMPLIFIED (display STANDARD) — a fallback row
///     and an attribute-qualified row.
///   * ACHARE point in PAPER_CHART (display STANDARD).
///   * DEPARE area in PLAIN (display DISPLAYBASE) with a CS() ref.
///   * LIGHTS point in SIMPLIFIED (display OTHER) with a CS() ref.
///   * BUOYDEF line in LINES (display OTHER) — tests geometry routing.
///
/// Covers: triple-key resolution, display-category filtering, CS
/// expansion (registered and unregistered), table-kind selection
/// driven by [S52Options.graphicsStyle] / [S52Options.boundaries].
LookupTable _buildTestLookups() {
  return LookupTable.fromJson(<String, dynamic>{
    'lookups': [
      // ACHARE point — simplified table
      {
        'id': 1,
        'name': 'ACHARE',
        'geometryType': 0,
        'lookupTable': 0,
        'instruction': 'SY(ACHARE02)',
        'attributes': <String, dynamic>{},
        'displayPriority': 6,
        'displayCategory': 1,
      },
      {
        'id': 2,
        'name': 'ACHARE',
        'geometryType': 0,
        'lookupTable': 0,
        'instruction': 'SY(ACHARE51)',
        'attributes': <String, dynamic>{'0': 'CATACH1'},
        'displayPriority': 6,
        'displayCategory': 1,
      },
      // ACHARE point — paper table
      {
        'id': 3,
        'name': 'ACHARE',
        'geometryType': 0,
        'lookupTable': 1,
        'instruction': 'SY(ACHARE02)',
        'attributes': <String, dynamic>{},
        'displayPriority': 6,
        'displayCategory': 1,
      },
      // DEPARE area — plain table with CS() dispatch
      {
        'id': 4,
        'name': 'DEPARE',
        'geometryType': 2,
        'lookupTable': 3,
        'instruction': 'AC(DEPVS);CS(DEPARE01)',
        'attributes': <String, dynamic>{},
        'displayPriority': 3,
        'displayCategory': 0,
      },
      // LIGHTS point — simplified, display OTHER
      {
        'id': 5,
        'name': 'LIGHTS',
        'geometryType': 0,
        'lookupTable': 0,
        'instruction': 'CS(LIGHTS05)',
        'attributes': <String, dynamic>{},
        'displayPriority': 4,
        'displayCategory': 2,
      },
      // BUOYDEF line — LINES table
      {
        'id': 6,
        'name': 'BUOYDEF',
        'geometryType': 1,
        'lookupTable': 2,
        'instruction': 'LS(SOLD,1,CHBLK)',
        'attributes': <String, dynamic>{},
        'displayPriority': 5,
        'displayCategory': 2,
      },
    ],
    'lookupStartIndex': {
      '0,ACHARE,0': 0,
      '1,ACHARE,0': 2,
      '3,DEPARE,2': 3,
      '0,LIGHTS,0': 4,
      '2,BUOYDEF,1': 5,
    },
  });
}

void main() {
  group('S52StyleEngine basic routing', () {
    test('resolves a simple point feature under SIMPLIFIED style', () {
      final engine = S52StyleEngine(
        lookups: _buildTestLookups(),
        options: const S52Options(
          graphicsStyle: S52GraphicsStyle.simplified,
          displayCategory: S52DisplayCategory.other,
        ),
      );
      const feature = S52Feature(
        objectClass: 'ACHARE',
        geometryType: S52GeometryType.point,
      );
      final out = engine.styleFeature(feature);
      expect(out, hasLength(1));
      expect(out.single, isA<S52Symbol>());
      expect((out.single as S52Symbol).name, 'ACHARE02');
    });

    test('graphicsStyle=paper selects the PAPER_CHART table', () {
      final engine = S52StyleEngine(
        lookups: _buildTestLookups(),
        options: const S52Options(
          graphicsStyle: S52GraphicsStyle.paper,
          displayCategory: S52DisplayCategory.other,
        ),
      );
      const feature = S52Feature(
        objectClass: 'ACHARE',
        geometryType: S52GeometryType.point,
      );
      final out = engine.styleFeature(feature);
      // paper-chart row also emits SY(ACHARE02) in our fixture, so
      // presence is enough to show routing worked.
      expect(out, hasLength(1));
      expect((out.single as S52Symbol).name, 'ACHARE02');
    });

    test('attribute-qualified row beats the fallback', () {
      final engine = S52StyleEngine(
        lookups: _buildTestLookups(),
        options: const S52Options(
          graphicsStyle: S52GraphicsStyle.simplified,
          displayCategory: S52DisplayCategory.other,
        ),
      );
      const feature = S52Feature(
        objectClass: 'ACHARE',
        geometryType: S52GeometryType.point,
        attributes: {'CATACH': '1'},
      );
      final out = engine.styleFeature(feature);
      expect((out.single as S52Symbol).name, 'ACHARE51');
    });

    test('line geometry routes through the LINES table', () {
      final engine = S52StyleEngine(
        lookups: _buildTestLookups(),
        options: const S52Options(
          displayCategory: S52DisplayCategory.other,
        ),
      );
      const feature = S52Feature(
        objectClass: 'BUOYDEF',
        geometryType: S52GeometryType.line,
      );
      final out = engine.styleFeature(feature);
      expect(out.single, isA<S52LineStyle>());
      expect((out.single as S52LineStyle).colorCode, 'CHBLK');
    });

    test('area boundaries setting picks PLAIN vs SYMBOLISED', () {
      // Our fixture only has a PLAIN-boundary DEPARE row, so under
      // SYMBOLISED setting styling should return empty (no row found).
      final plain = S52StyleEngine(
        lookups: _buildTestLookups(),
        options: const S52Options(
          boundaries: S52Boundaries.plain,
          displayCategory: S52DisplayCategory.other,
        ),
      );
      final symbolised = S52StyleEngine(
        lookups: _buildTestLookups(),
        options: const S52Options(
          boundaries: S52Boundaries.symbolised,
          displayCategory: S52DisplayCategory.other,
        ),
      );
      const feature = S52Feature(
        objectClass: 'DEPARE',
        geometryType: S52GeometryType.area,
      );
      expect(plain.styleFeature(feature), isNotEmpty);
      expect(symbolised.styleFeature(feature), isEmpty);
    });

    test('unknown object class returns empty list', () {
      final engine = S52StyleEngine(
        lookups: _buildTestLookups(),
        options: const S52Options(
          displayCategory: S52DisplayCategory.other,
        ),
      );
      const feature = S52Feature(
        objectClass: 'UNKNOWN',
        geometryType: S52GeometryType.point,
      );
      expect(engine.styleFeature(feature), isEmpty);
    });
  });

  group('display-category filter', () {
    test('DISPLAYBASE filter drops STANDARD rows', () {
      final engine = S52StyleEngine(
        lookups: _buildTestLookups(),
        options: const S52Options(
          graphicsStyle: S52GraphicsStyle.simplified,
          displayCategory: S52DisplayCategory.displayBase,
        ),
      );
      const feature = S52Feature(
        objectClass: 'ACHARE',
        geometryType: S52GeometryType.point,
      );
      expect(engine.styleFeature(feature), isEmpty);
    });

    test('STANDARD filter admits STANDARD rows and DISPLAYBASE rows', () {
      final engine = S52StyleEngine(
        lookups: _buildTestLookups(),
        options: const S52Options(
          graphicsStyle: S52GraphicsStyle.simplified,
          displayCategory: S52DisplayCategory.standard,
        ),
      );
      // ACHARE row is STANDARD → allowed.
      const achare = S52Feature(
        objectClass: 'ACHARE',
        geometryType: S52GeometryType.point,
      );
      expect(engine.styleFeature(achare), isNotEmpty);
      // DEPARE row is DISPLAYBASE → allowed.
      const depare = S52Feature(
        objectClass: 'DEPARE',
        geometryType: S52GeometryType.area,
      );
      expect(engine.styleFeature(depare), isNotEmpty);
    });

    test('STANDARD filter drops OTHER rows', () {
      final engine = S52StyleEngine(
        lookups: _buildTestLookups(),
        options: const S52Options(
          displayCategory: S52DisplayCategory.standard,
        ),
      );
      const buoy = S52Feature(
        objectClass: 'BUOYDEF',
        geometryType: S52GeometryType.line,
      );
      // BUOYDEF row is OTHER → dropped under STANDARD filter.
      expect(engine.styleFeature(buoy), isEmpty);
    });
  });

  group('CS expansion', () {
    test('CS() reference with no registered procedure becomes CS-MISSING', () {
      final engine = S52StyleEngine(
        lookups: _buildTestLookups(),
        options: const S52Options(),
      );
      const feature = S52Feature(
        objectClass: 'DEPARE',
        geometryType: S52GeometryType.area,
      );
      final out = engine.styleFeature(feature);
      // Row instruction: "AC(DEPVS);CS(DEPARE01)" → AC + placeholder.
      expect(out, hasLength(2));
      expect(out[0], isA<S52AreaColor>());
      expect(out[1], isA<S52UnknownInstruction>());
      final missing = out[1] as S52UnknownInstruction;
      expect(missing.opcode, 'CS-MISSING');
      expect(missing.args, 'DEPARE01');
    });

    test('registered CS procedure result is spliced in', () {
      List<S52Instruction> depare01(S52Feature f, S52Options o) => const [
            S52AreaColor(colorCode: 'DEPMD', raw: 'AC(DEPMD)'),
            S52LineStyle(
              pattern: S52LinePattern.solid,
              width: 1,
              colorCode: 'DEPCN',
              raw: 'LS(SOLD,1,DEPCN)',
            ),
          ];
      final engine = S52StyleEngine(
        lookups: _buildTestLookups(),
        options: const S52Options(),
        csProcedures: const {},
      ).copyWithProcs({'DEPARE01': depare01});
      const feature = S52Feature(
        objectClass: 'DEPARE',
        geometryType: S52GeometryType.area,
      );
      final out = engine.styleFeature(feature);
      expect(out, hasLength(3));
      expect(out[0], isA<S52AreaColor>());
      expect((out[0] as S52AreaColor).colorCode, 'DEPVS');
      // CS expansion splices in-place:
      expect((out[1] as S52AreaColor).colorCode, 'DEPMD');
      expect((out[2] as S52LineStyle).colorCode, 'DEPCN');
    });

    test('CS procedure gets the originating feature + options', () {
      String? seenClass;
      S52Options? seenOpts;
      List<S52Instruction> proc(S52Feature f, S52Options o) {
        seenClass = f.objectClass;
        seenOpts = o;
        return const [];
      }

      final engine = S52StyleEngine(
        lookups: _buildTestLookups(),
        options: const S52Options(safetyDepth: 99),
        csProcedures: {'DEPARE01': proc},
      );
      engine.styleFeature(const S52Feature(
        objectClass: 'DEPARE',
        geometryType: S52GeometryType.area,
      ));
      expect(seenClass, 'DEPARE');
      expect(seenOpts?.safetyDepth, 99);
    });
  });
}

/// Small test helper to clone the engine with extra CS procedures.
/// In production this would be a proper builder, but tests only need
/// the simplest merge.
extension on S52StyleEngine {
  S52StyleEngine copyWithProcs(Map<String, S52CsProcedure> extra) =>
      S52StyleEngine(
        lookups: lookups,
        options: options,
        csProcedures: {...csProcedures, ...extra},
      );
}
