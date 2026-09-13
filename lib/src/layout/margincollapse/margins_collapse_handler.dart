import 'package:dpdf/src/layout/borders/border.dart';
import 'package:dpdf/src/layout/margincollapse/margins_collapse_info.dart';
import 'package:dpdf/src/layout/properties/float_property_value.dart';
import 'package:dpdf/src/layout/properties/layout_position.dart';
import 'package:dpdf/src/layout/properties/overflow_property_value.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';

/// Drives margin collapsing for a block container, following CSS 2.1, 8.3.1.
///
/// The handler is owned by the block renderer that lays out the children. It
/// keeps the set of margins that is currently adjoining and reports, for every
/// child, how much vertical space must actually be inserted before it.
///
/// Usage per child: [beginChild] before laying the child out, then either
/// [childCollapsedThrough] (the child is self-collapsing, so its bottom margin
/// stays in the same adjoining set) or [commitChild] (the child produced a
/// border box, closing the adjoining set).
class MarginsCollapseHandler {
  final Renderer renderer;
  final double containingBlockWidth;

  /// Info received from the parent renderer, if the parent collapses too.
  final MarginsCollapseInfo? parentInfo;

  /// Margins adjoining the top edge of this block.
  final MarginsCollapse _collapseBefore = MarginsCollapse();

  /// Adjoining set currently open.
  MarginsCollapse _pending = MarginsCollapse();

  /// Amount of the current adjoining set that was already turned into space.
  double _applied = 0;

  bool _anyInFlowContent = false;

  MarginsCollapseHandler(this.renderer, this.containingBlockWidth,
      [this.parentInfo]);

  // ---------------------------------------------------------------- helpers

  /// Margin collapsing is opt-in: it is turned on by
  /// [Property.COLLAPSING_MARGINS], an inherited property, so setting it on a
  /// document or canvas enables it for the whole tree below.
  static bool marginsCollapsingEnabled(Renderer renderer) {
    return renderer.getProperty<bool>(Property.COLLAPSING_MARGINS) == true;
  }

  static double resolveLength(
      Renderer renderer, int property, double containingBlockWidth) {
    final value = renderer.getProperty<Object>(property);
    if (value is num) return value.toDouble();
    if (value is UnitValue) {
      if (value.isPointValue()) return value.getValue();
      if (value.isPercentValue()) {
        return value.getValue() * containingBlockWidth / 100.0;
      }
    }
    return 0;
  }

  static double borderWidth(Renderer renderer, int property) {
    final border = renderer.getProperty<Border>(property);
    return border?.width ?? 0;
  }

  /// CSS 2.1, 8.3.1: margins of floating and absolutely positioned boxes never
  /// collapse with the margins of their in-flow neighbours.
  static bool isOutOfFlow(Renderer renderer) {
    final float = renderer.getProperty<FloatPropertyValue>(Property.FLOAT);
    if (float != null && float != FloatPropertyValue.none) return true;
    final position = renderer.getProperty<LayoutPosition>(Property.POSITION);
    return position == LayoutPosition.ABSOLUTE ||
        position == LayoutPosition.FIXED;
  }

  /// CSS 2.1, 8.3.1: margins of a box that establishes a new block formatting
  /// context do not collapse with the margins of its in-flow children.
  static bool establishesNewBlockFormattingContext(Renderer renderer) {
    if (isOutOfFlow(renderer)) return true;
    final overflowX =
        renderer.getProperty<OverflowPropertyValue>(Property.OVERFLOW_X);
    final overflowY =
        renderer.getProperty<OverflowPropertyValue>(Property.OVERFLOW_Y);
    return overflowX == OverflowPropertyValue.hidden ||
        overflowY == OverflowPropertyValue.hidden;
  }

  /// Top border or top padding separate the parent's top margin from the top
  /// margin of its first in-flow child, preventing the collapse.
  static bool blocksTopMarginCollapseWithChildren(
      Renderer renderer, double containingBlockWidth) {
    if (establishesNewBlockFormattingContext(renderer)) return true;
    if (borderWidth(renderer, Property.BORDER_TOP) > 0) return true;
    return resolveLength(renderer, Property.PADDING_TOP, containingBlockWidth) >
        0;
  }

  /// Bottom border, bottom padding or a computed height separate the parent's
  /// bottom margin from the bottom margin of its last in-flow child.
  static bool blocksBottomMarginCollapseWithChildren(
      Renderer renderer, double containingBlockWidth) {
    if (establishesNewBlockFormattingContext(renderer)) return true;
    if (borderWidth(renderer, Property.BORDER_BOTTOM) > 0) return true;
    if (resolveLength(renderer, Property.PADDING_BOTTOM, containingBlockWidth) >
        0) {
      return true;
    }
    return renderer.getOwnProperty<Object>(Property.HEIGHT) != null ||
        renderer.getOwnProperty<Object>(Property.MIN_HEIGHT) != null ||
        _modelHas(renderer, Property.HEIGHT) ||
        _modelHas(renderer, Property.MIN_HEIGHT);
  }

