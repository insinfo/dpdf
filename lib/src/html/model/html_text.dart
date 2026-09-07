/// Small text primitives shared by DOM normalization and line layout.
class CraftHtmlText {
  CraftHtmlText._();

  static String collapseWhitespace(String source) {
    final output = StringBuffer();
    var previousWhitespace = false;
    for (final codeUnit in source.codeUnits) {
      final whitespace = _isWhitespace(codeUnit);
      if (whitespace) {
        if (!previousWhitespace) output.write(' ');
      } else {
        output.writeCharCode(codeUnit);
      }
      previousWhitespace = whitespace;
    }
    return output.toString();
  }

  static List<String> words(String source) {
    final result = <String>[];
    final word = StringBuffer();
    for (final codeUnit in source.codeUnits) {
      if (_isWhitespace(codeUnit)) {
        if (word.isNotEmpty) {
          result.add(word.toString());
          word.clear();
        }
      } else {
        word.writeCharCode(codeUnit);
      }
    }
    if (word.isNotEmpty) result.add(word.toString());
    return result;
  }

  static bool _isWhitespace(int codeUnit) =>
      codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0a ||
      codeUnit == 0x0d ||
      codeUnit == 0x0c;
}
