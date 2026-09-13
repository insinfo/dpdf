/// Margin collapsing model described by CSS 2.1, section 8.3.1.
///
/// A set of margins is said to be *adjoining* when no line boxes, clearance,
/// padding or border separate them. The collapsed size of such a set is the
/// largest of the positive margins plus the smallest (most negative) of the
/// negative margins.
class MarginsCollapse {
  double _maxPositive = 0;
  double _minNegative = 0;
  bool _empty = true;

  MarginsCollapse();

  /// Adds one more margin to the adjoining set.
  void joinMargin(double margin) {
    _empty = false;
    if (margin >= 0) {
      if (margin > _maxPositive) {
        _maxPositive = margin;
      }
    } else {
      if (margin < _minNegative) {
        _minNegative = margin;
      }
    }
  }

  /// Merges another adjoining set into this one.
  void joinMarginCollapse(MarginsCollapse other) {
    if (other._empty) return;
    joinMargin(other._maxPositive);
    joinMargin(other._minNegative);
  }

  /// CSS 2.1, 8.3.1: "the maximum of the positive adjoining margins plus the
  /// minimum of the negative adjoining margins".
  double getCollapsedMarginsSize() => _maxPositive + _minNegative;

  /// True while no margin has been joined yet.
  bool isEmpty() => _empty;

  double getMaxPositive() => _maxPositive;

  double getMinNegative() => _minNegative;

  MarginsCollapse clone() {
    final copy = MarginsCollapse();
    copy._maxPositive = _maxPositive;
    copy._minNegative = _minNegative;
    copy._empty = _empty;
    return copy;
  }

  @override
  String toString() =>
      'MarginsCollapse{+$_maxPositive, $_minNegative => ${getCollapsedMarginsSize()}}';
}

/// State passed from a parent renderer down to a child renderer so that
/// adjoining margins of the two are collapsed exactly once.
///
/// When [ignoreOwnMarginTop] (respectively [ignoreOwnMarginBottom]) is set, the
/// child must not reserve its own top (bottom) margin: the ancestor which owns
/// the adjoining set already accounted for it.
class MarginsCollapseInfo {
  bool ignoreOwnMarginTop;
  bool ignoreOwnMarginBottom;

  /// Margins adjoining the top edge of the box.
  MarginsCollapse collapseBefore;

  /// Margins adjoining the bottom edge of the box.
  MarginsCollapse collapseAfter;

  /// Set of margins the box itself contributes after its content, kept apart
  /// from [collapseAfter] while it is still unknown whether the box collapses
  /// through.
  MarginsCollapse? ownCollapseAfter;

  /// True when the top and the bottom margins of the box are adjoining, i.e.
  /// the box has no border, no padding, no line boxes and no computed height.
  bool isSelfCollapsing;

  /// Space kept available on top/bottom of the layout area for margins which
  /// may still grow while the children are laid out.
  double bufferSpaceOnTop;
  double bufferSpaceOnBottom;
  double usedBufferSpaceOnTop;
  double usedBufferSpaceOnBottom;

  /// CSS 2.1, 8.3.1: clearance introduced between a float and a following box
  /// prevents its margins from collapsing with the ones of the parent.
  bool clearanceApplied;

  MarginsCollapseInfo({
    this.ignoreOwnMarginTop = false,
    this.ignoreOwnMarginBottom = false,
    MarginsCollapse? collapseBefore,
    MarginsCollapse? collapseAfter,
    this.ownCollapseAfter,
    this.isSelfCollapsing = true,
    this.bufferSpaceOnTop = 0,
    this.bufferSpaceOnBottom = 0,
    this.usedBufferSpaceOnTop = 0,
    this.usedBufferSpaceOnBottom = 0,
    this.clearanceApplied = false,
  })  : collapseBefore = collapseBefore ?? MarginsCollapse(),
        collapseAfter = collapseAfter ?? MarginsCollapse();

  bool isIgnoreOwnMarginTop() => ignoreOwnMarginTop;

  bool isIgnoreOwnMarginBottom() => ignoreOwnMarginBottom;

  MarginsCollapse getCollapseBefore() => collapseBefore;

  MarginsCollapse getCollapseAfter() => collapseAfter;

  MarginsCollapse? getOwnCollapseAfter() => ownCollapseAfter;

  void setOwnCollapseAfter(MarginsCollapse? marginsCollapse) {
    ownCollapseAfter = marginsCollapse;
  }

  bool isClearanceApplied() => clearanceApplied;

  void setClearanceApplied(bool clearanceApplied) {
    this.clearanceApplied = clearanceApplied;
  }

  MarginsCollapseInfo clone() {
    return MarginsCollapseInfo(
      ignoreOwnMarginTop: ignoreOwnMarginTop,
      ignoreOwnMarginBottom: ignoreOwnMarginBottom,
      collapseBefore: collapseBefore.clone(),
      collapseAfter: collapseAfter.clone(),
      ownCollapseAfter: ownCollapseAfter?.clone(),
      isSelfCollapsing: isSelfCollapsing,
      bufferSpaceOnTop: bufferSpaceOnTop,
      bufferSpaceOnBottom: bufferSpaceOnBottom,
      usedBufferSpaceOnTop: usedBufferSpaceOnTop,
      usedBufferSpaceOnBottom: usedBufferSpaceOnBottom,
      clearanceApplied: clearanceApplied,
    );
  }

  /// Copies the mutable state of [from] into [to], keeping object identity so
  /// that a renderer which kept a reference still observes the update.
  static void copy(MarginsCollapseInfo from, MarginsCollapseInfo to) {
    to.ignoreOwnMarginTop = from.ignoreOwnMarginTop;
    to.ignoreOwnMarginBottom = from.ignoreOwnMarginBottom;
    to.collapseBefore = from.collapseBefore;
    to.collapseAfter = from.collapseAfter;
    to.ownCollapseAfter = from.ownCollapseAfter;
    to.isSelfCollapsing = from.isSelfCollapsing;
    to.bufferSpaceOnTop = from.bufferSpaceOnTop;
    to.bufferSpaceOnBottom = from.bufferSpaceOnBottom;
    to.usedBufferSpaceOnTop = from.usedBufferSpaceOnTop;
    to.usedBufferSpaceOnBottom = from.usedBufferSpaceOnBottom;
    to.clearanceApplied = from.clearanceApplied;
  }

  @override
  String toString() => 'MarginsCollapseInfo{before=$collapseBefore, '
      'after=$collapseAfter, selfCollapsing=$isSelfCollapsing}';
}
