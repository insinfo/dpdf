import 'package:html/dom.dart' as dom;

import 'package:dpdf/src/styledxmlparser/css/resolve/css_inheritance.dart';
import 'package:dpdf/src/styledxmlparser/css/resolve/style_inheritance.dart';
import 'package:dpdf/src/svg/css/impl/svg_attribute_inheritance.dart';
import 'package:dpdf/src/svg/processors/svg_renderer_factory.dart';
import 'package:dpdf/src/svg/renderers/branch_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/text_svg_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

/// Constrói a árvore de renderizadores a partir do DOM produzido pelo pacote
/// `html`.
///
/// A herança de estilo é resolvida aqui, na montagem, e não no desenho: o
/// mapa de cada renderizador já chega completo, de modo que o renderizador
/// nunca precisa consultar o pai para saber com que cor pintar.
class DefaultSvgProcessor {
  const DefaultSvgProcessor();

  static final RegExp _cssRule = RegExp(r'([^{}]+)\{([^{}]*)\}');

  static final List<StyleInheritance> _inheritanceRules = [
    SvgAttributeInheritance(),
    CssInheritance(),
  ];

  /// Monta a árvore a partir de um elemento `<svg>`. Devolve `null` quando o
  /// elemento não é reconhecido.
  SvgNodeRenderer? process(dom.Element element) {
    final rules = _collectStyleRules(element);
    return _build(element, const <String, String>{}, rules);
  }

  SvgNodeRenderer? _build(dom.Element element, Map<String, String> inherited,
      List<_SvgStyleRule> rules) {
    final name = element.localName;
    if (name == null) return null;
    final renderer = SvgRendererFactory.create(name);
    if (renderer == null) return null;

    final resolved = _resolveAttributes(element, inherited, rules);
    renderer.setAttributesAndStyles(resolved);

    if (renderer is BranchSvgNodeRenderer) {
      final inheritable = _inheritablePart(resolved);
      for (final child in element.nodes) {
        SvgNodeRenderer? childRenderer;
        if (child is dom.Text &&
            (name == SvgTags.TEXT || name == SvgTags.TSPAN) &&
            child.data.isNotEmpty) {
          childRenderer = TextLeafSvgNodeRenderer()
            ..setAttributesAndStyles(
                Map<String, String>.from(resolved)..['_text'] = child.data);
        } else if (child is dom.Element) {
          childRenderer = _build(child, inheritable, rules);
        }
        if (childRenderer != null) {
          childRenderer.setParent(renderer);
          renderer.addChild(childRenderer);
        }
      }
    }
    return renderer;
  }

  /// Ordem de precedência: herdado, depois atributo de apresentação, depois
  /// declaração do atributo `style` — a mesma da cascata em SVG, onde o
  /// `style` inline vence qualquer atributo do próprio elemento.
  Map<String, String> _resolveAttributes(dom.Element element,
      Map<String, String> inherited, List<_SvgStyleRule> rules) {
    final own = <String, String>{};
    element.attributes.forEach((key, value) {
      // Chaves com namespace (`xmlns`, `xlink:href`) chegam como objeto e não
      // como String; nenhuma delas influencia o subconjunto suportado.
      final name = key is String ? key : key.toString();
      own[name] = value;
    });
    final resolved = Map<String, String>.from(inherited);
    resolved.addAll(own);
    final matching = rules.where((rule) => rule.matches(element)).toList()
      ..sort((a, b) {
        final bySpecificity = a.specificity.compareTo(b.specificity);
        return bySpecificity != 0 ? bySpecificity : a.order.compareTo(b.order);
      });
    for (final rule in matching) {
      resolved.addAll(rule.declarations);
    }
    final style = own[SvgAttributes.STYLE];
    if (style != null) resolved.addAll(_parseStyleDeclarations(style));
    return resolved;
  }

