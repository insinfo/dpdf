/// Bijective base-24 labels using the modern Greek alphabet.
class GreekAlphabetNumbering {
  static const int ALPHABET_LENGTH = 24;
  static final List<String> ALPHABET_LOWERCASE =
      'αβγδεζηθικλμνξοπρστυφχψω'.split('');
  static final List<String> ALPHABET_UPPERCASE =
      'ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ'.split('');

  static String toGreekAlphabetNumberLowerCase(int number) =>
      toGreekAlphabetNumber(number, false);

  static String toGreekAlphabetNumberUpperCase(int number) =>
      toGreekAlphabetNumber(number, true);

  static String toGreekAlphabetNumber(int number, bool upperCase,
      [bool symbolFont = false]) {
    if (number < 1) {
      throw RangeError.range(number, 1, null, 'number');
    }
    final alphabet = upperCase ? ALPHABET_UPPERCASE : ALPHABET_LOWERCASE;
    final reversed = <String>[];
    var rest = number;
    while (rest != 0) {
      rest -= 1;
      final letter = alphabet[rest % ALPHABET_LENGTH];
      reversed.add(symbolFont ? _symbol(letter) : letter);
      rest ~/= ALPHABET_LENGTH;
    }
    return reversed.reversed.join();
  }

  // Adobe Symbol encoding positions for the 24 modern Greek letters.
  static String _symbol(String letter) {
    const greek = 'αβγδεζηθικλμνξοπρστυφχψω';
    const encoded = 'abgdezhqiklmnxoprstufcyw';
    if (letter == 'ς') return 'V';
    final slot = greek.indexOf(letter.toLowerCase());
    if (slot < 0 || letter.length != 1) return ' ';
    final code = encoded[slot];
    return letter == letter.toUpperCase() ? code.toUpperCase() : code;
  }
}
