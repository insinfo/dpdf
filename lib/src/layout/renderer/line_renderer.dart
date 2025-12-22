import 'package:dpdf/src/layout/renderer/abstract_renderer.dart';
import 'package:dpdf/src/layout/renderer/i_renderer.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';

/// A simplified LineRenderer to support List symbols and basic inline horizontal layout.
/// // TODO: Full port of LineRenderer from iText (Bidi, floats, tabs, etc.)
class LineRenderer extends AbstractRenderer {
  LineRenderer() : super(null);

  @override
  LayoutResult? layout(LayoutContext layoutContext) {
    double curX = layoutContext.getArea().getBBox().getLeft();
    double maxY = 0;
    double totalWidth = 0;

    for (var child in childRenderers) {
      child.setParent(this);

      // Relative positioning for children within the line
      Rectangle childBBox = Rectangle(
          curX,
          layoutContext.getArea().getBBox().getBottom(),
          layoutContext.getArea().getBBox().getWidth() - totalWidth,
          layoutContext.getArea().getBBox().getHeight());

      var res = child.layout(LayoutContext(
          LayoutArea(layoutContext.getArea().getPageNumber(), childBBox)));
      if (res != null && res.getOccupiedArea() != null) {
        var occupied = res.getOccupiedArea()!.getBBox();
        totalWidth += occupied.getWidth();
        curX += occupied.getWidth();
        if (occupied.getHeight() > maxY) {
          maxY = occupied.getHeight();
        }
      }
    }

    occupiedArea = LayoutArea(
        layoutContext.getArea().getPageNumber(),
        Rectangle(
            layoutContext.getArea().getBBox().getLeft(),
            layoutContext.getArea().getBBox().getTop() - maxY,
            totalWidth,
            maxY));

    return LayoutResult(LayoutResult.FULL, occupiedArea, null, null, this);
  }

  @override
  IRenderer getNextRenderer() {
    return LineRenderer();
  }

  double getYLine() {
    return occupiedArea?.getBBox().getBottom() ?? 0;
  }
}
