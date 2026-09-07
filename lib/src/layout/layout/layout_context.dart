import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/margincollapse/margins_collapse_info.dart';

class CraftLayoutContext {
  CraftLayoutArea area;
  CraftMarginsCollapseInfo? marginsCollapseInfo;
  List<CraftRectangle> floatRendererAreas = [];
  bool clippedHeight = false;

  CraftLayoutContext(this.area,
      [this.marginsCollapseInfo,
      List<CraftRectangle>? floatRendererAreas,
      this.clippedHeight = false]) {
    if (floatRendererAreas != null) {
      this.floatRendererAreas = floatRendererAreas;
    }
  }

  CraftLayoutArea getArea() {
    return area;
  }

  CraftMarginsCollapseInfo? getMarginsCollapseInfo() {
    return marginsCollapseInfo;
  }

  List<CraftRectangle> getFloatRendererAreas() {
    return floatRendererAreas;
  }

  bool isClippedHeight() {
    return clippedHeight;
  }

  void setClippedHeight(bool clippedHeight) {
    this.clippedHeight = clippedHeight;
  }

  @override
  String toString() {
    return area.toString();
  }
}
