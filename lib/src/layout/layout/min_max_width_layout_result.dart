import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/minmaxwidth/min_max_width.dart';

class MinMaxWidthLayoutResult extends LayoutResult {
  MinMaxWidth? minMaxWidth;

  MinMaxWidthLayoutResult(super.status, super.occupiedArea, super.splitRenderer,
      super.overflowRenderer,
      [super.causeOfNothing]) {
    minMaxWidth = MinMaxWidth();
  }

  MinMaxWidth? getMinMaxWidth() {
    return minMaxWidth;
  }

  MinMaxWidthLayoutResult setMinMaxWidth(MinMaxWidth? minMaxWidth) {
    this.minMaxWidth = minMaxWidth;
    return this;
  }
}
