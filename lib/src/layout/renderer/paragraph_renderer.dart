import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/renderer/block_renderer.dart';
import 'package:dpdf/src/layout/renderer/i_renderer.dart';
import 'package:dpdf/src/layout/element/paragraph.dart';
import 'package:dpdf/src/layout/renderer/line_renderer.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/layout/properties/property.dart';

class ParagraphRenderer extends BlockRenderer {
  List<IRenderer>? _originalChildren;

  ParagraphRenderer(Paragraph modelElement) : super(modelElement);

  @override
  LayoutResult? layout(LayoutContext layoutContext) {
    LayoutArea area = layoutContext.getArea();
    Rectangle parentBox = area.getBBox().clone();
    double parentWidth = parentBox.getWidth();

    // Box Model Properties
    double mt = getResolvedProperty(Property.MARGIN_TOP, parentWidth);
    double mb = getResolvedProperty(Property.MARGIN_BOTTOM, parentWidth);
    double ml = getResolvedProperty(Property.MARGIN_LEFT, parentWidth);
    double mr = getResolvedProperty(Property.MARGIN_RIGHT, parentWidth);

    double pt = getResolvedProperty(Property.PADDING_TOP, parentWidth);
    double pb = getResolvedProperty(Property.PADDING_BOTTOM, parentWidth);
    double pl = getResolvedProperty(Property.PADDING_LEFT, parentWidth);
    double pr = getResolvedProperty(Property.PADDING_RIGHT, parentWidth);

    double contentWidth = parentWidth - ml - mr - pl - pr;
    if (contentWidth < 0) contentWidth = 0;

    List<LineRenderer> lines = [];
    LineRenderer currentLine = LineRenderer();
    double currentLineWidth = 0;

    // Ensure we work on original children (TextRenderers) and not previously calculated Lines
    // We need to store the original children (TextRenderers) because `this.childRenderers`
    // is later overwritten with LineRenderers.
    List<IRenderer> sourceChildren;
    if (_originalChildren == null) {
      _originalChildren = List.from(childRenderers);
      sourceChildren = _originalChildren!;
    } else {
      sourceChildren = _originalChildren!;
    }

    List<IRenderer> queue = List.from(sourceChildren);

    // If queue is empty (empty paragraph), handle gracefully
    // ...

    while (queue.isNotEmpty) {
      IRenderer child = queue.removeAt(0);

      double availableWidth = contentWidth - currentLineWidth;

      // Temporary layout area for the child to test fit
      // We give it infinite height so it splits only on width
      LayoutArea childArea = LayoutArea(
          area.getPageNumber(), Rectangle(0, 0, availableWidth, 10000));

      LayoutResult? res = child.layout(LayoutContext(childArea));

      if (res != null) {
        if (res.getStatus() == LayoutResult.FULL) {
          currentLine.addChild(child);
          // Use occupied width if available, or estimated
          double w = res.getOccupiedArea()?.getBBox().getWidth() ?? 0;
          currentLineWidth += w;
        } else if (res.getStatus() == LayoutResult.PARTIAL) {
          if (res.getSplitRenderer() != null) {
            currentLine.addChild(res.getSplitRenderer()!);
            double w = res.getOccupiedArea()?.getBBox().getWidth() ?? 0;
            currentLineWidth += w;
          }

          lines.add(currentLine);
          currentLine = LineRenderer();
          currentLineWidth = 0;

          if (res.getOverflowRenderer() != null) {
            queue.insert(0, res.getOverflowRenderer()!);
          }
        } else if (res.getStatus() == LayoutResult.NOTHING) {
          if (currentLineWidth > 0) {
            // Move to next line
            lines.add(currentLine);
            currentLine = LineRenderer();
            currentLineWidth = 0;
            queue.insert(0, child);
          } else {
            // Force fit one chunk if it's too big for empty line?
            // Or just add it and let it overflow.
            currentLine.addChild(child);
            lines.add(currentLine);
            currentLine = LineRenderer();
            currentLineWidth = 0;
          }
        }
      }
    }

    if (currentLine.childRenderers.isNotEmpty) {
      lines.add(currentLine);
    }

    // Now layout the lines vertically
    // Basically behaving like BlockRenderer but with lines

    this.childRenderers.clear();
    this.childRenderers.addAll(lines);

    double currentHeightUsed = mt + pt; // Top offsets
    // Note: BlockRenderer adds top/bottom margins/padding.
    // layout() here should return the total occupied area including children lines.

    // We rely on BlockRenderer logic to stack them?
    // No, we are IN layout(), overriding BlockRenderer methods.
    // We should call layout() on each LineRenderer to set their positions.

    double curY = parentBox.getY() + parentBox.getHeight() - currentHeightUsed;

    for (var line in lines) {
      // Essential: Set parent so LineRenderer (and its children) inherits properties from ParagraphRenderer
      line.setParent(this);

      // Line layout needs actual width contentWidth
      LayoutArea lineArea = LayoutArea(
          area.getPageNumber(),
          Rectangle(
              parentBox.getX() + ml + pl, curY - 10000, contentWidth, 10000));
      // LineRenderer layout stacks children horizontally.
      LayoutResult? lineRes = line.layout(LayoutContext(lineArea));

      if (lineRes != null && lineRes.getOccupiedArea() != null) {
        double h = lineRes.getOccupiedArea()!.getBBox().getHeight();
        currentHeightUsed += h;
        curY -= h;
        line.occupiedArea = lineRes.getOccupiedArea();
      }
    }

    currentHeightUsed += mb + pb;

    occupiedArea = LayoutArea(
        area.getPageNumber(),
        Rectangle(
            parentBox.getX(),
            parentBox.getY() + parentBox.getHeight() - currentHeightUsed,
            parentWidth,
            currentHeightUsed));

    return LayoutResult(LayoutResult.FULL, occupiedArea, null, null);
  }
}
