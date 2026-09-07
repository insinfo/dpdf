import 'package:html/dom.dart' as dom;

import 'package:dpdf/src/styledxmlparser/css/resolve/css_inheritance.dart';
import 'package:dpdf/src/styledxmlparser/css/resolve/style_inheritance.dart';
import 'package:dpdf/src/svg/css/impl/svg_attribute_inheritance.dart';
import 'package:dpdf/src/svg/processors/svg_renderer_factory.dart';
import 'package:dpdf/src/svg/renderers/branch_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

/// Constrói a árvore de renderizadores a partir do DOM produzido pelo pacote
/// `html`.
///
/// A herança de estilo é resolvida aqui, na montagem, e não no desenho: o
/// mapa de cada renderizador já chega completo, de modo que o renderizador
/// nunca precisa consultar o pai para saber com que cor pintar.
class DefaultSvgProcessor {
  const DefaultSvgProcessor();

  static final List<StyleInheritance> _inheritanceRules = [
    SvgAttributeInheritance(),
    CssInheritance(),
  ];

  /// Monta a árvore a partir de um elemento `<svg>`. Devolve `null` quando o
  /// elemento não é reconhecido.
  SvgNodeRenderer? process(dom.Element element) =>
      _build(element, const <String, String>{});

  SvgNodeRenderer? _build(dom.Element element, Map<String, String> inherited) {
    final name = element.localName;
    if (name == null) return null;
    final renderer = SvgRendererFactory.create(name);
    if (renderer == null) return null;

    final resolved = _resolveAttributes(element, inherited);
    renderer.setAttributesAndStyles(resolved);

    if (renderer is BranchSvgNodeRenderer) {
      final inheritable = _inheritablePart(resolved);
      for (final child in element.children) {
        final childRenderer = _build(child, inheritable);
        if (childRenderer == null) continue;
        childRenderer.setParent(renderer);
        renderer.addChild(childRenderer);
      }
    }
    return renderer;
  }

  /// Ordem de precedência: herdado, depois atributo de apresentação, depois
  /// declaração do atributo `style` — a mesma da cascata em SVG, onde o
  /// `style` inline vence qualquer atributo do próprio elemento.
  Map<String, String> _resolveAttributes(
      dom.Element element, Map<String, String> inherited) {
    final own = <String, String>{};
    element.attributes.forEach((key, value) {
      // Chaves com namespace (`xmlns`, `xlink:href`) chegam como objeto e não
      // como String; nenhuma delas influencia o subconjunto suportado.
      if (key is String) own[key] = value;
    });
    final style = own[SvgAttributes.STYLE];
    if (style != null) own.addAll(_parseStyleDeclarations(style));

    final resolved = Map<String, String>.from(inherited);
    resolved.addAll(own);
    return resolved;
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
