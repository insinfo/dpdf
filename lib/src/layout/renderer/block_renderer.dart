import 'package:dpdf/src/layout/renderer/abstract_renderer.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/layout/element/element.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/layout/margincollapse/margins_collapse_handler.dart';
import 'package:dpdf/src/layout/margincollapse/margins_collapse_info.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';
import 'package:dpdf/src/layout/properties/layout_position.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/borders/border.dart';
import 'package:dpdf/src/layout/minmaxwidth/min_max_width.dart';

class BlockRenderer extends AbstractRenderer {
  BlockRenderer(Element super.modelElement);

  @override
  MinMaxWidth? getMinMaxWidth() {
    // Box properties
    double additionalWidth = 0;

    // Calculate margins/padding (approximated as we don't know parent width here usually)
    // Usually MinMaxWidth calculation ignores percentage padding/margins or assumes 0.

    // Simplified:

    double minW = 0;
    double maxW = 0;

    for (Renderer child in childRenderers) {
      MinMaxWidth? childMMW = child.getMinMaxWidth();
      if (childMMW != null) {
        if (childMMW.getMinWidth() > minW) minW = childMMW.getMinWidth();
        if (childMMW.getMaxWidth() > maxW) maxW = childMMW.getMaxWidth();
      }
    }
    return MinMaxWidth.full(minW, maxW, additionalWidth);
  }

  /// Rectangle in which an absolutely/fixed positioned box must be laid out,
  /// or null when the box takes part in the normal flow.
  Rectangle? resolveOutOfFlowBox(Rectangle flowBox) {
    final position = getProperty<LayoutPosition>(Property.POSITION);
    if (position != LayoutPosition.FIXED &&
        position != LayoutPosition.ABSOLUTE) {
      return null;
    }
    final double containerWidth = flowBox.getWidth();
    final bool hasLeft = hasProperty(Property.LEFT);
    final bool hasBottom = hasProperty(Property.BOTTOM);
    if (!hasLeft && !hasBottom) return null;

    final double left = hasLeft
        ? getResolvedProperty(Property.LEFT, containerWidth)
        : flowBox.getX();
    final double bottom = hasBottom
        ? getResolvedProperty(Property.BOTTOM, containerWidth)
        : flowBox.getY();
    final double width = hasProperty(Property.WIDTH)
        ? getResolvedProperty(Property.WIDTH, containerWidth)
        : containerWidth;
    double height;
    if (hasProperty(Property.HEIGHT)) {
      height = getResolvedProperty(Property.HEIGHT, flowBox.getHeight());
    } else if (hasProperty(Property.MIN_HEIGHT)) {
      height = getResolvedProperty(Property.MIN_HEIGHT, flowBox.getHeight());
    } else {
      height = flowBox.getY() + flowBox.getHeight() - bottom;
    }
    if (height < 0) height = 0;
    return Rectangle(left, bottom, width, height);
  }

  @override
  LayoutResult? layout(LayoutContext layoutContext) {
    final MarginsCollapseInfo? parentCollapseInfo =
        layoutContext.getMarginsCollapseInfo();
    LayoutArea area = layoutContext.getArea();
    Rectangle parentBox = area.getBBox().clone();

    final Rectangle? outOfFlowBox = resolveOutOfFlowBox(parentBox);
    final bool outOfFlow = outOfFlowBox != null;
    if (outOfFlow) {
      parentBox = outOfFlowBox;
    }
    double parentWidth = parentBox.getWidth();

    final bool collapsingMargins =
        !outOfFlow && MarginsCollapseHandler.marginsCollapsingEnabled(this);
    final MarginsCollapseHandler? collapseHandler = collapsingMargins
        ? MarginsCollapseHandler(this, parentWidth, parentCollapseInfo)
        : null;

    // Box Model Properties
    double mt = getResolvedProperty(Property.MARGIN_TOP, parentWidth);
    double mb = getResolvedProperty(Property.MARGIN_BOTTOM, parentWidth);
    double ml = getResolvedProperty(Property.MARGIN_LEFT, parentWidth);
    double mr = getResolvedProperty(Property.MARGIN_RIGHT, parentWidth);

    if (parentCollapseInfo != null) {
      if (parentCollapseInfo.isIgnoreOwnMarginTop()) mt = 0;
      if (parentCollapseInfo.isIgnoreOwnMarginBottom()) mb = 0;
    }

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
        area.pageOrdinal(),
        Rectangle(parentBox.getX(), parentBox.getY() + parentBox.getHeight(),
            parentWidth, 0));

    // Vertical cursor relative to parentBox top (moving downwards usually, but Y coordinate in PDF is bottom-up)
    // parentBox.getY() + parentBox.getHeight() is the TOP Y.
    // We want to place content downwards.

    // Top offset for first child
    double topOffset =
        (collapseHandler != null ? collapseHandler.startMarginsCollapse() : mt) +
            bt +
            pt;
    double bottomOffset =
        collapseHandler != null ? bb + pb : mb + bb + pb; // added at the end

