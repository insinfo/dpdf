import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/renderer/i_renderer.dart';
import 'package:dpdf/src/layout/element/area_break.dart';

class LayoutResult {
  static const int FULL = 1;
  static const int PARTIAL = 2;
  static const int NOTHING = 3;

  int status;
  LayoutArea? occupiedArea;
  IRenderer? splitRenderer;
  IRenderer? overflowRenderer;
  AreaBreak? areaBreak;
  IRenderer? causeOfNothing;

  LayoutResult(
      this.status, this.occupiedArea, this.splitRenderer, this.overflowRenderer,
      [this.causeOfNothing]);

  int getStatus() {
    return status;
  }

  void setStatus(int status) {
    this.status = status;
  }

  LayoutArea? getOccupiedArea() {
    return occupiedArea;
  }

  IRenderer? getSplitRenderer() {
    return splitRenderer;
  }

  void setSplitRenderer(IRenderer splitRenderer) {
    this.splitRenderer = splitRenderer;
  }

  IRenderer? getOverflowRenderer() {
    return overflowRenderer;
  }

  void setOverflowRenderer(IRenderer overflowRenderer) {
    this.overflowRenderer = overflowRenderer;
  }

  AreaBreak? getAreaBreak() {
    return areaBreak;
  }

  LayoutResult setAreaBreak(AreaBreak areaBreak) {
    this.areaBreak = areaBreak;
    return this;
  }

  IRenderer? getCauseOfNothing() {
    return causeOfNothing;
  }

  @override
  String toString() {
    String statusStr;
    switch (getStatus()) {
      case FULL:
        statusStr = "Full";
        break;
      case NOTHING:
        statusStr = "Nothing";
        break;
      case PARTIAL:
        statusStr = "Partial";
        break;
      default:
        statusStr = "None";
        break;
    }
    return "LayoutResult{$statusStr, areaBreak=$areaBreak, occupiedArea=$occupiedArea}";
  }
}
