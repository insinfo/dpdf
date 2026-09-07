import 'package:html/dom.dart' as dom;

import 'css_syntax.dart';

/// Immutable author stylesheet for the HTML-to-PDF layout engine.
///
/// Selectors deliberately cover the portable profile: type, class, id and
/// compounds of those forms. The parser safely skips unsupported selectors.
class HtmlStyleSheet {
  final List<_Rule> _rules;
  final List<HtmlFontFaceRule> fontFaces;
  HtmlStyleSheet._(this._rules, this.fontFaces);

  factory HtmlStyleSheet.fromDocument(dom.Document document) {
    final rules = <_Rule>[];
    final fontFaces = <HtmlFontFaceRule>[];
    var order = 0;
    for (final style in document.querySelectorAll('style')) {
      fontFaces.addAll(_parseFontFaces(style.text));
      for (final rule in CssSyntax.parseStyleRules(style.text)) {
        for (final source in _splitSelectorList(rule.selectorText)) {
          final selector = _Selector.parse(source.trim(), order++);
          if (selector != null && rule.declarations.isNotEmpty) {
            rules.add(_Rule(selector, rule.declarations));
          }
        }
      }
    }
    return HtmlStyleSheet._(rules, fontFaces);
  }

  Map<String, String> resolve(dom.Element element) {
    final matched = _rules
        .where((rule) => rule.selector.matches(element))
        .toList()
      ..sort((a, b) => a.selector.compareCascadeOrder(b.selector));
    final result = <String, CssDeclarationSyntax>{};
    for (final rule in matched) {
      for (final declaration in rule.declarations) {
        final previous = result[declaration.property];
        if (previous == null || declaration.important || !previous.important) {
          result[declaration.property] = declaration;
        }
      }
    }
    // Inline author declarations are stronger than an equally-important
    // stylesheet declaration, while a stylesheet !important beats inline.
    for (final declaration
        in CssSyntax.parseDeclarations(element.attributes['style'] ?? '')) {
      final previous = result[declaration.property];
      if (previous == null || declaration.important || !previous.important) {
        result[declaration.property] = declaration;
      }
    }
    return {for (final entry in result.entries) entry.key: entry.value.value};
  }

  static Map<String, String> declarationsOf(String source) => {
        for (final declaration in CssSyntax.parseDeclarations(source))
          declaration.property: declaration.value
      };
}

class HtmlFontFaceRule {
  final String family;
  final List<String> sources;
  const HtmlFontFaceRule(this.family, this.sources);
}

List<HtmlFontFaceRule> _parseFontFaces(String source) {
  final result = <HtmlFontFaceRule>[];
  final rulePattern = RegExp(r'@font-face\s*\{([^{}]*)\}',
      caseSensitive: false, multiLine: true);
  final urlPattern = RegExp(
      r'''url\(\s*(?:"([^"]*)"|'([^']*)'|([^\s\)]*))\s*\)''',
      caseSensitive: false);
  for (final match in rulePattern.allMatches(source)) {
    final declarations = HtmlStyleSheet.declarationsOf(match.group(1)!);
    var family = declarations['font-family']?.trim();
    if (family == null || family.isEmpty) continue;
    if (family.length >= 2 &&
        ((family.startsWith('"') && family.endsWith('"')) ||
            (family.startsWith("'") && family.endsWith("'")))) {
      family = family.substring(1, family.length - 1);
    }
    final sources = <String>[];
    for (final url in urlPattern.allMatches(declarations['src'] ?? '')) {
      final value = url.group(1) ?? url.group(2) ?? url.group(3);
      if (value != null && value.isNotEmpty) sources.add(value);
    }
    if (sources.isNotEmpty) result.add(HtmlFontFaceRule(family, sources));
  }
  return result;
}

class _Rule {
  final _Selector selector;
  final List<CssDeclarationSyntax> declarations;
  const _Rule(this.selector, this.declarations);
}

class _Selector {
  final String? tag;
  final String? id;
  final Set<String> classes;
  final int order;
  const _Selector(this.tag, this.id, this.classes, this.order);

  static _Selector? parse(String source, int order) {
    if (source.isEmpty) return null;
    var offset = 0;
    String? tag;
    String? id;
    final classes = <String>{};
    if (_isIdentifierStart(source.codeUnitAt(0))) {
      final end = _identifierEnd(source, 0);
      tag = source.substring(0, end).toLowerCase();
      offset = end;
    }
    while (offset < source.length) {
      final marker = source[offset++];
      if (marker != '#' && marker != '.') return null;
      final start = offset;
      if (start == source.length ||
          !_isIdentifierStart(source.codeUnitAt(start))) {
        return null;
      }
      offset = _identifierEnd(source, start);
      final value = source.substring(start, offset);
      if (marker == '#') {
        if (id != null) return null;
        id = value;
      } else {
        classes.add(value);
      }
    }
    return tag == null && id == null && classes.isEmpty
        ? null
        : _Selector(tag, id, classes, order);
  }

  int compareCascadeOrder(_Selector other) {
    final idComparison =
        (id == null ? 0 : 1).compareTo(other.id == null ? 0 : 1);
    if (idComparison != 0) return idComparison;
    final classComparison = classes.length.compareTo(other.classes.length);
    if (classComparison != 0) return classComparison;
    final tagComparison =
        (tag == null ? 0 : 1).compareTo(other.tag == null ? 0 : 1);
    return tagComparison != 0 ? tagComparison : order.compareTo(other.order);
  }

  bool matches(dom.Element element) =>
      (tag == null || element.localName?.toLowerCase() == tag) &&
      (id == null || element.id == id) &&
      classes.every(element.classes.contains);
}

List<String> _splitSelectorList(String source) {
  final selectors = <String>[];
  var start = 0;
  String? quote;
  var depth = 0;
  for (var index = 0; index < source.length; index++) {
    final char = source[index];
    if (quote != null) {
      if (char == '\\') index++;
      if (char == quote) quote = null;
    } else if (char == '"' || char == "'") {
      quote = char;
    } else if (char == '(' || char == '[') {
      depth++;
    } else if ((char == ')' || char == ']') && depth > 0) {
      depth--;
    } else if (char == ',' && depth == 0) {
      selectors.add(source.substring(start, index));
      start = index + 1;
    }
  }
  selectors.add(source.substring(start));
  return selectors;
}

bool _isIdentifierStart(int codeUnit) =>
    (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
    (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
    codeUnit == 0x5f ||
    codeUnit == 0x2d ||
    codeUnit >= 0x80;

int _identifierEnd(String value, int offset) {
  while (offset < value.length) {
    final codeUnit = value.codeUnitAt(offset);
    if (!_isIdentifierStart(codeUnit) &&
        !(codeUnit >= 0x30 && codeUnit <= 0x39)) {
      break;
    }
    offset++;
  }
  return offset;
}