    double currentHeightUsed = topOffset;
    double curY = parentBox.getY() + parentBox.getHeight() - currentHeightUsed;

    // Available height for content (children)
    // We must ensure we don't exceed parentBox.getHeight()
    // but usually splitting handles that.
    double availableHeight = parentBox.getHeight() - topOffset - bottomOffset;
    bool anyChildOccupiedSpace = false;

    for (int i = 0; i < childRenderers.length; i++) {
      Renderer child = childRenderers[i];

      // X is shifted by ml + bl + pl
      double childX = parentBox.getX() + ml + bl + pl;

      final bool childOutOfFlow =
          child is AbstractRenderer && child.isOutOfFlow();

      if (childOutOfFlow) {
        // Out of flow children are laid out against the whole box and do not
        // advance the vertical cursor (CSS 2.1, 9.5 and 9.6).
        child.layout(LayoutContext(LayoutArea(
            area.pageOrdinal(),
            Rectangle(parentBox.getX(), parentBox.getY(), parentBox.getWidth(),
                parentBox.getHeight()))));
        continue;
      }

      // Tentative amount of space the adjoining margins would occupy before
      // this child. It is only consumed if the child does not collapse through.
      double collapsedSpacing =
          collapseHandler != null ? collapseHandler.beginChild(child) : 0;

      double childAvailableHeight = availableHeight - collapsedSpacing;
      if (childAvailableHeight < 0) childAvailableHeight = 0;

      LayoutArea childArea = LayoutArea(
          area.pageOrdinal(),
          Rectangle(childX, curY - collapsedSpacing - childAvailableHeight,
              contentWidth, childAvailableHeight));

      LayoutResult? result = child.layout(LayoutContext(
          childArea,
          collapseHandler?.createChildInfo(child),
          layoutContext.getFloatRendererAreas(),
          layoutContext.isClippedHeight()));

      if (result == null) continue;

      if (result.getStatus() == LayoutResult.FULL) {
        Rectangle? childOccupied = result.getOccupiedArea()?.getBBox();
        double childHeight = childOccupied?.getHeight() ?? 0;

        if (collapseHandler != null &&
            MarginsCollapseHandler.isSelfCollapsing(child, parentWidth,
                hasContentHeight: childHeight > 0)) {
          // CSS 2.1, 8.3.1: the box collapses through, its bottom margin joins
          // the very same adjoining set and no space is reserved for it.
          collapseHandler.childCollapsedThrough(child);
          continue;
        }

        if (collapsedSpacing != 0) {
          currentHeightUsed += collapsedSpacing;
          availableHeight -= collapsedSpacing;
          curY -= collapsedSpacing;
        }

        if (childOccupied != null) {
          currentHeightUsed += childHeight;
          availableHeight -= childHeight;
          curY -= childHeight;

          if (child is AbstractRenderer) {
            child.occupiedArea = result.getOccupiedArea();
          }
        }
        if (childHeight > 0) anyChildOccupiedSpace = true;
        collapseHandler?.commitChild(child);

        // keep-with-next: the child must stay on the same area as the next
        // in-flow sibling. When the sibling cannot be placed here, move both.
        if (!outOfFlow &&
            i + 1 < childRenderers.length &&
            child.getProperty<bool>(Property.KEEP_WITH_NEXT) == true &&
            !_nextChildFits(childRenderers[i + 1], area, childX, curY,
                contentWidth, availableHeight)) {
          final splitAt = i;
          if (splitAt == 0) {
            return _nothing();
          }
          currentHeightUsed -= childHeight + collapsedSpacing;
          return _partial(area, parentBox, currentHeightUsed, splitAt, null,
              null, splitAt);
        }
      } else if (result.getStatus() == LayoutResult.PARTIAL) {
        if (child is AbstractRenderer) {
          child.occupiedArea = result.getOccupiedArea();
        }
        if (_keepTogether()) {
          return _nothing();
        }
        double childHeight =
            result.getOccupiedArea()?.getBBox().getHeight() ?? 0;
        currentHeightUsed += collapsedSpacing + childHeight;
        return _partial(area, parentBox, currentHeightUsed, i,
            result.getSplitRenderer(), result.getOverflowRenderer(), i + 1);
      } else {
        // NOTHING
        if (result.getAreaBreak() != null) {
          // Propagate the explicit area break upwards.
          if (i == 0) {
            return LayoutResult(LayoutResult.NOTHING, null, null, this,
                    result.getCauseOfNothing())
                .setAreaBreak(result.getAreaBreak()!);
          }
          return _partial(area, parentBox, currentHeightUsed, i, null, null,
                  i + 1)
              .setAreaBreak(result.getAreaBreak()!);
        }
        if (_keepTogether()) {
          return _nothing(result.getCauseOfNothing());
        }
        if (i > 0 && anyChildOccupiedSpace) {
          return _partial(
              area, parentBox, currentHeightUsed, i, null, null, i);
        }
        return _nothing(result.getCauseOfNothing());
      }
    }

