import 'package:dpdf/src/kernel/colors/color.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/i_no_draw_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';

/// Interface for working with paint servers.
abstract class ISvgPaintServer implements INoDrawSvgNodeRenderer {
  /// Creates the Color that represents the corresponding paint server for specified object box.
  Color? createColor(SvgDrawContext context, Rectangle objectBoundingBox,
      double objectBoundingBoxMargin, double parentOpacity);
}
