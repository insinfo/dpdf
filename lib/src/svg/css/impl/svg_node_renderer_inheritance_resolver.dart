import 'package:dpdf/src/styledxmlparser/css/resolve/css_inheritance.dart';
import 'package:dpdf/src/styledxmlparser/css/resolve/style_inheritance.dart';
import 'package:dpdf/src/svg/css/impl/svg_attribute_inheritance.dart';
import 'package:dpdf/src/svg/renderers/branch_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';

/// Empurra as propriedades herdáveis de um renderizador para dentro de uma
/// subárvore montada fora do lugar onde ela será desenhada.
///
/// É o caso de `<use>` e de `<clipPath>`: a árvore foi construída — e a
/// cascata resolvida — na posição de declaração, mas a cópia é desenhada como
/// se fosse filha de quem a referencia. Sem este passo, `fill` declarado no
/// `<use>` nunca alcançaria a forma instanciada.
///
/// O valor já presente no nó vence o herdado, como manda a cascata: só as
/// lacunas são preenchidas.
class SvgNodeRendererInheritanceResolver {
  SvgNodeRendererInheritanceResolver._();

  static final List<StyleInheritance> _rules = [
    SvgAttributeInheritance(),
    CssInheritance(),
  ];

  static void applyInheritanceToSubTree(
      SvgNodeRenderer? parent, SvgNodeRenderer? child, Object? cssContext) {
    if (parent == null || child == null) return;
    _apply(child, _inheritablePart(parent.getAttributeMapCopy()));
  }

  static void _apply(SvgNodeRenderer node, Map<String, String> inherited) {
    if (inherited.isNotEmpty) {
      final merged = Map<String, String>.from(inherited)
        ..addAll(node.getAttributeMapCopy());
      node.setAttributesAndStyles(merged);
    }
    if (node is BranchSvgNodeRenderer) {
      final next = _inheritablePart(node.getAttributeMapCopy());
      for (final grandChild in node.getChildren()) {
        _apply(grandChild, next);
      }
    }
  }

  static Map<String, String> _inheritablePart(Map<String, String> styles) {
    final inheritable = <String, String>{};
    styles.forEach((key, value) {
      if (_rules.any((rule) => rule.isInheritable(key))) {
        inheritable[key] = value;
      }
    });
    return inheritable;
  }
}
