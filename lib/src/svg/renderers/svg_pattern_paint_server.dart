import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/no_draw_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';

abstract interface class SvgPatternPaintServer
    implements NoDrawSvgNodeRenderer {
  Future<bool> applyPattern(SvgDrawContext context, Rectangle bounds,
      {bool stroke = false});
}
