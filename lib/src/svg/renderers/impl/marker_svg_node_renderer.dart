import 'package:pdfcraft/src/kernel/geom/rectangle.dart';
import 'package:pdfcraft/src/svg/renderers/svg_node_renderer.dart';
import 'package:pdfcraft/src/svg/renderers/svg_draw_context.dart';
import 'package:pdfcraft/src/svg/renderers/impl/abstract_container_svg_node_renderer.dart';

class CraftMarkerSvgNodeRenderer extends CraftAbstractContainerSvgNodeRenderer {
  @override
  Future<void> doDraw(CraftSvgDrawContext context) async {}

  @override
  CraftRectangle? getObjectBoundingBox(CraftSvgDrawContext context) => null;

  @override
  CraftSvgNodeRenderer createDeepCopy() {
    throw UnimplementedError();
  }
}
