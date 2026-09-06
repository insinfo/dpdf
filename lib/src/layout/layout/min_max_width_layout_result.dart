import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/renderer/i_renderer.dart';
import 'package:dpdf/src/layout/minmaxwidth/min_max_width.dart';

class MinMaxWidthLayoutResult extends LayoutResult {
  MinMaxWidth? minMaxWidth;

  MinMaxWidthLayoutResult(int status, LayoutArea? occupiedArea,
      IRenderer? splitRenderer, IRenderer? overflowRenderer,
      [IRenderer? causeOfNothing])
      : super(status, occupiedArea, splitRenderer, overflowRenderer,
            causeOfNothing) {
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
