import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/layout/element/area_break.dart';

class CraftLayoutResult {
  static const int FULL = 1;
  static const int PARTIAL = 2;
  static const int NOTHING = 3;

  int status;
  CraftLayoutArea? occupiedArea;
  CraftRenderer? splitRenderer;
  CraftRenderer? overflowRenderer;
  CraftAreaBreak? areaBreak;
  CraftRenderer? causeOfNothing;

  CraftLayoutResult(
      this.status, this.occupiedArea, this.splitRenderer, this.overflowRenderer,
      [this.causeOfNothing]);

  int getStatus() {
    return status;
  }

  void setStatus(int status) {
    this.status = status;
  }

  CraftLayoutArea? getOccupiedArea() {
    return occupiedArea;
  }

  CraftRenderer? getSplitRenderer() {
    return splitRenderer;
  }

  void setSplitRenderer(CraftRenderer splitRenderer) {
    this.splitRenderer = splitRenderer;
  }

  CraftRenderer? getOverflowRenderer() {
    return overflowRenderer;
  }

  void setOverflowRenderer(CraftRenderer overflowRenderer) {
    this.overflowRenderer = overflowRenderer;
  }

  CraftAreaBreak? getAreaBreak() {
    return areaBreak;
  }

  CraftLayoutResult setAreaBreak(CraftAreaBreak areaBreak) {
    this.areaBreak = areaBreak;
    return this;
  }

  CraftRenderer? getCauseOfNothing() {
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
