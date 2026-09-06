import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/i_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_container_svg_node_renderer.dart';

class ClipPathSvgNodeRenderer extends AbstractContainerSvgNodeRenderer {
  @override
  Future<void> doDraw(SvgDrawContext context) async {}

  void setClippedRenderer(dynamic renderer) {}

  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context) => null;

  @override
  ISvgNodeRenderer createDeepCopy() {
    throw UnimplementedError();
  }
}
