import 'package:s52_dart/s52_dart.dart';
import 'package:test/test.dart';

void main() {
  group('AttributeQualifier.tryParse', () {
    test('parses NAME + numeric pattern', () {
      final q = AttributeQualifier.tryParse('CATACH1')!;
      expect(q.name, 'CATACH');
      expect(q.pattern, '1');
    });

    test('parses NAME + ? wildcard', () {
      final q = AttributeQualifier.tryParse('DRVAL1?')!;
      expect(q.name, 'DRVAL1');
      expect(q.pattern, '?');
    });

    test('parses NAME + empty pattern', () {
      final q = AttributeQualifier.tryParse('CATLIT')!;
      expect(q.name, 'CATLIT');
      expect(q.pattern, '');
    });

    test('parses NAME + comma-list pattern', () {
      final q = AttributeQualifier.tryParse('COLOUR1,3')!;
      expect(q.name, 'COLOUR');
      expect(q.pattern, '1,3');
    });

    test('returns null on malformed input', () {
      // Empty string: regex needs at least 6 chars for the name.
      expect(AttributeQualifier.tryParse(''), isNull);
      // Name must be exactly 6 alphanumerics. Underscores (or any
      // non-alphanumeric char) in the first 6 positions fail the
      // character-class match.
      expect(AttributeQualifier.tryParse('foo_ba1'), isNull);
      // Trailing garbage after the pattern — anything outside the
      // `[0-9,?]` charset in the tail — also fails (the regex is
      // anchored at both ends).
      expect(AttributeQualifier.tryParse('CATACHfoo'), isNull);
    });
  });

  group('LookupRow.fromJson', () {
    test('parses a simple fallback row (empty qualifiers)', () {
      final row = LookupRow.fromJson({
        'id': 961,
        'name': 'ACHARE',
        'geometryType': 0,
        'lookupTable': 0,
        'instruction': 'SY(ACHARE02)',
        'attributes': <String, dynamic>{},
        'displayPriority': 6,
        'displayCategory': 1,
      });
      expect(row.id, 961);
      expect(row.name, 'ACHARE');
      expect(row.geometryType, S52GeometryType.point);
      expect(row.tableKind, S52LookupTableKind.simplified);
      expect(row.displayCategory, S52DisplayCategory.standard);
      expect(row.displayPriority, S52DisplayPriority.symbolArea);
      expect(row.instruction, 'SY(ACHARE02)');
      expect(row.qualifiers, isEmpty);
    });

    test('parses attribute-qualifier rows in the S-52 {index: "NAMEpat"} form',
        () {
      final row = LookupRow.fromJson({
        'id': 1,
        'name': 'LIGHTS',
        'geometryType': 0,
        'lookupTable': 0,
        'instruction': 'SY(LIGHTS11)',
        'attributes': <String, dynamic>{
          '0': 'COLOUR3',
          '1': 'CATLIT?',
        },
        'displayPriority': 4,
        'displayCategory': 2,
      });
      expect(row.qualifiers, hasLength(2));
      expect(row.qualifiers[0].name, 'COLOUR');
      expect(row.qualifiers[0].pattern, '3');
      expect(row.qualifiers[1].name, 'CATLIT');
      expect(row.qualifiers[1].pattern, '?');
    });
  });

  group('LookupTable.propertyCompare (mirrors Freeboard JS semantics)', () {
    test('numeric equality yields 0', () {
      expect(LookupTable.propertyCompare(1, '1'), 0);
      expect(LookupTable.propertyCompare(1.0, '1'), 0);
    });

    test('string equality yields 0', () {
      expect(LookupTable.propertyCompare('4', '4'), 0);
    });

    test('null is non-comparable', () {
      expect(LookupTable.propertyCompare(null, 'anything'), isNot(0));
    });
  });

  group('LookupTable', () {
    // Build a realistic two-object fixture mirroring the asset shape.
    //
    // Attribute-qualifier maps use the S-52 presentation-library form
    // `{index: "NAMEpattern"}`. The parser extracts each qualifier into
    // a typed (name, pattern) pair; lookup matches test
    // [LookupTable.bestMatch] with patterns across the wildcard (`?`,
    // never counts), blank (` `, always counts), and literal-equality
    // cases exercised elsewhere in this suite.
    final fixture = <String, dynamic>{
      'lookups': [
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
        {
          'id': 3,
          'name': 'DEPARE',
          'geometryType': 2,
          'lookupTable': 0,
          'instruction': 'AC(DEPVS);CS(DEPARE01)',
          'attributes': <String, dynamic>{},
          'displayPriority': 3,
          'displayCategory': 0,
        },
      ],
      'lookupStartIndex': {
        '0,ACHARE,0': 0,
        '0,DEPARE,2': 2,
      },
    };

    test('rowsFor returns all rows matching the triple', () {
      final table = LookupTable.fromJson(fixture);
      final rows = table.rowsFor(
        S52LookupTableKind.simplified,
        'ACHARE',
        S52GeometryType.point,
      );
      expect(rows, hasLength(2));
      expect(rows.map((r) => r.id), [1, 2]);
    });

    test('rowsFor returns empty for unknown triple', () {
      final table = LookupTable.fromJson(fixture);
      expect(
        table.rowsFor(
          S52LookupTableKind.simplified,
          'UNKNOWN',
          S52GeometryType.point,
        ),
        isEmpty,
      );
    });

    test('bestMatch prefers attribute-specific row over fallback', () {
      final table = LookupTable.fromJson(fixture);
      final row = table.bestMatch(
        S52LookupTableKind.simplified,
        'ACHARE',
        S52GeometryType.point,
        {'CATACH': '1'},
      );
      expect(row?.id, 2);
      expect(row?.instruction, 'SY(ACHARE51)');
    });

    test('bestMatch falls back when qualifiers do not match', () {
      final table = LookupTable.fromJson(fixture);
      final row = table.bestMatch(
        S52LookupTableKind.simplified,
        'ACHARE',
        S52GeometryType.point,
        {'CATACH': '2'}, // wrong value — only the empty-attr row matches
      );
      expect(row?.id, 1);
    });

    test('bestMatch returns null when triple unknown', () {
      final table = LookupTable.fromJson(fixture);
      final row = table.bestMatch(
        S52LookupTableKind.simplified,
        'UNKNOWN',
        S52GeometryType.point,
        const {},
      );
      expect(row, isNull);
    });

    test('bestMatch compares int feature values against string patterns', () {
      // Feature has CATACH as int 1 — should still match a row whose
      // qualifier pattern is the string "1" (via propertyCompare's
      // numeric branch).
      final table = LookupTable.fromJson(fixture);
      final row = table.bestMatch(
        S52LookupTableKind.simplified,
        'ACHARE',
        S52GeometryType.point,
        {'CATACH': 1},
      );
      expect(row?.id, 2);
    });

    test('bestMatch picks the most specific row among multiple matches', () {
      // Synthetic row with two attribute qualifiers — both must match,
      // and it should win over the single-qualifier and fallback rows.
      final multi = <String, dynamic>{
        'lookups': [
          {
            'id': 100,
            'name': 'X',
            'geometryType': 0,
            'lookupTable': 0,
            'instruction': 'SY(FALLBACK)',
            'attributes': <String, dynamic>{},
            'displayPriority': 0,
            'displayCategory': 1,
          },
          {
            'id': 101,
            'name': 'X',
            'geometryType': 0,
            'lookupTable': 0,
            'instruction': 'SY(ONE)',
            'attributes': <String, dynamic>{'0': 'CATACH1'},
            'displayPriority': 0,
            'displayCategory': 1,
          },
          {
            'id': 102,
            'name': 'X',
            'geometryType': 0,
            'lookupTable': 0,
            'instruction': 'SY(TWO)',
            'attributes': <String, dynamic>{
              '0': 'CATACH1',
              '1': 'COLOUR2',
            },
            'displayPriority': 0,
            'displayCategory': 1,
          },
        ],
        'lookupStartIndex': {'0,X,0': 0},
      };
      final table = LookupTable.fromJson(multi);
      final row = table.bestMatch(
        S52LookupTableKind.simplified,
        'X',
        S52GeometryType.point,
        {'CATACH': '1', 'COLOUR': '2', 'C': 'ignored'},
      );
      expect(row?.id, 102);
    });

    test('bestMatch treats ? qualifiers as unreachable-specific (JS parity)',
        () {
      // Mirrors Freeboard's observed behaviour: a row whose qualifier
      // pattern is `?` never counts toward the specific-match tally,
      // so rows with any `?` qualifier are unreachable via the
      // specific pass and the empty-qualifier fallback wins.
      final wildcard = <String, dynamic>{
        'lookups': [
          {
            'id': 1,
            'name': 'DEPARE',
            'geometryType': 2,
            'lookupTable': 3,
            'instruction': 'AC(NODTA)',
            'attributes': <String, dynamic>{
              '0': 'DRVAL1?',
              '1': 'DRVAL2?',
            },
            'displayPriority': 3,
            'displayCategory': 0,
          },
          {
            'id': 2,
            'name': 'DEPARE',
            'geometryType': 2,
            'lookupTable': 3,
            'instruction': 'CS(DEPARE01)',
            'attributes': <String, dynamic>{},
            'displayPriority': 3,
            'displayCategory': 0,
          },
        ],
        'lookupStartIndex': {'3,DEPARE,2': 0},
      };
      final table = LookupTable.fromJson(wildcard);
      final row = table.bestMatch(
        S52LookupTableKind.plainBoundaries,
        'DEPARE',
        S52GeometryType.area,
        // Feature has DRVAL1 & DRVAL2 defined — the ? row is still
        // not selectable, per JS semantics.
        {'DRVAL1': 3.6, 'DRVAL2': 5.4},
      );
      expect(row?.id, 2, reason: 'fallback row should win over ? row');
    });

    test('length reflects total row count', () {
      final table = LookupTable.fromJson(fixture);
      expect(table.length, 3);
      expect(table.rows, hasLength(3));
    });
  });
}
