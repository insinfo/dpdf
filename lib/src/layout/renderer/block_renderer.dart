import 'package:dpdf/src/layout/renderer/abstract_renderer.dart';
import 'package:dpdf/src/layout/renderer/i_renderer.dart';
import 'package:dpdf/src/layout/element/i_element.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/borders/border.dart';
import 'package:dpdf/src/layout/minmaxwidth/min_max_width.dart';

class BlockRenderer extends AbstractRenderer {
  BlockRenderer(IElement modelElement) : super(modelElement);

  @override
  MinMaxWidth? getMinMaxWidth() {
    // Box properties
    double additionalWidth = 0;

    // Calculate margins/padding (approximated as we don't know parent width here usually)
    // Usually MinMaxWidth calculation ignores percentage padding/margins or assumes 0.

    // Simplified:

    double minW = 0;
    double maxW = 0;

    for (IRenderer child in childRenderers) {
      MinMaxWidth? childMMW = child.getMinMaxWidth();
      if (childMMW != null) {
        if (childMMW.getMinWidth() > minW) minW = childMMW.getMinWidth();
        if (childMMW.getMaxWidth() > maxW) maxW = childMMW.getMaxWidth();
      }
    }
    return MinMaxWidth.full(minW, maxW, additionalWidth);
  }

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

    // Borders
    Border? btBorder = getProperty(Property.BORDER_TOP);
    Border? bbBorder = getProperty(Property.BORDER_BOTTOM);
    Border? blBorder = getProperty(Property.BORDER_LEFT);
    Border? brBorder = getProperty(Property.BORDER_RIGHT);

    double bt = btBorder?.width ?? 0;
    double bb = bbBorder?.width ?? 0;
    double bl = blBorder?.width ?? 0;
    double br = brBorder?.width ?? 0;

    // Content Box Width
    double contentWidth = parentWidth - ml - mr - bl - br - pl - pr;
    if (contentWidth < 0) contentWidth = 0;

    // Initialize occupied area
    // The occupied area usually includes margins.
    // We start assuming we take 0 height.
    occupiedArea = LayoutArea(
        area.getPageNumber(),
        Rectangle(parentBox.getX(), parentBox.getY() + parentBox.getHeight(),
            parentWidth, 0));

    // Vertical cursor relative to parentBox top (moving downwards usually, but Y coordinate in PDF is bottom-up)
    // parentBox.getY() + parentBox.getHeight() is the TOP Y.
    // We want to place content downwards.

    // Top offset for first child
    double topOffset = mt + bt + pt;
    double bottomOffset = mb + bb + pb; // To be added at end

    double currentHeightUsed = topOffset;
    double curY = parentBox.getY() + parentBox.getHeight() - currentHeightUsed;

    // Available height for content (children)
    // We must ensure we don't exceed parentBox.getHeight()
    // but usually splitting handles that.
    double availableHeight = parentBox.getHeight() - topOffset - bottomOffset;

    for (int i = 0; i < childRenderers.length; i++) {
      IRenderer child = childRenderers[i];

      // Child available area
      // X is shifted by ml + bl + pl
      double childX = parentBox.getX() + ml + bl + pl;

      // We give child full remaining height? Or constrained?
      // Usually full remaining on page.
      double childAvailableHeight = availableHeight;
      if (childAvailableHeight < 0) childAvailableHeight = 0;

      LayoutArea childArea = LayoutArea(
          area.getPageNumber(),
          Rectangle(childX, curY - childAvailableHeight, contentWidth,
              childAvailableHeight));

      LayoutResult? result = child.layout(LayoutContext(childArea));

      if (result != null) {
        if (result.getStatus() == LayoutResult.FULL) {
          Rectangle? childOccupied = result.getOccupiedArea()?.getBBox();
          if (childOccupied != null) {
            double childHeight = childOccupied.getHeight();

            currentHeightUsed += childHeight;
            availableHeight -= childHeight;
            curY -= childHeight;

            if (child is AbstractRenderer) {
              child.occupiedArea = result.getOccupiedArea();
            }
          }
        } else if (result.getStatus() == LayoutResult.PARTIAL) {
          // Handle split
          if (child is AbstractRenderer) {
            child.occupiedArea = result.getOccupiedArea();
          }

          // Create split renderer for 'this'
          BlockRenderer splitRenderer = BlockRenderer(modelElement!);
          // Split renderer needs to know it's a split.
          // We should probably copy properties, etc. (AbstractRenderer does not strictly enforce copy, but logic should)
          // For now simpler logic.

          splitRenderer.childRenderers.addAll(childRenderers.sublist(0, i));
          if (result.getSplitRenderer() != null) {
            splitRenderer.childRenderers.add(result.getSplitRenderer()!);
          }

          // Overflow
          BlockRenderer overflowRenderer = BlockRenderer(modelElement!);
          if (result.getOverflowRenderer() != null) {
            overflowRenderer.childRenderers.add(result.getOverflowRenderer()!);
          }
          overflowRenderer.childRenderers.addAll(childRenderers.sublist(i + 1));

          // Update occupied area for THIS renderer (partial fit)
          // Include bottom padding/border for split? Usually split omits bottom borders/margins if split.
          // But iText logic is complex here.
          // Simplified: add bottom offset if we are complying loosely.
          // But for PARTIAL, we might NOT add bottom margin/border on the first part.
          // Let's assume we do NOT add bottom offset for the first part of split.

          occupiedArea!.getBBox().setHeight(
              currentHeightUsed); // Height used so far (top offset + children)
          occupiedArea!.getBBox().setY(
              parentBox.getY() + parentBox.getHeight() - currentHeightUsed);

          splitRenderer.occupiedArea = occupiedArea;

          return LayoutResult(LayoutResult.PARTIAL, occupiedArea, splitRenderer,
              overflowRenderer);
        } else {
          // NOTHING logic
          // If first child returns NOTHING, we might be unable to fit anything.
          // Return NOTHING for this block too, unless we have content before it (which we do if i > 0)

          if (i > 0) {
            // Return PARTIAL with what we have
            BlockRenderer splitRenderer = BlockRenderer(modelElement!);
            splitRenderer.childRenderers.addAll(childRenderers.sublist(0, i));

            BlockRenderer overflowRenderer = BlockRenderer(modelElement!);
            overflowRenderer.childRenderers.addAll(childRenderers.sublist(i));

            occupiedArea!.getBBox().setHeight(currentHeightUsed);
            occupiedArea!.getBBox().setY(
                parentBox.getY() + parentBox.getHeight() - currentHeightUsed);
            splitRenderer.occupiedArea = occupiedArea;

            return LayoutResult(LayoutResult.PARTIAL, occupiedArea,
                splitRenderer, overflowRenderer);
          } else {
            // Nothing fits at all
            BlockRenderer overflowRenderer = BlockRenderer(modelElement!);
            overflowRenderer.childRenderers.addAll(childRenderers);
            return LayoutResult(
                LayoutResult.NOTHING, null, null, overflowRenderer);
          }
        }
      }
    }

    // All children fit fully
    currentHeightUsed += bottomOffset;
    occupiedArea!.getBBox().setHeight(currentHeightUsed);
    occupiedArea!
        .getBBox()
        .setY(parentBox.getY() + parentBox.getHeight() - currentHeightUsed);

    return LayoutResult(LayoutResult.FULL, occupiedArea, null, null);
  }

  @override
  Future<void> draw(DrawContext drawContext) async {
    // Draw background/borders here if needed
    await super.draw(drawContext);
  }
}
