/// Small, allocation-conscious CSS syntax reader used by the HTML renderer.
///
/// It deliberately reads only style rules and declarations.  It is not a
/// browser CSS implementation, but it preserves quoted strings, comments and
/// nested function values so that delimiters inside them never split a rule.
class CssRuleSyntax {
  final String selectorText;
  final List<CssDeclarationSyntax> declarations;

  const CssRuleSyntax(this.selectorText, this.declarations);
}

class CssDeclarationSyntax {
  final String property;
  final String value;
  final bool important;

  const CssDeclarationSyntax(this.property, this.value,
      {this.important = false});
}

class CssSyntax {
  CssSyntax._();

  /// Parses top-level style rules. At-rules are skipped as a unit; their
  /// contents cannot accidentally become ordinary declarations.
  static List<CssRuleSyntax> parseStyleRules(String source) {
    final reader = _CssReader(source);
    final rules = <CssRuleSyntax>[];
    while (!reader.isAtEnd) {
      reader.skipTrivia();
      if (reader.isAtEnd) break;
      final prelude = reader.readUntilTopLevel(const {'{', ';'}).trim();
      if (reader.isAtEnd) break;
      final delimiter = reader.take();
      if (delimiter == ';') continue;
      final body = reader.readBlockBody();
      if (prelude.isEmpty || prelude.startsWith('@')) continue;
      final declarations = parseDeclarations(body);
      if (declarations.isNotEmpty) {
        rules.add(CssRuleSyntax(prelude, declarations));
      }
    }
    return rules;
  }

  /// Parses a declaration list from either a style attribute or a rule body.
  static List<CssDeclarationSyntax> parseDeclarations(String source) {
    final reader = _CssReader(source);
    final declarations = <CssDeclarationSyntax>[];
    while (!reader.isAtEnd) {
      reader.skipTrivia();
      final name = reader.readUntilTopLevel(const {':', ';', '}'}).trim();
      if (reader.isAtEnd || name.isEmpty) {
        if (!reader.isAtEnd) reader.take();
        continue;
      }
      final separator = reader.take();
      if (separator != ':') continue;
      final value = reader.readUntilTopLevel(const {';', '}'}).trim();
      if (!reader.isAtEnd) reader.take();
      final parsed = _declaration(name, value);
      if (parsed != null) declarations.add(parsed);
    }
    return declarations;
  }

  static CssDeclarationSyntax? _declaration(String name, String value) {
    final property = name.toLowerCase();
    if (property.isEmpty || value.isEmpty) return null;
    final important = _endsWithImportant(value);
    final effectiveValue = important ? _removeImportant(value).trim() : value;
    return effectiveValue.isEmpty
        ? null
        : CssDeclarationSyntax(property, effectiveValue, important: important);
  }

  static bool _endsWithImportant(String value) {
    var index = value.length - 1;
    while (index >= 0 && _isWhitespace(value.codeUnitAt(index))) {
      index--;
    }
    const word = 'important';
    if (index + 1 < word.length) return false;
    final start = index - word.length + 1;
    if (value.substring(start, index + 1).toLowerCase() != word) return false;
    index = start - 1;
    while (index >= 0 && _isWhitespace(value.codeUnitAt(index))) {
      index--;
    }
    return index >= 0 && value.codeUnitAt(index) == 0x21;
  }

  static String _removeImportant(String value) {
    var index = value.length - 1;
    while (_isWhitespace(value.codeUnitAt(index))) {
      index--;
    }
    index -= 'important'.length;
    while (index >= 0 && _isWhitespace(value.codeUnitAt(index))) {
      index--;
    }
    return value.substring(0, index); // excludes the exclamation mark.
  }

  static bool _isWhitespace(int codeUnit) =>
      codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0a ||
      codeUnit == 0x0d ||
      codeUnit == 0x0c;
}

class _CssReader {
  final String source;
  int offset = 0;
  _CssReader(this.source);

  bool get isAtEnd => offset >= source.length;
  String take() => source[offset++];

  void skipTrivia() {
    while (!isAtEnd) {
      final code = source.codeUnitAt(offset);
      if (CssSyntax._isWhitespace(code)) {
        offset++;
      } else if (code == 0x2f &&
          offset + 1 < source.length &&
          source.codeUnitAt(offset + 1) == 0x2a) {
        offset += 2;
        while (offset + 1 < source.length &&
            !(source.codeUnitAt(offset) == 0x2a &&
                source.codeUnitAt(offset + 1) == 0x2f)) {
          offset++;
        }
        offset = offset + 1 < source.length ? offset + 2 : source.length;
      } else {
        return;
      }
    }
  }

  String readUntilTopLevel(Set<String> delimiters) {
    final start = offset;
    var parentheses = 0;
    var brackets = 0;
    String? quote;
    while (!isAtEnd) {
      final char = source[offset];
      if (quote != null) {
        if (char == '\\' && offset + 1 < source.length) {
          offset += 2;
        } else {
          offset++;
          if (char == quote) quote = null;
        }
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        offset++;
      } else if (char == '/' &&
          offset + 1 < source.length &&
          source[offset + 1] == '*') {
        skipTrivia();
      } else if (char == '(') {
        parentheses++;
        offset++;
      } else if (char == ')') {
        if (parentheses > 0) parentheses--;
        offset++;
      } else if (char == '[') {
        brackets++;
        offset++;
      } else if (char == ']') {
        if (brackets > 0) brackets--;
        offset++;
      } else if (parentheses == 0 &&
          brackets == 0 &&
          delimiters.contains(char)) {
        break;
      } else {
        offset++;
      }
    }
    return source.substring(start, offset);
  }

  String readBlockBody() {
    final start = offset;
    var depth = 1;
    String? quote;
    while (!isAtEnd && depth > 0) {
      final char = source[offset];
      if (quote != null) {
        if (char == '\\' && offset + 1 < source.length) {
          offset += 2;
        } else {
          offset++;
          if (char == quote) quote = null;
        }
      } else if (char == '"' || char == "'") {
        quote = char;
        offset++;
      } else if (char == '/' &&
          offset + 1 < source.length &&
          source[offset + 1] == '*') {
        skipTrivia();
      } else {
        offset++;
        if (char == '{') depth++;
        if (char == '}') depth--;
      }
    }
    final end = depth == 0 ? offset - 1 : offset;
    return source.substring(start, end);
  }
}
