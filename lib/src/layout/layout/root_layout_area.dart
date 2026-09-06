import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';

class RootLayoutArea extends LayoutArea {
  RootLayoutArea(int pageNumber, Rectangle bBox) : super(pageNumber, bBox);

  // Clone needs to return RootLayoutArea?
  @override
  LayoutArea clone() {
    return RootLayoutArea(pageNumber, bBox.clone());
  }
}
