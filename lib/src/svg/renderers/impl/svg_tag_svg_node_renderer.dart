import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_container_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';

/// Renderizador do elemento `<svg>`, inclusive quando aninhado.
class CraftSvgTagSvgNodeRenderer extends CraftAbstractContainerSvgNodeRenderer {
  @override
  CraftRectangle? getObjectBoundingBox(CraftSvgDrawContext context) => null;

  @override
  CraftSvgNodeRenderer createDeepCopy() {
    final copy = CraftSvgTagSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    deepCopyChildren(copy);
    return copy;
  }
}
