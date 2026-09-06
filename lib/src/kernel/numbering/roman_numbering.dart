class RomanNumbering {
  static final List<_RomanDigit> ROMAN_DIGITS = [
    _RomanDigit('m', 1000, false),
    _RomanDigit('d', 500, false),
    _RomanDigit('c', 100, true),
    _RomanDigit('l', 50, false),
    _RomanDigit('x', 10, true),
    _RomanDigit('v', 5, false),
    _RomanDigit('i', 1, true)
  ];

  static String toRomanLowerCase(int number) {
    return _convert(number);
  }

  static String toRomanUpperCase(int number) {
    return _convert(number).toUpperCase();
  }

  static String toRoman(int number, bool upperCase) {
    return upperCase ? toRomanUpperCase(number) : toRomanLowerCase(number);
  }

  static String _convert(int index) {
    StringBuffer buf = StringBuffer();
    if (index < 0) {
      buf.write('-');
      index = -index;
    }
    if (index >= 4000) {
      buf.write('|');
      buf.write(_convert(index ~/ 1000));
      buf.write('|');
      index = index % 1000;
    }

    int pos = 0;
    while (true) {
      _RomanDigit dig = ROMAN_DIGITS[pos];
      while (index >= dig.value) {
        buf.write(dig.digit);
        index -= dig.value;
      }

      if (index <= 0) {
        break;
      }

      int j = pos;
      while (!ROMAN_DIGITS[++j].pre) {}

      if (index + ROMAN_DIGITS[j].value >= dig.value) {
        buf.write(ROMAN_DIGITS[j].digit);
        buf.write(dig.digit);
        index -= dig.value - ROMAN_DIGITS[j].value;
      }
      pos++;
    }
    return buf.toString();
  }
}

class _RomanDigit {
  final String digit;
  final int value;
  final bool pre;

  _RomanDigit(this.digit, this.value, this.pre);
}