  static List<_SvgStyleRule> _collectStyleRules(dom.Element root) {
    final rules = <_SvgStyleRule>[];
    var order = 0;
    for (final style in root.querySelectorAll('style')) {
      final css = style.text.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
      for (final match in _cssRule.allMatches(css)) {
        final declarations = _parseStyleDeclarations(match.group(2)!);
        if (declarations.isEmpty) continue;
        for (final selector in match.group(1)!.split(',')) {
          final parsed = _SvgStyleRule.parse(selector, declarations, order++);
          if (parsed != null) rules.add(parsed);
        }
      }
    }
    return rules;
  }

  Map<String, String> _inheritablePart(Map<String, String> styles) {
    final inheritable = <String, String>{};
    styles.forEach((key, value) {
      if (_isInheritable(key)) inheritable[key] = value;
    });
    return inheritable;
  }

  static bool _isInheritable(String property) =>
      _inheritanceRules.any((rule) => rule.isInheritable(property));

  /// Analisador mínimo do atributo `style`: pares `nome: valor` separados por
  /// ponto e vírgula. Não trata valores que contenham `;` (só ocorrem em
  /// `url(data:…)`, que este módulo ainda não resolve).
  static Map<String, String> _parseStyleDeclarations(String style) {
    final declarations = <String, String>{};
    for (final part in style.split(';')) {
      final separator = part.indexOf(':');
      if (separator <= 0) continue;
      final property = part.substring(0, separator).trim().toLowerCase();
      final value = part.substring(separator + 1).trim();
      if (property.isEmpty || value.isEmpty) continue;
      declarations[property] = value;
    }
    return declarations;
  }
}

/// Regra para estilos SVG embutidos: compostos de tipo, id e classes, ligados
/// pelos combinadores descendente e filho direto.
class _SvgStyleRule {
  final List<_SvgSimpleSelector> selectors;
  final List<bool> directChild;
  final Map<String, String> declarations;
  final int specificity;
  final int order;

  const _SvgStyleRule(this.selectors, this.directChild, this.declarations,
      this.specificity, this.order);

  static _SvgStyleRule? parse(
      String raw, Map<String, String> declarations, int order) {
    final selector = raw.trim();
    if (selector.isEmpty) return null;
    final tokens = _selectorTokens(selector);
    if (tokens == null) return null;
    final selectors = <_SvgSimpleSelector>[];
    final directChild = <bool>[];
    var pendingChild = false;
    for (final token in tokens) {
      if (token == '>') {
        if (selectors.isEmpty || pendingChild) return null;
        pendingChild = true;
        continue;
      }
      final parsed = _SvgSimpleSelector.parse(token);
      if (parsed == null) return null;
      if (selectors.isNotEmpty) directChild.add(pendingChild);
      selectors.add(parsed);
      pendingChild = false;
    }
    if (selectors.isEmpty || pendingChild) return null;
    return _SvgStyleRule(
      List.unmodifiable(selectors),
      List.unmodifiable(directChild),
      Map<String, String>.unmodifiable(declarations),
      selectors.fold(0, (sum, part) => sum + part.specificity),
      order,
    );
  }

  bool matches(dom.Element element) {
    var current = element;
    if (!selectors.last.matches(current)) return false;
    for (var index = selectors.length - 2; index >= 0; index--) {
      final wanted = selectors[index];
      var ancestor = current.parent;
      if (directChild[index]) {
        if (ancestor is! dom.Element || !wanted.matches(ancestor)) return false;
        current = ancestor;
        continue;
      }
      while (ancestor is dom.Element && !wanted.matches(ancestor)) {
        ancestor = ancestor.parent;
      }
      if (ancestor is! dom.Element) return false;
      current = ancestor;
    }
    return true;
  }
}

class _SvgSimpleSelector {
  final String? tag;
  final String? id;
  final Set<String> classes;
  final List<_SvgAttributeSelector> attributes;
  final int specificity;

  const _SvgSimpleSelector(
      this.tag, this.id, this.classes, this.attributes, this.specificity);

