import 'package:flutter_test/flutter_test.dart';
import 'package:zed_display/widgets/tools/victron_flow_tool.dart';
import 'package:zed_display/screens/tool_config/configurators/radio_switch_configurator.dart';

void main() {
  group('victronModeValuesMatch (inverter-mode highlight)', () {
    test('null operands never match', () {
      expect(victronModeValuesMatch(null, 'on'), isFalse);
      expect(victronModeValuesMatch('on', null), isFalse);
      expect(victronModeValuesMatch(null, null), isFalse);
    });

    test('strings match case-insensitively and trimmed', () {
      expect(victronModeValuesMatch('On', 'on'), isTrue);
      expect(victronModeValuesMatch(' charger only ', 'Charger Only'), isTrue);
      expect(victronModeValuesMatch('inverter only', 'on'), isFalse);
    });

    test('numbers compare numerically (int vs double)', () {
      expect(victronModeValuesMatch(3, 3.0), isTrue);
      expect(victronModeValuesMatch(3, 4), isFalse);
    });

    test('mixed number/string falls back to string compare', () {
      expect(victronModeValuesMatch(3, '3'), isTrue);
      expect(victronModeValuesMatch(3, '3.0'), isFalse);
    });
  });

  group('coerceRadioOptionValue (radio-switch value typing)', () {
    test('text type trims and stays a String', () {
      final v = coerceRadioOptionValue('  charger only  ', 'string');
      expect(v, 'charger only');
      expect(v, isA<String>());
    });

    test('number type parses to num, falls back to trimmed text', () {
      expect(coerceRadioOptionValue('12', 'number'), 12);
      expect(coerceRadioOptionValue('12', 'number'), isA<num>());
      expect(coerceRadioOptionValue('1.5', 'number'), 1.5);
      expect(coerceRadioOptionValue('abc', 'number'), 'abc');
    });

    test('bool type maps true/false case-insensitively', () {
      expect(coerceRadioOptionValue('true', 'bool'), true);
      expect(coerceRadioOptionValue(' TRUE ', 'bool'), true);
      expect(coerceRadioOptionValue('false', 'bool'), false);
      expect(coerceRadioOptionValue('anything', 'bool'), false);
    });
  });
}
