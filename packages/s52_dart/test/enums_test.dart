import 'package:s52_dart/s52_dart.dart';
import 'package:test/test.dart';

void main() {
  group('S52GeometryType', () {
    test('wire-format codes are stable', () {
      expect(S52GeometryType.point.code, 0);
      expect(S52GeometryType.line.code, 1);
      expect(S52GeometryType.area.code, 2);
    });

    test('fromCode round-trip', () {
      for (final v in S52GeometryType.values) {
        expect(S52GeometryType.fromCode(v.code), v);
      }
    });

    test('fromCode throws on unknown', () {
      expect(() => S52GeometryType.fromCode(99), throwsArgumentError);
    });
  });

  group('S52DisplayCategory', () {
    test('wire-format codes are stable', () {
      expect(S52DisplayCategory.displayBase.code, 0);
      expect(S52DisplayCategory.standard.code, 1);
      expect(S52DisplayCategory.other.code, 2);
      expect(S52DisplayCategory.marinersStandard.code, 3);
      expect(S52DisplayCategory.marinersOther.code, 4);
      expect(S52DisplayCategory.dispCatNum.code, 5);
    });

    test('fromCode round-trip', () {
      for (final v in S52DisplayCategory.values) {
        expect(S52DisplayCategory.fromCode(v.code), v);
      }
    });
  });

  group('S52DisplayPriority', () {
    test('wire-format codes are stable', () {
      expect(S52DisplayPriority.noData.code, 0);
      expect(S52DisplayPriority.mariners.code, 9);
    });

    test('fromCode round-trip', () {
      for (final v in S52DisplayPriority.values) {
        expect(S52DisplayPriority.fromCode(v.code), v);
      }
    });
  });

  group('S52LookupTableKind', () {
    test('wire-format codes are stable', () {
      expect(S52LookupTableKind.simplified.code, 0);
      expect(S52LookupTableKind.paperChart.code, 1);
      expect(S52LookupTableKind.lines.code, 2);
      expect(S52LookupTableKind.plainBoundaries.code, 3);
      expect(S52LookupTableKind.symbolisedBoundaries.code, 4);
    });

    test('fromCode round-trip', () {
      for (final v in S52LookupTableKind.values) {
        expect(S52LookupTableKind.fromCode(v.code), v);
      }
    });
  });
}