  static _SvgSimpleSelector? parse(String selector) {
    final attributePattern = RegExp(
        r'''\[\s*([A-Za-z_][\w:.-]*)\s*(?:(~=|\|=|\^=|\$=|\*=|=)\s*(?:"([^"]*)"|'([^']*)'|([^\]\s]+)))?\s*\]''');
    final attributeMatches = attributePattern.allMatches(selector).toList();
    final attributes = <_SvgAttributeSelector>[
      for (final match in attributeMatches)
        _SvgAttributeSelector(match.group(1)!, match.group(2),
            match.group(3) ?? match.group(4) ?? match.group(5)),
    ];
    final plain = selector.replaceAll(attributePattern, '');
    final idMatches = RegExp(r'#([\w-]+)').allMatches(plain).toList();
    if (idMatches.length > 1) return null;
    final id = idMatches.isEmpty ? null : idMatches.single.group(1);
    final classes = RegExp(r'\.([\w-]+)')
        .allMatches(plain)
        .map((match) => match.group(1)!)
        .toSet();
    final tagMatch = RegExp(r'^([A-Za-z][\w-]*|\*)').firstMatch(plain);
    if (id == null &&
        classes.isEmpty &&
        attributes.isEmpty &&
        tagMatch == null) {
      return null;
    }
    final parts = RegExp(r'(^[A-Za-z][\w-]*|^\*|[.#][\w-]+)')
        .allMatches(selector)
        .map((match) => match.group(0)!)
        .join();
    if (parts != plain ||
        attributeMatches.map((match) => match.group(0)!).join().length !=
            selector.length - plain.length) {
      return null;
    }
    final rawTag = tagMatch?.group(1);
    final tag = rawTag == '*' ? null : rawTag;
    return _SvgSimpleSelector(
      tag,
      id,
      classes,
      List.unmodifiable(attributes),
      (id == null ? 0 : 100) +
          (classes.length + attributes.length) * 10 +
          (tag == null ? 0 : 1),
    );
  }

  bool matches(dom.Element element) {
    if (tag != null && element.localName != tag) return false;
    if (id != null && element.id != id) return false;
    final actual = (element.attributes['class'] ?? '')
        .split(RegExp(r'\s+'))
        .where((value) => value.isNotEmpty)
        .toSet();
    return classes.every(actual.contains) &&
        attributes.every((selector) => selector.matches(element));
  }
}

class _SvgAttributeSelector {
  final String name;
  final String? operator;
  final String? value;

  const _SvgAttributeSelector(this.name, this.operator, this.value);

  bool matches(dom.Element element) {
    if (!element.attributes.containsKey(name)) return false;
    if (operator == null) return true;
    final actual = element.attributes[name] ?? '';
    final expected = value ?? '';
    switch (operator) {
      case '=':
        return actual == expected;
      case '~=':
        return actual.split(RegExp(r'\s+')).contains(expected);
      case '|=':
        return actual == expected || actual.startsWith('$expected-');
      case '^=':
        return actual.startsWith(expected);
      case r'$=':
        return actual.endsWith(expected);
      case '*=':
        return actual.contains(expected);
    }
    return false;
  }
}

List<String>? _selectorTokens(String selector) {
  final tokens = <String>[];
  final current = StringBuffer();
  var brackets = 0;
  String? quote;
  void flush() {
    final token = current.toString().trim();
    if (token.isNotEmpty) tokens.add(token);
    current.clear();
  }

  for (var index = 0; index < selector.length; index++) {
    final char = selector[index];
    if (quote != null) {
      current.write(char);
      if (char == quote && (index == 0 || selector[index - 1] != r'\')) {
        quote = null;
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      current.write(char);
    } else if (char == '[') {
      brackets++;
      current.write(char);
    } else if (char == ']') {
      if (brackets == 0) return null;
      brackets--;
      current.write(char);
    } else if (brackets == 0 && char == '>') {
      flush();
      tokens.add('>');
    } else if (brackets == 0 && char.trim().isEmpty) {
      flush();
    } else {
      current.write(char);
    }
  }
  if (quote != null || brackets != 0) return null;
  flush();
  return tokens;
}
