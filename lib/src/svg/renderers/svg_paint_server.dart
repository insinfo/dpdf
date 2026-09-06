import 'package:pdfcraft/src/kernel/colors/color.dart';
import 'package:pdfcraft/src/kernel/geom/rectangle.dart';
import 'package:pdfcraft/src/svg/renderers/no_draw_svg_node_renderer.dart';
import 'package:pdfcraft/src/svg/renderers/svg_draw_context.dart';

/// Interface for working with paint servers.
abstract class CraftSvgPaintServer implements CraftNoDrawSvgNodeRenderer {
  /// Creates the Color that represents the corresponding paint server for specified object box.
  CraftColor? createColor(
      CraftSvgDrawContext context,
      CraftRectangle objectBoundingBox,
      double objectBoundingBoxMargin,
      double parentOpacity);
}
