import 'package:dpdf/src/layout/renderer/abstract_renderer.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';

/// Places list markers and inline children in a single horizontal row.
/// Bidirectional shaping, floating elements and tab stops are not handled here.
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
          LayoutArea(layoutContext.getArea().pageOrdinal(), childBBox)));
      if (res != null && res.getOccupiedArea() != null) {
        if (child is AbstractRenderer) {
          child.occupiedArea = res.getOccupiedArea();
        }
        var occupied = res.getOccupiedArea()!.getBBox();
        totalWidth += occupied.getWidth();
        curX += occupied.getWidth();
        if (occupied.getHeight() > maxY) {
          maxY = occupied.getHeight();
        }
      }
    }

    occupiedArea = LayoutArea(
        layoutContext.getArea().pageOrdinal(),
        Rectangle(
            layoutContext.getArea().getBBox().getLeft(),
            layoutContext.getArea().getBBox().getTop() - maxY,
            totalWidth,
            maxY));

    return LayoutResult(LayoutResult.FULL, occupiedArea, null, null, this);
  }

  @override
  Renderer getNextRenderer() {
    return LineRenderer();
  }

  double getYLine() {
    return occupiedArea?.getBBox().getBottom() ?? 0;
  }
}
