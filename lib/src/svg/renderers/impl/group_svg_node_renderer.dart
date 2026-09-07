import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_branch_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';

/// Renderizador de `<g>`.
///
/// Um grupo não estabelece viewport nem recorta: ele só existe para que
/// atributos herdáveis e `transform` alcancem a subárvore.
class CraftGroupSvgNodeRenderer extends CraftAbstractBranchSvgNodeRenderer {
  @override
  bool canElementFill() => false;

  @override
  CraftRectangle? getObjectBoundingBox(CraftSvgDrawContext context) => null;

  @override
  CraftSvgNodeRenderer createDeepCopy() {
    final copy = CraftGroupSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    deepCopyChildren(copy);
    return copy;
  }
}