    // All children fit fully. The height constraints of CSS apply to the
    // content box, so they are resolved before the box offsets are added back.
    double trailing = bottomOffset;
    if (collapseHandler != null) {
      trailing += collapseHandler.endMarginsCollapse();
    }
    double contentHeight = currentHeightUsed - topOffset;

    final double minHeight = hasProperty(Property.MIN_HEIGHT)
        ? getResolvedProperty(Property.MIN_HEIGHT, parentBox.getHeight())
        : 0;
    if (contentHeight < minHeight) {
      contentHeight = minHeight;
    }
    if (hasProperty(Property.HEIGHT)) {
      contentHeight =
          getResolvedProperty(Property.HEIGHT, parentBox.getHeight());
    }
    final double maxHeight = hasProperty(Property.MAX_HEIGHT)
        ? getResolvedProperty(Property.MAX_HEIGHT, parentBox.getHeight())
        : double.infinity;
    if (contentHeight > maxHeight) {
      contentHeight = maxHeight;
    }
    currentHeightUsed = topOffset + contentHeight + trailing;

    // The box as a whole (typically because of a minimum height) may still be
    // taller than the area it was given: it has to move to the next area.
    if (!outOfFlow &&
        currentHeightUsed > parentBox.getHeight() + 1e-6 &&
        getProperty<bool>(Property.FORCED_PLACEMENT) != true) {
      return _nothing();
    }

    occupiedArea!.getBBox().setHeight(currentHeightUsed);
    occupiedArea!
        .getBBox()
        .setY(parentBox.getY() + parentBox.getHeight() - currentHeightUsed);

    if (parentCollapseInfo != null && collapseHandler != null) {
      parentCollapseInfo.collapseBefore = collapseHandler.getCollapseBefore();
      parentCollapseInfo.isSelfCollapsing = MarginsCollapseHandler
          .isSelfCollapsing(this, parentWidth,
              hasContentHeight: anyChildOccupiedSpace);
    }

    if (outOfFlow) {
      // Reported area stays where it was requested, but the parent must not
      // reserve any space for it.
      return LayoutResult(LayoutResult.FULL, occupiedArea, null, null);
    }

    return LayoutResult(LayoutResult.FULL, occupiedArea, null, null);
  }

  bool _keepTogether() =>
      getProperty<bool>(Property.KEEP_TOGETHER) == true &&
      getProperty<bool>(Property.FORCED_PLACEMENT) != true;

  /// Probes whether [next] can be laid out entirely in the space left on the
  /// current area. The probe reuses the renderer itself; the renderer is laid
  /// out again by the regular loop afterwards, so no state is lost.
  bool _nextChildFits(Renderer next, LayoutArea area, double childX,
      double curY, double contentWidth, double availableHeight) {
    if (availableHeight <= 0) return false;
    final LayoutArea? previousArea = next.getOccupiedArea();
    final probeResult = next.layout(LayoutContext(LayoutArea(
        area.pageOrdinal(),
        Rectangle(
            childX, curY - availableHeight, contentWidth, availableHeight))));
    if (next is AbstractRenderer) {
      next.occupiedArea = previousArea;
    }
    return probeResult != null && probeResult.getStatus() == LayoutResult.FULL;
  }

  LayoutResult _nothing([Renderer? causeOfNothing]) {
    BlockRenderer overflowRenderer = createOverflowRenderer(LayoutResult.NOTHING)
        as BlockRenderer;
    overflowRenderer.childRenderers.addAll(childRenderers);
    return LayoutResult(LayoutResult.NOTHING, null, null, overflowRenderer,
        causeOfNothing ?? this);
  }

  LayoutResult _partial(
      LayoutArea area,
      Rectangle parentBox,
      double heightUsed,
      int splitChildCount,
      Renderer? splitOfChild,
      Renderer? overflowOfChild,
      int overflowStartIndex) {
    BlockRenderer splitRenderer =
        createSplitRenderer(LayoutResult.PARTIAL) as BlockRenderer;
    splitRenderer.childRenderers
        .addAll(childRenderers.sublist(0, splitChildCount));
    if (splitOfChild != null) {
      splitRenderer.childRenderers.add(splitOfChild);
    }

    BlockRenderer overflowRenderer =
        createOverflowRenderer(LayoutResult.PARTIAL) as BlockRenderer;
    if (overflowOfChild != null) {
      overflowRenderer.childRenderers.add(overflowOfChild);
    }
    if (overflowStartIndex < childRenderers.length) {
      overflowRenderer.childRenderers
          .addAll(childRenderers.sublist(overflowStartIndex));
    }

    occupiedArea!.getBBox().setHeight(heightUsed);
    occupiedArea!
        .getBBox()
        .setY(parentBox.getY() + parentBox.getHeight() - heightUsed);
    splitRenderer.occupiedArea = occupiedArea;

    return LayoutResult(
        LayoutResult.PARTIAL, occupiedArea, splitRenderer, overflowRenderer);
  }

  @override
  Renderer getNextRenderer() {
    return BlockRenderer(modelElement as Element);
  }

  @override
  Future<void> draw(DrawContext drawContext) async {
    // Draw background/borders here if needed
    await super.draw(drawContext);
  }
}
