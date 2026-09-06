import 'package:pdfcraft/src/layout/layout/layout_area.dart';
import 'package:pdfcraft/src/layout/layout/layout_context.dart';
import 'package:pdfcraft/src/layout/layout/layout_result.dart';
import 'package:pdfcraft/src/layout/renderer/block_renderer.dart';
import 'package:pdfcraft/src/layout/renderer/renderer.dart';
import 'package:pdfcraft/src/layout/element/paragraph.dart';
import 'package:pdfcraft/src/layout/renderer/line_renderer.dart';
import 'package:pdfcraft/src/kernel/geom/rectangle.dart';
import 'package:pdfcraft/src/layout/properties/property.dart';

class CraftParagraphRenderer extends CraftBlockRenderer {
  List<CraftRenderer>? _originalChildren;

  CraftParagraphRenderer(CraftParagraph modelElement) : super(modelElement);

  @override
  CraftLayoutResult? layout(CraftLayoutContext layoutContext) {
    CraftLayoutArea area = layoutContext.getArea();
    CraftRectangle parentBox = area.getBBox().clone();
    double parentWidth = parentBox.getWidth();

    // Box Model Properties
    double mt = getResolvedProperty(CraftProperty.MARGIN_TOP, parentWidth);
    double mb = getResolvedProperty(CraftProperty.MARGIN_BOTTOM, parentWidth);
    double ml = getResolvedProperty(CraftProperty.MARGIN_LEFT, parentWidth);
    double mr = getResolvedProperty(CraftProperty.MARGIN_RIGHT, parentWidth);

    double pt = getResolvedProperty(CraftProperty.PADDING_TOP, parentWidth);
    double pb = getResolvedProperty(CraftProperty.PADDING_BOTTOM, parentWidth);
    double pl = getResolvedProperty(CraftProperty.PADDING_LEFT, parentWidth);
    double pr = getResolvedProperty(CraftProperty.PADDING_RIGHT, parentWidth);

    double contentWidth = parentWidth - ml - mr - pl - pr;
    if (contentWidth < 0) contentWidth = 0;

    List<CraftLineRenderer> lines = [];
    CraftLineRenderer currentLine = CraftLineRenderer();
    double currentLineWidth = 0;

    // Ensure we work on original children (TextRenderers) and not previously calculated Lines
    // We need to store the original children (TextRenderers) because `this.childRenderers`
    // is later overwritten with LineRenderers.
    List<CraftRenderer> sourceChildren;
    if (_originalChildren == null) {
      _originalChildren = List.from(childRenderers);
      sourceChildren = _originalChildren!;
    } else {
      sourceChildren = _originalChildren!;
    }

    List<CraftRenderer> queue = List.from(sourceChildren);

    // If queue is empty (empty paragraph), handle gracefully
    // ...

    while (queue.isNotEmpty) {
      CraftRenderer child = queue.removeAt(0);

      double availableWidth = contentWidth - currentLineWidth;

      // Temporary layout area for the child to test fit
      // We give it infinite height so it splits only on width
      CraftLayoutArea childArea = CraftLayoutArea(
          area.pageOrdinal(), CraftRectangle(0, 0, availableWidth, 10000));

      CraftLayoutResult? res = child.layout(CraftLayoutContext(childArea));

      if (res != null) {
        if (res.getStatus() == CraftLayoutResult.FULL) {
          currentLine.addChild(child);
          // Use occupied width if available, or estimated
          double w = res.getOccupiedArea()?.getBBox().getWidth() ?? 0;
          currentLineWidth += w;
        } else if (res.getStatus() == CraftLayoutResult.PARTIAL) {
          if (res.getSplitRenderer() != null) {
            currentLine.addChild(res.getSplitRenderer()!);
            double w = res.getOccupiedArea()?.getBBox().getWidth() ?? 0;
            currentLineWidth += w;
          }

          lines.add(currentLine);
          currentLine = CraftLineRenderer();
          currentLineWidth = 0;

          if (res.getOverflowRenderer() != null) {
            queue.insert(0, res.getOverflowRenderer()!);
          }
        } else if (res.getStatus() == CraftLayoutResult.NOTHING) {
          if (currentLineWidth > 0) {
            // Move to next line
            lines.add(currentLine);
            currentLine = CraftLineRenderer();
            currentLineWidth = 0;
            queue.insert(0, child);
          } else {
            // Force fit one chunk if it's too big for empty line?
            // Or just add it and let it overflow.
            currentLine.addChild(child);
            lines.add(currentLine);
            currentLine = CraftLineRenderer();
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
      CraftLayoutArea lineArea = CraftLayoutArea(
          area.pageOrdinal(),
          CraftRectangle(
              parentBox.getX() + ml + pl, curY - 10000, contentWidth, 10000));
      // LineRenderer layout stacks children horizontally.
      CraftLayoutResult? lineRes = line.layout(CraftLayoutContext(lineArea));

      if (lineRes != null && lineRes.getOccupiedArea() != null) {
        double h = lineRes.getOccupiedArea()!.getBBox().getHeight();
        currentHeightUsed += h;
        curY -= h;
        line.occupiedArea = lineRes.getOccupiedArea();
      }
    }

    currentHeightUsed += mb + pb;

    occupiedArea = CraftLayoutArea(
        area.pageOrdinal(),
        CraftRectangle(
            parentBox.getX(),
            parentBox.getY() + parentBox.getHeight() - currentHeightUsed,
            parentWidth,
            currentHeightUsed));

    return CraftLayoutResult(CraftLayoutResult.FULL, occupiedArea, null, null);
  }
}
