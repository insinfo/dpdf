import 'package:dpdf/src/layout/layout/layout_area.dart';

class RootLayoutArea extends LayoutArea {
  RootLayoutArea(super.pageNumber, super.bBox);

  // Clone needs to return RootLayoutArea?
  @override
  LayoutArea clone() {
    return RootLayoutArea(pageNumber, bBox.clone());
  }
}
