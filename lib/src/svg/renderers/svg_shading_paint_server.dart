import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/no_draw_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';

abstract interface class SvgShadingPaintServer
    implements NoDrawSvgNodeRenderer {
  Future<void> paintShading(SvgDrawContext context, Rectangle bounds);

  Future<bool> applyStrokeShading(SvgDrawContext context, Rectangle bounds);
}
