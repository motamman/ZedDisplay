import 'package:flutter_test/flutter_test.dart';
import 'package:zed_display/config/navigation_constants.dart';

void main() {
  group('NavigationConstants.readDistanceMeters', () {
    test('prefers the SI key when present', () {
      final props = {'maxRangeMeters': 9260.0, 'maxRangeNm': 999.0};
      final result = NavigationConstants.readDistanceMeters(
        props,
        siKey: 'maxRangeMeters',
        legacyNmKey: 'maxRangeNm',
        defaultMeters: 1000.0,
      );
      expect(result, 9260.0);
    });

    test('migrates the legacy NM key when SI key is missing', () {
      final props = {'maxRangeNm': 5.0};
      final result = NavigationConstants.readDistanceMeters(
        props,
        siKey: 'maxRangeMeters',
        legacyNmKey: 'maxRangeNm',
        defaultMeters: 1000.0,
      );
      expect(result, closeTo(9260.0, 1e-9),
          reason: '5 nautical miles × 1852 m/nm');
    });

    test('returns default when neither key present', () {
      final result = NavigationConstants.readDistanceMeters(
        const {},
        siKey: 'maxRangeMeters',
        legacyNmKey: 'maxRangeNm',
        defaultMeters: 1852.0,
      );
      expect(result, 1852.0);
    });

    test('returns default when props is null', () {
      final result = NavigationConstants.readDistanceMeters(
        null,
        siKey: 'maxRangeMeters',
        legacyNmKey: 'maxRangeNm',
        defaultMeters: 42.0,
      );
      expect(result, 42.0);
    });

    test('handles int values coerced to double', () {
      final result = NavigationConstants.readDistanceMeters(
        const {'maxRangeNm': 100},
        siKey: 'maxRangeMeters',
        legacyNmKey: 'maxRangeNm',
        defaultMeters: 0.0,
      );
      expect(result, closeTo(185200.0, 1e-6));
    });
  });
}