  static bool _modelHas(Renderer renderer, int property) {
    final model = renderer.getModelElement();
    return model != null && model.hasOwnProperty(property);
  }

  /// A box is self-collapsing when its own top and bottom margins are
  /// adjoining: no border, no padding, no computed height and no in-flow
  /// content of non-zero height.
  static bool isSelfCollapsing(Renderer renderer, double containingBlockWidth,
      {required bool hasContentHeight}) {
    if (hasContentHeight) return false;
    if (establishesNewBlockFormattingContext(renderer)) return false;
    if (borderWidth(renderer, Property.BORDER_TOP) > 0) return false;
    if (borderWidth(renderer, Property.BORDER_BOTTOM) > 0) return false;
    if (resolveLength(renderer, Property.PADDING_TOP, containingBlockWidth) >
        0) {
      return false;
    }
    if (resolveLength(renderer, Property.PADDING_BOTTOM, containingBlockWidth) >
        0) {
      return false;
    }
    return !_modelHas(renderer, Property.HEIGHT) &&
        !_modelHas(renderer, Property.MIN_HEIGHT) &&
        renderer.getOwnProperty<Object>(Property.HEIGHT) == null &&
        renderer.getOwnProperty<Object>(Property.MIN_HEIGHT) == null;
  }

  // ------------------------------------------------------------------- flow

  double get marginTop =>
      resolveLength(renderer, Property.MARGIN_TOP, containingBlockWidth);

  double get marginBottom =>
      resolveLength(renderer, Property.MARGIN_BOTTOM, containingBlockWidth);

  /// True when this block's own top margin takes part in the adjoining set
  /// shared with its first in-flow child.
  bool get topCollapsesWithChildren =>
      !blocksTopMarginCollapseWithChildren(renderer, containingBlockWidth);

  /// True when this block's own bottom margin takes part in the adjoining set
  /// shared with its last in-flow child.
  bool get bottomCollapsesWithChildren =>
      !blocksBottomMarginCollapseWithChildren(renderer, containingBlockWidth);

  /// Starts the session and returns the space to reserve above the border box
  /// of this block for its own top margin. When the top margin collapses with
  /// the children's margins the amount is not known yet, so 0 is returned and
  /// the space is reported later by [beginChild].
  double startMarginsCollapse() {
    _applied = 0;
    final ownMarginTop =
        (parentInfo?.isIgnoreOwnMarginTop() ?? false) ? 0.0 : marginTop;
    _collapseBefore.joinMargin(ownMarginTop);
    if (topCollapsesWithChildren) {
      _pending.joinMargin(ownMarginTop);
      return 0;
    }
    return ownMarginTop;
  }

  /// Joins the top margin of [child] to the adjoining set and returns the space
  /// that would be inserted before the child if it turns out not to collapse
  /// through.
  double beginChild(Renderer child) {
    if (isOutOfFlow(child)) return 0;
    _pending.joinMargin(
        resolveLength(child, Property.MARGIN_TOP, containingBlockWidth));
    final delta = _pending.getCollapsedMarginsSize() - _applied;
    return delta;
  }

  /// The child collapsed through: its bottom margin joins the same adjoining
  /// set and no space is consumed yet.
  void childCollapsedThrough(Renderer child) {
    if (isOutOfFlow(child)) return;
    _pending.joinMargin(
        resolveLength(child, Property.MARGIN_BOTTOM, containingBlockWidth));
  }

  /// The child produced a border box: the adjoining set is closed and a new one
  /// starts with the child's bottom margin.
  void commitChild(Renderer child) {
    if (isOutOfFlow(child)) return;
    _anyInFlowContent = true;
    _applied = 0;
    _pending = MarginsCollapse();
    _pending.joinMargin(
        resolveLength(child, Property.MARGIN_BOTTOM, containingBlockWidth));
  }

  /// Space to reserve below the last child for the margins that are still
  /// adjoining plus this block's own bottom margin.
  double endMarginsCollapse() {
    final ownMarginBottom =
        (parentInfo?.isIgnoreOwnMarginBottom() ?? false) ? 0.0 : marginBottom;
    final after = _pending.clone();
    double result;
    if (bottomCollapsesWithChildren) {
      after.joinMargin(ownMarginBottom);
      result = after.getCollapsedMarginsSize() - _applied;
    } else {
      result = after.getCollapsedMarginsSize() - _applied + ownMarginBottom;
    }
    _applied = 0;
    _pending = MarginsCollapse();
    return result;
  }

  bool get hasInFlowContent => _anyInFlowContent;

  /// Adjoining set touching the top edge of this block, reported to the parent.
  MarginsCollapse getCollapseBefore() => _collapseBefore;

  /// Builds the info handed down to a child renderer: in-flow children never
  /// reserve their own vertical margins, the handler does it for them.
  MarginsCollapseInfo createChildInfo(Renderer child) {
    if (isOutOfFlow(child)) {
      return MarginsCollapseInfo(
          ignoreOwnMarginTop: false, ignoreOwnMarginBottom: false);
    }
    return MarginsCollapseInfo(
        ignoreOwnMarginTop: true, ignoreOwnMarginBottom: true);
  }
}
