import 'package:pdfcraft/src/layout/layout/layout_area.dart';
import 'package:pdfcraft/src/kernel/geom/rectangle.dart';

class CraftRootLayoutArea extends CraftLayoutArea {
  CraftRootLayoutArea(int pageNumber, CraftRectangle bBox)
      : super(pageNumber, bBox);

  // Clone needs to return RootLayoutArea?
  @override
  CraftLayoutArea clone() {
    return CraftRootLayoutArea(pageNumber, bBox.clone());
  }
}
