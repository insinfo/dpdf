import 'package:pdfcraft/src/kernel/numbering/greek_alphabet_numbering.dart';
import 'package:pdfcraft/src/kernel/numbering/roman_numbering.dart';
import 'package:test/test.dart';

void main() {
  test('Roman decimal boundaries, sign and recursive thousands', () {
    const cases = {
      0: '',
      1: 'i',
      4: 'iv',
      9: 'ix',
      40: 'xl',
      49: 'xlix',
      90: 'xc',
      99: 'xcix',
      400: 'cd',
      944: 'cmxliv',
      1999: 'mcmxcix',
      3999: 'mmmcmxcix',
      4000: '|iv|',
      4001: '|iv|i',
      3999999: '|mmmcmxcix|cmxcix',
      4000000: '||iv||',
      4001002: '||iv|i|ii',
    };
    for (final entry in cases.entries) {
      expect(CraftRomanNumbering.toRomanLowerCase(entry.key), entry.value);
      expect(CraftRomanNumbering.toRoman(entry.key, true),
          entry.value.toUpperCase());
      if (entry.key != 0) {
        expect(CraftRomanNumbering.toRomanLowerCase(-entry.key),
            '-${entry.value}');
      }
    }
  });

  test('Roman labels round trip every value below 4000', () {
    const values = {
      'i': 1,
      'v': 5,
      'x': 10,
      'l': 50,
      'c': 100,
      'd': 500,
      'm': 1000
    };
    for (var number = 1; number < 4000; number++) {
      final label = CraftRomanNumbering.toRomanLowerCase(number);
      var decoded = 0;
      for (var index = 0; index < label.length; index++) {
        final value = values[label[index]]!;
        final next = index + 1 < label.length ? values[label[index + 1]]! : 0;
        decoded += value < next ? -value : value;
      }
      expect(decoded, number);
    }
  });

  test('Roman minimum machine integer avoids signed magnitude overflow', () {
    final minimum = int.tryParse('-9223372036854775808');
    if (minimum != null) {
      final label = CraftRomanNumbering.toRomanLowerCase(minimum);
      expect(label, startsWith('-|'));
      expect(label, endsWith('dcccviii'));
      expect(label.substring(1), isNot(contains('-')));
    }
  });

  test('Greek bijective boundaries and Symbol encoding', () {
    const cases = {
      1: 'α',
      17: 'ρ',
      18: 'σ',
      24: 'ω',
      25: 'αα',
      48: 'αω',
      49: 'βα',
      600: 'ωω',
      601: 'ααα'
    };
    for (final entry in cases.entries) {
      expect(
          CraftGreekAlphabetNumbering.toGreekAlphabetNumberLowerCase(entry.key),
          entry.value);
      expect(
          CraftGreekAlphabetNumbering.toGreekAlphabetNumberUpperCase(entry.key),
          entry.value.toUpperCase());
    }
    const symbol = 'abgdezhqiklmnxoprstufcyw';
    for (var number = 1; number <= 24; number++) {
      expect(
          CraftGreekAlphabetNumbering.toGreekAlphabetNumber(
              number, false, true),
          symbol[number - 1]);
      expect(
          CraftGreekAlphabetNumbering.toGreekAlphabetNumber(number, true, true),
          symbol[number - 1].toUpperCase());
    }
    expect(CraftGreekAlphabetNumbering.toGreekAlphabetNumber(601, false, true),
        'aaa');
  });

  test('Greek rejects zero and negative ordinals', () {
    for (final number in [0, -1, -100]) {
      expect(
          () =>
              CraftGreekAlphabetNumbering.toGreekAlphabetNumber(number, false),
          throwsRangeError);
      expect(
          () => CraftGreekAlphabetNumbering.toGreekAlphabetNumber(
              number, true, true),
          throwsRangeError);
    }
  });
}
