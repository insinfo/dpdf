/// Positive integers in a bijective positional alphabet (A, ..., AA).
class CraftAlphabetNumbering {
  static String toAlphabetNumber(int number, List<String> alphabet) {
    if (number < 1) throw RangeError.range(number, 1, null, 'number');
    if (alphabet.isEmpty) {
      throw ArgumentError.value(
          alphabet, 'alphabet', 'Provide at least one symbol.');
    }
    final digits = <String>[];
    while (number > 0) {
      final ordinal = number - 1;
      digits.add(alphabet[ordinal % alphabet.length]);
      number = ordinal ~/ alphabet.length;
    }
    return digits.reversed.join();
  }
}
