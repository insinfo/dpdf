import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/margincollapse/margins_collapse_info.dart';

class LayoutContext {
  LayoutArea area;
  MarginsCollapseInfo? marginsCollapseInfo;
  List<Rectangle> floatRendererAreas = [];
  bool clippedHeight = false;

  LayoutContext(this.area,
      [this.marginsCollapseInfo,
      List<Rectangle>? floatRendererAreas,
      this.clippedHeight = false]) {
    if (floatRendererAreas != null) {
      this.floatRendererAreas = floatRendererAreas;
    }
  }

  LayoutArea getArea() {
    return area;
  }

  MarginsCollapseInfo? getMarginsCollapseInfo() {
    return marginsCollapseInfo;
  }

  List<Rectangle> getFloatRendererAreas() {
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
