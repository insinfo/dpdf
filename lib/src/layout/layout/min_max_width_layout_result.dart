import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/layout/minmaxwidth/min_max_width.dart';

class CraftMinMaxWidthLayoutResult extends CraftLayoutResult {
  CraftMinMaxWidth? minMaxWidth;

  CraftMinMaxWidthLayoutResult(int status, CraftLayoutArea? occupiedArea,
      CraftRenderer? splitRenderer, CraftRenderer? overflowRenderer,
      [CraftRenderer? causeOfNothing])
      : super(status, occupiedArea, splitRenderer, overflowRenderer,
            causeOfNothing) {
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
