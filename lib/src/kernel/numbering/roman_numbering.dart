/// Roman page labels, with vertical bars denoting multiplication by 1000.
class RomanNumbering {
  /// Retained for source compatibility. Conversion uses decimal places.
  @Deprecated('The conversion methods do not require a digit table.')
  static final List<_RomanDigit> ROMAN_DIGITS = [
    _RomanDigit('m', 1000, false),
    _RomanDigit('d', 500, false),
    _RomanDigit('c', 100, true),
    _RomanDigit('l', 50, false),
    _RomanDigit('x', 10, true),
    _RomanDigit('v', 5, false),
    _RomanDigit('i', 1, true),
  ];

  static String toRomanLowerCase(int number) => toRoman(number, false);
  static String toRomanUpperCase(int number) => toRoman(number, true);

  /// Zero is an empty label; negative labels carry a leading minus sign.
  static String toRoman(int number, bool upperCase) {
    final magnitude = BigInt.from(number).abs();
    final label = '${number < 0 ? '-' : ''}${_magnitude(magnitude)}';
    return upperCase ? label.toUpperCase() : label;
  }

  static String _magnitude(BigInt number) {
    final thousand = BigInt.from(1000);
    final out = StringBuffer();
    if (number >= BigInt.from(4000)) {
      out.write('|${_magnitude(number ~/ thousand)}|');
      number %= thousand;
    }
    var remaining = number.toInt();
    out.write('m' * (remaining ~/ 1000));
    remaining %= 1000;
    // Each decimal place uses the same subtractive spelling rules.
    const symbols = ['cdm', 'xlc', 'ivx'];
    var place = 100;
    for (final triplet in symbols) {
      final digit = remaining ~/ place;
      remaining %= place;
      place ~/= 10;
      if (digit == 9) {
        out.write('${triplet[0]}${triplet[2]}');
      } else if (digit == 4) {
        out.write('${triplet[0]}${triplet[1]}');
      } else {
        if (digit >= 5) out.write(triplet[1]);
        out.write(triplet[0] * (digit % 5));
      }
    }
    return out.toString();
  }
}

class _RomanDigit {
  final String digit;
  final int value;
  final bool pre;
  _RomanDigit(this.digit, this.value, this.pre);
}
