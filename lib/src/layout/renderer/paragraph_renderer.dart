import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/renderer/block_renderer.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/layout/element/paragraph.dart';
import 'package:dpdf/src/layout/renderer/line_renderer.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/layout/properties/property.dart';

class ParagraphRenderer extends BlockRenderer {
  List<Renderer>? _originalChildren;

  ParagraphRenderer(Paragraph super.modelElement);

  @override
  LayoutResult? layout(LayoutContext layoutContext) {
    LayoutArea area = layoutContext.getArea();
    Rectangle parentBox = area.getBBox().clone();
    double parentWidth = parentBox.getWidth();
    final collapseInfo = layoutContext.getMarginsCollapseInfo();

    // Box Model Properties
    double mt = getResolvedProperty(Property.MARGIN_TOP, parentWidth);
    double mb = getResolvedProperty(Property.MARGIN_BOTTOM, parentWidth);
    if (collapseInfo != null) {
      if (collapseInfo.isIgnoreOwnMarginTop()) mt = 0;
      if (collapseInfo.isIgnoreOwnMarginBottom()) mb = 0;
    }
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
    List<Renderer> sourceChildren;
    if (_originalChildren == null) {
      _originalChildren = List.from(childRenderers);
      sourceChildren = _originalChildren!;
    } else {
      sourceChildren = _originalChildren!;
    }

    List<Renderer> queue = List.from(sourceChildren);

    // If queue is empty (empty paragraph), handle gracefully
    // ...

    while (queue.isNotEmpty) {
      Renderer child = queue.removeAt(0);

      double availableWidth = contentWidth - currentLineWidth;

      // Temporary layout area for the child to test fit
      // We give it infinite height so it splits only on width
      LayoutArea childArea = LayoutArea(
          area.pageOrdinal(), Rectangle(0, 0, availableWidth, 10000));

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

    childRenderers.clear();
    childRenderers.addAll(lines);

    double currentHeightUsed = mt + pt; // Top offsets
    // Note: BlockRenderer adds top/bottom margins/padding.
    // layout() here should return the total occupied area including children lines.

    // We rely on BlockRenderer logic to stack them?
    // No, we are IN layout(), overriding BlockRenderer methods.
    // We should call layout() on each LineRenderer to set their positions.

    double curY = parentBox.getY() + parentBox.getHeight() - currentHeightUsed;
    final double heightLimit = parentBox.getHeight() - mb - pb;
    final bool forced = getProperty<bool>(Property.FORCED_PLACEMENT) == true;
    final List<LineRenderer> placedLines = [];
    int firstOverflowLine = lines.length;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      // Essential: Set parent so LineRenderer (and its children) inherits properties from ParagraphRenderer
      line.setParent(this);

      // Line layout needs actual width contentWidth
      LayoutArea lineArea = LayoutArea(
          area.pageOrdinal(),
          Rectangle(
              parentBox.getX() + ml + pl, curY - 10000, contentWidth, 10000));
      // LineRenderer layout stacks children horizontally.
      LayoutResult? lineRes = line.layout(LayoutContext(lineArea));

      if (lineRes != null && lineRes.getOccupiedArea() != null) {
        double h = lineRes.getOccupiedArea()!.getBBox().getHeight();
        if (!forced && currentHeightUsed + h > heightLimit) {
          firstOverflowLine = i;
          break;
        }
        currentHeightUsed += h;
        curY -= h;
        line.occupiedArea = lineRes.getOccupiedArea();
        placedLines.add(line);
      }
    }

    if (firstOverflowLine < lines.length && placedLines.isNotEmpty) {
      // The paragraph does not fit: keep the lines laid out so far and hand the
      // remaining ones to an overflow renderer.
      childRenderers
        ..clear()
        ..addAll(placedLines);
      currentHeightUsed += pb;
      occupiedArea = LayoutArea(
          area.pageOrdinal(),
          Rectangle(
              parentBox.getX(),
              parentBox.getY() + parentBox.getHeight() - currentHeightUsed,
              parentWidth,
              currentHeightUsed));

      final splitRenderer =
          createSplitRenderer(LayoutResult.PARTIAL) as ParagraphRenderer;
      splitRenderer.childRenderers.addAll(placedLines);
      splitRenderer._originalChildren = List.from(placedLines);
      splitRenderer.occupiedArea = occupiedArea;

      final overflowRenderer =
          createOverflowRenderer(LayoutResult.PARTIAL) as ParagraphRenderer;
      final remaining = <Renderer>[];
      for (int i = firstOverflowLine; i < lines.length; i++) {
        remaining.addAll(lines[i].getChildRenderers());
      }
      overflowRenderer._originalChildren = remaining;
      overflowRenderer.childRenderers.addAll(remaining);
      overflowRenderer.setProperty(Property.MARGIN_TOP, null);

      return LayoutResult(
          LayoutResult.PARTIAL, occupiedArea, splitRenderer, overflowRenderer);
    }

    if (placedLines.isEmpty && lines.isNotEmpty && !forced) {
      final overflowRenderer =
          createOverflowRenderer(LayoutResult.NOTHING) as ParagraphRenderer;
      overflowRenderer._originalChildren = List.from(sourceChildren);
      overflowRenderer.childRenderers.addAll(sourceChildren);
      return LayoutResult(
          LayoutResult.NOTHING, null, null, overflowRenderer, this);
    }

    currentHeightUsed += mb + pb;

    occupiedArea = LayoutArea(
        area.pageOrdinal(),
        Rectangle(
            parentBox.getX(),
            parentBox.getY() + parentBox.getHeight() - currentHeightUsed,
            parentWidth,
            currentHeightUsed));

    return LayoutResult(LayoutResult.FULL, occupiedArea, null, null);
  }

  @override
  Renderer getNextRenderer() {
    return ParagraphRenderer(modelElement as Paragraph);
  }
}
