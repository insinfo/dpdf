import 'alphabet_numbering.dart';

class EnglishAlphabetNumbering {
  static const int ALPHABET_LENGTH = 26;
  static final List<String> ALPHABET_LOWERCASE = List.generate(
      ALPHABET_LENGTH, (i) => String.fromCharCode('a'.codeUnitAt(0) + i));
  static final List<String> ALPHABET_UPPERCASE = List.generate(
      ALPHABET_LENGTH, (i) => String.fromCharCode('A'.codeUnitAt(0) + i));

  static String toLatinAlphabetNumberLowerCase(int number) {
    return AlphabetNumbering.toAlphabetNumber(number, ALPHABET_LOWERCASE);
  }

  static String toLatinAlphabetNumberUpperCase(int number) {
    return AlphabetNumbering.toAlphabetNumber(number, ALPHABET_UPPERCASE);
  }

  static String toLatinAlphabetNumber(int number, bool upperCase) {
    return upperCase
        ? toLatinAlphabetNumberUpperCase(number)
        : toLatinAlphabetNumberLowerCase(number);
  }
}
