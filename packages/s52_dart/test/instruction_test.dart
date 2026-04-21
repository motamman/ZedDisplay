import 'package:s52_dart/s52_dart.dart';
import 'package:test/test.dart';

void main() {
  group('S52InstructionParser.parse', () {
    test('empty and whitespace-only input produce empty list', () {
      expect(S52InstructionParser.parse(''), isEmpty);
      expect(S52InstructionParser.parse('   '), isEmpty);
      expect(S52InstructionParser.parse(';;'), isEmpty);
    });

    test('single SY instruction', () {
      final r = S52InstructionParser.parse('SY(ACHARE02)');
      expect(r, hasLength(1));
      final i = r.single;
      expect(i, isA<S52Symbol>());
      expect((i as S52Symbol).name, 'ACHARE02');
      expect(i.raw, 'SY(ACHARE02)');
    });

    test('single AC instruction', () {
      final r = S52InstructionParser.parse('AC(DEPVS)');
      expect(r.single, isA<S52AreaColor>());
      expect((r.single as S52AreaColor).colorCode, 'DEPVS');
    });

    test('single AP instruction', () {
      final r = S52InstructionParser.parse('AP(DRGARE01)');
      expect(r.single, isA<S52AreaPattern>());
      expect((r.single as S52AreaPattern).patternName, 'DRGARE01');
    });

    test('single LC instruction', () {
      final r = S52InstructionParser.parse('LC(LOWACC21)');
      expect(r.single, isA<S52LineComplex>());
      expect((r.single as S52LineComplex).patternName, 'LOWACC21');
    });

    test('single CS instruction', () {
      final r = S52InstructionParser.parse('CS(DEPARE01)');
      expect(r.single, isA<S52ConditionalSymbology>());
      expect(
        (r.single as S52ConditionalSymbology).procedureName,
        'DEPARE01',
      );
    });

    test('well-formed LS with each pattern', () {
      for (final tc in [
        ('LS(SOLD,1,DEPCN)', S52LinePattern.solid, 1, 'DEPCN'),
        ('LS(DASH,2,DEPSC)', S52LinePattern.dash, 2, 'DEPSC'),
        ('LS(DOTT,1,CHGRF)', S52LinePattern.dott, 1, 'CHGRF'),
      ]) {
        final (input, pattern, width, color) = tc;
        final r = S52InstructionParser.parse(input);
        expect(r.single, isA<S52LineStyle>(), reason: input);
        final ls = r.single as S52LineStyle;
        expect(ls.pattern, pattern, reason: input);
        expect(ls.width, width, reason: input);
        expect(ls.colorCode, color, reason: input);
      }
    });

    test('LS with whitespace around args', () {
      final r = S52InstructionParser.parse('LS( DASH , 2 , DEPSC )');
      final ls = r.single as S52LineStyle;
      expect(ls.pattern, S52LinePattern.dash);
      expect(ls.width, 2);
      expect(ls.colorCode, 'DEPSC');
    });

    test('LS with malformed pattern becomes Unknown', () {
      final r = S52InstructionParser.parse('LS(FOO,1,DEPCN)');
      expect(r.single, isA<S52UnknownInstruction>());
      expect((r.single as S52UnknownInstruction).opcode, 'LS');
    });

    test('LS with non-numeric width becomes Unknown', () {
      final r = S52InstructionParser.parse('LS(SOLD,wide,DEPCN)');
      expect(r.single, isA<S52UnknownInstruction>());
    });

    test('LS with too few args becomes Unknown', () {
      final r = S52InstructionParser.parse('LS(SOLD)');
      expect(r.single, isA<S52UnknownInstruction>());
    });

    test('multiple instructions joined by semicolons', () {
      final r = S52InstructionParser.parse(
        'AC(DEPVS);CS(DEPARE01);LS(SOLD,1,DEPCN)',
      );
      expect(r, hasLength(3));
      expect(r[0], isA<S52AreaColor>());
      expect(r[1], isA<S52ConditionalSymbology>());
      expect(r[2], isA<S52LineStyle>());
    });

    test('trailing semicolon produces no extra entry', () {
      final r = S52InstructionParser.parse('AC(DEPVS);');
      expect(r, hasLength(1));
    });

    test('tolerates missing closing paren (Freeboard LC(LOWACC21 artefact)',
        () {
      final r = S52InstructionParser.parse('LC(LOWACC21');
      expect(r, hasLength(1));
      expect(r.single, isA<S52LineComplex>());
      expect((r.single as S52LineComplex).patternName, 'LOWACC21');
    });

    test('unknown opcode is preserved as UnknownInstruction', () {
      final r = S52InstructionParser.parse('ZZ(mystery)');
      expect(r.single, isA<S52UnknownInstruction>());
      expect((r.single as S52UnknownInstruction).opcode, 'ZZ');
      expect((r.single as S52UnknownInstruction).args, 'mystery');
    });

    test('completely malformed chunk becomes UnknownInstruction ??', () {
      final r = S52InstructionParser.parse('not an instruction');
      expect(r.single, isA<S52UnknownInstruction>());
      expect((r.single as S52UnknownInstruction).opcode, '??');
    });
  });

  group('TX/TE arg splitting', () {
    test('TX arg list splits on commas', () {
      final r = S52InstructionParser.parse(
        "TX(OBJNAM,3,1,4,'15110',1,-1,50,CHBLK,51)",
      );
      expect(r.single, isA<S52Text>());
      final tx = r.single as S52Text;
      expect(tx.attribute, 'OBJNAM');
      expect(tx.args, [
        'OBJNAM',
        '3',
        '1',
        '4',
        '15110',
        '1',
        '-1',
        '50',
        'CHBLK',
        '51',
      ]);
    });

    test('TE format-string quoted commas are preserved inside the format',
        () {
      // First arg is a quoted format that contains NO commas (typical)
      // — but args 1..N are quoted attribute names that also shouldn't
      // split on the quoting. Example verbatim from Freeboard TE output:
      final r = S52InstructionParser.parse(
        "TE('%03.0lf°','CATHAF',3,1,4,'15110',1,-1,50,CHBLK,51)",
      );
      expect(r.single, isA<S52TextFormatted>());
      final te = r.single as S52TextFormatted;
      expect(te.format, '%03.0lf°');
      expect(te.args.first, '%03.0lf°');
      expect(te.args[1], 'CATHAF');
    });

    test('TE with commas inside the format string', () {
      // Synthetic: a format with a comma in it shouldn't split.
      final r = S52InstructionParser.parse(
        "TE('Depth: %d, safe: %d','VAL1','VAL2')",
      );
      final te = r.single as S52TextFormatted;
      expect(te.format, 'Depth: %d, safe: %d');
      expect(te.args, ['Depth: %d, safe: %d', 'VAL1', 'VAL2']);
    });
  });

  group('S52LinePattern', () {
    test('fromCode round-trip', () {
      for (final v in S52LinePattern.values) {
        expect(S52LinePattern.fromCode(v.code), v);
      }
    });

    test('fromCode throws on unknown', () {
      expect(
        () => S52LinePattern.fromCode('WIGG'),
        throwsFormatException,
      );
    });
  });
}
