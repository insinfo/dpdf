import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/minmaxwidth/min_max_width.dart';

class CraftMinMaxWidthLayoutResult extends CraftLayoutResult {
  CraftMinMaxWidth? minMaxWidth;

  CraftMinMaxWidthLayoutResult(super.status, super.occupiedArea,
      super.splitRenderer, super.overflowRenderer,
      [super.causeOfNothing]) {
    minMaxWidth = CraftMinMaxWidth();
  }

  CraftMinMaxWidth? getMinMaxWidth() {
    return minMaxWidth;
  }

  CraftMinMaxWidthLayoutResult setMinMaxWidth(CraftMinMaxWidth? minMaxWidth) {
    this.minMaxWidth = minMaxWidth;
    return this;
  }
}
