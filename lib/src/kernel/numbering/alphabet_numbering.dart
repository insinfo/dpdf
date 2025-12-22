class AlphabetNumbering {
  static String toAlphabetNumber(int number, List<String> alphabet) {
    if (number < 1) {
      throw ArgumentError("The parameter must be a positive integer");
    }
    int cardinality = alphabet.length;
    number--;
    int bytes = 1;
    int start = 0;
    int symbols = cardinality;
    while (number >= symbols + start) {
      bytes++;
      start += symbols;
      // Note: in Dart int is 64-bit, so symbols *= cardinality should be safe for reasonable lists.
      symbols *= cardinality;
    }
    int c = number - start;
    List<String> value = List.filled(bytes, "");
    while (bytes > 0) {
      value[--bytes] = alphabet[c % cardinality];
      c ~/= cardinality;
    }
    return value.join("");
  }
}
